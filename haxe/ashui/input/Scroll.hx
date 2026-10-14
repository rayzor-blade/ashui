package ashui.input;

import ashui.core.externs.LayoutTreeNative;
import ashui.input.Events;
import ashui.layout.Node;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

typedef ScrollbarColor = {final rgb:Int; final alpha:Float;}
typedef ScrollbarColors = {final thumb:ScrollbarColor; final track:ScrollbarColor;}

/**
	A scroll container: an element whose content, laid out taller or wider
	than the element, moves under the wheel or trackpad. The `overflow-auto`,
	`overflow-scroll`, `overflow-x-auto` and `overflow-y-auto` classes make
	one. Its offset is a pair of signals, so code can read and set it.

	A wheel event scrolls the innermost container under the pointer that can
	still move that way, and goes on to the containers around it once that
	one reaches its edge. A thumb shows how far along the content is while
	it scrolls, then fades; `visibility` keeps it shown, shows it while the
	pointer is over the container, or never shows it.
**/
class Scroll {
	static final byNode = new haxe.ds.ObjectMap<Node, Scroll>();

	/** Only reactive overflow needs a Haxe watch; constant overflow stays allocation-free until scrolling is enabled. **/
	static final overflowWatches = new haxe.ds.ObjectMap<Node, Map<Int, Watch<Int>>>();

