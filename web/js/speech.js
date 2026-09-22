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

// A tap speaks immediately — before any network, any lookup, any spinner
// (docs/porting.md §4). Cancelling any in-flight utterance keeps repeated
// taps responsive rather than queuing a backlog of stale words.
export function speak(text, settings = {}) {
  if (!text) return;
  synth.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  const voice = selectedVoice(settings);
  if (voice) utterance.voice = voice;
  utterance.rate = settings.rate ?? 1.0;
  utterance.pitch = settings.pitch ?? 1.0;
  synth.speak(utterance);
}

export function stop() {
  synth.cancel();
}
