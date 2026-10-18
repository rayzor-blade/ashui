// Drives the dashboard app in a page, as a person would, and checks what it does:
//
//     node dashboard_check.mjs <page url> <debugging port> <work directory>
//
// Each page of the dock is opened and draws something different; the music plays once the play key is pressed and stops when it is
// pressed again; the window follows the system's light or dark appearance as it changes, unless one is chosen on the Profile page;
// and a call can be placed and ended. The window is 1280 by 800, where the dock's keys are where this file says. Exits 0 when all hold.
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { writeFileSync } from "node:fs";

const [url, port, work] = process.argv.slice(2);
if (!work) {
  console.error("usage: node dashboard_check.mjs <page url> <debugging port> <work directory>");
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
let id = 0, ready = false, broken = null;
const pending = new Map();
ws.onmessage = ({ data }) => {
  const msg = JSON.parse(data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result);
  } else if (msg.method === "Runtime.consoleAPICalled") {
    const line = msg.params.args.map((a) => a.value ?? a.description).join(" ");
    console.log(`console.${msg.params.type}: ${line.slice(0, 300)}`);
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
await send("Page.navigate", { url });
for (let i = 0; i < 600 && !ready && !broken; i++) await sleep(100);
check("the app reports it is ready", ready, broken ?? "");
await sleep(1500);

// The dock: the page each key opens, and that it draws.
const dock = { Navigate: 340, Media: 424, Vehicle: 508, Charging: 592, Camera: 676, Phone: 760, Profile: 844, More: 940 };
const seen = new Map();
let previous = (await shoot()).hash;
for (const [name, x] of Object.entries(dock)) {
  await click(x, 738);
  await sleep(1200);
  const { hash } = await shoot();
  check(`the dock opens ${name}`, hash !== previous);
  seen.set(name, hash);
  previous = hash;
}
check("the eight pages are all different", new Set(seen.values()).size === 8);

// Music: the play key of the Media page starts the track, and pressing it again stops it.
await click(424, 738);
await sleep(1000);
await click(364, 556);
let playing = false, first = null;
for (let i = 0; i < 80 && !playing; i++) {
  await sleep(100);
  first = (await audio())[0];
  playing = !!first && !first.paused && first.time > 1;
}
check("the music plays", playing, JSON.stringify(first));
check("the track has its length", !!first && first.duration > 30, `${first && first.duration}`);
await click(364, 556);
await sleep(600);
const stopped = (await audio())[0];
check("the play key pauses it", !!stopped && stopped.paused);

// The scheme follows the system's: dark and light differ in how bright the page is.
await click(844, 738);
await sleep(800);
await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
await sleep(1800);
const dark = await shoot();
await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "light" }] });
await sleep(1800);
const light = await shoot();
check("the page changes with the system's scheme", dark.hash !== light.hash);
const [d, l] = [brightness(dark.file), brightness(light.file)];
if (d === null) console.log("wasm: no ImageMagick, so the pages' brightness was not compared");
else check("the light scheme is the brighter", l > d + 0.1, `dark ${d.toFixed(2)}, light ${l.toFixed(2)}`);

// A scheme chosen on the Profile page holds against the system's.
await click(978, 340);
await sleep(300);
await send("Emulation.setEmulatedMedia", { features: [{ name: "prefers-color-scheme", value: "dark" }] });
await sleep(1800);
const chosen = await shoot();
const c = brightness(chosen.file);
if (c !== null) check("a chosen Light stays light under a dark system", c > d + 0.1, `${c.toFixed(2)}`);
await click(876, 340);
await sleep(1800);
const auto = await shoot();
check("Auto follows the system again", auto.hash !== chosen.hash);

// The phone: a call starts and ends.
await click(760, 738);
await sleep(900);
const idle = (await shoot()).hash;
await click(655, 196);
await sleep(2800);
const calling = (await shoot()).hash;
check("a contact can be called", calling !== idle);
await click(294, 620);
await sleep(700);
const ended = (await shoot()).hash;
check("the call can be ended", ended !== calling);

check("no error was raised", !broken, broken ?? "");
console.log(failures === 0 ? "ALL PASSED" : `FAIL: ${failures} checks failed`);
ws.close();
process.exit(failures === 0 ? 0 : 1);
