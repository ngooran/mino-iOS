//
//  AboutView.swift
//  Mino
//
//  About screen with app info and licensing
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    // Replace with your actual repository URL
    private let sourceCodeURL = URL(string: "https://github.com/ngooran/mino-iOS")!
    private let mupdfURL = URL(string: "https://mupdf.com")!
    private let agplURL = URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!

    var body: some View {
        NavigationStack {
            List {
                // App info section
                Section {
                    appInfoHeader
                }

                // About section
                Section("About") {
                    Text("Mino is an offline PDF compressor that uses the MuPDF library to efficiently reduce PDF file sizes while maintaining quality.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Label {
                        Text("All compression happens on your device. Your files never leave your phone.")
                    } icon: {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(.green)
                    }
                    .font(.subheadline)
                }

                // Open Source section
                Section("Open Source") {
                    Link(destination: sourceCodeURL) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("View Source Code")
                                Text("GitHub Repository")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                        }
                    }

                    Link(destination: mupdfURL) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("MuPDF Library")
                                Text("PDF rendering engine")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "doc.text")
                        }
                    }
                }

                // License section
                Section("License") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GNU Affero General Public License v3.0")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text("This application is free software licensed under the AGPL-3.0. You are free to use, modify, and distribute it under the terms of this license.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("The source code is available at the GitHub link above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Link(destination: agplURL) {
                        Label("Read Full License", systemImage: "doc.plaintext")
                    }
                }

                // Credits section
                Section("Credits") {
                    VStack(alignment: .leading, spacing: 8) {
                        creditRow(name: "MuPDF", role: "PDF Engine", license: "AGPL-3.0")
                    }
                    .padding(.vertical, 4)
                }

                // Version section
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text(buildNumber)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Views

    private var appInfoHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentColor)

            Text("Mino")
                .font(.title.bold())

            Text("PDF Compressor")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("PDFs, made light")
                .font(.caption)
                .italic()
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func creditRow(name: String, role: String, license: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(role)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(license)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.secondary.opacity(0.2))
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

#Preview {
    AboutView()
}
