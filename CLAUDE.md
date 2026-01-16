# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Initialize submodules (required first time)
git submodule update --init --recursive

# Build MuPDF XCFrameworks for iOS (takes 10-20 min)
./Scripts/build_mupdf_ios.sh

# Build the app (simulator)
xcodebuild -project Mino.xcodeproj -scheme Mino -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build

# Run tests
xcodebuild test -scheme Mino -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'

# Open in Xcode
open Mino.xcodeproj
```

## Architecture Overview

Mino is an iOS PDF toolkit that uses MuPDF (C library) via Swift bridging. Features include compression, merge, and split.

### App Structure

```
Tab Bar
├── Home        - Quick compress with hero card
├── Tools       - Compress, Merge, Split tools
├── Files       - Generated files (Compressed/Merged/Split)
└── About       - App info, Statistics link, License
```

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

### UI Components (`Mino/UI/Components/`)

- `HomeView` - Hero card with quick compress
- `ToolsView` - Tool cards for Compress, Merge, Split
- `GeneratedFilesView` - Segmented view (Compressed/Merged/Split) with file cards
- `CompressionView` - Unified single/batch compression with quality selector
- `MergeView` - Reorderable document list, merge button
- `SplitView` - Range extraction or full split
- `ResultsView` - Single file success screen
- `BatchResultsView` - Batch success with stats and file list
- `AboutView` - App info, Statistics link, License

## UI & Theming

**Theme** (`Mino/UI/Styles/Theme.swift`)
- Dark theme with color hierarchy: `minoBackground` → `minoCardBackground`
- Accent color: `minoAccent` (teal), Success: `minoSuccess` (green), Error: `minoError` (red)
- Glass modifiers: `minoGlass()`, `minoGlassAccentButton()` for iOS 26 Liquid Glass
- Falls back to solid backgrounds on iOS < 26

**Button Best Practice**
- Always add `.contentShape(Rectangle())` to buttons with `Spacer()` or HStack layouts
- Ensures entire button area is tappable, not just visible content

**App Icon** (`Mino/Resources/AppIconDesign.swift`)
- SwiftUI Canvas-based icon design
- Export via `AppIconExportView` (DEBUG only in About screen)

## MuPDF C API Notes

The C helpers in `MuPDFHelpers.c` wrap MuPDF's error handling:
- MuPDF uses `fz_try/fz_catch` macros (setjmp/longjmp-based)
- All MuPDF calls require an `fz_context*`
- PDF operations need `pdf_document*` from `pdf_specifics()`
- Image rewriter uses `pdf_image_rewriter_options` with `char*` quality strings
- Merge uses `pdf_graft_map` for page copying between documents

## File Persistence

Compressed/Merged/Split files are stored in app's Documents directory:
- Paths stored as relative paths in UserDefaults (survives container UUID changes)
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
