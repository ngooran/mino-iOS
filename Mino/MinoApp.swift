//
//  MinoApp.swift
//  Mino
//
//  PDF Compressor App - Main Entry Point
//

import SwiftUI

@main
struct MinoApp: App {
    /// Global application state
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .task {
                    await checkForPendingSharedPDF()
                }
        }
    }

    // MARK: - URL Handling

    /// Handles incoming URLs from the share extension
    private func handleIncomingURL(_ url: URL) {
        guard url.scheme == SharedConstants.urlScheme else { return }

        if url.host == "import",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
           let fileParam = components.queryItems?.first(where: { $0.name == "file" })?.value,
           let fileURL = URL(string: fileParam) {
            importSharedPDF(from: fileURL)
        }
    }

    /// Checks for pending shared PDFs when app launches
    private func checkForPendingSharedPDF() async {
        guard let sharedDefaults = SharedConstants.sharedDefaults,
              let urlString = sharedDefaults.string(forKey: SharedConstants.sharedPDFKey),
              let fileURL = URL(string: urlString) else {
            return
        }

        // Clear the pending URL
        sharedDefaults.removeObject(forKey: SharedConstants.sharedPDFKey)
        sharedDefaults.synchronize()

        // Import the PDF
        importSharedPDF(from: fileURL)
    }

    /// Imports a PDF from the shared container
    private func importSharedPDF(from url: URL) {
        Task { @MainActor in
            do {
                // Import using the document importer
                let documentInfo = try await appState.documentImporter.importDocument(from: url)
                appState.addImportedDocument(documentInfo)
                appState.startCompression(for: documentInfo)

                // Clean up the shared file after successful import
                try? FileManager.default.removeItem(at: url)
            } catch {
                appState.showError(error)
            }
        }
    }
}
