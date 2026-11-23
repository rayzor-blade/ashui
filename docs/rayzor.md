# Ashui on Rayzor

Rayzor is a Haxe compiler with its own JIT. It compiles ashui's Haxe itself, including the HXX and CSS macros, so a Rayzor build
involves no `haxe` and no HashLink. This page says what runs on it today and how to run it.

## What works

Offscreen rendering works. The scenes in `tools/snapshot/scenes` build on Rayzor, lay out through the native layout engine, take
pointer and keyboard input, and render through the GPU to PNG files. The files are the same bytes as the ones Ash writes for the
same scenes when Ash uses the same blinc_abi, apart from a few pixels of difference in the 3D scenes. [apps/counter](../apps/counter) is the smallest
example. `tests/rayzor/run.sh` runs the reactive tests on Rayzor.

## What does not work yet

- A window. Ashui's window code uses the generated `window` package, and Rayzor has not got one yet. The offscreen path does not
  need it.
- Media, native menus and file dialogs, async work through `ash.Future`, and the wasm build. They have not been tried on Rayzor.

## Running a scene

You need a Rayzor binary and three native pieces:

| Variable | What it is |
| --- | --- |
| `BLINC_ABI` | `libblinc_abi`, built from blinc_abi with `--features rayzor`. |
| `BLINC_CSS` | The `blinc-css` tool, from blinc_abi with `--features css-cli`. |
| `RAYZOR_GPU` | `librayzor_gpu_plugin`, from `rayzor/gpu/plugin` with `--features webgpu-backend`. |

`RAYZOR` and `RAYZOR_STD_PATH` default to the sibling `../rayzor` checkout, its release binary and its `compiler/haxe-std`.
Then:

```sh
tools/snapshot/run-rayzor.sh tools/snapshot/scenes/Micro.hx
```

The PNG files land in `.ashui/snapshots`, or in `$ASHUI_SNAPSHOT_DIR`.

## Differences to know

- A `String` counts code points on Rayzor and UTF-16 units on HashLink. The native text layout reports UTF-16 offsets, so
  `ashui.core.Utf16` converts them to string indices where the program indexes a string.
- Rayzor defines `rayzor` and `eval`, and not `hl`. Ashui's Rayzor branches use `ashui_rayzor` or `#if rayzor`.
- Rayzor has no garbage collector. A signal, a style value or a layout tree frees its native copy when it is disposed, as the
  `dispose` methods of those classes say. On HashLink the collector does that.
