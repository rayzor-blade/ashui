// The page an ashui program built for the web runs in.
//
// The program is the WebAssembly module named by the page's `ashui-module`
// meta, run by ash's browser host in worker.js: a Haxe main loop never
// returns, and Atomics.wait is not allowed on this thread. This thread makes
// the agents Haxe threads run on, starts the libraries' shims beside the page
// (`xwindow.mjs` takes the canvas's size, pointer and keys; `gpu.mjs` gives
// the canvas to xgpu's worker), and says how it is going: what is loading, and
// what went wrong when something did.
//
// What the program writes goes to the browser's console, as worker.js wraps it.
// The page shows it as well when it is opened with `?debug`.

const module = "./" + document.querySelector('meta[name="ashui-module"]').content;
const name = module.slice(2);
const query = new URLSearchParams(location.search);
const screen = document.getElementById("screen");
const out = document.getElementById("out");
const status = document.getElementById("status");
const statusTitle = document.getElementById("status-title");
const statusDetail = document.getElementById("status-detail");

if (query.has("debug")) document.documentElement.classList.add("debug");

const LOG_LINES = 1000;
const write = (text, kind) => {
  const line = document.createElement("span");
  if (kind) line.className = kind;
  line.textContent = text + "\n";
  out.appendChild(line);
  while (out.childElementCount > LOG_LINES) out.firstElementChild.remove();
  if (out.parentElement && document.documentElement.classList.contains("debug")) out.scrollTop = out.scrollHeight;
};
const written = (data) => write(data.text, data.kind === "err" ? "err" : data.kind === "meta" ? "meta" : "");

// What the page says while the program starts, and for how long it may take to before the page says more.
const SLOW = 12000;
const started = performance.now();
let isReady = false;
let phase = "Fetching the program";
let software = false;
const say = (title, detail = "") => {
  if (isReady || status.classList.contains("failed")) return;
  statusTitle.textContent = title;
  statusDetail.textContent = detail + (software ? " This browser is drawing with a software GPU, which is slow: check its hardware acceleration setting." : "");
};
const waiting = () => {
  if (isReady || status.classList.contains("failed")) return;
  if (document.visibilityState === "hidden")
    return say("Waiting for this tab", "A window in a background tab draws nothing. The program starts drawing when the tab is shown.");
  if (performance.now() - started > SLOW)
    return say("Still starting", `${phase}. This takes longer than it should: open this page with ?debug to see what the program is doing.`);
  say("Loading", phase);
};
document.addEventListener("visibilitychange", waiting);
setInterval(waiting, 1000);

// The program says so on its console when its window has drawn its first frame.
const READY = "ashui: ready";
const ready = () => {
  isReady = true;
  status.classList.add("fading");
  setTimeout(() => (status.hidden = true), 300);
};
const lines = (data) => {
  written(data);
  if (data.text === READY) ready();
  else if (/^loaded \.\/.*\.wasm/.test(data.text)) phase = "Starting the program";
  else if (/native libraries/.test(data.text)) phase = "Opening the window";
};

const fail = (title, detail) => {
  status.hidden = false;
  status.classList.remove("fading");
  status.classList.add("failed");
  statusTitle.textContent = title;
  statusDetail.textContent = detail;
  if (!status.querySelector("button")) {
    const button = document.createElement("button");
    button.textContent = "Reload";
    button.onclick = () => location.reload();
    status.appendChild(button);
  }
};

