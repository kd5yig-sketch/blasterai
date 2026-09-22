import { buildVocabulary } from "./model.js";
import { materializeScene } from "./sceneImporter.js";
import { TileGrid } from "./grid.js";
import { SentenceEngine } from "./sentenceEngine.js";
import { speak, availableVoices } from "./speech.js";
import { loadSettings, saveSettings } from "./store.js";
import { colorForWordClass, labelColorOn } from "./color.js";

const STRIP_MAX = 12;

async function loadJSON(path) {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`Failed to load ${path}: ${res.status}`);
  return res.json();
}

async function main() {
  const [vocabularyJson, sceneJson, imageSets, vocabularyClasses, sentencePromptJson] =
    await Promise.all([
      loadJSON("data/vocabulary.json"),
      loadJSON("data/scenes/core_first.json"),
      loadJSON("data/image_sets.json"),
      loadJSON("data/vocabulary_classes.json"),
      loadJSON("data/sentence_prompt.json"),
    ]);

  const vocabByKey = buildVocabulary(vocabularyJson);
  const scene = materializeScene(sceneJson, vocabByKey);
  const settings = loadSettings();

  const gridEl = document.getElementById("grid");
  const trayEl = document.getElementById("tray");
  const sentenceTextEl = document.getElementById("sentence-text");

  let wordStrip = []; // single-word mode's spoken-word history (FIFO)

  const imageSetPrefix = () =>
    imageSets.find((s) => s.id === settings.imageSet)?.prefix || imageSets[0].prefix;

  const grid = new TileGrid({
    root: gridEl,
    scene,
    vocabByKey,
    vocabularyClasses,
    imageSetPrefix: imageSetPrefix(),
    settings,
    onTap: (vocab) => handleWordTap(vocab),
  });
  grid.render();

  const engine = new SentenceEngine({
    sentencePromptJson,
    settings,
    onChange: (state) => renderTray(state),
  });

  function handleWordTap(vocab) {
    if (settings.mode === "single-word") {
      // A tap speaks immediately — before any network, any lookup, any
      // spinner (docs/porting.md §4).
      speak(vocab.label, settings);
      wordStrip.push(vocab);
      if (wordStrip.length > STRIP_MAX) wordStrip.shift();
      renderStrip();
    } else {
      engine.addTile(vocab);
    }
  }

  function renderStrip() {
    trayEl.innerHTML = "";
    sentenceTextEl.textContent = "";
    for (const [i, vocab] of wordStrip.entries()) {
      trayEl.appendChild(makeChip(vocab, () => {
        wordStrip.splice(i, 1);
        renderStrip();
      }));
    }
  }

  function renderTray(state) {
    trayEl.innerHTML = "";
    for (const [i, vocab] of state.tray.entries()) {
      trayEl.appendChild(makeChip(vocab, () => engine.removeTile(i)));
    }
    sentenceTextEl.textContent = state.error ? `⚠ ${state.error}` : state.lastSentence || "";
  }

  function makeChip(vocab, onRemove) {
    const chip = document.createElement("button");
    chip.type = "button";
    chip.className = "tray-chip";
    const color = colorForWordClass(vocab.wordClass, vocabularyClasses);
    chip.style.background = color;
    chip.style.color = labelColorOn(color);
    chip.textContent = vocab.label;
    chip.addEventListener("click", onRemove);
    return chip;
  }

  document.getElementById("replay-btn").addEventListener("click", () => {
    if (settings.mode === "single-word") {
      if (wordStrip.length) speak(wordStrip.map((w) => w.label).join(" "), settings);
    } else {
      engine.replay();
    }
  });

  document.getElementById("clear-btn").addEventListener("click", () => {
    wordStrip = [];
    renderStrip();
    engine.clear();
  });

  // --- Settings dialog ---

  const dialog = document.getElementById("settings-dialog");
  const modeSelect = document.getElementById("mode-select");
  const imagesetSelect = document.getElementById("imageset-select");
  const providerSelect = document.getElementById("provider-select");
  const apikeyInput = document.getElementById("apikey-input");
  const voiceSelect = document.getElementById("voice-select");
  const maxtilesInput = document.getElementById("maxtiles-input");
  const errorEl = document.getElementById("settings-error");

  for (const set of imageSets) {
    const opt = document.createElement("option");
    opt.value = set.id;
    opt.textContent = set.displayName;
    imagesetSelect.appendChild(opt);
  }

  function populateVoices() {
    voiceSelect.innerHTML = "";
    const none = document.createElement("option");
    none.value = "";
    none.textContent = "System default";
    voiceSelect.appendChild(none);
    for (const v of availableVoices()) {
      const opt = document.createElement("option");
      opt.value = v.voiceURI;
      opt.textContent = `${v.name} (${v.lang})`;
      voiceSelect.appendChild(opt);
    }
  }

  function openSettings() {
    modeSelect.value = settings.mode;
    imagesetSelect.value = settings.imageSet;
    providerSelect.value = settings.provider;
    apikeyInput.value = settings.openaiApiKey;
    maxtilesInput.value = settings.maxTilesPerGroup;
    populateVoices();
    voiceSelect.value = settings.voiceURI;
    errorEl.textContent = "";
    dialog.showModal();
  }

  document.getElementById("settings-btn").addEventListener("click", openSettings);
  document.getElementById("settings-cancel").addEventListener("click", () => dialog.close());

  document.getElementById("settings-form").addEventListener("submit", (e) => {
    e.preventDefault();
    settings.mode = modeSelect.value;
    settings.imageSet = imagesetSelect.value;
    settings.provider = providerSelect.value;
    settings.openaiApiKey = apikeyInput.value.trim();
    settings.voiceURI = voiceSelect.value;
    settings.maxTilesPerGroup = Math.max(1, Math.min(8, Number(maxtilesInput.value) || 4));
    saveSettings(settings);
    grid.imageSetPrefix = imageSetPrefix();
    grid.render();
    dialog.close();
  });

  if (speechSynthesis.onvoiceschanged !== undefined) {
    speechSynthesis.addEventListener("voiceschanged", () => {
      if (dialog.open) populateVoices();
    });
  }
}

main().catch((err) => {
  document.body.innerHTML = `<pre style="color:#fff;padding:20px;white-space:pre-wrap;">Failed to start Blaster:\n${err.stack || err}</pre>`;
});
