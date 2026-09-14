import SwiftUI

struct ScannerScreen: View {
    @StateObject private var scanner = LiDARScanner()

    var body: some View {
        VStack(spacing: 0) {
            ARViewContainer(scanner: scanner)
                .ignoresSafeArea(edges: .horizontal)
                .overlay(alignment: .topLeading) {
                    statusOverlay
                        .padding()
                }

            controls
                .padding()
                .background(.regularMaterial)
        }
    }

    private var statusOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scanner.statusText)
                .font(.headline)
            Text("\(scanner.pointCount.formatted()) points")
                .monospacedDigit()
            Text(ByteCountFormatter.string(fromByteCount: scanner.rawByteCount, countStyle: .file))
                .monospacedDigit()
        }
        .font(.caption)
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Picker("Density", selection: $scanner.density) {
                ForEach(CaptureDensity.allCases) { density in
                    Text(density.title).tag(density)
                }
            }
            .pickerStyle(.segmented)
            .disabled(scanner.isScanning || scanner.isFinalizing)

            HStack(spacing: 12) {
                if scanner.isScanning {
                    Button(role: .destructive, action: scanner.stopScan) {
                        Label("Stop Scan", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(action: scanner.startNewScan) {
                        Label("Start Scan", systemImage: "record.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scanner.isFinalizing)

                    Button(action: scanner.exportPLY) {
                        Label("Export PLY", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(scanner.pointCount == 0 || scanner.isFinalizing)
                }
            }

            if let url = scanner.exportedURL {
                ShareLink(item: url) {
                    Label("Share \(url.lastPathComponent)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