if (!self.crossOriginIsolated) {
  fail(
    "This page is not cross-origin isolated",
    "A threaded WebAssembly program needs shared memory, which a browser gives only to a page served with " +
      "Cross-Origin-Opener-Policy: same-origin and Cross-Origin-Embedder-Policy: require-corp. `ash serve` sends them.",
  );
  throw new Error("not cross-origin isolated");
}
if (!navigator.gpu) {
  fail(
    "This browser has no WebGPU",
    "The program draws with WebGPU. Use a current Chrome, Edge or Safari, on a device with a GPU the browser supports.",
  );
  throw new Error("no WebGPU");
}
waiting();
// Which GPU the browser gives is the first thing to know when a page is slow or wrong: a fallback adapter is the CPU pretending.
navigator.gpu.requestAdapter().then((adapter) => {
  if (!adapter) return fail("This browser gave no GPU", "WebGPU is there, but no adapter: the GPU may be disabled or blocklisted in this browser.");
  const info = adapter.info || {};
  console.info("ashui: WebGPU adapter", info.vendor, info.architecture, info.description, adapter.isFallbackAdapter ? "(fallback)" : "");
  software = !!(adapter.isFallbackAdapter || info.isFallbackAdapter);
}, () => {});

// The canvas goes to the program's own window and GPU agents, as the shims ask
// for it; a program that presents a framebuffer instead gets display.js.
let display = null;
let screenTaken = false;
const takeScreen = () => {
  if (screenTaken) return null;
  screenTaken = true;
  try {
    return screen.transferControlToOffscreen();
  } catch {
    return null;
  }
};

// The agents Haxe threads run on are made here, not in worker.js: some
// browsers (Chrome on Android) cannot start a Worker from inside a Worker.
// Each gets one end of a channel and worker.js the other, and threads are
// handed over it. One that fails to start is left out, and the threads it
// would have run take turns on the main scheduler.
const threadAgents = [];
const startThreadAgents = (count) =>
  Promise.all(Array.from({ length: count }, () => new Promise((settle) => {
    const agent = new Worker("./thread.js", { type: "module" });
    let started = false;
    agent.onmessage = ({ data }) => {
      if (data.kind === "agent") {
        if (data.state === "ready" && !started) {
          started = true;
          const channel = new MessageChannel();
          agent.postMessage({ port: channel.port2 }, [channel.port2]);
          threadAgents.push(agent);
          settle(channel.port1);
        }
        return;
      }
      lines(data);
    };
    agent.onerror = (e) => {
      if (started) return write(`thread agent: ${e.message}`, "err");
      write(`thread agent did not start: ${e.message || "no reason given"}`, "meta");
      settle(null);
    };
  }))).then((ports) => ports.filter(Boolean));

const worker = new Worker("./worker.js", { type: "module" });
let lastError = "";
worker.onmessage = ({ data }) => {
  if (data.kind === "done") {
    for (const agent of threadAgents) agent.terminate();
    document.title = `${name} — ${data.trapped ? "trapped" : "done"}`;
    if (data.trapped) fail("The program stopped", String(data.trapped));
    else if (data.status) fail("The program stopped", lastError || `It exited with status ${data.status}.`);
    return;
  }
  // A library asked for something beside the program (`ash_host_agent`). Its
  // shim, <name>.mjs beside this page, is started on this thread with the
  // program's memory, the address it named and the canvas.
  if (data.kind === "spawn-agent") {
    if (data.name === "gpu") phase = "Drawing the first frame";
    import(new URL(`./${data.name}.mjs`, location.href))
      .then((shim) => shim.start({ memory: data.memory, address: data.address, canvas: screen }))
      .catch((e) => fail(`${data.name} did not start`, e && e.message ? e.message : String(e)));
    return;
  }
  if (data.kind === "display") {
    if (!display) {
      const canvas = takeScreen();
      if (!canvas) return; // an agent that draws already has it
      display = new Worker("./display.js");
      display.postMessage({ canvas }, [canvas]);
    }
    display.postMessage(data);
    return;
  }
  if (data.kind === "err") lastError = data.text;
  lines(data);
};
worker.onerror = (e) => fail("The program could not start", e.message || "worker.js did not load");

const agentPorts = await startThreadAgents(Math.max(1, (navigator.hardwareConcurrency || 4) - 1));
worker.postMessage(
  { module, args: [name, ...query.getAll("arg")], environ: query.getAll("env"), display: true, agents: agentPorts },
  agentPorts,
);
