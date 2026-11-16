//
//  OfficeFlowView.swift
//  Mino
//
//  Pick a Word, Excel or PowerPoint file → page size → Convert.
//

import SwiftUI

struct OfficeFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.officeSession {
            OfficeContent(session: session)
                .id(session.fileURL)
        } else {
            NoSessionView(tool: .officeToPDF)
        }
    }
}

private struct OfficeContent: View {
    @Bindable var session: OfficeSession
    @Environment(AppState.self) private var appState

    var body: some View {
        ToolFlow(
            tool: .officeToPDF,
            state: session.state,
            workingTitle: String(localized: "Converting…"),
            workingDetail: session.name,
            resultHeadline: String(localized: "Converted to PDF")
        ) {
            configureView
        }
    }

    private var configureView: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Text(verbatim: session.typeBadge)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 54, height: 70)
                        .background(Tool.officeToPDF.color.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(verbatim: "\(session.typeName) · \(ByteCountFormatter.string(fromByteCount: session.fileSize, countStyle: .file))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button("Change") { appState.importTarget = .tool(.officeToPDF) }
                        .buttonStyle(.borderless)
                }
                .accessibilityElement(children: .combine)
            }

            Section {
                Picker("Page Size", selection: $session.pageSize) {
                    ForEach(OfficePageSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Page Size")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Works with Word, Excel and PowerPoint files, and with RTF, CSV and text. Slides get one page each; every sheet of a workbook is included.")
                    Text("The PDF looks like the file's preview on this \(deviceName). Complex layouts can differ from Word or Excel, so check the result before you send it.")
                    Label("Converted on this \(deviceName). Nothing is uploaded.", systemImage: "lock.fill")
                }
                .padding(.top, 6)
            }
        }
        .bottomActions {
            Button {
                appState.convertOffice(session)
            } label: {
                ToolActionLabel(title: String(localized: "Convert to PDF"), tool: .officeToPDF)
            }
            .primaryButtonStyle()
            .keyboardShortcut(.defaultAction)
        }
    }
}
