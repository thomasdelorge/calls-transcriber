//go:build nemospeech

package nemospeech

// #cgo linux LDFLAGS: -lnemo_speech_asr_c -lnemo_speech_asr -lstdc++
// #cgo linux CFLAGS: -I/opt/nemo-speech/include
// #cgo linux LDFLAGS: -L/opt/nemo-speech/lib -Wl,-rpath,/opt/nemo-speech/lib
// #include <nemo_speech/asr.h>
// #include <stdlib.h>
import "C"

import (
	"fmt"
	"runtime"
	"sync"
	"unsafe"

	"github.com/mattermost/calls-transcriber/cmd/transcriber/transcribe"
)

type Recognizer struct {
	cfg RecognizerConfig
	rec *C.nemo_speech_asr_recognizer
	mu  sync.Mutex // guards recognizer-level C API calls (StartStream, Destroy, Transcribe)
}

type Stream struct {
	s        *C.nemo_speech_asr_stream
	langCStr *C.char
}

func lastError() string {
	p := C.nemo_speech_asr_last_error()
	if p == nil {
		return "unknown NeMo-Speech.cpp error"
	}
	return C.GoString(p)
}

func NewRecognizer(cfg RecognizerConfig) (*Recognizer, error) {
	if err := cfg.IsValid(); err != nil {
		return nil, err
	}

	cPath := C.CString(cfg.ModelFile)
	defer C.free(unsafe.Pointer(cPath))

	var backend C.nemo_speech_asr_backend_config
	backend.size = C.size_t(unsafe.Sizeof(backend))
	backend.gpu = -1

	var model C.nemo_speech_asr_model_config
	model.size = C.size_t(unsafe.Sizeof(model))
	model.path = cPath

	var recCfg C.nemo_speech_asr_recognizer_config
	recCfg.size = C.size_t(unsafe.Sizeof(recCfg))
	recCfg.backend = &backend
	recCfg.model = &model

	var streaming C.nemo_speech_asr_streaming_config
	var endpointing C.nemo_speech_asr_endpointing_config
	if cfg.Streaming {
		streaming.size = C.size_t(unsafe.Sizeof(streaming))
		rctx := cfg.RNNTRightContext
		if rctx == 0 {
			rctx = DefaultRNNTRightCtx
		}
		streaming.rnnt_right_context = C.int32_t(rctx)
		streaming.chunk_size = C.float(DefaultStreamChunkSec)
		streaming.ctc_left_padding = C.float(DefaultCTCLeftPadSec)
		streaming.ctc_right_padding = C.float(DefaultCTCRightPadSec)
		recCfg.streaming = &streaming

		if cfg.EnableEndpointing {
			endpointing.size = C.size_t(unsafe.Sizeof(endpointing))
			endpointing.enable = C.bool(true)
			recCfg.endpointing = &endpointing
		}
	}

	// recCfg holds pointers to other Go C structs; cgo refuses that unless pinned.
	var pin runtime.Pinner
	defer pin.Unpin()
	pin.Pin(&backend)
	pin.Pin(&model)
	pin.Pin(&recCfg)
	if cfg.Streaming {
		pin.Pin(&streaming)
		if cfg.EnableEndpointing {
			pin.Pin(&endpointing)
		}
	}

	var rec *C.nemo_speech_asr_recognizer
	if st := C.nemo_speech_asr_create(&recCfg, &rec); st != C.NEMO_SPEECH_ASR_OK || rec == nil {
		return nil, fmt.Errorf("nemo_speech_asr_create failed: %s", lastError())
	}

	return &Recognizer{cfg: cfg, rec: rec}, nil
}

