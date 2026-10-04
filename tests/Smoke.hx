import ashui.svg.PathData.PathCommand;
import ashui.svg.SvgDocument.Paint;
import ashui.svg.SvgDocument.SvgNode;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.PropertyId;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Reactive;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.Style;
import ashui.ui.Component;
import ashui.ui.Div;
import ashui.ui.Text;
import ashui.ui.View;
import ashui.ui.Hxx.hxx;

/** End-to-end check of the Haxe bindings against blinc_abi.hdll. **/
class Smoke {
	static var failures = 0;

	static function check(what:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			failures++;
			Sys.println('FAIL $what' + (detail != null ? ': $detail' : ''));
		} else {
			Sys.println('ok   $what');
		}
	}

	static function near(a:Float, b:Float)
		return Math.abs(a - b) < 0.01;

	static function main() {
		var tree = new LayoutTree();

		// --- Constant layout ---
		var first = new Div({height: 50}, tree);
		var w = Signal.make((200 : Single));
		var second = new Div({width: w, height: w.computed(v -> (v / 4 : Single))}, tree);
		var label = new Text("Hello, world", tree);
		var root = new Div({
			width: 400,
			height: 300,
			padding: 10,
			gap: 5,
			flexDirection: Column,
			alignItems: Start
		}, [first, second, label], tree);

		check("flush reports relayout", tree.flush());
		tree.computeLayout(root.node, 800, 600);
		var r = tree.getBounds(root.node);
		check("root bounds", r != null && near(r.width, 400) && near(r.height, 300), r);
		var a = tree.getBounds(first.node);
		check("padding offsets first child", a != null && near(a.x, 10) && near(a.y, 10) && near(a.height, 50), a);

		// --- Signal and computed bindings ---
		var b = tree.getBounds(second.node);
		check("signal width applied", b != null && near(b.width, 200), b);
		check("computed height applied", b != null && near(b.height, 50), b);
		check("gap offsets second child", b != null && near(b.y, 65), b);
		// Gaps are layout units, constant or bound: not Blinc's `gap()` steps of 4.
		var gapTree = new LayoutTree();
		var gapSize = Signal.make((8 : Single));
		var gapFirst = new Div({height: 10}, gapTree), gapSecond = new Div({height: 10}, gapTree);
		var gapColumn = new Div({flexDirection: Column, gap: gapSize, width: 50}, [gapFirst, gapSecond], gapTree);
		gapTree.flush();
		gapTree.computeLayout(gapColumn.node, 100, 100);
		var boundAt = gapTree.getBounds(gapSecond.node).y;
		gapSize.set(12);
		gapTree.flush();
		gapTree.computeLayout(gapColumn.node, 100, 100);
		var movedTo = gapTree.getBounds(gapSecond.node).y;
		check("a gap bound to a signal is in layout units, before and after it changes", near(boundAt, 18) && near(movedTo, 22), [boundAt, movedTo]);

		w.set(120);
		check("signal change queues relayout", tree.flush());
		tree.computeLayout(root.node, 800, 600);
		b = tree.getBounds(second.node);
		check("signal change reaches layout", b != null && near(b.width, 120) && near(b.height, 30), b);

		// --- Text is passed as UTF-8, not truncated UTF-16 ---
		var t = tree.getBounds(label.node);
		var short = new Text("H", tree);
		root.appendChild(short);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var s = tree.getBounds(short.node);
		check("text measured from full content", t != null && s != null && t.width > s.width * 4, '$t vs $s');

		// --- Text bound to a computed string is measured again when it changes ---
		var clicks = Signal.make(1);
		var counter = new Text(clicks.computed(c -> 'Value: $c'), tree);
		root.appendChild(counter);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var before = tree.getBounds(counter.node);
		clicks.set(1000000);
		check("bound text change queues relayout", tree.flush());
		tree.computeLayout(root.node, 800, 600);
		var after = tree.getBounds(counter.node);
		check("bound text measured again", before != null && after != null && after.width > before.width * 1.3, '$before -> $after');

		// --- Dependency tracking across signals and types ---
		var count = Signal.make(3);
		var label2 = count.computed(c -> 'Value: $c');
		check("computed string", label2.get() == "Value: 3", label2.get());
		count.set(4);
		check("computed string follows its signal", label2.get() == "Value: 4", label2.get());

		var x = Signal.make(2);
		var y = Signal.make(5);
		var sum = Computed.make(() -> x.get() + y.get());
		check("computed of two signals", sum.get() == 7, sum.get());
		y.set(10);
		check("second dependency tracked", sum.get() == 12, sum.get());

		var flag = Signal.make(true);
		var neg = flag.computed(f -> !f);
		check("bool computed", neg.get() == false);
		flag.set(false);
		check("bool computed follows", neg.get() == true);

		var unicode = Signal.make("héllo ✓");
		check("string round trip", unicode.get() == "héllo ✓", unicode.get());

		var obj = Signal.make({n: 1});
		var n = obj.computed(o -> o.n * 10);
		check("dynamic signal", n.get() == 10, n.get());
		obj.set({n: 2});
		check("dynamic signal change tracked", n.get() == 20, n.get());

		// --- Value signals bind without error ---
		var bg = Signal.make(new Color(0xff0000));
		var styled = new Div({bg: Brush.solid(0x00ff00), borderColor: bg, cornerRadius: ashui.types.CornerRadius.all(4)}, tree);
		root.appendChild(styled);
		bg.set(new Color(0x0000ff, 0.5));
		check("value signal set", bg.get() != null);
		tree.flush();

		// --- A computed held only by a binding outlives its handle ---
		var level = Signal.make(2);
		var bar = new Div({width: 10, height: level.computed(v -> (v * 10 : Single))}, tree);
		root.appendChild(bar);
		tree.flush();
		hl.Gc.major();
		hl.Gc.major();
		tree.flush();
		level.set(5);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var barBounds = tree.getBounds(bar.node);
		check("bound computed survives collection", barBounds != null && near(barBounds.height, 50), barBounds);

		// --- An owner supplies the tree and cleans up what was built under it ---
		var log = [];
		var ownedLevel = Signal.make(3);
		var ownedBox:Div = null;
		var ownedLabel:Text = null;
		var disposeOwned = Owner.root(tree, dispose -> {
			Owner.onCleanup(() -> log.push("root"));
			ownedLabel = new Text("owned");
			ownedBox = new Div({width: 20, height: ownedLevel.computed(v -> (v * 10 : Single))}, [ownedLabel]);
			new Owner().run(() -> Owner.onCleanup(() -> log.push("child")));
			dispose;
		});
		root.appendChild(ownedBox);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var ownedBounds = tree.getBounds(ownedBox.node);
		check("element under an owner takes its tree", ownedBounds != null && near(ownedBounds.height, 30), ownedBounds);
		var ownedNode = ownedBox.node;
		var labelNode = ownedLabel.node;
		disposeOwned();
		check("an owner disposes its children, then its cleanups latest first", log.join(",") == "child,root", log);
		check("disposing an owner removes its elements", ownedBox.node == null && ownedLabel.node == null);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		check("removed nodes are gone from the tree", tree.getBounds(ownedNode) == null && tree.getBounds(labelNode) == null);
		ownedLevel.set(4);
		check("a released computed's signal can still be set", tree.flush() == false);

		// --- hxx lowers templates to elements and bindings ---
		var hxxCount = Signal.make(1);
		var hxxWidth = Signal.make((40 : Single));
		var view:Div = Owner.root(tree, _ -> hxx('
			<div width={hxxWidth} height={hxxCount.get() * 10} flexShrink={0} bg={Brush.solid(0x336699)} flexDirection={Column}>
				<div width={8} height={8} />
			</div>
		'));
		var hxxLabel:Text = Owner.root(tree, _ -> hxx('<text>Count: ${hxxCount}</text>'));
		var disposeBadge:Void->Void = null;
		var badge:Badge = Owner.root(tree, dispose -> {
			disposeBadge = dispose;
			hxx('<badge label={"n=" + hxxCount.get()} />');
		});
		root.appendChild(view);
		root.appendChild(hxxLabel);
		root.appendChild(badge);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var v = tree.getBounds(view.node);
		var labelBefore = tree.getBounds(hxxLabel.node);
		check("hxx binds a signal attribute", v != null && near(v.width, 40), v);
		check("hxx makes a .get() attribute a computed", v != null && near(v.height, 10), v);
		hxxCount.set(12345);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		v = tree.getBounds(view.node);
		var labelAfter = tree.getBounds(hxxLabel.node);
		check("hxx computed attribute follows its signal", v != null && near(v.height, 123450), v);
		check("hxx interpolated text follows its signal", labelBefore != null && labelAfter != null && labelAfter.width > labelBefore.width,
			'$labelBefore -> $labelAfter');
		var b = tree.getBounds(badge.node);
		check("hxx builds a component tag", b != null && near(b.width, 50), b);

		disposeBadge();
		check("removing a component disposes what it rendered", badge.node == null);

		// --- <if> swaps branches at the next flush ---
		var visible = Signal.make(true);
		var shown:Div = Owner.root(tree, _ -> hxx('
			<div flexShrink={0}>
				<if {visible}>
					<div width={30} height={30} />
				<else>
					<div width={10} height={10} />
				</if>
			</div>
		'));
		root.appendChild(shown);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var shownBefore = tree.getBounds(shown.node);
		visible.set(false);
		check("a changed condition queues a relayout", tree.flush());
		tree.computeLayout(root.node, 800, 600);
		var shownAfter = tree.getBounds(shown.node);
		check("<if> shows the branch for its condition", shownBefore != null && near(shownBefore.width, 30) && shownAfter != null
			&& near(shownAfter.width, 10), '$shownBefore -> $shownAfter');

		// --- <for> keeps the element of an item still in the list ---
		var numbers = Signal.make([1, 2, 3]);
		var built = 0;
		function cell(n:Int):Element {
			built++;
			return new Div({width: n * 10, height: 5});
		}
		var listed:Div = Owner.root(tree, _ -> hxx('
			<div flexShrink={0}>
				<for {n in numbers}>{cell(n)}</for>
			</div>
		'));
		root.appendChild(listed);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var l = tree.getBounds(listed.node);
		check("<for> builds one item per value", l != null && near(l.width, 60) && built == 3, '$l built=$built');
		numbers.set([3, 1]);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		l = tree.getBounds(listed.node);
		check("<for> drops removed items and reuses kept ones", l != null && near(l.width, 40) && built == 3, '$l built=$built');
		numbers.set([3, 1, 4]);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		l = tree.getBounds(listed.node);
		check("<for> builds only new items", l != null && near(l.width, 80) && built == 4, '$l built=$built');

		// --- <for> and <if> lay their items out in the element they are in ---
		var rows = Signal.make([1, 2, 3]);
		var outer = Signal.make([1, 2]);
		var showExtra = Signal.make(true);
		var header:Div = null, footer:Div = null;
		var column:Div = Owner.root(tree, _ -> hxx('
			<div class="flex flex-col" gap={4} width={100} flexShrink={0}>
				${header = new Div({width: 100, height: 10})}
				<for {n in rows}><div width={20} height={10} /></for>
				<if {showExtra}><div width={30} height={6} /></if>
				<for {o in outer}><for {n in [o * 10, o * 10 + 1]}><div width={5} height={2} /></for></for>
				${footer = new Div({width: 100, height: 10})}
			</div>
		'));
		root.appendChild(column);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		function columnHeight()
			return tree.getBounds(column.node).height;
		function footerTop()
			return tree.getBounds(footer.node).y - tree.getBounds(column.node).y;
		// header 10, three rows of 10, the extra 6, four nested rows of 2, footer 10, and 9 gaps of 4.
		check("<for> and <if> items are the column's own children: stacked, with its gap", near(columnHeight(), 10 + 30 + 6 + 8 + 10 + 9 * 4)
			&& near(footerTop(), 10 + 30 + 6 + 8 + 9 * 4), [columnHeight(), footerTop()]);
		rows.set([1]);
		showExtra.set(false);
		outer.set([2]);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		check("removed items leave the column, in place", near(columnHeight(), 10 + 10 + 4 + 10 + 4 * 4) && near(footerTop(), 10 + 10 + 4 + 4 * 4),
			[columnHeight(), footerTop()]);
		rows.set([1, 2]);
		showExtra.set(true);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var order = [for (id in tree.order()) id];
		var headerAt = order.indexOf(header.node.id), footerAt = order.indexOf(footer.node.id);
		check("added items take their place between their siblings", near(columnHeight(), 10 + 20 + 6 + 4 + 10 + 6 * 4) && headerAt >= 0
			&& footerAt == headerAt + 6, [columnHeight(), headerAt, footerAt]);

		// --- A watch reacts only to what it read ---
		var flagA = Signal.make(true);
		var flagB = Signal.make(true);
		var builtA = 0, builtB = 0;
		var pair:Div = Owner.root(tree, _ -> hxx('
			<div flexShrink={0}>
				<if {flagA}>{(() -> { builtA++; new Div({width: 5, height: 5}); })()}</if>
				<if {flagB}>{(() -> { builtB++; new Div({width: 5, height: 5}); })()}</if>
			</div>
		'));
		root.appendChild(pair);
		tree.flush();
		flagA.set(false);
		tree.flush();
		flagA.set(true);
		tree.flush();
		check("a watch reacts only to what it read", builtA == 2 && builtB == 1, 'A built $builtA, B built $builtB');
		check("a flush with nothing changed reacts to nothing", tree.flush() == false);
		var readsB = 0;
		var watchedB = Owner.root(tree, _ -> new ashui.ui.Show(() -> {
			readsB++;
			flagB.get();
		}, () -> new Div({width: 5, height: 5})));
		root.appendChild(watchedB);
		for (_ in 0...3) {
			flagA.set(!flagA.get());
			tree.flush();
		}
		check("a watch's read runs only when what it read changes", readsB == 1, 'read $readsB times');

		// --- An <if> on a computed follows the signals under it ---
		var size = Signal.make(5);
		var big = size.computed(v -> v > 10);
		var sized:Div = Owner.root(tree, _ -> hxx('
			<div flexShrink={0}>
				<if {big}><div width={40} height={4} /><else><div width={4} height={4} /></if>
			</div>
		'));
		root.appendChild(sized);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var small = tree.getBounds(sized.node);
		size.set(20);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var large = tree.getBounds(sized.node);
		check("an <if> on a computed follows its signals", small != null && near(small.width, 4) && large != null && near(large.width, 40),
			'$small -> $large');

		// --- @:state is read in templates without .get(), and followed ---
		var counter:CounterView = Owner.root(tree, _ -> hxx('<counter-view />'));
		root.appendChild(counter);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var counted = tree.getBounds(counter.node);
		counter.increment();
		counter.increment();
		check("a @:state field reads and writes its signal", counter.count == 3, counter.count);
		check("changing @:state queues a relayout", tree.flush());
		tree.computeLayout(root.node, 800, 600);
		var recounted = tree.getBounds(counter.node);
		check("a template attribute reading @:state follows it", counted != null && near(counted.width, 10) && recounted != null
			&& near(recounted.width, 30), '$counted -> $recounted');

		// --- Rendering again keeps the @:state of the components it builds ---
		var shelf:Shelf = Owner.root(tree, _ -> hxx('<shelf />'));
		var first = shelf.counters;
		first[0].count = 4;
		first[1].count = 7;
		shelf.inner.counters[0].count = 9;
		shelf.rerender();
		var again = shelf.counters;
		check("a rerender builds its components afresh", again[0] != first[0] && again[1] != first[1]);
		check("each takes over the state of the one of its class in its place", again[0].count == 4 && again[1].count == 7,
			'${again[0].count} ${again[1].count}');
		check("and so do the components they build", shelf.inner.counters[0].count == 9 && shelf.inner.counters[1].count == 1,
			'${shelf.inner.counters[0].count} ${shelf.inner.counters[1].count}');
		again[1].count = 8;
		check("the state taken over is still followed", tree.flush() && first[1].count == 8);
		shelf.remove();

		// --- So does a component a <for> builds after its first render ---
		var rack:Rack = Owner.root(tree, _ -> hxx('<rack />'));
		rack.names.set(["a", "b"]);
		tree.flush();
		var later = rack.made[1];
		@:privateAccess {
			check("a component a <for> builds later is its component's, not a root",
				later.builder == rack && !Component.roots.contains(later) && rack.built.length == 2);
		}
		rack.made[0].count = 3;
		later.count = 6;
		rack.made.resize(0);
		rack.rerender();
		check("it keeps its state when its component renders again", rack.made.length == 2 && rack.made[0].count == 3 && rack.made[1].count == 6,
			[for (c in rack.made) c.count]);
		rack.names.set(["a"]);
		tree.flush();
		@:privateAccess {
			check("a component its <for> drops leaves the books", rack.built.length == 1 && rack.made[1].node == null && !Component.hosts.exists(rack.made[1].owner));
		}
		rack.remove();
		@:privateAccess check("a removed component leaves the roots", !Component.roots.contains(rack) && rack.built.length == 0);

		// --- A Float signal or computed binds to a Single property ---
		var floatWidth = Signal.make(100.0);
		var floaty = new Div({width: floatWidth, height: floatWidth.computed(v -> v / 10), flexShrink: 0}, tree);
		root.appendChild(floaty);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var f1 = tree.getBounds(floaty.node);
		// Taffy rounds layout to whole pixels.
		floatWidth.set(160.0);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var f2 = tree.getBounds(floaty.node);
		check("a Float signal binds to a Single property", f1 != null && near(f1.width, 100) && f2 != null && near(f2.width, 160), '$f1 -> $f2');
		check("a Float computed binds to a Single property", f1 != null && near(f1.height, 10) && f2 != null && near(f2.height, 16), '$f1 -> $f2');

		// --- A null String survives a signal and a computed ---
		var maybe = Signal.make((null : String));
		check("a null String signal reads back null", maybe.get() == null);
		maybe.set("x");
		check("a String signal reads back what was set", maybe.get() == "x");
		maybe.set(null);
		var echoed = maybe.computed(s -> s);
		check("a null String computed reads back null", maybe.get() == null && echoed.get() == null);

		// --- dispose frees a tree now, and the tree is inert afterwards ---
		var spare = new LayoutTree();
		var spareLevel = Signal.make(3);
		var spareBox = new Div({width: 10, height: spareLevel.computed(v -> (v : Single))}, spare);
		spare.flush();
		spare.computeLayout(spareBox.node, 100, 100);
		check("a tree lays out before dispose", spare.getBounds(spareBox.node) != null);
		spare.dispose();
		spareLevel.set(4);
		check("a disposed tree has nothing to flush", spare.flush() == false);
		check("a disposed tree has no bounds", spare.getBounds(spareBox.node) == null);
		check("the live tree still flushes after another is disposed", tree.flush() == false);

		// --- Text is measured with real fonts, not estimated ---
		var narrow = new Text("iiiiii", {fontSize: 32, wrap: false}, tree);
		var wide = new Text("WWWWWW", {fontSize: 32, wrap: false}, tree);
		root.appendChild(narrow);
		root.appendChild(wide);
		tree.flush();
		tree.computeLayout(root.node, 800, 600);
		var n = tree.getBounds(narrow.node);
		var w = tree.getBounds(wide.node);
		check("text is measured with real fonts", n != null && w != null && w.width > n.width * 2, '"iiiiii" $n vs "WWWWWW" $w');

		// --- The laid-out tree packs into a display list ---
		var paintTree = new LayoutTree();
		var shadowed = new Div({
			width: 10, height: 10, opacity: 0.5, bg: Brush.solid(0xff0000),
			borderColor: new Color(0x00ff00), borderWidth: 2
		}, paintTree);
		shadowed.node.set(ashui.layout.Prop.Shadow, new ashui.types.Shadow(1, 2, 3, 0x000000));
		var painted = new Div({width: 40, height: 30, padding: 5, overflow: ashui.types.Style.Overflow.Clip, bg: Brush.solid(0x000000)}, [shadowed], paintTree);
		paintTree.flush();
		paintTree.computeLayout(painted.node, 100, 100);
		var list = new ashui.layout.DisplayList();
		list.update(paintTree, painted.node);
		var R = 2; // the shadowed box's record
		check("a display list paints a box, then a child's shadow, then the child",
			list.count == 3 && list.kind(0) == 0 && list.kind(1) == 3 && list.kind(2) == 0, [for (r in 0...list.count) list.kind(r)]);
		check("records are at absolute positions",
			list.get(R, 0) == 5 && list.get(R, 1) == 5 && list.get(R, 2) == 10 && list.get(R, 3) == 10,
			[for (f in 0...4) list.get(R, f)]);
		check("a record carries fill and border, with opacity in their alpha",
			list.get(R, 8) == 1 && list.get(R, 9) == 0 && list.get(R, 11) == 0.5 && list.get(R, 16) == 2 && list.get(R, 19) == 2
			&& list.get(R, 21) == 1 && list.get(R, 23) == 0.5,
			[for (f in 8...24) list.get(R, f)]);
		check("a shadow record carries offset, blur and colour",
			list.get(1, 24) == 1 && list.get(1, 25) == 2 && list.get(1, 26) == 3 && list.get(1, 31) == 0.5,
			[for (f in 24...32) list.get(1, f)]);
		check("children of a clipping box are clipped to it, the box itself is not",
			list.get(R, 46) == 1 && list.get(R, 32) == 0 && list.get(R, 33) == 0 && list.get(R, 34) == 40 && list.get(R, 35) == 30
			&& list.get(0, 46) == 0,
			[for (f in 32...36) list.get(R, f)]);

		var bare = new Div({width: 8, height: 8, overflow: ashui.types.Style.Overflow.Clip}, [
			new Div({width: 20, height: 20, bg: Brush.solid(0xff0000)}, paintTree)
		], paintTree);
		paintTree.flush();
		paintTree.computeLayout(bare.node, 100, 100);
		list.update(paintTree, bare.node);
		check("a clipping box with nothing to draw still clips its children",
			list.count == 1 && list.get(0, 46) == 1 && list.get(0, 34) == 8, [list.count, list.get(0, 46), list.get(0, 34)]);

		// --- Theme tokens, as Blinc's blinc_theme has them ---
		var hybridLight = ashui.theme.themes.HybridTheme.light();
		check("a theme reads its tokens",
			hybridLight.colors.get(Primary).rgb() == 0x2A63E9 && Math.abs(hybridLight.colors.get(SuccessBg).a - 0.12) < 1e-6
			&& hybridLight.spacing.get(Space4) == 16 && hybridLight.radii.get(Xl) == 18 && hybridLight.shadows.get(Md).length == 2
			&& hybridLight.typography.get(TextSm) == 13 && hybridLight.animations.get(DurationNormal) == 240);
		check("the default colours are the default theme's", ashui.theme.ColorTokens.defaults().get(Primary).rgb() == 0x2A63E9);
		var off = ashui.theme.ShapeTokens.OFF;
		var hybridN = ashui.theme.themes.HybridTheme.shape().effectiveCornerN();
		check("shape tokens give the squircle n Blinc does",
			off.isOff() && off.effectiveCornerN() == 1 && Math.abs(hybridN - Math.log(2.52) / Math.log(2)) < 0.001
			&& ashui.theme.themes.RestrainedTheme.shape().effectiveCornerN() > hybridN
			&& hybridN > ashui.theme.themes.ExpressiveTheme.shape().effectiveCornerN()
			&& ashui.theme.themes.ExpressiveTheme.shape().effectiveCornerN() > 1, hybridN);
		var cssEase = ashui.theme.Easing.EasingTools.evaluate(CubicBezier(0.25, 0.1, 0.25, 1), 0.5);
		var easeIn = ashui.theme.Easing.EasingTools.evaluate(EaseIn, 0.5);
		var springPeak = 0.0;
		for (i in 0...101)
			springPeak = Math.max(springPeak, ashui.theme.Easing.EasingTools.evaluate(CubicBezier(0.34, 1.56, 0.64, 1), i / 100));
		check("easings evaluate as CSS does, spring curves overshooting",
			Math.abs(easeIn - 0.3248146106) < 1e-6 && ashui.theme.Easing.EasingTools.evaluate(Linear, 2) == 1
			&& Math.abs(cssEase - 0.8024033877) < 1e-6 && springPeak > 1.05, [easeIn, cssEase, springPeak]);

		// --- Corners take the theme's squircle as Blinc's paint walk resolves them ---
		var smooth = ashui.theme.themes.HybridTheme.shape();
		var n:Float = (smooth.effectiveCornerN() : Single);
		var cornerTree = new LayoutTree();
		var cornerList = new ashui.layout.DisplayList();
		// A box drawn by the walk under the given smoothing; its record's corner shapes.
		function shapeOf(radii:Array<Float>, w:Float, h:Float, ?explicit:Array<Float>, locked = false, ?theme) {
			var e = explicit != null ? explicit : [1.0, 1, 1, 1];
			var box = new Div({width: w, height: h, bg: Brush.solid(0xffffff),
				cornerRadius: new ashui.types.CornerRadius(radii[0], radii[1], radii[2], radii[3]),
				cornerShape: new ashui.types.CornerShape(e[0], e[1], e[2], e[3], locked)}, cornerTree);
			cornerTree.flush();
			cornerTree.computeLayout(box.node, w, h);
			cornerList.shapes = {tokens: theme != null ? theme : smooth, radiusFull: 9999};
			cornerList.update(cornerTree, box.node);
			return [for (c in 0...4) (cornerList.get(0, ashui.layout.DisplayList.CORNER_SHAPE_FIELD + c) : Float)].join(",");
		}
		var round = "1,1,1,1";
		check("an explicit corner shape wins over the theme", shapeOf([20, 20, 20, 20], 100, 100, [0, 0, 0, 0]) == "0,0,0,0");
		check("a theme with smoothing off keeps corners round", shapeOf([20, 20, 20, 20], 100, 100, null, false, off) == round);
		check("a full radius stays round", shapeOf([9999, 9999, 9999, 9999], 300, 300) == round);
		check("a locked shape stays round", shapeOf([20, 20, 20, 20], 100, 100, null, true) == round);
		check("a circle and a pill stay round", shapeOf([16, 16, 16, 16], 32, 32) == round && shapeOf([20, 20, 20, 20], 200, 40) == round);
		check("small corners stay round, large ones are smoothed", shapeOf([15, 15, 15, 4], 40, 40) == [n, n, n, 1].join(","),
			shapeOf([15, 15, 15, 4], 40, 40));
		check("a corner near a full circle stays round", shapeOf([19, 19, 19, 4], 40, 40) == round);
		check("each corner is resolved on its own", shapeOf([8, 16, 16, 8], 200, 100) == [1, n, n, 1].join(","));
		check("a smoothed corner is between a circle and a squircle", Std.parseFloat(shapeOf([20, 20, 20, 20], 200, 100)) > 1 && n < 2);

		// --- ThemeState: overrides, CSS variables, schemes ---
		ashui.theme.ThemeState.init(ashui.theme.themes.HybridTheme.bundle(), Light);
		var themeState = ashui.theme.ThemeState.get();
		var vars = themeState.toCssVariableMap();
		check("the CSS variable map writes values as Blinc does",
			[for (k in vars.keys()) k].length == 125 && vars.get("radius-xl") == "18px" && vars.get("shadow-md") != "none" && vars.get("text-sm") == "13px"
			&& vars.get("primary") == "#2a63e9" && vars.get("border") == "rgba(15,20,34,0.1)" && vars.get("focus-ring") == "rgba(42,99,233,0.35)"
			&& vars.get("font-sans").indexOf('"Noto Sans"') == 0 && vars.get("ease-default") == "cubic-bezier(0.25, 0.1, 0.25, 1)"
			&& vars.get("leading-tight") == "1.25" && vars.get("tracking-tight") == "-0.025em" && vars.get("duration-fast") == "180ms",
			[for (k in ["border", "focus-ring", "ease-default", "leading-tight", "tracking-tight", "font-sans"]) vars.get(k)]);
		themeState.setColorOverride(Primary, ashui.theme.Rgba.fromHex(0x112233));
		themeState.setRadiusOverride(Lg, 3);
		check("an override wins over the theme, but not in the token sets",
			themeState.color(Primary).rgb() == 0x112233 && themeState.colors().get(Primary).rgb() == 0x2A63E9 && themeState.radius(Lg) == 3
			&& themeState.radii().get(Lg) == 14 && themeState.toCssVariableMap().get("primary") == "#112233");
		themeState.clearOverrides();
		themeState.setScheme(Dark);
		check("without a scheduler a scheme switch is instant", themeState.color(Surface).rgb() == 0x1A1F2E && !themeState.isAnimating());
		var scheduler = new ashui.animation.AnimationScheduler();
		themeState.setScheduler(scheduler);
		themeState.setScheme(Light);
		var before = themeState.color(Surface).rgb();
		scheduler.tick(0.1);
		themeState.tick();
		var during = themeState.color(Surface);
		for (_ in 0...200) {
			scheduler.tick(1 / 60);
			themeState.tick();
		}
		check("with a scheduler the colours spring to the new scheme",
			before == 0x1A1F2E && during.r > 0x1A / 255 && during.r < 1 && themeState.color(Surface).rgb() == 0xFFFFFF && !themeState.isAnimating(),
			[before, during.rgb(), themeState.color(Surface).rgb()]);

		var themeTree = new LayoutTree();
		var themed = Owner.root(themeTree, _ -> new Div({width: 100, height: 60, bg: ashui.theme.Themed.brush(Surface), cornerRadius: ashui.types.CornerRadius.all(14)}));
		themeTree.flush();
		themeTree.computeLayout(themed.node, 100, 60);
		var themeList = new ashui.layout.DisplayList();
		themeList.update(themeTree, themed.node);
		var lightFill = themeList.get(0, 8);
		var squircle = themeList.get(0, ashui.layout.DisplayList.CORNER_SHAPE_FIELD);
		themeState.setScheduler(null);
		themeState.setScheme(Dark);
		themeTree.flush();
		themeList.update(themeTree, themed.node);
		var darkFill = themeList.get(0, 8);
		themeState.setScheme(Light);
		check("a prop bound to a colour token follows the scheme", lightFill == 1 && Math.abs(darkFill - 0x1A / 255) < 0.01, [lightFill, darkFill]);
		check("a box gets the theme's squircle in its record", Math.abs(squircle - n) < 1e-6, squircle);

		// --- Shadows stack layers, each with its spread ---
		var stackTree = new LayoutTree();
		var stacked = new Div({width: 10, height: 10, bg: Brush.solid(0xffffff)}, stackTree);
		stacked.node.set(ashui.layout.Prop.Shadow, new ashui.types.Shadow(0, 1, 2, 0x000000, 0.5).and(0, 8, 16, 0x000000, 0.25, 3));
		stackTree.flush();
		stackTree.computeLayout(stacked.node, 10, 10);
		var stackList = new ashui.layout.DisplayList();
		stackList.update(stackTree, stacked.node);
		check("a shadow of two layers draws both, the last first, with its spread",
			stackList.count == 3 && stackList.kind(0) == 3 && stackList.kind(1) == 3 && stackList.kind(2) == 0 && stackList.get(0, 25) == 8
			&& stackList.get(0, 27) == 3 && stackList.get(1, 25) == 1 && stackList.get(1, 27) == 0,
			[for (r in 0...stackList.count) [stackList.kind(r), stackList.get(r, 25), stackList.get(r, 27)]]);
		var themedShadow = Owner.root(stackTree, _ -> new Div({width: 10, height: 10, bg: Brush.solid(0xffffff)}));
		themedShadow.node.set(ashui.layout.Prop.Shadow, ashui.theme.Themed.shadow(Md));
		stackTree.flush();
		stackTree.computeLayout(themedShadow.node, 10, 10);
		stackList.update(stackTree, themedShadow.node);
		check("a theme shadow binds its whole stack", stackList.count == 3, stackList.count);

		// --- An explicit corner shape reaches the record and wins over the theme ---
		var shapeTree = new LayoutTree();
		var beveled = Owner.root(shapeTree, _ -> new Div({width: 100, height: 60, bg: Brush.solid(0xffffff),
			cornerRadius: ashui.types.CornerRadius.all(14), cornerShape: ashui.types.CornerShape.bevel()}));
		var lockedRound = Owner.root(shapeTree, _ -> new Div({width: 100, height: 60, bg: Brush.solid(0xffffff),
			cornerRadius: ashui.types.CornerRadius.all(14), cornerShape: ashui.types.CornerShape.round().lock()}));
		shapeTree.flush();
		shapeTree.computeLayout(beveled.node, 100, 60);
		shapeTree.computeLayout(lockedRound.node, 100, 60);
		var shapeList = new ashui.layout.DisplayList();
		shapeList.update(shapeTree, beveled.node);
		var beveledN = shapeList.get(0, ashui.layout.DisplayList.CORNER_SHAPE_FIELD);
		var beveledRadius = shapeList.get(0, 4);
		shapeList.update(shapeTree, lockedRound.node);
		check("an explicit corner shape wins over the theme's squircle, and keeps the radius",
			beveledN == 0 && beveledRadius == 14 && shapeList.get(0, ashui.layout.DisplayList.CORNER_SHAPE_FIELD) == 1,
			[beveledN, beveledRadius, shapeList.get(0, ashui.layout.DisplayList.CORNER_SHAPE_FIELD)]);

		// --- Utility classes resolve to theme tokens at compile time ---
		ashui.theme.ThemeState.init(ashui.theme.themes.HybridTheme.bundle(), Light);
		var twTree = new LayoutTree();
		var card = ashui.style.Tw.tw("flex flex-col p-4 gap-2 bg-surface border border-border rounded-lg shadow-md");
		var twBox:Div = Owner.root(twTree, _ -> hxx('
			<div class="w-32 h-16 bg-primary rounded-xl corner-bevel opacity-50" width={100} />
		'));
		var styled = Owner.root(twTree, _ -> new Div({style: card, width: 40, height: 30}));
		twTree.flush();
		twTree.computeLayout(twBox.node, 200, 200);
		twTree.computeLayout(styled.node, 200, 200);
		var twList = new ashui.layout.DisplayList();
		twList.update(twTree, twBox.node);
		check("a class sets its token's value, and an attribute wins over a class",
			twList.get(0, 2) == 100 && twList.get(0, 3) == 64 && twList.get(0, 4) == 18 && Math.abs(twList.get(0, 8) - 0x2A / 255) < 0.01
			&& twList.get(0, 11) == 0.5 && twList.get(0, ashui.layout.DisplayList.CORNER_SHAPE_FIELD) == 0,
			[for (f in [2, 3, 4, 8, 11, ashui.layout.DisplayList.CORNER_SHAPE_FIELD]) twList.get(0, f)]);
		var fadedWhite:Div = Owner.root(twTree, _ -> hxx('<div class="w-10 h-10 bg-white/40" />'));
		var halfPrimary:Div = Owner.root(twTree, _ -> hxx('<div class="w-10 h-10 bg-primary/50" />'));
		var fullPrimary:Div = Owner.root(twTree, _ -> hxx('<div class="w-10 h-10 bg-primary" />'));
		twTree.flush();
		var fills = [];
		for (box in [fadedWhite, halfPrimary, fullPrimary]) {
			twTree.computeLayout(box.node, 200, 200);
			twList.update(twTree, box.node);
			fills.push([for (f in 8...12) twList.get(0, f)]);
		}
		check("bg-white/40 is white at 0.4", fills[0][0] == 1 && fills[0][1] == 1 && fills[0][2] == 1 && Math.abs(fills[0][3] - 0.4) < 0.001,
			fills[0]);
		check("bg-primary/50 is the theme's primary at half its alpha",
			fills[1][0] == fills[2][0] && fills[1][2] == fills[2][2] && Math.abs(fills[1][3] - fills[2][3] * 0.5) < 0.001, fills);
		twList.update(twTree, styled.node);
		check("a style from classes applies to a div",
			twList.count == 3 && twList.get(2, 4) == 14 && twList.get(2, 16) == 1 && twList.get(2, 8) == 1,
			[twList.count, twList.get(2, 4), twList.get(2, 16), twList.get(2, 8)]);
		var graded = Owner.root(twTree, _ -> new Div({width: 100, height: 20,
			style: ashui.style.Tw.tw("bg-linear-to-r from-primary via-accent via-30% to-info")}));
		var faded = Owner.root(twTree, _ -> new Div({width: 100, height: 20, style: ashui.style.Tw.tw("bg-radial from-primary")}));
		twTree.flush();
		twTree.computeLayout(graded.node, 200, 200);
		twTree.computeLayout(faded.node, 200, 200);
		twList.update(twTree, graded.node);
		var stops = [for (f in 52...60) twList.get(0, f)];
		check("gradient classes compose into one fill with its stops",
			twList.get(0, 45) == 1 && twList.get(0, 40) == 0 && twList.get(0, 41) == 10 && twList.get(0, 42) == 100 && twList.get(0, 43) == 10
			&& Math.abs(twList.get(0, 8) - 0x2A / 255) < 0.01 && Math.abs(twList.get(0, 14) - 0xC7 / 255) < 0.01
			&& Math.abs(stops[0] - 0x2A / 255) < 0.01 && Math.abs(stops[5] - 0.3) < 1e-6 && stops[6] == 1 && stops[7] == 1,
			[for (f in [45, 40, 41, 42, 43, 8, 14]) twList.get(0, f)].concat(stops));
		twList.update(twTree, faded.node);
		check("a lone from- stop fades to its colour made transparent",
			twList.get(0, 45) == 2 && twList.get(0, 11) == 1 && twList.get(0, 15) == 0 && Math.abs(twList.get(0, 12) - 0x2A / 255) < 0.01,
			[for (f in [45, 11, 12, 15]) twList.get(0, f)]);
		ashui.theme.ThemeState.get().setScheme(Dark);
		twTree.flush();
		twList.update(twTree, styled.node);
		check("a class follows the theme's scheme", Math.abs(twList.get(2, 8) - 0x1A / 255) < 0.01, twList.get(2, 8));
		ashui.theme.ThemeState.get().setScheme(Light);

		// --- Per-side spacing, auto margins and fractions of the parent ---
		var sideTree = new LayoutTree();
		var centred:Div = null, half:Div = null, cells:Array<ashui.layout.Element> = [];
		var padded = Owner.root(sideTree, _ -> {
			centred = new Div({style: ashui.style.Tw.tw("w-8 h-2 mx-auto shrink-0")});
			half = new Div({style: ashui.style.Tw.tw("w-1/2 h-full shrink")});
			new Div({style: ashui.style.Tw.tw("pt-1 px-4 flex flex-col"), width: 100, height: 100}, [centred, half]);
		});
		var wrapped = Owner.root(sideTree, _ -> {
			cells = [for (_ in 0...3) new Div({style: ashui.style.Tw.tw("w-5 h-5 shrink-0")})];
			new Div({style: ashui.style.Tw.tw("flex flex-row flex-wrap gap-x-2 gap-y-4"), width: 50, height: 56}, cells);
		});
		sideTree.flush();
		sideTree.computeLayout(padded.node, 100, 100);
		sideTree.computeLayout(wrapped.node, 50, 56);
		var c = sideTree.getBounds(centred.node), h = sideTree.getBounds(half.node);
		check("one-side padding, auto margins and fractions lay out as Tailwind's",
			c.x == 34 && c.y == 4 && h.x == 16 && h.width == 34 && h.y == 12, [c.x, c.y, h.x, h.width, h.y]);
		var second = sideTree.getBounds(cells[1].node), third = sideTree.getBounds(cells[2].node);
		check("gap-x spaces columns and gap-y rows", second.x == 28 && third.x == 0 && third.y == 36, [second.x, third.x, third.y]);

		// --- Classes on text: sizes, and letter spacing in ems of that size ---
		var textTree = new LayoutTree();
		var small:Text = Owner.root(textTree, _ -> hxx('<text class="text-xs">Spacing</text>'));
		var large:Text = Owner.root(textTree, _ -> hxx('<text class="text-2xl tracking-normal">Spacing</text>'));
		var spaced:Text = Owner.root(textTree, _ -> hxx('<text class="text-2xl tracking-wider">Spacing</text>'));
		textTree.flush();
		for (t in [small, large, spaced])
			textTree.computeLayout(t.node, 400, 100);
		var sb = textTree.getBounds(small.node), lb = textTree.getBounds(large.node), wb = textTree.getBounds(spaced.node);
		check("a text size class sets the font size", lb.height > sb.height && lb.width > sb.width, [sb.width, sb.height, lb.width, lb.height]);
		var wider = ashui.theme.Themed.tracking(TrackingWider, Text2xl).get();
		check("tracking is ems of the font size", Math.abs(wider - 0.05 * 24) < 1e-6, wider);

		// --- hover:, active: and dark: follow the pointer and the scheme ---
		var hoverTree = new LayoutTree();
		var button:Div = Owner.root(hoverTree, _ -> hxx('
			<div class="w-10 h-10 bg-surface hover:bg-primary active:bg-error dark:bg-accent-subtle" />
		'));
		hoverTree.flush();
		hoverTree.computeLayout(button.node, 100, 100);
		var hoverList = new ashui.layout.DisplayList();
		function fill() {
			hoverTree.flush();
			hoverList.update(hoverTree, button.node);
			return hoverList.get(0, 8);
		}
		var idle = fill();
		ashui.input.Pointer.move(hoverTree, 20, 20);
		var hovered = fill();
		ashui.input.Pointer.press(hoverTree);
		var pressed = fill();
		ashui.input.Pointer.release(hoverTree);
		ashui.input.Pointer.move(hoverTree, 90, 90);
		var left = fill();
		ashui.theme.ThemeState.get().setScheme(Dark);
		var dark = fill();
		ashui.theme.ThemeState.get().setScheme(Light);
		check("hover: and active: follow the pointer",
			idle == 1 && Math.abs(hovered - 0x2A / 255) < 0.01 && Math.abs(pressed - 0xDC / 255) < 0.01 && left == 1,
			[idle, hovered, pressed, left]);
		check("dark: follows the scheme", Math.abs(dark - 0x7D / 255) < 0.01, dark);

		// --- CSS identity: an element's types, id and classes ---
		var idTree = new LayoutTree();
		var tagged:Div = Owner.root(idTree, _ -> hxx('<div id="save" class="w-10 h-10 card pill" />'));
		var tagIdentity = ashui.css.Identity.of(idTree, tagged.node.id);
		check("hxx class= gives Tw utilities and CSS classes, id= the id", tagIdentity != null && tagIdentity.id == "save"
			&& tagIdentity.classes().join(",") == "card,pill" && tagIdentity.types.join(",") == "div",
			tagIdentity == null ? null : [tagIdentity.id, tagIdentity.classes(), tagIdentity.types]);
		var picked = Signal.make(["card"]);
		var toggled = Owner.root(idTree, _ -> new Div({id: "row", classes: picked, width: 10}, idTree));
		var toggledIdentity = ashui.css.Identity.of(idTree, toggled.node.id);
		picked.set(["card", "selected"]);
		idTree.flush();
		check("a Div's classes follow a signal", toggledIdentity.id == "row" && toggledIdentity.hasClass("selected"), toggledIdentity.classes());
		var counted:CounterView = Owner.root(idTree, _ -> hxx('<counter-view />'));
		check("a component adds its tag to its root's types", ashui.css.Identity.of(idTree, counted.node.id).types.join(",") == "div,counter-view",
			ashui.css.Identity.of(idTree, counted.node.id).types);
		var labelled:Div = Owner.root(idTree, _ -> hxx('<div><text>hi</text></div>'));
		var label = idTree.children(labelled.node.id)[0];
		check("text is of type text", ashui.css.Identity.of(idTree, label).types.join(",") == "text");
		labelled.remove();
		check("a removed element leaves no identity", ashui.css.Identity.of(idTree, label) == null && ashui.css.Identity.of(idTree, labelled.node == null ? label : labelled.node.id) == null);

		// --- Built-in text elements: tags without imports, looks from the user-agent stylesheet ---
		var textTree = new LayoutTree();
		var article:Div = Owner.root(textTree, _ -> hxx('
			<div flexDirection={Column} alignItems={Start}>
				<h1>Title</h1>
				<p>Body text</p>
				<strong>Bold</strong>
			</div>
		'));
		textTree.flush();
		textTree.computeLayout(article.node, 400, 400);
		var blocks = textTree.children(article.node.id);
		// h1 and p hold a flow, as tall as its line; strong is a box around its text.
		var heights = [
			textTree.getBounds(new ashui.layout.Node(blocks[0])).height,
			textTree.getBounds(new ashui.layout.Node(blocks[1])).height,
			textTree.getBounds(new ashui.layout.Node(textTree.children(blocks[2])[0])).height
		];
		var types = [for (b in blocks) ashui.css.Identity.of(textTree, b).types.join(",")];
		check("text elements are built in, typed for CSS", types.join("|") == "h1|p|strong", types);
		// strong keeps the default line height, as h1 does; p's is 1.5.
		check("h1's text is twice the size of strong's, and p's lines are 1.5 tall, from the user-agent stylesheet",
			heights[0] > heights[2] * 1.9 && heights[0] < heights[2] * 2.2 && Math.abs(heights[1] - 24) <= 1, heights);
		check("the user-agent sheet is in force first", ashui.css.Css.userAgent != null);

		// --- Built-in controls: checkbox, radio, label, button ---
		var formTree = new LayoutTree();
		var agreed = Signal.make(false);
		var size = Signal.make("m");
		var pressedCount = 0;
		var form:Div = Owner.root(formTree, _ -> hxx('
			<div flexDirection={Column} alignItems={Start} gap={8}>
				<label><input type="checkbox" checked={agreed} />Agree</label>
				<input type="radio" name="size" value="s" group={size} />
				<input type="radio" name="size" value="m" group={size} />
				<input type="radio" name="size" value="l" group={size} disabled={true} />
				<button onClick={() -> pressedCount++}>Go</button>
			</div>
		'));
		formTree.flush();
		formTree.computeLayout(form.node, 400, 400);
		var formNodes = formTree.children(form.node.id);
		var label = formNodes[0];
		var box = formTree.children(label)[0];
		var labelText = formTree.children(label)[1];
		function clickAt(node:haxe.Int64) {
			var b = formTree.getBounds(new ashui.layout.Node(node));
			ashui.input.Pointer.move(formTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(formTree);
			ashui.input.Pointer.release(formTree);
			formTree.flush();
		}
		var boxBounds = formTree.getBounds(new ashui.layout.Node(box));
		check("a checkbox has the user-agent sheet's size", boxBounds != null && boxBounds.width == 18 && boxBounds.height == 18, boxBounds);
		// Its check and dash, and a radio's dot, centred in the box.
		var marks = formTree.children(box).concat(formTree.children(formNodes[1]));
		var offCentre = [
			for (m in marks) {
				var b = formTree.getBounds(new ashui.layout.Node(m));
				var outer = formTree.getBounds(new ashui.layout.Node(formTree.ancestors(m)[0]));
				Math.abs(b.x + b.width / 2 - (outer.x + outer.width / 2)) + Math.abs(b.y + b.height / 2 - (outer.y + outer.height / 2));
			}
		];
		check("a checkbox's marks and a radio's dot are centred in their box", marks.length == 3 && Lambda.foreach(offCentre, d -> d < 0.5),
			offCentre);
		clickAt(box);
		var afterBox = agreed.get();
		clickAt(labelText);
		var afterLabel = agreed.get();
		check("clicking a checkbox flips its signal, and so does clicking its label", afterBox && !afterLabel, [afterBox, afterLabel]);
		@:privateAccess check(":checked follows it", !ashui.input.Interaction.byId(formTree, box).checked.get());
		function key(k:window.Key, code:window.KeyCode, pressed:Bool):window.KeyEvent
			return Input(Code(code), k, None, Standard, pressed ? Pressed : Released, false, Unavailable);
		ashui.input.Focus.set(ashui.input.Interaction.byId(formTree, box), true);
		ashui.input.Keyboard.input(formTree, key(Named(Space), Space, true));
		ashui.input.Keyboard.input(formTree, key(Named(Space), Space, false));
		var afterSpace = agreed.get();
		ashui.input.Keyboard.input(formTree, key(Named(Enter), Enter, true));
		check("Space flips a focused checkbox, Enter does not", afterSpace && agreed.get(), [afterSpace, agreed.get()]);
		var radioS = formNodes[1], radioM = formNodes[2];
		clickAt(radioS);
		var picked = size.get();
		ashui.input.Keyboard.input(formTree, key(Named(ArrowDown), ArrowDown, true));
		var arrowed = size.get();
		ashui.input.Keyboard.input(formTree, key(Named(ArrowDown), ArrowDown, true));
		var wrapped = size.get();
		check("a radio sets its group; the arrows move through the set, skipping a disabled one",
			picked == "s" && arrowed == "m" && wrapped == "s" && ashui.input.Focus.of(formTree).node.id == radioS, [picked, arrowed, wrapped]);
		clickAt(formNodes[4]);
		check("a button clicks", pressedCount == 1, pressedCount);
		check("built-in controls are typed for CSS", ashui.css.Identity.of(formTree, box).attribute("type") == "checkbox"
			&& ashui.css.Identity.of(formTree, formNodes[4]).types.join(",") == "button");

		// --- Built-in select, details and dialog: the top layer ---
		var layerTree = new LayoutTree();
		var fruit = Signal.make("pear");
		var shown = Signal.make(false);
		var fruitSelect:Null<ashui.ui.Select> = null;
		var page:Div = Owner.root(layerTree, _ -> {
			fruitSelect = new ashui.ui.Select({value: fruit}, [
				new ashui.ui.Option({value: "apple"}, [new ashui.ui.Text("Apple")]),
				new ashui.ui.Option({value: "pear"}, [new ashui.ui.Text("Pear")]),
				new ashui.ui.Optgroup({label: "Citrus"}, [
					new ashui.ui.Option({value: "lemon", disabled: true}, [new ashui.ui.Text("Lemon")]),
					new ashui.ui.Option({value: "lime"}, [new ashui.ui.Text("Lime")])
				])
			]);
			hxx('
				<div width={400} height={400} flexDirection={Column} alignItems={Start} gap={8}>
					{fruitSelect}
					<details><summary>More</summary><p>Hidden</p></details>
					<dialog open={shown}><p>Sure?</p><button>Yes</button><button>No</button></dialog>
					<button>Outside</button>
				</div>
			');
		});
		function settle() {
			layerTree.flush();
			layerTree.computeLayout(page.node, 400, 400);
			layerTree.flush();
		}
		settle();
		function key(k:window.Key, code:window.KeyCode, pressed = true):window.KeyEvent
			return Input(Code(code), k, None, Standard, pressed ? Pressed : Released, false, Unavailable);
		var selectNode = fruitSelect.node.id;
		var sb = layerTree.getBounds(fruitSelect.node);
		ashui.input.Pointer.move(layerTree, sb.x + 4, sb.y + 4);
		ashui.input.Pointer.press(layerTree);
		ashui.input.Pointer.release(layerTree);
		settle();
		var opened = fruitSelect.isOpen() && layerTree.children(page.node.id).length == 5;
		var shade = layerTree.children(page.node.id)[4];
		var listbox = layerTree.children(layerTree.children(shade)[0])[0];
		var listWidth = layerTree.getBounds(new ashui.layout.Node(listbox)).width;
		check("the list of options is as wide as its select", Math.abs(listWidth - sb.width) < 0.5, [listWidth, sb.width]);
		ashui.input.Keyboard.input(layerTree, key(Named(ArrowDown), ArrowDown));
		ashui.input.Keyboard.input(layerTree, key(Named(Enter), Enter));
		settle();
		check("a select opens its list in the top layer, and the arrows and Enter choose, skipping a disabled option",
			opened && fruit.get() == "lime" && !fruitSelect.isOpen() && ashui.input.Focus.of(layerTree).node.id == selectNode, [opened, fruit.get()]);
		ashui.input.Keyboard.input(layerTree, key(Named(ArrowUp), ArrowUp));
		settle();
		var reopened = fruitSelect.isOpen();
		ashui.input.Keyboard.input(layerTree, key(Named(Escape), Escape));
		settle();
		check("Escape closes the list without choosing", reopened && !fruitSelect.isOpen() && fruit.get() == "lime");
		ashui.input.Keyboard.text(layerTree, "a");
		check("typing chooses by label while closed", fruit.get() == "apple", fruit.get());

		var detailsNode = layerTree.children(page.node.id)[1];
		var summaryNode = layerTree.children(detailsNode)[0];
		var detailsIdentity = ashui.css.Identity.of(layerTree, detailsNode);
		var closedFirst = detailsIdentity.attribute("open") == null;
		var sumBounds = layerTree.getBounds(new ashui.layout.Node(summaryNode));
		ashui.input.Pointer.move(layerTree, sumBounds.x + 2, sumBounds.y + 2);
		ashui.input.Pointer.press(layerTree);
		ashui.input.Pointer.release(layerTree);
		settle();
		check("a details opens when its summary is clicked, marked [open]", closedFirst && detailsIdentity.attribute("open") == "", detailsIdentity.attribute("open"));

		shown.set(true);
		settle();
		var inDialog = ashui.input.Focus.of(layerTree);
		ashui.input.Keyboard.input(layerTree, key(Named(Tab), Tab));
		ashui.input.Keyboard.input(layerTree, key(Named(Tab), Tab));
		var stillIn = ashui.input.Focus.of(layerTree);
		var dialogText = inDialog == null ? "" : ashui.css.Identity.of(layerTree, layerTree.children(inDialog.node.id)[0]) == null ? "" : "button";
		ashui.input.Keyboard.input(layerTree, key(Named(Escape), Escape));
		settle();
		check("a modal dialog takes focus, keeps Tab inside, and Escape closes it, setting its signal",
			inDialog != null && stillIn == inDialog && !shown.get(), [inDialog == null, stillIn == inDialog, shown.get()]);

		// --- Built-in text, number and range inputs; progress, meter, fieldset, a, hr, textarea ---
		var formsTree = new LayoutTree();
		var typed = Signal.make("");
		var pass = Signal.make("abc");
		var count = Signal.make(2.0);
		var level = Signal.make(50.0);
		var locked = Signal.make(false);
		var followed = 0;
		var formsPage:Div = Owner.root(formsTree, _ -> hxx('
			<div width={400} height={640} flexDirection={Column} alignItems={Start} gap={8}>
				<input type="text" value={typed} />
				<input type="password" value={pass} />
				<input type="number" valueAsNumber={count} min={0} max={3} step={0.5} />
				<input type="range" valueAsNumber={level} min={0} max={100} step={10} />
				<fieldset disabled={locked}><legend><input type="checkbox" /></legend><input type="checkbox" /></fieldset>
				<progress value={0.25} />
				<meter value={0.9} low={0.3} high={0.7} optimum={0.1} />
				<a onClick={_ -> followed++}>Go</a>
				<hr />
				<textarea />
			</div>
		'));
		function formsSettle() {
			formsTree.flush();
			formsTree.computeLayout(formsPage.node, 400, 640);
			formsTree.flush();
		}
		formsSettle();
		var formKids = formsTree.children(formsPage.node.id);
		function formNode(i:Int)
			return new ashui.layout.Node(formKids[i]);
		function clickAt(i:Int, fx:Float) {
			var b = formsTree.getBounds(formNode(i));
			ashui.input.Pointer.move(formsTree, b.x + b.width * fx, b.y + b.height / 2);
			ashui.input.Pointer.press(formsTree);
			ashui.input.Pointer.release(formsTree);
			formsSettle();
		}
		function formKey(k:window.Key, code:window.KeyCode) {
			ashui.input.Keyboard.input(formsTree, key(k, code));
			formsSettle();
		}
		clickAt(0, 0.5);
		ashui.input.Keyboard.text(formsTree, "hi");
		formsSettle();
		check("a text input edits its value signal", typed.get() == "hi", typed.get());
		var passInput = ashui.ui.Input.at(formsTree, formKids[1]);
		check("a password shows a dot for each character", passInput.editing.display() == "\u2022\u2022\u2022", passInput.editing.display());

		var numberInput = ashui.ui.Input.at(formsTree, formKids[2]);
		var shownFirst = numberInput.value.get();
		clickAt(2, 0.3);
		formKey(Named(ArrowUp), ArrowUp);
		var stepped = count.get();
		formKey(Named(ArrowUp), ArrowUp);
		formKey(Named(ArrowUp), ArrowUp);
		check("a number shows its value, and the up arrow steps it, no further than max", shownFirst == "2" && stepped == 2.5 && count.get() == 3
			&& numberInput.value.get() == "3", [shownFirst, stepped, count.get(), numberInput.value.get()]);
		ashui.input.Keyboard.text(formsTree, "x");
		formsSettle();
		count.set(1.5);
		formsSettle();
		check("a number refuses what no number is written with, and follows its signal", numberInput.value.get() == "1.5", numberInput.value.get());

		var rangeBounds = formsTree.getBounds(formNode(3));
		var thumbWidth = formsTree.getBounds(new ashui.layout.Node(formsTree.children(formKids[3])[1])).width;
		function rangeX(f:Float)
			return rangeBounds.x + thumbWidth / 2 + f * (rangeBounds.width - thumbWidth);
		clickAt(3, 0.5);
		formKey(Named(ArrowRight), ArrowRight);
		var afterArrow = level.get();
		formKey(Named(End), End);
		var atEnd = level.get();
		formKey(Named(Home), Home);
		check("a range steps by the arrows, and Home and End go to its ends", afterArrow == 60 && atEnd == 100 && level.get() == 0,
			[afterArrow, atEnd, level.get()]);
		ashui.input.Pointer.move(formsTree, rangeX(0.7), rangeBounds.y + rangeBounds.height / 2);
		ashui.input.Pointer.press(formsTree);
		var pressedAt = level.get();
		ashui.input.Pointer.move(formsTree, rangeX(0.2), rangeBounds.y + 200);
		var draggedTo = level.get();
		ashui.input.Pointer.release(formsTree);
		ashui.input.Pointer.move(formsTree, rangeX(0.9), rangeBounds.y + rangeBounds.height / 2);
		formsSettle();
		check("a range is set where it is pressed, follows a drag off it, and stops at the release", pressedAt == 70 && draggedTo == 20
			&& level.get() == 20, [pressedAt, draggedTo, level.get()]);

		var fieldsetKids = formsTree.children(formKids[4]);
		var legendBox = ashui.input.Interaction.byId(formsTree, formsTree.children(fieldsetKids[0])[0]);
		var heldBox = ashui.input.Interaction.byId(formsTree, fieldsetKids[1]);
		locked.set(true);
		formsSettle();
		var lockedNow = heldBox.disabled.get() && !legendBox.disabled.get()
			&& ashui.css.Identity.of(formsTree, formKids[4]).attribute("disabled") == "";
		locked.set(false);
		formsSettle();
		check("a disabled fieldset disables what it holds, but what is in its legend", lockedNow && !heldBox.disabled.get(),
			[lockedNow, heldBox.disabled.get()]);

		var progressWidth = formsTree.getBounds(formNode(5)).width;
		var progressBar = formsTree.getBounds(new ashui.layout.Node(formsTree.children(formKids[5])[0])).width;
		check("a progress bar fills to its value", Math.abs(progressBar - progressWidth * 0.25) < 0.5, [progressBar, progressWidth]);
		var meterBar = ashui.css.Identity.of(formsTree, formsTree.children(formKids[6])[0]);
		check("a meter judges a value beyond the part its optimum is in as even less good", @:privateAccess meterBar.fixed.indexOf("even-less-good") >= 0
			|| @:privateAccess (meterBar.classSignal != null && meterBar.classSignal.get().indexOf("even-less-good") >= 0));
		clickAt(7, 0.5);
		check("an a is followed when clicked", followed == 1, followed);
		var hrBounds = formsTree.getBounds(formNode(8));
		check("an hr is a rule across what holds it", hrBounds.height == 1 && hrBounds.width == 400, [hrBounds.width, hrBounds.height]);
		check("<textarea> is the built-in text area", ashui.css.Identity.of(formsTree, formKids[9]).types.indexOf("textarea") >= 0);

		// --- Built-in lists, tables and pre; CSS grid ---
		var listTree = new LayoutTree();
		var shoppingItems = Signal.make(["Milk", "Eggs"]);
		var listPage:Div = Owner.root(listTree, _ -> hxx('
			<div width={480} height={600} flexDirection={Column} alignItems={Start}>
				<ul><li>Fruit<ul><li>Apples<ul><li>Cox</li></ul></li></ul></li></ul>
				<ol start={3} type="a"><li>c</li><li value={10}>j</li><li>k</li></ol>
				<ol reversed={true} type="I"><for {item in shoppingItems}><li>{item}</li></for></ol>
				<table>
					<colgroup><col width="100" /></colgroup>
					<thead><tr><th>A</th><th>B</th><th>C</th></tr></thead>
					<tbody><tr><td>1</td><td colspan={2}>wide</td></tr></tbody>
				</table>
				<pre>{"line one is long enough to wrap if it could\n    two"}</pre>
			</div>
		'));
		function listSettle() {
			listTree.flush();
			listTree.computeLayout(listPage.node, 480, 600);
			listTree.flush();
		}
		listSettle();
		var listKids = listTree.children(listPage.node.id);
		// The items under a list, nested ones included, in document order.
		function itemsUnder(node:haxe.Int64):Array<ashui.ui.Li> {
			var out = [];
			for (c in listTree.children(node)) {
				var li = ashui.ui.Li.at(c);
				if (li != null)
					out.push(li);
				out = out.concat(itemsUnder(c));
			}
			return out;
		}
		function liAt(path:Array<Int>):ashui.ui.Li
			return itemsUnder(listKids[path[0]])[path[1]];
		var nested = itemsUnder(listKids[0]);
		var outer = nested[0], middle = nested[1], inner = nested[2];
		check("a ul marks its items with a disc, a circle inside one, a square deeper",
			outer.bullet.get() == "disc" && middle.bullet.get() == "circle" && inner.bullet.get() == "square",
			[outer.bullet.get(), middle.bullet.get(), inner.bullet.get()]);
		var lettered = [for (i in 0...3) liAt([1, i]).marker.get()];
		check("an ol counts from start in its type, an item's value setting the count", lettered.join(" ") == "c. j. k.", lettered);
		shoppingItems.set(["Milk", "Eggs", "Flour"]);
		listSettle();
		var reversed = [for (i in 0...3) liAt([2, i]).marker.get()];
		check("a reversed ol counts down from its items, numbering again as items come", reversed.join(" ") == "III. II. I.", reversed);

		var tableKids = listTree.children(listKids[3]);
		var headRow = listTree.children(tableKids[1])[0], bodyRow = listTree.children(tableKids[2])[0];
		var heads = [for (c in listTree.children(headRow)) listTree.getBounds(new ashui.layout.Node(c))];
		var cells = [for (c in listTree.children(bodyRow)) listTree.getBounds(new ashui.layout.Node(c))];
		check("table columns line up down the table, a col setting a width and a colspan spanning",
			Math.abs(heads[0].width - 100) < 0.5 && Math.abs(cells[0].width - heads[0].width) < 0.5
			&& Math.abs(cells[1].x - heads[1].x) < 0.5 && Math.abs(cells[1].x + cells[1].width - heads[2].x - heads[2].width) < 0.5,
			[heads[0].width, cells[0].width, cells[1].x, heads[1].x, cells[1].width]);
		var preText = listTree.children(listKids[4])[0];
		var preBounds = listTree.getBounds(new ashui.layout.Node(preText));
		check("a pre keeps its lines, wrapping none", preBounds.width > 300 && preBounds.height < 80, [preBounds.width, preBounds.height]);

		var gridTree = new LayoutTree();
		ashui.css.Css.load('
			.grid { display: grid; width: 300px; grid-template-columns: 50px repeat(2, 1fr); grid-template-rows: 20px 30px; }
			.grid > .spanned { grid-column: 2 / span 2; grid-row: 2; }
		');
		var gridBox:Div = Owner.root(gridTree, _ -> new Div({classes: ["grid"]}, [new Div({}), new Div({classes: ["spanned"]})], gridTree));
		gridTree.flush();
		gridTree.computeLayout(gridBox.node, 400, 400);
		gridTree.flush();
		var spanned = gridTree.getBounds(new ashui.layout.Node(gridTree.children(gridBox.node.id)[1]));
		check("CSS grid: tracks, repeat, and an item placed by line and span", spanned.x == 50 && spanned.width == 250 && spanned.y == 20
			&& spanned.height == 30, [spanned.x, spanned.width, spanned.y, spanned.height]);

		ashui.css.Css.load('.opened > .leaf { width: 30px; height: 10px } .opened + .after { width: 40px; height: 10px }');
		var openedClasses = Signal.make(["closed"]);
		var leaf = new Div({classes: ["leaf"]}, gridTree);
		var after = new Div({classes: ["after"]}, gridTree);
		var combinatorRoot:Div = Owner.root(gridTree, _ -> new Div({flexDirection: Column, alignItems: Start},
			[new Div({classes: openedClasses, alignItems: Start}, [leaf], gridTree), after], gridTree));
		function combinatorWidths() {
			gridTree.flush();
			gridTree.computeLayout(combinatorRoot.node, 400, 400);
			gridTree.flush();
			return [gridTree.getBounds(leaf.node).width, gridTree.getBounds(after.node).width];
		}
		var before = combinatorWidths();
		openedClasses.set(["opened"]);
		var afterOpen = combinatorWidths();
		check("a class change matches again what combinators reach: children and later siblings", before[0] == 0 && before[1] == 0
			&& afterOpen[0] == 30 && afterOpen[1] == 40, [before, afterOpen]);

		// --- Inline flow: a paragraph's text and inline elements wrap as one, on one baseline ---
		var flowTree = new LayoutTree();
		var flowWidth = Signal.make((400 : Single));
		var linkClicks = 0;
		var said = Signal.make("short");
		var flowPage:Div = Owner.root(flowTree, _ -> hxx('
			<div flexDirection={Column} alignItems={Start} width={flowWidth}>
				<p>with <strong>strong</strong> and</p>
				<p>Read the <a onClick={_ -> linkClicks++}>manual pages that go on and on</a> first, then <code>run</code> it.</p>
				<p>{said}</p>
			</div>
		'));
		function flowSettle() {
			flowTree.flush();
			flowTree.computeLayout(flowPage.node, 400, 600);
			flowTree.flush();
		}
		flowSettle();
		var flowList:Array<ashui.text.InlineFlow> = @:privateAccess ashui.text.InlineFlow.flows.get(flowTree);
		function piecesOf(flow:ashui.text.InlineFlow):Array<{text:String, x:Float, y:Float, w:Float, node:haxe.Int64}> {
			var out = [];
			for (run in @:privateAccess flow.runs)
				for (piece in @:privateAccess run.pieces)
					if (piece.shown.get() == ashui.types.Style.Display.Flex) {
						var b = flowTree.getBounds(piece.text.node);
						out.push({text: piece.content.get(), x: (b.x : Float), y: (b.y : Float), w: (b.width : Float), node: piece.text.node.id});
					}
			out.sort((a, b) -> a.y == b.y ? Std.int(a.x - b.x) : Std.int(a.y - b.y));
			return out;
		}
		var first = piecesOf(flowList[0]);
		check("inline flow keeps the space after an inline element", first.length == 3 && first[2].text == " and"
			&& first[2].x >= first[1].x + first[1].w - 0.5, [for (p in first) p.text]);

		flowWidth.set(160);
		flowSettle();
		var wrapped = piecesOf(flowList[1]);
		var linkPieces = wrapped.filter(p -> flowTree.ancestors(p.node)[0] != @:privateAccess flowList[1].root.node.id
			&& ashui.css.Identity.of(flowTree, flowTree.ancestors(p.node)[0]).types.indexOf("a") >= 0);
		var lineTops = [for (p in linkPieces) p.y];
		check("an inline element's text wraps across lines with the text around it", linkPieces.length >= 2 && lineTops[0] < lineTops[lineTops.length - 1],
			[for (p in wrapped) p.text]);
		var lastLink = linkPieces[linkPieces.length - 1];
		ashui.input.Pointer.move(flowTree, lastLink.x + 2, lastLink.y + 4);
		ashui.input.Pointer.press(flowTree);
		ashui.input.Pointer.release(flowTree);
		check("a click on a wrapped link's second line is a click on the link", linkClicks == 1, linkClicks);

		// code's text, in its box, on the baseline of the text beside it.
		var codeRun = Lambda.find(@:privateAccess flowList[1].runs, r -> @:privateAccess r.deco != null);
		var codePiece = flowTree.getBounds(@:privateAccess codeRun.pieces[0].text.node);
		var beside = wrapped.filter(p -> Math.abs(p.y - codePiece.y) < 20 && (p.text.indexOf("then") >= 0 || p.text.indexOf("it.") >= 0))[0];
		var besideRun = Lambda.find(@:privateAccess flowList[1].runs, r -> Lambda.exists(@:privateAccess r.pieces, q -> q.text.node.id == beside.node));
		var codeBaseline = codePiece.y + @:privateAccess codeRun.above, textBaseline = beside.y + @:privateAccess besideRun.above;
		check("an inline box in the flow, as code is, has its text on the line's baseline", Math.abs(codeBaseline - textBaseline) < 0.5,
			[codeBaseline, textBaseline]);

		var shortHeight = flowTree.getBounds(@:privateAccess flowList[2].root.node).height;
		said.set("a much longer sentence that now needs more than one line here");
		flowSettle();
		var longHeight = flowTree.getBounds(@:privateAccess flowList[2].root.node).height;
		check("a flow measures again when its text changes, and grows a line", longHeight > shortHeight * 1.5, [shortHeight, longHeight]);

		// --- Inline flow: a paragraph taken away while others stay, its siblings' children changing after ---
		var goneTree = new LayoutTree();
		var lines = Signal.make(["a", "b"]);
		var goneRoot:Div = Owner.root(goneTree, _ -> new Div({width: 200, height: 200, flexDirection: Column}, [
			new ashui.ui.For(() -> lines.get(), v -> hxx('<div><p>Line {v}</p></div>'))
		], goneTree));
		function goneSettle() {
			goneTree.flush();
			goneTree.computeLayout(goneRoot.node, 200, 200);
			goneTree.flush();
		}
		goneSettle();
		lines.set(["a"]);
		var survived = try {
			goneSettle();
			lines.set(["a", "c"]);
			goneSettle();
			true;
		} catch (e:haxe.Exception) false;
		check("a paragraph removed from a list leaves no flow behind to trip on the list's next change", survived);

		// --- Inline flow: text-align ---
		var alignTree = new LayoutTree();
		ashui.css.Css.load('.justified { text-align: justify }');
		var alignPage:Div = Owner.root(alignTree, _ -> hxx('
			<div flexDirection={Column} alignItems={Stretch} width={200}>
				<p class="text-center">short</p>
				<p class="text-right">short</p>
				<p>words that run on long enough to fill more than one whole line of this width</p>
			</div>
		'));
		var alignKids = alignTree.children(alignPage.node.id);
		ashui.css.Identity.of(alignTree, alignKids[2]).setClasses(["justified"]);
		alignTree.flush();
		alignTree.computeLayout(alignPage.node, 200, 400);
		alignTree.flush();
		alignTree.computeLayout(alignPage.node, 200, 400);
		var alignFlows:Array<ashui.text.InlineFlow> = @:privateAccess ashui.text.InlineFlow.flows.get(alignTree);
		function shownPieces(flow:ashui.text.InlineFlow) {
			var out = [];
			for (run in @:privateAccess flow.runs)
				for (piece in @:privateAccess run.pieces)
					if (piece.shown.get() == ashui.types.Style.Display.Flex)
						out.push(alignTree.getBounds(piece.text.node));
			return out;
		}
		var rootBox = alignTree.getBounds(new ashui.layout.Node(alignKids[0]));
		var centred = shownPieces(alignFlows[0])[0], righted = shownPieces(alignFlows[1])[0];
		var leftGap = centred.x - rootBox.x, rightGap = rootBox.x + rootBox.width - (centred.x + centred.width);
		check("text-align: center sets a flow's line in the middle, right at the end", Math.abs(leftGap - rightGap) < 1
			&& Math.abs(righted.x + righted.width - (rootBox.x + rootBox.width)) < 1, [leftGap, rightGap, righted.x + righted.width]);
		var justified = shownPieces(alignFlows[2]);
		var firstTop = Lambda.fold(justified, (b, m:Float) -> Math.min(m, b.y), 1e9);
		var lastTop = Lambda.fold(justified, (b, m:Float) -> Math.max(m, b.y), -1e9);
		var firstLineEnd = Lambda.fold(justified.filter(b -> b.y == firstTop), (b, m:Float) -> Math.max(m, b.x + b.width), 0);
		var lastLineEnd = Lambda.fold(justified.filter(b -> b.y == lastTop), (b, m:Float) -> Math.max(m, b.x + b.width), 0);
		var edge = rootBox.x + rootBox.width;
		check("text-align: justify fills every line to the edge but the last", lastTop > firstTop && Math.abs(firstLineEnd - edge) < 1
			&& lastLineEnd < edge - 5, [firstLineEnd, lastLineEnd, edge]);

		// --- Inline flow: boxes per line, long words, structure ---
		var proseTree = new LayoutTree();
		ashui.css.Css.load('.breaking { overflow-wrap: anywhere } .lead > strong:first-child { opacity: 0.5 }');
		var proseRoot:Div = Owner.root(proseTree, _ -> hxx('
			<div flexDirection={Column} alignItems={Stretch} width={160}>
				<p>some text and <mark>a highlight that runs over the line</mark> end</p>
				<p>Supercalifragilisticexpialidocious</p>
				<p>Supercalifragilisticexpialidocious</p>
				<p><strong>Lead</strong> in</p>
			</div>
		'));
		var proseKids = proseTree.children(proseRoot.node.id);
		ashui.css.Identity.of(proseTree, proseKids[2]).setClasses(["breaking"]);
		ashui.css.Identity.of(proseTree, proseKids[3]).setClasses(["lead"]);
		for (_ in 0...2) {
			proseTree.flush();
			proseTree.computeLayout(proseRoot.node, 160, 600);
		}
		var proseFlows:Array<ashui.text.InlineFlow> = @:privateAccess ashui.text.InlineFlow.flows.get(proseTree);
		var markRun = Lambda.find(@:privateAccess proseFlows[0].runs, r -> @:privateAccess r.deco != null);
		var markBoxes = [
			for (b in @:privateAccess markRun.deco.boxes)
				if (b.shown.get() == ashui.types.Style.Display.Flex) proseTree.getBounds(b.node)
		];
		var copyIdentity = ashui.css.Identity.of(proseTree, @:privateAccess markRun.deco.boxes[1].node.id);
		check("an inline box that wraps has a box on each line, the copies styled as it is", markBoxes.length >= 2 && markBoxes[1].y > markBoxes[0].y
			&& copyIdentity.types.indexOf("mark") >= 0 && copyIdentity.anonymous, [for (b in markBoxes) b.y]);
		function widestPiece(flow:ashui.text.InlineFlow):{width:Float, count:Int} {
			var w = 0.0, n = 0;
			for (run in @:privateAccess flow.runs)
				for (piece in @:privateAccess run.pieces)
					if (piece.shown.get() == ashui.types.Style.Display.Flex) {
						w = Math.max(w, proseTree.getBounds(piece.text.node).width);
						n++;
					}
			return {width: w, count: n};
		}
		var overflowing = widestPiece(proseFlows[1]), broken = widestPiece(proseFlows[2]);
		check("a word longer than its line overflows, unless overflow-wrap lets it break", overflowing.count == 1 && overflowing.width > 160
			&& broken.count >= 2 && broken.width <= 160, [overflowing, broken]);
		var leadStrong = ashui.css.Identity.of(proseTree, proseTree.children(proseKids[3])[2]);
		check("the flow's own nodes are not counted by :first-child", leadStrong.types.indexOf("strong") >= 0
			&& ashui.css.Css.computed(leadStrong, "opacity") == "0.5", ashui.css.Css.computed(leadStrong, "opacity"));

		// --- Built-in forms: constraints, :user-invalid, submit and reset ---
		var formTree2 = new LayoutTree();
		var email = Signal.make("");
		var nick = Signal.make("start");
		var agreed2 = Signal.make(false);
		var submitted:Null<ashui.ui.Form.FormData> = null;
		var formRoot:Div = Owner.root(formTree2, _ -> hxx('
			<div flexDirection={Column} alignItems={Start} width={400}>
				<form onSubmit={d -> submitted = d}>
					<input type="email" name="email" value={email} required={true} placeholder="you@example.com" />
					<input type="text" name="nick" value={nick} maxlength={3} pattern="[a-z]+" />
					<input type="number" name="age" min={1} max={120} />
					<input type="checkbox" name="agree" checked={agreed2} required={true} />
					<button type="reset">Reset</button>
					<button>Send</button>
				</form>
			</div>
		'));
		function formSettle2() {
			formTree2.flush();
			formTree2.computeLayout(formRoot.node, 400, 600);
			formTree2.flush();
		}
		formSettle2();
		var formNode = formTree2.children(formRoot.node.id)[0];
		var fields = [for (c in formTree2.children(formNode)) c];
		function clickNode(n:haxe.Int64) {
			var b = formTree2.getBounds(new ashui.layout.Node(n));
			ashui.input.Pointer.move(formTree2, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(formTree2);
			ashui.input.Pointer.release(formTree2);
			formSettle2();
		}
		var emailInput = ashui.ui.Input.at(formTree2, fields[0]), nickInput = ashui.ui.Input.at(formTree2, fields[1]);
		var ageInput = ashui.ui.Input.at(formTree2, fields[2]), agreeInput = ashui.ui.Input.at(formTree2, fields[3]);
		var emailState = @:privateAccess emailInput.interaction;
		var shownEmpty = emailState.formState("placeholder-shown").get();
		var untouchedInvalid = emailState.formState("invalid").get() && !emailState.formState("user-invalid").get();
		clickNode(fields[5]);
		check("submitting an invalid form submits nothing, marks its controls :user-invalid and focuses the first invalid one",
			submitted == null && untouchedInvalid && emailState.formState("user-invalid").get()
			&& ashui.input.Focus.of(formTree2) == emailState && shownEmpty, [submitted == null, untouchedInvalid, shownEmpty]);
		email.set("ada");
		formSettle2();
		var badEmail = emailInput.validationMessage();
		email.set("ada@example.com");
		formSettle2();
		check("an email input is invalid until it has an address, and :placeholder-shown leaves once it has text", badEmail.indexOf("@") >= 0
			&& emailInput.checkValidity() && !emailState.formState("placeholder-shown").get(), badEmail);
		clickNode(fields[1]);
		@:privateAccess nickInput.editing.anchor.set(0);
		@:privateAccess nickInput.editing.caret.set(5);
		ashui.input.Keyboard.text(formTree2, "abcdef");
		formSettle2();
		check("maxlength cuts what is typed to the room left", nick.get() == "abc", nick.get());
		nick.set("ab1");
		formSettle2();
		var patternMessage = nickInput.validationMessage();
		nick.set("abc");
		@:privateAccess ageInput.value.set("200");
		formSettle2();
		check("pattern and a number's max are constraints, with a browser's messages", patternMessage.indexOf("format") >= 0
			&& ageInput.validationMessage().indexOf("120") >= 0, [patternMessage, ageInput.validationMessage()]);
		@:privateAccess ageInput.value.set("30");
		agreed2.set(true);
		formSettle2();
		clickNode(fields[1]);
		ashui.input.Keyboard.input(formTree2, key(Named(Enter), Enter));
		formSettle2();
		check("Enter in a text input submits a valid form, with each named control's value", submitted != null && submitted.get("email") == "ada@example.com"
			&& submitted.get("nick") == "abc" && submitted.get("age") == "30" && submitted.get("agree") == "on",
			submitted == null ? null : [for (e in submitted.entries) e.name + "=" + e.value]);
		clickNode(fields[4]);
		check("a reset button puts each control's first value back", email.get() == "" && nick.get() == "start" && !agreed2.get(),
			[email.get(), nick.get(), agreed2.get()]);

		// --- CSS mask-image ---
		var maskSheet = ashui.css.Css.load('.faded { mask-image: linear-gradient(to right, black, transparent) } .plain { mask-image: none } .wrong { mask-image: url(x.png) }');
		check("mask-image takes a gradient or none, and reports anything else", maskSheet.diagnostics.length == 0
			&& ashui.css.Css.problems.filter(p -> p.indexOf("mask-image") >= 0).length == 0, maskSheet.report());
		var maskTree2 = new LayoutTree();
		var maskedDiv = Owner.root(maskTree2, _ -> new Div({classes: ["faded"]}, maskTree2));
		maskTree2.flush();
		var plainDiv = Owner.root(maskTree2, _ -> new Div({classes: ["wrong"]}, maskTree2));
		maskTree2.flush();
		check("a mask-image gradient is set on the element; a url is a problem, not a crash", @:privateAccess maskedDiv.node.styled != null
			&& @:privateAccess maskedDiv.node.styled.exists(ashui.layout.Node.field(ashui.layout.Prop.MaskImage))
			&& ashui.css.Css.problems.filter(p -> p.indexOf("mask-image") >= 0).length == 1, ashui.css.Css.problems);

		// --- State machines: typed transitions on signals, actions, timers on the scheduler's clock ---
		var clock = new ashui.animation.AnimationScheduler();
		var log = [];
		var m = new ashui.state.Machine<SmokeState, SmokeEvent>(Idle, (st, ev) -> switch [st, ev] {
			case [Idle, Go]: Loading(0);
			case [Loading(n), Step]: Loading(n + 1);
			case [Loading(_), Done]: Shown;
			case [Shown, Go]: Shown;
			case [Shown, Hide]: Hiding;
			case [Hiding, Gone]: Idle;
			case _: null;
		}, clock);
		m.onExit(Idle, _ -> log.push("exit idle")).onEnter(Loading(0), st -> log.push("enter " + Std.string(st)));
		m.onEnter(Shown, _ -> log.push("enter shown")).after(Hiding, 0.2, Gone);
		var name = m.name();
		m.send(Hide);
		var ignored = Type.enumEq(m.state.get(), Idle);
		m.send(Go);
		m.send(Step);
		check("a machine moves by its transition, ignores what it does not take, and matches a state's arguments by constructor",
			ignored && Type.enumEq(m.state.get(), Loading(1)) && log.join("|") == "exit idle|enter Loading(0)|enter Loading(1)",
			[Std.string(m.state.get()), log.join("|")]);
		m.send(Done);
		log.resize(0);
		m.send(Go);
		check("a move to the state it is in runs no actions", log.length == 0 && m.is(Shown), log);
		m.send(Hide);
		check("its name is its state's, in kebab case, for data-state", name.get() == "hiding", name.get());
		clock.tick(0.1);
		var stillHiding = m.is(Hiding);
		clock.tick(0.15);
		check("a transient state's timer sends its event after its time on the scheduler's clock", stillHiding && m.is(Idle), Std.string(m.state.get()));
		m.after(Shown, 0.1, Hide);
		m.send(Go);
		m.send(Done);
		m.send(Hide);
		clock.tick(0.05);
		m.send(Gone);
		clock.tick(0.2);
		check("leaving a state cancels its timers", m.is(Idle), Std.string(m.state.get()));
		var chained = new ashui.state.Machine<SmokeState, SmokeEvent>(Idle, (st, ev) -> switch [st, ev] {
			case [Idle, Go]: Shown;
			case [Shown, Hide]: Hiding;
			case _: null;
		}, clock);
		chained.onEnter(Shown, _ -> chained.send(Hide));
		chained.send(Go);
		check("an event an action sends is taken once the move is done", chained.is(Hiding), Std.string(chained.state.get()));
		var started = 0;
		var fresh = new ashui.state.Machine<SmokeState, SmokeEvent>(Shown, (st, ev) -> null, clock);
		fresh.onEnter(Shown, _ -> started++).start();
		fresh.dispose();
		fresh.send(Go);
		check("start runs the first state's entry; a disposed machine takes nothing", started == 1 && fresh.is(Shown), started);

		// --- Layout animation: FLIP, drawn from where it was to where layout puts it ---
		var flipTree = new LayoutTree();
		var above = Signal.make((20 : Single));
		var boxWidth = Signal.make((100 : Single));
		var carried = new Div({width: 20, height: 10, animateLayout: true}, flipTree);
		var moving = new Div({width: boxWidth, height: 40, animateLayout: true}, [carried], flipTree);
		var flipRoot = new Div({width: 300, height: 300, flexDirection: Column, alignItems: Start}, [new Div({width: 50, height: above}, flipTree), moving],
			flipTree);
		function flipSettle() {
			flipTree.flush();
			flipTree.computeLayout(flipRoot.node, 300, 300);
			flipTree.flush();
		}
		flipSettle();
		var anims:Map<String, ashui.animation.LayoutAnimation> = @:privateAccess ashui.animation.LayoutAnimation.animated.get(flipTree);
		var movingAnim = anims.get(haxe.Int64.toStr(moving.node.id)), carriedAnim = anims.get(haxe.Int64.toStr(carried.node.id));
		above.set(60);
		flipSettle();
		var startDy = @:privateAccess movingAnim.shown.dy;
		var hitOld = flipTree.hitTest(10, 25).map(h -> h.id).indexOf(moving.node.id) >= 0;
		var carriedStill = @:privateAccess carriedAnim.shown.dy == 0 && !@:privateAccess carriedAnim.running;
		ashui.animation.AnimationScheduler.main.tick(0.1);
		var midDy = @:privateAccess movingAnim.shown.dy;
		ashui.animation.AnimationScheduler.main.tick(0.5);
		check("a box layout moves is drawn where it was, eases to its place, and is hit where it is drawn", startDy == -40 && midDy > -40 && midDy < 0
			&& @:privateAccess movingAnim.shown.dy == 0 && !@:privateAccess movingAnim.running && hitOld, [startDy, midDy, hitOld]);
		check("a child its animated parent carries does not move twice", carriedStill);
		boxWidth.set(200);
		flipSettle();
		var startW = @:privateAccess movingAnim.shown.w;
		ashui.animation.AnimationScheduler.main.tick(0.1);
		var midW = @:privateAccess movingAnim.shown.w;
		ashui.animation.AnimationScheduler.main.tick(0.5);
		check("a box layout resizes is drawn at the size between, then at its own", startW == 100 && midW > 100 && midW < 200
			&& @:privateAccess movingAnim.shown.w == -1, [startW, midW]);

		// --- CSS: rules apply by the cascade, under what an element sets itself ---
		var cssTree = new LayoutTree();
		var sheet = ashui.css.Css.load('
			.card.selected { background: #0000ff; }
			.card { padding: 12px; background: #ff0000; width: 50px; height: 40px; }
			#save { opacity: 0.5 }
			.list > .row:first-child { height: 10px; }
			.list .row:nth-child(2) { height: 20px }
			:root { --brand: #00ff00 }
			.brand { background: var(--brand); width: 10px; height: 10px }
			.big { font-size: 32px }
			.oops { colour: red; width: wide }
		');
		check("a stylesheet loads, an unknown property a warning",
			sheet.diagnostics.length == 1 && sheet.diagnostics[0].severity == Warning && sheet.diagnostics[0].message.indexOf("colour") == 0
			&& sheet.diagnostics[0].line == 10, sheet.report());
		var cssList = new ashui.layout.DisplayList();
		function fillOf(d:Div):Array<Float> {
			cssTree.flush();
			cssTree.computeLayout(d.node, 400, 400);
			cssList.update(cssTree, d.node);
			return cssList.count == 0 ? [] : [for (f in 8...12) cssList.get(0, f)];
		}
		function boundsOf(d:Div) {
			cssTree.flush();
			cssTree.computeLayout(d.node, 400, 400);
			return cssTree.getBounds(d.node);
		}
		var picked = Signal.make(["card"]);
		var card = Owner.root(cssTree, _ -> new Div({id: "save", classes: picked}, cssTree));
		var f = fillOf(card);
		var b = boundsOf(card);
		check("a rule's declarations apply, the id rule's opacity too", f.join(",") == "1,0,0,0.5" && b != null && b.width == 50 && b.height == 40,
			[f, b]);
		picked.set(["card", "selected"]);
		check("a class added matches again, and specificity beats source order", fillOf(card).join(",") == "0,0,1,0.5", fillOf(card));
		picked.set([]);
		var gone = boundsOf(card);
		check("what no rule sets any more goes back", fillOf(card).length == 0 && gone != null && gone.width == 0, [fillOf(card), gone]);
		picked.set(["card"]);
		var owned = Owner.root(cssTree, _ -> new Div({classes: ["card"], width: 80}, cssTree));
		var ob = boundsOf(owned);
		check("an element's own attribute wins over a rule", ob != null && ob.width == 80 && ob.height == 40, ob);

		var rows = [for (_ in 0...3) new Div({classes: ["row"], width: 5}, cssTree)];
		var list = Owner.root(cssTree, _ -> new Div({classes: ["list"], flexDirection: Column, alignItems: Start}, [for (r in rows) (r : Element)], cssTree));
		boundsOf(list);
		var heights = [for (r in rows) cssTree.getBounds(r.node).height];
		check("child combinators and structural pseudo-classes", heights[0] == 10 && heights[1] == 20 && heights[2] == 0, heights);

		var branded = Owner.root(cssTree, _ -> new Div({classes: ["brand"]}, cssTree));
		check("var() reads :root's custom properties", fillOf(branded).join(",") == "0,1,0,1", fillOf(branded));

		var small = new ashui.ui.Text("Ag", null, cssTree);
		var large = new ashui.ui.Text("Ag", null, cssTree);
		var plainBox = Owner.root(cssTree, _ -> new Div({alignItems: Start, flexDirection: Column}, [small], cssTree));
		var bigBox = Owner.root(cssTree, _ -> new Div({classes: ["big"], alignItems: Start, flexDirection: Column}, [large], cssTree));
		boundsOf(plainBox);
		boundsOf(bigBox);
		var smallHeight = cssTree.getBounds(small.node).height, largeHeight = cssTree.getBounds(large.node).height;
		check("text inherits font-size from the element around it", largeHeight > smallHeight * 1.5, [smallHeight, largeHeight]);
		var oops = Owner.root(cssTree, _ -> new Div({classes: ["oops"]}, cssTree));
		boundsOf(oops);
		check("a value that does not read is reported once it applies", ashui.css.Css.problems.filter(p -> p.indexOf("width: expected a length") >= 0).length == 1,
			ashui.css.Css.problems);

		var bound = Owner.root(cssTree, _ -> hxx('<div class="card p-1"><div width={4} height={4} /></div>'));
		boundsOf(bound);
		var inner = cssTree.children(bound.node.id)[0];
		check("a Tw class wins over a rule", cssTree.getBounds(new ashui.layout.Node(inner)).x == 4, cssTree.getBounds(new ashui.layout.Node(inner)));

		// --- CSS states: :hover on the element, and on an ancestor ---
		var stateSheet = ashui.css.Css.load('
			.btn { width: 40px; height: 40px; background: #ff0000; }
			.btn:hover { background: #00ff00; }
			.btn:hover .dot { background: #0000ff; }
			.dot { width: 10px; height: 10px; background: #000000; }
		');
		var stateTree = new LayoutTree();
		var dot = new Div({classes: ["dot"]}, stateTree);
		var btn = Owner.root(stateTree, _ -> new Div({classes: ["btn"]}, [dot], stateTree));
		var stateList = new ashui.layout.DisplayList();
		function fills():Array<String> {
			stateTree.flush();
			stateTree.computeLayout(btn.node, 100, 100);
			stateList.update(stateTree, btn.node);
			return [for (r in 0...stateList.count) '${Std.int(stateList.get(r, 8))},${Std.int(stateList.get(r, 9))},${Std.int(stateList.get(r, 10))}'];
		}
		var rest = fills();
		ashui.input.Pointer.move(stateTree, 20, 20);
		var hovered = fills();
		ashui.input.Pointer.move(stateTree, 90, 90);
		var left = fills();
		check(":hover applies while hovered, to the element and through a combinator",
			rest.join("|") == "1,0,0|0,0,0" && hovered.join("|") == "0,1,0|0,0,1" && left.join("|") == "1,0,0|0,0,0", [rest, hovered, left]);
		ashui.css.Css.remove(stateSheet);

		// --- CSS theme variables: var(--primary) follows the scheme ---
		var themeSheet = ashui.css.Css.load('.themed { width: 10px; height: 10px; background: var(--primary); }');
		var themeTree = new LayoutTree();
		var themed = Owner.root(themeTree, _ -> new Div({classes: ["themed"]}, themeTree));
		var themeList = new ashui.layout.DisplayList();
		function red():Float {
			themeTree.flush();
			themeTree.computeLayout(themed.node, 50, 50);
			themeList.update(themeTree, themed.node);
			return themeList.count == 0 ? -1 : themeList.get(0, 8);
		}
		var light = red();
		ashui.theme.ThemeState.get().setScheme(Dark);
		var darkRed = red();
		ashui.theme.ThemeState.get().setScheme(Light);
		var back = red();
		var expect = ashui.theme.ThemeState.get().color(Primary).r;
		check("var() reads a theme token, and follows a scheme switch", Math.abs(light - expect) < 0.01 && Math.abs(darkRed - light) > 0.05
			&& Math.abs(back - light) < 0.01, [light, darkRed, back, expect]);
		ashui.css.Css.remove(themeSheet);

		// --- CSS @media follows the viewport ---
		var mediaSheet = ashui.css.Css.load('
			.box { width: 10px; height: 10px; }
			@media (min-width: 600px) { .box { width: 30px; } }
			.box { @media (max-height: 300px) { height: 5px } }
		');
		var mediaTree = new LayoutTree();
		var box = Owner.root(mediaTree, _ -> new Div({classes: ["box"]}, mediaTree));
		function sizeAt(w:Float, h:Float) {
			ashui.css.Css.setViewport(w, h);
			mediaTree.flush();
			mediaTree.computeLayout(box.node, 1000, 1000);
			var b = mediaTree.getBounds(box.node);
			return '${Std.int(b.width)}x${Std.int(b.height)}';
		}
		var sizes = [sizeAt(400, 800), sizeAt(800, 800), sizeAt(800, 200), sizeAt(400, 800)];
		check("@media rules apply while their queries hold, nested ones too", sizes.join(",") == "10x10,30x10,30x5,10x10", sizes);
		ashui.css.Css.remove(mediaSheet);

		// --- CSS transitions and @keyframes ---
		var motionSheet = ashui.css.Css.load('
			.fade { width: 10px; height: 10px; background: #ff0000; opacity: 1; transition: opacity 100ms linear; }
			.fade.out { opacity: 0; }
			@keyframes grow { from { width: 10px } to { width: 110px } }
			.grow { height: 10px; width: 10px; animation: grow 1s linear; }
			.held { height: 10px; width: 10px; animation: grow 1s linear forwards; }
		');
		var motionTree = new LayoutTree();
		var motionList = new ashui.layout.DisplayList();
		var fadeClasses = Signal.make(["fade"]);
		var fading = Owner.root(motionTree, _ -> new Div({classes: fadeClasses}, motionTree));
		function alpha():Float {
			motionTree.flush();
			motionTree.computeLayout(fading.node, 50, 50);
			motionList.update(motionTree, fading.node);
			return motionList.count == 0 ? -1 : motionList.get(0, 11);
		}
		var scheduler = ashui.animation.AnimationScheduler.main;
		var before = alpha();
		fadeClasses.set(["fade", "out"]);
		alpha();
		scheduler.tick(0.05);
		var midway = alpha();
		scheduler.tick(0.1);
		var after = alpha();
		// Fully transparent, the box draws nothing: no record at all.
		check("a transition moves a property the cascade changes", before == 1 && midway > 0.3 && midway < 0.7 && after <= 0, [before, midway, after]);

		var growing = Owner.root(motionTree, _ -> new Div({classes: ["grow"]}, motionTree));
		var held = Owner.root(motionTree, _ -> new Div({classes: ["held"]}, motionTree));
		function widths():Array<Int> {
			motionTree.flush();
			motionTree.computeLayout(growing.node, 500, 500);
			var a = Std.int(motionTree.getBounds(growing.node).width);
			motionTree.computeLayout(held.node, 500, 500);
			return [a, Std.int(motionTree.getBounds(held.node).width)];
		}
		var start = widths();
		scheduler.tick(0.5);
		var half = widths();
		scheduler.tick(0.6);
		var done = widths();
		check("@keyframes animates, then hands back to the cascade, or holds with forwards", start.join(",") == "10,10" && half.join(",") == "60,60"
			&& done.join(",") == "10,110", [start, half, done]);
		check("keyframe values interpolate: none as the identity, colours by channel, unlike shapes switch halfway",
			ashui.css.CssMotion.interpolate("none", "rotate(360deg)", 0.25) == "rotate(90deg)"
			&& ashui.css.CssMotion.interpolate("red", "blue", 0.5) == "rgba(127.5, 0, 127.5, 1)"
			&& ashui.css.CssMotion.interpolate("block", "flex", 0.4) == "block" && ashui.css.CssMotion.interpolate("block", "flex", 0.6) == "flex",
			[ashui.css.CssMotion.interpolate("none", "rotate(360deg)", 0.25), ashui.css.CssMotion.interpolate("red", "blue", 0.5)]);
		ashui.css.Css.remove(motionSheet);

		// --- CSS pointer queries: a property reads env(pointer-x) ---
		var pointerSheet = ashui.css.Css.load('
			.tilt { width: 100px; height: 100px; background: #ff0000; pointer-origin: top-left; pointer-range: 0 1;
				opacity: calc(0.25 + env(pointer-x) * 0.5); }
		');
		var pointerTree = new LayoutTree();
		var tilt = Owner.root(pointerTree, _ -> new Div({classes: ["tilt"]}, pointerTree));
		var pointerList = new ashui.layout.DisplayList();
		function tiltAlpha():Float {
			pointerTree.flush();
			pointerTree.computeLayout(tilt.node, 200, 200);
			pointerList.update(pointerTree, tilt.node);
			return pointerList.count == 0 ? -1 : Math.round(pointerList.get(0, 11) * 100) / 100;
		}
		tiltAlpha();
		ashui.input.Pointer.move(pointerTree, 0, 50);
		var leftEdge = tiltAlpha();
		ashui.input.Pointer.move(pointerTree, 100, 50);
		var rightEdge = tiltAlpha();
		ashui.input.Pointer.move(pointerTree, 50, 50);
		var middle = tiltAlpha();
		check("a declaration reading env(pointer-x) follows the pointer", leftEdge == 0.25 && rightEdge == 0.75 && middle == 0.5, [leftEdge, middle, rightEdge]);
		var tiltIdentity = ashui.css.Identity.of(pointerTree, tilt.node.id);
		@:privateAccess var tracked = ashui.css.Css.applied.exists(tiltIdentity) && ashui.css.PointerQueries.trackers.exists(tiltIdentity);
		tilt.remove();
		@:privateAccess check("a removed element leaves the stylesheet engine", tracked && !ashui.css.Css.applied.exists(tiltIdentity)
			&& !ashui.css.PointerQueries.trackers.exists(tiltIdentity));
		ashui.css.Css.remove(pointerSheet);

		// --- CSS files: loaded, and read again when they change ---
		var cssPath = "live.css";
		sys.io.File.saveContent(cssPath, ".live { width: 10px; height: 10px; }");
		var fileSheet = ashui.css.Css.loadFile(cssPath);
		var fileTree = new LayoutTree();
		var live = Owner.root(fileTree, _ -> new Div({classes: ["live"]}, fileTree));
		function liveWidth():Int {
			fileTree.flush();
			fileTree.computeLayout(live.node, 100, 100);
			return Std.int(fileTree.getBounds(live.node).width);
		}
		var firstWidth = liveWidth();
		check("Css.loadFile puts a file in force", firstWidth == 10, firstWidth);
		ashui.css.Css.remove(fileSheet);

		ashui.css.Css.remove(sheet);
		var after = boundsOf(card);
		check("a sheet taken out of force takes its values with it", fillOf(card).length == 0 && after.width == 0, [fillOf(card), after]);

		// --- Transform classes compose into one transform; hover: on top ---
		var turnTree = new LayoutTree();
		var turned:Div = Owner.root(turnTree, _ -> hxx('
			<div class="w-10 h-10 bg-primary translate-x-2 rotate-90 hover:scale-150" />
		'));
		turnTree.flush();
		turnTree.computeLayout(turned.node, 100, 100);
		var turnList = new ashui.layout.DisplayList();
		turnList.update(turnTree, turned.node);
		// A quarter turn about the centre (20, 20), moved 8 right: the top-left lands at (48, 0).
		var aff = [for (f in 60...64) turnList.get(0, f)];
		check("transform classes compose and turn the box about its centre",
			Math.abs(turnList.get(0, 0) - 48) < 1e-3 && Math.abs(turnList.get(0, 1)) < 1e-3 && Math.abs(aff[0]) < 1e-6 && Math.abs(aff[1] - 1) < 1e-6
			&& Math.abs(aff[2] + 1) < 1e-6 && Math.abs(aff[3]) < 1e-6,
			[turnList.get(0, 0), turnList.get(0, 1)].concat(aff));
		ashui.input.Pointer.move(turnTree, 20, 20);
		turnTree.flush();
		turnList.update(turnTree, turned.node);
		check("hover: scales the transform", Math.abs(turnList.get(0, 61) - 1.5) < 1e-6, turnList.get(0, 61));

		// --- animate-spin turns a full circle a second ---
		var spinTree = new LayoutTree();
		var spinner:Div = Owner.root(spinTree, _ -> hxx('<div class="w-10 h-10 bg-primary animate-spin" />'));
		spinTree.flush();
		spinTree.computeLayout(spinner.node, 100, 100);
		ashui.animation.AnimationScheduler.main.tick(0.25);
		spinTree.flush();
		var spinList = new ashui.layout.DisplayList();
		spinList.update(spinTree, spinner.node);
		check("animate-spin is a quarter turn after a quarter second", Math.abs(spinList.get(0, 61) - 1) < 1e-4, spinList.get(0, 61));

		// --- Transitions move a property to its new value over time ---
		ashui.theme.ThemeState.get().setScheduler(null);
		var moveTree = new LayoutTree();
		var fading = Signal.make((1 : Single));
		var moving = Owner.root(moveTree, _ -> new Div({width: 20, height: 20,
			style: ashui.style.Tw.tw("transition duration-200 ease-linear bg-surface"), opacity: fading}));
		moveTree.flush();
		moveTree.computeLayout(moving.node, 20, 20);
		var moveList = new ashui.layout.DisplayList();
		function fillAndOpacity() {
			moveTree.flush();
			moveList.update(moveTree, moving.node);
			return [moveList.get(0, 8), moveList.get(0, 11)];
		}
		var settled = fillAndOpacity();
		ashui.theme.ThemeState.get().setScheme(Dark);
		fading.set(0.2);
		moveTree.flush();
		ashui.animation.AnimationScheduler.main.tick(0.1);
		var midway = fillAndOpacity();
		ashui.animation.AnimationScheduler.main.tick(0.15);
		var done = fillAndOpacity();
		ashui.theme.ThemeState.get().setScheme(Light);
		moveTree.flush();
		ashui.animation.AnimationScheduler.main.tick(1);
		check("a transitioned colour moves to its new value over the duration",
			settled[0] == 1 && Math.abs(midway[0] - (1 + 0x1A / 255) / 2) < 0.02 && Math.abs(done[0] - 0x1A / 255) < 0.01, [settled[0], midway[0], done[0]]);
		check("a transitioned number follows its signal over the duration",
			settled[1] == 1 && Math.abs(midway[1] - 0.6) < 0.02 && Math.abs(done[1] - 0.2) < 1e-6, [settled[1], midway[1], done[1]]);

		// --- During a scheme transition a transitioned colour follows the theme's own animation ---
		var schemeTheme = ashui.theme.ThemeState.get();
		var clock = ashui.animation.AnimationScheduler.main;
		schemeTheme.setScheduler(clock);
		var keepTree = new LayoutTree();
		var keeping:Div = Owner.root(keepTree, _ -> hxx('<div class="w-5 h-5 bg-primary transition-colors duration-500 ease-linear" />'));
		keepTree.flush();
		keepTree.computeLayout(keeping.node, 20, 20);
		var keepList = new ashui.layout.DisplayList();
		schemeTheme.setScheme(Dark);
		var steps = 0;
		var behind = 0.0;
		while (schemeTheme.isAnimating() && steps++ < 600) {
			clock.tick(1 / 60);
			schemeTheme.tick();
			keepTree.flush();
			keepList.update(keepTree, keeping.node);
			behind = Math.max(behind, Math.abs(keepList.get(0, 8) - schemeTheme.color(Primary).r));
		}
		check("a transitioned colour keeps up with a scheme transition instead of trailing it", steps > 5 && behind < 3 / 255, [behind, steps]);
		schemeTheme.setScheduler(null);
		schemeTheme.setScheme(Light);
		keepTree.flush();
		clock.tick(1);

		// --- Trees share no node ids: a late tree's bindings are its own ---
		var lateTheme = ashui.theme.ThemeState.get();
		lateTheme.setScheduler(clock);
		var lateTree = new LayoutTree();
		var late:Div = Owner.root(lateTree, _ -> hxx('<div class="w-5 h-5 bg-primary hover:bg-primary-hover" />'));
		lateTree.flush();
		lateTree.computeLayout(late.node, 20, 20);
		var lateList = new ashui.layout.DisplayList();
		ashui.input.Interaction.of(late.node).hovered.set(true);
		lateTree.flush();
		lateTheme.setScheme(Dark);
		var lateBehind = 0.0;
		var lateSteps = 0;
		while (lateTheme.isAnimating() && lateSteps++ < 600) {
			clock.tick(1 / 60);
			lateTheme.tick();
			lateTree.flush();
			lateList.update(lateTree, late.node);
			lateBehind = Math.max(lateBehind, Math.abs(lateList.get(0, 8) - lateTheme.color(PrimaryHover).r));
		}
		check("a node in one of many trees draws only its own bindings, through a scheme transition", lateSteps > 5 && lateBehind < 3 / 255,
			[lateBehind, lateSteps]);
		lateTheme.setScheduler(null);
		lateTheme.setScheme(Light);
		lateTree.flush();

		// --- A text field edits its value from keys, text and the pointer ---
		var fieldTree = new LayoutTree();
		var fieldValue = Signal.make("");
		var submitted = "";
		var field:ashui.ui.TextField = Owner.root(fieldTree, _ -> new ashui.ui.TextField({value: fieldValue, onSubmit: v -> submitted = v}));
		fieldTree.flush();
		fieldTree.computeLayout(field.node, 300, 60);
		fieldTree.flush();
		fieldTree.computeLayout(field.node, 300, 60);
		function fieldKey(k:window.Key, code:window.KeyCode, ?mods:window.Modifiers)
			ashui.input.Keyboard.input(fieldTree, Input(Code(code), k, None, Standard, Pressed, false, Unavailable), mods);
		var none:window.Modifiers = State(false, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown);
		var shift:window.Modifiers = State(true, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown);
		var alt:window.Modifiers = State(false, false, true, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown);
		var cmd:window.Modifiers = State(false, false, false, true, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown);
		fieldKey(Named(Tab), Tab);
		check("text field: Tab focuses it", ashui.input.Focus.of(fieldTree) != null && ashui.input.Focus.of(fieldTree).node == field.node);
		ashui.input.Keyboard.text(fieldTree, "hello world");
		check("text field: typed text goes into its value", fieldValue.get() == "hello world", fieldValue.get());
		fieldKey(Named(Backspace), Backspace, alt);
		check("text field: Alt+Backspace deletes the word before the caret", fieldValue.get() == "hello ", fieldValue.get());
		ashui.input.Keyboard.text(fieldTree, "there");
		fieldKey(Named(ArrowLeft), ArrowLeft, alt);
		fieldKey(Named(ArrowLeft), ArrowLeft);
		ashui.input.Keyboard.text(fieldTree, ",");
		check("text field: arrows move by word and by character", fieldValue.get() == "hello, there", fieldValue.get());
		fieldKey(Named(End), End);
		fieldKey(Named(ArrowLeft), ArrowLeft, shift);
		fieldKey(Named(ArrowLeft), ArrowLeft, shift);
		ashui.input.Keyboard.text(fieldTree, "!");
		check("text field: Shift selects and typing replaces the selection", fieldValue.get() == "hello, the!", fieldValue.get());
		fieldKey(Character("a"), KeyA, cmd);
		fieldKey(Named(Delete), Delete);
		check("text field: Command+A then Delete empties it", fieldValue.get() == "", fieldValue.get());
		ashui.input.Keyboard.text(fieldTree, "go");
		fieldKey(Named(Enter), Enter);
		check("text field: Enter submits the value and does not click", submitted == "go", submitted);
		fieldTree.flush();
		fieldTree.computeLayout(field.node, 300, 60);
		var stops = field.editing.stopsFor("abc");
		check("text field: the text engine gives a caret stop per character and the end", stops.length == 4 && stops[0].x == 0
			&& stops[1].x > 0 && stops[3].x > stops[2].x, stops);
		var fieldBounds = fieldTree.getBounds(@:privateAccess field.text.node);
		var goStops = field.editing.stopsFor("go");
		ashui.input.Pointer.move(fieldTree, fieldBounds.x + goStops[1].x + 0.5, fieldBounds.y + 5);
		ashui.input.Pointer.press(fieldTree);
		ashui.input.Pointer.release(fieldTree);
		ashui.input.Keyboard.text(fieldTree, "-");
		check("text field: a click places the caret at the nearest character boundary", fieldValue.get() == "g-o", fieldValue.get());
		fieldKey(Character("a"), KeyA, cmd);
		fieldKey(Character("c"), KeyC, cmd);
		fieldKey(Named(End), End);
		fieldKey(Character("v"), KeyV, cmd);
		check("text field: Command+C copies the selection and Command+V pastes it", fieldValue.get() == "g-og-o", fieldValue.get());
		fieldKey(Named(Home), Home);
		fieldKey(Named(ArrowRight), ArrowRight, shift);
		fieldKey(Character("x"), KeyX, cmd);
		check("text field: Command+X cuts the selection", fieldValue.get() == "-og-o" && ashui.input.Clipboard.text() == "g",
			[fieldValue.get(), ashui.input.Clipboard.text()]);
		ashui.input.Clipboard.write([
			{type: "text/html", data: haxe.io.Bytes.ofString("<b>bold</b>")},
			{type: "text/plain", data: haxe.io.Bytes.ofString("bold")}
		]);
		check("clipboard: one copy holds several types, best first, and text reads text/plain",
			ashui.input.Clipboard.types().join(",") == "text/html,text/plain" && ashui.input.Clipboard.data("text/html").toString() == "<b>bold</b>"
			&& ashui.input.Clipboard.text() == "bold" && ashui.input.Clipboard.data("image/png") == null,
			ashui.input.Clipboard.types());
		ashui.input.Clipboard.setText("a\nb");
		check("clipboard: setting text replaces every type", ashui.input.Clipboard.types().join(",") == "text/plain", ashui.input.Clipboard.types());
		fieldKey(Character("v"), KeyV, cmd);
		check("text field: a pasted line break becomes a space", fieldValue.get() == "a b-og-o", fieldValue.get());
		fieldTree.flush();
		var blinkingFocused = field.editing.blinking();
		ashui.input.WindowState.active.set(false);
		fieldTree.flush();
		var stoppedInBackground = !field.editing.blinking();
		ashui.input.WindowState.active.set(true);
		ashui.input.WindowState.visible.set(false);
		fieldTree.flush();
		var stoppedHidden = !field.editing.blinking();
		ashui.input.WindowState.visible.set(true);
		fieldTree.flush();
		check("text field: the caret stops blinking while the window is in the background or hidden, and starts again",
			blinkingFocused && stoppedInBackground && stoppedHidden && field.editing.blinking(),
			[blinkingFocused, stoppedInBackground, stoppedHidden]);

		// --- Scroll containers move their content under the wheel ---
		var scrollTree = new LayoutTree();
		var clicked = -1;
		var rows:Array<Div> = [];
		var outerList:Div = null;
		var innerList:Div = null;
		var scroller:Div = Owner.root(scrollTree, _ -> {
			for (i in 0...10) {
				var n = i;
				rows.push(hxx('<div class="shrink-0 bg-surface" height={30} onClick={() -> clicked = n} />'));
			}
			innerList = hxx('<div class="flex flex-col shrink-0 overflow-y-auto" height={60}>
				<div class="shrink-0" height={50} />
				<div class="shrink-0" height={50} />
			</div>');
			outerList = hxx('<div class="flex flex-col overflow-y-auto" width={100} height={100}>${rows}</div>');
			outerList.appendChild(innerList);
			outerList;
		});
		scrollTree.flush();
		scrollTree.computeLayout(scroller.node, 100, 100);
		var outerScroll = ashui.input.Scroll.of(outerList.node);
		var innerScroll = ashui.input.Scroll.of(innerList.node);
		check("scroll: the classes make scroll containers", outerScroll != null && innerScroll != null);
		check("scroll: how far a container can scroll is its content beyond its view", outerScroll.limits().y == 260 && innerScroll.limits().y == 40,
			[outerScroll.limits(), innerScroll.limits()]);
		ashui.input.Pointer.move(scrollTree, 50, 50);
		ashui.input.Pointer.wheel(scrollTree, 0, -45);
		scrollTree.flush();
		var scrollList = new ashui.layout.DisplayList();
		scrollList.update(scrollTree, scroller.node);
		var firstRowY = scrollList.get(0, 1);
		for (r in 0...scrollList.count)
			if (scrollList.kind(r) == 0 && scrollList.get(r, 3) == 30) {
				firstRowY = scrollList.get(r, 1);
				break;
			}
		check("scroll: the wheel moves the offset and the content with it", outerScroll.y.get() == 45 && firstRowY == -45, [outerScroll.y.get(), firstRowY]);
		clicked = -1;
		ashui.input.Pointer.move(scrollTree, 50, 20);
		ashui.input.Pointer.press(scrollTree);
		ashui.input.Pointer.release(scrollTree);
		check("scroll: a click lands on the row now under the pointer", clicked == 2, clicked);
		ashui.input.Pointer.wheel(scrollTree, 0, 1000);
		check("scroll: the offset stops at the start", outerScroll.y.get() == 0, outerScroll.y.get());
		ashui.input.Pointer.wheel(scrollTree, 0, -1000);
		check("scroll: and at the end", outerScroll.y.get() == 260, outerScroll.y.get());
		scrollTree.flush();
		// The inner list now fills the view's last 60 units: wheel over it, past its own end.
		ashui.input.Pointer.move(scrollTree, 50, 70);
		ashui.input.Pointer.wheel(scrollTree, 0, 30);
		check("scroll: the innermost container under the pointer takes the wheel", innerScroll.y.get() == 0 && outerScroll.y.get() == 230,
			[innerScroll.y.get(), outerScroll.y.get()]);
		scrollTree.flush();
		ashui.input.Pointer.move(scrollTree, 50, 90);
		ashui.input.Pointer.wheel(scrollTree, 0, -30);
		var innerFirst = innerScroll.y.get();
		ashui.input.Pointer.wheel(scrollTree, 0, -30);
		check("scroll: an inner container takes the wheel until its edge, then it goes on",
			innerFirst == 30 && innerScroll.y.get() == 40 && outerScroll.y.get() == 230, [innerFirst, innerScroll.y.get(), outerScroll.y.get()]);

		// --- Timers wake the loop when due, and are not animation ---
		var timerClock = new ashui.animation.AnimationScheduler();
		var rang = 0;
		// On the scheduler's clock: what its ticks add up to.
		timerClock.after(0.2, () -> rang++);
		var cancelled = timerClock.after(0.2, () -> rang += 10);
		cancelled.cancel();
		var waitFor = timerClock.untilNextTimer();
		var idle = !timerClock.hasActive();
		timerClock.tick(0.001);
		var early = rang;
		timerClock.tick(0.25);
		check("timers: due at their time, not before, cancelled ones never, and not counted as animation",
			waitFor != null && waitFor > 0.1 && waitFor <= 0.2 && idle && early == 0 && rang == 1 && timerClock.untilNextTimer() == null,
			[waitFor, idle, early, rang]);

		// --- A text area edits lines: wrapping, Up and Down, per-line selection, scrolling ---
		var areaTree = new LayoutTree();
		var areaValue = Signal.make("");
		var areaSubmitted = "";
		var area:ashui.ui.TextArea = Owner.root(areaTree, _ -> new ashui.ui.TextArea({value: areaValue, width: 200, height: 80,
			onSubmit: v -> areaSubmitted = v}));
		function areaLayout() {
			areaTree.flush();
			areaTree.computeLayout(area.node, 300, 200);
			areaTree.flush();
		}
		areaLayout();
		function areaKey(k:window.Key, code:window.KeyCode, ?mods:window.Modifiers)
			ashui.input.Keyboard.input(areaTree, Input(Code(code), k, None, Standard, Pressed, false, Unavailable), mods);
		ashui.input.Focus.set(ashui.input.Interaction.of(area.node), true);
		var ed = area.editing;
		ashui.input.Keyboard.text(areaTree, "abcdef");
		areaKey(Named(Enter), Enter);
		ashui.input.Keyboard.text(areaTree, "xy");
		check("text area: Enter starts a new line", areaValue.get() == "abcdef\nxy", areaValue.get());
		areaKey(Named(ArrowUp), ArrowUp);
		var upAt = ed.caret.get();
		areaKey(Named(ArrowDown), ArrowDown);
		check("text area: Up and Down move between lines keeping to the same x", upAt == 2 && ed.caret.get() == 9, [upAt, ed.caret.get()]);
		areaKey(Named(ArrowUp), ArrowUp);
		areaKey(Named(End), End);
		check("text area: End goes to the end of the line", ed.caret.get() == 6, ed.caret.get());
		areaKey(Named(ArrowDown), ArrowDown);
		areaKey(Named(Home), Home);
		check("text area: Home goes to the start of the line", ed.caret.get() == 7, ed.caret.get());
		areaKey(Named(ArrowUp), ArrowUp, shift);
		areaKey(Named(Home), Home, shift);
		var rects = @:privateAccess area.selectionRects(ed.caret.get(), ed.anchor.get(), areaValue.get());
		check("text area: a selection over two lines is drawn as two rects", rects.length == 2 && rects[1].y > rects[0].y, rects);
		areaValue.set("");
		ed.caret.set(0);
		ed.anchor.set(0);
		ashui.input.Keyboard.text(areaTree, "the quick brown fox jumps over the lazy dog and keeps running far away");
		areaLayout();
		var wrapped = ed.stopsFor(areaValue.get());
		var lastLine = wrapped[wrapped.length - 1].line;
		check("text area: long text wraps at the area's width", lastLine >= 2 && ed.lines == lastLine + 1, [lastLine, ed.lines]);
		var areaText = @:privateAccess area.text;
		var textBounds = areaTree.getBounds(areaText.node);
		ashui.input.Pointer.move(areaTree, textBounds.x + 2, textBounds.y + ed.lineHeight * 1.5);
		ashui.input.Pointer.press(areaTree);
		ashui.input.Pointer.release(areaTree);
		check("text area: a click on the second line puts the caret there", ed.stopAt(ed.caret.get(), areaValue.get()).line == 1,
			ed.stopAt(ed.caret.get(), areaValue.get()));
		areaKey(Named(End), End, cmd);
		for (i in 0...6) {
			areaKey(Named(Enter), Enter);
			ashui.input.Keyboard.text(areaTree, "line " + i);
		}
		areaLayout();
		var areaScroll = ashui.input.Scroll.of(area.node);
		check("text area: typing past the bottom scrolls the caret into view", areaScroll != null && areaScroll.y.get() > 0,
			areaScroll == null ? null : areaScroll.y.get());
		areaKey(Named(Enter), Enter, cmd);
		check("text area: Command+Enter submits, Enter alone does not", areaSubmitted == areaValue.get() && areaSubmitted.indexOf("line 5") > 0);
		areaValue.set("first para here\nsecond para here");
		ed.caret.set(0);
		ed.anchor.set(0);
		areaLayout();
		var tb = areaTree.getBounds(areaText.node);
		var scrollY = areaScroll.y.get();
		var wordX = tb.x + ed.stopAt(8, areaValue.get()).x + 1;
		var wordY = tb.y - scrollY + ed.lineHeight * 0.5;
		ashui.input.Pointer.move(areaTree, wordX, wordY);
		ashui.input.Pointer.press(areaTree);
		ashui.input.Pointer.release(areaTree);
		ashui.input.Pointer.press(areaTree);
		ashui.input.Pointer.release(areaTree);
		check("text area: a double-click selects the word", ed.selection() == "para", ed.selection());
		ashui.input.Pointer.press(areaTree);
		ashui.input.Pointer.release(areaTree);
		check("text area: a triple-click selects the paragraph", ed.selection() == "first para here", ed.selection());
		ashui.input.Keyboard.composition(areaTree, "かな", 1);
		areaTree.flush();
		check("text area: a composition shows in place of the selection without changing the value",
			areaValue.get() == "first para here\nsecond para here" && ed.display() == "かな\nsecond para here" && ed.displayCaret() == 1,
			[ed.display(), ed.displayCaret()]);
		ashui.input.Keyboard.composition(areaTree, "", -1);
		ashui.input.Keyboard.text(areaTree, "仮名");
		check("text area: the committed text replaces the selection", areaValue.get() == "仮名\nsecond para here", areaValue.get());
		areaTree.flush();
		var published = ashui.input.WindowState.textCaret.get();
		ashui.input.Focus.clear(areaTree);
		areaTree.flush();
		check("text area: its caret is published for the input method while focused, and not after",
			published != null && published.height > 0 && ashui.input.WindowState.textCaret.get() == null, published);

		// --- SVG is read in Haxe: compact path data, shapes, paint, transforms ---
		var compact = ashui.svg.PathData.parse("M.5-1.5.5.5l1 1h2V4c1 1 2 2 3 3s4 4 5 5q1 0 2 2t3 3a1 1 0 01 1 1z");
		check("path data: compact numbers and implicit lines", compact[0].equals(MoveTo(0.5, -1.5)) && compact[1].equals(LineTo(0.5, 0.5)),
			compact.slice(0, 2));
		check("path data: relative, horizontal and vertical steps", compact[2].equals(LineTo(1.5, 1.5)) && compact[3].equals(LineTo(3.5, 1.5))
			&& compact[4].equals(LineTo(3.5, 4)), compact.slice(2, 5));
		check("path data: S reflects the last control point", compact[6].equals(CubicTo(7.5, 8, 10.5, 11, 11.5, 12)), compact[6]);
		check("path data: T reflects the last quadratic control point", compact[8].equals(QuadTo(14.5, 16, 16.5, 17)), compact[8]);
		check("path data: arc flags run into the next number", compact[9].equals(ArcTo(1, 1, 0, false, true, 17.5, 18)), compact[9]);
		check("path data: Z returns to the subpath start", compact[10].equals(Close), compact[10]);
		var pathError = try {
			ashui.svg.PathData.parse("M 0 0 L 5");
			"";
		} catch (e:ashui.svg.SvgError) e.message;
		check("path data: a cut-off command is an error", pathError.indexOf("ends in the middle") >= 0, pathError);
		var square = ashui.svg.PathData.flatten(ashui.svg.PathData.parse("M0 0L10 0L10 10"));
		check("path data: flattened subpaths close on their first point", square.length == 1 && square[0].join(",") == "0,0,10,0,10,10,0,0",
			square);
		var halfCircle = ashui.svg.PathData.flatten(ashui.svg.PathData.parse("M10 0A10 10 0 0 1 -10 0Z"))[0];
		var onCircle = true, lowest = 0.0;
		for (i in 0...Std.int(halfCircle.length / 2) - 1) {
			var px = halfCircle[i * 2], py = halfCircle[i * 2 + 1];
			onCircle = onCircle && Math.abs(Math.sqrt(px * px + py * py) - 10) < 0.01;
			lowest = Math.max(lowest, py);
		}
		check("path data: an arc flattens onto its circle, by its sweep", onCircle && Math.abs(lowest - 10) < 0.2, [onCircle, lowest]);
		var badge = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 10 10" width="20"><g fill="#ff0000" stroke="rgb(0, 0, 255)" opacity="0.5" transform="translate(1 2) scale(2)"><rect x="1" y="1" width="4" height="2" rx="1"/><circle style="fill: none" cx="5" cy="5" r="2"/></g><title>t</title></svg>');
		check("svg: natural size from width, and viewBox height", badge.width == 20 && badge.height == 10, [badge.width, badge.height]);
		switch badge.nodes {
			case [Group(opacity, transform, [Shape(rect), Shape(circle)])]:
				check("svg: groups keep their opacity and transform", opacity == 0.5 && transform.join(",") == "2,0,0,2,1,2", [opacity, transform]);
				check("svg: paint passes down to shapes", rect.fill.equals(Solid(0xff0000, 1)) && rect.stroke.equals(Solid(0x0000ff, 1)), rect);
				check("svg: style declarations win over inherited paint", circle.fill.equals(NoPaint), circle.fill);
				check("svg: a rounded rect becomes arcs", rect.path.length == 10 && rect.path[2].match(ArcTo(1, 1, 0, false, true, 5, 2)), rect.path);
			case other:
				check("svg: one group of a rect and a circle", false, other);
		}
		check("svg: fixed colours are not a mask", !badge.mask);
		var icon = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="m4 12 5 5L20 6"/></svg>');
		check("svg: currentColor alone is a mask", icon.mask);
		check("svg: the same SVG, attributes in any order, is one document",
			ashui.svg.SvgDocument.parse('<svg stroke="currentColor" fill="none" viewBox="0 0 24 24"><!-- tick --><path d="m4 12 5 5L20 6"/></svg>') == icon);
		var compiled = ashui.svg.SvgDocument.of(<svg viewBox="0 0 24 24" fill="none" stroke="currentColor"><path d="m4 12 5 5L20 6"/></svg>);
		check("svg: inline markup compiles to the same document", compiled == icon);
		var rich = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 10 10" xmlns:xlink="http://www.w3.org/1999/xlink"><defs><linearGradient id="g"><stop offset="0" stop-color="red"/></linearGradient></defs><rect id="r" width="1" height="1" fill="url(#g)"/><use xlink:href="#r" x="2"/><text x="1" y="9" fill="chartreuse">Hi &amp; bye</text></svg>');
		switch rich.nodes {
			case [OtherElement("defs", [OtherElement("linearGradient", _)]), Shape(gradientRect), OtherElement("use", []), OtherElement("text", [])]:
				check("svg: a gradient paint is kept as it is written", gradientRect.fill.equals(Other("url(#g)")), gradientRect.fill);
			case other:
				check("svg: gradients, <use> and text are kept as other elements", false, other);
		}
		check("svg: a document with elements outside the model is not a mask", !rich.mask);
		check("svg: the markup rendered is the SVG as written, text and links included",
			rich.markup.indexOf("Hi &amp; bye</text>") > 0 && rich.markup.indexOf('xlink:href="#r"') > 0 && rich.markup.indexOf('fill="chartreuse"') > 0,
			rich.markup);
		var plain = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 1 1"><use xlink:href="#a"/></svg>');
		check("svg: the SVG and XLink namespaces are declared for the renderer",
			StringTools.startsWith(plain.markup, '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox'), plain.markup);
		check("svg: currentColor is given the element's colour on the root",
			StringTools.startsWith(icon.withColor("#123456"), '<svg color="#123456" xmlns='), icon.withColor("#123456"));
		var ownColor = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 1 1" color="red"><rect width="1" height="1" fill="currentColor"/></svg>');
		check("svg: an SVG with a colour of its own keeps it, and is not a mask",
			ownColor.withColor("#123456") == ownColor.markup && !ownColor.mask);
		var lenient = ashui.svg.SvgDocument.parse('<svg width="2in" height="1em"><rect width="1" height="1" fill-rule="inherit" transform="skewX(10) frobnicate(2)"/></svg>');
		check("svg: units are converted, and values this model does not read are left to the renderer",
			lenient.width == 192 && lenient.height == 150, [lenient.width, lenient.height]);
		var svgTree = new LayoutTree();
		var svgElement:ashui.ui.Svg = Owner.root(svgTree, _ -> hxx('<svg class="w-6" viewBox="0 0 48 24"><path d="M0 0h48v24z"/></svg>'));
		svgTree.flush();
		svgTree.computeLayout(svgElement.node, 400, 400);
		var svgBounds = svgTree.getBounds(svgElement.node);
		check("svg in hxx: classes size it, the document gives the rest", svgBounds != null && near(svgBounds.width, 24) && near(svgBounds.height, 24),
			svgBounds);

		// --- Input: hit-testing as drawn, bubbling, focus, keys ---
		var log:Array<String> = [];
		function note(name:String)
			return (e:ashui.input.Events.PointerEvent) -> log.push(name);
		var inputTree = new LayoutTree();
		var turned:Div = null, pane:Div = null, inner:Div = null, top:Div = null, off:Div = null, first:Div = null, second:Div = null;
		var page:Div = Owner.root(inputTree, _ -> hxx('
			<div width={200} height={200} onClick={note("page")}>
				${pane = hxx('<div class="absolute" left={10} top={10} width={50} height={50} focusable={true} onClick={note("pane")}>
					${inner = hxx('<div class="absolute" left={0} top={0} width={20} height={20} onClick={e -> log.push("inner " + e.localX + "," + e.localY)} />')}
				</div>')}
				${top = hxx('<div class="absolute" left={40} top={40} width={50} height={50} onClick={e -> { log.push("top"); e.stopPropagation(); }} />')}
				${turned = hxx('<div class="absolute rotate-45" left={120} top={20} width={40} height={40} onClick={note("turned")} />')}
				${off = hxx('<div class="absolute" left={10} top={120} width={30} height={30} disabled={true} focusable={true} onClick={note("off")} />')}
				${first = hxx('<div class="absolute" left={60} top={120} width={20} height={20} focusable={true} onClick={note("first")} />')}
				${second = hxx('<div class="absolute" left={100} top={120} width={20} height={20} focusable={true} />')}
			</div>
		'));
		inputTree.flush();
		inputTree.computeLayout(page.node, 200, 200);
		function click(x:Float, y:Float) {
			log = [];
			ashui.input.Pointer.move(inputTree, x, y);
			ashui.input.Pointer.press(inputTree);
			ashui.input.Pointer.release(inputTree);
			return log.join(" ");
		}
		check("input: a click bubbles from the topmost node, with local points", click(15, 15) == "inner 5,5 pane page", log);
		check("input: the node drawn on top takes the click, and can stop it", click(45, 45) == "top", log);
		check("input: hit-testing goes through transforms", click(140, 40) == "turned page" && click(121, 21) == "page", log);
		check("input: a disabled node takes no click", click(20, 130) == "", log);
		log = [];
		ashui.input.Pointer.move(inputTree, 15, 15);
		ashui.input.Pointer.press(inputTree);
		ashui.input.Pointer.move(inputTree, 100, 180);
		ashui.input.Pointer.release(inputTree);
		check("input: press and release apart click their nearest common node", log.join(" ") == "page", log);
		var paneState = ashui.input.Interaction.of(pane.node);
		click(15, 15);
		check("input: pressing a focusable node focuses it", paneState.focused.get() && !paneState.focusVisible.get());
		click(180, 180);
		check("input: pressing elsewhere takes focus away", !paneState.focused.get());
		click(20, 130);
		check("input: a disabled node takes no focus", !ashui.input.Interaction.of(off.node).focused.get());
		var entered:Array<String> = [];
		ashui.input.Interaction.of(pane.node).onPointerEnter(_ -> entered.push("pane+")).onPointerLeave(_ -> entered.push("pane-"));
		ashui.input.Interaction.of(inner.node).onPointerEnter(_ -> entered.push("inner+")).onPointerLeave(_ -> entered.push("inner-"));
		ashui.input.Pointer.move(inputTree, 180, 180);
		ashui.input.Pointer.move(inputTree, 15, 15);
		ashui.input.Pointer.move(inputTree, 30, 30);
		ashui.input.Pointer.move(inputTree, 180, 180);
		check("input: enter outermost first, leave innermost first", entered.join(" ") == "pane+ inner+ inner- pane-", entered);

		function key(k:window.Key, code:window.KeyCode, pressed:Bool):window.KeyEvent
			return Input(Code(code), k, None, Standard, pressed ? Pressed : Released, false, Unavailable);
		var shifted:window.Modifiers = State(true, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown);
		ashui.input.Focus.clear(inputTree);
		ashui.input.Keyboard.input(inputTree, key(Named(Tab), Tab, true));
		var firstFocus = ashui.input.Focus.of(inputTree);
		ashui.input.Keyboard.input(inputTree, key(Named(Tab), Tab, true));
		var secondFocus = ashui.input.Focus.of(inputTree);
		ashui.input.Keyboard.input(inputTree, key(Named(Tab), Tab, true));
		var wrapped = ashui.input.Focus.of(inputTree);
		ashui.input.Keyboard.input(inputTree, key(Named(Tab), Tab, true), shifted);
		var back = ashui.input.Focus.of(inputTree);
		check("input: Tab walks focusable nodes in document order, skipping disabled ones, and wraps",
			firstFocus != null && firstFocus.node == pane.node && secondFocus.node == first.node && wrapped.node == second.node
			&& back.node == first.node && back.focusVisible.get());
		log = [];
		ashui.input.Keyboard.input(inputTree, key(Named(Enter), Enter, true));
		check("input: Enter clicks the focused node, bubbling", log.join(" ") == "first page", log);
		var typed:Array<String> = [];
		ashui.input.Interaction.of(page.node).onKeyDown(e -> {
			typed.push("down");
			if (e.key.match(Named(Tab)))
				e.preventDefault();
		}).onTextInput(e -> typed.push(e.text));
		ashui.input.Keyboard.input(inputTree, key(Named(Tab), Tab, true));
		ashui.input.Keyboard.text(inputTree, "é");
		check("input: keys and text bubble to ancestors, and preventDefault keeps Tab from moving focus",
			typed.join(" ") == "down é" && ashui.input.Focus.of(inputTree).node == first.node, typed);

		var focusTree = new LayoutTree();
		var ring:Div = Owner.root(focusTree, _ -> hxx('<div class="w-10 h-10 bg-surface focus-visible:bg-primary disabled:bg-error" focusable={true} />'));
		focusTree.flush();
		focusTree.computeLayout(ring.node, 100, 100);
		var ringList = new ashui.layout.DisplayList();
		function ringFill() {
			focusTree.flush();
			ringList.update(focusTree, ring.node);
			return ringList.get(0, 8);
		}
		var unfocused = ringFill();
		ashui.input.Keyboard.input(focusTree, key(Named(Tab), Tab, true));
		var ringed = ringFill();
		ashui.input.Interaction.of(ring.node).setDisabled(true);
		var disabledFill = ringFill();
		check("focus-visible: and disabled: follow focus and the disabled state",
			unfocused == 1 && Math.abs(ringed - 0x2A / 255) < 0.01 && Math.abs(disabledFill - 0xDC / 255) < 0.01, [unfocused, ringed, disabledFill]);

		// --- One border side over the border, and outlines from classes ---
		var edgeTree = new LayoutTree();
		var edged:Div = Owner.root(edgeTree, _ -> hxx('<div class="w-10 h-10 bg-surface border border-b-4 border-border border-t-error ring-2 ring-primary ring-offset-2" />'));
		edgeTree.flush();
		edgeTree.computeLayout(edged.node, 100, 100);
		var edgeList = new ashui.layout.DisplayList();
		edgeList.update(edgeTree, edged.node);
		var sides = [for (i in 16...20) edgeList.get(0, i)];
		var ringBounds = [for (i in 0...4) edgeList.get(1, i)];
		check("border-b-4 widens one side over border", [for (v in sides) Std.int(v)].join(",") == "1,1,4,1", sides);
		var topColour = [for (i in 64...68) edgeList.get(0, i)], rightColour = [for (i in 68...72) edgeList.get(0, i)];
		check("border-t-error colours the top alone", Math.abs(topColour[0] - 0xDC / 255) < 0.01 && topColour.join(",") != rightColour.join(","),
			[topColour, rightColour]);
		check("ring-2 with ring-offset-2 draws a ring 4 out", edgeList.count == 2 && [for (v in ringBounds) Std.int(v)].join(",") == "-4,-4,48,48", [edgeList.count, ringBounds]);

		// --- A clipping box's fade reaches the records of what it clips ---
		var fadeTree = new LayoutTree();
		var faded:Div = Owner.root(fadeTree, _ -> hxx('<div class="w-10 h-10 overflow-hidden fade-y-4"><div class="w-10 h-10 bg-surface" /></div>'));
		fadeTree.flush();
		fadeTree.computeLayout(faded.node, 100, 100);
		var fadeList = new ashui.layout.DisplayList();
		fadeList.update(fadeTree, faded.node);
		var fadeRow = [for (i in 84...88) Std.int(fadeList.get(fadeList.count - 1, i))];
		check("fade-y-4 fades a clipped child from the top and bottom", fadeRow.join(",") == "16,0,16,0", fadeRow);

		// --- A clip path from a template reaches its subtree's records ---
		var shapeTree = new LayoutTree();
		var avatar:Div = Owner.root(shapeTree, _ -> hxx('<div class="w-10 h-10" clipPath={ashui.types.ClipPath.circle()}><div class="w-10 h-10 bg-surface" /></div>'));
		shapeTree.flush();
		shapeTree.computeLayout(avatar.node, 100, 100);
		var shapeList = new ashui.layout.DisplayList();
		shapeList.update(shapeTree, avatar.node);
		var shapeRow = [for (i in 96...100) Std.int(shapeList.get(shapeList.count - 1, i))];
		check("clipPath={ClipPath.circle()} clips the child to the largest centred circle", Std.int(shapeList.get(shapeList.count - 1, 94)) == 1
			&& shapeRow.join(",") == "20,20,20,20", [shapeList.get(shapeList.count - 1, 94), shapeRow]);

		// --- CSS clip-path values, read at run time and in classes ---
		function shapeOf(css:String):String
			return Std.string(ashui.types.ClipPathCss.parse(css));
		check("clip-path css: a circle at keywords", shapeOf("circle(40% at left top)") == "Circle(Percent(40),Percent(0),Percent(0))",
			shapeOf("circle(40% at left top)"));
		check("clip-path css: inset's shorthand and round", shapeOf("inset(8px 12px round 16px)") == "Inset(Px(8),Px(12),Px(8),Px(12),16)",
			shapeOf("inset(8px 12px round 16px)"));
		check("clip-path css: polygon points and a bare zero", shapeOf("polygon(nonzero, 50% 0, 100% 100%, 0 100%)").indexOf("{x : Percent(50), y : Px(0)}") >= 0,
			shapeOf("polygon(nonzero, 50% 0, 100% 100%, 0 100%)"));
		var unitless = try {
			ashui.types.ClipPathCss.parse("circle(10)");
			"";
		} catch (e:String) e;
		check("clip-path css: a length without a unit is refused", unitless.indexOf("needs a unit") >= 0, unitless);
		var classTree = new LayoutTree();
		var classed:Div = Owner.root(classTree, _ -> hxx('<div class="w-10 h-10 [clip-path:polygon(50%_0,100%_100%,0_100%)] hover:[clip-path:none]"><div class="w-10 h-10 bg-surface" /></div>'));
		classTree.flush();
		classTree.computeLayout(classed.node, 100, 100);
		var classList = new ashui.layout.DisplayList();
		classList.update(classTree, classed.node);
		var shapeKind = classList.get(classList.count - 1, 94);
		ashui.input.Pointer.move(classTree, 20, 30);
		classTree.flush();
		classList.update(classTree, classed.node);
		check("[clip-path:…] in a class clips, and hover:[clip-path:none] takes it away", shapeKind == 3 && classList.get(classList.count - 1, 94) == 0,
			[shapeKind, classList.get(classList.count - 1, 94)]);

		// --- Colour filter classes reach the layer they composite through ---
		var filterTree = new LayoutTree();
		var muted:Div = Owner.root(filterTree, _ -> hxx('<div class="w-10 h-10 bg-surface grayscale hover:grayscale-0" />'));
		filterTree.flush();
		filterTree.computeLayout(muted.node, 100, 100);
		var filterList = new ashui.layout.DisplayList();
		filterList.update(filterTree, muted.node);
		var greyRow = [for (i in 12...16) Math.round(filterList.get(filterList.count - 1, i) * 1000) / 1000];
		var layered = filterList.count == 3 && filterList.kind(0) == ashui.layout.DisplayList.PRIM_LAYER_BEGIN && filterList.kind(2) == ashui.layout.DisplayList.PRIM_LAYER;
		ashui.input.Pointer.move(filterTree, 5, 5);
		filterTree.flush();
		filterList.update(filterTree, muted.node);
		check("grayscale composites through a grey matrix, and hover:grayscale-0 drops the layer", layered && greyRow.join(",") == "0.213,0.715,0.072,0"
			&& filterList.count == 1, [layered, greyRow, filterList.count]);

		// --- A clip-path's shape is what a press hits ---
		var hitTree = new LayoutTree();
		var hitLog:Array<String> = [];
		var round:Div = Owner.root(hitTree, _ -> hxx('
			<div class="w-32 h-32" onClick={() -> hitLog.push("page")}>
				<div class="w-10 h-10" clipPath={ashui.types.ClipPath.circle()} onClick={() -> hitLog.push("circle")} />
				<div class="w-10 h-10" clipPath={ashui.types.ClipPath.path("M0 0H40V40H0Z M10 10V30H30V10Z")} onClick={() -> hitLog.push("frame")} />
			</div>
		'));
		hitTree.flush();
		hitTree.computeLayout(round.node, 200, 200);
		function tap(x:Float, y:Float) {
			ashui.input.Pointer.move(hitTree, x, y);
			ashui.input.Pointer.press(hitTree);
			ashui.input.Pointer.release(hitTree);
		}
		tap(2, 2);
		tap(20, 20);
		tap(60, 20);
		tap(45, 5);
		// Each click bubbles on to the page.
		check("clip-path: a press outside the shape misses it, inside hits it", hitLog.join(" ") == "page circle page page frame page", hitLog);

		// --- A bitmap in a template: <img>, its fit from a class, clipped to its corners ---
		var pairBitmap = ashui.types.Bitmap.fromBytes(haxe.crypto.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4zwAE/wEHAAH/4iOeWQAAAABJRU5ErkJggg=="));
		check("bitmap: decoded with its size", pairBitmap.width == 2 && pairBitmap.height == 1, [pairBitmap.width, pairBitmap.height]);
		var imgTree = new LayoutTree();
		var avatar:Div = Owner.root(imgTree, _ -> hxx('<div><img src={pairBitmap} class="w-10 h-10 rounded-full object-cover" /></div>'));
		imgTree.flush();
		imgTree.computeLayout(avatar.node, 100, 100);
		var imgList = new ashui.layout.DisplayList();
		imgList.update(imgTree, avatar.node);
		var imageRecord = -1;
		for (r in 0...imgList.count)
			if (imgList.kind(r) == ashui.layout.DisplayList.PRIM_IMAGE)
				imageRecord = r;
		check("<img> with object-cover draws its bitmap covering, clipped to its round corners", imageRecord >= 0
			&& Std.int(imgList.get(imageRecord, 40)) == pairBitmap.slotFor(Cover) && imgList.get(imageRecord, 36) > 0,
			imageRecord < 0 ? null : [imgList.get(imageRecord, 40), imgList.get(imageRecord, 36)]);

		// --- focus-within:, group- and peer- follow another element's state ---
		var relTree = new LayoutTree();
		var field:Div = null;
		var shell:Div = Owner.root(relTree, _ -> hxx('
			<div class="w-32 h-32 bg-surface focus-within:bg-primary">
				<div class="group w-20 h-10 bg-surface">
					<div class="w-5 h-5 bg-surface group-hover:bg-error" />
					${field = hxx('<div class="w-5 h-5 bg-surface" focusable={true} />')}
				</div>
				<div class="peer w-5 h-5 bg-surface" />
				<div class="w-5 h-5 bg-surface peer-hover:bg-error" />
			</div>
		'));
		relTree.flush();
		relTree.computeLayout(shell.node, 200, 200);
		var relList = new ashui.layout.DisplayList();
		// Records in tree order: the shell, the group, its label, the field, the peer, the one after it.
		function reds():Array<Float> {
			relTree.flush();
			relList.update(relTree, shell.node);
			return [for (r in 0...6) Math.round(relList.get(r, 8) * 255) / 255];
		}
		var resting = reds();
		ashui.input.Pointer.move(relTree, 2, 2);
		var overLabel = reds();
		ashui.input.Pointer.move(relTree, 82, 2);
		var overPeer = reds();
		ashui.input.Pointer.leave(relTree);
		ashui.input.Focus.set(ashui.input.Interaction.of(field.node), false);
		var focusedInside = reds();
		ashui.input.Focus.clear(relTree);
		var cleared = reds();
		var error = Math.round(0xDC / 255 * 255) / 255;
		check("group-hover: follows the nearest group ancestor", overLabel[2] == error && resting[2] != error && overPeer[2] != error,
			[resting[2], overLabel[2], overPeer[2]]);
		check("peer-hover: follows the nearest earlier peer", overPeer[5] == error && resting[5] != error && overLabel[5] != error,
			[resting[5], overPeer[5], overLabel[5]]);
		check("focus-within: follows focus anywhere inside", focusedInside[0] != resting[0] && cleared[0] == resting[0],
			[resting[0], focusedInside[0], cleared[0]]);

		// --- Handles are released by the collector ---
		for (i in 0...20000) {
			Signal.make(i);
			new Color(i);
			new LayoutTree();
		}
		hl.Gc.major();
		hl.Gc.major();
		tree.flush();
		check("released handles removed from the graph without crashing", true);

		// --- An exception in a computed surfaces in Haxe ---
		var boom = Signal.make(0);
		var bad = boom.computed(v -> v > 0 ? throw "boom" : v);
		check("computed before throw", bad.get() == 0);
		boom.set(1);
		var caught = try {
			bad.get();
			false;
		} catch (e:haxe.Exception) e.message == "boom";
		check("exception rethrown from computed", caught);

		// --- The short spellings: signal, computed, watch ---
		var count = signal(2);
		var tint = signal(new Color(0x112233));
		var doubled = computed(() -> count.get() * 2);
		var seen:Array<Int> = [];
		watch(() -> doubled.get(), v -> seen.push(v));
		count.set(5);
		ashui.reactive.Watch.runQueued();
		var countIsInt:Int = count.get();
		check("signal(2) is an Int signal, signal(colour) a colour one, and computed and watch follow them",
			countIsInt == 5 && doubled.get() == 10 && tint.get().rgb == 0x112233 && seen.indexOf(10) >= 0, [doubled.get(), seen]);

		// --- A signal or computed can be made while a computed evaluates, as SolidJS allows ---
		var lazy:Null<ashui.reactive.ISignal<Int>> = null;
		var reader = Computed.make(() -> {
			if (lazy == null)
				lazy = Signal.make(7);
			var doubled = Computed.make(() -> lazy.get() * 2);
			doubled.get();
		});
		check("a signal and a computed made inside a computed are read there", reader.get() == 14, reader.get());
		lazy.set(10);
		check("and the computed follows the signal made inside it", reader.get() == 20, reader.get());
		var refused = try {
			Computed.make(() -> {
				new ashui.reactive.Watch(() -> 1, _ -> {});
				0;
			}).get();
			"";
		} catch (e:haxe.Exception) e.message;
		check("a watch made inside a computed is still refused with a reason", refused.indexOf("while a computed or watch evaluated") >= 0, refused);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}

/** A component whose label follows what its attribute reads. **/
class Badge extends Component<{label:IntoReactive<String>}> {
	function render():Element
		return new Div({width: 50, height: 20}, [new Text(props.label)]);
}

/** Counters it builds, and another of its kind with its own; for rendering again. **/
class Shelf extends View {
	public var counters:Array<CounterView> = [];
	public var inner:Null<Shelf> = null;
	final depth:Int;

	public function new(props:{}, ?children:Array<Element>, ?depth = 0) {
		this.depth = depth;
		super(props, children);
	}

	function render():Element {
		counters = [new CounterView({}), new CounterView({})];
		var kids:Array<Element> = [for (c in counters) c];
		if (depth == 0) {
			inner = new Shelf({}, null, 1);
			kids.push(inner);
		}
		return new Div({}, kids);
	}
}

/** Counters a <for> builds, one per name, some after its first render. **/
class Rack extends View {
	public final names = Signal.make(["a"]);
	public final made:Array<CounterView> = [];

	function render() '<div><for {n in names}>{counter()}</for></div>';

	function counter():Element {
		var c = new CounterView({});
		made.push(c);
		return c;
	}
}

/** The spec's counter: state read without .get(), and a template body. **/
class CounterView extends View {
	@:state public var count:Int = 1;

	function render() '
		<div width={count * 10} height={8} flexShrink={0}>
			<text>Value: ${count}</text>
		</div>
	';

	public function increment():Void {
		count++;
	}
}

enum SmokeState {
	Idle;
	Loading(n:Int);
	Shown;
	Hiding;
}

enum SmokeEvent {
	Go;
	Step;
	Done;
	Hide;
	Gone;
}
