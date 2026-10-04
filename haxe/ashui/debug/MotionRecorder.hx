package ashui.debug;

import ashui.core.render.Offscreen;
import ashui.core.render.Png;
import ashui.core.render.Snapshot;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Text;
import gpu.GpuTextureViewDescriptor;

typedef MotionRecordOptions = {
	/** Frames a second, and the most frames to record. **/
	?fps:Int,
	?frames:Int,
	/** Image pixels per layout unit. **/
	?scale:Float,
	/** Seconds the UI runs before recording starts, so animations it opens with are done. **/
	?settle:Float,
	/** Called before each frame, to hover, press or change something then. **/
	?before:(frame:Int, tree:LayoutTree, root:Element) -> Void,
	/** Frames recorded at least: past the last one `before` acts in. After them it stops once nothing has moved for three frames. **/
	?minFrames:Int,
	/** Whether the frames show the motion overlay; true by default. **/
	?overlay:Bool,
	/** Frames in the filmstrip, picked evenly; 12 by default. **/
	?thumbs:Int,
	/** The page colour frames are cleared to. **/
	?clear:Int
}

/** What a recording wrote, and the trace it made. **/
typedef MotionRecording = {
	dir:String,
	frames:Array<String>,
	filmstrip:String,
	curves:Null<String>,
	report:String,
	trace:MotionTrace
}

/**
	Records a UI's motion for review: runs it frame by frame on a fixed step,
	as `Snapshot.sequence` does, with a motion trace recording and its
	overlay drawn over every frame, and writes to
	`<snapshot dir>/motion/<name>/`:

	- `frame-000.png` …, each frame with its trails, bars and curves;
	- `filmstrip.png`, a contact sheet of frames picked evenly, each with
	  its number and time, to see a whole animation in one image;
	- `curves.png`, every track's curve as declared and as it ran;
	- `report.txt`, `MotionCheck`'s verdict on every track, and
	  `trace.json`, the whole trace.

	A line goes to `events.log` naming the directory and how many tracks had
	problems, for an agent tailing it to read the report and look at the
	filmstrip.
**/
class MotionRecorder {
	public static function record(name:String, width:Int, height:Int, build:Void->Element, ?options:MotionRecordOptions):MotionRecording {
		var o:MotionRecordOptions = options == null ? {} : options;
		var fps = o.fps == null ? 60 : o.fps;
		var frames = o.frames == null ? 60 : o.frames;
		if (SceneWindow.wanted()) {
			SceneWindow.open(name, width, height, build, o.before, fps, frames);
			return {dir: "", frames: [], filmstrip: "", curves: null, report: 'motion $name opened in a window', trace: MotionTrace.start()};
		}
		var scale = o.scale == null ? 1.0 : o.scale;
		var dir = haxe.io.Path.join([Snapshot.dir(), "motion", name]);
		clean(dir);
		var offscreen = Snapshot.renderer();
		offscreen.clear = o.clear == null ? 0xffffff : o.clear;
		offscreen.clearAlpha = 1;
		offscreen.scale = scale;

		// Started before the UI is built, so an animation it starts with, a loop that never ends, is in the trace.
		var trace = MotionTrace.start();
		var tree = new LayoutTree();
		var root:Element = Owner.root(tree, _ -> build());
		function layout() {
			ashui.css.Css.setViewport(width, height);
			ashui.css.Css.update();
			tree.flush();
			tree.computeLayout(root.node, width, height);
		}
		layout();
		if (o.settle != null)
			for (_ in 0...Math.ceil(o.settle * fps)) {
				Offscreen.advance(1 / fps);
				layout();
			}

		// What ran its course while it settled is not what the recording is of.
		var settled = [for (t in trace.tracks) if (!t.running) t];
		for (t in settled)
			trace.tracks.remove(t);
		var overlay = o.overlay == false ? null : new MotionOverlay(trace);
		// curves.png plots every track; on the frames the panel would only cover the UI.
		if (overlay != null)
			overlay.curves = false;
		if (overlay != null)
			offscreen.overlays.push(overlay);
		var paths = [], pngs = [], times = [];
		var minFrames = o.minFrames == null ? 0 : o.minFrames;
		var quiet = 0;
		try {
			for (i in 0...frames) {
				if (o.before != null)
					o.before(i, tree, root);
				if (i > 0)
					Offscreen.advance(1 / fps);
				layout();
				if (overlay == null)
					trace.observe(tree);
				var png = capture(offscreen, tree, root, width, height, scale);
				var path = haxe.io.Path.join([dir, 'frame-${StringTools.lpad(Std.string(i), "0", 3)}.png']);
				sys.io.File.saveBytes(path, png);
				paths.push(sys.FileSystem.absolutePath(path));
				pngs.push(png);
				times.push(MotionTrace.clock() - trace.started);
				// Done once nothing has moved for three frames; a looping animation never stops, so it does not count.
				var moving = Lambda.exists(trace.tracks, t -> t.running && !(t.kind == Keyframes && t.iterations == Math.POSITIVE_INFINITY));
				quiet = moving ? 0 : quiet + 1;
				if (i + 1 >= minFrames && quiet >= 3 && trace.tracks.length > 0)
					break;
			}
		} catch (e:haxe.Exception) {
			if (overlay != null)
				offscreen.overlays.remove(overlay);
			trace.stop();
			// Where it was thrown, which a rethrow from here would hide.
			Snapshot.event('error motion $name ${e.message} ${e.stack.toString().split("\n").join(" | ")}');
			throw e;
		}
		if (overlay != null)
			offscreen.overlays.remove(overlay);
		trace.stop();

		var written = write(name, dir, offscreen, trace, pngs, times, width, height, o.thumbs == null ? 12 : o.thumbs);
		return {
			dir: sys.FileSystem.absolutePath(dir),
			frames: paths,
			filmstrip: written.filmstrip,
			curves: written.curves,
			report: written.report,
			trace: trace
		};
	}