func (r *Recognizer) Destroy() error {
	if r == nil || r.rec == nil {
		return fmt.Errorf("recognizer is not initialized")
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.rec == nil {
		return fmt.Errorf("recognizer is not initialized")
	}
	C.nemo_speech_asr_destroy(r.rec)
	r.rec = nil
	return nil
}

func (r *Recognizer) Transcribe(samples []float32) ([]transcribe.Segment, string, error) {
	if r == nil || r.rec == nil {
		return nil, "", fmt.Errorf("recognizer is not initialized")
	}
	if len(samples) == 0 {
		return nil, "", fmt.Errorf("samples should not be empty")
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if r.rec == nil {
		return nil, "", fmt.Errorf("recognizer is not initialized")
	}

	opts := C.nemo_speech_asr_recognition_options_default()
	opts.enable_word_time_offsets = C.bool(true)
	lang := ResolveLanguageCode(r.cfg.Language)
	var cLang *C.char
	if lang != "" {
		cLang = C.CString(lang)
		defer C.free(unsafe.Pointer(cLang))
		opts.language_code = cLang
	}

	var result *C.nemo_speech_asr_result
	st := C.nemo_speech_asr_recognize_f32(
		r.rec,
		&opts,
		(*C.float)(unsafe.Pointer(&samples[0])),
		C.size_t(len(samples)),
		C.int32_t(DefaultSampleRate),
		&result,
	)
	if st != C.NEMO_SPEECH_ASR_OK {
		return nil, "", fmt.Errorf("nemo_speech_asr_recognize_f32 failed: %s", lastError())
	}
	if result == nil {
		return nil, "", nil
	}
	defer C.nemo_speech_asr_result_destroy(result)

	return resultToSegments(result)
}

func (r *Recognizer) StartStream(language string) (*Stream, error) {
	if r == nil || r.rec == nil {
		return nil, fmt.Errorf("recognizer is not initialized")
	}

	r.mu.Lock()
	defer r.mu.Unlock()
	if r.rec == nil {
		return nil, fmt.Errorf("recognizer is not initialized")
	}

	opts := C.nemo_speech_asr_recognition_options_default()
	opts.interim_results = C.bool(true)
	lang := ResolveLanguageCode(language)
	var langCStr *C.char
	if lang != "" {
		langCStr = C.CString(lang)
		opts.language_code = langCStr
	}

	var stream *C.nemo_speech_asr_stream
	if st := C.nemo_speech_asr_streaming_recognize(r.rec, &opts, &stream); st != C.NEMO_SPEECH_ASR_OK || stream == nil {
		if langCStr != nil {
			C.free(unsafe.Pointer(langCStr))
		}
		return nil, fmt.Errorf("nemo_speech_asr_streaming_recognize failed: %s", lastError())
	}
	return &Stream{s: stream, langCStr: langCStr}, nil
}

func (s *Stream) Push(samples []float32, sampleRate int32) error {
	if s == nil || s.s == nil {
		return fmt.Errorf("stream is not initialized")
	}
	if len(samples) == 0 {
		return nil
	}
	if sampleRate <= 0 {
		sampleRate = DefaultSampleRate
	}
	st := C.nemo_speech_asr_stream_push_f32(
		s.s,
		(*C.float)(unsafe.Pointer(&samples[0])),
		C.size_t(len(samples)),
		C.int32_t(sampleRate),
	)
	if st != C.NEMO_SPEECH_ASR_OK {
		return fmt.Errorf("nemo_speech_asr_stream_push_f32 failed: %s", lastError())
	}
	return nil
}

func (s *Stream) Next() (text string, isFinal bool, ok bool, err error) {
	if s == nil || s.s == nil {
		return "", false, false, fmt.Errorf("stream is not initialized")
	}
	var result *C.nemo_speech_asr_result
	st := C.nemo_speech_asr_stream_next(s.s, &result)
	if st != C.NEMO_SPEECH_ASR_OK {
		return "", false, false, fmt.Errorf("nemo_speech_asr_stream_next failed: %s", lastError())
	}
	if result == nil {
		return "", false, false, nil
	}
	defer C.nemo_speech_asr_result_destroy(result)

	if C.nemo_speech_asr_result_alternative_count(result) == 0 {
		return "", bool(C.nemo_speech_asr_result_is_final(result)), true, nil
	}
	raw := C.GoString(C.nemo_speech_asr_result_transcript(result, 0))
	return StripLangTags(raw), bool(C.nemo_speech_asr_result_is_final(result)), true, nil
}

func (s *Stream) ForceEndpoint() error {
	if s == nil || s.s == nil {
		return fmt.Errorf("stream is not initialized")
	}
	if st := C.nemo_speech_asr_stream_force_endpoint(s.s); st != C.NEMO_SPEECH_ASR_OK {
		return fmt.Errorf("nemo_speech_asr_stream_force_endpoint failed: %s", lastError())
	}
	return nil
}

func (s *Stream) Finish() error {
	if s == nil || s.s == nil {
		return fmt.Errorf("stream is not initialized")
	}
	if st := C.nemo_speech_asr_stream_finish(s.s); st != C.NEMO_SPEECH_ASR_OK {
		return fmt.Errorf("nemo_speech_asr_stream_finish failed: %s", lastError())
	}
	return nil
}

func (s *Stream) Close() {
	if s == nil {
		return
	}
	if s.s != nil {
		C.nemo_speech_asr_stream_close(s.s)
		s.s = nil
	}
	if s.langCStr != nil {
		C.free(unsafe.Pointer(s.langCStr))
		s.langCStr = nil
	}
}

func resultToSegments(result *C.nemo_speech_asr_result) ([]transcribe.Segment, string, error) {
	if C.nemo_speech_asr_result_alternative_count(result) == 0 {
		return nil, "", nil
	}

	text := StripLangTags(C.GoString(C.nemo_speech_asr_result_transcript(result, 0)))
	lang := ""
	if n := C.nemo_speech_asr_result_language_count(result, 0); n > 0 {
		lang = ToISO6391(C.GoString(C.nemo_speech_asr_result_language_code(result, 0, 0)))
	}

	nWords := int(C.nemo_speech_asr_result_word_count(result, 0))
	if nWords > 0 {
		words := make([]TimedWord, nWords)
		for i := 0; i < nWords; i++ {
			words[i] = TimedWord{
				Text:    C.GoString(C.nemo_speech_asr_result_word_text(result, 0, C.size_t(i))),
				StartMS: int64(C.nemo_speech_asr_result_word_start_time(result, 0, C.size_t(i))),
				EndMS:   int64(C.nemo_speech_asr_result_word_end_time(result, 0, C.size_t(i))),
			}
		}
		segments := GroupWordsIntoSegments(words, DefaultMaxSegmentDurMS)
		if len(segments) == 0 {
			return nil, lang, nil
		}
		return segments, lang, nil
	}

	seg := transcribe.Segment{Text: text}
	if text == "" {
		return nil, lang, nil
	}
	return []transcribe.Segment{seg}, lang, nil
}
