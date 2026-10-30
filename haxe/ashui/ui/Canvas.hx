package ashui.ui;

import ashui.animation.AnimationScheduler;
import ashui.core.externs.LayoutTreeNative;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

#if ashui_gpu
typedef CanvasPaint = ashui.core.render.CanvasFrame->Void;
#else

/** A GPU paint callback. Builds without a renderer lay out the canvas but do not paint it. **/
typedef CanvasPaint = Dynamic->Void;
#end

typedef CanvasProps = {
	/**
		Draws into the current GPU render pass at the canvas position in paint order.
		The pass is clipped to the visible canvas bounds. See `CanvasFrame`.
	**/
	?paint:CanvasPaint,

	/**
		Records shapes and paths with a `DrawContext` in canvas coordinates.
		Reactive dependencies, including canvas size, trigger a new recording
		only when they change.
	**/
	?draw:ashui.draw.DrawContext->Void,

	/** Runs a sketch on every animation frame, using the animation scheduler clock. **/
	?sketch:ashui.draw.Sketch,

	/**
		Keeps CPU drawing data for the lifetime of the canvas. Otherwise, the cache
		is released after a few seconds without a build and rebuilt when needed.
		Enable this for expensive drawings that repeatedly return to view, such as maps.
	**/
	?retain:Bool,

	/** Stops a `sketch` while true: no frames, and no wake-ups for the window; its clock waits. **/
	?paused:IntoReactive<Bool>,

	/** The most frames a `sketch` draws in a second; by default one for each the window draws. **/
	?fps:Float,

	/** Requests a frame on every animation tick while true. Use this to animate `paint`. **/
	?animate:IntoReactive<Bool>,

	/**
		Reports whether the 3D scene is waiting for textures to finish background
		compression. Meshes appear once their textures are ready.
	**/
	?onLoading:Bool->Void,

	/** Runs after each new render of the 3D scene. Use this to count scene frames. **/
	?onSceneFrame:Void->Void,

	?id:String
}

/**
	A drawing surface, written as `<canvas>` in HXX.

	`paint` draws directly with the GPU. `draw` records shapes and paths that
	the GPU renders after `paint`. Both respect the canvas transform, clipping,
	and opacity. Call `repaint()` when custom paint data changes, or enable
	`animate` to draw continuously. The default size is 300 by 150 layout units.
**/
class Canvas extends Component<CanvasProps> {
	static final bySlot = new Map<Int, Canvas>();
	static var nextSlot = 0;

	/** Returns the canvas registered at a display-list slot, or null if it has been removed. **/
	public static function at(slot:Int):Null<Canvas>
		return bySlot.get(slot);

	final ticks = Signal.make(0);

	/** Last measured canvas width, tracked by the drawing callback. **/
	final width = Signal.make(0.0);

	final height = Signal.make(0.0);

	/** Most recent recording from the `draw` callback. **/
	var recorded:Null<ashui.draw.DrawContext> = null;

	#if ashui_gpu
	final painter = new ashui.core.render.CanvasPainter();
	#end

	static function removeSettledHook(hook:LayoutTree->Void):Void {
		for (i in 0...LayoutTree.settledHooks.length)
			if (Reflect.compareMethods(LayoutTree.settledHooks[i], hook)) {
				LayoutTree.settledHooks.splice(i, 1);
				return;
			}
	}

