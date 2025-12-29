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
            // Home Tab
            NavigationStack {
                HomeView()
                    .navigationTitle("Mino")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }
            .tag(Tab.home)

            // Statistics Tab
            NavigationStack {
                StatisticsView()
                    .navigationTitle("Statistics")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Statistics", systemImage: "chart.bar.fill")
            }
            .tag(Tab.statistics)

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
