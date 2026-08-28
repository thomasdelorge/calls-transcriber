package nemospeech

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestGroupWordsIntoSegments(t *testing.T) {
	tcs := []struct {
		name string
		in   []TimedWord
		want []struct {
			text  string
			start int64
			end   int64
		}
	}{
		{
			name: "split on period",
			in: []TimedWord{
				{Text: "Hello", StartMS: 0, EndMS: 200},
				{Text: "world.", StartMS: 250, EndMS: 900},
				{Text: "Again", StartMS: 1000, EndMS: 1400},
			},
			want: []struct {
				text  string
				start int64
				end   int64
			}{
				{"Hello world.", 0, 900},
				{"Again", 1000, 1400},
			},
		},
		{
			name: "split on max duration",
			in: []TimedWord{
				{Text: "one", StartMS: 0, EndMS: 4000},
				{Text: "two", StartMS: 4000, EndMS: 11000},
			},
			want: []struct {
				text  string
				start int64
				end   int64
			}{
				{"one", 0, 4000},
				{"two", 4000, 11000},
			},
		},
	}
	for _, tc := range tcs {
		t.Run(tc.name, func(t *testing.T) {
			got := GroupWordsIntoSegments(tc.in, DefaultMaxSegmentDurMS)
			require.Len(t, got, len(tc.want))
			for i := range tc.want {
				require.Equal(t, tc.want[i].text, got[i].Text)
				require.Equal(t, tc.want[i].start, got[i].StartTS)
				require.Equal(t, tc.want[i].end, got[i].EndTS)
			}
		})
	}
}
