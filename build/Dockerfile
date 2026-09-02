# syntax=docker/dockerfile:1.4
# Mattermost calls-transcriber. Default target: whisper/azure image.
# NeMo/Parakeet: docker build --target runner-nemo --build-arg NEMOSPEECH=1 ...
ARG GO_VERSION
FROM --platform=$TARGETPLATFORM debian:bookworm-20240612-slim AS base

WORKDIR /workdir

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install --no-install-recommends -y ca-certificates libgomp1 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -r calls && useradd -mr -g calls calls

ARG GO_VERSION
FROM --platform=$TARGETPLATFORM golang:${GO_VERSION}-bookworm AS builder

# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install --no-install-recommends -y patch ccache wget ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ARG TARGETOS
ARG TARGETARCH
ARG GO_BUILD_PLATFORMS=${TARGETOS}-${TARGETARCH}
ARG OPUS_VERSION
ARG OPUS_SHA
ARG WHISPER_VERSION
ARG WHISPER_SHA
ARG WHISPER_MODELS
ARG ONNX_VERSION
ARG DEBIAN_FRONTEND=noninteractive
ARG AZURE_SDK_VERSION
ARG AZURE_SDK_SHA
ARG NEMOSPEECH=0
ARG NEMO_SPEECH_VERSION=0.1.0
ARG NEMO_SPEECH_GIT_SHA=4f9676226f667d14608487df744f375db87127f8
ARG NEMO_SPEECH_SHA_AMD64=0f74131d631ad2c694cf0ec53490866bb6461147959589a69fb6fc231944065b
ARG NEMO_SPEECH_SHA_ARM64=0e4112255d566de7bdd142f239e984995c4447103ba8feb41f2bb5c559d561d3
# download = wget into BuildKit cache (CI/upstream); host = extra build-context (local .cache)
ARG PARAKEET_MODELS_MODE=download

COPY ./build /src/build
WORKDIR /src

RUN --mount=type=cache,id=prepare-deps-${TARGETARCH},target=/cache/deps \
    --mount=type=cache,id=ccache-${TARGETARCH},target=/root/.ccache \
    DEPS_DIR=/cache/deps \
    /bin/bash ./build/prepare_deps.sh ${OPUS_VERSION} ${OPUS_SHA} ${WHISPER_VERSION} ${WHISPER_SHA} "${WHISPER_MODELS}" ${ONNX_VERSION} ${TARGETARCH} ${AZURE_SDK_VERSION} ${AZURE_SDK_SHA} && \
    cp -a /cache/deps/opus-${OPUS_VERSION} /tmp/ && \
    cp -a /cache/deps/whisper.cpp-${WHISPER_VERSION} /tmp/ && \
    cp -a /cache/deps/onnxruntime-linux-${ONNX_VERSION} /tmp/ && \
    cp -a /cache/deps/SpeechSDK-Linux-${AZURE_SDK_VERSION} /tmp/

# hadolint ignore=DL3008
RUN --mount=type=cache,id=nemo-src-${TARGETARCH},target=/tmp/NeMo-Speech.cpp \
    --mount=type=cache,id=ccache-${TARGETARCH},target=/root/.ccache \
    --mount=type=cache,id=prepare-deps-${TARGETARCH},target=/cache/deps \
    if [ "$NEMOSPEECH" = "1" ]; then \
        apt-get update && \
        apt-get install --no-install-recommends -y git ninja-build g++ pkg-config libsentencepiece-dev && \
        DEPS_DIR=/cache/deps \
        /bin/bash ./build/prepare_nemospeech.sh ${NEMO_SPEECH_VERSION} /opt/nemo-speech ${TARGETARCH} "${NEMO_SPEECH_GIT_SHA}"; \
        apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

RUN --mount=type=cache,id=parakeet-gguf-${TARGETARCH},target=/cache/parakeet-gguf \
    if [ "$NEMOSPEECH" != "1" ] || [ "$PARAKEET_MODELS_MODE" = "host" ]; then exit 0; fi; \
    /bin/bash ./build/download_parakeet_models.sh /cache/parakeet-gguf && \
    mkdir -p /tmp/parakeet-models && cp -a /cache/parakeet-gguf/. /tmp/parakeet-models/

RUN --mount=from=parakeet-models,source=.,target=/ctx \
    if [ "$NEMOSPEECH" != "1" ] || [ "$PARAKEET_MODELS_MODE" != "host" ]; then exit 0; fi; \
    test -f /ctx/parakeet-tdt-0.6b-v3.q8_0.gguf && \
    test -f /ctx/nemotron-3.5-asr-streaming-0.6b.q8_0.gguf && \
    mkdir -p /tmp/parakeet-models && cp -a /ctx/. /tmp/parakeet-models/

