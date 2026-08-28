#!/bin/bash
set -ex

MODELS_DIR=${1:-/models}
mkdir -p "$MODELS_DIR"

download() {
	local url=$1
	local out=$2
	if [ -f "$out" ]; then
		echo "already present: $out"
		return
	fi
	wget -O "$out.partial" "$url"
	mv "$out.partial" "$out"
}

download \
	"https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/resolve/main/parakeet-tdt-0.6b-v3.q8_0.gguf" \
	"$MODELS_DIR/parakeet-tdt-0.6b-v3.q8_0.gguf"

download \
	"https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b/resolve/main/nemotron-3.5-asr-streaming-0.6b.q8_0.gguf" \
	"$MODELS_DIR/nemotron-3.5-asr-streaming-0.6b.q8_0.gguf"
