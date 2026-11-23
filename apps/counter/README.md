# Counter

The smallest ashui program that uses every layer: signals and a computed, a layout written in HXX, real pointer and keyboard
input, and a render through the GPU to PNG files. It is one Haxe file, [Counter.hx](Counter.hx), and it runs unchanged on Ash and
on Rayzor.

The program builds a small form with a count, three buttons and a text field. A script then presses `+` three times and `-`
once, types a name, and presses `Shout`. The presses and the typing go through the same hit testing and focus code as a real
window, so a button must be under the pointer for its `onClick` to run. After each step the program checks what the signals hold
and prints `ok` or `FAIL`. It exits with status 1 if a check fails. It also writes 16 frames, `counter-000.png` to
`counter-015.png`.

## Running it

On Ash, from the repository root:

```sh
apps/counter/run.sh
```

On Rayzor, with the native pieces built as `tools/snapshot/run-rayzor.sh` describes:

```sh
BLINC_ABI=... BLINC_CSS=... RAYZOR_GPU=... apps/counter/run.sh rayzor
```

Both print the same five checks and `ALL PASSED`, and the 16 frames are the same bytes on both.

## What it does not cover

It draws to files, not to a window. A window on Rayzor needs the `window` package for Rayzor, which is not ready yet; see
`docs/rayzor.md`. A checked checkbox is not used, because it draws as an empty box today (git-bug b58ad36).
