package ashui.debug;

import ashui.core.render.Offscreen;
import ashui.core.render.Snapshot;
import ashui.layout.Element;
import ashui.layout.LayoutTree;

/**
	Motion tracing in a running window, set by `ASHUI_MOTION`:

	- `overlay` draws `MotionOverlay` over the window's frames;
	- `stream` does that too and writes each burst of motion, from the first
	  frame anything moves to three frames after everything stops, to
	  `<snapshot dir>/motion/live-<n>/` as `MotionRecorder` writes a
	  recording: frames, filmstrip, curves, report and JSON, with a line in
	  `events.log` for an agent tailing it.

	While a burst is written, animations advance a fixed sixtieth of a second
	per frame drawn rather than by the wall clock, so the time capturing a
	frame takes does not show in the motion: the report judges the motion,
	not the capture. Unset, nothing is traced. Safe to run with; `stream`
	slows the window while it writes.
**/
class MotionStream {
	static inline var STEP = 1 / 60;

	public final overlay:MotionOverlay;
	public final streaming:Bool;
	final offscreen:Offscreen;
	var trace:MotionTrace;
	var burst:Null<{dir:String, name:String, pngs:Array<haxe.io.Bytes>, times:Array<Float>, quiet:Int, started:Float}> = null;
	var bursts = 0;
	var owed = false;

	/** The mode `ASHUI_MOTION` asks for on `offscreen`, or null when it is unset. **/
	public static function fromEnvironment(offscreen:Offscreen):Null<MotionStream> {
		return switch Sys.getEnv("ASHUI_MOTION") {
			case "overlay": new MotionStream(offscreen, false);
			case "stream": new MotionStream(offscreen, true);
			case _: null;
		}
	}

	public function new(offscreen:Offscreen, streaming:Bool) {
		this.offscreen = offscreen;
		this.streaming = streaming;
		trace = MotionTrace.start();
		overlay = new MotionOverlay(trace);
		offscreen.overlays.push(overlay);
	}

	/** The step animations take on this tick: a sixtieth for each frame captured in a burst, nothing between, and `real` otherwise. **/
	public function step(real:Float):Float {
		if (burst == null)
			return real;
		if (!owed)
			return 0;
		owed = false;
		return STEP;
	}

	/** Whether motion is being written now, so the window keeps drawing. **/
	public function busy():Bool
		return burst != null;

	/** After a frame is drawn: starts, continues or ends a burst. **/
	public function frame(tree:LayoutTree, root:Element, width:Int, height:Int):Void {
		if (!streaming)
			return;
		var moving = Lambda.exists(trace.tracks, t -> t.running && !(t.kind == Keyframes && t.iterations == Math.POSITIVE_INFINITY));
		if (burst == null) {
			if (!moving)
				return;
			var name = 'live-${++bursts}';
			var dir = haxe.io.Path.join([Snapshot.dir(), "motion", name]);
			MotionRecorder.clean(dir);
			burst = {dir: dir, name: name, pngs: [], times: [], quiet: 0, started: MotionTrace.clock()};
		}
		var b = burst;
		var png = MotionRecorder.capture(offscreen, tree, root, width, height, 1);
		sys.io.File.saveBytes(haxe.io.Path.join([b.dir, 'frame-${StringTools.lpad(Std.string(b.pngs.length), "0", 3)}.png']), png);
		b.pngs.push(png);
		b.times.push(MotionTrace.clock() - b.started);
		owed = true;
		b.quiet = moving ? 0 : b.quiet + 1;
		if (b.quiet < 3)
			return;
		// Written out, and a fresh trace for the next burst, so a long session's trace does not grow without end.
		trace.stop();
		MotionRecorder.write(b.name, b.dir, offscreen, trace, b.pngs, b.times, width, height, 12);
		burst = null;
		owed = false;
		trace = MotionTrace.start();
		overlay.trace = trace;
	}
}
