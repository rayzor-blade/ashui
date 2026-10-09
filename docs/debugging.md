# Visual debugging

The snapshot runner captures a scene offscreen, or opens the same scene in
an interactive window with `--window`. Both use the framework renderer.

## Hit map

```sh
ASHUI_HIT_MAP=1 tools/demo/run.sh tools/demo/Interactions.hx
ASHUI_HIT_MAP=1 tools/snapshot/run.sh --window tools/snapshot/scenes/ComponentsGallery.hx
ASHUI_HIT_MAP=1 tools/snapshot/run.sh tools/snapshot/scenes/HitMap.hx
```

Colors show the **topmost native hit target**, including plain containers,
text and component roots with no handlers. Overlaps, transforms, clipping
and nodes marked pass-through follow the same native hit tests used for input.
The spatial map samples a grid, whose spacing appears in the panel; the
panel's **pointer path is exact**.

The first row is the target. Subsequent rows are its ancestors, in bubbling
order. Each row shows the element's tag, CSS id and native id, plus its
registered handlers, whether it owns input state, and focus/disabled state.
`No handlers` means the node can be hit without running an application
handler. The path shows where
events can bubble; handlers can stop propagation, and disabled ancestors
block button input.

For bubbling pointer events, `event.target` is the first node in that path
with input state. It can differ from the deepest native hit, such as text
inside a button.

An amber outline marks the native region available for quiet hit caching.
The debugger installs no continuous ticker or pointer hook: movement inside that region still
coalesces in the native window, and the marker updates when the dispatcher
consumes the next position. Enable the map only for inspection when
measuring interaction/rendering costs.

For a renderer embedded in another application, add the same overlay:

```haxe
var hits = new ashui.debug.HitOverlay();
offscreen.overlays.push(hits);
var path = hits.inspect(tree, x, y); // exact native path, deepest first
```

`sampleSize` controls the map's requested grid spacing (four layout units
by default). Large viewports increase the spacing to cap sampling at
65,536 points. The map is cached until layout, geometry, clipping or the
viewport changes. Overlays draw in their own trees.

## Motion

```sh
ASHUI_MOTION=overlay tools/snapshot/run.sh --window tools/snapshot/scenes/TreeMotion.hx
ASHUI_MOTION=stream tools/snapshot/run.sh --window tools/snapshot/scenes/TreeMotion.hx
```

`overlay` shows moving bounds, trails, progress and per-element easing
curves. `stream` also captures each burst with frames, a filmstrip, curves,
motion differences, a report and JSON for review. `ASHUI_HIT_MAP=1` can be
used alongside either mode.
