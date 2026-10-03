import ashui.core.render.Offscreen;
import ashui.layout.LayoutTree;
import ashui.layout.Prop;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.Shadow;
import ashui.types.Style;
import ashui.ui.Div;
import gpu.GpuExtent3D;
import gpu.GpuInstance;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureViewDescriptor;
import gpu.Power;
import gpu.TextureFormat;
import gpu.TextureUsage;

/**
	Renders a scene with `Offscreen` and checks pixels read back from it,
	twice: into a texture this program makes on its own device, as a host
	would, and through `renderToRgba8` on a BGRA renderer. On a white
	64×64 root, absolutely placed:
	- a red 20×20 square at (8,8) casting a black shadow 6px down, blur 2;
	- a blue circle of radius 12 at (32,8) with a 2px green border;
	- a 24×16 bar at (8,40), a gradient from red on the left to blue;
	- a 16×16 box at (40,40) that clips a 32×32 green child to itself.

	Then a 32×32 box at (16,16) turned 45 degrees, clipping a green child
	that covers its bounding box: the child shows inside the turned box and
	not in its bounding box's corners.

	Then a white box with a red top border alone, a green box with a blue
	2-pixel outline 2 pixels out, and a white box with a 4-pixel border,
	green but for its red top and blue left.

	Then SVG, on white: a 24×24 mask square in currentColor, drawn red by
	the element's colour, and a colour square that is blue whatever the
	element's colour, each with a transparent margin.

	Then inherited colour: mask icons with no colour of their own, inside a
	parent coloured red; inside a blue box inside that red one; inside a
	parent whose colour signal turns green after the first frame; one
	added to the red parent after the first frame; and a two-colour icon in
	a red parent, whose currentColor half turns red while its fixed blue
	half stays blue.

	Then SVG beyond the typed model, drawn as written: a red-to-blue linear
	gradient, a `<use>` of a rect styled green by a `<style>` sheet, linked
	by `href` and by `xlink:href`, an embedded magenta PNG `<image>`, and
	an "M" in `<text>` coloured red by the element.

	Then text, on white: black "MM" at 24px, which must ink pixels, and "MM"
	at 10px under a 4x zoom, whose stem edges must stay about a pixel wide,
	as a glyph rasterized at its on-screen size has and a magnified one,
	about four pixels, does not.
**/
class Pixels {
	static inline var SIZE = 64;
	static inline var ROW = SIZE * 4;

