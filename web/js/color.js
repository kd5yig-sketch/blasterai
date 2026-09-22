// Modified Fitzgerald Key tile coloring, ported from
// claudeBlast/Services/VocabularyClasses.swift (TileColorResolver).
//
// Color means part of speech, not semantic category: yellow pronouns, green
// verbs, blue describing words, orange nouns, purple questions, red negation,
// pink social, neutral function words. This is the same key TouchChat, Snap
// Core First, LAMP and PODD use, so a child's color sense transfers to a
// school board built on a different app.

const FITZGERALD = {
  pronoun: "rgb(250, 204, 51)",       // yellow
  verb: "rgb(77, 184, 89)",           // green
  adjective: "rgb(92, 179, 245)",     // light blue
  noun: "rgb(245, 153, 41)",          // orange
  question: "rgb(158, 102, 209)",     // purple
  negation: "rgb(230, 74, 69)",       // red
  social: "rgb(242, 140, 184)",       // pink
  interjection: "rgb(242, 140, 184)", // pink
};

const FUNCTION_WORD = "rgb(158, 163, 171)";
export const CHROME = "rgb(142, 142, 147)";
export const NAVIGATION = "rgb(41, 66, 173)";

const FUNCTION_POS = new Set(["preposition", "determiner", "conjunction"]);

export function colorForPartOfSpeech(pos) {
  if (!pos) return CHROME;
  if (FUNCTION_POS.has(pos)) return FUNCTION_WORD;
  return FITZGERALD[pos] || CHROME;
}

export function colorForWordClass(wordClass, vocabularyClasses) {
  const pos = vocabularyClasses[wordClass];
  return colorForPartOfSpeech(pos === undefined ? null : pos);
}

// Rec. 709 luminance, matching the Swift `label(on:)` — readable text color
// (black or white) for a given "rgb(r, g, b)" string.
export function labelColorOn(rgbString) {
  const m = /rgb\((\d+),\s*(\d+),\s*(\d+)\)/.exec(rgbString);
  if (!m) return "#000";
  const [, r, g, b] = m.map(Number);
  const luminance = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
  return luminance >= 0.5 ? "#000" : "#fff";
}