RUN if [ "$NEMOSPEECH" = "1" ]; then \
        test -f /tmp/parakeet-models/parakeet-tdt-0.6b-v3.q8_0.gguf && \
        test -f /tmp/parakeet-models/nemotron-3.5-asr-streaming-0.6b.q8_0.gguf; \
    fi

COPY . /src
ENV NEMOSPEECH=${NEMOSPEECH}
RUN if [ "$NEMOSPEECH" = "1" ]; then \
        export C_INCLUDE_PATH="/opt/nemo-speech/include:${C_INCLUDE_PATH}"; \
        export LIBRARY_PATH="/opt/nemo-speech/lib:${LIBRARY_PATH}"; \
    fi && \
    /bin/bash ./build/build.sh ${OPUS_VERSION} ${OPUS_SHA} ${WHISPER_VERSION} ${WHISPER_SHA} "${WHISPER_MODELS}" ${ONNX_VERSION} ${TARGETARCH} ${AZURE_SDK_VERSION} ${AZURE_SDK_SHA}

FROM base AS runner
ARG TARGETOS
ARG TARGETARCH
ARG WHISPER_VERSION
ARG ONNX_VERSION
ARG AZURE_SDK_VERSION
COPY --from=builder /src/dist/calls-transcriber-${TARGETOS}-${TARGETARCH} /opt/calls-transcriber/bin/calls-transcriber
COPY --from=builder /tmp/whisper.cpp-${WHISPER_VERSION}/models /models
COPY --from=builder /tmp/whisper.cpp-${WHISPER_VERSION}/build/src/libwhisper* /usr/lib/
COPY --from=builder /tmp/whisper.cpp-${WHISPER_VERSION}/build/ggml/src/libggml* /usr/lib/
COPY --from=builder /tmp/onnxruntime-linux-${ONNX_VERSION}/lib/* /usr/lib/
COPY --from=builder /tmp/SpeechSDK-Linux-${AZURE_SDK_VERSION}/lib/${TARGETARCH}/* /usr/lib/
COPY --from=builder /src/build/models/silero_vad.onnx /models
COPY --from=builder /src/build/entrypoint.sh .
RUN ldconfig

ENTRYPOINT ["./entrypoint.sh"]
CMD ["/opt/calls-transcriber/bin/calls-transcriber"]

FROM base AS runner-nemo
ARG TARGETOS
ARG TARGETARCH
ARG WHISPER_VERSION
ARG ONNX_VERSION
ARG AZURE_SDK_VERSION
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install --no-install-recommends -y patchelf binutils libsentencepiece0 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
COPY --from=builder /src/dist/calls-transcriber-${TARGETOS}-${TARGETARCH} /opt/calls-transcriber/bin/calls-transcriber
COPY --from=builder /tmp/whisper.cpp-${WHISPER_VERSION}/models /models
COPY --from=builder /tmp/parakeet-models/ /models/
COPY --from=builder /opt/nemo-speech /opt/nemo-speech
COPY --from=builder /tmp/onnxruntime-linux-${ONNX_VERSION}/lib/* /usr/lib/
COPY --from=builder /tmp/SpeechSDK-Linux-${AZURE_SDK_VERSION}/lib/${TARGETARCH}/* /usr/lib/
COPY --from=builder /src/build/models/silero_vad.onnx /models
COPY --from=builder /src/build/licenses /opt/calls-transcriber/licenses
COPY --from=builder /src/build/entrypoint.sh .
COPY --from=builder /src/build/fix_parakeet_libs.sh /tmp/fix_parakeet_libs.sh
RUN mkdir -p /tmp/whisper-import
COPY --from=builder /tmp/whisper.cpp-${WHISPER_VERSION}/build/src/libwhisper* /tmp/whisper-import/
COPY --from=builder /tmp/whisper.cpp-${WHISPER_VERSION}/build/ggml/src/libggml* /tmp/whisper-import/
RUN /bin/bash /tmp/fix_parakeet_libs.sh \
    /tmp/whisper-import \
    /opt/nemo-speech \
    /opt/calls-transcriber/bin/calls-transcriber && \
    rm -rf /tmp/whisper-import /tmp/fix_parakeet_libs.sh
RUN ldconfig

ENTRYPOINT ["./entrypoint.sh"]
CMD ["/opt/calls-transcriber/bin/calls-transcriber"]
