// Sentence-generation prompt assembly, ported from
// claudeBlast/Engine/SentencePromptBuilder.swift. See docs/porting.md §5.2 —
// the rules here are what took the most iteration to get right upstream.

import { promptDescriptor } from "./brownsStage.js";

const CATEGORY_HONOR_RULE =
  "The category in parentheses after a word is that word's intended meaning — honor it even when unusual.";

// Reinforces the escalation ladder for a repeated tile selection. Cumulative
// and graduated by count — each rung must sound more insistent than the
// last, since capitals/exclamation marks alone don't change how most TTS
// engines actually sound (docs/porting.md §5.3).
function escalationPrompt(count) {
  return `The child just selected the SAME tiles again — repeat #${count}. Repetition is how a ` +
    "non-verbal child turns up the volume: the want hasn't changed, but they mean it MORE. " +
    "Your own previous sentence for this want is your most recent reply above. Make THIS " +
    "sentence clearly more insistent than that one — never calmer, never the same wording, " +
    "escalate on every repeat while keeping the exact same want.\n\n" +
    "While escalating you MAY use more words than the child's usual level allows, and the " +
    "sentence may grow longer on each rung. Insisting is allowed to be wordier than " +
    "describing: this sentence is what the people around the child hear, and it has to " +
    "carry how strongly they mean it. Do not introduce a new want — only more insistence " +
    "about the one they chose.\n\n" +
    `Climb this intensity ladder as the repeat count rises (you are at #${count}):\n` +
    '• 1 — add urgency and a please ("really", "right now").\n' +
    "• 2 — turn the want into a NEED and keep the urgency words you already added " +
    '("I really NEED … right now!"). Escalating never means removing urgency.\n' +
    "• 3 — very emphatic: put the most important word in CAPITALS and end with an " +
    "exclamation.\n" +
    "• 4+ — maximal: several words in ALL-CAPS with multiple exclamation marks, like a " +
    "child on the edge of tears who will not be ignored.\n\n" +
    "The GRAMMAR BY WORD CLASS rule still holds at every rung — escalating is never a " +
    "reason to move a word into a role it cannot take. In particular a (feeling) or " +
    '(health) word never becomes something wanted: "I WANT HUNGRY NOW" is always wrong, ' +
    "however loud the child is.\n\n" +
    "Because intensifiers alone run out fast, escalate a feeling by making the request it " +
    "IMPLIES more urgent — hungry implies eating, tired implies rest, hurt implies help:\n" +
    '"Dad, I am hungry." → "Dad, I am really hungry, can I eat?" → "Dad, I am SO hungry! I ' +
    'need to eat now!" → "DAD! I am SO, SO HUNGRY! I need to EAT NOW!!!"\n' +
    "That is not a new want — it is the same one, said more urgently.\n\n" +
    "Every rung must be a grammatical English sentence. Capitals are for emphasis only — " +
    "never reshape the grammar around a word just to capitalise it.\n\n" +
    'Example trajectory for a generic want, "juice":\n' +
    '"Can I please have some juice?" → "I really want juice right now." → ' +
    '"I need JUICE now!" → "I WANT JUICE NOW!!!"\n' +
    "Apply that escalation to the child's actual tiles — do not mention juice.";
}

// `sentencePromptJson` is the array loaded from data/sentence_prompt.json.
export function buildSystemMessages(sentencePromptJson, { stage, repetitionCount = 0 }) {
  const stageText = promptDescriptor(stage, repetitionCount > 0);
  const messages = sentencePromptJson.map((line) => ({
    role: "system",
    content: line.replace("{stage}", stageText),
  }));
  messages.push({ role: "system", content: CATEGORY_HONOR_RULE });
  if (repetitionCount > 0) {
    messages.push({ role: "system", content: escalationPrompt(repetitionCount) });
  }
  return messages;
}

// The user turn: just the selected tiles as "word (class)", comma-joined.
// Tile order is explicitly incidental (see data/sentence_prompt.json) — this
// stays pure tile content; enhancements live in the system prompt.
export function formatUserPrompt(tiles) {
  return tiles.map((t) => `${t.label} (${t.wordClass})`).join(", ");
}
