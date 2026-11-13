//
//  CreditsView.swift
//  LiDARScanner
//
//  Created for the RIM Project (Roman Infrastructure Mapping).
//

import SwiftUI

struct CreditsView: View {
    @Environment(\.openURL) private var openURL
    private let mint = Color(red: 0.38, green: 0.93, blue: 0.76)

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "4"
        return String.localizedStringWithFormat(NSLocalizedString("Version %@ (Build %@)", comment: ""), version, build)
    }

    var body: some View {
        List {
            // App Header
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "point.3.filled.connected.3d")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(mint)
                        .padding(.top, 8)

                    Text("LiDAR-Scanner")
                        .font(.title2.bold())

                    Text(appVersionString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("Native on-device 3D LiDAR & Gaussian Splatting for field archaeology and surveying.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Research Project: RIM
            Section("Research Project") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 14) {
                        Image("LogoRIM")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                            .padding(4)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("RIM Project")
                                .font(.headline)
                            Text("Roman Infrastructure Mapping")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("IP-2025-02-1060 · 2025–2028")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Tracing the Empire’s Territorial Remnants and Infrastructural Systems in Pannonia: Roman Infrastructure Mapping.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link(destination: URL(string: "https://rim.iarh.hr/index.php/en")!) {
                        Label("Visit Project Website (rim.iarh.hr)", systemImage: "arrow.up.right.square")
                            .font(.caption.weight(.medium))
                    }
                }
                .padding(.vertical, 4)
            }

            // Institutional Host & Funding
            Section("Host Institution & Funding") {
                HStack(alignment: .center, spacing: 14) {
                    Image("LogoIARH")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .padding(4)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Institut za arheologiju (IARH)")
                            .font(.subheadline.weight(.semibold))
                        Text("Institute of Archaeology, Zagreb")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://www.iarh.hr/en/home/")!) {
                            Text("iarh.hr").font(.caption2)
                        }
                    }
                }
                .padding(.vertical, 2)

                HStack(alignment: .center, spacing: 14) {
                    Image("LogoHRZZ")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 32)
                        .padding(4)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hrvatska zaklada za znanost (HRZZ)")
                            .font(.subheadline.weight(.semibold))
                        Text("Croatian Science Foundation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://hrzz.hr/en/")!) {
                            Text("hrzz.hr").font(.caption2)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // Authors & Scientific Direction
            Section("Author & Scientific Direction") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dominik Hagmann")
                        .font(.headline)
                    Text("University of Vienna / Institute of Archaeology (IARH), Zagreb")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)

                Link(destination: URL(string: "https://github.com/Dominik-Hagmann/lidar-scanner-ios")!) {
                    Label("Source Code on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            // Open Source Technologies
            Section("Open Source & Architecture") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MetalSplatter & SplatIO")
                        .font(.subheadline.weight(.medium))
                    Text("Metal-accelerated 3D Gaussian splat rendering by scier.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("msplat-ios")
                        .font(.subheadline.weight(.medium))
                    Text("On-device 3D Gaussian Splatting engine by frs0n.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple ARKit & Metal")
                        .font(.subheadline.weight(.medium))
                    Text("Hardware-accelerated LiDAR scene depth capture and high-performance GPU compute.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // AI Collaboration
            Section("AI-Assisted Development") {
                Text("This application was developed through an AI-assisted workflow with Google Antigravity and OpenAI Codex / ChatGPT.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // License
            Section {
                Text("Released under the MIT License.\nFree and open-source software.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("About & Credits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CreditsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CreditsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
