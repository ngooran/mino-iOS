#!/bin/bash
# Build script for MuPDF iOS libraries
# Creates XCFramework for both device and simulator

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MUPDF_DIR="$PROJECT_DIR/Frameworks/mupdf"
BUILD_DIR="$PROJECT_DIR/build"
OUTPUT_DIR="$PROJECT_DIR/Frameworks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== MuPDF iOS Build Script ===${NC}"
echo "MuPDF directory: $MUPDF_DIR"
echo "Build directory: $BUILD_DIR"
echo "Output directory: $OUTPUT_DIR"

# Check if MuPDF exists
if [ ! -d "$MUPDF_DIR" ]; then
    echo -e "${RED}Error: MuPDF not found at $MUPDF_DIR${NC}"
    echo "Please run: git submodule update --init"
    exit 1
fi

# Check if submodules are initialized
if [ ! -f "$MUPDF_DIR/thirdparty/freetype/CMakeLists.txt" ]; then
    echo -e "${YELLOW}Warning: MuPDF submodules may not be initialized${NC}"
    echo "Running: git submodule update --init"
    cd "$MUPDF_DIR"
    git submodule update --init
    cd "$PROJECT_DIR"
fi

# Clean previous builds
echo -e "${YELLOW}Cleaning previous builds...${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# iOS SDK paths
IOS_SDK=$(xcrun --sdk iphoneos --show-sdk-path)
SIM_SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
MIN_IOS_VERSION="16.0"

# Common build flags (bitcode is deprecated in Xcode 14+)
COMMON_CFLAGS="-DNDEBUG -Os -fPIC -fno-common"

# Function to build for a specific target
build_for_target() {
    local ARCH=$1
    local SDK=$2
    local PLATFORM=$3

    echo -e "${GREEN}Building for $PLATFORM ($ARCH)...${NC}"

    local TARGET_DIR="$BUILD_DIR/$PLATFORM-$ARCH"
    mkdir -p "$TARGET_DIR"

    cd "$MUPDF_DIR"

    # Set up cross-compilation environment
    export CC="$(xcrun --sdk $SDK --find clang)"
    export CXX="$(xcrun --sdk $SDK --find clang++)"
    export AR="$(xcrun --sdk $SDK --find ar)"
    export RANLIB="$(xcrun --sdk $SDK --find ranlib)"

    # Disable optional features at compile time
    local FEATURE_FLAGS="-DFZ_ENABLE_ICC=0 -DFZ_ENABLE_JS=0"

    if [ "$PLATFORM" = "iphoneos" ]; then
        export CFLAGS="$COMMON_CFLAGS $FEATURE_FLAGS -arch $ARCH -isysroot $SDK -miphoneos-version-min=$MIN_IOS_VERSION -target $ARCH-apple-ios$MIN_IOS_VERSION"
        export CXXFLAGS="$CFLAGS"
    else
        export CFLAGS="$COMMON_CFLAGS $FEATURE_FLAGS -arch $ARCH -isysroot $SDK -mios-simulator-version-min=$MIN_IOS_VERSION -target $ARCH-apple-ios$MIN_IOS_VERSION-simulator"
        export CXXFLAGS="$CFLAGS"
    fi

    export LDFLAGS="-arch $ARCH -isysroot $SDK"

    # Clean and build MuPDF
    make clean 2>/dev/null || true

    # Build with iOS-appropriate options (minimal dependencies)
    make \
        HAVE_X11=no \
        HAVE_GLUT=no \
        HAVE_CURL=no \
        HAVE_LIBCRYPTO=no \
        HAVE_PTHREAD=yes \
        HAVE_LEPTONICA=no \
        HAVE_TESSERACT=no \
        HAVE_LCMS2=no \
        HAVE_MUJS=no \
        HAVE_EXTRACT=no \
        USE_SYSTEM_FREETYPE=no \
        USE_SYSTEM_HARFBUZZ=no \
        USE_SYSTEM_LIBJPEG=no \
        USE_SYSTEM_ZLIB=no \
        USE_SYSTEM_OPENJPEG=no \
        USE_SYSTEM_JBIG2DEC=no \
        XCFLAGS="$FEATURE_FLAGS" \
        build=release \
        verbose=no \
        libs -j$(sysctl -n hw.ncpu)

    # Copy built libraries
    mkdir -p "$TARGET_DIR/lib"
    cp build/release/libmupdf.a "$TARGET_DIR/lib/" 2>/dev/null || true
    cp build/release/libmupdf-third.a "$TARGET_DIR/lib/" 2>/dev/null || true

    # If separate libs don't exist, look for combined
    if [ ! -f "$TARGET_DIR/lib/libmupdf.a" ]; then
        # Try alternative locations
        find build -name "*.a" -exec cp {} "$TARGET_DIR/lib/" \; 2>/dev/null || true
    fi

    cd "$PROJECT_DIR"

    echo -e "${GREEN}Built for $PLATFORM ($ARCH)${NC}"
}

