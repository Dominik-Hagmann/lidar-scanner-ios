"""Small, audited integration patches on the pinned upstream source.

Make I/O errors observable to the app and use Metal 3.1 (iOS 18 compatible).
Expose the chosen camera and effective resolution for each recorded step.
No reconstruction/optimization algorithm is changed.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1])
p = root / 'CMakeLists.txt'
s = p.read_text().replace('"metal4.0" CACHE', '"metal3.1" CACHE')
p.write_text(s)
for name in ['core/src/loaders/save_gaussians.cpp', 'core/src/model.cpp']:
    p = root / name
    s = p.read_text()
    for declaration, variable in [('std::ofstream o(path, std::ios::binary);', 'o'),
                                   ('std::ofstream f(filename, std::ios::binary);', 'f'),
                                   ('std::ifstream f(filename, std::ios::binary);', 'f')]:
        marker = declaration + f'\n    {variable}.exceptions(std::ios::failbit | std::ios::badbit);'
        if marker not in s:
            s = s.replace(declaration, marker)
    p.write_text(s)

for name, marker in [('core/include/msplat_api.hpp', '    float msPerStep = 0.0f;'),
                     ('core/include/msplat_c_api.h', '    float msPerStep;')]:
    p = root / name
    s = p.read_text()
    if 'int cameraIndex;' not in s:
        assert marker in s
        s = s.replace(marker, marker + '\n    int cameraIndex;\n    int imageWidth;\n    int imageHeight;')
    p.write_text(s)
p = root / 'core/src/msplat_api.mm'
s = p.read_text()
if 's.cameraIndex = ' not in s:
    s = s.replace('    s.msPerStep = ms;', '    s.msPerStep = ms;\n    s.cameraIndex = (int)impl->ds->trainIndices[camIdx];\n    s.imageWidth = cam.width / ds;\n    s.imageHeight = cam.height / ds;')
    s = s.replace('MsplatStats{stats.iteration, stats.splatCount, stats.msPerStep}',
                  'MsplatStats{stats.iteration, stats.splatCount, stats.msPerStep, stats.cameraIndex, stats.imageWidth, stats.imageHeight}')
p.write_text(s)
