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
                Button("Open PDF…") { appState.openPDF() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Compress PDF…") { appState.chooseFilesToCompress() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
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
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        // The share extension passes one `file` item per shared file.
        let files = (components.queryItems ?? [])
            .filter { $0.name == "file" }
            .compactMap { $0.value.flatMap(URL.init(string:)) }
        guard !files.isEmpty else { return }
        SharedConstants.sharedDefaults?.removeObject(forKey: SharedConstants.sharedPDFKey)
        importSharedFiles(files)
    }

    /// Picks up files the share extension left in the App Group container.
    private func checkForPendingSharedPDF() async {
        guard let sharedDefaults = SharedConstants.sharedDefaults else { return }
        // One URL per line; builds before 2.1 stored a single URL.
        let files = (sharedDefaults.string(forKey: SharedConstants.sharedPDFKey) ?? "")
            .split(separator: "\n")
            .compactMap { URL(string: String($0)) }
        sharedDefaults.removeObject(forKey: SharedConstants.sharedPDFKey)
        guard !files.isEmpty else { return }
        importSharedFiles(files)
    }

    private func importSharedFiles(_ urls: [URL]) {
        Task {
            await appState.receive(urls)
            // The app now has its own copies; remove the shared ones.
            for url in urls {
                try? FileManager.default.removeItem(at: url)
                // Each shared file sits in its own folder (2.1 and later).
                let folder = url.deletingLastPathComponent()
                if UUID(uuidString: folder.lastPathComponent) != nil {
                    try? FileManager.default.removeItem(at: folder)
                }
            }
        }
    }
}
