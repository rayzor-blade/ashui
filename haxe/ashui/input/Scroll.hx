package ashui.input;

import ashui.core.externs.LayoutTreeNative;
import ashui.input.Events;
import ashui.layout.Node;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

/**
	A scroll container: an element whose content, laid out taller or wider
	than the element, moves under the wheel or trackpad. The `overflow-auto`,
	`overflow-scroll`, `overflow-x-auto` and `overflow-y-auto` classes make
	one. Its offset is a pair of signals, so code can read and set it.

	A wheel event scrolls the innermost container under the pointer that can
	still move that way, and goes on to the containers around it once that
	one reaches its edge. A thumb shows how far along the content is while
	it scrolls, then fades.
**/
class Scroll {
	static final byNode = new haxe.ds.ObjectMap<Node, Scroll>();

	/** Seconds the thumb stays after the last scroll, then the seconds it takes to fade. **/
	static inline var THUMB_STAYS = 0.8;
	static inline var THUMB_FADES = 0.25;

	/** The scroll container. **/
	public final node:Node;

	/** How far the content is scrolled right and down, in layout units. **/
	public final x:Signal<Float>;
	public final y:Signal<Float>;

	final alongX:Bool;
	final alongY:Bool;
	final thumb = Signal.make(0.0);
	var fading = false;
	var stay:Null<ashui.animation.AnimationScheduler.Timer> = null;
	final extent = new hl.Bytes(16);

	function new(node:Node, alongX:Bool, alongY:Bool) {
		this.node = node;
		this.alongX = alongX;
		this.alongY = alongY;
		x = Signal.make(0.0);
		y = Signal.make(0.0);
		Interaction.of(node).onWheel(wheel);
		// Reacts at the next flush, which marks the frame for redrawing.
		new Watch(() -> {
			var c = ashui.theme.ThemeState.tryGet();
			var color = c != null ? c.color(TextTertiary) : null;
			{
				x: x.get(),
				y: y.get(),
				thumb: thumb.get(),
				rgb: color != null ? color.rgb() : 0x808080
			};
		}, s -> {
			var alpha = Std.int(Math.max(0, Math.min(1, s.thumb * 0.7)) * 255);
			if (node.tree != null)
				LayoutTreeNative.blinc_tree_set_scroll(node.tree.ptr, node.id, s.x, s.y, alpha << 24 | s.rgb);
		}, (a, b) -> a.x == b.x && a.y == b.y && a.thumb == b.thumb && a.rgb == b.rgb);
	}

	/** Makes `node` a scroll container along the axes given; once per node. **/
	public static function attach(node:Node, alongX:Bool, alongY:Bool):Scroll {
		var known = byNode.get(node);
		if (known != null)
			return known;
		var s = new Scroll(node, alongX, alongY);
		byNode.set(node, s);
		return s;
	}

	/** `node`'s scroll container, if it is one. **/
	public static function of(node:Node):Null<Scroll>
		return byNode.get(node);

	/** How far the content can scroll right and down; zeros before layout. **/
	public function limits():{x:Float, y:Float} {
		if (node.tree == null || !LayoutTreeNative.blinc_tree_scroll_extent(node.tree.ptr, node.id, extent))
			return {x: 0, y: 0};
		return {
			x: alongX ? Math.max(0, extent.getF32(8) - extent.getF32(0)) : 0,
			y: alongY ? Math.max(0, extent.getF32(12) - extent.getF32(4)) : 0
		};
	}

	/** Scrolls to `(toX, toY)`, kept within the content; true if it moved. **/
	public function scrollTo(toX:Float, toY:Float):Bool {
		var max = limits();
		var nx = Math.max(0, Math.min(max.x, toX));
		var ny = Math.max(0, Math.min(max.y, toY));
		if (nx == x.get() && ny == y.get())
			return false;
		x.set(nx);
		y.set(ny);
		showThumb();
		return true;
	}

	/**
		Scrolls to `(toX, toY)` as given, kept only from going below 0: for a
		caller that knows how far the content reaches before layout does,
		such as a text area that has just grown a line.
	**/
	public function jumpTo(toX:Float, toY:Float):Void {
		var nx = alongX ? Math.max(0, toX) : 0;
		var ny = alongY ? Math.max(0, toY) : 0;
		if (nx == x.get() && ny == y.get())
			return;
		x.set(nx);
		y.set(ny);
		showThumb();
	}

	function wheel(e:PointerEvent):Void {
		// A vertical wheel scrolls a container that only scrolls sideways.
		var dx = e.deltaX, dy = e.deltaY;
		if (alongX && !alongY && dx == 0) {
			dx = dy;
			dy = 0;
		}
		// The content follows the fingers: a positive delta moves it down, toward the start.
		if (scrollTo(x.get() - dx, y.get() - dy))
			e.stopPropagation();
	}

	function showThumb():Void {
		if (thumb.get() != 1)
			thumb.set(1);
		fading = false;
		if (stay != null)
			stay.cancel();
		// The thumb stays without drawing frames, then fades over a few.
		stay = ashui.animation.AnimationScheduler.main.after(THUMB_STAYS, fade);
	}

	function fade():Void {
		stay = null;
		fading = true;
		var faded = 0.0;
		ashui.animation.AnimationScheduler.main.addTicker(dt -> {
			if (!fading)
				return false;
			faded += dt;
			var alpha = Math.max(0, 1 - faded / THUMB_FADES);
			thumb.set(alpha);
			if (alpha <= 0) {
				fading = false;
				return false;
			}
			return true;
		});
	}
}
