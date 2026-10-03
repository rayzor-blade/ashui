package ashui.input;

import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

private enum Kind {
	Group;
	Peer;
}

private typedef Pending = {
	final node:Node;
	final kind:Kind;
	final found:Signal<Null<Interaction>>;
}

/**
	Which element's state a `group-` or `peer-` class reads: the nearest
	ancestor marked `group`, or the nearest earlier sibling marked `peer`,
	as in Tailwind. Elements are built before they are placed, so the
	relation is found when the tree flushes: tentatively until the tree has
	a root, and for good once the element is under it.
**/
class Relations {
	static final pending = new haxe.ds.ObjectMap<LayoutTree, Array<Pending>>();
	static var hooked = false;

	/** The group `node` belongs to, null until it is found or when there is none. Not to be called inside a computed. **/
	public static function groupOf(node:Node):Signal<Null<Interaction>>
		return track(node, Group);

	/** The peer before `node`, null until it is found or when there is none. Not to be called inside a computed. **/
	public static function peerOf(node:Node):Signal<Null<Interaction>>
		return track(node, Peer);

	static function track(node:Node, kind:Kind):Signal<Null<Interaction>> {
		var found = Signal.make((null : Null<Interaction>));
		var tree = node.tree;
		if (tree == null)
			return found;
		if (!hooked) {
			hooked = true;
			LayoutTree.flushHooks.push(resolve);
		}
		var list = pending.get(tree);
		if (list == null)
			pending.set(tree, list = []);
		var entry:Pending = {node: node, kind: kind, found: found};
		list.push(entry);
		Owner.onCleanup(() -> {
			var l = pending.get(tree);
			if (l != null)
				l.remove(entry);
		});
		return found;
	}

	static function resolve(tree:LayoutTree):Void {
		var list = pending.get(tree);
		if (list == null || list.length == 0)
			return;
		for (entry in list.copy()) {
			var up = tree.ancestors(entry.node.id);
			if (up.length == 0)
				continue;
			var placed = tree.root != null && up[up.length - 1] == tree.root.id;
			var interaction = switch entry.kind {
				case Group: nearestGroup(tree, up);
				case Peer: nearestPeer(tree, entry.node.id, up[0]);
			}
			if (entry.found.get() != interaction)
				entry.found.set(interaction);
			if (placed)
				list.remove(entry);
		}
	}

	static function nearestGroup(tree:LayoutTree, up:Array<haxe.Int64>):Null<Interaction> {
		for (id in up) {
			var i = Interaction.byId(tree, id);
			if (i != null && i.isGroup)
				return i;
		}
		return null;
	}

	static function nearestPeer(tree:LayoutTree, node:haxe.Int64, parent:haxe.Int64):Null<Interaction> {
		var siblings = tree.children(parent);
		var at = siblings.indexOf(node);
		while (--at >= 0) {
			var i = Interaction.byId(tree, siblings[at]);
			if (i != null && i.isPeer)
				return i;
		}
		return null;
	}
}
