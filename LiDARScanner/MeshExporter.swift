import Foundation
import ARKit
import SceneKit
import simd

struct MeshPreviewData: Sendable, Equatable {
    let vertices: [SIMD3<Float>]
    let indices: [UInt32]

    var isEmpty: Bool { vertices.isEmpty || indices.count < 3 }
    var triangleCount: Int { indices.count / 3 }

    static func fromAnchors(_ anchors: [ARMeshAnchor]) -> MeshPreviewData {
        var worldVertices: [SIMD3<Float>] = []
        var triangleIndices: [UInt32] = []

        for anchor in anchors {
            let geometry = anchor.geometry
            let verts = geometry.vertices
            let faces = geometry.faces
            guard verts.count > 0, faces.count > 0, faces.primitiveType == .triangle else { continue }

            let baseVertexIndex = UInt32(worldVertices.count)
            let vPtr = verts.buffer.contents().advanced(by: verts.offset)
            let vStride = verts.stride
            let transform = anchor.transform

            worldVertices.reserveCapacity(worldVertices.count + verts.count)
            for i in 0..<verts.count {
                let local = vPtr.advanced(by: i * vStride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let world = simd_mul(transform, simd_float4(local.x, local.y, local.z, 1.0))
                worldVertices.append(SIMD3<Float>(world.x, world.y, world.z))
            }

            let fPtr = faces.buffer.contents()
            let bytesPerIndex = faces.bytesPerIndex
            triangleIndices.reserveCapacity(triangleIndices.count + faces.count * 3)
            if bytesPerIndex == 2 {
                let idxPtr = fPtr.assumingMemoryBound(to: UInt16.self)
                for f in 0..<faces.count {
                    triangleIndices.append(baseVertexIndex + UInt32(idxPtr[f * 3]))
                    triangleIndices.append(baseVertexIndex + UInt32(idxPtr[f * 3 + 1]))
                    triangleIndices.append(baseVertexIndex + UInt32(idxPtr[f * 3 + 2]))
                }
            } else if bytesPerIndex == 4 {
                let idxPtr = fPtr.assumingMemoryBound(to: UInt32.self)
                for f in 0..<faces.count {
                    triangleIndices.append(baseVertexIndex + idxPtr[f * 3])
                    triangleIndices.append(baseVertexIndex + idxPtr[f * 3 + 1])
                    triangleIndices.append(baseVertexIndex + idxPtr[f * 3 + 2])
                }
            }
        }
        return MeshPreviewData(vertices: worldVertices, indices: triangleIndices)
    }

    static func fromOBJ(url: URL) -> MeshPreviewData? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

        content.enumerateLines { rawLine, _ in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { return }
            if line.hasPrefix("v ") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 4,
                      let x = Float(parts[1]),
                      let y = Float(parts[2]),
                      let z = Float(parts[3]),
                      x.isFinite, y.isFinite, z.isFinite else { return }
                // Inverse of OBJ Z-up (x, -z, y) back into ARKit Y-up coordinates
                vertices.append(SIMD3<Float>(x, z, -y))
            } else if line.hasPrefix("f ") {
                let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard parts.count >= 4 else { return }
                var faceVerts: [UInt32] = []
                faceVerts.reserveCapacity(parts.count - 1)
                let vertexCount = vertices.count
                for token in parts.dropFirst() {
                    let firstComp = token.split(separator: "/", omittingEmptySubsequences: false).first ?? token
                    guard let rawIdx = Int(firstComp) else { continue }
                    let resolved = rawIdx > 0 ? (rawIdx - 1) : (vertexCount + rawIdx)
                    if resolved >= 0, resolved < vertexCount {
                        faceVerts.append(UInt32(resolved))
                    }
                }
                guard faceVerts.count >= 3 else { return }
                for i in 1..<(faceVerts.count - 1) {
                    indices.append(faceVerts[0])
                    indices.append(faceVerts[i])
                    indices.append(faceVerts[i + 1])
                }
            }
        }
        let mesh = MeshPreviewData(vertices: vertices, indices: indices)
        return mesh.isEmpty ? nil : mesh
    }
}