	function render():Element {
		#if ashui_gpu
		painter.repaint = () -> repaint();
		painter.retain = props.retain == true;
		if (props.onLoading != null)
			painter.onLoading = props.onLoading;
		if (props.onSceneFrame != null)
			painter.onSceneFrame = props.onSceneFrame;
		#end
		var box = new Div({tag: "canvas", id: props.id});
		var slot = nextSlot++;
		bySlot.set(slot, this);
		var tree = box.tree, id = box.node.id;
		LayoutTreeNative.blinc_tree_set_canvas(tree.ptr, id, slot);
		Owner.onCleanup(() -> {
			bySlot.remove(slot);
			LayoutTreeNative.blinc_tree_set_canvas(tree.ptr, id, -1);
			#if ashui_gpu
			painter.dispose();
			#end
		});
		// A tick read by a watch: changing it makes the next flush report a change, so a frame is drawn.
		var t = ticks;
		new Watch(() -> t.get(), _ -> {});
		// Its size after each layout, so `draw` draws again when it changes, before the frame is drawn.
		var w = width, h = height;
		var sized:LayoutTree->Void = laid -> if (laid == tree) {
			var b = tree.getBounds(box.node);
			if (b != null) {
				if (w.get() != b.width)
					w.set(b.width);
				if (h.get() != b.height)
					h.set(b.height);
			}
		}
		LayoutTree.settledHooks.push(sized);
		Owner.onCleanup(() -> removeSettledHook(sized));
		if (props.sketch != null) {
			var sketch = props.sketch;
			var frames = 0, t = 0.0, setUp = false;
			var alive = true;
			Owner.onCleanup(() -> alive = false);
			// What the user does in the canvas is queued for the next frame, whole and in order; a press holds the pointer.
			var input = new ashui.draw.SketchInput();
			ashui.input.Interaction.of(box.node).setFocusable(true).onPointerDown(input.pointerDown).onPointerMove(input.pointerMove)
				.onPointerUp(input.pointerUp).onWheel(input.wheel).onKeyDown(input.keyDown).onKeyUp(input.keyUp).onTextInput(input.text)
				.onComposition(input.composition).onFocus(input.focus).onBlur(input.blur)
				.onTouchStart(e -> input.touch(e, 0)).onTouchMove(e -> input.touch(e, 1)).onTouchEnd(e -> input.touch(e, 2))
				.onTouchCancel(e -> input.touch(e, 3));
			var seenW = -1.0, seenH = -1.0;
			var ticker:Null<ashui.animation.AnimationScheduler.Ticker> = null;
			var pausedNow = false;
			var owed = 0.0;
			var resting = false;
			var tick:Float->Bool = null;
			// Asks for the ticker back after the sketch rested, was paused, or its window came into view.
			function wake() {
				resting = false;
				if (alive && ticker == null && !pausedNow)
					ticker = AnimationScheduler.main.addTicker(tick);
			}
			input.onActivity = wake;
			// A frame at the canvas's size; time runs from the first, drawn as soon as it is laid out.
			function step(dt:Float) {
				if (seenW >= 0 && (w.get() != seenW || h.get() != seenH))
					input.resized(w.get(), h.get());
				seenW = w.get();
				seenH = h.get();
				var ctx = new ashui.draw.Sketch.SketchContext(w.get(), h.get(), frames, input);
				if (!setUp) {
					sketch.setup(ctx);
					setUp = true;
					dt = 0;
				} else
					t += dt;
				sketch.draw(ctx, t, dt);
				frames++;
				resting = ctx.resting;
				if (!ctx.kept) {
					recorded = ctx;
					repaint();
				}
			}
			var first:LayoutTree->Void = null;
			first = laid -> if (laid == tree && !setUp && w.get() > 0 && h.get() > 0) step(0);
			LayoutTree.settledHooks.push(first);
			Owner.onCleanup(() -> removeSettledHook(first));
			tick = function(dt:Float):Bool {
				if (!alive || pausedNow || resting || !ashui.input.WindowState.visible.get()) {
					ticker = null;
					return false;
				}
				// Out of view, a sketch is not drawn; its clock waits with it.
				if (setUp && w.get() > 0 && h.get() > 0 && tree.inView(id)) {
					owed += dt;
					if (props.fps == null || props.fps <= 0 || owed >= 1 / props.fps - 0.0005) {
						var due = owed;
						owed = 0;
						step(due);
					}
				}
				if (resting) {
					ticker = null;
					return false;
				}
				return true;
			}
			// A size change, the window coming back and a paused sketch resuming are all reasons to draw.
			new Watch(() -> w.get() + h.get(), _ -> wake());
			new Watch(() -> ashui.input.WindowState.visible.get(), v -> if (v) wake());
			new Watch(() -> switch props.paused {
				case null: false;
				case Const(v): v;
				case Bound(s): s.get();
				case Derived(c): c.get();
			}, v -> {
				pausedNow = v;
				if (!v)
					wake();
			});
			wake();
			sketchWake = wake;
		}
		if (props.draw != null) {
			var draw = props.draw;
			// Out of view, a change is not drawn: the canvas keeps what it drew, and draws once more as it comes into view.
			var seen = Signal.make(0);
			var behind = false;
			// Recorded as the watch reads, which a change of what it read runs at once; the reaction asks for the frame.
			new Watch(() -> {
				seen.get();
				var width = w.get(), height = h.get();
				if (recorded != null && !tree.inView(id)) {
					behind = true;
					return recorded;
				}
				behind = false;
				var ctx = new ashui.draw.DrawContext(width, height);
				if (ctx.width > 0 && ctx.height > 0)
					draw(ctx);
				recorded = ctx;
				ctx;
			}, _ -> repaint(), (a, b) -> a == b);
			var returned:LayoutTree->Void = t -> if (t == tree && behind && tree.inView(id)) {
				behind = false;
				seen.set(seen.get() + 1);
			};
			LayoutTree.flushHooks.push(returned);
			Owner.onCleanup(() -> LayoutTree.flushHooks.remove(returned));
		}
		switch props.animate {
			case null:
			case animate:
				var running = ashui.reactive.Computed.make(() -> (switch animate {
					case Const(v): v;
					case Bound(s): s.get();
					case Derived(c): c.get();
				} : Bool));
				// git-bug 364d4b2: a paused canvas must leave the scheduler idle.
				var ticker:ashui.animation.AnimationScheduler.Ticker = null;
				function stop() {
					if (ticker != null) {
						ticker.cancel();
						ticker = null;
					}
				}
				new Watch(() -> running.get(), enabled -> {
					if (!enabled)
						stop();
					else if (ticker == null)
						ticker = AnimationScheduler.main.addTicker(_ -> {
							if (tree.inView(id))
								repaint();
							return true;
						});
				});
				Owner.onCleanup(stop);
		}
		return box;
	}

