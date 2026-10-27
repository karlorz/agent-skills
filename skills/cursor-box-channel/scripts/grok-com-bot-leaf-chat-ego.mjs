#!/usr/bin/env node
// Mac-owned Leaf chat through Ego Lite. Prompt and script travel only over stdin.
import process from "node:process";
import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { homedir } from "node:os";
import { pathToFileURL } from "node:url";
import { selectWriter, inspectPage, messageMatchesPrompt, TARGET_URL, writeReceipt } from "./grok-com-bot-leaf-chat.mjs";

// Self-contained Node program for ego-browser nodejs; never pass this in argv.
export function buildScript(prompt, timeoutMs, marker) {
  return `
const prompt = ${JSON.stringify(prompt)};
const target = ${JSON.stringify(TARGET_URL)};
const marker = ${JSON.stringify(marker)};
const messageMatchesPrompt = ${messageMatchesPrompt.toString()};
const inspectPage = ${inspectPage.toString()};
const expectedUrl = new URL(target);
const mapped = (url) => {
  try {
    const u = new URL(url);
    return u.origin === expectedUrl.origin && u.pathname.replace(/\\/+$/, "") === expectedUrl.pathname;
  } catch { return false; }
};
const clean = (text) => text.replace(/\\s+/g, " ").trim();
const expectedDraft = clean(prompt);
const sameTab = (s, base) => !!s?.readable && mapped(s.url) && s.documentId === base.documentId;
const emit = (result) => console.log(marker + JSON.stringify(result));
let entered = false, spaceId, pageLabel;
async function run() {
  const task = await taskSpace("cursor-box-channel-leaf-chat");
  spaceId = task.spaceId;
  const tabs = await task.tabs();
  const found = tabs.find((tab) => mapped(tab.url));
  let page;
  if (found) page = found.label ? task.page(found.label) : await task.adopt(found.page);
  else {
    const blank = tabs.find((tab) => tab.label && tab.url === "about:blank");
    page = blank ? task.page(blank.label) : await task.newPage();
    await page.goto(target);
  }
  pageLabel = page.label;
  const deadline = Date.now() + ${timeoutMs};
  const inspect = () => page.evaluate(inspectPage, prompt);
  const pause = () => new Promise((resolve) => setTimeout(resolve, 100));
  let baseline;
  do {
    baseline = await inspect();
    if (!mapped(baseline.url)) return { status: "skipped", reason: "navigation" };
    if (baseline.readable) break;
    await pause();
  } while (Date.now() < deadline);
  if (!baseline.readable) return { status: "skipped", reason: "not_signed_in_or_composer_missing" };
  if (baseline.generating || baseline.draft)
    return { status: "skipped", reason: baseline.generating ? "generating" : "composer_busy" };
  const focused = await page.evaluate((documentId) => {
    const el = document.querySelector('[role="textbox"][aria-label="Ask Grok anything"]') || document.querySelector('[contenteditable="true"][role="textbox"]');
    if (!el || (el.value || el.innerText || '').trim() || globalThis.__cursorBoxLeafDocumentId !== documentId) return false;
    el.focus(); return document.activeElement === el;
  }, baseline.documentId);
  if (!focused) return { status: "skipped", reason: "composer_busy" };
  await page.keyboard.insertText(prompt);
  const filled = await inspect();
  if (!mapped(filled.url) || filled.documentId !== baseline.documentId || filled.generating ||
      !filled.readable || filled.draft !== expectedDraft || filled.matchingCount !== baseline.matchingCount)
    return { status: "skipped", reason: "draft_not_ready" };
  entered = true; // A lost press response is uncertain; there is no retry.
  await page.keyboard.press("Enter");
  const proofDeadline = Date.now() + ${timeoutMs};
  let last;
  do {
    await pause();
    last = await inspect();
    if (!sameTab(last, baseline)) break;
    if (last.draft === "" && last.matchingCount > baseline.matchingCount) return { status: "ok" };
  } while (Date.now() < proofDeadline);
  return { status: sameTab(last, baseline) && last.draft === expectedDraft ? "submit_stuck" : "submit_unknown" };
}
let result;
try { result = await run(); }
catch { result = { status: entered ? "submit_unknown" : "skipped", reason: "ego_unavailable" }; }
emit({ ...result, entered, spaceId, pageLabel });
`;
}

