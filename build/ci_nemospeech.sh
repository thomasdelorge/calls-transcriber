#!/bin/bash
set -euxo pipefail

# Compile-check the nemospeech cgo package in CI (SDK ~4.5 MiB, no GGUF).
ARCH="${ARCH:-amd64}"
NEMO_SPEECH_VERSION="${NEMO_SPEECH_VERSION:-0.1.0}"
NEMO_SPEECH_SHA_AMD64="${NEMO_SPEECH_SHA_AMD64:-0f74131d631ad2c694cf0ec53490866bb6461147959589a69fb6fc231944065b}"
NEMO_SPEECH_SHA_ARM64="${NEMO_SPEECH_SHA_ARM64:-0e4112255d566de7bdd142f239e984995c4447103ba8feb41f2bb5c559d561d3}"

case "$ARCH" in
	arm64|aarch64) NEMO_SHA="$NEMO_SPEECH_SHA_ARM64" ;;
	*) NEMO_SHA="$NEMO_SPEECH_SHA_AMD64" ;;
esac

sudo mkdir -p /opt/nemo-speech
sudo PREBUILT=1 bash ./build/prepare_nemospeech.sh "$NEMO_SPEECH_VERSION" /opt/nemo-speech "$ARCH" "$NEMO_SHA"

export CGO_ENABLED=1
go build -mod=readonly -tags nemospeech ./cmd/transcriber/apis/nemospeech/...
go vet -mod=readonly -tags nemospeech ./cmd/transcriber/apis/nemospeech/...
go build -mod=readonly -tags nemospeech ./cmd/transcriber/apis/whisper.cpp/...
