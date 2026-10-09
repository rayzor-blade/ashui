import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.LayoutTree.Hit;
import ashui.reactive.Owner;
import ashui.types.Style;
import ashui.ui.Div;

/** Quiet motion skips the native walk; observable input always sees fresh coordinates. */
class HitCache {
	static var failures = 0;
	static function check(name:String, ok:Bool) {
		Sys.println((ok ? "ok   " : "FAIL ") + name);
		if (!ok) failures++;
	}

	static function main() {
		var tree = new CountingTree();
		var child:Div = null;
		var enters = 0, leaves = 0;
		var downX = -1.0, downY = -1.0;
		var root:Div = Owner.root(tree, _ -> <div width={400} height={240}
			onPointerDown={e -> { downX = e.localX; downY = e.localY; }}>
			${child = <div position={Absolute} left={20} top={20} width={80} height={50}
				onPointerEnter={_ -> enters++} onPointerLeave={_ -> leaves++} />}
		</div>);
		function layout() {
			tree.flush();
			tree.computeLayout(root.node, 400, 240);
		}
		layout();
		Pointer.move(tree, 200, 170);
		var queries = tree.queries;
		var start = haxe.Timer.stamp();
		for (i in 0...100000) Pointer.move(tree, 200 + i % 40, 170 + i % 20);
		var elapsed = haxe.Timer.stamp() - start;
		check("100,000 empty-space moves reuse one hit region", tree.queries == queries && Pointer.quietRegion(tree) != null);
		var at = Pointer.at(tree);
		check("cached moves retain the latest position", at.x == 239 && at.y == 189);
		Pointer.press(tree);
		Pointer.release(tree);
		check("click coordinates are fresh after cached movement", downX == 239 && downY == 189);

		Pointer.move(tree, 30, 30);
		queries = tree.queries;
		Pointer.move(tree, 35, 35);
		check("enter fires once and motion inside a quiet target is cached", enters == 1 && leaves == 0 && tree.queries == queries);
		Pointer.press(tree);
		queries = tree.queries;
		Pointer.move(tree, 36, 36);
		check("pressed movement is never suppressed", tree.queries == queries + 1 && Pointer.quietRegion(tree) == null);
		Pointer.release(tree);
		Pointer.move(tree, 210, 180);
		check("crossing a target boundary leaves it", leaves == 1);
		tree.setVisual(child.node.id, 180, 140);
		check("visual movement invalidates a quiet region immediately", Pointer.quietRegion(tree) == null);
		Pointer.refresh(tree);
		check("a stationary pointer enters a target moved under it", enters == 2);
		tree.clearVisual(child.node.id);
		Pointer.refresh(tree);
		check("clearing visual movement retargets the stationary pointer", leaves == 2);
		Pointer.move(tree, 30, 30);
		tree.setPassThrough(child.node.id, true);
		check("pointer-events changes invalidate cached targets", Pointer.quietRegion(tree) == null);
		Pointer.refresh(tree);
		check("a pass-through target stops being hovered", !Interaction.of(child.node).hovered.get());
		tree.setPassThrough(child.node.id, false);
		Pointer.move(tree, 210, 180);

		var moves = 0;
		var hook:LayoutTree->Void = _ -> moves++;
		Pointer.hooks.push(hook);
		queries = tree.queries;
		Pointer.move(tree, 211, 180);
		Pointer.move(tree, 212, 180);
		check("pointer queries and hooks continue receiving every move", moves == 2 && tree.queries == queries + 2 && Pointer.quietRegion(tree) == null);
		Pointer.hooks.remove(hook);

		var woke = 0;
		ashui.core.Work.listen(() -> woke++);
		var added = new sys.thread.Lock();
		sys.thread.Thread.create(() -> {
			Interaction.of(root.node).onPointerMove(_ -> moves++);
			added.release();
		});
		check("adding a move handler from a worker wakes the host to clear its filter", added.wait(2) && woke == 1);
		ashui.core.Work.listen(null);
		queries = tree.queries;
		Pointer.move(tree, 213, 180);
		Pointer.move(tree, 214, 180);
		check("adding an ancestor move handler invalidates the cache and keeps bubbling", moves == 4 && tree.queries == queries + 2 && Pointer.quietRegion(tree) == null);

		Pointer.leave(tree);
		check("leaving the window disables native coalescing", Pointer.quietRegion(tree) == null);
		tree.dispose();

		var deepTree = new CountingTree();
		var deep = new Div({width: 100, height: 100}, deepTree);
		var deepest = deep;
		for (_ in 0...40) {
			var next = new Div({width: 100, height: 100}, deepTree);
			deepest.appendChild(next);
			deepest = next;
		}
		deepTree.flush();
		deepTree.computeLayout(deep.node, 100, 100);
		var hits = deepTree.hitTest(10, 10);
		check("retained hit storage grows for deep paths without truncating", hits.length == 41 && hits[0].id == deepest.node.id);
		Pointer.move(deepTree, 10, 10);
		queries = deepTree.queries;
		Pointer.move(deepTree, 11, 11);
		check("deep hit paths are cached too", deepTree.queries == queries && Pointer.quietRegion(deepTree) != null);
		deepTree.dispose();
		Pointer.refresh(deepTree);
		check("disposed trees cannot retain a quiet hit region", Pointer.quietRegion(deepTree) == null);
		Sys.println('quiet motion: 100000 moves in ${Math.round(elapsed * 1000000) / 1000} ms');
		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}

private class CountingTree extends LayoutTree {
	public var queries = 0;
	public function new() { super(); }
	override public function hitTest(x:Float, y:Float, ?region:hl.Bytes):Array<Hit> {
		queries++;
		return super.hitTest(x, y, region);
	}
}
