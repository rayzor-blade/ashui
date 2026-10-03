package ashui.input;

import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;

/**
	Whether the pointer is over a node and whether it is pressing it, as two
	signals. Made for a node only when something reads them, such as a
	`hover:` or `active:` class; `Pointer` keeps them up to date. As with
	CSS's `:hover`, a node is hovered when the pointer is anywhere over it,
	also over its children.
**/
class Interaction {
	static final byNode = new haxe.ds.ObjectMap<Node, Interaction>();
	static final byTree = new haxe.ds.ObjectMap<LayoutTree, Array<Interaction>>();

	public final node:Node;
	public final hovered:Signal<Bool>;
	public final pressed:Signal<Bool>;

	function new(node:Node) {
		this.node = node;
		hovered = Signal.make(false);
		pressed = Signal.make(false);
	}

	/** `node`'s interaction, made the first time it is asked for. Not to be called inside a computed. **/
	public static function of(node:Node):Interaction {
		var interaction = byNode.get(node);
		if (interaction != null)
			return interaction;
		interaction = new Interaction(node);
		byNode.set(node, interaction);
		var tree = node.tree;
		if (tree != null) {
			var list = byTree.get(tree);
			if (list == null)
				byTree.set(tree, list = []);
			list.push(interaction);
		}
		Owner.onCleanup(() -> {
			byNode.remove(node);
			if (tree != null)
				byTree.get(tree).remove(interaction);
		});
		return interaction;
	}

	/** The interactions of `tree`'s nodes. **/
	public static function inTree(tree:LayoutTree):Array<Interaction> {
		var list = byTree.get(tree);
		return list != null ? list : [];
	}
}
