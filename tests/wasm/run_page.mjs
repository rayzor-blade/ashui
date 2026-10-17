// Runs a program Ash built for a page in a Chrome started with
// --remote-debugging-port, and prints what it wrote to the page.
//
//     node run_page.mjs <page url> <debugging port> [seconds]
//
// Exits 0 when the program ended without trapping, its output holds no line
// beginning FAIL or "Uncaught exception", and it exited 0.
const [url, port, seconds = "120"] = process.argv.slice(2);
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
let finished = false, printed = 0;
// What the program writes is shown as it arrives, so a program that stalls shows where.
while (Date.now() < end && !(finished = await ended())) {
  const so_far = await output();
  if (so_far.length > printed) {
    process.stdout.write(so_far.slice(printed));
    printed = so_far.length;
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
if (!finished) failures.push("the program did not end");
if (/trapped$/.test(title)) failures.push("the program trapped");
const status = /exited with (-?\d+)/.exec(text)?.[1];
if (finished && status !== undefined && status !== "0") failures.push(`the program exited with ${status}`);
if (/^FAIL|Uncaught exception/m.test(text)) failures.push("the program reported a failure");
if (failures.length) {
  console.log(`page: FAIL: ${failures.join("; ")}`);
  process.exit(1);
}
console.log("page: PASS");
