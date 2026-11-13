# Changelog

## Unreleased

- Added point-to-point distance measurement tool (`Measure` mode) in the 3D point cloud preview (`OrbitCloudView` / `CloudPreviewSheet`).
- Added Ground Control Points (GCPs / Passpunkte): 3D point picking, reference coordinate/CRS/notes editor, live 3D markers, `metadata.json` persistence, `gcps.csv` export, and GCP table in PDF reports.
- Added GNSS georeferencing metadata (`LocationService`, WGS84 coordinates, altitude, horizontal/vertical accuracy, heading) with offline recording toggle in Settings and output in `metadata.json` and PDF reports.
- Added point-cloud export and import support for **CSV** (`points.csv`) plus binary **ASPRS LAS** (`points.las`), compressed **LAZ** (`points.laz`, LASzip v2), and **ASTM E57** (`points.e57`).
- Added ARKit `ARMeshAnchor` surface reconstruction capture and Wavefront **OBJ** (`mesh.obj`) export and sharing.

## 1.2.0 (Build 4) – 2026-09-26

- Added a separate Gaussian mode with local Metal training, saved capture data, progress, checkpoints and native viewing.
- Added optional narrative PDF reports, processing logs and reusable capture exports.
- Raised the deployment target to iOS/iPadOS 18 for the native Gaussian libraries.
- Retained the point-cloud core and export formats; added report export and safe mode switching.

## 1.1.0 (Build 3) – 2026-09-26

- Added English and German interfaces, with English as the default.
- Set version 1.1.0 (Build 3) and aligned the export and citation identifiers.

## 1.0.0 (Build 2)

- LiDAR point-cloud capture, binary/ASCII PLY and XYZ export, and JSON metadata.
