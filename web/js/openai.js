// OpenAI sentence provider + failure classification, ported from
// claudeBlast/Services/OpenAI/OpenAIFailure.swift (docs/porting.md §5.5 —
// "the most portable file in the repository").

export const MODEL = "gpt-4o-mini";

// Classifies a failed fetch response into what the device should actually
// do. Two status codes carry four distinct meanings; the status alone does
// not separate them — see the table in OpenAIFailure.swift.
export async function classifyFailure(response) {
  let detail = { type: null, code: null, message: null };
  try {
    const json = await response.json();
    if (json?.error) {
      detail = {
        type: json.error.type ?? null,
        code: json.error.code ?? null,
        message: json.error.message ?? null,
      };
    }
  } catch {
    // Body wasn't JSON — fall through to the per-status default below. A
    // refusal we cannot parse is still a refusal.
  }

  switch (response.status) {
    case 401:
      return { kind: "rejected" };
    case 403:
      if (detail.code === "model_not_found") {
        return { kind: "capability", model: modelNameFrom(detail.message) };
      }
      return { kind: "rejected" };
    case 429:
      if (detail.type === "insufficient_quota") return { kind: "exhausted" };
      return { kind: "transient" };
    case 400:
    case 422:
      if (detail.message) return { kind: "requestRefused", message: detail.message };
      return { kind: "transient" };
    default:
      return { kind: "transient" };
  }
}

function modelNameFrom(message) {
  if (!message) return null;
  const quoted = message.split("`").filter((_, i) => i % 2 === 1);
  return quoted.reverse().find((s) => s.includes("-") && !s.startsWith("proj_")) || null;
}

// One sentence a caregiver can act on. Never OpenAI's own message except for
// a content-policy refusal, where it names what it objected to.
export function caregiverMessage(failure) {
  switch (failure.kind) {
    case "exhausted":
      return "This key is out of credit. The key itself is fine — it works again " +
        "once more credit is added or the spending limit resets.";
    case "rejected":
      return "OpenAI refused this key. It may have been revoked or deleted. " +
        "Add a different key in Settings.";
    case "capability": {
      const what = failure.model ? `the ${failure.model} model` : "a model it needs";
      return `This key cannot use ${what}. Everything that doesn't need it still works.`;
    }
    case "requestRefused":
      return failure.message;
    case "transient":
    default:
      return "Couldn't reach OpenAI just now. Check the connection and try again.";
  }
}

// Calls the Chat Completions API. Throws { failure } on a non-OK response,
// with `failure` already classified via classifyFailure.
export async function generateSentence({ apiKey, messages }) {
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODEL,
      messages,
      temperature: 0.7,
      max_tokens: 120,
    }),
  });

  if (!response.ok) {
    const failure = await classifyFailure(response);
    const err = new Error(caregiverMessage(failure));
    err.failure = failure;
    throw err;
  }

  const json = await response.json();
  return json.choices?.[0]?.message?.content?.trim() ?? "";
}
