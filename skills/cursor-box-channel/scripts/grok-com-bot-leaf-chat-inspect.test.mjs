import test from "node:test";
import assert from "node:assert/strict";
import {
  inspectPage,
  inspectPageExpression,
  messageMatchesPrompt,
  TARGET_URL,
} from "./grok-com-bot-leaf-chat.mjs";

const prompt = "LIVE-TEST cursor-box-channel 0.3.14 ego-leaf: reply with the token EGOLEAF-OK-1027 then idle.";

function fakePage({ href = TARGET_URL, draft = "", users = [], generating = false, insideComposer = false } = {}) {
  const composer = {
    value: draft,
    innerText: draft,
    getClientRects: () => [{ width: 1, height: 1 }],
    contains: () => insideComposer,
  };
  return {
    document: {
      querySelector(selector) {
        if (selector.includes("textbox")) return composer;
        if (selector.includes("Stop")) return generating ? {} : null;
        return null;
      },
      querySelectorAll(selector) {
        if (!selector.includes("user-message")) return [];
        return users.map((innerText) => ({ innerText }));
      },
    },
    location: { href },
    crypto: { randomUUID: () => "doc-1" },
  };
}

test("messageMatchesPrompt accepts exact, UI suffix, and truncated prefix", () => {
  assert.equal(messageMatchesPrompt(prompt, prompt), true);
  assert.equal(messageMatchesPrompt(`${prompt} Copy`, prompt), true);
  assert.equal(messageMatchesPrompt(prompt.slice(0, 40), prompt), true);
  assert.equal(messageMatchesPrompt("unrelated bubble", prompt), false);
  assert.equal(messageMatchesPrompt("LIVE", prompt), false);
  assert.equal(messageMatchesPrompt("", prompt), false);
});

test("inspectPage counts a bubble with trailing UI chrome", () => {
  const page = fakePage({ draft: "", users: [`${prompt}\nCopy`] });
  const shot = inspectPage(prompt, page);
  assert.equal(shot.matchingCount, 1);
  assert.equal(shot.draft, "");
});

test("inspectPage counts a truncated bubble prefix of the prompt", () => {
  const page = fakePage({ draft: "", users: [prompt.slice(0, 40)] });
  assert.equal(inspectPage(prompt, page).matchingCount, 1);
});

test("inspectPage ignores composer-contained and unrelated bubbles", () => {
  const inside = fakePage({ draft: "", users: [prompt], insideComposer: true });
  assert.equal(inspectPage(prompt, inside).matchingCount, 0);
  const other = fakePage({ draft: "", users: ["hello"] });
  assert.equal(inspectPage(prompt, other).matchingCount, 0);
});

test("inspectPageExpression serializes the matcher into the page program", () => {
  const expr = inspectPageExpression(prompt);
  assert.match(expr, /messageMatchesPrompt/);
  assert.match(expr, /inspectPage/);
  assert.ok(expr.includes("LIVE-TEST"));
});
