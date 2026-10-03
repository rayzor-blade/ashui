package ashui.input;

import ashui.input.Events;
import ashui.layout.LayoutTree;
import window.Modifiers;

/**
	Feeds hlwindow's key events and text to the focused node of a tree,
	bubbling up through its ancestors. Unless a handler calls
	`preventDefault`, Tab and Shift+Tab move focus, and Enter, or Space on
	release, clicks the focused node, as a button does.
**/
class Keyboard {
	/** A key went down or up, as hlwindow reports it. **/
	public static function input(tree:LayoutTree, event:window.KeyEvent, ?modifiers:Modifiers):Void {
		var mods = modifiers != null ? modifiers : InputEvent.NO_MODIFIERS;
		switch event {
			case Input(physical, key, _, location, state, repeat, _):
				var pressed = state == Pressed;
				var focused = Focus.of(tree);
				var e = focused == null ? null : new KeyEvent(focused.node, key, physical, location, repeat, mods);
				if (e != null)
					for (i in ancestors(tree, focused)) {
						i.fire(pressed ? "keydown" : "keyup", e);
						if (e.propagationStopped)
							break;
					}
				if (e != null && e.defaultPrevented)
					return;
				switch [key, pressed] {
					case [Named(Tab), true]:
						Focus.move(tree, e != null ? e.shift : shift(mods));
					case [Named(Enter), true] | [Named(Space), false]:
						click(tree, mods);
					case _:
				}
		}
	}

	/** `text` was typed or committed by an input method. **/
	public static function text(tree:LayoutTree, text:String, ?modifiers:Modifiers):Void {
		var focused = Focus.of(tree);
		if (focused == null || text == "")
			return;
		var e = new TextInputEvent(focused.node, text, modifiers != null ? modifiers : InputEvent.NO_MODIFIERS);
		for (i in ancestors(tree, focused)) {
			i.fire("textinput", e);
			if (e.propagationStopped)
				return;
		}
	}

	/** An input method's composition is now `text`, its caret at `cursor` (-1 for none); empty when it ends. **/
	public static function composition(tree:LayoutTree, text:String, cursor:Int):Void {
		var focused = Focus.of(tree);
		if (focused == null)
			return;
		var e = new CompositionEvent(focused.node, text, cursor);
		for (i in ancestors(tree, focused)) {
			i.fire("composition", e);
			if (e.propagationStopped)
				return;
		}
	}

	static function shift(m:Modifiers):Bool
		return switch m {
			case State(v, _, _, _, _, _, _, _, _, _, _, _): v;
		}

	/** Clicks the focused node, bubbling, as a press and release over it would. **/
	static function click(tree:LayoutTree, mods:Modifiers):Void {
		var focused = Focus.of(tree);
		if (focused == null || focused.disabled.get())
			return;
		var b = tree.getBounds(focused.node);
		var e = new PointerEvent(focused.node, b != null ? b.x : 0, b != null ? b.y : 0, Left, mods);
		for (i in ancestors(tree, focused)) {
			e.local(0, 0);
			i.fire("click", e);
			if (e.propagationStopped)
				return;
		}
	}

	/** `i` and the interactions of its ancestors, nearest first. **/
	static function ancestors(tree:LayoutTree, i:Interaction):Array<Interaction> {
		var out = [];
		for (id in tree.path(i.node)) {
			var a = Interaction.byId(tree, id);
			if (a != null)
				out.push(a);
		}
		return out.length == 0 ? [i] : out;
	}
}
