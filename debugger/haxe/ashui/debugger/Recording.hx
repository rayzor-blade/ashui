package ashui.debugger;

import ashui.types.Bitmap;

/** One animation in a recording, as `trace.json` gives it. **/
typedef Track = {
	id:Int,
	kind:String,
	label:String,
	property:String,
	from:String,
	to:String,
	delay:Float,
	duration:Float,
	curve:String,
	began:Float,
	ended:Null<Float>,
	end:String,
	issues:Array<String>,
	notes:Array<String>,
	/** Where its element was drawn, frame by frame. **/
	rects:Array<{t:Float, x:Float, y:Float, w:Float, h:Float}>
}

/**
	A recording `MotionRecorder` wrote: its frames and their times, its
	motion trace, what changed in the tree frame by frame, its report, and
	how it compared with its baseline when it was checked against one.
	Times are seconds from the start of the recording.
**/
class Recording {
	public final dir:String;
	public final name:String;
	/** Each frame's PNG, in order. **/
	public final frames:Array<String>;
	/** Each frame's time. **/
	public final times:Array<Float>;
	public final width:Int;
	public final height:Int;
	public final tracks:Array<Track>;
	/** How long it ran: its last frame's time, or its last track's end. **/
	public final span:Float;
	/** What changed in the tree at each frame that changed it, as `tree.txt` lists it. **/
	public final changes:Map<Int, Array<String>>;
	public final report:String;
	/** `regression.txt`, when it was checked against a baseline. **/
	public final regression:Null<String>;
	final bitmaps:Map<Int, Bitmap> = [];

	public function new(dir:String) {
		this.dir = dir;
		name = haxe.io.Path.withoutDirectory(haxe.io.Path.removeTrailingSlashes(dir));
		frames = [for (f in sys.FileSystem.readDirectory(dir)) if (StringTools.startsWith(f, "frame-") && StringTools.endsWith(f, ".png")) f];
		frames.sort(Reflect.compare);
		frames = [for (f in frames) haxe.io.Path.join([dir, f])];
		var meta:Dynamic = read("frames.json", s -> haxe.Json.parse(s));
		times = meta != null ? (meta.times : Array<Float>) : [for (i in 0...frames.length) i / 60];
		width = meta != null ? meta.width : 0;
		height = meta != null ? meta.height : 0;
		var trace:Dynamic = read("trace.json", s -> haxe.Json.parse(s));
		var started:Float = trace == null ? 0 : trace.started;
		tracks = trace == null ? [] : [
			for (t in (trace.tracks : Array<Dynamic>))
				{
					id: t.id,
					kind: t.kind,
					label: t.label,
					property: t.property,
					from: t.from,
					to: t.to,
					delay: t.delay,
					duration: t.duration,
					curve: t.curve,
					began: t.began - started,
					ended: t.ended == null ? null : t.ended - started,
					end: t.end,
					issues: t.issues,
					notes: t.notes,
					rects: [for (r in (t.rects : Array<Dynamic>)) {t: r.clock - started, x: r.x, y: r.y, w: r.w, h: r.h}]
				}
		];
		var last = times.length == 0 ? 0.0 : times[times.length - 1];
		for (t in tracks)
			last = Math.max(last, t.ended != null ? t.ended : t.began + t.delay + t.duration);
		span = Math.max(last, 1 / 60);
		changes = read("tree.txt", parseChanges);
		if (changes == null)
			changes = [];
		report = read("report.txt", s -> s);
		regression = read("regression.txt", s -> s);
	}

	/** The recordings under `root`, `.ashui/snapshots/motion` by default: each directory with frames in it, newest first. **/
	public static function list(?root:String):Array<String> {
		var base = root != null ? root : haxe.io.Path.join([snapshots(), "motion"]);
		if (!sys.FileSystem.exists(base))
			return [];
		var out = [
			for (d in sys.FileSystem.readDirectory(base))
				if (sys.FileSystem.isDirectory(haxe.io.Path.join([base, d])) && sys.FileSystem.exists(haxe.io.Path.join([base, d, "frame-000.png"])))
					haxe.io.Path.join([base, d])
		];
		out.sort((a, b) -> Reflect.compare(stamp(b), stamp(a)));
		return out;
	}

	static function stamp(dir:String):Float
		return sys.FileSystem.stat(haxe.io.Path.join([dir, "frame-000.png"])).mtime.getTime();

	/** Where snapshots go, as `Snapshot.dir` says. **/
	static function snapshots():String {
		var dir = Sys.getEnv("ASHUI_SNAPSHOT_DIR");
		return dir != null && dir != "" ? dir : ".ashui/snapshots";
	}

	/** Frame `i`'s image, read the first time it is asked for. **/
	public function bitmap(i:Int):Bitmap {
		var b = bitmaps.get(i);
		if (b == null)
			bitmaps.set(i, b = Bitmap.load(frames[i]));
		return b;
	}

	/** The frame shown at time `t`: the last at or before it. **/
	public function frameAt(t:Float):Int {
		var i = 0;
		while (i + 1 < times.length && times[i + 1] <= t + 1e-9)
			i++;
		return i;
	}

	/** Where `track`'s element was drawn at `t`: its last rect at or before then; null before its first or after it ended. **/
	public static function rectAt(track:Track, t:Float):Null<{x:Float, y:Float, w:Float, h:Float}> {
		var found = null;
		for (r in track.rects)
			if (r.t <= t + 1e-9)
				found = r;
		if (found == null || (track.ended != null && t > track.ended + 1e-9))
			return null;
		return found;
	}

	/** Tracks with problems. **/
	public function warnings():Int
		return [for (t in tracks) if (t.issues.length > 0) t].length;

	function read<T>(file:String, parse:String->T):Null<T> {
		var path = haxe.io.Path.join([dir, file]);
		return sys.FileSystem.exists(path) ? parse(sys.io.File.getContent(path)) : null;
	}

	/** `tree.txt`'s blocks, each headed `frame N (Tms)`, by frame. **/
	static function parseChanges(text:String):Map<Int, Array<String>> {
		var out = new Map<Int, Array<String>>();
		var current:Null<Array<String>> = null;
		var head = ~/^frame (\d+) \(/;
		for (line in text.split("\n")) {
			if (head.match(line))
				out.set(Std.parseInt(head.matched(1)), current = []);
			else if (current != null && line != "")
				current.push(line);
		}
		return out;
	}
}
