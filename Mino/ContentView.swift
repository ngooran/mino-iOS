//
//  ContentView.swift
//  Mino
//
//  Main content view with tab bar navigation
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedTab: Tab = .home

    enum Tab {
        case home
        case statistics
        case about
    }

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $selectedTab) {
            // Home Tab
            NavigationStack {
                HomeView()
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(Tab.home)

            // Statistics Tab
            NavigationStack {
                StatisticsView()
            }
            .tabItem {
                Label("Statistics", systemImage: "chart.bar.fill")
            }
            .tag(Tab.statistics)

            // About Tab
            NavigationStack {
                AboutView()
            }
            .tabItem {
                Label("About", systemImage: "info.circle.fill")
            }
            .tag(Tab.about)
        }
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
            if let document = state.selectedDocument {
                CompressionView(document: document)
                    .environment(appState)
            }
        }
        .sheet(isPresented: $state.showingResultsView) {
            if let result = state.currentResult {
                ResultsView(result: result)
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
}

#Preview {
    ContentView()
        .environment(AppState())
}
