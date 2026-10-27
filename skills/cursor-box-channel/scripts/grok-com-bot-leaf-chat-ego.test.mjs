import test from "node:test";
import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough, Writable } from "node:stream";
import { mkdtemp, readFile, readdir, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { runLeafChat } from "./grok-com-bot-leaf-chat-ego.mjs";
import { TARGET_URL } from "./grok-com-bot-leaf-chat.mjs";

const prompt = 'Private unicode 測試 $token `literal`\nsecond line';
const base = { url: TARGET_URL, documentId: "doc", readable: true, draft: "", generating: false, matchingCount: 2 };
const normalized = prompt.replace(/\s+/g, " ").trim();
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

function harness({ states = [], reuse = true, pressFails = false, lostOutput = false, focus = true,
  missing = false, malformed = false, noStatus = false, navigateFails = false } = {}) {
  const calls = [], receipts = [], inspections = [...states];
  let script;
  const page = { label: "p1", async goto(url) { calls.push(["goto", url]); if (navigateFails) throw Error(prompt); },
    async evaluate(fn) {
      if (fn.name !== "inspectPage") return focus;
      return { ...base, ...(inspections.shift() || {}) };
    }, keyboard: {
      async insertText(value) { calls.push(["insertText", value]); },
      async press(key) { calls.push(["press", key]); if (pressFails) throw Error(prompt); },
    } };
  const task = { spaceId: 7, page(label) { calls.push(["page", label]); return page; },
    async tabs() { return [{ label: "p1", url: reuse ? TARGET_URL : "about:blank" }]; },
    async newPage() { assert.fail("should reuse p1"); } };
  const hooks = {
    spawn(command, args, options) {
      calls.push(["spawn", command, args, options]);
      assert.deepEqual(args, ["nodejs"]);
      assert.equal(command, "ego-browser");
      assert.ok(!JSON.stringify(args).includes(prompt));
      const child = new EventEmitter();
      child.stdout = new PassThrough(); child.stderr = new PassThrough(); child.kill = () => {};
      child.stdin = new Writable({ write(chunk, encoding, callback) { script = chunk.toString(); callback(); } });
      child.stdin.on("finish", async () => {
        if (missing) { child.emit("error", Object.assign(Error(prompt), { code: "ENOENT" })); return; }
        const logger = { log(text) {
          if (lostOutput || (noStatus && text.includes('"status"'))) return;
          child.stdout.write(malformed ? "bad output\n" : text + "\n");
        } };
        try { await new AsyncFunction("taskSpace", "console", script)(async (name) => {
          calls.push(["taskSpace", name]); return task;
        }, logger); } catch (error) { child.stderr.write(String(error)); }
        child.emit("close", 0);
      });
      return child;
    },
    async writeReceipt(record) { receipts.push(record); return "/hash-receipt.md"; },
  };
  return { calls, receipts, hooks, get script() { return script; } };
}

async function run(options = {}, extra = {}) {
  const h = harness(options);
  const result = await runLeafChat({ prompt, timeoutMs: 1, hooks: h.hooks, ...extra });
  assert.ok(!JSON.stringify(result).includes(prompt));
  assert.ok(!JSON.stringify(h.receipts).includes(prompt));
  assert.ok(!/page\.close|closeTaskSpace|Browser\.close|Target\.closeTarget|playwright-cli close|\.finish\(/.test(h.script || ""));
  return { h, result };
}
const success = [{}, { draft: normalized }, { matchingCount: 3 }];

test("reuses Ego TaskSpace and submits exactly one Enter with positive proof", async () => {
  const { h, result } = await run({ states: success });
  assert.equal(result.status, "ok");
  assert.equal(result.spaceId, 7); assert.equal(result.pageLabel, "p1");
  assert.deepEqual(h.calls.filter(([name]) => name === "press"), [["press", "Enter"]]);
  assert.equal(h.calls.filter(([name]) => name === "insertText").length, 1);
  assert.ok(h.script.includes(JSON.stringify(prompt)));
  assert.equal(h.calls.filter(([name]) => name === "goto").length, 0);
  assert.deepEqual(Object.keys(h.receipts[0]).sort(), ["promptSha256", "status", "timestamp", "url"]);
  assert.equal(h.receipts[0].promptSha256, createHash("sha256").update(prompt).digest("hex"));
});
test("navigates the initial blank page to the exact target", async () => {
  const { h, result } = await run({ states: success, reuse: false });
  assert.equal(result.status, "ok");
  assert.deepEqual(h.calls.find(([name]) => name === "goto"), ["goto", TARGET_URL]);
});
for (const [name, after, expected] of [
  ["empty composer without new matching user", {}, "submit_unknown"],
  ["new matching user without empty composer", { draft: normalized, matchingCount: 3 }, "submit_stuck"],
  ["unchanged draft", { draft: normalized }, "submit_stuck"],
  ["document changed", { documentId: "other", matchingCount: 3 }, "submit_unknown"],
  ["navigation", { url: "https://grok.com/", matchingCount: 3 }, "submit_unknown"],
  ["unreadable composer", { readable: false, matchingCount: 3 }, "submit_unknown"],
]) test(name + " never resends", async () => {
  const { h, result } = await run({ states: [{}, { draft: normalized }, after] });
  assert.equal(result.status, expected); assert.equal(h.receipts.length, 1);
  assert.equal(h.calls.filter(([name]) => name === "press").length, 1);
});
for (const options of [{ pressFails: true }, { lostOutput: true }, { malformed: true }, { noStatus: true }])
  test("lost/failed CLI result remains uncertain: " + JSON.stringify(options), async () => {
    const { h, result } = await run({ states: success, ...options });
    assert.equal(result.status, "submit_unknown"); assert.equal(h.receipts.length, 1);
    assert.equal(h.calls.filter(([name]) => name === "spawn").length, 1);
    assert.equal(h.calls.filter(([name]) => name === "press").length, 1);
  });
for (const [name, states, reason] of [
  ["busy", [{ draft: "existing" }], "composer_busy"],
  ["generating", [{ generating: true }], "generating"],
  ["signed out", [{ readable: false }], "not_signed_in_or_composer_missing"],
  ["wrong URL", [{ url: "https://example.com/" }], "navigation"],
  ["wrong draft", [{}, { draft: "wrong" }], "draft_not_ready"],
  ["racing matching message", [{}, { draft: normalized, matchingCount: 3 }], "draft_not_ready"],
]) test("skips before Enter: " + name, async () => {
  const { h, result } = await run({ states });
  assert.deepEqual(result.status, "skipped"); assert.equal(result.reason, reason);
  assert.equal(h.calls.filter(([name]) => name === "press").length, 0); assert.equal(h.receipts.length, 0);
});
test("missing executable reports ego_not_running without fallback", async () => {
  const { h, result } = await run({ missing: true });
  assert.deepEqual(result, { status: "ego_not_running" }); assert.equal(h.calls.length, 1);
});
test("MCP ownership, lost asks, and empty input never spawn", async () => {
  for (const routeState of [{ messageId: "id", operatorChatNow: true }, { pending: true }, { askDispatched: true }]) {
    const { h, result } = await run({}, { routeState });
    assert.equal(result.status, "skipped"); assert.equal(h.calls.length, 0);
  }
  const { h } = await run({}, { prompt: " " }); assert.equal(h.calls.length, 0);
});
test("receipt failure preserves successful send without retry", async () => {
  const h = harness({ states: success });
  h.hooks.writeReceipt = async () => { throw Error(prompt); };
  const result = await runLeafChat({ prompt, hooks: h.hooks });
  assert.equal(result.status, "ok"); assert.equal(result.logStatus, "write_failed");
  assert.equal(h.calls.filter(([name]) => name === "press").length, 1);
});
test("real receipt contains only timestamp, target, hash and status with private permissions", async () => {
  const home = await mkdtemp(join(tmpdir(), "leaf-ego-test-"));
  try {
    const h = harness({ states: success }); delete h.hooks.writeReceipt;
    const result = await runLeafChat({ prompt, home, hooks: h.hooks });
    const files = await readdir(join(home, ".grok", "handoffs"));
    assert.match(files[0], /^\d{4}-\d\d-\d\d-leaf-chat-[a-f0-9]{64}\.md$/);
    const text = await readFile(result.receiptPath, "utf8");
    assert.ok(!text.includes(prompt)); assert.equal(text.split("\n").length, 7);
    assert.equal((await stat(result.receiptPath)).mode & 0o777, 0o600);
  } finally { await rm(home, { recursive: true, force: true }); }
});
