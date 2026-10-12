#!/usr/bin/env node
// Mac-owned Leaf chat: stdin -> one Enter -> positive submit proof. Never waits for an answer.
import process from "node:process";
import { createHash } from "node:crypto";
import { mkdir, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";
import { pathToFileURL, URL } from "node:url";
import { setTimeout, clearTimeout } from "node:timers";
import { setTimeout as delay } from "node:timers/promises";

export const TARGET_URL = "https://grok.com/bot/22b3b80c-f7ba-400d-8ad1-6e686cec4d58";
export const DEFAULT_ENDPOINT = "http://127.0.0.1:9222";
const normalize = (text) => String(text).replace(/\s+/g, " ").trim();

// Caller contract, not a cross-host lock. Receipt/dispatch state takes precedence over chat-now.
export function selectWriter({
  messageId,
  pending,
  askDispatched,
  operatorChatNow,
  handshake,
} = {}) {
  if (messageId || pending) return "mcp";
  if (askDispatched) return "reconcile";
  if (operatorChatNow || ["530", "1033", "disconnected"].includes(handshake)) return "leaf";
  return handshake === "connected" ? "mcp" : "stop";
}

// This function is serialized into the page. User text stays in memory, never in receipts/output.
export function inspectPage(prompt, page = globalThis) {
  const document = page.document;
  const clean = (text) =>
    String(text || "")
      .replace(/\s+/g, " ")
      .trim();
  const expected = clean(prompt);
  const el =
    document.querySelector('[role="textbox"][aria-label="Ask Grok anything"]') ||
    document.querySelector('[contenteditable="true"][role="textbox"]');
  page.__cursorBoxLeafDocumentId ||= page.crypto.randomUUID();
  const readable = !!el && el.getClientRects().length > 0;
  const users = Array.from(document.querySelectorAll('[data-testid="user-message"]'));
  return {
    url: page.location.href,
    documentId: page.__cursorBoxLeafDocumentId,
    readable,
    draft: readable ? clean("value" in el ? el.value : el.innerText) : null,
    generating: !!document.querySelector(
      'button[aria-label="Stop generating"], button[aria-label="Stop response"], button[data-testid="stop-button"]',
    ),
    matchingCount: users.filter((user) => !el?.contains(user) && clean(user.innerText) === expected)
      .length,
  };
}

export class CdpConnection {
  constructor(url) {
    this.ws = new globalThis.WebSocket(url);
    this.seq = 0;
    this.pending = new Map();
  }
  async connect(timeoutMs) {
    this.ws.addEventListener("message", (event) => {
      let msg;
      try {
        msg = JSON.parse(event.data);
      } catch {
        return;
      }
      const pending = this.pending.get(msg.id);
      if (!pending) return;
      this.pending.delete(msg.id);
      if (msg.error) pending.reject(new Error("CDP command failed"));
      else pending.resolve(msg.result);
    });
    this.ws.addEventListener("close", () => {
      for (const p of this.pending.values()) p.reject(new Error("CDP disconnected"));
      this.pending.clear();
    });
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.disconnect();
        reject(new Error("CDP connect timeout"));
      }, timeoutMs);
      this.ws.addEventListener(
        "open",
        () => {
          clearTimeout(timer);
          resolve();
        },
        { once: true },
      );
      this.ws.addEventListener(
        "error",
        () => {
          clearTimeout(timer);
          this.disconnect();
          reject(new Error("CDP connect failed"));
        },
        { once: true },
      );
    });
    return this;
  }
  async send(method, params = {}, timeoutMs = 3000) {
    if (this.ws.readyState !== 1) throw new Error("CDP disconnected");
    const id = ++this.seq;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error("CDP timeout"));
      }, timeoutMs);
      const done = (fn) => (value) => {
        clearTimeout(timer);
        fn(value);
      };
      this.pending.set(id, { resolve: done(resolve), reject: done(reject) });
      try {
        this.ws.send(JSON.stringify({ id, method, params }));
      } catch {
        this.pending.delete(id);
        clearTimeout(timer);
        reject(new Error("CDP send failed"));
      }
    });
  }
  disconnect() {
    this.ws.close();
  } // Disconnect only the client socket; leave Chrome and targets open.
}

