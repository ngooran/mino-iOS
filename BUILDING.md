# Building Mino

This guide explains how to build Mino from source.

## Prerequisites

- **macOS** Ventura (13.0) or later
- **Xcode** 15.0 or later
- **Command Line Tools**: `xcode-select --install`
- **Git** with submodule support

## Step 1: Clone the Repository

```bash
git clone https://github.com/yourusername/mino.git
cd mino
```

## Step 2: Initialize Submodules

MuPDF is included as a git submodule. Initialize it:

```bash
git submodule update --init --recursive
```

This downloads the MuPDF source code and its dependencies.

## Step 3: Build MuPDF for iOS

Run the build script to compile MuPDF for iOS:

```bash
chmod +x Scripts/build_mupdf_ios.sh
./Scripts/build_mupdf_ios.sh
```

This script:
1. Builds MuPDF for iOS device (arm64)
2. Builds MuPDF for iOS Simulator (arm64 + x86_64)
3. Creates universal binaries
4. Packages everything into XCFrameworks

The build process takes 10-20 minutes depending on your machine.

### Build Output

After successful build, you'll have:
- `Frameworks/MuPDF.xcframework` - Main MuPDF library
- `Frameworks/MuPDFThird.xcframework` - Third-party dependencies

## Step 4: Configure Xcode Project

1. Open `Mino.xcodeproj` in Xcode
2. Add the XCFrameworks to your project:
   - Drag `MuPDF.xcframework` and `MuPDFThird.xcframework` into the project
   - Set "Embed" to "Do Not Embed" (they're static libraries)
3. Configure Build Settings:
   - **Header Search Paths**: Add `$(PROJECT_DIR)/Frameworks/mupdf/include`
   - **Other Linker Flags**: Add `-lz`
   - **Swift Compiler - Objective-C Bridging Header**: Set to `Mino/Core/MuPDF/Mino-Bridging-Header.h`

## Step 5: Build and Run

1. Select your target device or simulator
2. Press Cmd+R to build and run

## Troubleshooting

### MuPDF Build Fails

If the MuPDF build fails:

1. **Check Xcode installation**:
   ```bash
   xcode-select -p
   # Should show: /Applications/Xcode.app/Contents/Developer
   ```

2. **Check SDKs are available**:
   ```bash
   xcrun --sdk iphoneos --show-sdk-path
   xcrun --sdk iphonesimulator --show-sdk-path
   ```

3. **Clean and rebuild**:
   ```bash
   rm -rf build/
   ./Scripts/build_mupdf_ios.sh
   ```

### Linker Errors

If you get undefined symbol errors:

1. Ensure both XCFrameworks are added to the project
2. Verify `-lz` is in "Other Linker Flags"
3. Check that frameworks are linked in "Build Phases" > "Link Binary With Libraries"

### Bridging Header Not Found

If Swift can't find the bridging header:

1. Verify the path in Build Settings is correct
2. The bridging header should be at: `Mino/Core/MuPDF/Mino-Bridging-Header.h`

### Simulator vs Device

- The XCFramework includes both device and simulator architectures
- Build for simulator with Cmd+R
- Build for device by selecting a real device

## Project Structure

```
mino/
├── Mino.xcodeproj          # Xcode project
├── Mino/                   # Source code
│   ├── App/                # App entry point
│   ├── Core/               # Core logic and MuPDF wrapper
│   ├── Features/           # Feature modules
│   └── UI/                 # SwiftUI views
├── Frameworks/
│   ├── mupdf/              # MuPDF source (submodule)
│   ├── MuPDF.xcframework   # Built framework (after build)
│   └── MuPDFThird.xcframework
├── Scripts/
│   └── build_mupdf_ios.sh  # Build script
├── LICENSE                 # AGPL-3.0 + App Store Exception
└── README.md
```

## Development Workflow

### Running Tests

```bash
# Run tests from command line
xcodebuild test -scheme Mino -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Creating a Release Build

1. Set the version number in the target's General settings
2. Select "Any iOS Device" as the destination
3. Product > Archive
4. Follow the distribution workflow

## Contributing

When contributing:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Ensure the build succeeds
5. Submit a pull request

## License Compliance

Remember that MuPDF is licensed under AGPL-3.0. Any modifications to MuPDF or the wrapper code must be made available under the same license.
