package ashui.input;

import ashui.core.externs.LayoutTreeNative;
import ashui.input.Events;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

typedef ScrollbarColor = {final rgb:Int; final alpha:Float;}
typedef ScrollbarColors = {final thumb:ScrollbarColor; final track:ScrollbarColor;}

/**
	Manages scrolling when an element's content exceeds its visible bounds.
	Create a scroll container with `overflow-auto`, `overflow-scroll`,
	`overflow-x-auto` or `overflow-y-auto`. Offset signals can be read or set
	from application code.

	Wheel events scroll the innermost container that can move in the requested
	direction. At an edge, scrolling continues in an ancestor container.
	The scrollbar thumb appears during scrolling, then fades. `visibility`
	can instead keep it visible, show it on hover or hide it entirely.
**/
class Scroll {
	static final byNode = new haxe.ds.ObjectMap<Node, Scroll>();

	/** Only reactive overflow needs a Haxe watch; constant overflow stays allocation-free until scrolling is enabled. **/
	static final overflowWatches = new haxe.ds.ObjectMap<Node, Map<Int, Watch<Int>>>();

	static var hooked = false;

	/** The containers whose reach is followed: those with `scroll-shadow: auto` and those something asked a reach signal of. **/
	static final followed:Array<Scroll> = [];

	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		ashui.css.Css.restyled.push(identity -> {
			var scroll = byNode.get(identity.node);
			if (scroll != null) {
				scroll.setShadow(ashui.css.Css.resolved(identity, "scroll-shadow") == "auto");
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

	/**
		Whether content is hidden past each edge: scrolled away above or at the left, or still to scroll to below or at the right.
		A signal is made, and the reach followed after each layout and scroll, the first time one is read; each moves only when the edge
		is crossed.
	**/
	public var moreAbove(get, never):Signal<Bool>;

	public var moreBelow(get, never):Signal<Bool>;
	public var moreLeft(get, never):Signal<Bool>;
	public var moreRight(get, never):Signal<Bool>;

	var reach = 0;
	var reachSignals:Null<Array<Null<Signal<Bool>>>> = null;
	var shadow = false;

	static inline var ABOVE = 1;
	static inline var BELOW = 2;
	static inline var LEFT = 4;
	static inline var RIGHT = 8;

	function reachSignal(index:Int):Signal<Bool> {
		if (reachSignals == null)
			reachSignals = [null, null, null, null];
		follow();
		var s = reachSignals[index];
		if (s == null)
			reachSignals[index] = s = Signal.make((reach & (1 << index)) != 0);
		return s;
	}

	function get_moreAbove():Signal<Bool> return reachSignal(0);
	function get_moreBelow():Signal<Bool> return reachSignal(1);
	function get_moreLeft():Signal<Bool> return reachSignal(2);
	function get_moreRight():Signal<Bool> return reachSignal(3);

	static var followHooked = false;

	function follow():Void {
		// One layout hook for every followed container, made when the first is.
		if (!followHooked) {
			followHooked = true;
			LayoutTree.layoutHooks.push(_ -> {
				var changed = false;
				for (scroll in followed.copy())
					if (scroll.refreshReach())
						changed = true;
				changed;
			});
		}
		if (followed.indexOf(this) < 0) {
			followed.push(this);
			refreshReach();
		}
	}

	/** Draws inset shadows at the edges that hide content (CSS `scroll-shadow: auto`), through the attributes the user-agent sheet styles. **/
	function setShadow(on:Bool):Void {
		if (on == shadow)
			return;
		shadow = on;
		if (node.tree != null) {
			var identity = ashui.css.Identity.of(node.tree, node.id);
			if (identity != null)
				identity.setAttribute("data-scroll-shadow", on ? "" : null);
		}
		if (on) {
			// The rules that draw the shadows are the user-agent sheet's.
			ashui.css.Css.useUserAgent();
			follow();
		} else {
			markEdges(0);
			if (reachSignals == null)
				followed.remove(this);
		}
	}

	function markEdges(bits:Int):Void {
		var identity = node.tree == null ? null : ashui.css.Identity.of(node.tree, node.id);
		if (identity == null)
			return;
		identity.setAttribute("data-more-above", bits & ABOVE != 0 ? "" : null);
		identity.setAttribute("data-more-below", bits & BELOW != 0 ? "" : null);
		identity.setAttribute("data-more-left", bits & LEFT != 0 ? "" : null);
		identity.setAttribute("data-more-right", bits & RIGHT != 0 ? "" : null);
	}

	/** Works out the reach from the scroll and the layout; true when an edge was crossed. **/
	function refreshReach():Bool {
		if (disposed)
			return false;
		var l = limits(), px = x.get(), py = y.get();
		var next = (py > .5 ? ABOVE : 0) | (py < l.y - .5 ? BELOW : 0) | (px > .5 ? LEFT : 0) | (px < l.x - .5 ? RIGHT : 0);
		if (next == reach)
			return false;
		reach = next;
		if (reachSignals != null)
			for (i in 0...4)
				if (reachSignals[i] != null)
					reachSignals[i].set((next & (1 << i)) != 0);
		if (shadow)
			markEdges(next);
		return true;
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
		followed.remove(this);
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
		if (followed.length > 0 && followed.indexOf(this) >= 0)
			refreshReach();
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
		if (followed.indexOf(this) >= 0)
			refreshReach();
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
