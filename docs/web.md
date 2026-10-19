# ashui in a page

An ashui program can run in a browser. [Ash](https://ash.rayzor.tech) compiles
its bytecode to a WebAssembly module for the `wasm32-wasip1-threads` target, and
the page runs it. The page's canvas is the program's window: hlwindow's
`xwindow.wasm` takes the pointer, keyboard, size and scale from it, and hlwgpu's
`xgpu.wasm` draws into it with the browser's WebGPU. ashui's own native library,
`blinc_abi`, is a third module beside them.

## What you need

- ashui, hlwgpu and hlwindow from Haxelib. Each release ZIP carries its web build
  under `web/`, so nothing is compiled from Rust.
- `ash-future` from Haxelib, and Ash, with threads in a page working (a release
  after 0.1.10).
- To look at it, a browser with WebGPU, and a server that sends the two headers a
  threaded module needs. `ash serve` does.

## Build it

An app's hxml is the desktop one with two more defines:

```hxml
-cp src
-lib ashui
-lib ash-future
-D wasm
-D ashui_window
-main App
-hl dist/app.hl
```

```sh
haxe web.hxml
ASH_WASM_FIBERS=1 ash --build dist/app.wasm --target wasm32-wasip1-threads dist/app.hl
ash serve dist
```

Fibers let `await` suspend inside the module while the page completes the GPU's
promise, which opening a window needs. The Haxe build stages everything else
beside the bytecode, as a desktop build stages its native libraries, and
`ash --build` adds its own host:

| File | From |
| --- | --- |
| `index.html`, `ashui-host.mjs` | ashui: the page, and the script that runs it |
| `blinc_abi.wasm` | ashui |
| `xgpu.wasm`, `gpu.mjs`, `gpu-worker.mjs`, `gpu-agent.mjs`, `hlwgpu.js` | hlwgpu |
| `xwindow.wasm`, `xwindow.mjs`, `xwindow_wire.mjs` | hlwindow |
| `app.wasm`, `worker.js`, `thread.js`, `display.js`, `ash_browser.js`, `ash_browser_bg.wasm` | `ash --build` |

The module is named after the bytecode: `app.hl` is run as `app.wasm`. From a
source checkout of the three libraries, `scripts/build_wasm.sh` in each builds
their web files, and `-D hlwgpu_web=<directory>` and `-D hlwindow_web=<directory>`
name where. They need a Rust nightly no newer than `nightly-2026-08-25`, which
`RUST_NIGHTLY=nightly-2026-08-25` names: the standard library of 1.101's nightlies
imports `pthread_key_*`, which Ash does not define yet, and the scripts stop with
that message.

## The page

The canvas takes the whole page, and the program lays out at its size and scale,
which follow the window as it is resized or moved between screens. What the program
asks of its window's size does not change that. Until the first frame is on the
GPU the page says it is loading; if the page is not cross-origin isolated, the
browser has no WebGPU, or the program stops, it says so.

What the program writes goes to the browser's console. Open the page with `?debug`
to see it in the page too, and `?arg=value` hands the program a command line
argument.

An `index.html` of your own beside the output is left alone: ashui replaces only
its own page, and the one `ash --build` writes. Define `ashui_no_page` to stage
neither the page nor `ashui-host.mjs`. A page of your own starts the program as
`ashui-host.mjs` does; read it first.

## What a page does not have

A page has no files to read when the program runs, and no environment variables.
`Css.loadFile`, `Bitmap.load`, `Fonts.load`, `Gltf.load` and the like read
through `ashui.core.Assets`, which finds the file at a path or what the build
embedded under that path. Embed a directory when you compile:

```hxml
--macro ashui.core.Assets.embed("assets", "assets")
```

Every file under `assets` is then in the program as `assets/<its path>`, and
`Bitmap.load("assets/photo.png")` finds it, in a page or on a desktop. The second
argument is the path the program asks for the files by, which is where it runs
from when that is not where it compiles from: `("../tools/snapshot/assets/map",
"../assets/map")`. `Bitmap.embed`, `Fonts.embed` and the compiled stylesheets of
`CompiledCss` read at compile time and need none of this.

It has no system fonts either; the next section says what a build carries. The
debugging tools that write files, such as `MotionRecorder`, are not for a page.

## Media

A page plays audio through `hlavi`, which has a web build as hlwgpu and hlwindow do. Add it to the build as a desktop
one does, `-lib hlavi` with `-D wasm` and its `NativeInstall` macro: it stages `xavi.wasm` and its scripts beside the
program. A page reads a media file by URL, so the file has to be served beside the page: copy it there when you compile,

```hxml
--macro ashui.macro.WebPage.copy("assets/audio", "audio")
```

and open it by the path the page has it under, as `MediaPlayer.open("audio/track.m4a")` does.
What plays is what the browser plays: MP3, AAC in M4A, Ogg and WAV, usually. A browser lets sound start only after the user
has pressed or typed in the page; a play it refuses is made at the next press or key, so a page that starts a track from a
button, as a player does, plays at once. Audio only so far: there are no video frames and no equalizer in a page, and the
rest of hlavi, its codecs, queues and muxers, says it is not available on the web.

## Fonts

A build defined `wasm` carries Arimo, a sans with the widths of Helvetica and Arial,
and text with no family, `system-ui` and `sans-serif` are set in it. To use another
face, `Fonts.embed` its file and give it the family name `Helvetica`,
`Helvetica Neue` or `Arial`, which are looked for before Arimo. Define
`ashui_no_default_fonts` to leave Arimo out. Register fonts before any text is laid
out. See `ashui.text.Fonts`.

## Threads

Work a program starts on a thread, such as compressing a texture, runs on a Worker
the page made before the program started. A frame's commands go to the GPU
together, so a thread is not woken, and the device is not asked a question, while
a frame is being drawn.

## Try it

`tests/wasm/run.sh` builds a demo for a page, serves it and opens it in your
browser, and runs no tests:

```sh
tests/wasm/run.sh            # the README's banner: a glTF car, glass panels, gauges, a street map
tests/wasm/run.sh Dashboard  # apps/dashboard: the same dashboard as an app, with working pages and music
tests/wasm/run.sh WindowPage
```

It builds `blinc_abi` and the web builds of hlwindow and hlwgpu from checkouts beside
ashui the first time, and keeps them in `tests/bin/web`; `--rebuild` builds them
again, `--port` and `--no-open` do what they say, and `BROWSER="Google Chrome"`
names the browser to open on macOS. Needs nightly Rust with `rust-src` for that
first build, Ash (`ASH=` names one), and a browser with WebGPU.

`tests/wasm/smoke.sh` is the check: it builds the same libraries and four
programs, and runs each in headless Chrome: a short check of what a page needs,
ashui's whole smoke test, a small window whose canvas is checked for pixels, and the
banner, which has to be running and drawing at the end of 25 seconds, and the
dashboard app, which is clicked through: its pages, its music, and its light
and dark.
`tests/wasm/smoke.sh Banner` runs only that. It needs Node 22 or later, Google
Chrome (`CHROME=` names one) and ImageMagick besides.

## How big it is

For the example window, as built by `tests/wasm/smoke.sh`, the files a page loads are
about 25 MB: the program 15 MB, `blinc_abi` 7 MB, ash's own browser host 1.8 MB, and
the two GPU and window modules under 1 MB. Sent with brotli they are 4.9 MB, or
6.5 MB with gzip. Most sites compress wasm without being asked; check that yours
does. The program is mostly compiled Haxe, with 2.5 MB of ash's Rust runtime and a
4.7 MB data section that is half zero padding, which compression removes.

For the dashboard app (`apps/dashboard`) the program is 23.0 MB, 5.5 MB sent with brotli: 13.2 MB of code, of which 9.9 MB is the
Haxe program compiled by Ash (5,921 wasm functions from 3,095 Haxe functions) and 2.4 MB Ash's runtime, and 8.3 MB of data, of
which about 3.5 MB is what the app embeds (the car, its textures, the map, the fonts) and the rest the bytecode. Haxe's dead code
elimination is on for the standard library only; `-dce full` also drops what the program's own classes never use. It took the
program to 20.4 MB (5.1 MB with brotli), and the app still passed its page test. A build that sets `ASHUI_HAXE_FLAGS="-dce full"`
passes it on to the Haxe compiler (`tests/wasm` reads it as `tests/run.sh` does); whether an app can take it depends on whether it
reaches classes only through reflection. Brotli is the larger lever: most hosts compress wasm on request, and the page loads in
about half the time with it (20 Mbit/s: 19 s ready with the program sent as it is, 10 s with brotli).

Ash's host asks for the program and every library at once, and prepares each on an idle agent as its bytes arrive. Under Chrome's own
network throttling, with the files sent as brotli, no cache and a headless Chrome, the dashboard says `ashui: ready` at 12.8 s on
10 Mbit/s with 80 ms of latency and at 4.9 s on 50 Mbit/s with 40 ms; the host that fetched one file after another took 14.5 s and
6.1 s. `ash serve` does not compress, and sent that way the same page needs 45 s at 10 Mbit/s, so judge a page on a host that
compresses, over a link like its visitors'.

`ASHUI_WASM_SMALL=1 tests/wasm/smoke.sh` builds as a site would ship, and prints each
file's size:

- `blinc_abi` with fat LTO and `opt-level=z`: 6.9 MB becomes 5.5 MB;
- the programs with `ASH_LLVM_PASSES='default<Oz>'`: 15.2 MB becomes 14.6 MB;
- the name section, which only helps debugging, dropped from every module with
  `scripts/strip_wasm_names.py`: about 1.4 MB between them.

Together that is about 21 MB of files, 4.4 MB with brotli and 5.8 MB with gzip.
Binaryen's `wasm-opt` is not worth running: its output compresses worse than ash's,
and version 132 writes imports in an encoding browsers do not all read yet.
