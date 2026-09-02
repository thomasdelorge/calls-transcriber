#!/bin/bash
set -euxo pipefail

# CPU ASR SDK into PREFIX. Default: build v0.1.0 from source with a portable
# AVX2 baseline (GGML_NATIVE=OFF, AVX-512 off). The official linux-x86_64-cpu
# tarball is compiled with GGML_NATIVE and SIGILLs on AVX2-only hosts.
#
# PREBUILT=1: unpack the NVIDIA archive instead (CI compile-check only).
# Pin: NEMO_SPEECH_VERSION + 4th arg (git SHA, or archive sha256 if PREBUILT=1).
#
# https://github.com/NVIDIA/NeMo-Speech.cpp
NEMO_SPEECH_VERSION=${1:-0.1.0}
PREFIX=${2:-/opt/nemo-speech}
TARGET_ARCH=${3:-amd64}
NEMO_PIN=${4:?NEMO_PIN is required (git SHA, or archive sha256 if PREBUILT=1)}

CMAKE_VERSION="4.0.3"
CMAKE_SHA_AMD64=585ae9e013107bc8e7c7c9ce872cbdcbdff569e675b07ef57aacfb88c886faac
CMAKE_SHA_ARM64=391da1544ef50ac31300841caaf11db4de3976cdc4468643272e44b3f4644713
SRC_DIR=${NEMO_SRC_DIR:-/tmp/NeMo-Speech.cpp}
DEPS_DIR=${DEPS_DIR:-/tmp}

case "$TARGET_ARCH" in
	amd64|x86_64)
		ARCH=x86_64
		CMAKE_ARCH=x86_64
		CMAKE_SHA=$CMAKE_SHA_AMD64
		;;
	arm64|aarch64)
		ARCH=aarch64
		CMAKE_ARCH=aarch64
		CMAKE_SHA=$CMAKE_SHA_ARM64
		;;
	*)
		echo "unsupported TARGET_ARCH=$TARGET_ARCH" >&2
		exit 1
		;;
esac

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

