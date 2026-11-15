//
//  ProtectFlowView.swift
//  Mino
//
//  Protect: set a password, choose what stays allowed.
//  Unlock: save a copy without a password you know.
//

import SwiftUI

struct ProtectFlowView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let session = appState.protectSession {
            ProtectContent(session: session)
                .id(session.document.id)
        } else {
            NoSessionView(tool: .protect)
        }
    }
}

private struct ProtectContent: View {
    @Bindable var session: ProtectSession
    @Environment(AppState.self) private var appState
    @FocusState private var focus: Field?

    private enum Field {
        case password
        case confirmation
        case permissions
    }

    var body: some View {
        ToolFlow(
            tool: .protect,
            state: session.state,
            workingTitle: session.mode == .protect ? String(localized: "Encrypting…") : String(localized: "Removing the password…"),
            workingDetail: session.document.name,
            resultHeadline: session.mode == .protect ? String(localized: "PDF protected") : String(localized: "Password removed")
        ) {
            configureView
        }
    }

    private var configureView: some View {
        Form {
            Section {
                Picker("Mode", selection: $session.mode) {
                    Text("Protect").tag(ProtectSession.Mode.protect)
                    Text("Unlock").tag(ProtectSession.Mode.unlock)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                DocumentCard(document: session.document) { appState.importTarget = .tool(.protect) }
            }

            switch session.mode {
            case .protect:
                protectSections
            case .unlock:
                unlockSections
            }
        }
        .bottomActions {
            Button {
                focus = nil
                appState.protect(session)
            } label: {
                ToolActionLabel(
                    title: session.mode == .protect ? String(localized: "Protect PDF") : String(localized: "Remove Password"),
                    tool: .protect
                )
            }
            .primaryButtonStyle()
            .disabled(!session.canRun)
        }
    }

    // MARK: - Protect

    @ViewBuilder
    private var protectSections: some View {
        Section {
            SecureField("Password", text: $session.password)
                .textContentType(.newPassword)
                .focused($focus, equals: .password)
                .submitLabel(.next)
                .onSubmit { focus = .confirmation }
            SecureField("Repeat Password", text: $session.confirmation)
                .textContentType(.newPassword)
                .focused($focus, equals: .confirmation)
                .submitLabel(.done)
        } footer: {
            if !session.passwordIsPortable {
                Label("Use only letters, numbers and symbols from the English keyboard. Other characters don't work in every PDF app.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            } else if !session.confirmation.isEmpty && session.password != session.confirmation {
                Label("The passwords don't match.", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
        }

        Section {
            Toggle("Allow Printing", isOn: $session.allowPrinting)
            Toggle("Allow Copying Text", isOn: $session.allowCopying)
        } footer: {
            Text("AES-256 encryption. If you forget the password, the file can't be opened. Mino doesn't store it.")
        }
    }

    // MARK: - Unlock

    @ViewBuilder
    private var unlockSections: some View {
        if session.document.wasLocked {
            Section {
                Label {
                    Text("Password accepted")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } footer: {
                Text("Mino saves a copy that opens without the password. The original stays as it is.")
            }
        } else if session.document.hasRestrictions {
            Section {
                SecureField("Permissions Password", text: $session.permissionsPassword)
                    .textContentType(.password)
                    .focused($focus, equals: .permissions)
                    .submitLabel(.done)
            } footer: {
                Text("This PDF opens without a password but limits printing or copying. Enter its permissions password to save a copy without the limits.")
            }
        } else {
            Section {
                Label("This PDF has no password.", systemImage: "lock.open")
                    .foregroundStyle(.secondary)
                Button("Choose Another PDF") { appState.importTarget = .tool(.protect) }
            }
        }

        Section {
        } footer: {
            Text("Unlock removes a password you know. It can't open a PDF whose password you don't know.")
        }
    }
}
