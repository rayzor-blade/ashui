package ashui.debug;

import ashui.layout.LayoutTree;
import ashui.theme.Easing;
import ashui.debug.MotionTrack.MotionKind;
import ashui.debug.MotionTrack.MotionEnd;

/**
	A recording of every animation while it runs: each property tween,
	`@keyframes` run, layout animation and spring becomes a `MotionTrack`,
	what it was declared to do and, frame by frame, what it did. While no
	trace is started the animation code checks one null and records
	nothing.

	```haxe
	var trace = MotionTrace.start();
	// … tick and draw frames …
	trace.stop();
	for (track in trace.tracks)
		trace(MotionCheck.check(track).line());
	```

	`MotionOverlay` draws a trace over the frames, `MotionRecorder` writes
	one out as frames, a filmstrip, curves and a report.
**/
class MotionTrace {
	/** The trace recording now, if one is. **/
	public static var current(default, null):Null<MotionTrace> = null;

	public final tracks:Array<MotionTrack> = [];
	/** The scheduler's clock when it started. **/
	public final started:Float;
	public var stopped(default, null):Null<Float> = null;
	/** Whether `observe` has been called: only then do missing drawn rects mean anything. **/
	public var observed(default, null) = false;
	var nextId = 1;

	function new() {
		started = clock();
	}

	/** Starts recording, ending a trace already recording. **/
	public static function start():MotionTrace {
		if (current != null)
			current.stop();
		return current = new MotionTrace();
	}

	/** Stops recording; tracks still running end as running. **/
	public function stop():Void {
		if (stopped != null)
			return;
		stopped = clock();
		if (current == this)
			current = null;
	}

	/** The time animations run on: the main scheduler's clock. **/
	public static inline function clock():Float
		return ashui.animation.AnimationScheduler.main.clock;

	/** Tracks running now. **/
	public function running():Array<MotionTrack>
		return [for (t in tracks) if (t.running) t];

	/**
		A new track, when a trace is recording; null otherwise, so a caller
		does `var t = MotionTrace.begin(…)` and samples `t` only when it is not
		null. A track still running on the same element and property ends,
		interrupted.
	**/
	public static function begin(kind:MotionKind, tree:Null<LayoutTree>, node:Null<haxe.Int64>, property:String, from:String, to:String, delay:Float,
			duration:Float, easing:Null<Easing>, ?spring:ashui.animation.SpringConfig, ?label:String):Null<MotionTrack> {
		var trace = current;
		if (trace == null)
			return null;
		var name = label != null ? label : describe(tree, node);
		var track = new MotionTrack(trace.nextId++, kind, tree, node, name, property, from, to, delay, duration, easing, curveText(easing, spring),
			spring, clock());
		var key = track.key();
		for (t in trace.tracks)
			if (t.running && t.key() == key)
				t.finish(Interrupted);
		trace.tracks.push(track);
		return track;
	}

	/**
		Records where each running track's element is drawn in `tree` now,
		after layout: its box, moved by what a layout animation has left of
		its move. The overlay calls this each frame; a recorder without one
		calls it itself.
	**/
	public function observe(tree:LayoutTree):Void {
		observed = true;
		var now = clock();
		for (t in tracks) {
			if (t.tree != tree || t.node == null)
				continue;
			// A track that ended this frame still gets the frame it ended in.
			if (!t.running && (t.ended == null || t.ended < now))
				continue;
			var last = t.lastRect();
			if (last != null && last.clock == now)
				continue;
			// Only where it is drawn: under the tree's root, not detached, as a closed popover's panel is.
			var root = tree.root;
			if (root == null || (t.node != root.id && tree.ancestors(t.node).indexOf(root.id) < 0))
				continue;
			var b = tree.getBounds(new ashui.layout.Node(t.node));
			if (b == null)
				continue;
			var x:Float = b.x, y:Float = b.y, w:Float = b.width, h:Float = b.height;
			var s = t.samples.length == 0 ? null : t.samples[t.samples.length - 1];
			if (t.kind == Layout && s != null && t.running) {
				x += s.dx;
				y += s.dy;
				if (s.w >= 0) {
					w = s.w;
					h = s.h;
				}
			}
			t.rects.push({clock: now, x: x, y: y, w: w, h: h});
		}
	}

	/** An element as a selector: its tag, classes and id, as CSS sees it. **/
	public static function describe(tree:Null<LayoutTree>, node:Null<haxe.Int64>):String {
		if (tree == null || node == null)
			return "?";
		var identity = ashui.css.Identity.of(tree, node);
		if (identity == null)
			return '#node${haxe.Int64.toStr(node)}';
		var tag = identity.types.length > 0 ? identity.types[0] : "div";
		var classes = identity.classes();
		var out = tag + [for (c in classes) '.$c'].join("");
		var id = identity.id;
		return id != null && id != "" ? out + '#$id' : out;
	}

	/** A curve as CSS writes it, or a spring's constants. **/
	public static function curveText(easing:Null<Easing>, ?spring:ashui.animation.SpringConfig):String {
		if (spring != null)
			return 'spring(stiffness ${spring.stiffness}, damping ${spring.damping}, mass ${spring.mass})';
		return switch easing {
			case null: "none";
			case Linear: "linear";
			case Steps(n, start): 'steps($n, ${start ? "start" : "end"})';
			case e:
				var p = EasingTools.controlPoints(e);
				'cubic-bezier(${[for (v in p) round(v, 3)].join(", ")})';
		}
	}

	static function round(v:Float, places:Int):Float {
		var f = Math.pow(10, places);
		return Math.round(v * f) / f;
	}
}
