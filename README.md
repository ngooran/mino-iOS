# Mino - PDF Compressor

**PDFs, made light.**

Mino is an iOS app that compresses, merges and splits PDF files using the MuPDF library. It runs entirely offline - your files never leave your device.

## Features

- **Powerful Compression**: Achieve 60-95% file size reduction on image-heavy PDFs, with the result size shown before you start
- **Quality Presets**: Smallest, Balanced and Best Quality, plus custom quality and resolution
- **Merge and Split**: Combine PDFs in any order, or extract any set of pages
- **Batch Compression**: Compress many PDFs at once
- **iPhone, iPad and iPhone Duo**: Native SwiftUI layout for each, including the Duo's book pose
- **Complete Privacy**: All processing happens on-device, no server uploads
- **Open Source**: Licensed under AGPL-3.0 with App Store Exception

## Free and Pro

Mino is a free download. Free use covers 3 single-file compressions a day. **Mino Pro**, a one-time in-app purchase, unlocks unlimited compressions, batch compression, merge, split and custom quality. People who bought the paid app (1.x) keep everything automatically.

## Expected Results

| Preset (in code) | JPEG Quality | Target DPI | Expected Reduction |
|------------------|--------------|------------|-------------------|
| Smallest (`low`) | 30%          | 72         | 85-95%            |
| Balanced (`medium`) | 50%       | 100        | 75-85%            |
| Best Quality (`high`) | 70%     | 150        | 60-75%            |

For a 100MB image-heavy PDF:
- **Smallest**: ~5-15MB
- **Balanced**: ~15-25MB
- **Best Quality**: ~25-40MB

## Requirements

- iOS 18.6+
- Xcode 27.1+ (needed for the iPhone Duo SDK and simulator)
- macOS with Xcode 27 support (for building)

## Building from Source

See [BUILDING.md](BUILDING.md) for detailed build instructions.

### Quick Start

```bash
# Clone the repository
git clone https://github.com/ngooran/mino-iOS.git
cd mino-iOS

# Initialize submodules
git submodule update --init --recursive

# Build MuPDF for iOS
./Scripts/build_mupdf_ios.sh

# Open in Xcode
open Mino.xcodeproj
```

## Architecture

```
Mino/
├── App/                    # AppState, navigation, task sessions, DEBUG demo launch
├── Core/
│   ├── MuPDF/              # MuPDF C wrapper and Swift bridge (compress, merge, split)
│   ├── Models/             # Data models
│   ├── OutputLocation.swift
│   └── StorageRoot.swift   # All persistence goes through here
├── Features/               # Import, compression, batch, merge/split, export, history, viewer
├── Store/                  # Mino Pro (StoreKit 2) and the free daily limit
└── UI/
    ├── Root/               # Tabs and adaptive navigation (iPhone, iPad, iPhone Duo)
    ├── Home/ Files/ Settings/ Tasks/ Paywall/
    ├── Components/         # Shared views, thumbnails, fold awareness
    └── Styles/             # Theme
MinoShare/                  # Share Extension
```

More detail for contributors is in [CLAUDE.md](CLAUDE.md). The release plan for 2.0 is in [RELEASE-2.0.md](RELEASE-2.0.md).

## How It Works

1. **Import**: Select a PDF from the Files app, the Share Sheet, or drag and drop
2. **Analyze**: MuPDF opens and analyzes the document
3. **Compress**: Images are recompressed and downsampled based on quality level
4. **Clean**: Unused objects are removed (garbage collection)
5. **Save**: Optimized PDF is saved with stream compression

## Technology Stack

- **Swift** with SwiftUI and Swift Observation
- **StoreKit 2** for the Mino Pro purchase
- **MuPDF** - High-performance PDF library (AGPL-3.0)

## License

This project is licensed under the **GNU Affero General Public License v3.0** with an **App Store Exception**.

### What this means:

- You can use, modify, and distribute this software
- Source code must remain open source
- Modifications must be shared under the same license
- The App Store Exception allows distribution through Apple's App Store

### Third-Party Licenses

- **MuPDF**: [AGPL-3.0](https://www.gnu.org/licenses/agpl-3.0.html) (by [Artifex Software](https://artifex.com))

See [LICENSE](LICENSE) for the full license text.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## Acknowledgments

- [MuPDF](https://mupdf.com) by Artifex Software for the excellent PDF library
- The open source community for inspiration and tools

## Support

If you encounter issues or have questions:

1. Check the [Issues](https://github.com/ngooran/mino-iOS/issues) page
2. Open a new issue with details about your problem
3. Include device model, iOS version, and steps to reproduce

---

Made with care for privacy and performance.