enum MeshGeometry {
    static let liveWireframeColor = UIColor(red: 0.35, green: 0.90, blue: 0.98, alpha: 0.80)
    static let previewWireframeColor = UIColor(red: 0.35, green: 0.90, blue: 0.98, alpha: 0.55)
    static let previewSurfaceColor = UIColor(red: 0.62, green: 0.86, blue: 0.92, alpha: 0.94)

    static func makeWireframeGeometry(from anchor: ARMeshAnchor, color: UIColor = liveWireframeColor) -> SCNGeometry? {
        let geometry = anchor.geometry
        let verts = geometry.vertices
        let faces = geometry.faces
        guard verts.count > 0, faces.count > 0, faces.primitiveType == .triangle else { return nil }

        let vPtr = verts.buffer.contents().advanced(by: verts.offset)
        let vStride = verts.stride
        var flatVertices: [Float] = []
        flatVertices.reserveCapacity(verts.count * 3)
        for i in 0..<verts.count {
            let v = vPtr.advanced(by: i * vStride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            flatVertices.append(v.x)
            flatVertices.append(v.y)
            flatVertices.append(v.z)
        }

        let fPtr = faces.buffer.contents()
        let indexCount = faces.count * 3
        let indexData: Data
        if faces.bytesPerIndex == 2 {
            indexData = Data(bytes: fPtr, count: indexCount * MemoryLayout<UInt16>.size)
        } else {
            indexData = Data(bytes: fPtr, count: indexCount * MemoryLayout<UInt32>.size)
        }

        let vertexSource = SCNGeometrySource(
            data: flatVertices.withUnsafeBytes { Data($0) },
            semantic: .vertex,
            vectorCount: verts.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: 4,
            dataOffset: 0,
            dataStride: 12
        )
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex
        )
        let scn = SCNGeometry(sources: [vertexSource], elements: [element])
        let mat = SCNMaterial()
        mat.lightingModel = .constant
        mat.fillMode = .lines
        mat.diffuse.contents = color
        mat.isDoubleSided = true
        scn.materials = [mat]
        return scn
    }

    static func makeSCNGeometry(from mesh: MeshPreviewData, wireframe: Bool, color: UIColor) -> SCNGeometry? {
        guard !mesh.isEmpty else { return nil }
        var flatVertices: [Float] = []
        flatVertices.reserveCapacity(mesh.vertices.count * 3)
        for v in mesh.vertices {
            flatVertices.append(v.x)
            flatVertices.append(v.y)
            flatVertices.append(v.z)
        }
        let vertexSource = SCNGeometrySource(
            data: flatVertices.withUnsafeBytes { Data($0) },
            semantic: .vertex,
            vectorCount: mesh.vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: 4,
            dataOffset: 0,
            dataStride: 12
        )

        var sources = [vertexSource]
        if !wireframe {
            var normals = [SIMD3<Float>](repeating: .zero, count: mesh.vertices.count)
            let triCount = mesh.indices.count / 3
            for t in 0..<triCount {
                let i0 = Int(mesh.indices[t * 3])
                let i1 = Int(mesh.indices[t * 3 + 1])
                let i2 = Int(mesh.indices[t * 3 + 2])
                guard i0 < mesh.vertices.count, i1 < mesh.vertices.count, i2 < mesh.vertices.count else { continue }
                let e1 = mesh.vertices[i1] - mesh.vertices[i0]
                let e2 = mesh.vertices[i2] - mesh.vertices[i0]
                let fn = simd_cross(e1, e2)
                normals[i0] += fn
                normals[i1] += fn
                normals[i2] += fn
            }
            var flatNormals: [Float] = []
            flatNormals.reserveCapacity(normals.count * 3)
            for n in normals {
                let len = simd_length(n)
                let unit = len > 1e-6 ? (n / len) : SIMD3<Float>(0, 1, 0)
                flatNormals.append(unit.x)
                flatNormals.append(unit.y)
                flatNormals.append(unit.z)
            }
            let normalSource = SCNGeometrySource(
                data: flatNormals.withUnsafeBytes { Data($0) },
                semantic: .normal,
                vectorCount: mesh.vertices.count,
                usesFloatComponents: true,
                componentsPerVector: 3,
                bytesPerComponent: 4,
                dataOffset: 0,
                dataStride: 12
            )
            sources.append(normalSource)
        }

        let element = SCNGeometryElement(
            data: mesh.indices.withUnsafeBytes { Data($0) },
            primitiveType: .triangles,
            primitiveCount: mesh.triangleCount,
            bytesPerIndex: 4
        )
        let scn = SCNGeometry(sources: sources, elements: [element])
        let mat = SCNMaterial()
        if wireframe {
            mat.lightingModel = .constant
            mat.fillMode = .lines
            mat.diffuse.contents = color
            mat.writesToDepthBuffer = false
        } else {
            mat.lightingModel = .lambert
            mat.fillMode = .fill
            mat.diffuse.contents = color
        }
        mat.isDoubleSided = true
        scn.materials = [mat]
        return scn
    }
}

