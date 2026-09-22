// Core data model helpers, ported from claudeBlast/Models/TileModel.swift.

// Canonical tile key: lowercased, internal whitespace collapsed to
// underscores. Language-neutral identifier — never translated (see
// docs/porting.md §2, "the one irreversible rule").
export function normalizeKey(raw) {
  return raw
    .toLowerCase()
    .trim()
    .split(/\s+/)
    .join("_");
}

// Human label: underscores back to spaces, no capitalization.
export function labelForKey(key) {
  return key.replace(/_/g, " ");
}

// Load vocabulary.json into a Map keyed by tile key, resolving artKey
// (bundleImage alias when present, else the key itself — "art belongs to
// the picture, not the tile", docs/porting.md §3).
export function buildVocabulary(vocabularyJson) {
  const byKey = new Map();
  for (const entry of vocabularyJson) {
    const key = normalizeKey(entry.key);
    byKey.set(key, {
      key,
      wordClass: entry.wordClass,
      artKey: entry.bundleImage ? normalizeKey(entry.bundleImage) : key,
      label: labelForKey(key),
    });
  }
  return byKey;
}
