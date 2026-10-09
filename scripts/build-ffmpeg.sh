#!/bin/sh
# Builds the minimal ffmpeg bundled with utubmp3:
#   macOS (default):     universal utubmp3/Resources/bin/ffmpeg, for utubmp3.app
#   TARGET=windows:      x64 windows/bin/ffmpeg.exe, for the Windows installer
# Only what utubmp3 needs: decode YouTube audio (Opus, AAC, Vorbis, MP3), encode MP3
# with LAME, convert thumbnails (WebP -> PNG), and rewrite ID3 tags.
# LGPL build (no --enable-gpl): FFmpeg, LAME and zlib are LGPL or more permissive.
#
# Usage: ./scripts/build-ffmpeg.sh                  # needs Xcode command line tools
#        TARGET=windows ./scripts/build-ffmpeg.sh   # also needs: brew install mingw-w64
set -eu

FFMPEG_VERSION="${FFMPEG_VERSION:-9.0.2}"
LAME_VERSION="3.100"
ZLIB_VERSION="1.3.1"
MIN_MACOS="13.0"
TARGET="${TARGET:-macos}"
EXE=""
[ "$TARGET" = "windows" ] && EXE=".exe"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
WORK="${WORK:-$(mktemp -d)}"
JOBS="$(sysctl -n hw.ncpu)"
mkdir -p "$WORK"

cd "$WORK"
[ -f "ffmpeg-$FFMPEG_VERSION.tar.xz" ] ||
    curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o "ffmpeg-$FFMPEG_VERSION.tar.xz"
[ -f "lame-$LAME_VERSION.tar.gz" ] ||
    curl -fsSL "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" -o "lame-$LAME_VERSION.tar.gz"

FFMPEG_FEATURES="--disable-everything --disable-autodetect --disable-doc --disable-debug --disable-network
    --disable-ffplay --disable-ffprobe --disable-avdevice --enable-small
    --enable-libmp3lame --enable-zlib
    --enable-protocol=file,pipe
    --enable-demuxer=mov,matroska,ogg,mp3,aac,wav,flac,image2,ffmetadata,image_webp_pipe,image_jpeg_pipe,image_png_pipe
    --enable-decoder=opus,aac,aac_latm,vorbis,mp3,mp3float,flac,pcm_s16le,webp,vp8,mjpeg,png
    --enable-encoder=libmp3lame,mjpeg,png
    --enable-muxer=mp3,mov,mp4,ipod,image2,ffmetadata,null
    --enable-parser=aac,opus,vorbis,mpegaudio,flac,mjpeg,png,webp,vp8
    --enable-filter=aresample,aformat,anull,null,format,scale,crop,copy"

# build_lame <name> <host> <prefix> <cflags> <ldflags> [CC]
build_lame() {
    echo "lame ($1)…"
    rm -rf "lame-$1" && mkdir "lame-$1"
    tar -xzf "lame-$LAME_VERSION.tar.gz" -C "lame-$1" --strip-components 1
    # lame 3.100 exports a symbol that no longer exists; harmless for static builds but breaks the link step
    sed -i '' '/lame_init_old/d' "lame-$1/include/libmp3lame.sym"
    (cd "lame-$1" &&
        CC="${6:-clang}" CFLAGS="$4" LDFLAGS="$5" ./configure --host="$2" --prefix="$3" \
            --disable-shared --enable-static --disable-frontend --disable-decoder --disable-dependency-tracking >/dev/null &&
        make -j"$JOBS" >/dev/null && make install >/dev/null)
}

# build_ffmpeg <name> <extra configure args…>
build_ffmpeg() {
    name="$1"; shift
    echo "ffmpeg ($name)…"
    rm -rf "ffmpeg-$name" && mkdir "ffmpeg-$name"
    tar -xJf "ffmpeg-$FFMPEG_VERSION.tar.xz" -C "ffmpeg-$name" --strip-components 1
    # shellcheck disable=SC2086
    (cd "ffmpeg-$name" && ./configure "$@" $FFMPEG_FEATURES >/dev/null && make -j"$JOBS" "ffmpeg$EXE" >/dev/null)
}

if [ "$TARGET" = "windows" ]; then
    CROSS="x86_64-w64-mingw32"
    prefix="$WORK/prefix-win64"
    OUT="$ROOT/windows/bin"
    mkdir -p "$OUT" "$prefix/lib" "$prefix/include"

    # Windows has no system zlib (PNG cover art needs it): build a static one.
    [ -f "zlib-$ZLIB_VERSION.tar.gz" ] ||
        curl -fsSL "https://zlib.net/fossils/zlib-$ZLIB_VERSION.tar.gz" -o "zlib-$ZLIB_VERSION.tar.gz"
    echo "zlib (win64)…"
    rm -rf zlib-win64 && mkdir zlib-win64
    tar -xzf "zlib-$ZLIB_VERSION.tar.gz" -C zlib-win64 --strip-components 1
    (cd zlib-win64 && make -f win32/Makefile.gcc PREFIX="$CROSS-" libz.a >/dev/null &&
        cp libz.a "$prefix/lib/" && cp zlib.h zconf.h "$prefix/include/")

    build_lame win64 "$CROSS" "$prefix" "-O2" "" "$CROSS-gcc"
    build_ffmpeg win64 --arch=x86_64 --target-os=mingw32 --cross-prefix="$CROSS-" --enable-cross-compile \
        --disable-x86asm --enable-w32threads --pkg-config=false \
        --extra-cflags="-O2 -I$prefix/include" --extra-ldflags="-static -L$prefix/lib"
    cp ffmpeg-win64/ffmpeg.exe "$OUT/ffmpeg.exe"
    "$CROSS-strip" "$OUT/ffmpeg.exe"
    ls -lh "$OUT/ffmpeg.exe"
    exit 0
fi

OUT="$ROOT/utubmp3/Resources/bin"
mkdir -p "$OUT"
for arch in arm64 x86_64; do
    case "$arch" in
        arm64) host="aarch64-apple-darwin"; asm="" ;;
        x86_64) host="x86_64-apple-darwin"; asm="--disable-x86asm" ;;  # no nasm needed
    esac
    prefix="$WORK/prefix-$arch"
    cflags="-arch $arch -mmacosx-version-min=$MIN_MACOS -O2"
    build_lame "$arch" "$host" "$prefix" "$cflags" "-arch $arch"
    # shellcheck disable=SC2086
    build_ffmpeg "$arch" --arch="$arch" --target-os=darwin --enable-cross-compile --cc=clang $asm \
        --extra-cflags="$cflags -I$prefix/include" --extra-ldflags="-arch $arch -mmacosx-version-min=$MIN_MACOS -L$prefix/lib"
done

lipo -create "ffmpeg-arm64/ffmpeg" "ffmpeg-x86_64/ffmpeg" -output "$OUT/ffmpeg"
strip -x "$OUT/ffmpeg"
codesign --force --sign - "$OUT/ffmpeg" 2>/dev/null || true
"$OUT/ffmpeg" -hide_banner -version | head -1
ls -lh "$OUT/ffmpeg"
