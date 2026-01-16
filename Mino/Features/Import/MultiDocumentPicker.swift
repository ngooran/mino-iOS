//
//  MultiDocumentPicker.swift
//  Mino
//
//  SwiftUI wrapper for UIDocumentPickerViewController with multiple selection
//

import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI wrapper for document picker with multiple selection support
struct MultiDocumentPicker: UIViewControllerRepresentable {

    /// Callback when documents are picked (returns array of URLs)
    let onPick: ([URL]) -> Void

    /// Callback when picker is cancelled
    var onCancel: (() -> Void)?

    // MARK: - UIViewControllerRepresentable

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.pdf],
            asCopy: false
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: MultiDocumentPicker

        init(_ parent: MultiDocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel?()
        }
    }
}

// MARK: - Preview

#Preview {
    MultiDocumentPicker { urls in
        print("Selected \(urls.count) files")
    }
}
