# ashui debugger

A standalone ashui app for reviewing UI recordings frame by frame.
Built with `ashui.components`.

It opens a recording made by `ashui.debug.MotionRecorder` and plays it back:

- Frame playback with play, pause, step, scrub, speed and repeat controls.
  Toggle motion outlines, trails, labels and progress bars.
- An animation timeline showing each element, property, duration and failed
  check. Select a track to highlight its element and inspect the result.
- Per-frame tree changes: added/removed elements, bounds, states and styles.
- Motion reports and baseline frame-regression results.

## Running it

From the repository root, after recording something (for example
`tools/snapshot/run.sh tools/snapshot/scenes/DialogMotion.hx`):

```sh
debugger/run.sh                                  # the newest recording
debugger/run.sh .ashui/snapshots/motion/dialog   # a given one
```

It needs the same sibling checkouts as `tools/demo` (`../hlwgpu`,
`../hlwindow` and a built `../ash`).

`scenes/DebuggerScene.hx` captures the page offscreen for review, as
`tools/snapshot` scenes do:

```sh
ASHUI_HAXE_FLAGS="--class-path $PWD/debugger/haxe" tools/snapshot/run.sh debugger/scenes/DebuggerScene.hx
```

Use `RECORDING` to select a recording. Set `ASHUI_DEBUGGER_TAB` to `timeline`,
`tree` or `report`; `ASHUI_DEBUGGER_AT` selects a time in seconds, and
`ASHUI_DEBUGGER_TRACK` selects a track id. `ASHUI_DEBUGGER_GIZMOS=0` hides
the motion overlay.

## Building on it

Each view accepts a `RecordingPlayer`, so you can arrange the components
in a custom layout. This follows the media controls' `Player` pattern:

```tsx
var player = new RecordingPlayer(new Recording(dir));
return <div class="flex flex-col gap-2">
  <frame-view player={player} />
  <recording-controls player={player} />
  <motion-timeline player={player} />
  <tree-changes player={player} />
</div>;
```

They are styled by `css/debugger.css` (`.ui-debugger-*`), which reads the
theme's variables.
