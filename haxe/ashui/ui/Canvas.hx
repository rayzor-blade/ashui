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
/** A build without the renderer lays a canvas out and never paints it. **/
typedef CanvasPaint = Dynamic->Void;
#end

typedef CanvasProps = {
	/**
		Paints the canvas with the GPU, in every frame drawn: handed the
		render pass at the canvas's place in paint order, scissored to its
		clipped box (see `CanvasFrame`).
	**/
	?paint:CanvasPaint,

	/**
		Draws the canvas with a `DrawContext` of its size: shapes and paths
		filled and stroked, in its own coordinates. Run as a computed is, it
		draws again when a signal it read changes, its size included, and
		only then.
	**/
	?draw:ashui.draw.DrawContext->Void,

	/** Runs a sketch: drawn again every frame, on the animation scheduler's clock. **/
	?sketch:ashui.draw.Sketch,

	/** While true, a frame is drawn every tick of the animation scheduler, so `paint` animates. **/
	?animate:IntoReactive<Bool>,

	/**
		Called with true when meshes it draws start waiting for their
		textures, which are compressed in the background, and with false when
		all are in place; a mesh is not drawn until its textures are.
	**/
	?onLoading:Bool->Void,

	/** Called after each frame in which its 3D scene was rendered afresh: what a frame counter counts. **/
	?onSceneFrame:Void->Void,

	?id:String
}

/**
	HTML's `<canvas>`, built in: a box that paints itself with the GPU. Its
	`paint` runs whenever a frame is drawn, at the canvas's place in paint
	order, under its transform, clips and opacity; `repaint` asks for a
	frame when what it paints changes, and `animate` asks for every frame.
	It is 300 by 150 unless sized, as HTML's is. Its `draw`, when it has
	one, is recorded and played by the GPU after `paint`.
**/
class Canvas extends Component<CanvasProps> {
	static final bySlot = new Map<Int, Canvas>();
	static var nextSlot = 0;

	/** The canvas the display list knows as `slot`, if it is still there. **/
	public static function at(slot:Int):Null<Canvas>
		return bySlot.get(slot);

	final ticks = Signal.make(0);

	/** Its size as last laid out, which `draw` reads. **/
	final width = Signal.make(0.0);

	final height = Signal.make(0.0);

	/** What `draw` drew, last time it ran. **/
	var recorded:Null<ashui.draw.DrawContext> = null;

	#if ashui_gpu
	final painter = new ashui.core.render.CanvasPainter();
	#end

	function render():Element {
		#if ashui_gpu
		painter.repaint = () -> repaint();
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
		Owner.onCleanup(() -> LayoutTree.settledHooks.remove(sized));
		if (props.sketch != null) {
			var sketch = props.sketch;
			var frames = 0, t = 0.0, setUp = false;
			var alive = true;
			Owner.onCleanup(() -> alive = false);
			// A frame at the canvas's size; time runs from the first, drawn as soon as it is laid out.
			function step(dt:Float) {
				var ctx = new ashui.draw.Sketch.SketchContext(w.get(), h.get(), frames);
				if (!setUp) {
					sketch.setup(ctx);
					setUp = true;
					dt = 0;
				} else
					t += dt;
				sketch.draw(ctx, t, dt);
				frames++;
				recorded = ctx;
				repaint();
			}
			var first:LayoutTree->Void = null;
			first = laid -> if (laid == tree && !setUp && w.get() > 0 && h.get() > 0)
				step(0);
			LayoutTree.settledHooks.push(first);
			Owner.onCleanup(() -> LayoutTree.settledHooks.remove(first));
			AnimationScheduler.main.addTicker(dt -> {
				if (!alive)
					return false;
				// Out of view, a sketch is not drawn; its clock waits with it.
				if (setUp && w.get() > 0 && h.get() > 0 && tree.inView(id))
					step(dt);
				return true;
			});
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
				var alive = true;
				Owner.onCleanup(() -> alive = false);
				AnimationScheduler.main.addTicker(_ -> {
					if (alive && running.get() && tree.inView(id))
						repaint();
					return alive;
				});
		}
		return box;
	}

	/** Its width as last laid out; read in a computed or watch, which follows it. **/
	public function laidWidth():Float
		return width.get();

	/** Its height as last laid out, followed as `laidWidth` is. **/
	public function laidHeight():Float
		return height.get();

	/** Asks for a frame: what `paint` draws has changed. **/
	public function repaint():Void
		ticks.set(ticks.get() + 1);

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
