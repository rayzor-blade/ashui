package ashui.input;

import ashui.input.Events;
import ashui.layout.LayoutTree;

/**
	The node of each tree that keyboard input goes to. A focusable node gets
	focus when it is pressed or tabbed to; Tab and Shift+Tab move through the
	focusable nodes in document order, skipping disabled ones.
**/
class Focus {
	static final current = new haxe.ds.ObjectMap<LayoutTree, Interaction>();

	/** The focused node's interaction in `tree`, if any. **/
	public static function of(tree:LayoutTree):Null<Interaction>
		return current.get(tree);

	/** Focuses `target`; `visible` when the keyboard moved focus there. **/
	public static function set(target:Interaction, visible:Bool):Void {
		var tree = target.node.tree;
		if (tree == null || !target.focusable || target.disabled.get())
			return;
		var before = current.get(tree);
		if (before == target) {
			if (target.focusVisible.get() != visible)
				target.focusVisible.set(visible);
			return;
		}
		if (before != null)
			blur(before);
		current.set(tree, target);
		target.focused.set(true);
		target.focusVisible.set(visible);
		target.fire("focus", new FocusEvent(target.node, visible));
	}

	/** Takes focus from whatever in `tree` has it. **/
	public static function clear(tree:Null<LayoutTree>):Void {
		if (tree == null)
			return;
		var before = current.get(tree);
		if (before != null) {
			current.remove(tree);
			blur(before);
		}
	}

	/** Moves focus to the next focusable node after the focused one, or the previous with `backward`, wrapping. **/
	public static function move(tree:LayoutTree, backward = false):Void {
		var order = [];
		for (id in tree.order()) {
			var i = Interaction.byId(tree, id);
			if (i != null && i.focusable && !i.disabled.get())
				order.push(i);
		}
		if (order.length == 0)
			return;
		var at = order.indexOf(current.get(tree));
		var next = at < 0 ? (backward ? order.length - 1 : 0) : (at + (backward ? order.length - 1 : 1)) % order.length;
		set(order[next], true);
	}

	static function blur(i:Interaction):Void {
		i.focused.set(false);
		i.focusVisible.set(false);
		i.fire("blur", new FocusEvent(i.node, false));
	}

	@:allow(ashui.input.Interaction)
	static function forget(i:Interaction):Void {
		var tree = i.node.tree;
		if (tree != null && current.get(tree) == i)
			current.remove(tree);
	}
}
