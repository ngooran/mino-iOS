# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Release status and the remaining steps for 2.0 (App Store Connect, TestFlight, pricing switch) are in [RELEASE-2.0.md](RELEASE-2.0.md). App Store texts are in [AppStoreMetadata.md](AppStoreMetadata.md). The plan after 2.0 (10 new tools, releases 2.1–2.4) is in [ROADMAP.md](ROADMAP.md).

## Build Commands

```bash
# Initialize submodules (required first time)
git submodule update --init --recursive

# Build MuPDF XCFrameworks for iOS (takes 10-20 min)
./Scripts/build_mupdf_ios.sh

# Build the app (simulator). Use a named simulator: MuPDF is built for arm64 only,
# so the generic simulator destination fails to link x86_64.
xcodebuild -project Mino.xcodeproj -scheme Mino -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17' build

# Run tests
xcodebuild test -scheme Mino -destination 'platform=iOS Simulator,name=iPhone 17'

# Open in Xcode
open Mino.xcodeproj
```

## Architecture Overview

Mino is an iOS PDF toolkit that uses MuPDF (C library) via Swift bridging. 2.0 has Compress, Merge and Split. `main` also has the tools of ROADMAP.md; it is the only branch. Tag `v1.2` marks the live version, and commit `d2b82b3` is 2.0 without the new tools. ROADMAP.md's "Progress" section says what is built, how it was verified and what is left.

### App Structure

```
TabView (.sidebarAdaptable)
├── Home      - Search, Open PDF, tools by category, recent files
├── Files     - All generated files: search + filter menu (only kinds that exist)
└── Settings  - Mino Pro status, defaults, statistics, support, about
```

**Adaptive layout** (`Mino/UI/Root/RootView.swift`): layout follows the horizontal size class, never the device.
- Compact (iPhone, iPhone Duo closed, Split View halves): each tab is a `NavigationStack`.
- Regular (iPad, iPhone Duo open): tabs move to a sidebar; each tab is a `NavigationSplitView` with the list leading and the current task or file trailing.
- Both read the same `AppState` paths (`homePath`, `filesPath`, `settingsPath`), so the screen survives rotation, folding and window resizing.
- Tasks (compress, merge, split) keep their state in sessions (`Mino/App/Sessions.swift`), not in views.
- iPhone Duo (`Mino/UI/Components/FoldAwareness.swift`): iOS 27.1 reports the hinge as a `.division` reserved region whose frame includes ~20pt margins each side.
  - Book pose (hinge bent): the list column is as wide as the hinge's midX, and `avoidingFoldEdges()` keeps each column's content out of the band.
  - Flat: the Duo is a small tablet, so the list keeps its standard width. A hinge-wide list next to a 476pt detail makes iOS overlay the list instead of showing it alongside.
  - Split views start with `columnVisibility = .all`; on automatic, a flat Duo hides the list.
  - The paywall goes two-page only when a full page fits on each side, and gets a tighter header on screens under 720pt tall.
  - DEBUG launch argument `-showRegions` outlines all reserved regions.

### Tools (`Mino/App/Tools.swift`)

`Tool` is the registry: title, subtitle, symbol, color, category, access (free allowance or Pro), input, search keywords, route and paywall message. Home, search, the tool picker sheet and the paywall read from it.
- `Tool.available` lists the tools that ship. Add a tool there when it is finished.
- Free with 3 actions a day (shared): Compress, Scan, Photos to PDF, PDF to Images, Organize Pages. Everything else is Pro. This split is the owner's decision; don't change it.
- Pro tools open for everyone. The paywall shows at the final button: call `appState.mayRun(tool) { retry }` there.

**Adding a tool** (the pattern of every tool after 2.0):
1. Engine in `Mino/Features/<Tool>/`: a `nonisolated enum` with static functions that do the work and throw. No UI, no AppState. The app's default actor isolation is MainActor, so engines and the models they use must be marked `nonisolated`.
2. MuPDF wrapper functions in `MuPDFHelpers.c/.h` where needed (`MuPDF.withPDF` and `MuPDF.lastError()` in `MuPDFSupport.swift` help on the Swift side).
3. Session in `Mino/App/Sessions.swift`: an `@Observable` class with the options and `let state = TaskState()`.
4. In `AppState`: a session property, a case in `start(_:with:)` and `finish(_:)`, and a run function that calls `mayRun`, then `run(tool, state:) { progress in ... return ToolOutput(...) }`. `run` works off the main thread, stores the result in `ToolResultStore`, counts a free action and sets `state.phase`.
5. Flow view in `Mino/UI/Tasks/`: wrap the configure screen in `ToolFlow`, which supplies the working, failure and result screens. Add it to `ToolRouteView` in `RootView.swift`.
6. `-demoScreen` case in `DebugLaunch.swift`, a test file in `MinoTests/`, and the tool in `Tool.available`.
7. Run `python3 Scripts/sync_strings.py` after a build to update the String Catalog.

