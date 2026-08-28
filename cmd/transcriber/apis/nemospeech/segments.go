package nemospeech

import (
	"strings"

	"github.com/mattermost/calls-transcriber/cmd/transcriber/transcribe"
)

// DefaultMaxSegmentDurMS targets ~5–10 s WebVTT cues (whisper-like readability).
const DefaultMaxSegmentDurMS = 10000

type TimedWord struct {
	Text    string
	StartMS int64
	EndMS   int64
}

func endsStrongPunct(word string) bool {
	s := strings.TrimSpace(word)
	if s == "" {
		return false
	}
	switch s[len(s)-1] {
	case '.', '!', '?', ':', ';':
		return true
	default:
		return false
	}
}

// GroupWordsIntoSegments splits word timings on strong punctuation and max duration.
func GroupWordsIntoSegments(words []TimedWord, maxDurMS int64) []transcribe.Segment {
	if len(words) == 0 {
		return nil
	}
	if maxDurMS <= 0 {
		maxDurMS = DefaultMaxSegmentDurMS
	}

	var segments []transcribe.Segment
	var b strings.Builder
	start := words[0].StartMS
	end := words[0].EndMS

	flush := func() {
		text := strings.TrimSpace(b.String())
		if text != "" {
			segments = append(segments, transcribe.Segment{
				Text:    text,
				StartTS: start,
				EndTS:   end,
			})
		}
		b.Reset()
	}

	for i, w := range words {
		if b.Len() == 0 {
			start = w.StartMS
		} else if w.EndMS-start >= maxDurMS {
			flush()
			start = w.StartMS
		}
		if b.Len() > 0 {
			b.WriteByte(' ')
		}
		b.WriteString(w.Text)
		end = w.EndMS

		if endsStrongPunct(w.Text) || i == len(words)-1 {
			flush()
		}
	}
	return segments
}
