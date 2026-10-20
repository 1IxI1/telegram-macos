#!/bin/bash

FRAMEWORK_STAMP_SCHEMA=1

framework_project_dir() {
    MATCH="$(ls "$1/core-xprojects" 2>/dev/null | awk -v n="$2" 'tolower($0) == tolower(n) { print; exit }')"
    if [ -n "$MATCH" ]; then
        echo "$1/core-xprojects/$MATCH"
    else
        echo "$1/core-xprojects/$2"
    fi
}

framework_build_dir() {
    echo "$(framework_project_dir "$1" "$2")/build"
}

framework_source_roots() {
    case "$2" in
        OpenSSL)
            echo "$1/submodules/telegram-ios/submodules/openssl"
            ;;
        mozjpeg)
            echo "$1/submodules/telegram-ios/third-party/mozjpeg/mozjpeg"
            ;;
        dav1d)
            echo "$1/submodules/telegram-ios/third-party/dav1d/dav1d"
            ;;
        ffmpeg)
            echo "$1/submodules/telegram-ios/submodules/ffmpeg/Sources/FFMpeg"
            ;;
        webrtc)
            echo "$1/submodules/tg_owt"
            ;;
        tde2e)
            echo "$1/submodules/telegram-ios/third-party/td/td"
            ;;
        wallet-engine)
            echo "$1/submodules/telegram-ios/third-party/wallet-engine/wallet-engine"
            ;;
        mtproto-engine)
            echo "$1/submodules/telegram-ios/third-party/mtproto-engine"
            ;;
        *)
            ;;
    esac
}

framework_inputs() {
    framework_project_dir "$1" "$2"
    framework_source_roots "$1" "$2"
}

framework_dependencies() {
    case "$1" in
        ffmpeg) echo "libopus libvpx dav1d" ;;
        webrtc) echo "OpenH264 OpenSSL mozjpeg libopus libvpx ffmpeg" ;;
        tde2e) echo "OpenSSL" ;;
        *) echo "" ;;
    esac
}

framework_extra_fingerprint() {
    case "$1" in
        wallet-engine|mtproto-engine)
            CARGO_BIN=""
            if [ -n "${CARGO:-}" ]; then
                CARGO_BIN="$CARGO"
            elif command -v cargo >/dev/null 2>&1; then
                CARGO_BIN="$(command -v cargo)"
            elif [ -x "$HOME/.cargo/bin/cargo" ]; then
                CARGO_BIN="$HOME/.cargo/bin/cargo"
            fi
            if [ -n "$CARGO_BIN" ]; then
                echo "rust=$("$CARGO_BIN" --version 2>/dev/null || echo unavailable)"
            else
                echo "rust=missing"
            fi
            ;;
        *)
            ;;
    esac
}

framework_reset_outputs() {
    case "$2" in
        wallet-engine)
            rm -rf "$1/packages/WalletEngine/wallet_engineFFI.xcframework"
            ;;
        mtproto-engine)
            rm -rf "$1/submodules/telegram-ios/submodules/MTProtoRustEngine/MTProtoEngineFFI.xcframework"
            ;;
        *)
            ;;
    esac
}

framework_outputs_consistent() {
    case "$2" in
        wallet-engine)
            sh "$1/scripts/check-wallet-engine-bindings.sh" "$1"
            ;;
        *)
            ;;
    esac
}

framework_path_fingerprint() {
    TARGET="$1"
    if [ ! -e "$TARGET" ]; then
        echo "missing"
        return
    fi
    if [ -f "$TARGET" ]; then
        shasum -a 256 "$TARGET" | cut -d' ' -f1
        return
    fi
    if git -C "$TARGET" rev-parse --show-toplevel >/dev/null 2>&1; then
        TREE="$(git -C "$TARGET" rev-parse 'HEAD:./' 2>/dev/null || echo untracked)"
        DIRTY="$(git -C "$TARGET" status --porcelain -- . 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"
        echo "$TREE.${DIRTY:0:12}"
        return
    fi
    find "$TARGET" -type f -exec shasum -a 256 {} + 2>/dev/null | sort | shasum -a 256 | cut -d' ' -f1
}

framework_stamp() {
    ROOT="$1"
    LIB="$2"
    CACHE_DIR="$3"
    echo "schema=$FRAMEWORK_STAMP_SCHEMA"
    echo "lib=$LIB"
    echo "xcode=$(xcodebuild -version 2>/dev/null | tr '\n' ' ')"
    echo "deployment=${MACOSX_DEPLOYMENT_TARGET:-default}"
    framework_extra_fingerprint "$LIB"
    while IFS= read -r INPUT; do
        [ -n "$INPUT" ] || continue
        echo "input:${INPUT#$ROOT/}=$(framework_path_fingerprint "$INPUT")"
    done <<< "$(framework_inputs "$ROOT" "$LIB")"
    for DEP in $(framework_dependencies "$LIB"); do
        DEP_STAMP="$CACHE_DIR/$DEP"
        if [ -f "$DEP_STAMP" ]; then
            echo "dependency:$DEP=$(shasum -a 256 "$DEP_STAMP" | cut -d' ' -f1)"
        else
            echo "dependency:$DEP=uncomputed"
        fi
    done
}
