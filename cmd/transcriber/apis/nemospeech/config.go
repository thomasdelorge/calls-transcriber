package nemospeech

import (
	"fmt"
	"os"
)

const (
	DefaultParakeetModel = "parakeet-tdt-0.6b-v3.q8_0.gguf"
	DefaultNemotronModel = "nemotron-3.5-asr-streaming-0.6b.q8_0.gguf"
	DefaultSampleRate    = 16000
	DefaultRNNTRightCtx  = 3
	// Official NeMo-Speech.cpp ASR streaming defaults (seconds).
	// Passing a streaming_config pointer with zeros is not "use defaults":
	// the C API requires chunk_size > 0 and paddings >= 0.
	DefaultStreamChunkSec = 0.16
	DefaultCTCLeftPadSec  = 1.92
	DefaultCTCRightPadSec = 1.92
)

type RecognizerConfig struct {
	ModelFile         string
	Language          string
	Streaming         bool
	RNNTRightContext  int32
	EnableEndpointing bool
}

func (c RecognizerConfig) IsValid() error {
	if c.ModelFile == "" {
		return fmt.Errorf("invalid ModelFile: should not be empty")
	}
	if _, err := os.Stat(c.ModelFile); err != nil {
		return fmt.Errorf("invalid ModelFile: failed to stat model file: %w", err)
	}
	return nil
}

func ModelPath(modelsDir, filename string) string {
	if modelsDir == "" {
		modelsDir = "/models"
	}
	return modelsDir + "/" + filename
}
