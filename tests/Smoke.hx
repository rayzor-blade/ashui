import ashui.layout.LayoutTree;
import ashui.layout.PropertyId;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Text;

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

		// --- Handles are released by the collector ---
		for (i in 0...20000) {
			Signal.make(i);
			new Color(i);
			new LayoutTree();
		}
		hl.Gc.major();
		hl.Gc.major();
		check("finalizers ran without crashing", true);

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
