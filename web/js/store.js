// localStorage-backed persistence: settings and the sentence cache. Mirrors
// docs/porting.md §3's framing — single-device storage with no sync, which
// is the right answer for a Linux machine that lives on one desk.

const SETTINGS_KEY = "blaster.settings.v1";
const CACHE_KEY = "blaster.sentenceCache.v1";

const CACHE_MAX_ENTRIES = 2000;
const CACHE_MAX_AGE_MS = 180 * 24 * 60 * 60 * 1000; // 180 days

const DEFAULT_SETTINGS = {
  provider: "mock", // "mock" | "openai"
  openaiApiKey: "",
  imageSet: "classic",
  mode: "single-word", // "single-word" | "sentence"
  voiceURI: "",
  rate: 1.0,
  pitch: 1.0,
  stage: "an early communicator, using two to three word combinations",
  maxTilesPerGroup: 4,
  autoCommitSeconds: 30,
};

export function loadSettings() {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (!raw) return { ...DEFAULT_SETTINGS };
    return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
  } catch {
    return { ...DEFAULT_SETTINGS };
  }
}

export function saveSettings(settings) {
  try {
    localStorage.setItem(SETTINGS_KEY, JSON.stringify(settings));
  } catch {
    // Storage unavailable (private mode, quota) — settings just won't persist.
  }
}

function loadCacheRaw() {
  try {
    const raw = localStorage.getItem(CACHE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function saveCacheRaw(entries) {
  try {
    localStorage.setItem(CACHE_KEY, JSON.stringify(entries));
  } catch {
    // Quota exceeded or unavailable — cache degrades to session-only.
  }
}

// Sweeps entries older than the max age, then trims to the max entry count,
// least-recently-used first (docs/porting.md §5.4 eviction policy).
function evict(entries) {
  const now = Date.now();
  for (const key of Object.keys(entries)) {
    if (now - entries[key].lastUsed > CACHE_MAX_AGE_MS && !entries[key].pinned) {
      delete entries[key];
    }
  }
  const keys = Object.keys(entries);
  if (keys.length > CACHE_MAX_ENTRIES) {
    const unpinned = keys
      .filter((k) => !entries[k].pinned)
      .sort((a, b) => entries[a].lastUsed - entries[b].lastUsed);
    const overflow = keys.length - CACHE_MAX_ENTRIES;
    for (let i = 0; i < overflow && i < unpinned.length; i++) {
      delete entries[unpinned[i]];
    }
  }
  return entries;
}

export function cacheLookup(key) {
  const entries = loadCacheRaw();
  const hit = entries[key];
  if (!hit) return null;
  hit.hitCount = (hit.hitCount || 0) + 1;
  hit.lastUsed = Date.now();
  saveCacheRaw(entries);
  return hit;
}

export function cacheStore(key, sentence, extra = {}) {
  const entries = evict(loadCacheRaw());
  entries[key] = {
    sentence,
    hitCount: entries[key]?.hitCount || 0,
    lastUsed: Date.now(),
    ...extra,
  };
  saveCacheRaw(entries);
}

export function cacheClear() {
  saveCacheRaw({});
}