**Camera:** the document camera does not exist in the simulator (`DocumentCamera.isSupported` is false). `-demoScreen scan` and the DEBUG "Use Sample Pages" button use `DebugLaunch.makeSampleScanPages`. Never run it on a physical device from here; the owner tests the camera. The camera is presented from `RootView` (`AppState.openCamera`), never from a tool screen: unfolding the Duo rebuilds tool screens. `-demoCamera` puts a stand-in camera in the simulator to test presenting and folding.

**Text layers:** `mino_overlay_pages` draws pages of one PDF on top of pages of another as Form XObjects, mapped through the page's rotation and crop box. Recognize Text uses it for the invisible text layer (drawn with CoreGraphics, so fonts for any script are embedded).

**Page editor:** `EditorSession` holds the PDFKit document and all behavior; `PageEditorView` only turns touches into `tap(at:on:)` and `dragBegan/Changed/Ended` in page coordinates, which is also how the tests and demo screens drive it. Additions are standard PDF annotations. Saving = PDFKit `write`, then `PageEditorEngine.finish` (MuPDF `mino_bake`, saved with `mino_save_pdf_untouched`; do not use the cleaning save after baking). PDFKit on iOS redraws a page when an annotation is added or removed, not when one is changed: use the session's `mutate`.

**Office to PDF:** `OfficeConverter` (main actor, async; AppState uses `runOnMain`, not `run`) loads the file in an offscreen `WKWebView`, which uses the system's Office renderers, and prints it with a `UIPrintPageRenderer`. The web view blocks all network loads with a content rule list and runs no document scripts; if the rules can't be compiled, nothing is converted. Workbooks are converted one sheet at a time (`WorkbookSplitter` hides the other sheets in a copy). The reasons for each step are in ROADMAP.md, "2.4, Office to PDF: the gate".

**PDF to Text:** the tool `Tool.pdfToWord` is titled "PDF to Text". PDF to Word failed its quality gate (ROADMAP.md, section 11), so never promise Word output in the app or store texts. `PDFToWordEngine.text` is what ships; `convertToWord` and `mino_write_docx` exist only for `WordGateTests`.

**Opening files:** `ImportTarget` says what the file picker is for. `AppState.importDocuments` copies PDFs into `ImportedPDFs/` and asks for the password of locked ones; the working copy is then unlocked (`PDFDocumentInfo.wasLocked`). "Open PDF", incoming files and "Continue with another tool" show `ToolPickerSheet`.

### Monetization (`Mino/Store/`)

