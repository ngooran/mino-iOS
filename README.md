# Mino - PDF Compressor

**PDFs, made light.**

Mino is an iOS app that compresses PDF files (especially image-heavy PDFs) using the MuPDF library. It runs entirely offline - your files never leave your device.

## Features

- **Powerful Compression**: Achieve 60-95% file size reduction on image-heavy PDFs
- **Quality Presets**: Choose between Low, Medium, and High quality presets
- **Advanced Mode**: Fine-tune JPEG quality, DPI, and cleanup settings
- **Complete Privacy**: All processing happens on-device, no server uploads
- **Simple Interface**: Clean SwiftUI design with drag-and-drop support
- **Open Source**: Licensed under AGPL-3.0 with App Store Exception

## Expected Results

| Quality | JPEG Quality | Target DPI | Expected Reduction |
|---------|--------------|------------|-------------------|
| Low     | 30%          | 72         | 85-95%            |
| Medium  | 50%          | 100        | 75-85%            |
| High    | 70%          | 150        | 60-75%            |

For a 100MB image-heavy PDF:
- **Low**: ~5-15MB
- **Medium**: ~15-25MB
- **High**: ~25-40MB

## Requirements

- iOS 18.0+
- Xcode 16.0+
- macOS Sonoma or later (for building)

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
├── App/                    # App entry point and state
├── Core/
│   ├── MuPDF/              # MuPDF C wrapper and Swift bridge
│   └── Models/             # Data models
├── Features/
│   ├── Import/             # PDF import handling
│   ├── Compression/        # Compression service
│   └── Export/             # Export and sharing
└── UI/
    ├── Components/         # SwiftUI views
    └── Styles/             # Theme and styling
```

## How It Works

1. **Import**: Select a PDF from Files app, Share Sheet, or drag-and-drop
2. **Analyze**: MuPDF opens and analyzes the document
3. **Compress**: Images are recompressed and downsampled based on quality level
4. **Clean**: Unused objects are removed (garbage collection)
5. **Save**: Optimized PDF is saved with stream compression

## Technology Stack

- **Swift 5.9+** with SwiftUI
- **MuPDF** - High-performance PDF library (AGPL-3.0)
- **MVVM Architecture** with Swift Observation

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
