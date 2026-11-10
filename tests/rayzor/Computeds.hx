import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.ComputedBool;
import ashui.reactive.ComputedDynamic;
import ashui.reactive.ComputedF32;
import ashui.reactive.ComputedI32;
import ashui.reactive.ComputedString;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.SignalF32;
import ashui.reactive.SignalI32;
import ashui.reactive.SignalString;
import ashui.reactive.Watch;
import ashui.ui.Div;

/**
	Computeds on Rayzor, where the plugin cannot call a Haxe closure and Haxe reruns a computed when a dependency was written.
	Run by `run.sh`.
**/
class Computeds {
	// Static, not captured locals, so that a closure which counts shares the count.
	static var runs = 0;
	static var qruns = 0;
	static var failed = 0;
	static var passed = 0;

	static function check(name:String, ok:Bool):Void {
		if (ok) {
			passed++;
			Sys.println("ok   " + name);
		} else {
			failed++;
			Sys.println("FAIL " + name);
		}
	}

	static function pull() {
		var s = new SignalI32(2);
		runs = 0;
		var d = new ComputedI32(() -> {
			runs++;
			s.get() * 2;
		});
		check("a computed has its value at once", d.get() == 4 && runs == 1);
		s.set(5);
		check("a read after a write is current, with no flush", d.get() == 10 && runs == 2);
		d.get();
		check("a second read runs nothing", runs == 2);
		var e = new ComputedI32(() -> d.get() + 1);
		s.set(7);
		check("a computed of a computed follows", e.get() == 15);
	}

	static function cutoff() {
		var s = new SignalI32(2);
		var p = new ComputedBool(() -> s.get() > 100);
		qruns = 0;
		var q = new ComputedI32(() -> {
			qruns++;
			p.get() ? 1 : 0;
		});
		s.set(8);
		check("an unchanged result wakes no dependent", q.get() == 0 && qruns == 1);
		s.set(200);
		check("a changed result does", q.get() == 1 && qruns == 2);
	}

	static function diamond() {
		var s = new SignalI32(1);
		var a = new ComputedI32(() -> s.get() * 2);
		var b = new ComputedI32(() -> s.get() + 1);
		runs = 0;
		var c = new ComputedI32(() -> {
			runs++;
			a.get() + b.get();
		});
		var first = runs;
		s.set(3);
		check("a diamond ends consistent", c.get() == 10);
		check("and its join ran once for the change", runs - first == 1);
	}

	static function watching() {
		var tree = new LayoutTree();
		var s = new SignalI32(1);
		var d = new ComputedI32(() -> s.get() * 10);
		var seen:Array<Int> = [];
		var w = new Watch(() -> d.get(), v -> seen.push(v));
		check("a watch reacts once at the start", seen.length == 1 && seen[0] == 10);
		s.set(2);
		check("a flush reacts to a computed's change", tree.flush() && seen.length == 2 && seen[1] == 20);
		check("an idle flush reacts to nothing", !tree.flush() && seen.length == 2);
		w.stop();
	}

	static function idle() {
		var tree = new LayoutTree();
		var s = new SignalI32(1);
		runs = 0;
		var d = new ComputedI32(() -> {
			runs++;
			s.get() + 1;
		});
		tree.flush();
		var before = runs;
		var any = false;
		for (i in 0...1000)
			if (tree.flush())
				any = true;
		check("1000 idle flushes run no computed and change nothing", runs == before && !any);
	}

	static function owned() {
		var tree = new LayoutTree();
		var s = new SignalI32(1);
		runs = 0;
		var kept:Int = Owner.root(tree, dispose -> {
			var c = new ComputedI32(() -> {
				runs++;
				s.get() * 3;
			});
			var v = c.get();
			dispose();
			v;
		});
		var after = runs;
		s.set(9);
		tree.flush();
		check("a disposed computed no longer runs", kept == 3 && runs == after);
	}

