# ashui debugger

An app for reviewing what an ashui UI did, frame by frame. It is built
with `ashui.components` and lives beside the libraries as a project of its
own.

It opens a recording made by `ashui.debug.MotionRecorder` and plays it back:

- the recorded frames, with transport controls to play, pause, step a
  frame at a time, scrub, slow down and repeat, and to turn the gizmos
  (the motion overlay's outlines, trails, labels and bars) on and off;
- a timeline of every animation in the recording: its element and
  property, a bar from when it began to when it ended, marked when its
  checks found a problem. Selecting one outlines its element on the frame
  and shows its verdict;
- what changed in the element tree at each frame: elements added and
  removed, boxes, states and restyled values;
- the motion report, and the frame regression result when the recording
  was checked against a baseline.

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

`RECORDING` picks the recording; `ASHUI_DEBUGGER_TAB` (`timeline`, `tree`,
`report`), `ASHUI_DEBUGGER_AT` (seconds) and `ASHUI_DEBUGGER_TRACK` (a track
id) pick what the page shows, and `ASHUI_DEBUGGER_GIZMOS=0` shows frames
without their gizmos.

## Building on it

The views are components that take a `RecordingPlayer`, the way
`ashui.media`'s controls take a `Player`, so they can be arranged in
another layout:

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
