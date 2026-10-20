#!/bin/sh
set -e
set -x


declare -a libs=("OpenH264" "OpenSSL" "libopus" "libvpx" "mozjpeg" "libwebp" "dav1d" "ffmpeg" "webrtc" "tde2e" "wallet-engine" "mtproto-engine")
declare -a libname=("OpenH264" "OpenSSLEncryption" "libopus" "libvpx" "Mozjpeg" "libwebp" "dav1d" "ffmpeg" "webrtc" "tde2e" "WalletEngine" "MTProtoEngine")

arraylength=${#libs[@]}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
ROOT_DIR="$( cd "$SCRIPT_DIR/.." >/dev/null && pwd )"

. "$SCRIPT_DIR/framework-inputs.sh"


mkdir -p "$SCRIPT_DIR/../submodules/telegram-ios/submodules/TelegramCore/FlatSerialization/Sources"

sh $SCRIPT_DIR/../submodules/telegram-ios/submodules/TelegramCore/FlatSerialization/macOS/generate.sh --input $SCRIPT_DIR/../submodules/telegram-ios/submodules/TelegramCore/FlatSerialization/Models --output $SCRIPT_DIR/../submodules/telegram-ios/submodules/TelegramCore/FlatSerialization/Sources --binary $SCRIPT_DIR/../scripts/flatc


RebuildFile="${SCRIPT_DIR}/rebuild"

FORCE_REBUILD="no"
if grep -q yes "$RebuildFile"; then
    FORCE_REBUILD="yes"
fi

STAMP_CACHE="$( mktemp -d )"

for (( i=0; i<${arraylength}; i++ ));
do
    LIB=${libs[$i]}
    BUILD_DIR="$(framework_build_dir "$ROOT_DIR" "$LIB")"
    STAMP_FILE="$BUILD_DIR/.framework-stamp"
    framework_stamp "$ROOT_DIR" "$LIB" "$STAMP_CACHE" > "$STAMP_CACHE/$LIB"

    if [ "$FORCE_REBUILD" = "yes" ]; then
        echo "framework-stamp: $LIB forced by scripts/rebuild"
        rm -rf "$BUILD_DIR"
        framework_reset_outputs "$ROOT_DIR" "$LIB"
    elif [ ! -d "$BUILD_DIR" ]; then
        echo "framework-stamp: $LIB has no build output yet"
    elif [ ! -f "$STAMP_FILE" ]; then
        echo "framework-stamp: $LIB adopted without rebuilding, stamp recorded from the current output"
        cp "$STAMP_CACHE/$LIB" "$STAMP_FILE"
    elif ! cmp -s "$STAMP_CACHE/$LIB" "$STAMP_FILE"; then
        echo "framework-stamp: $LIB inputs changed, rebuilding"
        diff "$STAMP_FILE" "$STAMP_CACHE/$LIB" | sed 's/^/framework-stamp:   /' || true
        rm -rf "$BUILD_DIR"
        framework_reset_outputs "$ROOT_DIR" "$LIB"
    else
        echo "framework-stamp: $LIB is up to date"
    fi

    if [ -d "$BUILD_DIR" ] && ! framework_outputs_consistent "$ROOT_DIR" "$LIB"; then
        echo "framework-stamp: $LIB outputs do not match the library in its build directory, regenerating them"
        framework_reset_outputs "$ROOT_DIR" "$LIB"
    fi
done



for (( i=0; i<${arraylength}; i++ ));
do
    FWNAME=${libname[$i]}
    LIB=${libs[$i]}
    SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
    BASE_PWD="${SCRIPT_DIR}/../submodules/${LIB}"
    OUTPUT_DIR=$( mktemp -d )

    COMMON_SETUP=" -project ${SCRIPT_DIR}/../core-xprojects/${LIB}/${FWNAME}.xcodeproj -configuration Release BUILD_LIBRARY_FOR_DISTRIBUTION=YES "


    DERIVED_DATA_PATH=$( mktemp -d )
    xcrun xcodebuild build \
        $COMMON_SETUP \
        -scheme "${FWNAME}" \
        -derivedDataPath "${DERIVED_DATA_PATH}" \
        -destination 'generic/platform=macOS'

    BUILD_DIR="$(framework_build_dir "$ROOT_DIR" "$LIB")"
    mkdir -p "$BUILD_DIR"
    cp "$STAMP_CACHE/$LIB" "$BUILD_DIR/.framework-stamp"

done

for (( i=0; i<${arraylength}; i++ ));
do
    LIB=${libs[$i]}
    if ! framework_outputs_consistent "$ROOT_DIR" "$LIB"; then
        echo "error: $LIB outputs still do not match its library after the build"
        exit 1
    fi
done




DIRECTORY_PAIRS=(
    "${SCRIPT_DIR}/../core-xprojects/libopus/build/libopus/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpusBinding/SharedHeaders/libopus/include"
    "${SCRIPT_DIR}/../core-xprojects/ffmpeg/build/ffmpeg/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/FFMpegBinding/SharedHeaders/ffmpeg/include"
    "${SCRIPT_DIR}/../core-xprojects/webrtc/build/src,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/webrtc"
    "${SCRIPT_DIR}/../core-xprojects/openssl/build/openssl/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/openssl/include"
    "${SCRIPT_DIR}/../core-xprojects/libopus/build/libopus/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/libopus/include"
    "${SCRIPT_DIR}/../core-xprojects/ffmpeg/build/ffmpeg/include,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/ffmpeg/include"
    "${SCRIPT_DIR}/../submodules/telegram-ios/third-party/rnnoise/PublicHeaders,${SCRIPT_DIR}/../submodules/tgcalls/SharedHeaders/rnoise"
    "${SCRIPT_DIR}/../core-xprojects/libwebp/build/libwebp/include,${SCRIPT_DIR}/../submodules/libwebp/SharedHeaders/libwebp/include"
    "${SCRIPT_DIR}/../core-xprojects/openssl/build/openssl/include,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpenSSLEncryptionProvider/SharedHeaders/openssl/include"
    "${SCRIPT_DIR}/../submodules/telegram-ios/submodules/EncryptionProvider/PublicHeaders,${SCRIPT_DIR}/../submodules/telegram-ios/submodules/OpenSSLEncryptionProvider/SharedHeaders/EncryptionProvider"
    "${SCRIPT_DIR}/../core-xprojects/Mozjpeg/build,${SCRIPT_DIR}/../submodules/Mozjpeg/SharedHeaders/libmozjpeg"
    "${SCRIPT_DIR}/../submodules/telegram-ios/third-party/mozjpeg/mozjpeg,${SCRIPT_DIR}/../submodules/Mozjpeg/SharedHeaders/ios-mozjpeg"
)


# Loop through each pair and process them
for pair in "${DIRECTORY_PAIRS[@]}"; do
    # Split the pair into source and destination variables
    IFS=',' read -r SOURCE_DIR DEST_DIR <<< "$pair"

    # Ensure the source directory exists
    if [ ! -d "$SOURCE_DIR" ]; then
        echo "Source directory $SOURCE_DIR does not exist. Skipping."
        continue
    fi

    # Clean the destination directory if it exists
    if [ -d "$DEST_DIR" ]; then
        echo "Cleaning the destination directory: $DEST_DIR"
        rm -rf "$DEST_DIR"
    fi

    # Recreate the destination directory
    mkdir -p "$DEST_DIR"

    # Use rsync to copy only .h files while preserving the directory structure
    echo "Copying .h header files from $SOURCE_DIR to $DEST_DIR while preserving folder structure..."
    rsync -av --include='*/' --include='*.h' --exclude='*' "$SOURCE_DIR/" "$DEST_DIR/"

    echo "Headers copied successfully from $SOURCE_DIR to $DEST_DIR!"
done



sh $SCRIPT_DIR/../submodules/telegram-ios/third-party/td/macos-cleanup.sh $SCRIPT_DIR/../submodules/telegram-ios/third-party/td/td $SCRIPT_DIR/../submodules/telegram-ios/third-party/td/TdBinding/SharedHeaders