	/**
		Writes a recorded trace's report, JSON, filmstrip of `pngs` (frames
		taken `times` seconds into it) and curves to `dir`, and the line in
		`events.log` that says so.
	**/
	public static function write(name:String, dir:String, offscreen:Offscreen, trace:MotionTrace, pngs:Array<haxe.io.Bytes>, times:Array<Float>,
			width:Int, height:Int, thumbs:Int):{report:String, filmstrip:String, curves:Null<String>} {
		var report = MotionCheck.report(trace);
		sys.io.File.saveContent(haxe.io.Path.join([dir, "report.txt"]), report);
		sys.io.File.saveContent(haxe.io.Path.join([dir, "trace.json"]), MotionCheck.json(trace));
		var strip = filmstrip(offscreen, pngs, times, width, height, thumbs, haxe.io.Path.join([dir, "filmstrip.png"]));
		var curves = trace.tracks.length == 0 ? null : curveSheet(offscreen, trace, haxe.io.Path.join([dir, "curves.png"]));
		var warned = [for (t in trace.tracks) if (MotionCheck.check(t, trace).issues.length > 0) t].length;
		Snapshot.event('motion $name ${sys.FileSystem.absolutePath(dir)} frames=${pngs.length} tracks=${trace.tracks.length} warnings=$warned');
		return {report: report, filmstrip: strip, curves: curves};
	}

	/** The directory, made, with the frames of a recording before taken out. **/
	public static function clean(dir:String):Void {
		sys.FileSystem.createDirectory(dir);
		for (f in sys.FileSystem.readDirectory(dir))
			if (StringTools.endsWith(f, ".png") || f == "report.txt" || f == "trace.json")
				sys.FileSystem.deleteFile(haxe.io.Path.join([dir, f]));
	}

	/** `root` of `tree`, laid out, drawn with the overlays as PNG bytes. **/
	public static function capture(offscreen:Offscreen, tree:LayoutTree, root:Element, width:Int, height:Int, scale:Float):haxe.io.Bytes {
		var pw = Math.round(width * scale), ph = Math.round(height * scale);
		// Drawn at its own size, whatever size a window's frames are.
		var saved = {scale: offscreen.scale, w: offscreen.targetWidth, h: offscreen.targetHeight};
		offscreen.scale = scale;
		offscreen.targetWidth = null;
		offscreen.targetHeight = null;
		var texture = offscreen.createTexture(pw, ph);
		offscreen.renderTree(tree, root.node, texture.createView(new GpuTextureViewDescriptor()), width, height);
		var pixels = offscreen.readRgba8(texture, pw, ph);
		texture.destroy();
		offscreen.scale = saved.scale;
		offscreen.targetWidth = saved.w;
		offscreen.targetHeight = saved.h;
		return Png.encode(pw, ph, pixels);
	}

