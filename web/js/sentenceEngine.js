// Sentence-mode engine: tiles collect in a tray, then a model assembles them
// into a spoken sentence. Ported from claudeBlast/Engine/SentenceEngine.swift
// and docs/porting.md §5.

import { buildSystemMessages, formatUserPrompt } from "./promptBuilder.js";
import { cacheKey, stableKey } from "./cacheKeyPolicy.js";
import { cacheLookup, cacheStore } from "./store.js";
import { generateSentence, MODEL } from "./openai.js";
import { speak } from "./speech.js";

const DEBOUNCE_MS = 350;
const IDLE_CLEAR_MS = 30_000;

export class SentenceEngine {
  constructor({ sentencePromptJson, settings, onChange }) {
    this.sentencePromptJson = sentencePromptJson;
    this.settings = settings;
    this.onChange = onChange || (() => {});
    this.tray = []; // selected tile objects, in tap order
    this.lastSentence = "";
    this.history = []; // last N generated sentences (conversation context)
    this.repeatCounts = new Map(); // stableKey -> repeat count
    this.debounceHandle = null;
    this.idleHandle = null;
    this.generation = 0; // bumped on every tray change — staleness guard
  }

  get maxTiles() {
    return this.settings.maxTilesPerGroup || 4;
  }

  addTile(tile) {
    if (this.tray.length >= this.maxTiles) return;
    this.tray.push(tile);
    this._armIdleTimer();
    this._scheduleGeneration();
    this.onChange(this._state());
  }

  // The tray has no back button — tapping a tile in the tray removes it
  // (docs/porting.md §4).
  removeTile(index) {
    this.tray.splice(index, 1);
    this.onChange(this._state());
    if (this.tray.length > 0) this._scheduleGeneration();
  }

  clear() {
    this.tray = [];
    clearTimeout(this.debounceHandle);
    clearTimeout(this.idleHandle);
    this.onChange(this._state());
  }

  _armIdleTimer() {
    clearTimeout(this.idleHandle);
    this.idleHandle = setTimeout(() => this.clear(), IDLE_CLEAR_MS);
  }

  _scheduleGeneration() {
    clearTimeout(this.debounceHandle);
    const atCap = this.tray.length >= this.maxTiles;
    // Fires immediately when the tile cap is hit; otherwise waits for the
    // child to stop tapping.
    this.debounceHandle = setTimeout(() => this._generate(), atCap ? 0 : DEBOUNCE_MS);
  }

  async _generate() {
    if (this.tray.length === 0) return;
    const tiles = [...this.tray];
    const myGeneration = ++this.generation;
    const key = stableKey(tiles);
    const isRepeat = this.repeatCounts.has(key);
    const repeatCount = isRepeat ? this.repeatCounts.get(key) + 1 : 0;
    this.repeatCounts.set(key, repeatCount);

    // Cache lookup — skipped for repeats, since the whole point of a repeat
    // is to produce something different (an escalation).
    if (!isRepeat) {
      const hit = cacheLookup(cacheKey({ model: MODEL, stage: this.settings.stage, tiles }));
      if (hit) {
        this._deliver(hit.sentence, tiles, myGeneration);
        return;
      }
    }

    if (this.settings.provider !== "openai" || !this.settings.openaiApiKey) {
      const mock = this._mockSentence(tiles, repeatCount);
      this._deliver(mock, tiles, myGeneration);
      return;
    }

    try {
      const messages = buildSystemMessages(this.sentencePromptJson, {
        stage: this.settings.stage,
        repetitionCount: repeatCount,
      });
      for (const s of this.history.slice(-5)) {
        messages.push({ role: "assistant", content: s });
      }
      messages.push({ role: "user", content: formatUserPrompt(tiles) });

      const sentence = await generateSentence({ apiKey: this.settings.openaiApiKey, messages });

      // Staleness guard: if the tray changed while we were awaiting the
      // response, discard it — the child has already moved on.
      if (myGeneration !== this.generation) return;

      if (!isRepeat) {
        cacheStore(cacheKey({ model: MODEL, stage: this.settings.stage, tiles }), sentence);
      }
      this._deliver(sentence, tiles, myGeneration);
    } catch (err) {
      if (myGeneration !== this.generation) return;
      this.onChange({ ...this._state(), error: err.message });
    }
  }

  _deliver(sentence, tiles, myGeneration) {
    if (myGeneration !== this.generation) return;
    this.lastSentence = sentence;
    this.history.push(sentence);
    if (this.history.length > 5) this.history.shift();
    speak(sentence, this.settings);
    this.onChange(this._state());
    this._armIdleTimer();
  }

  // No-key / no-network placeholder, so sentence mode is demoable without an
  // OpenAI key (mirrors MockSentenceProvider).
  _mockSentence(tiles, repeatCount) {
    const words = tiles.map((t) => t.label).join(" ");
    const bang = repeatCount > 0 ? "!".repeat(Math.min(repeatCount, 3)) : "";
    return `(mock) ${words}${bang}`;
  }

  replay() {
    if (this.lastSentence) speak(this.lastSentence, this.settings);
  }

  _state() {
    return { tray: [...this.tray], lastSentence: this.lastSentence, error: null };
  }
}