function spawnStatus(error) {
  return error?.code === "ENOENT" ? "ego_not_running" : "submit_unknown";
}

async function execute(script, marker, timeoutMs, spawnChild) {
  return new Promise((resolve) => {
    let child, timer, output = "", finished = false;
    const done = (result) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      resolve(result);
    };
    try {
      child = spawnChild("ego-browser", ["nodejs"], { stdio: ["pipe", "pipe", "pipe"] });
    } catch (error) {
      done({ status: spawnStatus(error) });
      return;
    }
    // Never forward child logs: errors and browser output can contain prompt text.
    child.stderr.on("data", () => {});
    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => { output = (output + chunk).slice(-65536); });
    child.on("error", (error) => done({ status: spawnStatus(error) }));
    child.on("close", () => {
      const start = output.lastIndexOf(marker);
      let record;
      try {
        const line = start < 0 ? "" : output.slice(start, output.indexOf("\n", start) + 1 || undefined);
        record = JSON.parse(line.slice(marker.length));
      } catch { /* Uncertain. */ }
      const wantEntered = { skipped: false, ok: true, submit_stuck: true }[record?.status];
      if (!record || !["ok", "skipped", "submit_unknown", "submit_stuck"].includes(record.status) ||
          (wantEntered !== undefined && record.entered !== wantEntered)) {
        done({ status: "submit_unknown" });
        return;
      }
      // Copy only safe, bounded metadata; never propagate arbitrary child fields.
      const result = { status: record.status };
      if (Number.isSafeInteger(record.spaceId)) result.spaceId = record.spaceId;
      if (/^p\d+$/.test(record.pageLabel)) result.pageLabel = record.pageLabel;
      if (["navigation", "not_signed_in_or_composer_missing", "generating", "composer_busy",
        "draft_not_ready", "ego_unavailable"].includes(record.reason)) result.reason = record.reason;
      done(result);
    });
    timer = setTimeout(() => {
      done({ status: "submit_unknown" });
      child.kill(); // Stop only the CLI client; the Space and tab remain open.
    }, timeoutMs + 10000);
    child.stdin.on("error", () => {}); // EPIPE is resolved by the child outcome, never a resend.
    child.stdin.end(script);
  });
}

export async function runLeafChat({ prompt, timeoutMs = 15000, home = homedir(), hooks = {},
  routeState = { operatorChatNow: true } } = {}) {
  const writer = selectWriter(routeState);
  if (writer !== "leaf") return { status: "skipped", reason: writer };
  if (typeof prompt !== "string" || !prompt.trim()) return { status: "skipped", reason: "empty_prompt" };
  timeoutMs = Math.min(30000, Math.max(1, Number(timeoutMs) || 15000));
  const marker = `LEAF_${randomUUID()}:`;
  const result = await execute(buildScript(prompt, timeoutMs, marker), marker, timeoutMs, hooks.spawn || spawn);
  if (["skipped", "ego_not_running"].includes(result.status)) return result;
  const record = { timestamp: new Date().toISOString(), url: TARGET_URL,
    promptSha256: createHash("sha256").update(prompt).digest("hex"), status: result.status };
  try {
    result.receiptPath = await (hooks.writeReceipt ? hooks.writeReceipt(record) : writeReceipt(record, home));
    result.logStatus = "written";
  } catch { result.logStatus = "write_failed"; }
  return result;
}

async function main() {
  const args = process.argv.slice(2);
  if (args.length && (args.length !== 2 || args[0] !== "--timeout-ms" || !/^\d+$/.test(args[1])))
    throw new Error("invalid arguments");
  let prompt = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) prompt += chunk;
  const result = await runLeafChat({ prompt, timeoutMs: args[1] });
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exitCode = result.status === "ok" ? 0 : 2;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    process.stdout.write('{"status":"skipped","reason":"invalid_input"}\n');
    process.exitCode = 2;
  });
}
