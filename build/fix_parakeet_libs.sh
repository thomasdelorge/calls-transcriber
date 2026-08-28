#!/bin/bash
set -euo pipefail

# Isolate Whisper and NeMo ggml (same SONAME libggml.so.0) into private trees with
# $ORIGIN rpaths so neither engine resolves the other's dependencies.
WHISPER_SRC=${1:?whisper lib source dir}
NEMO_PREFIX=${2:-/opt/nemo-speech}
BIN=${3:?calls-transcriber binary}
WHISPER_LIB=/opt/whisper/lib
SYSTEM_STDCXX="/usr/lib/$(uname -m)-linux-gnu/libstdc++.so.6"
NEMO_STDCXX="${NEMO_PREFIX}/lib/libstdc++.so.6"

mkdir -p "$WHISPER_LIB"
cp -a "${WHISPER_SRC}"/libwhisper* "$WHISPER_LIB/"
cp -a "${WHISPER_SRC}"/libggml* "$WHISPER_LIB/"

set_rpath_origin() {
	local dir=$1
	local lib
	for lib in "$dir"/*.so*; do
		[[ -e "$lib" ]] || continue
		patchelf --set-rpath '$ORIGIN' "$lib"
	done
}

required_glibcxx() {
	objdump -p "$1" 2>/dev/null | sed -n '/Version References:/,/^[[:space:]]*$/p' \
		| grep -oE 'GLIBCXX_[0-9.]+' | sort -Vu
}

provided_glibcxx() {
	objdump -p "$1" 2>/dev/null | sed -n '/Version definitions:/,/^[[:space:]]*$/p' \
		| grep -oE 'GLIBCXX_[0-9.]+' | sort -Vu
}

verify_nemo_glibcxx() {
	local lib=$1
	local missing

	if [[ ! -e "$NEMO_STDCXX" ]]; then
		echo "NeMo bundled libstdc++ missing at ${NEMO_STDCXX}" >&2
		exit 1
	fi

	missing=$(comm -23 <(required_glibcxx "$lib") <(provided_glibcxx "$NEMO_STDCXX"))
	if [[ -n "$missing" ]]; then
		echo "NeMo requires GLIBCXX versions not provided by bundled libstdc++:" >&2
		echo "$missing" >&2
		exit 1
	fi

	if [[ ! -e "$SYSTEM_STDCXX" ]]; then
		echo "system libstdc++ missing at ${SYSTEM_STDCXX}" >&2
		exit 1
	fi
	missing=$(comm -23 <(required_glibcxx "$lib") <(provided_glibcxx "$SYSTEM_STDCXX"))
	if [[ -n "$missing" ]]; then
		echo "NeMo requires GLIBCXX versions absent from base image libstdc++;" >&2
		echo "bundled runtimes in ${NEMO_PREFIX}/lib are required:" >&2
		echo "$missing" >&2
	fi
}

set_rpath_origin "$WHISPER_LIB"
set_rpath_origin "${NEMO_PREFIX}/lib"

patchelf --set-rpath "${WHISPER_LIB}:${NEMO_PREFIX}/lib" "$BIN"

resolve_ggml() {
	ldd "$1" | awk '/libggml\.so/ {print $3; exit}'
}

whisper_so="${WHISPER_LIB}/libwhisper.so"
nemo_so="${NEMO_PREFIX}/lib/libnemo_speech_asr_c.so"

w_ggml=$(resolve_ggml "$whisper_so")
n_ggml=$(resolve_ggml "$nemo_so")

if [[ -z "$w_ggml" || "$w_ggml" != "${WHISPER_LIB}/"* ]]; then
	echo "libwhisper must resolve libggml from ${WHISPER_LIB}, got: ${w_ggml:-<missing>}" >&2
	exit 1
fi
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

ldd "$BIN" | grep -q "${WHISPER_LIB}/libwhisper" || {
	echo "binary must load libwhisper from ${WHISPER_LIB}" >&2
	exit 1
}
ldd "$BIN" | grep -q "${NEMO_PREFIX}/lib/libnemo_speech_asr" || {
	echo "binary must load libnemo_speech_asr from ${NEMO_PREFIX}/lib" >&2
	exit 1
}

echo "parakeet lib isolation OK"
