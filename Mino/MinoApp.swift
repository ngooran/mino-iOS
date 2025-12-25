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
        }
    }
}
