//
//  StorageRoot.swift
//  Mino
//
//  Where Mino keeps its files and settings. Everything that persists goes
//  through here, so DEBUG builds can swap in a throwaway sandbox.
//

import Foundation

nonisolated enum StorageRoot {

    /// Documents folder for generated and imported PDFs.
    static let documents: URL = {
        let real = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #if DEBUG
        if isDemoSandbox {
            let sandbox = real.appendingPathComponent("DemoSandbox", isDirectory: true)
            try? FileManager.default.removeItem(at: sandbox)
            try? FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
            return sandbox
        }
        #endif
        return real
    }()

    /// Settings, history and purchase cache.
    nonisolated(unsafe) static let defaults: UserDefaults = {
        #if DEBUG
        if isDemoSandbox, let sandbox = UserDefaults(suiteName: demoSuiteName) {
            sandbox.removePersistentDomain(forName: demoSuiteName)
            return sandbox
        }
        #endif
        return .standard
    }()

    #if DEBUG
    /// Launch with `-demoSandbox` for screenshots: an empty store, reset on every
    /// launch, so the real files and statistics on a test device stay untouched.
    static let isDemoSandbox = ProcessInfo.processInfo.arguments.contains("-demoSandbox")
    private static let demoSuiteName = "com.applestan.Mino.demoSandbox"
    #endif
}
