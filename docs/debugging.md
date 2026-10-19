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

## GPU errors

A window keeps running when the GPU reports an error while a frame is drawn. The error is written once to stderr,
starting with `[ashui] gpu error drawing, the frame goes on`, and the next frame is drawn whole. The count of such
frames is `offscreen.failedFrames`. Anything that draws with an `Offscreen` directly, such as a test or a snapshot,
throws instead, until `offscreen.strictErrors` is set to `false`.

The GPU reports an error after the frame, without saying which texture or buffer it was about, so the message names
the limit that was passed and little else. A canvas whose triangles do not fit in a texture says so on stderr and
draws the first of them, and a mesh texture larger than the device's limit is shrunk to it.

## Partial redraws

A frame that has a backdrop filter is drawn into a layer that stays from one frame to the next. When the next frame
differs from it in only a few records or canvases, only the boxes of what changed are drawn again; the rest of the layer
is kept. `ASHUI_DAMAGE=0` turns this off, to compare. `offscreen.drew` says how the last frame was drawn: `full`, `none`,
or the rectangles drawn again.
