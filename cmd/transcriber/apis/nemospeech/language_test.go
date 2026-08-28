package nemospeech

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestResolveLanguageCode(t *testing.T) {
	tcs := []struct {
		in, want string
	}{
		{"", ""},
		{"auto", ""},
		{"AUTO", ""},
		{"en", "en-US"},
		{"fr", "fr-FR"},
		{"fr-FR", "fr-FR"},
		{"fr-CA", "fr-CA"},
		{"pt", "pt-PT"},
		{"pt-BR", "pt-BR"},
		{"en-GB", "en-GB"},
		{"cs", "cs-CZ"},
		{"sv", "sv-SE"},
		{"xx", ""},
		{"  fr  ", "fr-FR"},
	}
	for _, tc := range tcs {
		t.Run(tc.in, func(t *testing.T) {
			require.Equal(t, tc.want, ResolveLanguageCode(tc.in))
		})
	}
}

func TestToISO6391(t *testing.T) {
	require.Equal(t, "fr", ToISO6391("fr-FR"))
	require.Equal(t, "en", ToISO6391("<en-US>"))
	require.Equal(t, "de", ToISO6391("de"))
	require.Equal(t, "", ToISO6391(""))
}

func TestStripLangTags(t *testing.T) {
	require.Equal(t, "Bonjour.", StripLangTags("Bonjour. <fr-FR>"))
	require.Equal(t, "Hello", StripLangTags("Hello"))
}

func TestStreamingGeometryDefaults(t *testing.T) {
	require.Greater(t, DefaultStreamChunkSec, 0.0)
	require.GreaterOrEqual(t, DefaultCTCLeftPadSec, 0.0)
	require.GreaterOrEqual(t, DefaultCTCRightPadSec, 0.0)
}
