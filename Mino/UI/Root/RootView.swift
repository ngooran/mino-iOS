//
//  RootView.swift
//  Mino
//
//  Tab structure and adaptive navigation.
//
//  Compact width (iPhone, iPhone Duo closed, Split View halves):
//    a tab bar, and each tab is a navigation stack.
//  Regular width (iPad, iPhone Duo open):
//    tabs move into a sidebar, and each tab is a two-column split view:
//    the list on the leading side, the current task or file on the trailing side.
//
//  Both layouts read the same AppState paths, so the screen and its state
//  survive rotation, folding and window resizing.
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(SettingsKeys.appearance) private var appearance: AppearanceOption = .system

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {
            Tab("Home", systemImage: "house", value: AppTab.home) {
                TabRoot(tab: .home)
            }
            Tab("Files", systemImage: "folder", value: AppTab.files) {
                TabRoot(tab: .files)
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                TabRoot(tab: .settings)
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .preferredColorScheme(appearance.colorScheme)
        .fileImporter(
            isPresented: Binding(
                get: { appState.importTarget != nil },
                set: { if !$0 { appState.importTarget = nil } }
            ),
            allowedContentTypes: appState.lastImportTarget.contentTypes,
            allowsMultipleSelection: appState.lastImportTarget.allowsMultipleSelection
        ) { result in
            appState.handleImporterResult(result, target: appState.lastImportTarget)
        }
        .sheet(item: $state.paywallReason, onDismiss: { appState.paywallDismissed() }) { reason in
            PaywallView(reason: reason)
        }
        .sheet(item: $state.toolPicker) { context in
            ToolPickerSheet(context: context)
        }
        .modifier(PasswordPrompt())
        .alert(
            "Can't Open File",
            isPresented: Binding(
                get: { appState.errorMessage != nil },
                set: { if !$0 { appState.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .overlay {
            if appState.isImporting {
                ProgressView("Opening…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .dropDestination(for: DroppedFile.self) { items, _ in
            appState.handleIncoming(items.map(\.url))
            return !items.isEmpty
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appState.usage.rollOverIfNeeded()
            }
        }
    }
}

// MARK: - Tab root

/// One tab, laid out for the current width.
struct TabRoot: View {
    let tab: AppTab

    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The iPhone Duo hinge, when the display has one.
    @State private var fold: CGRect?
    /// Start with the list showing. Left automatic, a flat iPhone Duo hides it
    /// although both columns fit; the sidebar button still collapses it.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        let path = Binding(
            get: { appState.path(for: tab) },
            set: { appState.setPath($0, for: tab) }
        )

        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                TabList(tab: tab)
                    .avoidingFoldEdges()
                    .modifier(ListColumnWidth(fold: fold))
            } detail: {
                let detailPath = Binding(
                    get: { Array(path.wrappedValue.dropFirst()) },
                    set: { path.wrappedValue = Array(path.wrappedValue.prefix(1)) + $0 }
                )
                NavigationStack(path: detailPath) {
                    Group {
                        if let first = path.wrappedValue.first {
                            RouteView(route: first)
                        } else {
                            TabPlaceholder(tab: tab)
                        }
                    }
                    .id(path.wrappedValue.first)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
                }
                .avoidingFoldEdges()
            }
            .navigationSplitViewStyle(.balanced)
            // Only a bent hinge sets the column width: flat, the Duo is a small
            // tablet and iOS overlays a hinge-wide list instead of showing it alongside.
            .readVerticalFold(includeInactive: false, into: $fold)
        } else {
            NavigationStack(path: path) {
                TabList(tab: tab)
                    .navigationDestination(for: Route.self) { RouteView(route: $0) }
            }
        }
    }
}

/// Width of the list column. On iPhone Duo the columns meet at the middle of the
/// hinge, so in book pose each column sits on its own half; `avoidingFoldEdges()`
/// keeps each column's content out of its side of the hinge band.
private struct ListColumnWidth: ViewModifier {
    let fold: CGRect?

    func body(content: Content) -> some View {
        if let fold {
            content.navigationSplitViewColumnWidth(fold.midX)
        } else {
            content.navigationSplitViewColumnWidth(min: 320, ideal: 380, max: 460)
        }
    }
}

/// The leading (list) content of a tab.
private struct TabList: View {
    let tab: AppTab

    var body: some View {
        switch tab {
        case .home: HomeView()
        case .files: FilesView()
        case .settings: SettingsView()
        }
    }
}

/// What the trailing column shows when nothing is open (regular width only).
private struct TabPlaceholder: View {
    let tab: AppTab
    @Environment(AppState.self) private var appState

    var body: some View {
        switch tab {
        case .home:
            HomeDropZone()
        case .files:
            if let first = appState.files.first {
                FilePreviewView(item: first)
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc", description: Text("Choose a file to preview it."))
            }
        case .settings:
            StatisticsView()
        }
    }
}

/// Maps a route to its screen.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .compress: CompressFlowView()
        case .merge: MergeFlowView()
        case .split: SplitFlowView()
        case .tool(let tool): ToolRouteView(tool: tool)
        case .preview(let item): FilePreviewView(item: item)
        case .statistics: StatisticsView()
        }
    }
}

