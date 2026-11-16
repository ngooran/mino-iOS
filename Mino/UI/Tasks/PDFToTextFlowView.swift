//
//  PDFToTextFlowView.swift
//  Mino
//
//  Open PDF → Convert to Text. The result is a text file with the words in
//  reading order.
//

import SwiftUI

struct PDFToTextFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.textSession {
            PDFToTextContent(session: session)
                .id(session.document.id)
        } else {
            NoSessionView(tool: .pdfToWord)
        }
    }
}

private struct PDFToTextContent: View {
    @Bindable var session: PDFToTextSession
    @Environment(AppState.self) private var appState

    var body: some View {
        ToolFlow(
            tool: .pdfToWord,
            state: session.state,
            workingTitle: String(localized: "Converting…"),
            workingDetail: session.document.name,
            resultHeadline: String(localized: "Text ready")
        ) {
            configureView
        } extras: { _ in
            RecognizedTextCard(text: session.state.resultText)
        }
    }

    private var configureView: some View {
        Form {
            Section {
                DocumentCard(document: session.document) { appState.importTarget = .tool(.pdfToWord) }
            }

            Section {
                Toggle(isOn: $session.readScans) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Read Scanned Pages")
                        Text("Recognizes text on pages that are images")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Best for text documents. You get the words in reading order as a text file you can open in Word, Pages or Notes. Layout, tables and pictures are not kept.")
                    Label("Converted on this \(deviceName). Nothing is uploaded.", systemImage: "lock.fill")
                }
                .padding(.top, 6)
            }
        }
        .bottomActions {
            Button {
                appState.convertToText(session)
            } label: {
                ToolActionLabel(title: String(localized: "Convert to Text"), tool: .pdfToWord)
            }
            .primaryButtonStyle()
            .keyboardShortcut(.defaultAction)
        }
    }
}
