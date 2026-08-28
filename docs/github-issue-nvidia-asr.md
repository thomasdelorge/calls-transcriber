# GitHub issue draft — NVIDIA Parakeet / Nemotron local ASR

Proposition d’issue pour [mattermost/calls-transcriber](https://github.com/mattermost/calls-transcriber/issues/new).

---

## Title

Feature request: support NVIDIA Parakeet / Nemotron as local ASR backend (alternative to whisper.cpp)

---

## Body

### Context

`calls-transcriber` uses whisper.cpp as the default local backend for:

- Post-call transcription (`TRANSCRIBE_API=whisper.cpp`)
- Live captions (Whisper tiny + VAD + sliding windows + transcriber pool)

This works for basic deployments. On my Mattermost Calls setup (multi-speaker audio, French locale), French transcription wasn't always very accurate, and live captions felt too slow to keep up with real-time speech. Post-call quality improves with larger Whisper models, but at a noticeable CPU/RAM cost on self-hosted hardware. More broadly, Whisper is increasingly being matched or surpassed by newer local ASR models — especially for streaming, where dedicated architectures seem like a better fit.

Azure (`TRANSCRIBE_API=azure`) is an option for cloud deployments, but many self-hosted Mattermost instances want fully local inference without sending audio to a third party.

I also have a local PoC on top of NeMo-Speech.cpp (Parakeet for post-call, Nemotron for live captions) that shows this can work end-to-end on Mattermost Calls. It's still very much a proof of concept though — rough around the edges, and probably not in a state I'd open as a draft PR today. If this direction seems relevant, I'm happy to share details or work toward a PR.

### Proposal

Add an optional local backend based on NVIDIA NeMo-Speech.cpp (GGUF, CPU inference), using models suited to each task:

| Task | Model | Role |
|------|-------|------|
| Post-call transcription | [Parakeet TDT 0.6B v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) (`q8_0` GGUF) | Batch/offline ASR after the call |
| Live captions | [Nemotron 3.5 ASR Streaming 0.6B](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b) (`q8_0` GGUF) | Cache-aware streaming RNNT decoder |

Runtime: [NeMo-Speech.cpp v0.1.0](https://github.com/NVIDIA/NeMo-Speech.cpp/releases/tag/v0.1.0)  prebuilt CPU SDK (`libnemo_speech_asr_c.so`), no source build required.

Configuration sketch (aligned with existing `TRANSCRIBE_API` pattern):

```bash
TRANSCRIBE_API=parakeet
LIVE_CAPTIONS_ON=true
LIVE_CAPTIONS_LANGUAGE=fr          # BCP-47 / ISO 639-1, Nemotron handles streaming locale
ASR_LANGUAGE=fr-FR                 # optional post-call language hint, empty = auto-detect
LIVE_CAPTIONS_RNNT_RIGHT_CONTEXT=3 # streaming latency vs stability (80 ms frames)
```

Whisper would remain available (`TRANSCRIBE_API=whisper.cpp`) for backward compatibility and smaller images.

### Why these models

- Parakeet TDT: NVIDIA’s TDT architecture is aimed at accurate offline/batch transcription, in local CPU GGUF form it is a practical upgrade over Whisper for post-call jobs on modest hardware.
- Nemotron Streaming: purpose-built for streaming ASR with RNNT cache-aware decoding and endpointing : a better match for live captions than re-purposing Whisper with VAD + sliding windows.
- Single stack: one C API (NeMo-Speech.cpp) for both post-call and live paths simplifies integration vs bolting on unrelated engines.

### Observed benefits (local testing)

On a self-hosted Mattermost + `calls-offloader` setup, compared to whisper.cpp defaults:

- Lower perceived latency on live captions (streaming decoder vs 2–8 s Whisper windows)
- Better word error rate on conversational French/English call audio
- More stable captions under multi-speaker load (one shared Nemotron stream per call vs Whisper pool pressure / window drops)
- Acceptable CPU footprint with Q8 GGUF on CPU-only nodes (no GPU required)

> Remplacer ou compléter cette section avec vos mesures concrètes (latence, WER, CPU/RAM, durée d’appel testée).

### Trade-offs to discuss

| Topic | Notes |
|-------|-------|
| Image size | ~1.45 GB extra for two GGUF weights (+ existing Whisper models if kept) |
| RAM | Several GB at inference, similar order of magnitude to larger Whisper models |
| Licenses | Parakeet CC-BY-4.0, Nemotron OpenMDW-1.1, NeMo-Speech.cpp Apache-2.0, need `NOTICE` in the image |
| Build complexity | SDK is a small prebuilt archive, models downloaded at build time (cacheable) |
| Plugin / offloader | Today requires env override (`MM_CALLS_TRANSCRIBER_TRANSCRIBE_API=parakeet`), first-class UI/config in Calls plugin would help adoption |
| arm64 | NeMo-Speech.cpp CPU SDK availability for arm64 should be verified before claiming support |

### Suggested integration path

1. Add `TRANSCRIBE_API=parakeet` (or `nemospeech`) behind a Go build tag `nemospeech`.
2. Wire post-call transcription through NeMo-Speech.cpp + Parakeet GGUF (same `transcribe.Transcriber` interface as whisper/azure).
3. For live captions when `TRANSCRIBE_API=parakeet`, use a single shared Nemotron streaming recognizer per call instead of the Whisper transcriber pool.
4. Optional dedicated Docker image target (e.g. `calls-transcriber:parakeet`) so default Hub images stay lean.
5. Document env vars, licenses, and resource requirements.

### Questions for maintainers

1. Is there appetite for a second local backend alongside whisper.cpp, or a longer-term goal to replace Whisper for live captions?
2. Preferred API name: `parakeet`, `nemospeech`, or something else?
3. Should the official image bundle both backends, or ship a separate tag?
4. Any concerns on model licenses for redistribution via Docker Hub?

---

## Labels suggérés

`enhancement`, `live-captions`, `transcription` (selon les labels du dépôt)

## Lien de création

https://github.com/mattermost/calls-transcriber/issues/new
