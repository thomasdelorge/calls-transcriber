#!/bin/bash
set -euo pipefail

# Parakeet image is NeMo-only: do not ship whisper.cpp. Two ggml copies cannot
# share one process even with different SONAMEs (global ggml_* symbols).
NEMO_PREFIX=${1:-/opt/nemo-speech}
BIN=${2:?calls-transcriber binary}
SYSTEM_STDCXX="/usr/lib/$(uname -m)-linux-gnu/libstdc++.so.6"
NEMO_STDCXX="${NEMO_PREFIX}/lib/libstdc++.so.6"

is_elf() {
	[[ -f "$1" && ! -L "$1" ]] || return 1
	patchelf --print-soname "$1" >/dev/null 2>&1 || patchelf --print-needed "$1" >/dev/null 2>&1
}

set_rpath_origin() {
	local dir=$1
	local lib
	for lib in "$dir"/*.so*; do
		[[ -e "$lib" ]] || continue
		is_elf "$lib" || continue
		patchelf --set-rpath '$ORIGIN' "$lib"
	done
}

required_glibcxx() {
	objdump -p "$1" 2>/dev/null | sed -n '/Version References:/,/^[[:space:]]*$/p' \
		| grep -oE 'GLIBCXX_[0-9.]+' | LC_ALL=C sort -u || true
}

provided_glibcxx() {
	objdump -p "$1" 2>/dev/null | sed -n '/Version definitions:/,/^[[:space:]]*$/p' \
		| grep -oE 'GLIBCXX_[0-9.]+' | LC_ALL=C sort -u || true
}

verify_nemo_glibcxx() {
	local lib=$1
	local missing

	if [[ ! -e "$NEMO_STDCXX" ]]; then
		echo "NeMo bundled libstdc++ missing at ${NEMO_STDCXX}" >&2
		exit 1
	fi

	missing=$(LC_ALL=C comm -23 <(required_glibcxx "$lib") <(provided_glibcxx "$NEMO_STDCXX"))
	if [[ -n "$missing" ]]; then
		echo "NeMo requires GLIBCXX versions not provided by bundled libstdc++:" >&2
		echo "$missing" >&2
		exit 1
	fi

	if [[ ! -e "$SYSTEM_STDCXX" ]]; then
		echo "system libstdc++ missing at ${SYSTEM_STDCXX}" >&2
		exit 1
	fi
	missing=$(LC_ALL=C comm -23 <(required_glibcxx "$lib") <(provided_glibcxx "$SYSTEM_STDCXX"))
	if [[ -n "$missing" ]]; then
		echo "NeMo requires GLIBCXX versions absent from base image libstdc++;" >&2
		echo "bundled runtimes in ${NEMO_PREFIX}/lib are required:" >&2
		echo "$missing" >&2
	fi
}

set_rpath_origin "${NEMO_PREFIX}/lib"
patchelf --set-rpath "${NEMO_PREFIX}/lib" "$BIN"

nemo_so="${NEMO_PREFIX}/lib/libnemo_speech_asr_c.so"

n_ggml=$(ldd "$nemo_so" | awk '/libggml\.so/ {print $3; exit}')
if [[ -z "$n_ggml" || "$n_ggml" != "${NEMO_PREFIX}/lib/"* ]]; then
	echo "libnemo_speech_asr_c must resolve libggml from ${NEMO_PREFIX}/lib, got: ${n_ggml:-<missing>}" >&2
	exit 1
fi

nemo_stdcxx=$(ldd "$nemo_so" | awk '/libstdc\+\+\.so/ {print $3; exit}')
if [[ -z "$nemo_stdcxx" || "$nemo_stdcxx" != "${NEMO_PREFIX}/lib/"* ]]; then
	echo "libnemo_speech_asr_c must resolve libstdc++ from ${NEMO_PREFIX}/lib, got: ${nemo_stdcxx:-<missing>}" >&2
	exit 1
fi

verify_nemo_glibcxx "$nemo_so"

ldd "$BIN" | grep -q libwhisper && {
	echo "Parakeet binary must not link libwhisper" >&2
	ldd "$BIN" >&2
	exit 1
}
ldd "$BIN" | grep -q "${NEMO_PREFIX}/lib/libnemo_speech_asr" || {
	echo "binary must load libnemo_speech_asr from ${NEMO_PREFIX}/lib" >&2
	exit 1
}

bin_ggml=$(ldd "$BIN" | awk '$1 ~ /^libggml\.so/ {print $3; exit}')
if [[ -z "$bin_ggml" || "$bin_ggml" != "${NEMO_PREFIX}/lib/"* ]]; then
	echo "binary libggml.so.0 must resolve from ${NEMO_PREFIX}/lib, got: ${bin_ggml:-<missing>}" >&2
	ldd "$BIN" | grep ggml >&2 || true
	exit 1
fi

missing=$(ldd "$BIN" | awk '/not found/ {print}' || true)
if [[ -n "$missing" ]]; then
	echo "calls-transcriber has unresolved shared libraries:" >&2
	echo "$missing" >&2
	exit 1
fi

echo "parakeet lib isolation OK"
