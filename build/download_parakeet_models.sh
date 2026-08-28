#!/bin/bash
set -euxo pipefail

# Pin with the HuggingFace resolve/main URLs below. Bump when NVIDIA republishes weights.
PARAKEET_GGUF_SHA=e3880d0aaaaf2c308ea2c35016b2b895c423eb3fda924c1b463d1c19b7f4d32e
NEMOTRON_GGUF_SHA=a5c435f294eea8f88ce68dd27b8c3bfea7f777cb2fbba04fcd30eaa555f429ae

MODELS_DIR=${1:-/models}
mkdir -p "$MODELS_DIR"

download() {
	local url=$1
	local out=$2
	local sha=$3
	if [ -f "$out" ]; then
		if echo "$sha  $out" | sha256sum --check --status; then
			echo "already present: $out"
			return
		fi
		echo "stale or corrupt cache, re-downloading: $out" >&2
		rm -f "$out"
	fi
	rm -f "$out.partial"
	wget -O "$out.partial" --tries=3 --timeout=60 "$url"
	echo "$sha  $out.partial" | sha256sum --check
	mv "$out.partial" "$out"
}

download \
	"https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3/resolve/main/parakeet-tdt-0.6b-v3.q8_0.gguf" \
	"$MODELS_DIR/parakeet-tdt-0.6b-v3.q8_0.gguf" \
	"$PARAKEET_GGUF_SHA"

download \
	"https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b/resolve/main/nemotron-3.5-asr-streaming-0.6b.q8_0.gguf" \
	"$MODELS_DIR/nemotron-3.5-asr-streaming-0.6b.q8_0.gguf" \
	"$NEMOTRON_GGUF_SHA"
