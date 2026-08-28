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
# Archive ships libstdc++/libgcc/libgomp. Keep them: NeMo loads them via $ORIGIN rpath
# (fix_parakeet_libs.sh). Whisper keeps using the base image runtimes.
test -e "$PREFIX/lib/libstdc++.so.6"
test -e "$PREFIX/lib/libgcc_s.so.1"
test -f "$PREFIX/include/nemo_speech/asr.h"
test -f "$PREFIX/lib/libnemo_speech_asr_c.so"