	static var hooked = false;

	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		ashui.css.Css.restyled.push(identity -> {
			var scroll = byNode.get(identity.node);
			if (scroll != null) {
				var visibility = ashui.css.Css.resolved(identity, "scrollbar-visibility");
				if (visibility == null)
					visibility = "auto";
				if (scroll.visibility != visibility)
					scroll.visibility = visibility;
				scroll.restyle(identity);
			}
		});
		ashui.css.Identity.forgetHooks.push(identity -> {
			var watches = overflowWatches.get(identity.node);
			if (watches != null) {
				for (watch in watches)
					watch.stop();
				overflowWatches.remove(identity.node);
			}
			var scroll = byNode.get(identity.node);
			if (scroll != null)
				scroll.dispose();
		});
	}

	/** The native overflow binding and input axes follow the same value. **/
	@:noCompletion public static function bindOverflow(node:Node, field:Int, value:ashui.layout.IntoReactive<Int>):Void {
		var watches = overflowWatches.get(node);
		if (watches != null) {
			var old = watches.get(field);
			if (old != null)
				old.stop();
			watches.remove(field);
			if (!watches.iterator().hasNext())
				overflowWatches.remove(node);
		}
		switch (value : ashui.layout.IntoReactive.ReactiveType<Int>) {
			case Const(v):
				configure(node, field, v == ashui.types.Style.Overflow.Scroll);
			case Bound(_) | Derived(_):
				hook();
				if (watches == null)
					watches = new Map();
				overflowWatches.set(node, watches);
				var read = switch (value : ashui.layout.IntoReactive.ReactiveType<Int>) {
					case Bound(s): () -> s.get();
					case Derived(c): () -> c.get();
					case _: throw "expected reactive overflow";
				};
				var watch = new Watch(read, v -> configure(node, field, v == ashui.types.Style.Overflow.Scroll));
				watches.set(field, watch);
				ashui.reactive.Owner.onCleanup(() -> {
					watch.stop();
					if (watches.get(field) == watch)
						watches.remove(field);
					if (overflowWatches.get(node) == watches && !watches.iterator().hasNext())
						overflowWatches.remove(node);
				});
		}
	}

	/** Seconds the thumb stays after the last scroll, then the seconds it takes to fade. **/
	static inline var THUMB_STAYS = 0.8;

	static inline var THUMB_FADES = 0.25;

	/** The scroll container. **/
	public final node:Node;

	/** How far the content is scrolled right and down, in layout units. **/
	public final x:Signal<Float>;

	public final y:Signal<Float>;

	var alongX:Bool;
	var alongY:Bool;
	final hoverWatch:Watch<Bool>;
	final offsetWatch:Watch<Dynamic>;
	var disposed = false;
	final thumb = Signal.make(0.0);
	var fading = false;
	var stay:Null<ashui.animation.AnimationScheduler.Timer> = null;
	final extent = new hl.Bytes(16);
	final appearance = Signal.make(0);
	var scrollbarColors:Null<ScrollbarColors> = null;
	var scrollbarWidth = 4.0;
	var lastWidth = 4.0;
	var lastTrack = 0;
	var lastColors:Null<String> = null;
	var lastCurrentColor:Null<String> = null;

	function restyle(identity:ashui.css.Identity):Void {
		var colors = ashui.css.Css.resolved(identity, "scrollbar-color");
		var current = colors != null
			&& colors.toLowerCase().indexOf("currentcolor") >= 0 ? ashui.css.Css.resolved(identity, "color") : null;
		if (colors != lastColors || current != lastCurrentColor) {
			var next = try ashui.css.Properties.scrollbarColors(colors == null ? "auto" : colors,
				current == null ? Rgba(0, 1) : ashui.css.CssValue.color(current)) catch (_:String) null;
			setScrollbarColors(next);
			lastColors = colors;
			lastCurrentColor = current;
		}
		var width = ashui.css.Css.resolved(identity, "scrollbar-width");
		setScrollbarWidth(try ashui.css.Properties.scrollbarWidth(width == null ? "auto" : width) catch (_:String) 4.0);
	}

	/** Restyles the existing thumb watch; no additional watcher or ticker. Null restores the theme. **/
	@:noCompletion public function setScrollbarColors(colors:Null<ScrollbarColors>):Void {
		if (colors == null && scrollbarColors == null)
			return;
		if (colors != null
			&& scrollbarColors != null
			&& colors.thumb.rgb == scrollbarColors.thumb.rgb
			&& colors.thumb.alpha == scrollbarColors.thumb.alpha
			&& colors.track.rgb == scrollbarColors.track.rgb
			&& colors.track.alpha == scrollbarColors.track.alpha)
			return;
		scrollbarColors = colors;
		appearance.set(appearance.get() + 1);
	}

	/** Overlay widths in layout units: auto 4, thin 2, none 0. **/
	@:noCompletion public function setScrollbarWidth(width:Float):Void {
		if (scrollbarWidth == width)
			return;
		scrollbarWidth = width;
		if (width == 0) {
			if (stay != null)
				stay.cancel();
			stay = null;
			fading = false;
			if (visibility == "auto")
				thumb.set(0);
		}
		appearance.set(appearance.get() + 1);
	}

	static inline function packed(rgb:Int, alpha:Float):Int
		return Std.int(Math.max(0, Math.min(1, alpha)) * 255) << 24 | rgb;

	/**
		When the thumb shows: "auto" while it scrolls (the default),
		"always", "hover" while the pointer is over the container, or
		"hidden". CSS's `scrollbar-visibility` sets it.
	**/
	public var visibility(default, set) = "auto";

	function set_visibility(v:String):String {
		if (v == visibility) {
			if (v == "always" && (alongX || alongY))
				thumb.set(1);
			if (v == "hidden")
				thumb.set(0);
			return v;
		}
		if (stay != null)
			stay.cancel();
		stay = null;
		fading = false;
		visibility = v;
		switch v {
			case "always":
				fading = false;
				thumb.set(1);
			case "hidden":
				fading = false;
				thumb.set(0);
			case "hover":
				if (Interaction.of(node).hovered.get())
					thumb.set(1);
				else
					fade();
			case _:
				fade();
		}
		return v;
	}

	function new(node:Node, alongX:Bool, alongY:Bool) {
		this.node = node;
		this.alongX = alongX;
		this.alongY = alongY;
		x = Signal.make(0.0);
		y = Signal.make(0.0);
		Interaction.of(node).onWheel(wheel);
		// Shown while the pointer is over it, for "hover".
		var hovered = Interaction.of(node).hovered;
		hoverWatch = new Watch(() -> hovered.get(), h -> if (visibility == "hover") {
			if (h) {
				fading = false;
				thumb.set(1);
			} else
				fade();
		});
		// Reacts at the next flush, which marks the frame for redrawing.
		offsetWatch = new Watch(() -> {
			appearance.get();
			var colors = scrollbarColors;
			var c = colors == null ? ashui.theme.ThemeState.tryGet() : null;
			var color = c != null ? c.color(TextTertiary) : null;
			var shown = thumb.get();
			{
				x: x.get(),
				y: y.get(),
				thumb: colors == null ? packed(color != null ? color.rgb() : 0x808080, shown * 0.7) : packed(colors.thumb.rgb, shown * colors.thumb.alpha),
				track: colors == null ? 0 : packed(colors.track.rgb, shown * colors.track.alpha),
				width: scrollbarWidth
			};
		}, s -> {
			if (node.tree != null) {
				LayoutTreeNative.blinc_tree_set_scroll(node.tree.ptr, node.id, s.x, s.y, s.thumb);
				if (lastWidth != s.width || lastTrack != s.track) {
					LayoutTreeNative.blinc_tree_set_scrollbar_style(node.tree.ptr, node.id, s.width, s.track);
					lastWidth = s.width;
					lastTrack = s.track;
				}
			}
		},
			(a, b) -> a.x == b.x && a.y == b.y && a.thumb == b.thumb && a.track == b.track && a.width == b.width);
	}

	/** Makes `node` a scroll container along the axes given; once per node. **/
	public static function attach(node:Node, alongX:Bool, alongY:Bool):Scroll {
		hook();
		var known = byNode.get(node);
		if (known != null) {
			known.setAxes(known.alongX || alongX, known.alongY || alongY);
			return known;
		}
		var s = new Scroll(node, alongX, alongY);
		byNode.set(node, s);
		ashui.reactive.Owner.onCleanup(s.dispose);
		return s;
	}

	function dispose():Void {
		if (disposed)
			return;
		disposed = true;
		Pointer.cancelWheel(node);
		byNode.remove(node);
		hoverWatch.stop();
		offsetWatch.stop();
		if (stay != null)
			stay.cancel();
		stay = null;
		fading = false;
	}

	/** Updates one CSS overflow field without allocating another interaction or watch. **/
	public static function configure(node:Node, field:Int, enabled:Bool):Void {
		var s = byNode.get(node);
		if (s == null) {
			if (enabled)
				attach(node, field != ashui.layout.PropertyId.OverflowY, field != ashui.layout.PropertyId.OverflowX);
			return;
		}
		s.setAxes(field == ashui.layout.PropertyId.OverflowY ? s.alongX : enabled, field == ashui.layout.PropertyId.OverflowX ? s.alongY : enabled);
	}

	function setAxes(nextX:Bool, nextY:Bool):Void {
		if (alongX == nextX && alongY == nextY)
			return;
		Pointer.cancelWheel(node);
		alongX = nextX;
		alongY = nextY;
		if ((alongX || alongY) && (visibility == "always" || visibility == "hover" && Interaction.of(node).hovered.get()))
			thumb.set(1);
		if (!alongX)
			x.set(0);
		if (!alongY)
			y.set(0);
		if (!alongX && !alongY) {
			if (stay != null)
				stay.cancel();
			stay = null;
			fading = false;
			thumb.set(0);
		}
	}

	/** `node`'s scroll container, if it is one. **/
	public static function of(node:Node):Null<Scroll>
		return byNode.get(node);

	/** The scroll container of the node `id`, found by its id rather than its `Node`. **/
	public static function at(id:haxe.Int64, ?tree:ashui.layout.LayoutTree):Null<Scroll> {
		for (n => s in byNode)
			if (n.id == id && (tree == null || n.tree == tree))
				return s;
		return null;
	}

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
		return bounded(toX, toY, max.x, max.y);
	}

	function bounded(toX:Float, toY:Float, maxX:Float, maxY:Float):Bool {
		var nx = Math.max(0, Math.min(maxX, toX));
		var ny = Math.max(0, Math.min(maxY, toY));
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
		if (disposed)
			return;
		// A vertical wheel scrolls a container that only scrolls sideways.
		var dx = e.deltaX, dy = e.deltaY;
		if (alongX && !alongY && dx == 0) {
			dx = dy;
			dy = 0;
		}
		// The content follows the fingers: a positive delta moves it down, toward the start.
		var max = limits();
		// Even at a boundary, scrolling must not begin editing an input that
		// moves under the pointer. Outer scrollers still receive unused deltas (095fab4).
		if (dx != 0 && max.x > 0 || dy != 0 && max.y > 0)
			e.captureWheel();
		if (bounded(x.get() - dx, y.get() - dy, max.x, max.y))
			e.stopPropagation();
	}

	function showThumb():Void {
		// Always shown, never shown, or shown by the pointer: scrolling changes none of these.
		if (visibility != "auto" || scrollbarWidth == 0)
			return;
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
		if (scrollbarWidth == 0) {
			thumb.set(0);
			fading = false;
			return;
		}
		// From where it is: nothing to fade when it is not shown.
		var from = thumb.get();
		if (from <= 0 || fading)
			return;
		fading = true;
		var faded = 0.0;
		ashui.animation.AnimationScheduler.main.addTicker(dt -> {
			if (!fading)
				return false;
			faded += dt;
			var alpha = Math.max(0, from * (1 - faded / THUMB_FADES));
			thumb.set(alpha);
			if (alpha <= 0) {
				fading = false;
				return false;
			}
			return true;
		});
	}
}
