#!/bin/bash
set -euo pipefail

# Isolate Whisper and NeMo ggml. rpath/$ORIGIN is not enough: ELF loads a SONAME
# once per process, so both engines would share Whisper's libggml.so.0. Rename
# Whisper ggml SONAMEs so NeMo keeps libggml.so.0.
WHISPER_SRC=${1:?whisper lib source dir}
NEMO_PREFIX=${2:-/opt/nemo-speech}
BIN=${3:?calls-transcriber binary}
WHISPER_LIB=/opt/whisper/lib
SYSTEM_STDCXX="/usr/lib/$(uname -m)-linux-gnu/libstdc++.so.6"
NEMO_STDCXX="${NEMO_PREFIX}/lib/libstdc++.so.6"

mkdir -p "$WHISPER_LIB"
cp -a "${WHISPER_SRC}"/libwhisper* "$WHISPER_LIB/"
cp -a "${WHISPER_SRC}"/libggml* "$WHISPER_LIB/"

is_elf() {
	[[ -f "$1" && ! -L "$1" ]] || return 1
	patchelf --print-soname "$1" >/dev/null 2>&1 || patchelf --print-needed "$1" >/dev/null 2>&1
}

# libggml.so.0 -> libggml-wsp.so.0; libggml-cpu.so.0 -> libggml-cpu-wsp.so.0
wsp_soname() {
	sed -E 's/^(libggml(-[a-z0-9]+)*)\.so/\1-wsp.so/' <<<"$1"
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

rename_whisper_ggml() {
	local dir=$1
	local f old new
	for f in "$dir"/libggml*.so*; do
		[[ -e "$f" ]] || continue
		is_elf "$f" || continue
		old=$(patchelf --print-soname "$f" 2>/dev/null || true)
		[[ "$old" == libggml* ]] || continue
		[[ "$old" == *-wsp.so* ]] && continue
		new=$(wsp_soname "$old")
		[[ "$new" != "$old" ]] || continue
		patchelf --set-soname "$new" "$f"
		if [[ "$(basename "$f")" != "$new" ]]; then
			mv "$f" "$dir/$new"
		fi
	done
	for f in "$dir"/libggml*; do
		[[ -L "$f" ]] || continue
		[[ "$(basename "$f")" == *-wsp.so* ]] && continue
		rm -f "$f"
	done
}

replace_whisper_ggml_needed() {
	local target=$1
	local n new
	is_elf "$target" || return 0
	for n in $(patchelf --print-needed "$target" 2>/dev/null); do
		case "$n" in
		libggml*.so*)
			[[ "$n" == *-wsp.so* ]] && continue
			new=$(wsp_soname "$n")
			[[ "$new" != "$n" ]] || continue
			patchelf --replace-needed "$n" "$new" "$target"
			;;
		esac
	done
}

required_glibcxx() {
	# LC_ALL=C lexicographic sort: comm(1) rejects sort -V order
	# (GLIBCXX_3.4.9 vs 3.4.10).
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

set_rpath_origin "$WHISPER_LIB"
set_rpath_origin "${NEMO_PREFIX}/lib"
rename_whisper_ggml "$WHISPER_LIB"

for lib in "$WHISPER_LIB"/*.so*; do
	[[ -e "$lib" ]] || continue
	replace_whisper_ggml_needed "$lib"
done
replace_whisper_ggml_needed "$BIN"

patchelf --set-rpath "${WHISPER_LIB}:${NEMO_PREFIX}/lib" "$BIN"

whisper_so="${WHISPER_LIB}/libwhisper.so"
nemo_so="${NEMO_PREFIX}/lib/libnemo_speech_asr_c.so"

w_ggml=$(ldd "$whisper_so" | awk '/libggml.*-wsp\.so/ {print $3; exit}')
n_ggml=$(ldd "$nemo_so" | awk '/libggml\.so/ {print $3; exit}')

if [[ -z "$w_ggml" || "$w_ggml" != "${WHISPER_LIB}/"* ]]; then
	echo "libwhisper must resolve ggml-wsp from ${WHISPER_LIB}, got: ${w_ggml:-<missing>}" >&2
	ldd "$whisper_so" >&2 || true
	exit 1
fi
if [[ -z "$n_ggml" || "$n_ggml" != "${NEMO_PREFIX}/lib/"* ]]; then
	echo "libnemo_speech_asr_c must resolve libggml from ${NEMO_PREFIX}/lib, got: ${n_ggml:-<missing>}" >&2
	exit 1
fi

if ldd "$whisper_so" | grep -q "${NEMO_PREFIX}/lib/libggml"; then
	echo "libwhisper must not resolve ggml from ${NEMO_PREFIX}" >&2
	ldd "$whisper_so" >&2 || true
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

bin_ggml=$(ldd "$BIN" | awk '$1 ~ /^libggml\.so/ {print $3; exit}')
if [[ -z "$bin_ggml" || "$bin_ggml" != "${NEMO_PREFIX}/lib/"* ]]; then
	echo "binary libggml.so.0 must resolve from ${NEMO_PREFIX}/lib, got: ${bin_ggml:-<missing>}" >&2
	ldd "$BIN" | grep ggml >&2 || true
	exit 1
fi
if ldd "$BIN" | awk '$1 ~ /^libggml\.so/ && $3 ~ /\/opt\/whisper\// {found=1} END {exit found ? 0 : 1}'; then
	echo "binary must not resolve libggml.so.0 from ${WHISPER_LIB}" >&2
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
