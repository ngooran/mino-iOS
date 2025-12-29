//
//  AboutView.swift
//  Mino
//
//  About screen with app info and licensing
//

import SwiftUI

struct AboutView: View {
    private let sourceCodeURL = URL(string: "https://github.com/ngooran/mino-iOS")!
    private let mupdfURL = URL(string: "https://mupdf.com")!
    private let agplURL = URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!

    @State private var showingIconExport = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // About section
                AboutSection(title: "About") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Mino is an offline PDF compressor that uses the MuPDF library to efficiently reduce PDF file sizes while maintaining quality.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))

                        HStack(spacing: 12) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(Color.minoSuccess)
                            Text("All compression happens on your device. Your files never leave your phone.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                // Open Source section
                AboutSection(title: "Open Source") {
                    VStack(spacing: 0) {
                        AboutLinkRow(
                            icon: "chevron.left.forwardslash.chevron.right",
                            title: "View Source Code",
                            subtitle: "GitHub Repository",
                            url: sourceCodeURL
                        )

                        Divider()
                            .background(Color.minoCardBorder)

                        AboutLinkRow(
                            icon: "doc.text",
                            title: "MuPDF Library",
                            subtitle: "PDF rendering engine",
                            url: mupdfURL
                        )
                    }
                }

                // License section
                AboutSection(title: "License") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("GNU Affero General Public License v3.0")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)

                        Text("This application is free software licensed under the AGPL-3.0. You are free to use, modify, and distribute it under the terms of this license.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))

                        Text("The source code is available at the GitHub link above.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))

                        Divider()
                            .background(Color.minoCardBorder)
                            .padding(.vertical, 4)

                        Link(destination: agplURL) {
                            HStack {
                                Image(systemName: "doc.plaintext")
                                    .foregroundStyle(Color.minoAccent)
                                Text("Read Full License")
                                    .foregroundStyle(Color.minoAccent)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }

                // Credits section
                AboutSection(title: "Credits") {
                    creditRow(name: "MuPDF", role: "PDF Engine", license: "AGPL-3.0")
                }

                // Version section
                AboutSection(title: nil) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("Version")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(appVersion)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.vertical, 12)

                        Divider()
                            .background(Color.minoCardBorder)

                        HStack {
                            Text("Build")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(buildNumber)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .padding(.vertical, 12)
                    }
                }

                // Developer section
                AboutSection(title: "Developer") {
                    Button {
                        showingIconExport = true
                    } label: {
                        HStack {
                            Image(systemName: "app.gift")
                                .foregroundStyle(Color.minoAccent)
                            Text("Export App Icon")
                                .foregroundStyle(Color.minoAccent)
                            Spacer()
                        }
                    }
                }

                Spacer(minLength: 100)
            }
            .padding()
        }
        .background(Color.minoBackground)
        .minoToolbarStyle()
        .sheet(isPresented: $showingIconExport) {
            AppIconExportView()
        }
    }

    // MARK: - Views

    private func creditRow(name: String, role: String, license: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Text(license)
                .font(.caption)
                .foregroundStyle(Color.minoAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.minoAccent.opacity(0.15))
                .clipShape(Capsule())
        }
    }

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}

// MARK: - About Section

struct AboutSection<Content: View>: View {
    let title: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.5)
            }

            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.minoCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.minoCardBorder, lineWidth: 1)
                )
        }
    }
}

// MARK: - About Link Row

struct AboutLinkRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color.minoAccent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.vertical, 12)
        }
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .preferredColorScheme(.dark)
}