# Build for all targets
echo -e "${GREEN}Starting builds...${NC}"

build_for_target "arm64" "$IOS_SDK" "iphoneos"
build_for_target "arm64" "$SIM_SDK" "iphonesimulator"
build_for_target "x86_64" "$SIM_SDK" "iphonesimulator-x86_64"

# Create fat library for simulator (arm64 + x86_64)
echo -e "${GREEN}Creating universal simulator library...${NC}"
mkdir -p "$BUILD_DIR/iphonesimulator-universal/lib"

# Check which libraries exist and create fat binaries
for lib in libmupdf.a libmupdf-third.a; do
    SIM_ARM64="$BUILD_DIR/iphonesimulator-arm64/lib/$lib"
    SIM_X86="$BUILD_DIR/iphonesimulator-x86_64/lib/$lib"
    UNIVERSAL="$BUILD_DIR/iphonesimulator-universal/lib/$lib"

    if [ -f "$SIM_ARM64" ] && [ -f "$SIM_X86" ]; then
        lipo -create "$SIM_ARM64" "$SIM_X86" -output "$UNIVERSAL"
        echo "Created universal $lib"
    elif [ -f "$SIM_ARM64" ]; then
        cp "$SIM_ARM64" "$UNIVERSAL"
        echo "Copied arm64 $lib (x86_64 not available)"
    fi
done

# Create XCFramework
echo -e "${GREEN}Creating XCFramework...${NC}"

DEVICE_LIB="$BUILD_DIR/iphoneos-arm64/lib/libmupdf.a"
SIM_LIB="$BUILD_DIR/iphonesimulator-universal/lib/libmupdf.a"
HEADERS="$MUPDF_DIR/include"

# Remove existing xcframeworks
rm -rf "$OUTPUT_DIR/MuPDF.xcframework"
rm -rf "$OUTPUT_DIR/MuPDFThird.xcframework"

if [ -f "$DEVICE_LIB" ] && [ -f "$SIM_LIB" ]; then
    xcodebuild -create-xcframework \
        -library "$DEVICE_LIB" \
        -headers "$HEADERS" \
        -library "$SIM_LIB" \
        -headers "$HEADERS" \
        -output "$OUTPUT_DIR/MuPDF.xcframework"

    echo -e "${GREEN}Created MuPDF.xcframework${NC}"
fi

# Create third-party XCFramework
DEVICE_THIRD="$BUILD_DIR/iphoneos-arm64/lib/libmupdf-third.a"
SIM_THIRD="$BUILD_DIR/iphonesimulator-universal/lib/libmupdf-third.a"

if [ -f "$DEVICE_THIRD" ] && [ -f "$SIM_THIRD" ]; then
    xcodebuild -create-xcframework \
        -library "$DEVICE_THIRD" \
        -library "$SIM_THIRD" \
        -output "$OUTPUT_DIR/MuPDFThird.xcframework"

    echo -e "${GREEN}Created MuPDFThird.xcframework${NC}"
fi

echo ""
echo -e "${GREEN}=== Build Complete ===${NC}"
echo "XCFrameworks created at: $OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "1. Add MuPDF.xcframework and MuPDFThird.xcframework to your Xcode project"
echo "2. Set 'Embed' to 'Do Not Embed' (static libraries)"
echo "3. Add -lz to 'Other Linker Flags'"
echo "4. Add \$(PROJECT_DIR)/Frameworks/mupdf/include to 'Header Search Paths'"
