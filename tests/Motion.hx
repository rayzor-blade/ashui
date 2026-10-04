import ashui.animation.AnimationScheduler;
import ashui.debug.MotionCheck;
import ashui.debug.MotionTrace;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.ui.Div;

/** Motion tracing: what each kind of animation records, and what MotionCheck finds in a sound and a faulty one. **/
class Motion {
	static var failures = 0;

	static function check(what:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			failures++;
			Sys.println('FAIL $what' + (detail != null ? ': $detail' : ''));
		} else
			Sys.println('ok   $what');
	}

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var scheduler = AnimationScheduler.main;
		var tree = new LayoutTree();
		ashui.css.Css.load('
			.fade { width: 10px; height: 10px; opacity: 1; transition: opacity 100ms ease-out; }
			.fade.out { opacity: 0; }
			@keyframes grow { from { width: 10px } to { width: 110px } }
			.grow { height: 10px; width: 10px; animation: grow 200ms linear; }
		');
		var classes = Signal.make(["fade"]);
		var growClasses = Signal.make(([] : Array<String>));
		var root:Div = Owner.root(tree, _ -> new Div({width: 300, height: 300}, [new Div({classes: classes}, tree), new Div({classes: growClasses}, tree)], tree));
		function frame(n = 1) {
			for (_ in 0...n) {
				scheduler.tick(1 / 60);
				ashui.css.Css.update();
				tree.flush();
				tree.computeLayout(root.node, 300, 300);
				if (MotionTrace.current != null)
					MotionTrace.current.observe(tree);
			}
		}
		frame();

		classes.set(["fade", "out"]);
		frame();
		check("nothing is recorded while no trace is", MotionTrace.current == null);
		frame(10);

		// --- A CSS transition, recorded and judged sound ---
		var trace = MotionTrace.start();
		classes.set(["fade"]);
		frame(10);
		var fade = Lambda.find(trace.tracks, t -> t.property == "opacity");
		var v = fade == null ? null : MotionCheck.check(fade, trace);
		check("a CSS transition is a track: its element, property, values, timing and curve as declared", fade != null && fade.kind == Transition
			&& fade.label == "div.fade" && fade.from == "0" && fade.to == "1" && Math.abs(fade.duration - 0.1) < 1e-6
			&& fade.curve == "cubic-bezier(0, 0, 0.58, 1)", fade == null ? null : [fade.label, fade.from, fade.to, fade.duration, fade.curve]);
		check("it ran its course on its curve, frame by frame, and is judged ok", v != null && fade.end == Completed && v.frames >= 6 && v.frames <= 7
			&& v.issues.length == 0 && v.maxError < 1e-6 && fade.rects.length >= 6, v == null ? null : [fade.end, v.frames, v.issues, v.maxError]);

		// --- A keyframes run ---
		growClasses.set(["grow"]);
		frame(15);
		var grow = Lambda.find(trace.tracks, t -> t.kind == Keyframes);
		var gv = grow == null ? null : MotionCheck.check(grow, trace);
		check("a @keyframes run is a track along its timeline, judged ok", gv != null && grow.end == Completed && gv.issues.length == 0
			&& StringTools.startsWith(grow.property, "@keyframes grow"), gv == null ? null : [grow.property, grow.end, gv.issues]);

		// --- A spring, against the oscillator's closed form ---
		var spring = new ashui.animation.Spring(ashui.animation.SpringConfig.wobbly(), 0);
		var id = scheduler.register(spring);
		scheduler.setTarget(id, 100);
		frame(240);
		var sprung = Lambda.find(trace.tracks, t -> t.kind == Spring && t.to == "100");
		var sv = sprung == null ? null : MotionCheck.check(sprung, trace);
		check("a spring follows the damped oscillator's own curve, overshoots as it should, and settles", sv != null && sprung.end == Completed
			&& sv.maxError < 0.01 && sv.overshoot > 0.05 && sv.issues.length == 0, sv == null ? null : [sprung.end, sv.maxError, sv.overshoot, sv.issues]);
		trace.stop();
		check("a stopped trace is no longer current", MotionTrace.current == null);

		// --- Faults: a late start, a jump off the curve, a snap, a run repeated ---
		var faults = MotionTrace.start();
		var late = MotionTrace.begin(Transition, null, null, "x", "0", "1", 0, 0.1, Linear, null, "late");
		frame(3);
		var t0 = late.began;
		for (_ in 0...6) {
			frame();
			// Two frames behind its clock.
			var t = Math.min(1, (MotionTrace.clock() - t0 - 2 / 60) / 0.1);
			late.sample(t, t);
		}
		late.finish(Completed);
		var snapped = MotionTrace.begin(Transition, null, null, "y", "0", "1", 0, 0.2, Linear, null, "snapper");
		snapped.sample(1, 1);
		snapped.finish(Completed);
		for (_ in 0...2) {
			var again = MotionTrace.begin(Transition, null, null, "z", "0", "1", 0, 1 / 60, Linear, null, "repeater");
			frame();
			again.sample(1, 1);
			again.finish(Completed);
		}
		faults.stop();
		var lv = MotionCheck.check(late, faults);
		check("a track behind its clock is off its curve and runs long", lv.issues.filter(i -> StringTools.startsWith(i, "off its curve")).length == 1
			&& lv.issues.filter(i -> StringTools.startsWith(i, "ran ")).length == 1, lv.issues);
		check("a track with no frames between start and end snapped", MotionCheck.check(snapped, faults).issues.indexOf("snapped: no frames between its start and end") >= 0,
			MotionCheck.check(snapped, faults).issues);
		var repeated = MotionCheck.check(faults.tracks[faults.tracks.length - 1], faults);
		check("the same move run again is reported", repeated.issues.filter(i -> StringTools.startsWith(i, "ran again")).length == 1, repeated.issues);
		var report = MotionCheck.report(faults);
		check("the report sums up and judges each track", StringTools.startsWith(report, "motion trace: 4 tracks") && report.indexOf("WARN") > 0,
			report.split("\n")[0]);
		var json:Dynamic = haxe.Json.parse(MotionCheck.json(trace));
		check("the trace reads back as JSON, samples and expected values included", json.tracks.length == trace.tracks.length
			&& json.tracks[0].samples.length > 0 && json.tracks[0].samples[0].expected != null);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
