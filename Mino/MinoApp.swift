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
            RootView()
                .environment(appState)
                .defaultAppStorage(StorageRoot.defaults)
                #if DEBUG
                .overlay { ReservedRegionsDebugOverlay() }
                #endif
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .task {
                    #if DEBUG
                    await DebugLaunch.apply(to: appState)
                    #endif
                    await checkForPendingSharedPDF()
                }
        }
        .commands {
            // Keyboard shortcuts on iPad (and iPhone with a keyboard).
            CommandGroup(replacing: .newItem) {
                Button("Compress PDF…") { appState.chooseFilesToCompress() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Merge PDFs…") { appState.openMerge() }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Split PDF…") { appState.openSplit() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }

    // MARK: - Incoming files

    /// Handles "Open in Mino" (file URLs) and the share extension (mino://import?file=…).
    private func handleIncomingURL(_ url: URL) {
        if url.isFileURL {
            appState.handleIncoming([url])
            return
        }
        guard url.scheme == SharedConstants.urlScheme,
              url.host == "import",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let fileParam = components.queryItems?.first(where: { $0.name == "file" })?.value,
              let fileURL = URL(string: fileParam) else { return }
        importSharedPDF(from: fileURL)
    }

    /// Picks up a PDF the share extension left in the App Group container.
    private func checkForPendingSharedPDF() async {
        guard let sharedDefaults = SharedConstants.sharedDefaults,
              let urlString = sharedDefaults.string(forKey: SharedConstants.sharedPDFKey),
              let fileURL = URL(string: urlString) else {
            return
        }
        sharedDefaults.removeObject(forKey: SharedConstants.sharedPDFKey)
        importSharedPDF(from: fileURL)
    }

    private func importSharedPDF(from url: URL) {
        Task {
            await appState.receive([url])
            // The app now has its own copy; remove the shared one.
            try? FileManager.default.removeItem(at: url)
        }
    }
}
