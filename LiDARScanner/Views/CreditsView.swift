//
//  CreditsView.swift
//  LiDARScanner
//
//  Created for the RIM Project (Roman Infrastructure Mapping).
//

import SwiftUI

struct CreditsView: View {
    @ObservedObject private var language = LanguageManager.shared
    private let mint = Color(red: 0.38, green: 0.93, blue: 0.76)

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.3.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "5"
        return LanguageManager.format("Version %@ (Build %@)", version, build)
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

                    Text(L("LiDAR Scanner App for iPhone and iPad"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(appVersionString)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(L("Native on-device 3D LiDAR & Gaussian Splatting for field archaeology and surveying."))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            // Author
            Section(L("Author")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dominik Hagmann")
                        .font(.headline)
                    Link(destination: URL(string: "https://orcid.org/0000-0003-4905-2678")!) {
                        Text("ORCID: 0000-0003-4905-2678")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 2)

                Link(destination: URL(string: "https://github.com/Dominik-Hagmann/lidar-scanner-ios")!) {
                    Label(L("Source Code on GitHub"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }

            // Open Source Technologies
            Section(L("Open Source & Architecture")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MetalSplatter & SplatIO")
                        .font(.subheadline.weight(.medium))
                    Text(L("Metal-accelerated 3D Gaussian splat rendering by scier."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("msplat-ios")
                        .font(.subheadline.weight(.medium))
                    Text(L("On-device 3D Gaussian Splatting engine by frs0n."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Apple ARKit & Metal"))
                        .font(.subheadline.weight(.medium))
                    Text(L("Hardware-accelerated LiDAR scene depth capture and high-performance GPU compute."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // AI Collaboration
            Section(L("AI-Assisted Development")) {
                Text(L("This application was developed through an AI-assisted workflow with Google Antigravity and OpenAI Codex / ChatGPT."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Acknowledgments
            Section(L("Acknowledgments")) {
                HStack(alignment: .center, spacing: 14) {
                    Image("LogoRIM")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .padding(4)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("RIM Project"))
                            .font(.subheadline.weight(.semibold))
                        Text(L("Roman Infrastructure Mapping"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://rim.iarh.hr/index.php/en")!) {
                            Text("rim.iarh.hr").font(.caption2)
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
                        Text(L("Hrvatska zaklada za znanost (HRZZ)"))
                            .font(.subheadline.weight(.semibold))
                        Text(L("Croatian Science Foundation"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://hrzz.hr/en/")!) {
                            Text("hrzz.hr").font(.caption2)
                        }
                    }
                }
                .padding(.vertical, 2)

                HStack(alignment: .center, spacing: 14) {
                    Image("LogoIARH")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .padding(4)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Institut za arheologiju (IARH)"))
                            .font(.subheadline.weight(.semibold))
                        Text(L("Institute of Archaeology, Zagreb"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://www.iarh.hr/en/home/")!) {
                            Text("iarh.hr").font(.caption2)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            // License
            Section {
                Text(L("Released under the MIT License.\nFree and open-source software."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(L("About & Credits"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct CreditsSheet: View {
    @ObservedObject private var language = LanguageManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CreditsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(L("Done")) { dismiss() }
                    }
                }
        }
    }
}
