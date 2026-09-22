// Materializes a scene's pages from the command DSL, ported from
// claudeBlast/Models/SceneJSON.swift.
//
// Each entry in a page's `tiles` array is a command run in document order
// against a working, key-indexed tile list — not a literal tile. `link`
// updates an existing tile in place (preserving position) or appends;
// `remove` drops a tile if present. See docs/porting.md and SceneJSON.swift
// for the full command shapes.

function classSelector(cmd, vocabList) {
  const classes = Array.isArray(cmd.class) ? cmd.class : [cmd.class];
  const exclude = new Set(cmd.exclude || []);
  let candidates = vocabList.filter(
    (t) => classes.includes(t.wordClass) && !exclude.has(t.key)
  );
  if (cmd.orderBy === "name") {
    candidates = [...candidates].sort((a, b) => a.key.localeCompare(b.key));
  }
  // orderBy "score" has no scoring data ported yet — falls back to vocab
  // declaration order, same as the default.
  if (cmd.limit) candidates = candidates.slice(0, cmd.limit);
  return candidates.map((t) => ({ key: t.key, audible: true }));
}

// Applies one page's command list against the vocabulary, returning an
// ordered array of { key, audible, link?, to? } tile placements.
export function materializePage(pageJson, vocabByKey) {
  const vocabList = [...vocabByKey.values()];
  const working = [];
  const indexByKey = new Map();

  function upsert(entry) {
    if (indexByKey.has(entry.key)) {
      working[indexByKey.get(entry.key)] = entry;
    } else {
      indexByKey.set(entry.key, working.length);
      working.push(entry);
    }
  }

  function remove(key) {
    if (!indexByKey.has(key)) return;
    const idx = indexByKey.get(key);
    working.splice(idx, 1);
    indexByKey.delete(key);
    for (const [k, i] of indexByKey) if (i > idx) indexByKey.set(k, i - 1);
  }

  for (const cmd of pageJson.tiles) {
    if ("class" in cmd) {
      for (const entry of classSelector(cmd, vocabList)) upsert(entry);
    } else if ("keys" in cmd) {
      for (const key of cmd.keys) upsert({ key, audible: true });
    } else if ("link" in cmd) {
      upsert({ key: cmd.link, to: cmd.to, audible: cmd.audible, link: true });
    } else if ("remove" in cmd) {
      remove(cmd.remove);
    }
  }

  return working;
}

// Materializes every page in a scene into { pageKey -> [placements] }.
export function materializeScene(sceneJson, vocabByKey) {
  const pages = new Map();
  for (const page of sceneJson.pages) {
    pages.set(page.key, materializePage(page, vocabByKey));
  }
  return pages;
}
