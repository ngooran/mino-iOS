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

Mino is an iOS PDF compressor that uses MuPDF (C library) via Swift bridging.

### Core Data Flow

```
User selects PDF → DocumentImporter → PDFDocumentInfo
                                           ↓
                    CompressionService ← AppState.startCompression()
                                           ↓
                    PDFCompressor (Swift) → mino_compress_pdf() (C)
                                           ↓
                    CompressionResult → ResultsView
```

### Key Components

**AppState** (`Mino/App/AppState.swift`)
- Central `@Observable` state container
- Holds services: `documentImporter`, `compressionService`, `exportService`
- Manages navigation state and imported documents
- Injected via SwiftUI environment

**MuPDF Integration** (`Mino/Core/MuPDF/`)
- `MuPDFHelpers.h/.c` - C wrapper functions for MuPDF API
- `Mino-Bridging-Header.h` - Exposes C functions to Swift
- `PDFCompressor.swift` - Swift interface calling C helpers
- `MuPDFRenderer.swift` - Renders PDF pages to UIImage for viewer
- `CompressionSettings` - Holds compression parameters (preset or custom)

**History & Statistics** (`Mino/Features/History/`)
- `HistoryManager` - Singleton tracking compression stats (persisted to UserDefaults)
- Cleared automatically when `CompressionService.clearAllResults()` is called

**PDF Viewer** (`Mino/Features/Viewer/`)
- `PDFViewerView` - Full-screen viewer with page navigation and zoom
- Uses MuPDFRenderer for page rendering

**Compression Pipeline**
1. `CompressionService.compress()` creates a `CompressionJob`
2. Runs `PDFCompressor.compress()` on background thread
3. C helper `mino_compress_pdf()` calls MuPDF functions:
   - `pdf_rewrite_images()` - Recompress/downsample images
   - `pdf_save_document()` - Write with garbage collection

### Models

- `CompressionQuality` - Presets (Low/Medium/High) with JPEG quality and DPI
- `CompressionSettings` - Full settings including custom values
- `CompressionResult` - Output file info, sizes, duration
- `PDFDocumentInfo` - Input document metadata

## UI & Theming

**Theme** (`Mino/UI/Styles/Theme.swift`)
- Dark theme with color hierarchy: `minoBackground` → `minoCardBackground`
- Accent color: `minoAccent` (teal), Success: `minoSuccess` (green)
- Glass modifiers: `minoGlass()`, `minoGlassAccentButton()` for iOS 26 Liquid Glass
- Falls back to solid backgrounds on iOS < 26

**App Icon** (`Mino/Resources/AppIconDesign.swift`)
- SwiftUI Canvas-based icon design
- Three variants: Main (gradient), Dark (black), Tinted (monochrome)
- Export via `AppIconExportView`

## MuPDF C API Notes

The C helpers in `MuPDFHelpers.c` wrap MuPDF's error handling:
- MuPDF uses `fz_try/fz_catch` macros (setjmp/longjmp-based)
- All MuPDF calls require an `fz_context*`
- PDF operations need `pdf_document*` from `pdf_specifics()`
- Image rewriter uses `pdf_image_rewriter_options` with `char*` quality strings

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