/// The screen of a tool added after 2.0.
private struct ToolRouteView: View {
    let tool: Tool

    var body: some View {
        switch tool {
        case .scan: ScanFlowView()
        case .ocr: OCRFlowView()
        case .fillSign, .edit: EditorFlowView(tool: tool)
        case .officeToPDF: OfficeFlowView()
        case .photosToPDF: PhotosToPDFFlowView()
        case .pdfToImages: PDFToImagesFlowView()
        case .organize: OrganizeFlowView()
        case .protect: ProtectFlowView()
        default: NoSessionView(tool: tool)
        }
    }
}

// MARK: - Password prompt

/// Asks for the password of a locked PDF while it is being opened.
private struct PasswordPrompt: ViewModifier {
    @Environment(AppState.self) private var appState
    @State private var password = ""

    func body(content: Content) -> some View {
        let request = appState.passwordRequest
        content.alert(
            "Password Required",
            isPresented: Binding(
                get: { appState.passwordRequest != nil },
                // Dismissed without a button (never by the system today): treat as cancel.
                set: { if !$0, appState.passwordRequest != nil { appState.submitPassword(nil) } }
            )
        ) {
            SecureField("Password", text: $password)
                .textContentType(.password)
            Button("Cancel", role: .cancel) {
                password = ""
                appState.submitPassword(nil)
            }
            Button("Open") {
                let entered = password
                password = ""
                appState.submitPassword(entered)
            }
            .keyboardShortcut(.defaultAction)
        } message: {
            if let request {
                Text(request.failed
                     ? String(localized: "That password didn't work. Try again to open “\(request.fileName)”.")
                     : String(localized: "“\(request.fileName)” is locked. Enter its password to open it."))
            }
        }
    }
}

// MARK: - Appearance

enum AppearanceOption: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return String(localized: "System")
        case .light: return String(localized: "Light")
        case .dark: return String(localized: "Dark")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Drag and drop

/// A PDF or an image dropped onto Mino from Files, Mail, Safari, Photos or another app.
struct DroppedFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .pdf) { try DroppedFile(copying: $0.file) }
        FileRepresentation(importedContentType: .image) { try DroppedFile(copying: $0.file) }
        FileRepresentation(importedContentType: UTType("org.openxmlformats.wordprocessingml.document") ?? .rtf) { try DroppedFile(copying: $0.file) }
        FileRepresentation(importedContentType: UTType("org.openxmlformats.spreadsheetml.sheet") ?? .rtf) { try DroppedFile(copying: $0.file) }
        FileRepresentation(importedContentType: UTType("org.openxmlformats.presentationml.presentation") ?? .rtf) { try DroppedFile(copying: $0.file) }
    }

    /// The received file only lives until the drop ends, so keep a copy.
    private init(copying file: URL) throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dropped-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: destination)
        url = destination
    }
}

/// Device word for copy such as "Nothing leaves your iPhone."
@MainActor
var deviceName: String {
    UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
}
