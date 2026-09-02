//go:build nemospeech

package whisper

import (
	"fmt"

	"github.com/mattermost/calls-transcriber/cmd/transcriber/transcribe"
)

// Parakeet image: whisper.cpp is not linked (ggml symbol clash with NeMo).

var errNotLinked = fmt.Errorf("whisper.cpp is not linked in the Parakeet image")

type Config struct {
	ModelFile     string
	NumThreads    int
	NoContext     bool
	AudioContext  int
	PrintProgress bool
	Language      string
	SingleSegment bool
}

func (c Config) IsValid() error { return errNotLinked }

type Context struct{}

func NewContext(_ Config) (*Context, error) { return nil, errNotLinked }

func (c *Context) Destroy() error { return errNotLinked }

func (c *Context) Transcribe(_ []float32) ([]transcribe.Segment, string, error) {
	return nil, "", errNotLinked
}
