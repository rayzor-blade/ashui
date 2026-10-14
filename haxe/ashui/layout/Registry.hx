package ashui.layout;

/** Components by their nodes, so a part can find the component containing it. **/
class Registry<T> {
	final byTree = new haxe.ds.ObjectMap<LayoutTree, Map<String, T>>();

	public function new() {}

	/** Keeps a value registered until the current owner is cleaned up. **/
	public function add(tree:LayoutTree, id:haxe.Int64, value:T):Void {
		var map = byTree.get(tree);
		if (map == null)
			byTree.set(tree, map = new Map());
		var key = haxe.Int64.toStr(id);
		map.set(key, value);
		if (ashui.reactive.Owner.current != null)
			ashui.reactive.Owner.onCleanup(() -> {
				if (map.get(key) == value)
					map.remove(key);
				if (!map.keys().hasNext() && byTree.get(tree) == map)
					byTree.remove(tree);
			});
	}

	/** The value at this node or its nearest registered ancestor. **/
	public function near(tree:LayoutTree, id:haxe.Int64):Null<T> {
		var map = byTree.get(tree);
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
