#!/bin/bash
set -euxo pipefail

# Official CPU SDK archives: headers + libnemo_speech_asr_c (no local compile).
# Pin: NEMO_SPEECH_VERSION + SHA (Makefile / Docker build-arg). Bump both to upgrade.
# https://github.com/NVIDIA/NeMo-Speech.cpp/releases
NEMO_SPEECH_VERSION=${1:-0.1.0}
PREFIX=${2:-/opt/nemo-speech}
TARGET_ARCH=${3:-amd64}
NEMO_SPEECH_SHA=${4:?NEMO_SPEECH_SHA is required}

case "$TARGET_ARCH" in
	amd64|x86_64)
		ARCH=x86_64
		;;
	arm64|aarch64)
		ARCH=aarch64
		;;
	*)
		echo "unsupported TARGET_ARCH=$TARGET_ARCH" >&2
		exit 1
		;;
esac

ARCHIVE="nemo-speech-${NEMO_SPEECH_VERSION}-linux-${ARCH}-cpu.tar.gz"
URL="https://github.com/NVIDIA/NeMo-Speech.cpp/releases/download/v${NEMO_SPEECH_VERSION}/${ARCHIVE}"

fetch() {
	local url=$1 file=$2 sha=$3
	if [ -f "$file" ] && echo "$sha  $file" | sha256sum --check --status; then
		echo "using cached $file"
		return
	fi
	rm -f "$file"
	wget -O "$file" --tries=3 --timeout=60 "$url"
	echo "$sha  $file" | sha256sum --check
}

cd /tmp
fetch "$URL" "$ARCHIVE" "$NEMO_SPEECH_SHA"
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
tar xf "$ARCHIVE"
mv "nemo-speech-${NEMO_SPEECH_VERSION}-linux-${ARCH}-cpu"/* "$PREFIX/"
rmdir "nemo-speech-${NEMO_SPEECH_VERSION}-linux-${ARCH}-cpu"
# Archive ships libstdc++/libgcc/libgomp. Keep them: NeMo loads them via $ORIGIN rpath
# (fix_parakeet_libs.sh). Whisper keeps using the base image runtimes.
test -e "$PREFIX/lib/libstdc++.so.6"
test -e "$PREFIX/lib/libgcc_s.so.1"
test -f "$PREFIX/include/nemo_speech/asr.h"
test -f "$PREFIX/lib/libnemo_speech_asr_c.so"
