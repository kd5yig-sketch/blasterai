// TTS wrapper around the Web Speech API, standing in for AVSpeechSynthesizer
// (docs/porting.md §9: "Any TTS with selectable voices"). On Linux this is
// backed by whatever the browser wires up — typically speech-dispatcher /
// espeak-ng — so voice quality depends on what the distro ships; steering
// users to a higher-quality installed voice matters here just as it did on
// iOS.

const synth = window.speechSynthesis;

let voices = [];
function loadVoices() {
  voices = synth.getVoices();
}
loadVoices();
if (synth.onvoiceschanged !== undefined) {
  synth.onvoiceschanged = loadVoices;
}

export function availableVoices() {
  return voices;
}

export function selectedVoice(settings) {
  if (settings.voiceURI) {
    const match = voices.find((v) => v.voiceURI === settings.voiceURI);
    if (match) return match;
  }
  return null;
}

// Some browsers (observed: Brave on Linux) implement the Web Speech API but
// never populate a voice list and never surface an error — a tap just makes
// no sound, with nothing in the console to say why. That's indistinguishable
// from a real bug, so app.js wires this up to an on-screen warning instead
// of leaving it silent.
let warningHandler = null;
export function onSpeechWarning(handler) {
  warningHandler = handler;
}

// A tap speaks immediately — before any network, any lookup, any spinner
// (docs/porting.md §4). Cancelling any in-flight utterance keeps repeated
// taps responsive rather than queuing a backlog of stale words.
export function speak(text, settings = {}) {
  if (!text) return;
  synth.cancel();

  if (voices.length === 0) {
    warningHandler?.(
      "No text-to-speech voices found in this browser. Try Google Chrome or Firefox instead."
    );
    return;
  }

  const utterance = new SpeechSynthesisUtterance(text);
  const voice = selectedVoice(settings);
  if (voice) utterance.voice = voice;
  utterance.rate = settings.rate ?? 1.0;
  utterance.pitch = settings.pitch ?? 1.0;
  utterance.onerror = (event) => {
    warningHandler?.(`Speech failed (${event.error}). Try a different voice in Settings.`);
  };
  synth.speak(utterance);
}

export function stop() {
  synth.cancel();
}
