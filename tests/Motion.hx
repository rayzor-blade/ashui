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
			.spin { width: 10px; height: 10px; transition: transform 100ms linear, background 100ms linear; }
			.spin.on { transform: rotate(90deg); background: #ff0000; }
		');
		var classes = Signal.make(["fade"]);
		var growClasses = Signal.make(([] : Array<String>));
		var spinClasses = Signal.make(["spin"]);
		var root:Div = Owner.root(tree, _ -> new Div({width: 300, height: 300}, [
			new Div({classes: classes}, tree),
			new Div({classes: growClasses}, tree),
			new Div({classes: spinClasses}, tree)
		], tree));
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

		// --- A property a later rule gives a value moves from its initial value, and back when the rule stops ---
		spinClasses.set(["spin", "on"]);
		frame(8);
		spinClasses.set(["spin"]);
		frame(8);
		var turns = trace.tracks.filter(t -> StringTools.startsWith(t.label, "div.spin") && t.property == "transform");
		var fills = trace.tracks.filter(t -> StringTools.startsWith(t.label, "div.spin") && t.property == "background");
		check("a transform a later rule sets turns from none and back to none, as CSS transitions it",
			turns.length == 2 && turns[0].from == "none" && turns[0].to == "rotate(90deg)" && turns[1].to == "none"
			&& turns.filter(t -> t.end == Completed && MotionCheck.check(t, trace).issues.length == 0).length == 2,
			[for (t in turns) '${t.from}->${t.to} ${t.end} ${MotionCheck.check(t, trace).issues}']);
		var half = fills.length == 0 ? null : fills[0].samples[2];
		check("a colour fades in from transparent keeping its hue, alpha premultiplied", fills.length == 2 && half != null && half.value != null
			&& StringTools.startsWith(half.value, "#ff0000/"), [for (f in fills) f.samples.map(x -> x.value)]);

		// --- Motion on an element not drawn: styled while detached, as a closed popover's panel is ---
		var hidden:Div = Owner.root(tree, _ -> new Div({classes: ["grow"]}, tree));
		frame(15);
		var unseen = Lambda.find(trace.tracks, t -> t.kind == Keyframes && t.node == hidden.node.id);
		var uv = unseen == null ? null : MotionCheck.check(unseen, trace);
		check("an animation that runs where nothing is drawn is reported", uv != null
			&& uv.issues.filter(i -> StringTools.startsWith(i, "ran where it is not drawn")).length == 1, uv == null ? null : uv.issues);

		// --- A property bound to a computed before a stylesheet's transition arrives still moves by it ---
		ashui.css.Css.load(".bound { height: 4px; transition: width 100ms linear; }");
		var share = Signal.make(0.2);
		var bar:Div = Owner.root(tree, _ -> new Div({classes: ["bound"]}, tree));
		bar.node.set(ashui.layout.Prop.WidthPercent, ashui.reactive.Computed.make(() -> (share.get() : Single)));
		@:privateAccess tree.addChild(root.node.id, bar.node.id);
		frame(2);
		share.set(0.9);
		frame(8);
		var grew = Lambda.find(trace.tracks, t -> t.node == bar.node.id && t.property == "width-percent");
		check("a binding made before its transition, as a progress bar's width, moves by the transition when it arrives",
			grew != null && grew.end == Completed && grew.from == "0.2" && grew.to == "0.9", grew == null ? null : [grew.from, grew.to, grew.end]);

		// --- A value set with no transition, then changed by a rule that brings one: it moves, as CSS's after-change style says ---
		ashui.css.Css.load(".late { width: 10px; height: 10px; opacity: 0.5; } .late.go { opacity: 1; transition: opacity 100ms linear; }");
		var lateClasses = Signal.make(["late"]);
		var lateBox:Div = Owner.root(tree, _ -> new Div({classes: lateClasses}, tree));
		@:privateAccess tree.addChild(root.node.id, lateBox.node.id);
		frame(2);
		lateClasses.set(["late", "go"]);
		frame(8);
		var brightened = Lambda.find(trace.tracks, t -> t.node == lateBox.node.id && t.property == "opacity");
		check("a value changed by the rule that brings its transition moves from where it was", brightened != null && brightened.end == Completed
			&& brightened.from == "0.5" && brightened.to == "1", brightened == null ? null : [brightened.from, brightened.to, brightened.end]);

		// --- A keyframes run whose segments each have their own curve ---
		ashui.css.Css.load("@keyframes bob { 0% { width: 10px; animation-timing-function: ease-in; } 50% { width: 60px; animation-timing-function: linear; } 100% { width: 10px; } }
			.bob { height: 10px; width: 10px; animation: bob 200ms ease-out; }");
		var bob:Div = Owner.root(tree, _ -> new Div({classes: ["bob"]}, tree));
		@:privateAccess tree.addChild(root.node.id, bob.node.id);
		frame(16);
		var bobbed = Lambda.find(trace.tracks, t -> t.kind == Keyframes && t.node == bob.node.id);
		var bv = bobbed == null ? null : MotionCheck.check(bobbed, trace);
		check("a keyframes run records each segment's curve and follows it", bv != null && bobbed.keyframes != null && bobbed.keyframes.length == 3
			&& bobbed.samples.filter(x -> x.eased != null).length >= 10 && bv.issues.length == 0, bv == null ? null : [bobbed.keyframes, bv.issues]);

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
		for (move in [["0", "1"], ["1", "0"], ["0", "1"]]) {
			var toggled = MotionTrace.begin(Transition, null, null, "w", move[0], move[1], 0, 1 / 60, Linear, null, "toggler");
			frame();
			toggled.sample(1, 1);
			toggled.finish(Completed);
		}
		var there = MotionTrace.begin(Layout, null, null, "layout", "0,0", "0,48", 0, 0.24, EaseOut, null, "item");
		frame(2);
		there.sample(0.3, 0.1);
		var back = MotionTrace.begin(Layout, null, null, "layout", "0,48", "0,0", 0, 0.24, EaseOut, null, "item");
		frame();
		back.sample(0.2, 0.1);
		back.finish(Completed);
		faults.stop();
		var bv = MotionCheck.check(back, faults);
		check("a move cut short and undone at once is a bounce", there.end == Interrupted
			&& bv.issues.filter(i -> StringTools.startsWith(i, 'undid track #${there.id}')).length == 1, bv.issues);
		var lv = MotionCheck.check(late, faults);
		check("a track behind its clock is off its curve and runs long", lv.issues.filter(i -> StringTools.startsWith(i, "off its curve")).length == 1
			&& lv.issues.filter(i -> StringTools.startsWith(i, "ran ")).length == 1, lv.issues);
		check("a track with no frames between start and end snapped", MotionCheck.check(snapped, faults).issues.indexOf("snapped: no frames between its start and end") >= 0,
			MotionCheck.check(snapped, faults).issues);
		var repeated = MotionCheck.check([for (t in faults.tracks) if (t.label == "repeater") t][1], faults);
		check("the same move run again is reported", repeated.issues.filter(i -> StringTools.startsWith(i, "ran again")).length == 1, repeated.issues);
		var retoggled = MotionCheck.check([for (t in faults.tracks) if (t.label == "toggler") t][2], faults);
		check("a move taken back and made again is not a repeat", retoggled.issues.filter(i -> StringTools.startsWith(i, "ran again")).length == 0,
			retoggled.issues);
		var report = MotionCheck.report(faults);
		check("the report sums up and judges each track", StringTools.startsWith(report, "motion trace: 9 tracks") && report.indexOf("WARN") > 0,
			report.split("\n")[0]);
		var json:Dynamic = haxe.Json.parse(MotionCheck.json(trace));
		check("the trace reads back as JSON, samples and expected values included", json.tracks.length == trace.tracks.length
			&& json.tracks[0].samples.length > 0 && json.tracks[0].samples[0].expected != null);

		// --- An input log: recorded at the input entry points, replayed into a fresh tree frame by frame ---
		function pad(into:LayoutTree, counts:Array<Int>, typed:Array<String>):Div {
			var target:Div = Owner.root(into, _ -> new Div({width: 100, height: 40, focusable: true, onClick: e -> counts.push(e.clickCount)}, null, into));
			ashui.input.Interaction.of(target.node).onTextInput(e -> typed.push(e.text));
			into.flush();
			into.computeLayout(target.node, 100, 40);
			return target;
		}
		ashui.input.InputClock.source = () -> scheduler.clock;
		var liveTree = new LayoutTree(), liveCounts = [], liveTyped = [];
		pad(liveTree, liveCounts, liveTyped);
		var log = ashui.debug.InputLog.start();
		function clickAt(x:Float) {
			ashui.input.Pointer.move(liveTree, x, 20);
			ashui.input.Pointer.press(liveTree);
			ashui.input.Pointer.release(liveTree);
		}
		clickAt(50);
		scheduler.tick(0.1);
		clickAt(51);
		scheduler.tick(1);
		clickAt(50);
		ashui.input.Keyboard.text(liveTree, "hi");
		log.stop();
		ashui.input.InputClock.source = null;
		var path = "input-log/session.hxs";
		log.save(path);
		var loaded = ashui.debug.InputLog.load(path);
		check("an input log records each input with its time, and reads back as written", log.entries.length == 10 && loaded.entries.length == 10
			&& Math.abs(loaded.entries[3].time - 0.1) < 1e-9 && Std.string(loaded.entries[9].record) == Std.string(log.entries[9].record)
			&& sys.FileSystem.exists("input-log/session.txt"), loaded.lines());
		var replayTree = new LayoutTree(), replayCounts = [], replayTyped = [];
		var replayRoot = pad(replayTree, replayCounts, replayTyped);
		var play = loaded.player();
		for (i in 0...80) {
			play(i, replayTree, replayRoot);
			scheduler.tick(1 / 60);
		}
		ashui.input.InputClock.source = null;
		check("a replay sends the same input at the same times: a double-click stays one, a click a second later does not",
			liveCounts.join(",") == "1,2,1" && replayCounts.join(",") == liveCounts.join(",") && replayTyped.join("") == "hi",
			[liveCounts, replayCounts, replayTyped]);
		check("nothing records while no log is", ashui.debug.InputLog.current == null);

		// --- Tree snapshots and their diff ---
		ashui.css.Css.load(".hov { width: 20px; height: 20px; background: #000000; margin: 2px 3px; padding: 4px; padding-left: 6px; border: 1px solid #000000; } .hov:hover { background: #ffffff; }");
		var shotTree = new LayoutTree();
		var shotRoot:Div = Owner.root(shotTree, _ -> new Div({width: 100, height: 100}, [new Div({classes: ["hov"], onClick: _ -> {}}, shotTree)], shotTree));
		function settle() {
			ashui.css.Css.update();
			shotTree.flush();
			shotTree.computeLayout(shotRoot.node, 100, 100);
		}
		settle();
		var first = ashui.debug.TreeSnapshot.take(shotTree);
		ashui.input.Pointer.move(shotTree, 5, 5);
		var extra:Div = Owner.root(shotTree, _ -> new Div({width: 30, height: 10}, shotTree));
		shotTree.addChild(shotRoot.node.id, extra.node.id);
		settle();
		var second = ashui.debug.TreeSnapshot.take(shotTree);
		var d = ashui.debug.TreeSnapshot.diff(first, second);
		var hovered = Lambda.find(d.changed, c -> c.label == "div.hov");
		check("a snapshot diff names the element added and the one hovered, its states and restyled background",
			first.elements.length == 2 && d.added.length == 1 && d.removed.length == 0 && hovered != null && hovered.states != null
			&& hovered.states.to.indexOf("hover") >= 0 && Lambda.exists(hovered.style, x -> x.name == "background" && x.to == "#ffffff"),
			ashui.debug.TreeSnapshot.lines(d));
		var inspector = new ashui.debug.InspectorOverlay();
		var seen = inspector.inspect(shotTree, inspector.target(shotTree));
		check("the inspector shows the element under the pointer: its box model, states, handlers and own CSS", seen != null && seen.label == "div.hov"
			&& seen.margin.join(",") == "2,3,2,3" && seen.padding.join(",") == "4,4,4,6" && seen.border.join(",") == "1,1,1,1"
			&& seen.states.indexOf("hover") >= 0 && seen.handlers.indexOf("click") >= 0 && seen.path.length == 1
			&& Lambda.exists(seen.style, x -> x.name == "background" && x.value == "#ffffff" && StringTools.startsWith(x.from, ".hov:hover ("))
			&& seen.overridden >= 1,
			seen == null ? null : [seen.label, seen.margin, seen.padding, seen.border, seen.states, seen.handlers, seen.path]);
		var hovIdentity = ashui.css.Identity.of(shotTree, shotTree.children(shotRoot.node.id)[0]);
		var backgrounds = ashui.css.Css.explain(hovIdentity).filter(o -> o.name == "background");
		check("explain lists each background that matched, the hover rule's winning", backgrounds.length == 2 && !backgrounds[0].wins
			&& backgrounds[1].wins && backgrounds[1].selector == ".hov:hover" && backgrounds[1].line == 1,
			[for (o in backgrounds) '${o.selector} ${o.line} ${o.wins}']);
		check("a diff line names the rule a restyled value came from",
			ashui.debug.TreeSnapshot.lines(d, shotTree).indexOf("background: #000000 -> #ffffff  [.hov:hover (sheet:1)]") >= 0,
			ashui.debug.TreeSnapshot.lines(d, shotTree));
		check("a snapshot reads back as JSON", (haxe.Json.parse(second.json()).elements : Array<Dynamic>).length == 3);

		// --- PNG decoding and frame regression ---
		var filtered = ashui.core.render.Png.decode(sys.io.File.getBytes("../fixtures/png/filters.png"));
		check("a PNG whose rows use the Sub, Up and Paeth filters decodes to its pixels", filtered.width == 3 && filtered.height == 3
			&& [for (i in 0...filtered.pixels.length) filtered.pixels.get(i)].join(",")
				== "0,200,50,255,3,180,50,248,6,160,50,241,10,200,90,255,13,180,90,248,16,160,90,241,20,200,130,255,23,180,130,248,26,160,130,241");
		function frameOf(mark:Int):haxe.io.Bytes {
			var pixels = haxe.io.Bytes.alloc(8 * 8 * 4);
			pixels.fill(0, pixels.length, 200);
			for (y in 2...4)
				for (x in 3...6)
					pixels.set((y * 8 + x) * 4, mark);
			return ashui.core.render.Png.encode(8, 8, pixels);
		}
		var regressionDir = "regression-out", baselineDir = "regression-baseline/frames";
		for (d in [regressionDir, baselineDir])
			sys.FileSystem.createDirectory(d);
		for (f in sys.FileSystem.readDirectory(baselineDir))
			sys.FileSystem.deleteFile(baselineDir + "/" + f);
		var first = ashui.debug.FrameRegression.check("frames", [frameOf(200), frameOf(200)], baselineDir, regressionDir);
		var same = ashui.debug.FrameRegression.check("frames", [frameOf(201), frameOf(200)], baselineDir, regressionDir);
		var moved = ashui.debug.FrameRegression.check("frames", [frameOf(200), frameOf(90), frameOf(200)], baselineDir, regressionDir);
		var changedFrame = moved.frames[1];
		check("a baseline is recorded first, matched within tolerance, and a changed frame found with its box and diff image",
			first.recorded && !same.recorded && same.failed == 0 && moved.failed == 1 && moved.frames[2] == null && changedFrame != null
			&& changedFrame.changed == 6 && changedFrame.box.x == 3 && changedFrame.box.y == 2 && changedFrame.box.w == 3 && changedFrame.box.h == 2
			&& sys.FileSystem.exists(regressionDir + "/diff-001.png"),
			sys.io.File.getContent(regressionDir + "/regression.txt"));

		var skewed = MotionTrace.start();
		var off = MotionTrace.begin(Keyframes, null, null, "@keyframes off (width)", "10px", "10px", 0, 0.2, Linear, null, "skewer");
		off.keyframes = [{offset: 0, easing: EaseIn}, {offset: 0.5, easing: Linear}, {offset: 1, easing: Linear}];
		// Each frame eased linearly in the first half, which declares ease-in.
		for (i in 1...13) {
			scheduler.tick(1 / 60);
			var p = Math.min(1, i / 12);
			var local = p < 0.5 ? p / 0.5 : (p - 0.5) / 0.5;
			off.sample(p, p, null, null, local);
		}
		off.finish(Completed);
		skewed.stop();
		check("a keyframe segment off its declared curve is reported", MotionCheck.check(off, skewed).issues
			.filter(i -> StringTools.startsWith(i, "off its keyframe curve") && i.indexOf("between 0% and 50%") > 0).length == 1,
			MotionCheck.check(off, skewed).issues);

		var jumps = MotionTrace.start();
		var jumped = MotionTrace.begin(Transition, null, null, "opacity", "0.5", "1", 0, 0.1, Linear, null, "jumper");
		jumped.finish(Snapped);
		jumps.stop();
		check("a change a transition covers that took effect at once is reported", MotionCheck.check(jumped, jumps).issues
			.filter(i -> StringTools.startsWith(i, "snapped: its transition declares 100ms")).length == 1, MotionCheck.check(jumped, jumps).issues);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