Free download + one-time non-consumable **Mino Pro** (`com.applestan.Mino.pro`), StoreKit 2.
- Free: 3 actions per day, shared by the free tools (`FreeUsage`).
- Pro: unlimited, batch, merge, split, custom quality, and the Pro tools.
- People who bought the paid app keep everything: `ProStore.checkLegacyPurchase()` compares `AppTransaction.originalAppVersion` (the build number on iOS) with `firstFreemiumBuild` (4). Only production receipts count.
- Gate features with `appState.requirePro(reason) { action }`; the paywall runs `action` after unlocking. Tools use `appState.mayRun(tool) { retry }`, which also checks the daily allowance.
- Local testing: the shared `Mino` scheme uses `Mino.storekit`. DEBUG builds have a Pro/Free switch in Settings.
- DEBUG launch arguments open any screen with sample data: `-demoScreen home|search|picker|password|compress|result|merge|split|scan|ocr|sign|signature|edit|office|text|photos|images|organize|protect|unlock|files|settings|paywall`, plus `-demoFree`, `-demoPro`, and `-demoRun` to run the tool and show its result (`Mino/App/DebugLaunch.swift`).
- `-demoSandbox` (DEBUG) swaps in a throwaway store (`StorageRoot`: `Documents/DemoSandbox` + a separate UserDefaults suite). It is wiped and refilled with sample files on every launch, shows the €4.99 price (the real Mino Pro price, since StoreKit can't load outside Xcode) and never asks for a review. Use it for screenshots so a device's real files and stats never show. `-demoAppearance light|dark` sets the app appearance.

### Core Data Flow

```
Compression:
User selects PDF(s) → DocumentImporter → [PDFDocumentInfo]
                                              ↓
                      CompressionService / BatchCompressionService
                                              ↓
                      PDFCompressor (Swift) → mino_compress_pdf() (C)
                                              ↓
                      CompressionResult → ResultsView / BatchResultsView

Merge:
User selects PDFs → MergeService → PDFMerger → MergeResult

Split:
User selects PDF → SplitService → PDFSplitter → [SplitResult]
```

### Key Components

**AppState** (`Mino/App/AppState.swift`)
- Central `@Observable` state container
- Holds services: `compressionService`, `batchCompressionService`, `mergeService`, `splitService`
- Manages navigation state and documents
- Injected via SwiftUI environment

**Services** (`Mino/Features/`)
- `CompressionService` - Single file compression with job tracking
- `BatchCompressionService` - Multi-file sequential compression with queue
- `MergeService` - Combine multiple PDFs into one
- `SplitService` - Extract page ranges or split into individual pages
- `Library/ToolResultStore` - Results of every tool added after 2.0
- Engines: `PhotosToPDF/PhotosToPDFEngine`, `PDFToImages/PDFToImagesEngine`, `Organize/PageOrganizer`, `Protect/PDFProtector`, `Scan/ScanEngine` (+ `Scan/DocumentCamera`, the VisionKit camera), `OCR/TextRecognizer` (Vision), `Editor/` (the page editor of Fill & Sign and Edit & Annotate: `EditorSession`, `EditorModel`, `SignatureStore`, `PageEditorEngine`), `Office/OfficeConverter` (+ `Office/WorkbookSplitter`), `PDFToWord/PDFToWordEngine` (PDF to Text)

**MuPDF Integration** (`Mino/Core/MuPDF/`)
- `MuPDFHelpers.h/.c` - C wrapper functions for MuPDF API
- `Mino-Bridging-Header.h` - Exposes C functions to Swift
- `PDFCompressor.swift` - Compression via `mino_compress_pdf()`
- `PDFMerger.swift` - Page grafting for merge
- `PDFSplitter.swift` - Page extraction for split

**History & Statistics** (`Mino/Features/History/`)
- `HistoryManager` - Singleton tracking compression stats (persisted to UserDefaults)
- `StatisticsView` - Accessible from About screen, shows stats and recent activity

**PDF Viewer** (`Mino/Features/Viewer/`)
- `PDFViewerView` - Uses QuickLook (`QLPreviewController`) for reliable PDF display
- Wrapped via `UIViewControllerRepresentable`

### Models

- `CompressionQuality` - Presets (Low/Medium/High) with JPEG quality and DPI
- `CompressionSettings` - Full settings including custom values
- `CompressionResult` - Output file info, sizes, duration
- `PDFDocumentInfo` - Input document metadata
- `BatchCompressionQueue` / `BatchCompressionItem` - Queue state for batch ops
- `MergeJob` / `MergeResult` - Merge operation state
- `SplitResult` - Split operation output

### UI (`Mino/UI/`)

- `Root/RootView` - tabs, adaptive navigation, file importer, paywall sheet, drag and drop
- `Home/HomeView` - search, entry points, tool tiles by category, recent files, placeholder (regular width)
- `Tasks/CompressFlowView` - quality (with size estimates) → progress → result
- `Tasks/MergeFlowView`, `Tasks/SplitFlowView` - same configure → progress → result pattern
- `Tasks/ToolFlow` - shared frame of the newer tools: working, failure and result screens, `PageSelectionGrid`, `DocumentCard`
- `Tasks/PhotosToPDFFlowView`, `PDFToImagesFlowView`, `OrganizeFlowView`, `ProtectFlowView`, `ScanFlowView`, `OCRFlowView`, `EditorFlowView` (both editor tools), `OfficeFlowView`, `PDFToTextFlowView`
- `Home/ToolPickerSheet` - "What do you want to do?"
- `Files/FilesView` - file list and Quick Look preview
- `Settings/SettingsView` - settings and statistics
- `Paywall/PaywallView` - Mino Pro
- `Components/` - thumbnails (Quick Look / PDFKit), rows, progress and result views

## UI & Theming

**Theme** (`Mino/UI/Styles/Theme.swift`)
- Follows the system: light and dark mode, grouped backgrounds, standard lists and Liquid Glass on iOS 26 (bordered fallbacks on iOS 18)
- Tint is the `AccentColor` asset (teal, with a lighter dark-mode variant)
- Helpers: `primaryButtonStyle()`, `secondaryButtonStyle()`, `bottomActions {}`, `cardStyle()`, `ProBadge`, `IconTile`, `AppIconView`

**Button Best Practice**
- Always add `.contentShape(Rectangle())` to buttons with `Spacer()` or HStack layouts
- Ensures entire button area is tappable, not just visible content

**App Icon** (`Mino/Resources/AppIconDesign.swift`)
- SwiftUI Canvas-based icon design, also drawn in-app by `AppIconView`
- Export via `AppIconExportView` (DEBUG only, in Settings)

## MuPDF C API Notes

The C helpers in `MuPDFHelpers.c` wrap MuPDF's error handling:
- MuPDF uses `fz_try/fz_catch` macros (setjmp/longjmp-based)
- All MuPDF calls require an `fz_context*`
- PDF operations need `pdf_document*` from `pdf_specifics()`
- Image rewriter uses `pdf_image_rewriter_options` with `char*` quality strings
- Merge uses `pdf_graft_map` for page copying between documents

## File Persistence

Generated files are stored in the app's Documents directory:
- Each operation writes to its own folder, `<Kind>/<UUID>/<Clean Name>.pdf` (`OutputLocation`), so shared files keep readable names. Folders: `Compressed`, `Merged`, `Split`, `Converted`, `Images`, `Edited`, `Protected`, `Scans`, `Signed`; signatures in `Signatures/`
- All persistence goes through `StorageRoot` (`Mino/Core/StorageRoot.swift`): use `StorageRoot.documents` and `StorageRoot.defaults`, never `UserDefaults.standard` or the documents directory directly
- Paths stored as relative paths in UserDefaults (survives container UUID changes)
- Imported input copies (`ImportedPDFs/`) are cleared at launch
- `standardizedFileURL` used for consistent path handling
- Services have `clearAllResults()` to delete files and clear history

## Text

All UI text is in `Mino/Localizable.xcstrings` (English only for now). SwiftUI literals are picked up automatically; anything that is a `String` must be written as `String(localized: "...")`. Counted strings use one key ("\(count) pages") with plural forms in the catalog. `python3 Scripts/sync_strings.py` updates the catalog after a command-line build and adds the plural forms listed in it.

## Tests

`MinoTests` is a unit-test target hosted by the app. The scheme starts the host with `-demoSandbox`, so tests never touch real data.

```bash
xcodebuild test -project Mino.xcodeproj -scheme Mino -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' -derivedDataPath build/DerivedData
```

- One test file per tool, with a round trip (the output is opened with PDFKit, which is independent of the MuPDF code under test) and the tool's "done when" from ROADMAP.md.
- Fixtures are in `MinoTests/Fixtures`, generated by `Scripts/make_fixtures.swift`, `make_structured_fixture.py`, `make_form_fixture.py` and `make_office_fixtures.py`.
- `OfficeGateTests` and `WordGateTests` are the two quality gates. They are skipped unless a folder of test documents is given (`TEST_RUNNER_MINO_GATE_DIR` / `TEST_RUNNER_MINO_WORD_GATE_DIR`, see ROADMAP.md section 11).

## App Store Screenshots

Raw screenshots live in `Screenshots/raw/<locale>/<device>/` (`iphone-6.9`, `ipad-13`, `iphone-duo`, `iphone-duo-closed`), one file per screen (`01-home` ... `07-paywall`). Only `en-US` exists: the app and the listing are English only.

- Take them on simulators only, never on a physical device: iPhone 18 Pro Max (6.9", 1320×2868), iPad Pro 13-inch (2064×2752), iPhone Duo (open 2853×2007, closed 1398×2034).
- Before shooting, run `xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100`, and set `xcrun simctl ui <udid> appearance light`.
- Launch each screen with `-demoSandbox -demoAppearance light -demoScreen <screen>`, adding `-demoFree` except for merge and split. Wait about 15 s for the sample files.
- Xcode 27 has no Simulator.app (Device Hub replaces it), and `simctl` can't fold the Duo. Use `hinge` (`brew install artemnovichkov/tap/hinge`):
  - `hinge open` / `hinge close` / `hinge 110` set the fold.
  - `hinge orient portrait` gives the wide, two-page inner layout; Duo "portrait" is 2853×2007.
  - `hinge screenshot <file>` captures the display that is showing the app.

## Git Workflow

```bash
# Check status
git status

# Stage all changes
git add .

# Commit (no Claude footer or Co-Authored-By)
git commit -m "Your commit message"

# Push
git push origin main
```

**Commit message style**: Use imperative mood, concise description. No emoji, no Claude attribution footer.

## License

AGPL-3.0 with App Store Exception. MuPDF modifications must remain open source.