	/** A UI built in a tree of its own, drawn at `width` × `height` on a dark page, saved as PNG at `path`. **/
	static function sheet(offscreen:Offscreen, width:Int, height:Int, build:LayoutTree->Element, path:String):String {
		var tree = new LayoutTree();
		var saved = {clear: offscreen.clear, alpha: offscreen.clearAlpha, scale: offscreen.scale, overlays: offscreen.overlays.copy()};
		offscreen.clear = 0x11131a;
		offscreen.clearAlpha = 1;
		offscreen.scale = 1;
		offscreen.overlays.resize(0);
		Owner.root(tree, dispose -> {
			var root = build(tree);
			tree.flush();
			tree.computeLayout(root.node, width, height);
			sys.io.File.saveBytes(path, capture(offscreen, tree, root, width, height, 1));
			dispose();
		});
		tree.dispose();
		offscreen.clear = saved.clear;
		offscreen.clearAlpha = saved.alpha;
		offscreen.scale = saved.scale;
		for (o in saved.overlays)
			offscreen.overlays.push(o);
		return sys.FileSystem.absolutePath(path);
	}

	/** Frames picked evenly, first and last among them, in a grid, each captioned with its number and time. **/
	static function filmstrip(offscreen:Offscreen, pngs:Array<haxe.io.Bytes>, times:Array<Float>, width:Int, height:Int, count:Int, path:String):String {
		var picks = [];
		var n = Std.int(Math.min(count, pngs.length));
		for (k in 0...n) {
			var i = n == 1 ? 0 : Math.round(k * (pngs.length - 1) / (n - 1));
			if (picks.indexOf(i) < 0)
				picks.push(i);
		}
		var columns = Std.int(Math.min(3, picks.length));
		var rows = Math.ceil(picks.length / Math.max(columns, 1));
		var thumbWidth = Math.min(480.0, width * offscreen.scale), thumbHeight = thumbWidth * height / width;
		var gap = 10.0, caption = 16.0;
		var sheetWidth = Math.ceil(columns * (thumbWidth + gap) + gap), sheetHeight = Math.ceil(rows * (thumbHeight + caption + gap) + gap);
		return sheet(offscreen, sheetWidth, sheetHeight, tree -> {
			var cells:Array<Element> = [];
			for (k in 0...picks.length) {
				var i = picks[k];
				var image = new ashui.ui.Image(ashui.types.Bitmap.fromBytes(pngs[i]), {width: thumbWidth, height: thumbHeight}, tree);
				var label = new Text('frame $i  ${MotionCheck.ms(times[i])}', {color: new Color(0xd0d4dc), fontSize: 11, wrap: false}, tree);
				cells.push(new Div({
					position: Position.Absolute,
					left: gap + (k % columns) * (thumbWidth + gap),
					top: gap + Std.int(k / columns) * (thumbHeight + caption + gap),
					flexDirection: FlexDirection.Column,
					gap: 3
				}, [label, image], tree));
			}
			new Div({width: sheetWidth, height: sheetHeight}, cells, tree);
		}, path);
	}

	/** Every track's curve, large, in a grid. **/
	static function curveSheet(offscreen:Offscreen, trace:MotionTrace, path:String):String {
		var w = 320.0, h = 200.0, gap = 10.0;
		var columns = Std.int(Math.min(3, trace.tracks.length));
		var rows = Math.ceil(trace.tracks.length / columns);
		var sheetWidth = Math.ceil(columns * (w + gap) + gap), sheetHeight = Math.ceil(rows * (h + gap) + gap);
		return sheet(offscreen, sheetWidth, sheetHeight, tree -> {
			var out:Array<Element> = [];
			for (k in 0...trace.tracks.length)
				MotionOverlay.chart(tree, trace.tracks[k], gap + (k % columns) * (w + gap), gap + Std.int(k / columns) * (h + gap), w, h, 1, out);
			new Div({width: sheetWidth, height: sheetHeight}, out, tree);
		}, path);
	}
}
