//
//  SharedConstants.swift
//  Mino
//
//  Shared constants for App Group communication
//

import Foundation

/// Constants for sharing data between app and extensions
enum SharedConstants {
    /// App Group identifier for sharing data between app and extensions
    static let appGroupIdentifier = "group.com.applestan.Mino"

    /// URL scheme for deep linking
    static let urlScheme = "mino"

    /// Key for shared PDF URL in UserDefaults
    static let sharedPDFKey = "sharedPDFURL"

    /// Directory name for shared PDFs in App Group container
    static let sharedPDFDirectory = "SharedPDFs"

    /// Returns the shared container URL for the App Group
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// Returns the shared PDFs directory URL
    static var sharedPDFsURL: URL? {
        guard let container = sharedContainerURL else { return nil }
        let url = container.appendingPathComponent(sharedPDFDirectory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Returns the shared UserDefaults for the App Group
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
