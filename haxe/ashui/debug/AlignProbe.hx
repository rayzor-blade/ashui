package ashui.debug;

import ashui.core.render.Png;
import ashui.core.render.Snapshot;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import gpu.GpuTextureViewDescriptor;

/** One box measured: where it is, where its ink is, and how far the ink sits off its middle. **/
typedef AlignResult = {
	final label:String;
	final box:{x:Float, y:Float, width:Float, height:Float};
	/** The drawn content's bounds, null when nothing is drawn inside. **/
	final ink:Null<{x:Float, y:Float, width:Float, height:Float}>;
	/** Right of the middle is positive, in layout units. **/
	final dx:Float;
	/** Below the middle is positive, in layout units. **/
	final dy:Float;
}

/**
	Measures how well what boxes hold is centred in them, from what is
	drawn: each box is rendered, its background read just inside its left
	edge, and the ink is every pixel inside it that is neither that
	background nor the page. A text's own line box, its ascent and
	descent, does not count: the glyphs do, as an eye sees them.

	`measure` builds the UI, draws it at `scale`, and returns a result for
	each node whose identity has an `id`; `report` sets them out, and
	`record` also writes an annotated PNG, each box's middle crossed in
	blue and its ink framed in red, to `.ashui/snapshots/align/<name>/`.
**/
class AlignProbe {
	/** How far inside a box its edge, border and focus ring are passed over, in layout units. **/
	public static var inset = 3.0;

	/** How different from the background and the page a pixel is to count as ink, in summed 8-bit channels. **/
	public static var threshold = 60;

	public static function record(name:String, width:Int, height:Int, build:Void->Element, scale = 2.0, page = 0xffffff):Array<AlignResult> {
		var dir = haxe.io.Path.join([Snapshot.dir(), "align", name]);
		sys.FileSystem.createDirectory(dir);
		var drawn = draw(width, height, build, scale, page);
		var results = drawn.results;
		var pw = drawn.pw, ph = drawn.ph, px = drawn.pixels;
		function plot(x:Float, y:Float, rgb:Int) {
			var ix = Math.round(x * scale), iy = Math.round(y * scale);
			if (ix < 0 || iy < 0 || ix >= pw || iy >= ph)
				return;
			var o = (iy * pw + ix) * 4;
			px.set(o, (rgb >> 16) & 0xff);
			px.set(o + 1, (rgb >> 8) & 0xff);
			px.set(o + 2, rgb & 0xff);
			px.set(o + 3, 255);
		}
		function frame(r:{x:Float, y:Float, width:Float, height:Float}, rgb:Int) {
			var step = 1 / scale;
			var x = r.x;
			while (x <= r.x + r.width) {
				plot(x, r.y, rgb);
				plot(x, r.y + r.height, rgb);
				x += step;
			}
			var y = r.y;
			while (y <= r.y + r.height) {
				plot(r.x, y, rgb);
				plot(r.x + r.width, y, rgb);
				y += step;
			}
		}
		for (r in results) {
			var b = r.box;
			var step = 1 / scale;
			var x = b.x;
			while (x <= b.x + b.width) {
				plot(x, b.y + b.height / 2, 0x3b82f6);
				x += step * 3;
			}
			var y = b.y;
			while (y <= b.y + b.height) {
				plot(b.x + b.width / 2, y, 0x3b82f6);
				y += step * 3;
			}
			if (r.ink != null)
				frame(r.ink, 0xef4444);
		}
		sys.io.File.saveBytes(haxe.io.Path.join([dir, "probe.png"]), Png.encode(pw, ph, px));
		var text = report(results);
		sys.io.File.saveContent(haxe.io.Path.join([dir, "report.txt"]), text);
		Snapshot.event('align $name ${sys.FileSystem.absolutePath(dir)} boxes=${results.length}');
		return results;
	}

	public static function measure(width:Int, height:Int, build:Void->Element, scale = 2.0, page = 0xffffff):Array<AlignResult>
		return draw(width, height, build, scale, page).results;

