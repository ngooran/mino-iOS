//
//  ContentView.swift
//  Mino
//
//  Main content view with tab bar navigation
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTab: Tab = .tools

    enum Tab {
        case tools
        case files
        case about
    }

    init() {
        // iOS 26+ uses automatic Liquid Glass for navigation/tab bars
        // Only apply custom dark appearance for older iOS versions
        if #unavailable(iOS 26.0) {
            // Configure tab bar appearance
            let tabBarAppearance = UITabBarAppearance()
            tabBarAppearance.configureWithOpaqueBackground()
            tabBarAppearance.backgroundColor = UIColor(Color.minoHeroBackground)

            // Unselected tab items
            tabBarAppearance.stackedLayoutAppearance.normal.iconColor = UIColor.white.withAlphaComponent(0.4)
            tabBarAppearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                .foregroundColor: UIColor.white.withAlphaComponent(0.4)
            ]

            UITabBar.appearance().standardAppearance = tabBarAppearance
            UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance

            // Configure navigation bar appearance (compact inline style)
            let navBarAppearance = UINavigationBarAppearance()
            navBarAppearance.configureWithOpaqueBackground()
            navBarAppearance.backgroundColor = UIColor(Color.minoHeroBackground)
            navBarAppearance.titleTextAttributes = [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold)
            ]

            UINavigationBar.appearance().standardAppearance = navBarAppearance
            UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
            UINavigationBar.appearance().compactAppearance = navBarAppearance
        }
        // iOS 26+: Liquid Glass is applied automatically to toolbars
    }

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $selectedTab) {
            // Tools Tab
            NavigationStack {
                ToolsView()
                    .navigationTitle("Mino")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Tools", systemImage: "wrench.and.screwdriver.fill")
            }
            .tag(Tab.tools)

            // Files Tab
            NavigationStack {
                GeneratedFilesView()
                    .navigationTitle("Files")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Files", systemImage: "folder.fill")
            }
            .tag(Tab.files)

            // About Tab
            NavigationStack {
                AboutView()
                    .navigationTitle("About")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("About", systemImage: "info.circle.fill")
            }
            .tag(Tab.about)
        }
        .tint(Color.minoAccent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $state.showingDocumentPicker) {
            DocumentPicker { url in
                Task {
                    await importDocument(from: url)
                }
            } onCancel: {
                state.showingDocumentPicker = false
            }
        }
        .sheet(isPresented: $state.showingCompressionView) {
            if !state.documentsToCompress.isEmpty {
                CompressionView(documents: state.documentsToCompress)
                    .environment(appState)
            } else if let document = state.selectedDocument {
                // Fallback for legacy single document flow
                CompressionView(documents: [document])
                    .environment(appState)
            }
        }
        .sheet(isPresented: $state.showingResultsView) {
            if let result = state.currentResult {
                ResultsView(result: result)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $state.showingBatchResultsView) {
            if let queue = state.batchCompressionService.currentQueue {
                BatchResultsView(queue: queue) {
                    state.showingBatchResultsView = false
                }
                .environment(appState)
            }
        }
        .alert("Error", isPresented: $state.showingError) {
            Button("OK") {
                state.clearError()
            }
        } message: {
            if let error = state.currentError {
                Text(error.localizedDescription)
            }
        }
        // MARK: - Tools Sheets
        .sheet(isPresented: $state.showingMergeView) {
            MergeView()
                .environment(appState)
        }
        .sheet(isPresented: $state.showingSplitView) {
            if let document = state.documentForSplit {
                SplitView(document: document)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $state.showingDocumentPickerForSplit) {
            DocumentPicker { url in
                Task {
                    await importDocumentForSplit(from: url)
                }
            } onCancel: {
                state.showingDocumentPickerForSplit = false
            }
        }
        .sheet(isPresented: $state.showingMultiDocumentPicker) {
            MultiDocumentPicker { urls in
                Task {
                    await importDocumentsForBatch(urls)
                }
            } onCancel: {
                state.showingMultiDocumentPicker = false
            }
        }
    }

    // MARK: - Actions

    private func importDocument(from url: URL) async {
        do {
            let document = try await appState.documentImporter.importDocument(from: url)
            appState.addImportedDocument(document)
            appState.showingDocumentPicker = false
            appState.startCompression(for: document)
        } catch {
            appState.showError(error)
        }
    }

    private func importDocumentForSplit(from url: URL) async {
        do {
            let document = try await appState.documentImporter.importDocument(from: url)
            appState.addImportedDocument(document)
            appState.showingDocumentPickerForSplit = false
            appState.documentForSplit = document
            appState.showingSplitView = true
        } catch {
            appState.showError(error)
        }
    }

    private func importDocumentsForBatch(_ urls: [URL]) async {
        var documents: [PDFDocumentInfo] = []
        for url in urls {
            do {
                let document = try await appState.documentImporter.importDocument(from: url)
                appState.addImportedDocument(document)
                documents.append(document)
            } catch {
                appState.showError(error)
            }
        }

        if !documents.isEmpty {
            appState.showingMultiDocumentPicker = false
            appState.startCompressionForDocuments(documents)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
