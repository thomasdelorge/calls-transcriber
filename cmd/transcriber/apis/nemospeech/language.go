package nemospeech

import (
	"log/slog"
	"strings"
)

// Default ISO 639-1 → Nemotron 3.5 locale. Prefer transcription-ready locales
// when a language has several. Not an exhaustive world map: unknown codes fall
// back to auto-detect rather than a guessed xx-XX.
var iso639ToLocale = map[string]string{
	"ar": "ar-AR",
	"bg": "bg-BG",
	"cs": "cs-CZ",
	"da": "da-DK",
	"de": "de-DE",
	"el": "el-GR",
	"en": "en-US",
	"es": "es-ES",
	"et": "et-EE",
	"fi": "fi-FI",
	"fr": "fr-FR",
	"he": "he-IL",
	"hi": "hi-IN",
	"hr": "hr-HR",
	"hu": "hu-HU",
	"it": "it-IT",
	"ja": "ja-JP",
	"ko": "ko-KR",
	"lt": "lt-LT",
	"lv": "lv-LV",
	"mt": "mt-MT",
	"nb": "nb-NO",
	"nl": "nl-NL",
	"nn": "nn-NO",
	"pl": "pl-PL",
	"pt": "pt-PT",
	"ro": "ro-RO",
	"ru": "ru-RU",
	"sk": "sk-SK",
	"sl": "sl-SI",
	"sv": "sv-SE",
	"th": "th-TH",
	"tr": "tr-TR",
	"uk": "uk-UA",
	"vi": "vi-VN",
	"zh": "zh-CN",
}

// ResolveLanguageCode maps a plugin/env language setting to the value passed as
// nemo_speech_asr_recognition_options.language_code.
//
// Empty, "auto" → "" (model auto-detect).
// Strings containing "-" are treated as locales and passed through (fr-FR, en-GB).
// Two-letter ISO 639-1 codes are mapped via iso639ToLocale.
// Unknown values fall back to auto-detect.
func ResolveLanguageCode(raw string) string {
	s := strings.TrimSpace(raw)
	if s == "" || strings.EqualFold(s, "auto") {
		return ""
	}
	if strings.Contains(s, "-") {
		return s
	}
	if loc, ok := iso639ToLocale[strings.ToLower(s)]; ok {
		return loc
	}
	slog.Warn("unknown ASR language, falling back to auto-detect", slog.String("value", raw))
	return ""
}

// ToISO6391 turns a BCP-47 / tagged code (en-US, <fr-FR>) into a 2-letter code
// for public.Transcription.Language compatibility with Whisper.
func ToISO6391(code string) string {
	s := strings.TrimSpace(code)
	s = strings.Trim(s, "<>")
	if s == "" {
		return ""
	}
	if i := strings.IndexByte(s, '-'); i > 0 {
		s = s[:i]
	}
	if i := strings.IndexByte(s, '_'); i > 0 {
		s = s[:i]
	}
	return strings.ToLower(s)
}

// StripLangTags removes trailing <xx-XX> tokens some Nemotron auto-detect
// paths append after terminal punctuation.
func StripLangTags(text string) string {
	out := text
	for {
		i := strings.LastIndex(out, "<")
		if i < 0 || !strings.HasSuffix(strings.TrimSpace(out), ">") {
			return strings.TrimSpace(out)
		}
		j := strings.LastIndex(out, ">")
		if j < i {
			return strings.TrimSpace(out)
		}
		tag := out[i+1 : j]
		if len(tag) < 2 || len(tag) > 8 {
			return strings.TrimSpace(out)
		}
		out = strings.TrimSpace(out[:i])
	}
}
