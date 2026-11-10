# Roadmap & Improvement Proposals

This document outlines potential future enhancements for **LiDAR Scanner**, focusing on archaeological field documentation, data quality, GIS interoperability, and on-device processing.

---

## 1. Georeferencing & Field Survey (GNSS)

Currently, the application records scans strictly within ARKit's local metric coordinate space (origin at the session start position). Real-world coordinates (WGS84 / EPSG) are not yet captured.

### Planned Enhancements:
- **GNSS Metadata Acquisition (`CoreLocation`):**
  - Record latitude, longitude, ellipsoidal/orthometric altitude, horizontal accuracy, vertical accuracy, and true-north heading at scan start and scan end.
  - Integrate GNSS metadata into `metadata.json` (`ScanMetadata`) and the narrative PDF report (`ScanReport.swift`).
  - Add optional location privacy toggle in the settings.
- **Ground Control Points (GCPs) & Scaling:**
  - Feature to tag reference markers (targets) in the point cloud or Gaussian preview.
  - Manual entry of known coordinates (e.g., from an external RTK-GNSS or total station) for exact affine transformation / georeferencing in external GIS.
- **In-App Distance Measurement:**
  - Two-point measurement tool in the 3D preview sheet to verify physical scale (e.g., against a folding rule or photo scale) directly on site.

---

## 2. Capture Quality & Camera Controls

Environmental conditions during outdoor and trench surveys fluctuate rapidly, affecting texture and splat quality.

### Planned Enhancements:
- **AE / AF & White-Balance Lock:**
  - Add an exposure, focus, and white-balance lock toggle to prevent banding, inconsistent lighting, and colour shifts across different angles of the same surface.
- **Torch / Illumination Control:**
  - Integrated LED torch control with adjustable intensity for scanning shaded niches, trenches, tombs, and dark interior spaces.
- **Edge-Bleed / Flying-Pixel Filtering:**
  - Implement depth-discontinuity and gradient filtering in `PointCloudCore.cpp` to reject mixed-pixel/flying-pixel artefacts at depth edges (e.g., silhouettes, stone edges).

---

## 3. Data Formats & Interoperability

While binary/ASCII PLY, XYZ, and Gaussian PLY are supported, heritage and surveying workflows rely on standard GIS and exchange formats.

### Planned Enhancements:
- **ASTM E57 Export:**
  - Industry standard for terrestrial 3D laser scans, natively compatible with CloudCompare, Leica Cyclone, RealityCapture, and Agisoft Metashape.
- **LAS / LAZ (ASPRS) Export:**
  - Standard format for geospatial LiDAR data, with CRS/projection header support for GIS software (QGIS, ArcGIS).
- **Surface Normals:**
  - Estimate and export vertex normals in PLY/XYZ files for realistic shading and improved surface reconstruction in downstream 3D software.

---

## 4. Surface Reconstruction (Meshing)

- **Real-Time Mesh Generation:**
  - Evaluate Apple's native `ARMeshAnchor` (`sceneReconstruction = .meshWithClassification`) to provide an instant, textured 3D mesh (OBJ / USDZ) alongside the raw point cloud.
- **Offline Mesh Processing:**
  - Lightweight on-device Poisson Surface Reconstruction or Ball-Pivoting for closing point clouds into water-tight models.

---

## 5. Gaussian Splatting Enhancements

- **Splat Pruning & Optimization:**
  - Automated post-training culling of low-opacity and oversized Gaussians to reduce file sizes.
- **Thermal & Battery Profiling:**
  - Adaptive iteration limits or training pause intervals when device temperature rises, avoiding iOS thermal throttling.
