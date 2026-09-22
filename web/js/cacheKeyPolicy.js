// Sentence cache key policy, ported from
// claudeBlast/Engine/Cache/CacheKeyPolicy.swift.
//
// Key shape: <model>/v<promptVersion>/b<stage>#<sorted key:class pairs>
//
// Order-independent (tiles are deduplicated and sorted) so two tap orders of
// the same words share one cache entry. Versioned by model and prompt so a
// prompt change can invalidate history by bumping PROMPT_VERSION.

export const PROMPT_VERSION = 1;

// Bump whenever a prompt change should invalidate previously cached
// sentences (see docs/porting.md §5.4).
export function cacheKey({ model, stage, tiles }) {
  const pairs = tiles
    .map((t) => `${t.key}:${t.wordClass}`)
    .sort()
    .join(",");
  return `${model}/v${PROMPT_VERSION}/b${stage}#${pairs}`;
}

// Version-independent key for caregiver overrides — survives a model swap
// or prompt bump because a hand-typed correction is about the words the
// child picked, not the machinery.
export function stableKey(tiles) {
  return tiles
    .map((t) => t.key)
    .sort()
    .join(",");
}
