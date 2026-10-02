import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.layout.PropertyId;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
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
			<Div width={hxxWidth} height={hxxCount.get() * 10} flexShrink={0} bg={Brush.solid(0x336699)} flexDirection={Column}>
				<Div width={8} height={8} />
			</Div>
		'));
		var hxxLabel:Text = Owner.root(tree, _ -> hxx('<Text>Count: ${hxxCount}</Text>'));
		var disposeBadge:Void->Void = null;
		var badge:Badge = Owner.root(tree, dispose -> {
			disposeBadge = dispose;
			hxx('<Badge label={"n=" + hxxCount.get()} />');
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
			<Div flexShrink={0}>
				<if {visible}>
					<Div width={30} height={30} />
				<else>
					<Div width={10} height={10} />
				</if>
			</Div>
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
			<Div flexShrink={0}>
				<for {n in numbers}>{cell(n)}</for>
			</Div>
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

		// --- A watch reacts only to what it read ---
		var flagA = Signal.make(true);
		var flagB = Signal.make(true);
		var builtA = 0, builtB = 0;
		var pair:Div = Owner.root(tree, _ -> hxx('
			<Div flexShrink={0}>
				<if {flagA}>{(() -> { builtA++; new Div({width: 5, height: 5}); })()}</if>
				<if {flagB}>{(() -> { builtB++; new Div({width: 5, height: 5}); })()}</if>
			</Div>
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
			<Div flexShrink={0}>
				<if {big}><Div width={40} height={4} /><else><Div width={4} height={4} /></if>
			</Div>
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
		var counter:CounterView = Owner.root(tree, _ -> hxx('<CounterView />'));
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

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}

/** A component whose label follows what its attribute reads. **/
class Badge extends Component<{label:IntoReactive<String>}> {
	function render():Element
		return new Div({width: 50, height: 20}, [new Text(props.label)]);
}

/** The spec's counter: state read without .get(), and a template body. **/
class CounterView extends View {
	@:state public var count:Int = 1;

	function render() '
		<Div width={count * 10} height={8} flexShrink={0}>
			<Text>Value: ${count}</Text>
		</Div>
	';

	public function increment():Void {
		count++;
	}
}
