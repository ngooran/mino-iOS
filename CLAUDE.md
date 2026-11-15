# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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

Mino is an iOS PDF toolkit that uses MuPDF (C library) via Swift bridging. Features include compression, merge, and split.

### App Structure

```
TabView (.sidebarAdaptable)
├── Home      - Compress card, Merge / Split tiles, recent files
├── Files     - All generated files: search + All/Compressed/Merged/Split filter
└── Settings  - Mino Pro status, defaults, statistics, support, about
```

**Adaptive layout** (`Mino/UI/Root/RootView.swift`): layout follows the horizontal size class, never the device.
- Compact (iPhone, iPhone Duo closed, Split View halves): each tab is a `NavigationStack`.
- Regular (iPad, iPhone Duo open): tabs move to a sidebar; each tab is a `NavigationSplitView` with the list leading and the current task or file trailing.
- Both read the same `AppState` paths (`homePath`, `filesPath`, `settingsPath`), so the screen survives rotation, folding and window resizing.
- Tasks (compress, merge, split) keep their state in sessions (`Mino/App/Sessions.swift`), not in views.
- iPhone Duo book pose (`Mino/UI/Components/FoldAwareness.swift`): iOS 27.1 reports the hinge as a `.division` reserved region whose frame includes ~20pt margins each side. Split view columns meet at the hinge's midX and `avoidingFoldEdges()` keeps each column's content out of the band. The paywall goes two-page only when a full page fits on each side. DEBUG launch argument `-showRegions` outlines all reserved regions.

### Monetization (`Mino/Store/`)

Free download + one-time non-consumable **Mino Pro** (`com.applestan.Mino.pro`), StoreKit 2.
- Free: 3 single-file compressions per day (`FreeUsage`).
- Pro: unlimited, batch, merge, split, custom quality.
- People who bought the paid app keep everything: `ProStore.checkLegacyPurchase()` compares `AppTransaction.originalAppVersion` (the build number on iOS) with `firstFreemiumBuild` (4). Only production receipts count.
- Gate features with `appState.requirePro(reason) { action }`; the paywall runs `action` after unlocking.
- Local testing: the shared `Mino` scheme uses `Mino.storekit`. DEBUG builds have a Pro/Free switch in Settings.
- DEBUG launch arguments open any screen with sample PDFs: `-demoScreen home|compress|result|merge|split|files|settings|paywall`, plus `-demoFree`, `-demoPro`, `-demoRun` (`Mino/App/DebugLaunch.swift`).

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
- `Home/HomeView` - compress card, tool tiles, recent files, drop zone (regular width)
- `Tasks/CompressFlowView` - quality (with size estimates) → progress → result
- `Tasks/MergeFlowView`, `Tasks/SplitFlowView` - same configure → progress → result pattern
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

Compressed/Merged/Split files are stored in app's Documents directory:
- Each operation writes to its own folder, `<Kind>/<UUID>/<Clean Name>.pdf` (`OutputLocation`), so shared files keep readable names
- Paths stored as relative paths in UserDefaults (survives container UUID changes)
- Imported input copies (`ImportedPDFs/`) are cleared at launch
- `standardizedFileURL` used for consistent path handling
- Services have `clearAllResults()` to delete files and clear history

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