function mapped(url) {
  try {
    const u = new URL(url);
    return (
      u.origin === "https://grok.com" &&
      u.pathname.replace(/\/+$/, "") === new URL(TARGET_URL).pathname
    );
  } catch {
    return false;
  }
}

async function writeReceipt(record, home) {
  const dir = join(home, ".grok", "handoffs");
  await mkdir(dir, { recursive: true, mode: 0o700 });
  const path = join(dir, `${record.timestamp.slice(0, 10)}-leaf-chat-${record.promptSha256}.md`);
  await writeFile(
    path,
    `---\ntimestamp: ${record.timestamp}\nurl: ${record.url}\nprompt_sha256: ${record.promptSha256}\nstatus: ${record.status}\n---\n`,
    { mode: 0o600 },
  );
  return path;
}

export async function runLeafChat({
  prompt,
  endpoint = DEFAULT_ENDPOINT,
  timeoutMs = 15000,
  home = homedir(),
  hooks = {},
  routeState = { operatorChatNow: true },
}) {
  const writer = selectWriter(routeState);
  if (writer !== "leaf") return { status: "skipped", reason: writer };
  if (typeof prompt !== "string" || !prompt.trim())
    return { status: "skipped", reason: "empty_prompt" };
  // :19222 is the box reverse tunnel. Leaf callers may override only for local test servers.
  try {
    const u = new URL(endpoint);
    if (
      u.protocol !== "http:" ||
      !["127.0.0.1", "localhost"].includes(u.hostname) ||
      u.port === "19222" ||
      u.username ||
      u.password ||
      u.pathname !== "/"
    )
      return { status: "skipped", reason: "invalid_endpoint" };
  } catch {
    return { status: "skipped", reason: "invalid_endpoint" };
  }
  timeoutMs = Math.min(30000, Math.max(1, Number(timeoutMs) || 15000));
  const fetch = hooks.fetch || globalThis.fetch;
  const sleep = hooks.delay || delay;
  const base = endpoint.replace(/\/+$/, "");
  const request = async (path, method = "GET") => {
    const res = await fetch(`${base}${path}`, {
      method,
      signal: globalThis.AbortSignal.timeout(Math.min(timeoutMs, 3000)),
    });
    if (!res.ok) throw new Error("DevTools HTTP failed");
    return res.json();
  };
  let tabs;
  try {
    tabs = await request("/json/list");
    if (!Array.isArray(tabs)) throw new Error("invalid list");
  } catch {
    return { status: "chrome_not_running" };
  }
  let tab = tabs.find((t) => t.type === "page" && mapped(t.url) && t.webSocketDebuggerUrl);
  if (!tab) {
    try {
      tab = await request(`/json/new?${TARGET_URL}`, "PUT");
    } catch {
      return { status: "skipped", reason: "tab_open_failed" };
    }
  }
  if (!tab?.webSocketDebuggerUrl || !mapped(tab.url))
    return { status: "skipped", reason: "tab_not_found" };
  let cdp,
    entered = false,
    status = "submit_unknown",
    reason;
  const deadline = Date.now() + timeoutMs;
  const command = (method, params) => cdp.send(method, params, Math.max(1, deadline - Date.now()));
  const inspect = async () => {
    const result = await command("Runtime.evaluate", {
      expression: `(${inspectPage.toString()})(${JSON.stringify(prompt)})`,
      returnByValue: true,
    });
    if (result.exceptionDetails || !result.result?.value) throw new Error("inspection failed");
    return result.result.value;
  };
  let baseline;
  try {
    cdp = await (hooks.connect
      ? hooks.connect(tab.webSocketDebuggerUrl)
      : new CdpConnection(tab.webSocketDebuggerUrl).connect(Math.min(timeoutMs, 3000)));
    do {
      baseline = await inspect();
      if (!mapped(baseline.url)) return { status: "skipped", reason: "navigation" };
      if (baseline.readable) break;
      await sleep(100);
    } while (Date.now() < deadline);
    if (!baseline.readable)
      return { status: "skipped", reason: "not_signed_in_or_composer_missing" };
    if (baseline.generating || baseline.draft)
      return { status: "skipped", reason: baseline.generating ? "generating" : "composer_busy" };
    const focused = await command("Runtime.evaluate", {
      expression: `(() => {
      const el = document.querySelector('[role="textbox"][aria-label="Ask Grok anything"]') || document.querySelector('[contenteditable="true"][role="textbox"]');
      if (!el || (el.value || el.innerText || '').trim() || globalThis.__cursorBoxLeafDocumentId !== ${JSON.stringify(baseline.documentId)}) return false;
      el.focus(); return document.activeElement === el;
    })()`,
      returnByValue: true,
    });
    if (focused.result?.value !== true) return { status: "skipped", reason: "composer_busy" };
    await command("Input.insertText", { text: prompt });
    const filled = await inspect();
    if (
      !mapped(filled.url) ||
      filled.documentId !== baseline.documentId ||
      filled.generating ||
      !filled.readable ||
      filled.draft !== normalize(prompt)
    )
      return { status: "skipped", reason: "draft_not_ready" };
    const key = {
      key: "Enter",
      code: "Enter",
      windowsVirtualKeyCode: 13,
      nativeVirtualKeyCode: 13,
    };
    entered = true; // A lost keyDown response is already ambiguous; never try Enter again.
    await command("Input.dispatchKeyEvent", { type: "keyDown", ...key });
    await command("Input.dispatchKeyEvent", { type: "keyUp", ...key });
    let last;
    do {
      await sleep(100);
      last = await inspect();
      if (!mapped(last.url) || last.documentId !== baseline.documentId || !last.readable) break;
      if (last.draft === "" && last.matchingCount > baseline.matchingCount) {
        status = "ok";
        break;
      }
    } while (Date.now() < deadline);
    if (
      status !== "ok" &&
      last?.readable &&
      mapped(last.url) &&
      last.documentId === baseline.documentId &&
      last.draft === normalize(prompt)
    )
      status = "submit_stuck";
  } catch {
    if (!entered) return { status: "skipped", reason: "cdp_unavailable_before_enter" };
    reason = "cdp_timeout_or_disconnect";
  } finally {
    try {
      cdp?.disconnect();
    } catch {
      /* Receipt must survive socket cleanup failure. */
    }
  }
  const result = { status, tabId: tab.id, url: TARGET_URL, ...(reason ? { reason } : {}) };
  const record = {
    timestamp: new Date().toISOString(),
    url: TARGET_URL,
    promptSha256: createHash("sha256").update(prompt).digest("hex"),
    status,
  };
  try {
    result.receiptPath = await (hooks.writeReceipt
      ? hooks.writeReceipt(record)
      : writeReceipt(record, home));
    result.logStatus = "written";
  } catch {
    result.logStatus = "write_failed";
  }
  return result;
}

async function main() {
  const options = {};
  const args = process.argv.slice(2);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--endpoint" && args[i + 1]) options.endpoint = args[++i];
    else if (args[i] === "--timeout-ms" && args[i + 1]) options.timeoutMs = args[++i];
    else throw new Error("invalid arguments");
  }
  let prompt = "";
  process.stdin.setEncoding("utf8");
  for await (const chunk of process.stdin) prompt += chunk;
  const result = await runLeafChat({ ...options, prompt });
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exitCode = result.status === "ok" ? 0 : 2;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(() => {
    process.stdout.write('{"status":"skipped","reason":"invalid_input"}\n');
    process.exitCode = 2;
  });
}
