// Runs a program Ash built for a page in a Chrome started with
// --remote-debugging-port, and prints what it wrote to the page.
//
//     node run_page.mjs <page url> <debugging port> [seconds] [--shot file.png --when regex [--wait seconds]] [--running]
//
// With --shot, the page is captured to file.png once the program has written a
// line matching the regex, and --wait seconds (half a second by default) more,
// while it still draws.
//
// Exits 0 when the program ended without trapping, its output holds no line
// beginning FAIL or "Uncaught exception", and it exited 0. With --running the
// program is an application that does not end: it passes when it is still
// running when the time is up, and fails if it ended before.
const args = process.argv.slice(2);
const flag = (name) => {
  const at = args.indexOf(name);
  return at < 0 ? undefined : args.splice(at, 2)[1];
};
const running = args.includes("--running") && !!args.splice(args.indexOf("--running"), 1);
const shot = flag("--shot");
const when = new RegExp(flag("--when") ?? "drawing");
const wait = Number(flag("--wait") ?? 0.5);
const [url, port, seconds = "120"] = args;
if (!port) {
  console.error("usage: node run_page.mjs <page url> <debugging port> [seconds]");
  process.exit(2);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

let target;
for (let i = 0; i < 100 && !target; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    target = list.find((t) => t.type === "page");
  } catch {}
  if (!target) await sleep(200);
}
if (!target) {
  console.error(`no page target on debugging port ${port}`);
  process.exit(1);
}

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
let id = 0;
const pending = new Map();
ws.onmessage = ({ data }) => {
  const msg = JSON.parse(data);
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id);
    pending.delete(msg.id);
    if (msg.error) reject(new Error(JSON.stringify(msg.error)));
    else resolve(msg.result);
  } else if (msg.method === "Runtime.consoleAPICalled" && /error|warn/.test(msg.params.type)) {
    console.log(`[page console.${msg.params.type}]`, msg.params.args.map((a) => a.value ?? a.description).join(" "));
  } else if (msg.method === "Runtime.exceptionThrown") {
    const details = msg.params.exceptionDetails;
    console.log("[page exception]", details.exception?.description ?? details.text);
  }
};
const send = (method, params = {}) => new Promise((resolve, reject) => {
  const n = ++id;
  pending.set(n, { resolve, reject });
  ws.send(JSON.stringify({ id: n, method, params }));
});
const evaluate = async (expression) =>
  (await send("Runtime.evaluate", { expression, returnByValue: true })).result.value;
// The page titles itself "<module> — done" or "— trapped" when the program ends.
const ended = async () => /— (done|trapped)$/.test(await evaluate("document.title"));

await send("Runtime.enable");
await send("Page.enable");
await send("Page.navigate", { url });

const output = async () => (await evaluate("document.getElementById('out')?.textContent")) ?? "";
const end = Date.now() + Number(seconds) * 1000;
let finished = false, printed = 0, shotTaken = false;
// What the program writes is shown as it arrives, so a program that stalls shows where.
while (Date.now() < end && !(finished = await ended())) {
  const so_far = await output();
  if (so_far.length > printed) {
    process.stdout.write(so_far.slice(printed));
    printed = so_far.length;
  }
  if (shot && !shotTaken && when.test(so_far)) {
    shotTaken = true;
    await sleep(wait * 1000);
    const { data } = await send("Page.captureScreenshot", { format: "png" });
    const fs = await import("node:fs");
    fs.writeFileSync(shot, Buffer.from(data, "base64"));
    // Where the canvas is in the capture, in its pixels, for a checker to crop to.
    const box = await evaluate(`(() => {
      const r = document.getElementById("screen")?.getBoundingClientRect();
      return r && { x: r.x * devicePixelRatio, y: r.y * devicePixelRatio, width: r.width * devicePixelRatio, height: r.height * devicePixelRatio };
    })()`);
    if (box) fs.writeFileSync(shot + ".json", JSON.stringify(box));
  }
  await sleep(200);
}
const title = await evaluate("document.title");
const text = await output();
ws.close();

process.stdout.write(text.slice(printed));
if (!text.endsWith("\n")) console.log();
console.log(`page title: ${title}`);
const failures = [];
if (running && finished) failures.push("the program ended, and was meant to keep running");
if (!running && !finished) failures.push("the program did not end");
if (/trapped$/.test(title)) failures.push("the program trapped");
const status = /exited with (-?\d+)/.exec(text)?.[1];
if (finished && status !== undefined && status !== "0") failures.push(`the program exited with ${status}`);
if (/^FAIL|Uncaught exception/m.test(text)) failures.push("the program reported a failure");
if (failures.length) {
  console.log(`page: FAIL: ${failures.join("; ")}`);
  process.exit(1);
}
console.log("page: PASS");
