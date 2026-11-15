//
//  OCRFlowView.swift
//  Mino
//
//  Open a scanned PDF → language → Searchable PDF or Text Only → Recognize.
//

import SwiftUI

struct OCRFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.ocrSession {
            OCRContent(session: session)
                .id(session.document.id)
        } else {
            NoSessionView(tool: .ocr)
        }
    }
}

private struct OCRContent: View {
    @Bindable var session: OCRSession
    @Environment(AppState.self) private var appState
    @State private var languages: [String] = []

    var body: some View {
        ToolFlow(
            tool: .ocr,
            state: session.state,
            workingTitle: String(localized: "Reading pages…"),
            workingDetail: session.document.name,
            resultHeadline: String(localized: "Text recognized")
        ) {
            configureView
        } extras: { _ in
            RecognizedTextCard(text: session.state.resultText)
        }
    }

    private var configureView: some View {
        Form {
            Section {
                DocumentCard(document: session.document) { appState.importTarget = .tool(.ocr) }
            }

            Section {
                Picker("Language", selection: $session.language) {
                    Text("Automatic").tag(String?.none)
                    ForEach(languages, id: \.self) { code in
                        Text(Locale.current.localizedString(forIdentifier: code) ?? code).tag(String?.some(code))
                    }
                }
            } footer: {
                Text("Automatic works for most documents. Choose a language when the text is read badly.")
            }

            Section {
                Picker("Result", selection: $session.output) {
                    Text("Searchable PDF").tag(OCRSession.Output.searchablePDF)
                    Text("Text Only").tag(OCRSession.Output.text)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Result")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.output == .searchablePDF
                         ? "The PDF looks the same. Its text can then be searched, selected and copied. Pages that already have text are left as they are."
                         : "Saves the text of every page as a text file.")
                    Label("Text is recognized on this \(deviceName). Nothing is uploaded.", systemImage: "lock.fill")
                }
                .padding(.top, 6)
            }
        }
        .bottomActions {
            Button {
                appState.recognizeText(session)
            } label: {
                ToolActionLabel(title: String(localized: "Recognize Text"), tool: .ocr)
            }
            .primaryButtonStyle()
            .keyboardShortcut(.defaultAction)
        }
        .task {
            if languages.isEmpty {
                languages = await Task.detached { TextRecognizer.supportedLanguages }.value
            }
        }
    }
}
