package ashui.ui;

import ashui.animation.AnimationScheduler;
import ashui.core.externs.LayoutTreeNative;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

#if ashui_gpu
typedef CanvasPaint = ashui.core.render.CanvasPass->Void;
#else
/** A build without the renderer lays a canvas out and never paints it. **/
typedef CanvasPaint = Dynamic->Void;
#end

typedef CanvasProps = {
	/**
		Paints the canvas with the GPU, in every frame drawn: handed the
		render pass at the canvas's place in paint order, scissored to its
		clipped box (see `CanvasPass`).
	**/
	?paint:CanvasPaint,

	/** While true, a frame is drawn every tick of the animation scheduler, so `paint` animates. **/
	?animate:IntoReactive<Bool>,

	?id:String
}

/**
	HTML's `<canvas>`, built in: a box that paints itself with the GPU. Its
	`paint` runs whenever a frame is drawn, at the canvas's place in paint
	order, under its transform, clips and opacity; `repaint` asks for a
	frame when what it paints changes, and `animate` asks for every frame.
	It is 300 by 150 unless sized, as HTML's is.
**/
class Canvas extends Component<CanvasProps> {
	static final bySlot = new Map<Int, Canvas>();
	static var nextSlot = 0;

	/** The canvas the display list knows as `slot`, if it is still there. **/
	public static function at(slot:Int):Null<Canvas>
		return bySlot.get(slot);

	final ticks = Signal.make(0);

	function render():Element {
		var box = new Div({tag: "canvas", id: props.id});
		var slot = nextSlot++;
		bySlot.set(slot, this);
		var tree = box.tree, id = box.node.id;
		LayoutTreeNative.blinc_tree_set_canvas(tree.ptr, id, slot);
		Owner.onCleanup(() -> {
			bySlot.remove(slot);
			LayoutTreeNative.blinc_tree_set_canvas(tree.ptr, id, -1);
		});
		// A tick read by a watch: changing it makes the next flush report a change, so a frame is drawn.
		var t = ticks;
		new Watch(() -> t.get(), _ -> {});
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
					if (alive && running.get())
						repaint();
					return alive;
				});
		}
		return box;
	}

	/** Asks for a frame: what `paint` draws has changed. **/
	public function repaint():Void
		ticks.set(ticks.get() + 1);

	@:allow(ashui.core.render.Renderer)
	function paintWith(pass:Dynamic):Void
		if (props.paint != null)
			props.paint(pass);
}