	static function main() {
		var tree = new LayoutTree();
		function at(x:Int, y:Int, w:Int, h:Int, ?bg:Brush, ?children:Array<ashui.layout.Element>) {
			return new Div({
				position: Position.Absolute, left: x, top: y, width: w, height: h, flexShrink: 0, bg: bg
			}, children, tree);
		}
		var square = at(8, 8, 20, 20, Brush.solid(0xff0000));
		square.node.set(Prop.Shadow, new Shadow(0, 6, 2, 0x000000));
		var circle = new Div({
			position: Position.Absolute, left: 32, top: 8, width: 24, height: 24, cornerRadius: CornerRadius.all(12),
			bg: Brush.solid(0x0000ff), borderColor: new Color(0x00ff00), borderWidth: 2
		}, tree);
		var bar = at(8, 40, 24, 16, Brush.linearGradient(0, 0, 24, 0, 0xff0000, 1, 0x0000ff, 1));
		var clipper = new Div({
			position: Position.Absolute, left: 40, top: 40, width: 16, height: 16, overflow: Overflow.Clip
		}, [at(0, 0, 32, 32, Brush.solid(0x00ff00))], tree);
		var root = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [square, circle, bar, clipper], tree);
		// As a host would: its own device and texture, the UI drawn into them.
		var device = new GpuInstance().requestAdapter(Power.HighPerformance).await().requestDevice().await();
		var size = new GpuExtent3D(SIZE);
		size.height(SIZE);
		var target = device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba8unorm, TextureUsage.RENDER_ATTACHMENT | TextureUsage.COPY_SRC));
		var offscreen = new Offscreen(device, TextureFormat.Rgba8unorm);
		offscreen.render(root, target.createView(new GpuTextureViewDescriptor()), SIZE, SIZE);
		var shared = offscreen.readRgba8(target, SIZE, SIZE);
		target.destroy();
		// Read back from a BGRA target, which must come out RGBA.
		var bgra = new Offscreen(device, TextureFormat.Bgra8unorm).renderToRgba8(root, SIZE, SIZE);

		var failures = 0;
		var pixels = shared;
		var label = "";
		function probe(name:String, x:Int, y:Int, ok:(r:Int, g:Int, b:Int) -> Bool) {
			var at = y * ROW + x * 4;
			var rgba = [for (c in 0...4) pixels.get(at + c)];
			var passed = ok(rgba[0], rgba[1], rgba[2]) && rgba[3] == 255;
			if (!passed)
				failures++;
			Sys.println('${passed ? "ok  " : "FAIL"} $label$name ($x,$y): $rgba');
		}
		function near(want:Int)
			return (r, g, b) -> Math.abs(r - (want >> 16 & 0xff)) <= 2 && Math.abs(g - (want >> 8 & 0xff)) <= 2 && Math.abs(b - (want & 0xff)) <= 2;
		probe("root fill", 2, 2, near(0xffffff));
		probe("square fill", 18, 18, near(0xff0000));
		probe("shadow below the square", 18, 31, (r, g, b) -> r < 40 && g < 40 && b < 40);
		probe("no shadow above the square", 18, 4, near(0xffffff));
		probe("circle fill", 44, 20, near(0x0000ff));
		probe("outside the circle's corner", 33, 9, near(0xffffff));
		probe("circle border", 44, 9, near(0x00ff00));
		probe("gradient start", 9, 48, (r, g, b) -> r > 220 && b < 35 && g < 5);
		probe("gradient middle", 20, 48, (r, g, b) -> r > 100 && r < 155 && b > 100 && b < 155);
		probe("gradient end", 31, 48, (r, g, b) -> b > 220 && r < 35 && g < 5);
		probe("clipped child inside the clip", 48, 48, near(0x00ff00));
		probe("clipped child outside the clip", 60, 48, near(0xffffff));
		pixels = bgra;
		label = "bgra: ";
		probe("root fill", 2, 2, near(0xffffff));
		probe("square fill", 18, 18, near(0xff0000));
		probe("shadow below the square", 18, 31, (r, g, b) -> r < 40 && g < 40 && b < 40);
		probe("no shadow above the square", 18, 4, near(0xffffff));
		probe("circle fill", 44, 20, near(0x0000ff));
		probe("outside the circle's corner", 33, 9, near(0xffffff));
		probe("circle border", 44, 9, near(0x00ff00));
		probe("gradient start", 9, 48, (r, g, b) -> r > 220 && b < 35 && g < 5);
		probe("gradient middle", 20, 48, (r, g, b) -> r > 100 && r < 155 && b > 100 && b < 155);
		probe("gradient end", 31, 48, (r, g, b) -> b > 220 && r < 35 && g < 5);
		probe("clipped child inside the clip", 48, 48, near(0x00ff00));
		probe("clipped child outside the clip", 60, 48, near(0xffffff));

		var clipTree = new LayoutTree();
		var turned = new Div({
			position: Position.Absolute, left: 16, top: 16, width: 32, height: 32, overflow: Overflow.Clip
		}, [new Div({position: Position.Absolute, left: -16, top: -16, width: 64, height: 64, bg: Brush.solid(0x00ff00)}, clipTree)], clipTree);
		turned.node.set(Prop.Transform, ashui.types.Transform.rotation(45));
		var clipRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [turned], clipTree);
		pixels = offscreen.renderToRgba8(clipRoot, SIZE, SIZE);
		label = "turned clip: ";
		probe("child inside the turned box", 32, 32, near(0x00ff00));
		probe("child inside, near the turned box's tip", 32, 13, near(0x00ff00));
		probe("nothing in the bounding box's corner", 14, 14, near(0xffffff));

		var edgeTree = new LayoutTree();
		var topOnly = new Div({position: Position.Absolute, left: 4, top: 4, width: 24, height: 24, bg: Brush.solid(0xffffff)}, edgeTree);
		topOnly.node.set(Prop.BorderColor, new Color(0xff0000));
		topOnly.node.set(Prop.BorderTopWidth, (4 : Single));
		var outlined = new Div({position: Position.Absolute, left: 40, top: 20, width: 16, height: 16, bg: Brush.solid(0x00ff00)}, edgeTree);
		outlined.node.set(Prop.OutlineColor, new Color(0x0000ff));
		outlined.node.set(Prop.OutlineWidth, (2 : Single));
		outlined.node.set(Prop.OutlineOffset, (2 : Single));
		var fourColours = new Div({position: Position.Absolute, left: 4, top: 36, width: 24, height: 24, bg: Brush.solid(0xffffff)}, edgeTree);
		fourColours.node.set(Prop.BorderWidth, (4 : Single));
		fourColours.node.set(Prop.BorderColor, new Color(0x00ff00));
		fourColours.node.set(Prop.BorderTopColor, new Color(0xff0000));
		fourColours.node.set(Prop.BorderLeftColor, new Color(0x0000ff));
		var edgeRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [topOnly, outlined, fourColours], edgeTree);
		pixels = offscreen.renderToRgba8(edgeRoot, SIZE, SIZE);
		label = "borders and outlines: ";
		probe("a top border alone is drawn on top", 16, 5, near(0xff0000));
		probe("and not on the left", 5, 16, near(0xffffff));
		probe("nor at the bottom", 16, 26, near(0xffffff));
		probe("an outline outside its box, past its offset", 37, 28, near(0x0000ff));
		probe("the offset's gap is left clear", 39, 28, near(0xffffff));
		probe("the box itself is untouched", 48, 28, near(0x00ff00));
		probe("a side's own colour, top", 16, 37, near(0xff0000));
		probe("a side's own colour, left", 5, 48, near(0x0000ff));
		probe("a side in the border's colour, right", 26, 48, near(0x00ff00));
		probe("and bottom", 16, 58, near(0x00ff00));
		probe("the sides meet on the corner's diagonal", 5, 38, near(0x0000ff));

		var svgTree = new LayoutTree();
		var maskDoc = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" fill="currentColor"/></svg>');
		var colourDoc = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><rect x="4" y="4" width="16" height="16" fill="#0000ff"/></svg>');
		var maskIcon = new ashui.ui.Svg(maskDoc, {width: 24, height: 24, color: new Color(0xff0000)}, svgTree);
		var colourIcon = new ashui.ui.Svg(colourDoc, {width: 24, height: 24, color: new Color(0xff0000)}, svgTree);
		var svgRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), gap: 8, padding: 4, flexDirection: Row},
			[maskIcon, colourIcon], svgTree);
		pixels = offscreen.renderToRgba8(svgRoot, SIZE, SIZE);
		label = "svg: ";
		probe("mask drawn in the element's colour", 16, 16, near(0xff0000));
		probe("mask's transparent margin", 6, 6, near(0xffffff));
		probe("colour image as drawn", 48, 16, near(0x0000ff));
		probe("colour image's transparent margin", 38, 6, near(0xffffff));

		var inheritTree = new LayoutTree();
		function icon()
			return new ashui.ui.Svg(maskDoc, {width: 24, height: 24}, inheritTree);
		function box(left:Int, children:Array<ashui.layout.Element>)
			return new Div({position: Position.Absolute, left: left, top: 0, width: 24, height: 24}, children, inheritTree);
		var red = box(0, [icon()]);
		red.node.set(Prop.Color, new Color(0xff0000));
		var inner = box(0, [icon()]);
		inner.node.set(Prop.Color, new Color(0x0000ff));
		var outer = box(32, [inner]);
		outer.node.set(Prop.Color, new Color(0xff0000));
		var tone = ashui.reactive.Signal.make(new Color(0xff0000));
		var bound = box(64, [icon()]);
		bound.node.set(Prop.Color, tone);
		var later = box(96, []);
		later.node.set(Prop.Color, new Color(0xff0000));
		var twoTone = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><rect width="12" height="24" fill="currentColor"/><rect x="12" width="12" height="24" fill="#0000ff"/></svg>');
		var mixed = box(128, [new ashui.ui.Svg(twoTone, {width: 24, height: 24}, inheritTree)]);
		mixed.node.set(Prop.Color, new Color(0xff0000));
		var inheritRoot = new Div({width: 160, height: 24, bg: Brush.solid(0xffffff)}, [red, outer, bound, later, mixed], inheritTree);
		offscreen.renderToRgba8(inheritRoot, 160, 24);
		tone.set(new Color(0x00ff00));
		later.appendChild(icon());
		pixels = offscreen.renderToRgba8(inheritRoot, 160, 24);
		label = "inherited colour: ";
		function at(x:Int, y:Int, want:Int, name:String) {
			var i = (y * 160 + x) * 4;
			var ok = Math.abs(pixels.get(i) - (want >> 16 & 0xff)) <= 2 && Math.abs(pixels.get(i + 1) - (want >> 8 & 0xff)) <= 2
				&& Math.abs(pixels.get(i + 2) - (want & 0xff)) <= 2;
			if (!ok)
				failures++;
			Sys.println('${ok ? "ok  " : "FAIL"} $label$name ($x,$y): [${pixels.get(i)},${pixels.get(i + 1)},${pixels.get(i + 2)}]');
		}
		at(12, 12, 0xff0000, "from the parent");
		at(44, 12, 0x0000ff, "from the nearest ancestor that sets one");
		at(76, 12, 0x00ff00, "follows the parent's colour after it changes");
		at(108, 12, 0xff0000, "reaches a child added after the first frame");
		at(134, 12, 0xff0000, "is a two-colour icon's currentColor");
		at(146, 12, 0x0000ff, "leaves a two-colour icon's fixed colour as written");

		var fullTree = new LayoutTree();
		var gradient = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><defs><linearGradient id="g"><stop offset="0" stop-color="#ff0000"/><stop offset="1" stop-color="#0000ff"/></linearGradient></defs><rect width="24" height="24" fill="url(#g)"/></svg>');
		var reused = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><style>.a { fill: #00ff00 }</style><defs><rect id="r" class="a" width="12" height="24"/></defs><use href="#r"/><use xlink:href="#r" x="12" fill="red"/></svg>');
		function full(doc:ashui.svg.SvgDocument)
			return new ashui.ui.Svg(doc, {width: 24, height: 24, color: new Color(0xff0000)}, fullTree);
		var embedded = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><image width="24" height="24" style="image-rendering: pixelated" href="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z/AfAAQAAf8iCjrwAAAAAElFTkSuQmCC"/></svg>');
		var written = ashui.svg.SvgDocument.parse('<svg viewBox="0 0 24 24"><text x="0" y="22" font-size="28" font-weight="bold" fill="currentColor">M</text></svg>');
		var fullRoot = new Div({width: 160, height: 24, bg: Brush.solid(0xffffff), gap: 8, flexDirection: Row},
			[full(gradient), full(reused), full(embedded), full(written)], fullTree);
		pixels = offscreen.renderToRgba8(fullRoot, 160, 24);
		label = "full svg: ";
		function hue(x:Int, y:Int, name:String, ok:(r:Int, g:Int, b:Int) -> Bool) {
			var i = (y * 160 + x) * 4;
			var passed = ok(pixels.get(i), pixels.get(i + 1), pixels.get(i + 2));
			if (!passed)
				failures++;
			Sys.println('${passed ? "ok  " : "FAIL"} $label$name ($x,$y): [${pixels.get(i)},${pixels.get(i + 1)},${pixels.get(i + 2)}]');
		}
		hue(1, 12, "a gradient starts at its first stop", (r, g, b) -> r > 200 && b < 50);
		hue(22, 12, "and ends at its last", (r, g, b) -> b > 200 && r < 50);
		hue(36, 12, "<use> draws what it links to, styled by a <style> sheet", (r, g, b) -> g > 200 && r < 50);
		hue(50, 12, "xlink:href links too", (r, g, b) -> g > 200 && r < 50);
		hue(76, 12, "an embedded image is drawn", (r, g, b) -> r > 200 && g < 50 && b > 200);
		var textInk = 0;
		for (y in 0...24)
			for (x in 96...120) {
				var i = (y * 160 + x) * 4;
				if (pixels.get(i) > 200 && pixels.get(i + 1) < 60 && pixels.get(i + 2) < 60)
					textInk++;
			}
		var textOk = textInk > 40;
		if (!textOk)
			failures++;
		Sys.println('${textOk ? "ok  " : "FAIL"} ${label}<text> is drawn in currentColor ($textInk red pixels)');

		var textTree = new LayoutTree();
		var label24 = new ashui.ui.Text("MM", {fontSize: 24, color: new Color(0x000000), wrap: false}, textTree);
		var plain = new Div({position: Position.Absolute, left: 8, top: 8}, [label24], textTree);
		var label10 = new ashui.ui.Text("MM", {fontSize: 10, color: new Color(0x000000), wrap: false}, textTree);
		var zoomed = new Div({position: Position.Absolute, left: 144, top: 56, width: 32, height: 16}, [label10], textTree);
		zoomed.node.set(Prop.Transform, new ashui.types.Transform(0, 0, 0, 4, 4));
		var textRoot = new Div({width: 4 * SIZE, height: 2 * SIZE, bg: Brush.solid(0xffffff)}, [plain, zoomed], textTree);
		var w = 4 * SIZE;
		var h = 2 * SIZE;
		var text = offscreen.renderToRgba8(textRoot, w, h);
		function ink(x0:Int, y0:Int, x1:Int, y1:Int) {
			var full = 0;
			var partial = 0;
			for (y in y0...y1)
				for (x in x0...x1) {
					var r = text.get((y * w + x) * 4);
					if (r < 40)
						full++;
					else if (r < 215)
						partial++;
				}
			return {full: full, partial: partial};
		}
		var small = ink(0, 0, 64, 48);
		label = "text: ";
		var inked = small.full > 40;
		if (!inked)
			failures++;
		Sys.println('${inked ? "ok  " : "FAIL"} text: 24px glyphs ink ${small.full} pixels');
		// Across each row of the zoomed text, how many pixels the first edge,
		// the left side of the first M's stem, takes from paper to ink.
		var edges = [];
		for (y in 0...h) {
			var x = 80;
			while (x < w && text.get((y * w + x) * 4) >= 215)
				x++;
			var start = x;
			while (x < w && text.get((y * w + x) * 4) >= 40)
				x++;
			if (x < w)
				edges.push(x - start);
		}
		edges.sort((a, b) -> a - b);
		var median = edges.length > 0 ? edges[edges.length >> 1] : -1;
		var sharp = edges.length > 20 && median >= 0 && median <= 2;
		if (!sharp)
			failures++;
		Sys.println('${sharp ? "ok  " : "FAIL"} text: zoomed glyph edges are $median pixels wide over ${edges.length} rows');
		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