if [ "${PREBUILT:-0}" = "1" ]; then
	ARCHIVE="nemo-speech-${NEMO_SPEECH_VERSION}-linux-${ARCH}-cpu.tar.gz"
	URL="https://github.com/NVIDIA/NeMo-Speech.cpp/releases/download/v${NEMO_SPEECH_VERSION}/${ARCHIVE}"
	cd /tmp
	fetch "$URL" "$ARCHIVE" "$NEMO_PIN"
	rm -rf "$PREFIX"
	mkdir -p "$PREFIX"
	tar xf "$ARCHIVE"
	mv "nemo-speech-${NEMO_SPEECH_VERSION}-linux-${ARCH}-cpu"/* "$PREFIX/"
	rmdir "nemo-speech-${NEMO_SPEECH_VERSION}-linux-${ARCH}-cpu"
	test -e "$PREFIX/lib/libstdc++.so.6"
	test -e "$PREFIX/lib/libgcc_s.so.1"
	test -f "$PREFIX/include/nemo_speech/asr.h"
	test -f "$PREFIX/lib/libnemo_speech_asr_c.so"
	exit 0
fi

if ! command -v ninja >/dev/null 2>&1; then
	echo "ninja is required for a source build" >&2
	exit 1
fi
if ! command -v git >/dev/null 2>&1; then
	echo "git is required for a source build" >&2
	exit 1
fi

mkdir -p "$DEPS_DIR"
CMAKE_BASE="cmake-$CMAKE_VERSION-linux-$CMAKE_ARCH"
CMAKE_PATH="$DEPS_DIR/$CMAKE_BASE/bin"
cd "$DEPS_DIR"
fetch "https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/$CMAKE_BASE.tar.gz" "$CMAKE_BASE.tar.gz" "$CMAKE_SHA"
if [ ! -x "$CMAKE_PATH/cmake" ]; then
	tar xf "$CMAKE_BASE.tar.gz"
fi
export PATH="$CMAKE_PATH:$PATH"

mkdir -p "$SRC_DIR"
if [ ! -d "$SRC_DIR/.git" ]; then
	git clone --depth 1 --branch "v${NEMO_SPEECH_VERSION}" \
		https://github.com/NVIDIA/NeMo-Speech.cpp.git "$SRC_DIR"
fi
cd "$SRC_DIR"
HEAD=$(git rev-parse HEAD)
if [ "$HEAD" != "$NEMO_PIN" ]; then
	echo "NeMo-Speech.cpp HEAD $HEAD != pinned $NEMO_PIN" >&2
	exit 1
fi
git submodule update --init --depth 1 ggml

# Drop a cached cpu-asr tree compiled -march=native on the GHA runner.
rm -rf "$SRC_DIR/build"

GGML_CPU_FLAGS=(
	-DGGML_NATIVE=OFF
	-DGGML_AVX512=OFF
	-DGGML_AVX512_VBMI=OFF
	-DGGML_AVX512_VNNI=OFF
	-DGGML_AVX512_BF16=OFF
	-DGGML_AMX_INT8=OFF
	-DGGML_AMX_BF16=OFF
)
if [ "$ARCH" = "x86_64" ]; then
	GGML_CPU_FLAGS+=(
		-DCMAKE_C_FLAGS=-march=x86-64-v3
		-DCMAKE_CXX_FLAGS=-march=x86-64-v3
		-DGGML_AVX=ON
		-DGGML_AVX2=ON
		-DGGML_FMA=ON
		-DGGML_F16C=ON
	)
else
	GGML_CPU_FLAGS+=(-DGGML_CPU_ARM_ARCH=armv8-a)
fi

CCACHE_ARGS=()
if command -v ccache >/dev/null 2>&1; then
	CCACHE_ARGS=(
		-DCMAKE_C_COMPILER_LAUNCHER=ccache
		-DCMAKE_CXX_COMPILER_LAUNCHER=ccache
	)
fi

# cpu-asr links Debian's shared sentencepiece (NVIDIA's tarball uses a static
# .a). runner-nemo must install libsentencepiece0; cmake --install does not.
cmake --preset cpu-asr \
	-DBUILD_SHARED_LIBS=ON \
	-DNEMO_SPEECH_BUILD_CLI=OFF \
	-DNEMO_SPEECH_BUILD_MIC_CAPTURE=OFF \
	-DNEMO_SPEECH_BUILD_DIAR=OFF \
	"${GGML_CPU_FLAGS[@]}" \
	"${CCACHE_ARGS[@]}"
cmake --build --preset cpu-asr -j"$(nproc)"
rm -rf "$PREFIX"
cmake --install "$SRC_DIR/build/cpu-asr" --prefix "$PREFIX"

# Keep $ORIGIN rpath isolation (fix_parakeet_libs.sh) working like the NVIDIA tarball.
LIBDIR="/usr/lib/${ARCH}-linux-gnu"
if [ ! -d "$LIBDIR" ]; then
	LIBDIR="/usr/lib/$(uname -m)-linux-gnu"
fi
mkdir -p "$PREFIX/lib"
for so in libstdc++.so.6 libgcc_s.so.1 libgomp.so.1; do
	if [ -e "$LIBDIR/$so" ]; then
		cp -a "$LIBDIR/$so"* "$PREFIX/lib/" || true
	fi
done

test -f "$PREFIX/include/nemo_speech/asr.h"
test -f "$PREFIX/lib/libnemo_speech_asr_c.so"

# Any %zmm / EVEX in the installed tree SIGILLs on AVX2-only hosts (N100).
if [ "$ARCH" = "x86_64" ]; then
	found=0
	for so in "$PREFIX"/lib/*.so*; do
		[[ -f "$so" && ! -L "$so" ]] || continue
		if objdump -d "$so" 2>/dev/null | grep -Eq '%zmm'; then
			echo "AVX-512 codegen (%zmm) in $so" >&2
			found=1
		fi
	done
	if [ "$found" != 0 ]; then
		exit 1
	fi
fi
