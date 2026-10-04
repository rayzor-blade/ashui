package ashui.components;

import ashui.layout.LayoutTree;

/**
	Components by their nodes, so a part finds the component it is in from
	where it sits in the tree: a dialog's close button, wherever in the
	panel it is, a menu's item. A part's element knows nothing of the
	component around it until it is pressed; then it looks up its
	ancestors.
**/
class Registry<T> {
	final byNode = new haxe.ds.ObjectMap<LayoutTree, Map<String, T>>();

	public function new() {}

	/** Records `value` for the node `id` of `tree` until the current owner is cleaned up. **/
	public function add(tree:LayoutTree, id:haxe.Int64, value:T):Void {
		var map = byNode.get(tree);
		if (map == null)
			byNode.set(tree, map = new Map());
		var key = haxe.Int64.toStr(id);
		map.set(key, value);
		if (ashui.reactive.Owner.current != null)
			ashui.reactive.Owner.onCleanup(() -> map.remove(key));
	}

	/** What the node `id` is recorded under, or the nearest of its ancestors. **/
	public function near(tree:LayoutTree, id:haxe.Int64):Null<T> {
		var map = byNode.get(tree);
		if (map == null)
			return null;
		var own = map.get(haxe.Int64.toStr(id));
		if (own != null)
			return own;
		for (up in tree.ancestors(id)) {
			var found = map.get(haxe.Int64.toStr(up));
			if (found != null)
				return found;
		}
		return null;
	}
}
