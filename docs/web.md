# ashui in a page

An ashui program can run in a browser. [Ash](https://ash.rayzor.tech) compiles its
bytecode to a WebAssembly module for the `wasm32-wasip1-threads` target, and the
page runs it. The window is the page's canvas: hlwindow's `xwindow.wasm` takes
the pointer, keyboard and size events from it, and hlwgpu's `xgpu.wasm` draws
into it with the browser's WebGPU. ashui's own native library, `blinc_abi`, is a
third module beside them. `tests/wasm/WindowPage.hx` is a whole example.

## Build it

Compile as for any ashui program, with `-D wasm`, `-D ashui_window` and the
hlwgpu, hlwindow and ash-future class paths. Then ash builds the page:

```sh
ASH_WASM_FIBERS=1 ash --build page/app.wasm --target wasm32-wasip1-threads app.hl
```

Fibers let `await` suspend inside the module while the page completes the GPU's
promise, which opening a window needs. Beside the module in `page/` go the
libraries it loads, and ash writes the page and its scripts there too:

| File | From |
| --- | --- |
| `blinc_abi.wasm` | the release package, which a build defined `wasm` copies beside its output; `scripts/build_wasm.sh` from a source checkout |
| `xwindow.wasm`, `xwindow.mjs`, `xwindow_wire.mjs` | `scripts/build_wasm.sh` in hlwindow |
| `xgpu.wasm`, `gpu.mjs`, `gpu-worker.mjs`, `gpu-agent.mjs`, `hlwgpu.js` | `scripts/build_wasm.sh` in hlwgpu |

All three scripts need nightly Rust with `rust-src`. Serve the directory with
`ash serve page`, which sends the two headers a threaded module needs, and open it
in a browser with WebGPU. `tests/wasm/run.sh` does all of this in headless Chrome
and checks the canvas for pixels; `tests/wasm/run.sh WindowPage` runs only that.

## What a page does not have

A page has no files to read when the program runs, so `Css.loadFile`,
`Bitmap.load`, `Fonts.load` and the like fail as a missing file does. Embed
instead: `Bitmap.embed`, `Fonts.embed`, and the compiled stylesheets of
`CompiledCss`. It has no system fonts either; the next section says what a build
carries. The debugging tools that write files, such as `MotionRecorder`, are not
for a page.

## Fonts

A build defined `wasm` carries Arimo, a sans with the widths of Helvetica and Arial,
and text with no family, `system-ui` and `sans-serif` are set in it. To use another
face, `Fonts.embed` its file and give it the family name `Helvetica`,
`Helvetica Neue` or `Arial`, which are looked for before Arimo. Define
`ashui_no_default_fonts` to leave Arimo out. Register fonts before any text is laid
out. See `ashui.text.Fonts`.

## How big it is

For the example window, as built by `tests/wasm/run.sh`, the files a page loads are
about 25 MB: the program 15 MB, `blinc_abi` 7 MB, ash's own browser host 1.8 MB, and
the two GPU and window modules under 1 MB. Sent with brotli they are 4.9 MB, or
6.5 MB with gzip. Most sites compress wasm without being asked; check that yours
does. The program is mostly compiled Haxe, with 2.5 MB of ash's Rust runtime and a
4.7 MB data section that is half zero padding, which compression removes.

`ASHUI_WASM_SMALL=1 tests/wasm/run.sh` builds as a site would ship, and prints each
file's size:

- `blinc_abi` with fat LTO and `opt-level=z`: 6.9 MB becomes 5.5 MB;
- the programs with `ASH_LLVM_PASSES='default<Oz>'`: 15.2 MB becomes 14.6 MB;
- the name section, which only helps debugging, dropped from every module with
  `scripts/strip_wasm_names.py`: about 1.4 MB between them.

Together that is about 21 MB of files, 4.4 MB with brotli and 5.8 MB with gzip.
Binaryen's `wasm-opt` is not worth running: its output compresses worse than ash's,
and version 132 writes imports in an encoding browsers do not all read yet.
