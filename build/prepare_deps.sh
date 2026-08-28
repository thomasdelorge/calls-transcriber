#!/bin/bash
set -euxo pipefail

OPUS_VERSION=$1
OPUS_SHA=$2
WHISPER_VERSION=$3
WHISPER_SHA=$4
MODELS=$5
ONNX_VERSION=$6
TARGET_ARCH=$7
AZURE_SDK_VERSION=$8
AZURE_SDK_SHA=$9
ONNX_ARCH=x64
ONNX_SHA=a0994512ec1e1debc00c18bfc7a5f16249f6ebd6a6128ff2034464cc380ea211
CMAKE_VERSION="4.0.3"
CMAKE_ARCH=x86_64
CMAKE_SHA=585ae9e013107bc8e7c7c9ce872cbdcbdff569e675b07ef57aacfb88c886faac
CMAKE_ARGS=""
DEPS_DIR=${DEPS_DIR:-/tmp}
mkdir -p "$DEPS_DIR"

if [ "$TARGET_ARCH" == "arm64" ]; then
	ONNX_ARCH=aarch64
	CMAKE_ARCH=aarch64
	ONNX_SHA=c1dcd8ab29e8d227d886b6ee415c08aea893956acf98f0758a42a84f27c02851
	CMAKE_SHA=391da1544ef50ac31300841caaf11db4de3976cdc4468643272e44b3f4644713

	echo "Adding CMAKE_ARGS on detected arm64 host";
	CMAKE_ARGS="-DGGML_NATIVE=OFF -DGGML_CPU_ARM_ARCH=armv8-a"
fi

if command -v ccache >/dev/null 2>&1; then
	CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
fi

CMAKE_BASE="cmake-$CMAKE_VERSION-linux-$CMAKE_ARCH"
CMAKE_PATH="$DEPS_DIR/$CMAKE_BASE/bin"

fetch() {
	local url=$1 file=$2 sha=$3
	if [ -f "$file" ] && echo "$sha  $file" | sha256sum --check --status; then
		echo "using cached $file"
		return
	fi
	wget -O "$file" "$url"
	echo "$sha  $file" | sha256sum --check
}

cd "$DEPS_DIR"
fetch "https://github.com/Kitware/CMake/releases/download/v$CMAKE_VERSION/$CMAKE_BASE.tar.gz" "$CMAKE_BASE.tar.gz" "$CMAKE_SHA"
if [ ! -x "$CMAKE_PATH/cmake" ]; then
	tar xf "$CMAKE_BASE.tar.gz"
fi

fetch "https://downloads.xiph.org/releases/opus/opus-${OPUS_VERSION}.tar.gz" "opus-${OPUS_VERSION}.tar.gz" "${OPUS_SHA}"
if [ ! -e "opus-${OPUS_VERSION}/.libs/libopus.so" ] && [ ! -e "opus-${OPUS_VERSION}/.libs/libopus.a" ]; then
	tar xf "opus-${OPUS_VERSION}.tar.gz"
	(cd "opus-${OPUS_VERSION}" && ./configure && make -j4)
fi

fetch "https://github.com/ggerganov/whisper.cpp/archive/refs/tags/v${WHISPER_VERSION}.tar.gz" "v${WHISPER_VERSION}.tar.gz" "${WHISPER_SHA}"
if ! compgen -G "whisper.cpp-${WHISPER_VERSION}/build/src/libwhisper*" > /dev/null; then
	tar xf "v${WHISPER_VERSION}.tar.gz"
	cd "whisper.cpp-${WHISPER_VERSION}"
	for model in ${MODELS}; do ./models/download-ggml-model.sh "${model}"; done
	PATH="$PATH:$CMAKE_PATH" cmake -B build ${CMAKE_ARGS}
	PATH="$PATH:$CMAKE_PATH" cmake --build build -j --config Release
	cd "$DEPS_DIR"
fi

fetch "https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VERSION}/onnxruntime-linux-${ONNX_ARCH}-${ONNX_VERSION}.tgz" "onnxruntime-linux-${ONNX_ARCH}-${ONNX_VERSION}.tgz" "${ONNX_SHA}"
if [ ! -d "onnxruntime-linux-${ONNX_VERSION}" ]; then
	tar xf "onnxruntime-linux-${ONNX_ARCH}-${ONNX_VERSION}.tgz"
	mv "onnxruntime-linux-${ONNX_ARCH}-${ONNX_VERSION}" "onnxruntime-linux-${ONNX_VERSION}"
fi

fetch "https://csspeechstorage.blob.core.windows.net/drop/${AZURE_SDK_VERSION}/SpeechSDK-Linux-${AZURE_SDK_VERSION}.tar.gz" "SpeechSDK-Linux-${AZURE_SDK_VERSION}.tar.gz" "${AZURE_SDK_SHA}"
if [ ! -d "SpeechSDK-Linux-${AZURE_SDK_VERSION}" ]; then
	tar xf "SpeechSDK-Linux-${AZURE_SDK_VERSION}.tar.gz"
	mv "$DEPS_DIR/SpeechSDK-Linux-${AZURE_SDK_VERSION}/lib/x64" "$DEPS_DIR/SpeechSDK-Linux-${AZURE_SDK_VERSION}/lib/amd64"
fi
