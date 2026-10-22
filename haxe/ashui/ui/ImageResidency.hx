package ashui.ui;

import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.types.Bitmap;

private typedef ImageUse = {
	final node:Node;
	final bitmap:Null<Bitmap>;
	final update:Bool->Void;
	var managed:Bool;
	var active:Bool;
}

/** Opt-in scroll image residency. Layout boxes survive while decoded pixels and atlas entries may be reclaimed. **/
class ImageResidency {
	static final containers = new haxe.ds.ObjectMap<LayoutTree, Map<String, Bool>>();
	static final uses:Array<ImageUse> = [];
	static var hooked = false;
	/** Renderer caches repack before their next draw when the resident set changes. **/
	public static var revision(default, null) = 0;

	static function key(id:haxe.Int64):String return haxe.Int64.toStr(id);

	static function hook():Void {
		if (hooked) return;
		hooked = true;
		ashui.css.Identity.forgetHooks.push(identity -> {
			var flags = containers.get(identity.tree);
			if (flags != null) {
				if (flags.remove(key(identity.node.id))) revision++;
				if (!flags.iterator().hasNext()) containers.remove(identity.tree);
			}
			for (use in uses.copy()) if (use.node == identity.node) remove(use);
		});
	}

	public static function configure(node:Node, enabled:Bool):Void {
		hook();
		var flags = containers.get(node.tree);
		if (flags == null) containers.set(node.tree, flags = []);
		if (flags.exists(key(node.id)) && flags.get(key(node.id)) == enabled) return;
		flags.set(key(node.id), enabled);
		revision++;
		node.tree.markDrawn();
	}

	@:noCompletion public static function register(node:Node, bitmap:Null<Bitmap>, update:Bool->Void):Void {
		hook();
		var use:ImageUse = {node:node, bitmap:bitmap, update:update, managed:false, active:true};
		uses.push(use);
		ashui.reactive.Owner.onCleanup(() -> remove(use));
	}

	static function remove(use:ImageUse):Void {
		if (uses.remove(use) && use.managed) {
			revision++;
			if (use.bitmap != null && !Lambda.exists(uses, other -> other.bitmap == use.bitmap && other.active)) use.bitmap.suspend();
		}
	}

	static function managed(use:ImageUse):Bool {
		var tree = use.node.tree, flags = containers.get(tree);
		if (flags == null) return false;
		for (id in tree.ancestors(use.node.id)) if (flags.exists(key(id))) {
			if (!flags.get(key(id))) return false;
			if (ashui.input.Scroll.at(id, tree) != null) return true;
		}
		return false;
	}

	/** Runs after layout and scrolling, before native slots are recorded for drawing. **/
	@:noCompletion public static function sync(tree:LayoutTree):Void {
		if (!containers.exists(tree) && !Lambda.exists(uses, use -> use.node.tree == tree && use.managed)) return;
		for (use in uses) if (use.node.tree == tree) {
			var owned = managed(use), active = !owned || tree.inView(use.node.id);
			if (owned != use.managed || active != use.active) revision++;
			use.managed = owned; use.active = active;
		}
		var wanted = new haxe.ds.ObjectMap<Bitmap, Bool>();
		for (use in uses) if (use.bitmap != null) wanted.set(use.bitmap, use.active || wanted.get(use.bitmap) == true);
		for (bitmap => active in wanted) if (!active) bitmap.suspend();
		for (use in uses) if (use.node.tree == tree) use.update(use.active);
	}
}
