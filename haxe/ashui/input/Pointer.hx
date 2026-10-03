package ashui.input;

import ashui.input.Events;
import ashui.layout.LayoutTree;
import window.Modifiers;
import window.MouseButton;
import ashui.layout.LayoutTree.Hit;

/**
	Feeds pointer movement, buttons and wheel, in the tree's layout units, to
	its nodes. Each position is hit-tested as the tree is drawn: the topmost
	node under the pointer is the event's target, and the event bubbles up
	through its ancestors (see `InputEvent`). A window's loop calls these
	from its events; tests call them directly.
**/
class Pointer {
	static final states = new haxe.ds.ObjectMap<LayoutTree, PointerState>();

	/** Seconds and layout units within which presses count as one double- or triple-click. **/
	static inline var MULTI_CLICK_TIME = 0.5;
	static inline var MULTI_CLICK_SLOP = 4.0;

	static function state(tree:LayoutTree):PointerState {
		var s = states.get(tree);
		if (s == null)
			states.set(tree, s = new PointerState());
		return s;
	}

	/** The pointer moved to `(x, y)`. **/
	public static function move(tree:LayoutTree, x:Float, y:Float, ?modifiers:Modifiers):Void {
		var s = state(tree);
		s.x = x;
		s.y = y;
		s.inside = true;
		if (modifiers != null)
			s.modifiers = modifiers;
		retarget(tree, s, tree.hitTest(x, y));
		bubble(tree, s, s.chain, 0, "pointermove", null);
	}

	/** The pointer left the window: nothing is hovered. **/
	public static function leave(tree:LayoutTree):Void {
		var s = state(tree);
		s.inside = false;
		retarget(tree, s, []);
	}

	/** `button` went down where the pointer is. **/
	public static function press(tree:LayoutTree, button:MouseButton = Left):Void {
		var s = state(tree);
		var blocked = disabledIn(tree, s.chain);
		if (button.match(Left)) {
			var now = haxe.Timer.stamp();
			var near = Math.abs(s.x - s.lastX) <= MULTI_CLICK_SLOP && Math.abs(s.y - s.lastY) <= MULTI_CLICK_SLOP;
			s.clicks = now - s.lastPress <= MULTI_CLICK_TIME && near ? s.clicks + 1 : 1;
			s.lastPress = now;
			s.lastX = s.x;
			s.lastY = s.y;
			s.pressChain = s.chain.copy();
			if (!blocked) {
				for (i in interactions(tree, s.chain))
					if (!i.pressed.get())
						i.pressed.set(true);
				// Pressing gives focus to the nearest focusable node, or takes it away.
				var target = null;
				for (i in interactions(tree, s.chain))
					if (i.focusable) {
						target = i;
						break;
					}
				if (target != null)
					Focus.set(target, false);
				else
					Focus.clear(tree);
			}
		}
		if (!blocked)
			bubble(tree, s, s.chain, 0, "pointerdown", button);
	}

	/**
		`button` came up. For the left button, nothing is pressed any more,
		and the deepest node both the press and the release were over is
		clicked.
	**/
	public static function release(tree:LayoutTree, button:MouseButton = Left):Void {
		var s = state(tree);
		var blocked = disabledIn(tree, s.chain);
		if (!blocked)
			bubble(tree, s, s.chain, 0, "pointerup", button);
		if (!button.match(Left))
			return;
		for (i in Interaction.inTree(tree))
			if (i.pressed.get())
				i.pressed.set(false);
		var pressed = s.pressChain;
		s.pressChain = [];
		if (blocked || disabledIn(tree, pressed))
			return;
		for (index => hit in s.chain)
			if (Lambda.exists(pressed, p -> p.id == hit.id)) {
				bubble(tree, s, s.chain, index, "click", Left);
				return;
			}
	}

	/** A wheel or trackpad scrolled by `(dx, dy)` layout units where the pointer is. **/
	public static function wheel(tree:LayoutTree, dx:Float, dy:Float):Void {
		var s = state(tree);
		bubble(tree, s, s.chain, 0, "wheel", null, dx, dy);
	}

	/** The modifier keys now held, for the events that follow. **/
	public static function modifiers(tree:LayoutTree, modifiers:Modifiers):Void {
		state(tree).modifiers = modifiers;
	}

	/** Hit-tests again where the pointer is, for when layout moved things under it. **/
	public static function refresh(tree:LayoutTree):Void {
		var s = state(tree);
		if (s.inside)
			retarget(tree, s, tree.hitTest(s.x, s.y));
	}

	/** Moves hover to the nodes of `chain`: those it leaves get leave events, innermost first; those it reaches, enter events, outermost first. **/
	static function retarget(tree:LayoutTree, s:PointerState, chain:Array<Hit>):Void {
		var before = s.chain;
		s.chain = chain;
		inline function has(list:Array<Hit>, hit:Hit)
			return Lambda.exists(list, h -> h.id == hit.id);
		for (hit in before)
			if (!has(chain, hit)) {
				var i = Interaction.byId(tree, hit.id);
				if (i != null) {
					i.hovered.set(false);
					i.fire("pointerleave", event(i.node, s, hit));
				}
			}
		var i = chain.length;
		while (i-- > 0) {
			var hit = chain[i];
			if (!has(before, hit)) {
				var interaction = Interaction.byId(tree, hit.id);
				if (interaction != null) {
					interaction.hovered.set(true);
					interaction.fire("pointerenter", event(interaction.node, s, hit));
				}
			}
		}
	}

	/** Hands a `kind` event to the handlers along `chain` from `from` outward, until one stops it. **/
	static function bubble(tree:LayoutTree, s:PointerState, chain:Array<Hit>, from:Int, kind:String, button:Null<MouseButton>, dx = 0.0,
			dy = 0.0):Void {
		var e:Null<PointerEvent> = null;
		for (index in from...chain.length) {
			var hit = chain[index];
			var i = Interaction.byId(tree, hit.id);
			if (i == null)
				continue;
			if (e == null) {
				var target = Interaction.byId(tree, chain[from].id);
				e = new PointerEvent(target != null ? target.node : i.node, s.x, s.y, button, s.modifiers, dx, dy);
				if (button != null)
					e.count(s.clicks);
			}
			e.local(hit.x, hit.y);
			i.fire(kind, e);
			if (e.propagationStopped)
				return;
		}
	}

	static function event(node:ashui.layout.Node, s:PointerState, hit:Hit):PointerEvent {
		var e = new PointerEvent(node, s.x, s.y, null, s.modifiers);
		e.local(hit.x, hit.y);
		return e;
	}

	static function interactions(tree:LayoutTree, chain:Array<Hit>):Array<Interaction> {
		var out = [];
		for (hit in chain) {
			var i = Interaction.byId(tree, hit.id);
			if (i != null)
				out.push(i);
		}
		return out;
	}

	static function disabledIn(tree:LayoutTree, chain:Array<Hit>):Bool {
		for (i in interactions(tree, chain))
			if (i.disabled.get())
				return true;
		return false;
	}
}

private class PointerState {
	public var x = 0.0;
	public var y = 0.0;
	public var inside = false;
	public var chain:Array<Hit> = [];
	public var pressChain:Array<Hit> = [];
	public var modifiers:Modifiers = InputEvent.NO_MODIFIERS;
	/** The last press's time and place, and how many presses in a row it made. **/
	public var lastPress = -1.0;
	public var lastX = 0.0;
	public var lastY = 0.0;
	public var clicks = 0;

	public function new() {}
}
