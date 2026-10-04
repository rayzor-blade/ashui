package ashui.animation;

import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.theme.Easing;

typedef LayoutAnimationOptions = {
	/** Animates where it is; true by default. **/
	?position:Bool,
	/** Animates its size, its children clipped to the size drawn; true by default. **/
	?size:Bool,
	/** Seconds the move takes; the theme's normal duration by default. **/
	?duration:Float,
	/** Its curve; the theme's ease-out by default. **/
	?easing:Easing
}

/**
	Layout animation by FLIP: when layout moves or resizes an element, layout
	settles at once and the element is drawn where it was, then eases to
	where it is now. Nothing is laid out again for it: the element is drawn
	away from its layout (`LayoutTree.setVisual`), moved by what is left of
	the move and, while its size changes, at the size between, its children
	clipped to it rather than stretched. An accordion's panel growing, a
	list's items making room, a tab's indicator sliding.

	A change is measured against the nearest animated element it is in, so
	a child carried by its parent's move does not move twice. A change while
	one is running starts from where the element is drawn then. It eases
	over the theme's motion tokens unless given its own.
**/
class LayoutAnimation {
	static final animated = new haxe.ds.ObjectMap<LayoutTree, Map<String, LayoutAnimation>>();
	static var hooked = false;

	final node:Node;
	final tree:LayoutTree;
	final options:LayoutAnimationOptions;
	/** Its box at the last layout, relative to the nearest animated element it is in. **/
	var last:Null<{x:Float, y:Float, w:Float, h:Float}> = null;
	/** Where it is drawn from, relative to its layout, and the size it is drawn at, when the running move started; and how far it is. **/
	var from = {dx: 0.0, dy: 0.0, w: 0.0, h: 0.0};
	var to = {w: 0.0, h: 0.0};
	var elapsed = 0.0;
	var running = false;
	/** Where it is drawn now, relative to its layout, and at what size. **/
	var shown = {dx: 0.0, dy: 0.0, w: -1.0, h: -1.0};

	/** Animates `node`'s layout changes from now until the current owner is cleaned up. **/
	public static function attach(node:Node, ?options:LayoutAnimationOptions):LayoutAnimation {
		hook();
		var a = new LayoutAnimation(node, options == null ? {} : options);
		var tree = node.tree;
		var list = animated.get(tree);
		if (list == null)
			animated.set(tree, list = new Map());
		var key = haxe.Int64.toStr(node.id);
		list.set(key, a);
		if (Owner.current != null)
			Owner.onCleanup(() -> {
				list.remove(key);
				a.running = false;
			});
		return a;
	}

	function new(node:Node, options:LayoutAnimationOptions) {
		this.node = node;
		this.tree = node.tree;
		this.options = options;
	}

	static function hook():Void {
		if (hooked)
			return;
		hooked = true;
		LayoutTree.layoutHooks.push(tree -> {
			var list = animated.get(tree);
			if (list != null)
				for (a in list)
					a.measure(list);
			false;
		});
	}

	/** After a layout pass: starts a move when its box changed. **/
	function measure(list:Map<String, LayoutAnimation>):Void {
		var b = tree.getBounds(node);
		if (b == null)
			return;
		var x:Float = b.x, y:Float = b.y;
		// Relative to the nearest animated element it is in, whose own move carries it.
		for (up in tree.ancestors(node.id))
			if (list.exists(haxe.Int64.toStr(up))) {
				var p = tree.getBounds(new Node(up));
				if (p != null) {
					x -= p.x;
					y -= p.y;
				}
				break;
			}
		var now = {x: x, y: y, w: (b.width : Float), h: (b.height : Float)};
		var was = last;
		last = now;
		if (was == null || (was.x == now.x && was.y == now.y && was.w == now.w && was.h == now.h))
			return;
		// From where it is drawn now: its last layout, less what of the running move is left.
		var position = options.position != false, size = options.size != false;
		from = {
			dx: position ? was.x + shown.dx - now.x : 0.0,
			dy: position ? was.y + shown.dy - now.y : 0.0,
			w: size ? (shown.w >= 0 ? shown.w : was.w) : now.w,
			h: size ? (shown.h >= 0 ? shown.h : was.h) : now.h
		};
		to = {w: now.w, h: now.h};
		elapsed = 0;
		apply(0);
		if (!running) {
			running = true;
			AnimationScheduler.main.addTicker(dt -> {
				if (!running)
					return false;
				elapsed += dt;
				var t = Math.min(1, elapsed / duration());
				apply(t);
				if (t >= 1) {
					running = false;
					shown = {dx: 0, dy: 0, w: -1, h: -1};
					tree.clearVisual(node.id);
				}
				return running;
			});
		}
	}

	function duration():Float {
		if (options.duration != null)
			return Math.max(options.duration, 0.0001);
		var theme = ashui.theme.ThemeState.tryGet();
		return theme == null ? 0.2 : theme.animations().durationNormal / 1000;
	}

	function apply(t:Float):Void {
		var easing = options.easing;
		if (easing == null) {
			var theme = ashui.theme.ThemeState.tryGet();
			easing = theme == null ? EaseOut : theme.animations().easeOut;
		}
		var e = EasingTools.evaluate(easing, t);
		var left = 1 - e;
		var sized = from.w != to.w || from.h != to.h;
		shown = {
			dx: from.dx * left,
			dy: from.dy * left,
			w: sized ? from.w + (to.w - from.w) * e : -1.0,
			h: sized ? from.h + (to.h - from.h) * e : -1.0
		};
		tree.setVisual(node.id, shown.dx, shown.dy, shown.w, shown.h);
	}
}
