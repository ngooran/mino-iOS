//
//  SignatureStore.swift
//  Mino
//
//  The person's drawn signature and initials, kept as PNG files on this
//  device only (through StorageRoot). Nothing is synced or uploaded.
//

import UIKit

@Observable
@MainActor
final class SignatureStore {

    private(set) var images: [SignatureKind: UIImage] = [:]

    private var folder: URL {
        StorageRoot.documents.appendingPathComponent("Signatures", isDirectory: true)
    }

    init() {
        for kind in SignatureKind.allCases {
            if let data = try? Data(contentsOf: url(for: kind)), let image = UIImage(data: data) {
                images[kind] = image
            }
        }
    }

    func image(for kind: SignatureKind) -> UIImage? {
        images[kind]
    }

    var count: Int { images.count }

    func save(_ image: UIImage, for kind: SignatureKind) {
        guard let data = image.pngData() else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Protected while the device is locked.
        try? data.write(to: url(for: kind), options: [.atomic, .completeFileProtection])
        images[kind] = UIImage(data: data) ?? image
    }

    func delete(_ kind: SignatureKind) {
        try? FileManager.default.removeItem(at: url(for: kind))
        images[kind] = nil
    }

    private func url(for kind: SignatureKind) -> URL {
        folder.appendingPathComponent("\(kind.rawValue).png")
    }
}
