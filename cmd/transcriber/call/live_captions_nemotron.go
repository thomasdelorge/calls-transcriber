package call

import (
	"log/slog"
	"path/filepath"
	"time"

	"github.com/mattermost/calls-transcriber/cmd/transcriber/apis/nemospeech"
	"github.com/mattermost/calls-transcriber/cmd/transcriber/opus"

	"github.com/mattermost/mattermost-plugin-calls/server/public"
)

const (
	liveCaptionsDrainTick      = 200 * time.Millisecond
	minNemotronCaptionInterval = 100 * time.Millisecond
)

type nemotronCaptionState struct {
	prevText string
	lastSend time.Time
}

func (t *Transcriber) initNemotronLiveCaptions() error {
	rec, err := nemospeech.NewRecognizer(nemospeech.RecognizerConfig{
		ModelFile:         filepath.Join(getModelsDir(), nemospeech.DefaultNemotronModel),
		Language:          t.cfg.LiveCaptionsLanguage,
		Streaming:         true,
		RNNTRightContext:  int32(t.cfg.LiveCaptionsRNNTRightContext),
		EnableEndpointing: true,
	})
	if err != nil {
		return err
	}
	t.liveASR = rec
	n := t.cfg.LiveCaptionsNumTranscribers
	if n < 1 {
		n = 1
	}
	t.liveASRSlots = make(chan struct{}, n)
	slog.Info("nemotron live captions recognizer ready",
		slog.String("language", t.cfg.LiveCaptionsLanguage),
		slog.Int("rnnt_right_context", t.cfg.LiveCaptionsRNNTRightContext),
		slog.Int("max_streams", n))
	return nil
}

func (t *Transcriber) processLiveCaptionsNemotron(ctx trackContext, pktPayloadsCh <-chan []byte) {
	defer t.liveCaptionsWg.Done()

	if t.liveASR == nil {
		slog.Error("processLiveCaptionsNemotron: recognizer is not initialized",
			slog.String("trackID", ctx.trackID))
		return
	}

	opusDec, err := opus.NewDecoder(trackOutAudioRate, trackAudioChannels)
	if err != nil {
		slog.Error("processLiveCaptionsNemotron: failed to create opus decoder",
			slog.String("err", err.Error()), slog.String("trackID", ctx.trackID))
		return
	}
	defer func() {
		if err := opusDec.Destroy(); err != nil {
			slog.Error("processLiveCaptionsNemotron: failed to destroy decoder",
				slog.String("err", err.Error()), slog.String("trackID", ctx.trackID))
		}
	}()

	t.liveASRWg.Add(1)
	stream, err := t.liveASR.StartStream(t.cfg.LiveCaptionsLanguage)
	if err != nil {
		t.liveASRWg.Done()
		slog.Error("processLiveCaptionsNemotron: failed to start stream",
			slog.String("err", err.Error()), slog.String("trackID", ctx.trackID))
		return
	}
	defer func() {
		_ = stream.Finish()
		t.drainCaptionStream(ctx, stream, &nemotronCaptionState{}, 0)
		stream.Close()
		t.liveASRWg.Done()
	}()

	pcmBuf := make([]float32, trackOutFrameSize)
	pcm := make([]float32, 0, trackOutAudioRate)
	ticker := time.NewTicker(liveCaptionsDrainTick)
	defer ticker.Stop()
	captionState := &nemotronCaptionState{}

	flush := func() {
		newAudioLenMs := float64(len(pcm)) * 1000 / float64(trackOutAudioRate)
		if len(pcm) == 0 {
			t.drainCaptionStream(ctx, stream, captionState, 0)
			return
		}
		if err := stream.Push(pcm, trackOutAudioRate); err != nil {
			slog.Error("processLiveCaptionsNemotron: push failed",
				slog.String("err", err.Error()), slog.String("trackID", ctx.trackID))
			if err := t.client.SendWS(wsEvMetric, public.MetricMsg{
				SessionID:  ctx.sessionID,
				MetricName: public.MetricLiveCaptionsTranscriberBufFull,
			}, false); err != nil {
				slog.Error("processLiveCaptionsNemotron: error sending wsEvMetric MetricLiveCaptionsTranscriberBufFull",
					slog.String("err", err.Error()), slog.String("trackID", ctx.trackID))
			}
			pcm = pcm[:0]
			return
		}
		pcm = pcm[:0]
		t.drainCaptionStream(ctx, stream, captionState, newAudioLenMs)
	}

	for {
		select {
		case <-t.captionsPoolDoneCh:
			return
		case payload, ok := <-pktPayloadsCh:
			if !ok {
				flush()
				return
			}
			n, err := opusDec.Decode(payload, pcmBuf)
			if err != nil {
				slog.Error("processLiveCaptionsNemotron: failed to decode audio",
					slog.String("err", err.Error()), slog.String("trackID", ctx.trackID))
				continue
			}
			if n > 0 {
				pcm = append(pcm, pcmBuf[:n]...)
			}
			if len(pcm) >= trackOutAudioRate {
				flush()
			}
		case <-ticker.C:
			flush()
		}
	}
}

func (t *Transcriber) drainCaptionStream(ctx trackContext, stream *nemospeech.Stream, state *nemotronCaptionState, newAudioLenMs float64) {
	for {
		text, isFinal, ok, err := stream.Next()
		if err != nil {
			slog.Error("processLiveCaptionsNemotron: next failed",
				slog.String("err", err.Error()), slog.String("trackID", ctx.trackID))
			return
		}
		if !ok {
			return
		}
		if text == "" {
			if isFinal {
				state.prevText = ""
			}
			continue
		}
		if text == state.prevText {
			if isFinal {
				state.prevText = ""
			}
			continue
		}
		if !isFinal && !state.lastSend.IsZero() && time.Since(state.lastSend) < minNemotronCaptionInterval {
			continue
		}
		if err := t.client.SendWS(wsEvCaption, public.CaptionMsg{
			SessionID:     ctx.sessionID,
			Text:          text,
			NewAudioLenMs: newAudioLenMs,
		}, false); err != nil {
			slog.Error("processLiveCaptionsNemotron: error sending ws captions",
				slog.String("err", err.Error()), slog.String("trackID", ctx.trackID))
			return
		}
		state.prevText = text
		state.lastSend = time.Now()
		if isFinal {
			state.prevText = ""
		}
	}
}
