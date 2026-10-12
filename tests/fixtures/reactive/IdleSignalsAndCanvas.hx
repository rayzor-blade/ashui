// Native signal deduplication (blinc_abi f12b432) and paused tickers (Ashui 364d4b2).
import ashui.animation.AnimationScheduler;
import ashui.core.externs.BlincNative;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.ui.Canvas;
import ashui.ui.Div;

class IdleSignalsAndCanvas {
	static var failures = 0;
	static var checks = 0;
	static function check(label:String, ok:Bool):Void {
		checks++;
		if (!ok) failures++;
		Sys.println((ok ? "ok   " : "FAIL ") + label);
	}

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var tree = new LayoutTree();
		var integer = Signal.make(12), single = Signal.make((40 : Single));
		var double = Signal.make(60.0), enabled = Signal.make(false);
		var reads = 0;
		var twice = Computed.make(() -> { reads++; return (single.get() * 2 : Single); });
		var root = new Div({width: integer.computed(v -> (v : Single)), height: double, opacity: enabled.computed(v -> (v ? 1.0 : 0.5 : Single))},
			[new Div({width: single, height: twice}, tree)], tree);
		tree.flush();
		tree.computeLayout(root.node, 200, 200);
		var before = reads;
		integer.set(12); single.set(40); double.set(60); enabled.set(false);
		check("equal primitives queue no native layout or paint updates", !tree.flush());
		check("equal primitive keeps computed cached", twice.get() == 80 && reads == before);
		integer.set(13); single.set(41); double.set(61); enabled.set(true);
		check("changed primitives still queue updates", tree.flush());
		tree.computeLayout(root.node, 200, 200);
		check("changed values reach layout and computed", tree.getBounds(root.node).width == 13 && tree.getBounds(root.node).height == 61
			&& twice.get() == 82 && reads > before);
		var nan = Signal.make(Math.NaN);
		var nanReads = 0;
		var nanComputed = Computed.make(() -> { nanReads++; return Math.isNaN(nan.get()); });
		nanComputed.get();
		nan.set(Math.NaN);
		check("repeated NaN keeps computed cached", nanComputed.get() && nanReads == 1);
		nan.set(1);
		check("NaN to finite still invalidates computed", !nanComputed.get() && nanReads == 2);
		var zero = Signal.make(0.0);
		var reciprocal = zero.computed(v -> 1 / v);
		check("positive zero starts positive infinity", reciprocal.get() == Math.POSITIVE_INFINITY);
		// Produce negative zero at runtime; Haxe folds the literal -0.0 to +0.0.
		zero.set(-1 / Math.POSITIVE_INFINITY);
		check("signed zero change remains observable", reciprocal.get() == Math.NEGATIVE_INFINITY);

		// A setter in a host read must not silently subscribe that read to its target.
		var slot = BlincNative.blinc_host_effect_new();
		BlincNative.blinc_host_effect_begin(slot);
		BlincNative.blinc_signal_set_bool(enabled.ptr, 1);
		BlincNative.blinc_host_effect_end(slot);
		enabled.set(false);
		var due = new hl.Bytes(1024);
		var count = BlincNative.blinc_host_effects_due(due, 256);
		var subscribed = false;
		for (i in 0...count) if (due.getI32(i * 4) == slot) subscribed = true;
		check("equal setter does not record a read dependency", !subscribed);
		BlincNative.blinc_host_effect_release(slot);
		var done = new sys.thread.Lock();
		sys.thread.Thread.create(() -> { single.set(42); done.release(); });
		check("worker writes complete", done.wait(2));
		check("worker change still reaches native bindings", tree.flush() && twice.get() == 84);

		var scheduler = AnimationScheduler.main;
		check("scheduler starts idle", !scheduler.hasActive());
		var active = Signal.make(false);
		var dispose:Void->Void = null;
		Owner.root(tree, cleanup -> {
			dispose = cleanup;
			return <canvas width={80} height={60} animate={active} />;
		});
		tree.flush();
		check("initially paused canvas registers no ticker", !scheduler.hasActive());
		active.set(true); tree.flush();
		check("canvas starts reactively", scheduler.hasActive());
		scheduler.tick(0.016);
		check("active canvas requests a frame", tree.flush());
		active.set(false); tree.flush();
		check("pausing removes ticker without another tick", !scheduler.hasActive());
		scheduler.tick(0.016);
		check("paused canvas requests no frame", !tree.flush());
		active.set(true); tree.flush();
		active.set(false); tree.flush();
		active.set(true); tree.flush();
		check("rapid pause and resume still animates", scheduler.hasActive());
		dispose();
		check("disposing active canvas immediately removes ticker", !scheduler.hasActive());
		active.set(false); active.set(true); tree.flush();
		check("disposed canvas cannot restart", !scheduler.hasActive());
		Owner.root(tree, cleanup -> {
			var paused = <canvas animate={false} />;
			check("constant false canvas stays idle", !scheduler.hasActive());
			cleanup();
			return null;
		});
		Owner.root(tree, cleanup -> {
			var playing = <canvas animate={true} />;
			check("constant true canvas animates", scheduler.hasActive());
			cleanup();
			return null;
		});
		check("constant animation is removed on disposal", !scheduler.hasActive());
		Owner.root(tree, cleanup -> {
			var derived = <canvas animate={active.computed(v -> !v)} />;
			check("derived false canvas starts idle", !scheduler.hasActive());
			active.set(false); tree.flush();
			check("derived canvas resumes", scheduler.hasActive());
			active.set(true); tree.flush();
			check("derived canvas pauses immediately", !scheduler.hasActive());
			cleanup();
			return null;
		});
		var second = scheduler.addTicker(_ -> true);
		scheduler.addTicker(_ -> { second.cancel(); return false; });
		scheduler.tick(0.016);
		check("ticker cancelled during a tick is not reinserted", !scheduler.hasActive());
		var later:ashui.animation.AnimationScheduler.Ticker = null;
		var laterRan = false;
		scheduler.addTicker(_ -> { later.cancel(); return false; });
		later = scheduler.addTicker(_ -> { laterRan = true; return true; });
		scheduler.tick(0.016);
		check("cancellation skips callbacks not yet run in the same tick", !laterRan && !scheduler.hasActive());
		Sys.println('$checks checks, $failures failures');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
