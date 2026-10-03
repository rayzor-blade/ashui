package ashui.input;

import ashui.layout.LayoutTree;

/**
	Feeds pointer movement and buttons, in the tree's logical pixels, to the
	`Interaction`s of a tree's nodes, using where each node was last laid
	out. A window's loop calls these from its events; tests call them
	directly.
**/
class Pointer {
	static final positions = new haxe.ds.ObjectMap<LayoutTree, {x:Float, y:Float}>();

	/** The pointer moved to `(x, y)`: each node under it is hovered, every other is not. **/
	public static function move(tree:LayoutTree, x:Float, y:Float):Void {
		positions.set(tree, {x: x, y: y});
		for (interaction in Interaction.inTree(tree)) {
			var over = contains(tree, interaction, x, y);
			if (interaction.hovered.get() != over)
				interaction.hovered.set(over);
			if (!over && interaction.pressed.get())
				interaction.pressed.set(false);
		}
	}

	/** The pointer left the window: nothing is hovered or pressed. **/
	public static function leave(tree:LayoutTree):Void {
		positions.remove(tree);
		for (interaction in Interaction.inTree(tree)) {
			if (interaction.hovered.get())
				interaction.hovered.set(false);
			if (interaction.pressed.get())
				interaction.pressed.set(false);
		}
	}

	/** The primary button went down where the pointer is: each hovered node is pressed. **/
	public static function press(tree:LayoutTree):Void {
		for (interaction in Interaction.inTree(tree))
			if (interaction.hovered.get() && !interaction.pressed.get())
				interaction.pressed.set(true);
	}

	/** The primary button came up: nothing is pressed. **/
	public static function release(tree:LayoutTree):Void {
		for (interaction in Interaction.inTree(tree))
			if (interaction.pressed.get())
				interaction.pressed.set(false);
	}

	/** Hit-tests again where the pointer is, for when layout moved things under it. **/
	public static function refresh(tree:LayoutTree):Void {
		var at = positions.get(tree);
		if (at != null)
			move(tree, at.x, at.y);
	}

	static function contains(tree:LayoutTree, interaction:Interaction, x:Float, y:Float):Bool {
		var b = tree.getBounds(interaction.node);
		return b != null && x >= b.x && y >= b.y && x < b.x + b.width && y < b.y + b.height;
	}
}