enum MeshExporter {
    static func writeOBJ(anchors: [ARMeshAnchor], to url: URL) throws {
        guard !anchors.isEmpty else { return }
        let tempURL = url.appendingPathExtension("partial")
        FileManager.default.createFile(atPath: tempURL.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: tempURL) else {
            throw ScanFailure.message(L("Could not create export file."))
        }
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: tempURL)
        }

        let posix = Locale(identifier: "en_US_POSIX")
        let header = "# Wavefront OBJ generated by LiDAR-Scanner\n# Units: metres, right-handed Z-up\n"
        if let data = header.data(using: .utf8) { try handle.write(contentsOf: data) }

        var vertexOffset = 1

        for anchor in anchors {
            let geometry = anchor.geometry
            let transform = anchor.transform
            let vertices = geometry.vertices
            let faces = geometry.faces

            let vertexBuffer = vertices.buffer.contents().advanced(by: vertices.offset)
            let vertexStride = vertices.stride

            var chunk = ""
            chunk.reserveCapacity(vertices.count * 32)

            for i in 0..<vertices.count {
                let vertexPtr = vertexBuffer.advanced(by: i * vertexStride).assumingMemoryBound(to: SIMD3<Float>.self)
                let v = vertexPtr.pointee
                let local4 = simd_float4(v.x, v.y, v.z, 1.0)
                let world4 = simd_mul(transform, local4)
                // Convert ARKit Y-up (x, y, z) to right-handed Z-up (x, -z, y) matching PLY/LAS/LAZ/E57/CSV/XYZ exports.
                chunk += String(format: "v %.4f %.4f %.4f\n", locale: posix, world4.x, -world4.z, world4.y)
            }
            if let data = chunk.data(using: .utf8) { try handle.write(contentsOf: data) }

            chunk = ""
            chunk.reserveCapacity(faces.count * 20)
            let faceBuffer = faces.buffer.contents()
            let bytesPerIndex = faces.bytesPerIndex

            for f in 0..<faces.count {
                if faces.primitiveType == .triangle {
                    let idx0: Int
                    let idx1: Int
                    let idx2: Int
                    if bytesPerIndex == 2 {
                        let ptr = faceBuffer.assumingMemoryBound(to: UInt16.self)
                        idx0 = Int(ptr[f * 3]) + vertexOffset
                        idx1 = Int(ptr[f * 3 + 1]) + vertexOffset
                        idx2 = Int(ptr[f * 3 + 2]) + vertexOffset
                    } else {
                        let ptr = faceBuffer.assumingMemoryBound(to: UInt32.self)
                        idx0 = Int(ptr[f * 3]) + vertexOffset
                        idx1 = Int(ptr[f * 3 + 1]) + vertexOffset
                        idx2 = Int(ptr[f * 3 + 2]) + vertexOffset
                    }
                    chunk += "f \(idx0) \(idx1) \(idx2)\n"
                }
            }
            if let data = chunk.data(using: .utf8) { try handle.write(contentsOf: data) }
            vertexOffset += vertices.count
        }

        try handle.synchronize()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: tempURL, to: url)
    }
}
