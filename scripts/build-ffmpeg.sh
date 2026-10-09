#!/bin/sh
# Builds the minimal universal ffmpeg bundled in utubmp3.app (utubmp3/Resources/bin/ffmpeg).
# Only what utubmp3 needs: decode YouTube audio (Opus, AAC, Vorbis, MP3), encode MP3
# with LAME, convert thumbnails (WebP/PNG -> JPEG), and rewrite ID3 tags.
# LGPL build (no --enable-gpl): FFmpeg and LAME are both LGPL.
#
# Usage: ./scripts/build-ffmpeg.sh    # needs Xcode command line tools only
set -eu

FFMPEG_VERSION="${FFMPEG_VERSION:-9.0.2}"
LAME_VERSION="3.100"
MIN_MACOS="13.0"

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
OUT="utubmp3/Resources/bin"
WORK="${WORK:-$(mktemp -d)}"
JOBS="$(sysctl -n hw.ncpu)"
mkdir -p "$OUT" "$WORK"

cd "$WORK"
[ -f "ffmpeg-$FFMPEG_VERSION.tar.xz" ] ||
    curl -fsSL "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz" -o "ffmpeg-$FFMPEG_VERSION.tar.xz"
[ -f "lame-$LAME_VERSION.tar.gz" ] ||
    curl -fsSL "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" -o "lame-$LAME_VERSION.tar.gz"

for arch in arm64 x86_64; do
    case "$arch" in
        arm64) host="aarch64-apple-darwin"; asm="" ;;
        x86_64) host="x86_64-apple-darwin"; asm="--disable-x86asm" ;;  # no nasm needed
    esac
    prefix="$WORK/prefix-$arch"
    cflags="-arch $arch -mmacosx-version-min=$MIN_MACOS -O2"

    echo "lame ($arch)…"
    rm -rf "lame-$arch" && mkdir "lame-$arch"
    tar -xzf "lame-$LAME_VERSION.tar.gz" -C "lame-$arch" --strip-components 1
    # lame 3.100 exports a symbol that no longer exists; harmless for static builds but breaks the link step
    sed -i '' '/lame_init_old/d' "lame-$arch/include/libmp3lame.sym"
    (cd "lame-$arch" &&
        CFLAGS="$cflags" LDFLAGS="-arch $arch" ./configure --host="$host" --prefix="$prefix" \
            --disable-shared --enable-static --disable-frontend --disable-decoder --disable-dependency-tracking >/dev/null &&
        make -j"$JOBS" >/dev/null && make install >/dev/null)

    echo "ffmpeg ($arch)…"
    rm -rf "ffmpeg-$arch" && mkdir "ffmpeg-$arch"
    tar -xJf "ffmpeg-$FFMPEG_VERSION.tar.xz" -C "ffmpeg-$arch" --strip-components 1
    # shellcheck disable=SC2086
    (cd "ffmpeg-$arch" && ./configure \
        --arch="$arch" --target-os=darwin --enable-cross-compile --cc=clang $asm \
        --extra-cflags="$cflags -I$prefix/include" --extra-ldflags="-arch $arch -mmacosx-version-min=$MIN_MACOS -L$prefix/lib" \
        --disable-everything --disable-autodetect --disable-doc --disable-debug --disable-network \
        --disable-ffplay --disable-ffprobe --disable-avdevice --enable-small \
        --enable-libmp3lame --enable-zlib \
        --enable-protocol=file,pipe \
        --enable-demuxer=mov,matroska,ogg,mp3,aac,wav,flac,image2,ffmetadata,image_webp_pipe,image_jpeg_pipe,image_png_pipe \
        --enable-decoder=opus,aac,aac_latm,vorbis,mp3,mp3float,flac,pcm_s16le,webp,vp8,mjpeg,png \
        --enable-encoder=libmp3lame,mjpeg,png \
        --enable-muxer=mp3,mov,mp4,ipod,image2,ffmetadata,null \
        --enable-parser=aac,opus,vorbis,mpegaudio,flac,mjpeg,png,webp,vp8 \
        --enable-filter=aresample,aformat,anull,null,format,scale,crop,copy \
        >/dev/null &&
        make -j"$JOBS" ffmpeg >/dev/null)
done

lipo -create "ffmpeg-arm64/ffmpeg" "ffmpeg-x86_64/ffmpeg" -output "$ROOT/$OUT/ffmpeg"
strip -x "$ROOT/$OUT/ffmpeg"
codesign --force --sign - "$ROOT/$OUT/ffmpeg" 2>/dev/null || true
"$ROOT/$OUT/ffmpeg" -hide_banner -version | head -1
ls -lh "$ROOT/$OUT/ffmpeg"