	// A computed bound to a node's property: the tree reads the computed's native signal. Display is an Int property
	// (1 flex, 3 none); the size is set natively.
	static function bound() {
		var tree = new LayoutTree();
		var s = new SignalI32(1);
		var disp = new ComputedI32(() -> s.get());
		var div = new Div({}, [], tree);
		var hundred:Single = 100;
		var forty:Single = 40;
		ashui.core.externs.BlincNative.blinc_apply_f32(div.node.id, ashui.layout.PropertyId.Width, 0, hundred, null, null);
		ashui.core.externs.BlincNative.blinc_apply_f32(div.node.id, ashui.layout.PropertyId.Height, 0, forty, null, null);
		ashui.core.externs.BlincNative.blinc_apply_i32(div.node.id, ashui.layout.PropertyId.Display, 2, 0, null, disp.ptr);
		var sw:Single = 800;
		var sh:Single = 600;
		tree.flush();
		tree.computeLayout(div.node, sw, sh);
		var b = tree.getBounds(div.node);
		Sys.println("  width " + (b == null ? "null" : "" + b.width) + " height " + (b == null ? "null" : "" + b.height));
		check("a bound computed sets the property", b != null && Math.abs(b.width - 100) < 0.01);
		s.set(3);
		check("a flush applies a change", tree.flush());
		tree.computeLayout(div.node, sw, sh);
		var b2 = tree.getBounds(div.node);
		Sys.println("  width " + (b2 == null ? "null" : "" + b2.width) + " height " + (b2 == null ? "null" : "" + b2.height));
		check("and the layout follows", b2 == null || b2.width < 0.01);
		check("an idle flush applies nothing", !tree.flush());
		s.set(1);
		tree.flush();
		tree.computeLayout(div.node, sw, sh);
		var b3 = tree.getBounds(div.node);
		Sys.println("  width " + (b3 == null ? "null" : "" + b3.width));
		check("and back", b3 != null && Math.abs(b3.width - 100) < 0.01);
	}

	// A Div attribute bound to a signal and to a computed.
	static function attributes() {
		var tree = new LayoutTree();
		var sw:Single = 800;
		var sh:Single = 600;
		var w:Signal<Single> = new SignalF32(50);
		var twice:Computed<Single> = new ComputedF32(() -> w.get() * 2);
		var a = new Div({width: w}, [], tree);
		var b = new Div({width: twice}, [], tree);
		tree.flush();
		tree.computeLayout(a.node, sw, sh);
		tree.computeLayout(b.node, sw, sh);
		check("a width bound to a signal", width(tree, a) == 50);
		check("a width bound to a computed", width(tree, b) == 100);
		var seventy:Single = 70;
		w.set(seventy);
		check("a flush applies the write", tree.flush());
		tree.computeLayout(a.node, sw, sh);
		tree.computeLayout(b.node, sw, sh);
		check("the signal's width follows", width(tree, a) == 70);
		check("and the computed's", width(tree, b) == 140);
		check("an idle flush applies nothing", !tree.flush());
	}

	static function width(tree:LayoutTree, d:Div):Int {
		var b = tree.getBounds(d.node);
		return b == null ? -1 : Math.round(b.width);
	}

	static function strings() {
		var s = new SignalString("a");
		var up = new ComputedString(() -> s.get() + "!");
		check("a string computed", up.get() == "a!");
		s.set("bc");
		check("a string computed follows", up.get() == "bc!");
	}

	static function singles() {
		var s = new SignalF32(1.5);
		var d = new ComputedF32(() -> s.get() * 2);
		check("a Single computed", "" + d.get() == "3");
		s.set(2.5);
		check("a Single computed follows", "" + d.get() == "5");
	}

	static function dynamics() {
		var s = new SignalI32(1);
		runs = 0;
		var d = new ComputedDynamic<Array<Int>>(() -> {
			runs++;
			[s.get(), s.get() * 2];
		});
		check("a dynamic computed has its value", d.get().length == 2 && d.get()[1] == 2 && runs == 1);
		s.set(4);
		check("a dynamic computed follows", d.get()[1] == 8 && runs == 2);
	}

	// The macros pick the class from the value's type.
	static function makes() {
		var n = Signal.make(2);
		var twice = Computed.make(() -> n.get() * 2);
		check("Signal.make and Computed.make", twice.get() == 4);
		n.set(5);
		check("and the computed follows", twice.get() == 10);
		var name = Signal.make("a");
		var shout = Computed.make(() -> name.get() + "!");
		name.set("bc");
		check("a string signal and computed", shout.get() == "bc!");
		var on = Signal.make(false);
		var flip = Computed.make(() -> !on.get());
		on.set(true);
		check("a bool signal and computed", flip.get() == false);
	}

	static function main() {
		var args = Sys.args();
		if (args.length == 0)
			args = ["pull", "cutoff", "diamond", "watching", "idle", "owned", "strings", "singles", "dynamics", "makes", "attributes", "bound"];
		for (a in args) {
			Sys.println("== " + a);
			try {
				switch (a) {
					case "pull": pull();
					case "cutoff": cutoff();
					case "diamond": diamond();
					case "watching": watching();
					case "idle": idle();
					case "owned": owned();
					case "bound": bound();
					case "strings": strings();
					case "singles": singles();
					case "dynamics": dynamics();
					case "makes": makes();
					case "attributes": attributes();
					case _: Sys.println("unknown step " + a);
				}
			} catch (e:haxe.Exception) {
				failed++;
				Sys.println("EXCEPTION in " + a + ": " + e.message);
			}
		}
		Sys.println(failed == 0 ? "ALL PASSED " + passed : "FAILED " + failed + " of " + (passed + failed));
	}
}
