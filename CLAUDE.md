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
- `CompressionSettings` - Holds compression parameters (preset or custom)

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
