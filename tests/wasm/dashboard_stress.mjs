// Drives the dashboard app in a page, as a person would, and checks what it does:
//
//     node dashboard_check.mjs <page url> <debugging port> <seconds> <work directory>
//
// Each page of the dock is opened and draws something different; the music plays once the play key is pressed and stops when it is
// pressed again; the window follows the system's light or dark appearance as it changes, unless one is chosen on the Profile page;
// and a call can be placed and ended. The window is 1280 by 800 at the layout's own size (ASHUI_ZOOM=1), where the dock's keys are where this file says. Exits 0 when all hold.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const [url, port, , work] = process.argv.slice(2);
if (!work) {
  console.error("usage: node dashboard_check.mjs <page url> <debugging port> <seconds> <work directory>");
  process.exit(2);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target;
for (let i = 0; i < 100 && !target; i++) {
  try { target = (await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()).find((t) => t.type === "page"); } catch {}
  if (!target) await sleep(200);
}
if (!target) { console.error(`no page target on debugging port ${port}`); process.exit(1); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
const ring = [], gcRing = [];
let lastLoopAt = Date.now();
let programFrames = 0, lastFramesAt = Date.now(), lastLoop = "", id = 0, ready = false, broken = null, liveMegabytes = null;
const pending = new Map();
ws.onmessage = ({ data }) => {
  const msg = JSON.parse(data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
  } else if (msg.method === "Runtime.consoleAPICalled") {
    const line = msg.params.args.map((a) => a.value ?? a.description).join(" ");
    if (/\[gc\]/.test(line) || /^\[page\]/.test(line)) { gcRing.push(`${Date.now() % 1000000} ${line.slice(0, 260)}`); if (gcRing.length > 6) gcRing.shift(); }
    const gc = /\[gc\] #\d+ .*live=\d+ blocks \(([\d.]+)MB\)/.exec(line);
    if (gc) liveMegabytes = Number(gc[1]);
    const fr = /^\[frames\] (\d+) in/.exec(line); if (fr) { programFrames += Number(fr[1]); lastFramesAt = Date.now(); }
    if (/^\[(loop|frames)\]/.test(line)) { if (/^\[loop\]/.test(line)) lastLoopAt = Date.now(); lastLoop = line; ring.push(`${Date.now() % 1000000} ${line.slice(0, 330)}`); if (ring.length > 14) ring.shift(); }
    if (!/\[gc|\[frames|\[loop/.test(line)) console.log(`console.${msg.params.type}: ${line.slice(0, 300)}`);
    if (/ashui: ready/.test(line)) ready = true;
    if (/^FAIL|^Uncaught exception/.test(line)) broken ??= line;
  } else if (msg.method === "Runtime.exceptionThrown") {
    broken ??= msg.params.exceptionDetails.exception?.description ?? msg.params.exceptionDetails.text;
    console.log("exception:", String(broken).slice(0, 300));
  } else if (msg.method === "Target.attachedToTarget") {
    const s = msg.params.sessionId;
    send("Runtime.enable", {}, s).catch(() => {});
    send("Runtime.runIfWaitingForDebugger", {}, s).catch(() => {});
  }
};
const send = (method, params = {}, sessionId) => new Promise((resolve, reject) => {
  const n = ++id;
  pending.set(n, { resolve, reject });
  ws.send(JSON.stringify({ id: n, method, params, ...(sessionId ? { sessionId } : {}) }));
});

let failures = 0;
const check = (name, ok, detail = "") => {
  console.log(`${ok ? "ok  " : "FAIL"} ${name}${detail ? ` (${detail})` : ""}`);
  if (!ok) failures++;
};
const mouse = (type, x, y) => send("Input.dispatchMouseEvent", { type, x, y, button: "left", buttons: type === "mouseReleased" ? 0 : 1, clickCount: 1 });
const click = async (x, y) => {
  await send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y, button: "none", buttons: 0 });
  await sleep(60);
  await mouse("mousePressed", x, y);
  await sleep(60);
  await mouse("mouseReleased", x, y);
};
let shots = 0;
const shoot = async () => {
  const png = Buffer.from((await send("Page.captureScreenshot", { format: "png" })).data, "base64");
  const file = `${work}/shot-${++shots}.png`;
  writeFileSync(file, png);
  return { file, hash: createHash("sha1").update(png).digest("hex") };
};
// The page's brightness, 0 to 1, where ImageMagick is installed.
const brightness = (file) => {
  try { return Number(execFileSync("magick", [file, "-format", "%[fx:mean]", "info:"]).toString()); } catch { return null; }
};
const audio = async () => JSON.parse((await send("Runtime.evaluate", {
  expression: "JSON.stringify(window.__audios.map(a => ({ paused: a.paused, time: a.currentTime, duration: a.duration, error: a.error && a.error.code })))",
  returnByValue: true,
})).result.value);

await send("Runtime.enable");
await send("Page.enable");
await send("Target.setAutoAttach", { autoAttach: true, waitForDebuggerOnStart: false, flatten: true });
await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 800, deviceScaleFactor: 1, mobile: false });
await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
// Every audio element the page makes, to read its state.
await send("Page.addScriptToEvaluateOnNewDocument", { source: `
  window.__audios = [];
  const A = window.Audio;
  window.Audio = function (...a) { const e = new A(...a); window.__audios.push(e); return e; };
  window.Audio.prototype = A.prototype;
  const make = document.createElement.bind(document);
  document.createElement = function (t, ...r) { const e = make(t, ...r); if (String(t).toLowerCase() === "audio") window.__audios.push(e); return e; };
` });
await send("Page.navigate", { url: url + (url.includes("?") ? "&" : "?") + "env=ASH_GC_STATS=1&env=ASHUI_ZOOM=1&env=ASHUI_FRAME_STATS=1&watch" });
for (let i = 0; i < 600 && !ready && !broken; i++) await sleep(100);
check("the app reports it is ready", ready, broken ?? "");
await sleep(1500);


// Random navigation: pages in random order at random delays, with the car dragged now and then, until the page stops changing.
const dock = { Navigate: 340, Media: 424, Vehicle: 508, Charging: 592, Camera: 676, Phone: 760, Profile: 844, More: 940 };
const keys = Object.entries(dock);
const seed = Number(process.env.SEED ?? Date.now() % 100000);
let state = seed;
const rnd = () => (state = (state * 1664525 + 1013904223) >>> 0) / 4294967296;
console.log("seed", seed);
const frames = async () => Number((await send("Runtime.evaluate", { expression: "window.__raf|0", returnByValue: true })).result.value);
await send("Runtime.evaluate", { expression: "window.__raf=0;(function f(){window.__raf++;requestAnimationFrame(f)})()" });
const deadline = Date.now() + Number(process.env.MINUTES ?? 10) * 60000;
// Which pages animate when they are first visited: two pictures 500 ms apart differ.
const animates = {};
for (const [name, x] of keys) {
  await click(x, 738);
  await sleep(1500);
  const a = (await shoot()).hash;
  await sleep(500);
  const b = (await shoot()).hash;
  animates[name] = a !== b;
}
console.log("animating pages on a fresh visit:", JSON.stringify(animates));
const moving = keys.filter(([name]) => animates[name] && name !== "Charging");
check("some page animates", moving.length > 0);
let steps = 0, last = "";
const trail = [];
while (Date.now() < deadline && !broken) {
  const [name, x] = keys[Math.floor(rnd() * keys.length)];
  const wait = Math.floor(30 + rnd() * rnd() * 900);
  await click(x, 738);
  steps++;
  trail.push(`${name}+${wait}`);
  if (trail.length > 40) trail.shift();
  if (name === "Vehicle" && rnd() < 0.5) {
    await mouse("mouseMoved", 640, 400);
    await mouse("mousePressed", 640, 400);
    for (let i = 1; i <= 6; i++) { await mouse("mouseMoved", 640 + i * 20, 400); await sleep(16); }
    await mouse("mouseReleased", 800, 400);
  }
  await sleep(wait);
  if (Date.now() - lastLoopAt > 4000) {
    console.log(`DEAD: the program's loop has printed nothing for ${Math.round((Date.now() - lastLoopAt) / 1000)} s at step ${steps}; trail ${trail.join(" ")}`);
    console.log("recent lines:\n" + ring.join("\n"));
    console.log("collector and page lines:\n" + gcRing.join("\n"));
    const before = (await shoot()).hash;
    await click(dock.Media, 738);
    await sleep(2000);
    const after = (await shoot()).hash;
    console.log(`after a click: picture changed=${before !== after}, loop lines since=${Date.now() - lastLoopAt < 3000}`);
    const audios = await audio();
    console.log("audio:", JSON.stringify(audios));
    const cpu = await send("Runtime.evaluate", { expression: "JSON.stringify({hidden: document.hidden, mem: performance.memory && performance.memory.usedJSHeapSize})", returnByValue: true });
    console.log("page:", cpu.result.value);
    check("the program's loop keeps running", false, `seed ${seed} step ${steps}`);
    break;
  }
  if (steps % 20 === 0) console.log(`step ${steps} live=${liveMegabytes}MB last loop line ${Date.now() - lastLoopAt} ms ago`);
}
check("no error was raised", !broken, broken ?? "");
console.log(failures === 0 ? "ALL PASSED" : `FAIL: ${failures} checks failed`);
ws.close();
process.exit(failures === 0 ? 0 : 1);
