//go:build !nemospeech

package nemospeech

import (
	"fmt"

	"github.com/mattermost/calls-transcriber/cmd/transcriber/transcribe"
)

var errNotBuilt = fmt.Errorf("parakeet/nemotron support was not compiled in (build with -tags nemospeech)")

type Recognizer struct{}

type Stream struct{}

func NewRecognizer(_ RecognizerConfig) (*Recognizer, error) {
	return nil, errNotBuilt
}

func (r *Recognizer) Destroy() error { return errNotBuilt }

func (r *Recognizer) Transcribe(_ []float32) ([]transcribe.Segment, string, error) {
	return nil, "", errNotBuilt
}

func (r *Recognizer) StartStream(_ string) (*Stream, error) {
	return nil, errNotBuilt
}

func (s *Stream) Push(_ []float32, _ int32) error { return errNotBuilt }

func (s *Stream) Next() (string, bool, bool, error) { return "", false, false, errNotBuilt }

func (s *Stream) ForceEndpoint() error { return errNotBuilt }

func (s *Stream) Finish() error { return errNotBuilt }

func (s *Stream) Close() {}