	/** One line a box: its label, how far off its middle the ink is across and down, and the ink's gaps to each side. **/
	public static function report(results:Array<AlignResult>):String {
		inline function f(v:Float)
			return Std.string(Math.round(v * 10) / 10);
		var lines = [];
		for (r in results) {
			if (r.ink == null) {
				lines.push('${r.label}: nothing drawn');
				continue;
			}
			var b = r.box, i = r.ink;
			var left = i.x - b.x, right = b.x + b.width - (i.x + i.width), top = i.y - b.y, bottom = b.y + b.height - (i.y + i.height);
			lines.push('${r.label}: dx ${f(r.dx)} dy ${f(r.dy)}  (left ${f(left)} right ${f(right)} top ${f(top)} bottom ${f(bottom)})');
		}
		return lines.join("\n");
	}

	static function draw(width:Int, height:Int, build:Void->Element, scale:Float,
			page:Int):{results:Array<AlignResult>, pixels:haxe.io.Bytes, pw:Int, ph:Int} {
		var offscreen = Snapshot.renderer();
		offscreen.clear = page;
		offscreen.clearAlpha = 1;
		var tree = new LayoutTree();
		var root:Element = Owner.root(tree, _ -> build());
		ashui.css.Css.setViewport(width, height);
		ashui.css.Css.update();
		tree.flush();
		tree.computeLayout(root.node, width, height);
		tree.flush();
		var pw = Math.round(width * scale), ph = Math.round(height * scale);
		var saved = offscreen.scale;
		offscreen.scale = scale;
		var texture = offscreen.createTexture(pw, ph);
		offscreen.renderTree(tree, root.node, texture.createView(new GpuTextureViewDescriptor()), width, height);
		var pixels = offscreen.readRgba8(texture, pw, ph);
		texture.destroy();
		offscreen.scale = saved;

		inline function at(x:Int, y:Int):Int {
			var o = (y * pw + x) * 4;
			return (pixels.get(o) << 16) | (pixels.get(o + 1) << 8) | pixels.get(o + 2);
		}
		inline function far(a:Int, b:Int):Bool
			return Math.abs(((a >> 16) & 0xff) - ((b >> 16) & 0xff)) + Math.abs(((a >> 8) & 0xff) - ((b >> 8) & 0xff))
				+ Math.abs((a & 0xff) - (b & 0xff)) > threshold;
		var results:Array<AlignResult> = [];
		for (id in tree.order()) {
			var identity = ashui.css.Identity.of(tree, id);
			if (identity == null || identity.id == null || identity.id == "")
				continue;
			var b = tree.getBounds(new Node(id));
			if (b == null || b.width <= 0 || b.height <= 0)
				continue;
			var x0 = Math.ceil((b.x + inset) * scale), x1 = Math.floor((b.x + b.width - inset) * scale);
			var y0 = Math.ceil((b.y + inset) * scale), y1 = Math.floor((b.y + b.height - inset) * scale);
			x0 = Std.int(Math.max(0, x0));
			y0 = Std.int(Math.max(0, y0));
			x1 = Std.int(Math.min(pw - 1, x1));
			y1 = Std.int(Math.min(ph - 1, y1));
			if (x1 <= x0 || y1 <= y0)
				continue;
			var bg = at(x0, Std.int((y0 + y1) / 2));
			// The corners' curve lets the page through; the ink is looked for clear of it.
			var corner = Std.int(Math.min(6 * scale, Math.min((x1 - x0) / 4, (y1 - y0) / 4)));
			var minX = pw, minY = ph, maxX = -1, maxY = -1;
			for (y in y0...y1 + 1)
				for (x in x0...x1 + 1) {
					var inCorner = (x - x0 < corner || x1 - x < corner) && (y - y0 < corner || y1 - y < corner);
					if (inCorner)
						continue;
					var c = at(x, y);
					if (far(c, bg) && far(c, page)) {
						if (x < minX)
							minX = x;
						if (x > maxX)
							maxX = x;
						if (y < minY)
							minY = y;
						if (y > maxY)
							maxY = y;
					}
				}
			var box = {x: (b.x : Float), y: (b.y : Float), width: (b.width : Float), height: (b.height : Float)};
			if (maxX < 0) {
				results.push({label: identity.id, box: box, ink: null, dx: 0, dy: 0});
				continue;
			}
			var ink = {x: minX / scale, y: minY / scale, width: (maxX + 1 - minX) / scale, height: (maxY + 1 - minY) / scale};
			results.push({
				label: identity.id,
				box: box,
				ink: ink,
				dx: (ink.x + ink.width / 2) - (b.x + b.width / 2),
				dy: (ink.y + ink.height / 2) - (b.y + b.height / 2)
			});
		}
		return {results: results, pixels: pixels, pw: pw, ph: ph};
	}
}
