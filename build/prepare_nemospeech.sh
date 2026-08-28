#!/bin/bash
set -ex

# Official CPU SDK archives: headers + libnemo_speech_asr_c (no local compile).
# Pin: NEMO_SPEECH_VERSION. Bump that (Makefile / Docker ARG) to upgrade.
# https://github.com/NVIDIA/NeMo-Speech.cpp/releases
NEMO_SPEECH_VERSION=${1:-0.1.0}
PREFIX=${2:-/opt/nemo-speech}
TARGET_ARCH=${3:-amd64}

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

cd /tmp
wget -O "$ARCHIVE" "$URL"
rm -rf "$PREFIX"
mkdir -p "$PREFIX"
tar xf "$ARCHIVE"
mv "nemo-speech-${NEMO_SPEECH_VERSION}-linux-${ARCH}-cpu"/* "$PREFIX/"
rmdir "nemo-speech-${NEMO_SPEECH_VERSION}-linux-${ARCH}-cpu"
# Archive ships libstdc++/libgcc/libgomp. LD_LIBRARY_PATH must stay on PREFIX/lib
# so NeMo libggml wins over Whisper's copy (same SONAME). Those runtimes would
# shadow Debian's and break libwhisper (GLIBCXX_3.4.29).
find "$PREFIX/lib" -maxdepth 1 \( \
	-name 'libstdc++.so*' -o -name 'libgcc_s.so*' -o -name 'libgomp.so*' \
\) -delete
test -f "$PREFIX/include/nemo_speech/asr.h"
test -f "$PREFIX/lib/libnemo_speech_asr_c.so"
