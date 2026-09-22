// Brown's Stages, ported from claudeBlast/Models/ChildProfile.swift. Names a
// developmental target (MLU + morpheme inventory) instead of a school grade
// — a far more actionable instruction for the sentence model, and the axis
// caregivers actually reason about.

export const STAGES = {
  one: {
    id: "one",
    label: "Stage I",
    detail: "Uses one word at a time. Each tile speaks its own word.",
    appBehavior: "Classic AAC: each tap speaks its own word. No AI, and no key needed.",
    requiresAPIKey: false,
    interactionMode: "single-word",
    tileCap: 1,
  },
  twoThree: {
    id: "twoThree",
    label: "Stage II-III",
    detail: "Putting two and three words together. Up to 4 tiles per sentence.",
    appBehavior: "AI turns up to 4 tiles into a spoken sentence. Needs an OpenAI key.",
    requiresAPIKey: true,
    interactionMode: "sentence",
    tileCap: 4,
  },
  fourPlus: {
    id: "fourPlus",
    label: "Stage IV+",
    detail: "Building longer sentences. You choose how many tiles.",
    appBehavior: "AI builds longer sentences from the tiles you allow. Needs an OpenAI key.",
    requiresAPIKey: true,
    interactionMode: "sentence",
    tileCap: 8,
  },
};

export function promptDescriptor(stageId, escalating = false) {
  switch (stageId) {
    case "one":
      return "at Brown's Stage I: single words, mean utterance length 1.0-2.0, " +
        "no grammatical morphemes";
    case "twoThree": {
      const base = "at Brown's Stage II-III: mean utterance length 2.0-3.0, two- and " +
        "three-word combinations, early grammatical morphemes only (present " +
        "progressive -ing, the prepositions in and on, regular plural -s)";
      return escalating
        ? base + ". They are insisting right now, so this sentence may be longer " +
            "and more forceful than their usual level — keep the words simple, " +
            "but do not shorten it back down"
        : base + ". Keep sentences short and concrete; do not use complex clauses";
    }
    case "fourPlus":
      return "at Brown's Stage IV or later: mean utterance length above 3.0, " +
        "full simple sentences with embedding and coordination, including " +
        "irregular past tense, possessives, articles and contractible copula";
    default:
      return promptDescriptor("twoThree", escalating);
  }
}