	/** Returns the last measured width. Reactive readers subscribe to size changes. **/
	public function laidWidth():Float
		return width.get();

	/** Returns the last measured height. Reactive readers subscribe to size changes. **/
	public function laidHeight():Float
		return height.get();

	var sketchWake:Null<Void->Void> = null;

	/** Starts a sketch that rested drawing again, for a change it cannot see: data it reads from outside. **/
	public function wake():Void {
		if (sketchWake != null)
			sketchWake();
	}

	/** Requests a frame after custom paint data changes. **/
	public function repaint():Void
		ticks.set(ticks.get() + 1);

	/**
		Reports whether the canvas needs a new render at this transform, pixel ratio,
		and atlas revision. Paint callbacks may change every frame; recorded drawings
		change when rebuilt or moved, and 3D scenes change when their render is dirty.
	**/
	@:allow(ashui.core.render.Renderer)
	function changed(transform:ashui.draw.Affine, ratio:Float, atlasRevision:Int):Bool {
		if (props.paint != null)
			return true;
		#if ashui_gpu
		return recorded != null && (painter.needsBuild(recorded, transform, ratio, atlasRevision) || painter.sceneChanging());
		#else
		return false;
		#end
	}

	@:allow(ashui.core.render.Renderer)
	function paintWith(frame:Dynamic):Void {
		if (props.paint != null)
			props.paint(frame);
		#if ashui_gpu
		if (recorded != null && recorded.ops.length > 0)
			painter.play(frame, recorded);
		#end
	}
}
