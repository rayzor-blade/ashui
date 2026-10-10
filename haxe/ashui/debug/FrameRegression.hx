package ashui.debug;

import ashui.core.render.Png;
import haxe.io.Bytes;

/** How one frame differs from its baseline. **/
typedef FrameDifference = {
	/** Pixels whose colour moved by more than the tolerance on any channel. **/
	changed:Int,
	total:Int,
	/** The largest change on any channel of any pixel, 0 to 255. **/
	maxDelta:Int,
	/** The box around every changed pixel; null when none changed. **/
	box:Null<{x:Int, y:Int, w:Int, h:Int}>,
	/** Whether the two are of different sizes, which is a change in itself. **/
	resized:Bool
}

/** A recording against its baseline: each frame's difference, and what the baseline has that it does not. **/
typedef RegressionResult = {
	name:String,
	/** By frame, in order; null for a frame the baseline does not have. **/
	frames:Array<Null<FrameDifference>>,
	/** Frames the baseline has past the recording's last. **/
	missing:Int,
	/** Frames with any pixel changed. **/
	failed:Int,
	/** Where the report and diff images went. **/
	dir:String,
	/** Whether this run wrote the baseline rather than comparing with one. **/
	recorded:Bool
}

/**
	Frame regression: a recording's frames against a baseline kept from an
	earlier run. Each frame is compared pixel by pixel, within a tolerance
	for the last bit of rounding a GPU may differ by; a frame that changed
	gets `diff-NNN.png` beside it, the baseline faded with what changed in
	red, and `regression.txt` sums it up.

	`MotionRecorder` checks against `$ASHUI_BASELINE/<name>/` when
	`ASHUI_BASELINE` names a directory: the first run records the baseline,
	later ones compare; `ASHUI_BASELINE_UPDATE=1` records it again. It
	writes a line to `events.log` either way.
**/
class FrameRegression {
	/** How far a channel may move, 0 to 255, before a pixel counts as changed. **/
	public static var tolerance = 2;

	/** How frame `b` differs from baseline `a`, both PNGs; and, when they differ, the diff image as a PNG. **/
	public static function compare(a:Bytes, b:Bytes):{difference:FrameDifference, diff:Null<Bytes>} {
		var x = Png.decode(a), y = Png.decode(b);
		if (x.width != y.width || x.height != y.height) {
			var total = y.width * y.height;
			return {
				difference: {changed: total, total: total, maxDelta: 255, box: {x: 0, y: 0, w: y.width, h: y.height}, resized: true},
				diff: null
			};
		}
		var w = x.width, h = x.height;
		var changed = 0, maxDelta = 0;
		var left = w, top = h, right = -1, bottom = -1;
		var out = Bytes.alloc(w * h * 4);
		for (i in 0...w * h) {
			var p = i * 4;
			var delta = 0;
			for (c in 0...4) {
				var d = x.pixels.get(p + c) - y.pixels.get(p + c);
				if (d < 0)
					d = -d;
				if (d > delta)
					delta = d;
			}
			if (delta > maxDelta)
				maxDelta = delta;
			if (delta > tolerance) {
				changed++;
				var px = i % w, py = Std.int(i / w);
				if (px < left)
					left = px;
				if (px > right)
					right = px;
				if (py < top)
					top = py;
				if (py > bottom)
					bottom = py;
				out.set(p, 255);
				out.set(p + 1, 0);
				out.set(p + 2, 0);
			} else {
				// The baseline as a faded grey, so what changed stands out.
				var grey = Std.int((x.pixels.get(p) + x.pixels.get(p + 1) + x.pixels.get(p + 2)) / 3);
				var faded = 160 + (grey >> 2);
				out.set(p, faded);
				out.set(p + 1, faded);
				out.set(p + 2, faded);
			}
			out.set(p + 3, 255);
		}
		return {
			difference: {
				changed: changed,
				total: w * h,
				maxDelta: maxDelta,
				box: changed == 0 ? null : {x: left, y: top, w: right - left + 1, h: bottom - top + 1},
				resized: false
			},
			diff: changed == 0 ? null : Png.encode(w, h, out)
		};
	}

	/**
		The frames of recording `name`, PNGs in order, against the baseline in
		`baseline`: records them there when it has none or `update` is set,
		compares them otherwise, writing diff images and `regression.txt` to
		`dir`. `log` takes a line saying what it did, as `Snapshot.event` writes
		one to `events.log`.
	**/
	public static function check(name:String, frames:Array<Bytes>, baseline:String, dir:String, update = false, ?log:String->Void):RegressionResult {
		var have = sys.FileSystem.exists(baseline) ? [for (f in sys.FileSystem.readDirectory(baseline)) if (isFrame(f)) f] : [];
		have.sort(Reflect.compare);
		var result:RegressionResult = {
			name: name,
			frames: [],
			missing: 0,
			failed: 0,
			dir: sys.FileSystem.absolutePath(dir),
			recorded: false
		};
		if (update || have.length == 0) {
			if (!sys.FileSystem.exists(baseline))
				sys.FileSystem.createDirectory(baseline);
			for (f in have)
				sys.FileSystem.deleteFile(haxe.io.Path.join([baseline, f]));
			for (i => png in frames)
				sys.io.File.saveBytes(haxe.io.Path.join([baseline, frameName(i)]), png);
			result.recorded = true;
			if (log != null)
				log('regression $name recorded ${sys.FileSystem.absolutePath(baseline)} frames=${frames.length}');
			return result;
		}
		for (i => png in frames) {
			var path = haxe.io.Path.join([baseline, frameName(i)]);
			if (!sys.FileSystem.exists(path)) {
				result.frames.push(null);
				continue;
			}
			var c = compare(sys.io.File.getBytes(path), png);
			result.frames.push(c.difference);
			if (c.difference.changed > 0)
				result.failed++;
			if (c.diff != null)
				sys.io.File.saveBytes(haxe.io.Path.join([dir, 'diff-${pad(i)}.png']), c.diff);
		}
		result.missing = Std.int(Math.max(0, have.length - frames.length));
		sys.io.File.saveContent(haxe.io.Path.join([dir, "regression.txt"]), report(result));
		if (log != null)
			log('regression $name ${result.dir} frames=${frames.length} changed=${result.failed} missing=${result.missing}');
		return result;
	}

	/** A result as text: a summary line, then a line per frame that changed or that the baseline lacks. **/
	public static function report(r:RegressionResult):String {
		var extra = [for (f in r.frames) if (f == null) f].length;
		var out = ['regression ${r.name}: ${r.failed} of ${r.frames.length} frames changed'
			+ (extra > 0 ? ', $extra new' : "") + (r.missing > 0 ? ', ${r.missing} missing' : "")];
		for (i => f in r.frames) {
			if (f == null)
				out.push('frame ${pad(i)}: not in the baseline');
			else if (f.resized)
				out.push('frame ${pad(i)}: a different size');
			else if (f.changed > 0)
				out.push('frame ${pad(i)}: ${f.changed} pixels (${Math.round(f.changed * 10000 / f.total) / 100}%) changed, up to ${f.maxDelta}, in ${f.box.w}x${f.box.h} at ${f.box.x},${f.box.y}');
		}
		return out.join("\n") + "\n";
	}

	static function isFrame(f:String):Bool
		return StringTools.startsWith(f, "frame-") && StringTools.endsWith(f, ".png");

	static function frameName(i:Int):String
		return 'frame-${pad(i)}.png';

	static function pad(i:Int):String
		return StringTools.lpad(Std.string(i), "0", 3);
}
