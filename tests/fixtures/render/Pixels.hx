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

	Then a box clipping a red child, fading it out over 20 pixels in from
	its top edge.

	Then clip paths: a red child clipped to its parent's circle, a red box
	clipped to a wide, flat ellipse and turned 90° so the ellipse stands
	tall, a blue box inset by 10 pixels with rounded corners, and a green
	triangle from percentages; then a red square path with a square hole.

	Then group opacity: a blue box at half opacity holding a red one, which
	shows as half-strength red with no blue through it, as a group
	composites; and a red box at half opacity holding a green one.

	Then colour filters: red in grayscale, blue inverted, red at half
	brightness, and white in sepia.

	Then a red square blurred by 4: red in its middle, a pink halo past its
	edges, white away from it.

	Then a box with CSS's `backdrop-filter: blur(4px)` over a black stripe:
	the stripe grey and spread under the box, sharp and black outside it.

	Then drop shadows: a red circle's sharp black one offset by 6, cast by
	the circle rather than its box, and a red square's blurred one.

	Then inset shadows on grey: a white box with a sharp black one 4 wide,
	and a narrow white box with one offset down and right and blurred.

	Then bitmaps, from a PNG of a red pixel and a blue one: stretched,
	letterboxed in a square, cropped to cover a tall box, as the
	background of a round box, and tiled over a square, red and blue
	columns one layout unit wide.

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
		var target = device.texture(new GpuTextureDescriptor(size, TextureFormat.Rgba8unorm, ashui.core.render.GpuFlags.TEXTURE_RENDER_ATTACHMENT | ashui.core.render.GpuFlags.TEXTURE_COPY_SRC));
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

		var fadeTree = new LayoutTree();
		var fadeChild = new Div({width: 40, height: 40, bg: Brush.solid(0xff0000)}, fadeTree);
		var fading = new Div({position: Position.Absolute, left: 8, top: 8, width: 40, height: 40, overflow: Overflow.Clip}, [fadeChild], fadeTree);
		fading.node.set(Prop.FadeTop, (20 : Single));
		var fadeRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [fading], fadeTree);
		pixels = offscreen.renderToRgba8(fadeRoot, SIZE, SIZE);
		label = "overflow fade: ";
		probe("almost gone at the clip's top edge", 28, 9, (r, g, b) -> r > 240 && g > 220);
		probe("half way through the fade", 28, 18, (r, g, b) -> r > 240 && g > 110 && g < 150);
		probe("whole past it", 28, 40, near(0xff0000));

		// A mask-image: a red box, opaque at its left, transparent at its right, over white; its child is masked with it.
		var maskTree = new LayoutTree();
		var maskBrush = Brush.linear(0, 0, 1, 0, true);
		maskBrush.stop(0, 0x000000, 1).stop(1, 0x000000, 0);
		var maskChild = new Div({width: 40, height: 10, bg: Brush.solid(0x0000ff)}, maskTree);
		var masked = new Div({position: Position.Absolute, left: 8, top: 8, width: 48, height: 40, bg: Brush.solid(0xff0000), maskImage: maskBrush},
			[maskChild], maskTree);
		var maskRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [masked], maskTree);
		pixels = offscreen.renderToRgba8(maskRoot, SIZE, SIZE);
		label = "mask-image: ";
		probe("whole at the start", 9, 30, (r, g, b) -> r > 240 && g < 20);
		probe("about half way across", 32, 30, (r, g, b) -> r > 240 && g > 100 && g < 160);
		probe("almost gone at the end", 55, 30, (r, g, b) -> r > 240 && g > 230);
		probe("and what it holds masked with it", 46, 12, (r, g, b) -> b > 240 && r > 150 && r < 240);

		// Layout animation: a box layout moves 30 to the right is drawn where it was when the move starts, and at its place once it has run.
		var flipTree = new LayoutTree();
		var shift = ashui.reactive.Signal.make((4 : Single));
		var flipBox = new Div({position: Position.Absolute, left: shift, top: 20, width: 20, height: 20, bg: Brush.solid(0xff0000), animateLayout: true}, flipTree);
		var flipRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [flipBox], flipTree);
		pixels = offscreen.renderToRgba8(flipRoot, SIZE, SIZE);
		shift.set(34);
		pixels = offscreen.renderToRgba8(flipRoot, SIZE, SIZE);
		label = "layout animation: ";
		probe("drawn where it was as the move starts", 10, 30, near(0xff0000));
		probe("not yet at its place", 50, 30, near(0xffffff));
		pixels = offscreen.renderAnimatedToRgba8(flipRoot, SIZE, SIZE, 1.0);
		probe("at its place once the move has run", 50, 30, near(0xff0000));
		probe("and gone from where it was", 10, 30, near(0xffffff));

		// A notch: concave top corners of 10, so its body starts 10 down, flaring out to the box's edge there.
		var notchTree = new LayoutTree();
		var notched = new Div({position: Position.Absolute, left: 8, top: 8, width: 48, height: 40, bg: Brush.solid(0xff0000),
			notch: ashui.types.Notch.concaveTop(10)}, notchTree);
		var notchRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [notched], notchTree);
		pixels = offscreen.renderToRgba8(notchRoot, SIZE, SIZE);
		label = "notch: ";
		probe("nothing above the body, where the corners' radius insets it", 30, 12, near(0xffffff));
		probe("the flare, out at the box's edge just below the body's top", 14, 19, near(0xff0000));
		probe("the concave bite under the flare", 9, 27, near(0xffffff));
		probe("the body", 30, 34, near(0xff0000));

		var shapeTree = new LayoutTree();
		var inCircle = new Div({width: 24, height: 24, bg: Brush.solid(0xff0000)}, shapeTree);
		var circled = new Div({position: Position.Absolute, left: 4, top: 4, width: 24, height: 24}, [inCircle], shapeTree);
		circled.node.set(Prop.ClipPath, ashui.types.ClipPath.circle());
		var band = new Div({position: Position.Absolute, left: 36, top: 4, width: 24, height: 24, bg: Brush.solid(0xff0000)}, shapeTree);
		band.node.set(Prop.ClipPath, ashui.types.ClipPath.ellipse(Px(12), Px(4)));
		band.node.set(Prop.Transform, ashui.types.Transform.rotation(90));
		var inset = new Div({position: Position.Absolute, left: 4, top: 36, width: 24, height: 24, bg: Brush.solid(0x0000ff)}, shapeTree);
		inset.node.set(Prop.ClipPath, ashui.types.ClipPath.inset(Px(10), Px(10), Px(10), Px(10), 2));
		var triangle = new Div({position: Position.Absolute, left: 36, top: 36, width: 24, height: 24, bg: Brush.solid(0x00ff00)}, shapeTree);
		triangle.node.set(Prop.ClipPath, ashui.types.ClipPath.polygon([
			{x: Percent(50), y: Px(0)},
			{x: Percent(100), y: Percent(100)},
			{x: Px(0), y: Percent(100)}
		]));
		var shapeRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [circled, band, inset, triangle], shapeTree);
		pixels = offscreen.renderToRgba8(shapeRoot, SIZE, SIZE);
		label = "clip-path: ";
		probe("a circle clips a child's corner away", 6, 6, near(0xffffff));
		probe("and keeps its middle", 16, 16, near(0xff0000));
		probe("and its top edge's middle", 16, 5, near(0xff0000));
		probe("an ellipse turns with its element: tall", 48, 7, near(0xff0000));
		probe("and narrow", 40, 16, near(0xffffff));
		probe("an inset keeps its middle", 16, 48, near(0x0000ff));
		probe("and clears its margin", 8, 48, near(0xffffff));
		probe("a polygon keeps its triangle's middle", 48, 52, near(0x00ff00));
		probe("and clears what is beside its apex", 39, 39, near(0xffffff));

		var pathTree = new LayoutTree();
		var framed = new Div({position: Position.Absolute, left: 8, top: 8, width: 24, height: 24, bg: Brush.solid(0xff0000)}, pathTree);
		framed.node.set(Prop.ClipPath, ashui.types.ClipPath.path("M0 0H24V24H0Z M8 8V16H16V8Z"));
		var pathRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [framed], pathTree);
		pixels = offscreen.renderToRgba8(pathRoot, SIZE, SIZE);
		probe("a path of two rings keeps the frame", 11, 20, near(0xff0000));
		probe("and leaves the hole, wound the other way, clear", 20, 20, near(0xffffff));

		var groupTree = new LayoutTree();
		var groupRed = new Div({position: Position.Absolute, left: 8, top: 8, width: 16, height: 16, bg: Brush.solid(0xff0000)}, groupTree);
		var group = new Div({position: Position.Absolute, left: 8, top: 8, width: 32, height: 32, bg: Brush.solid(0x0000ff)}, [groupRed], groupTree);
		group.node.set(Prop.Opacity, (0.5 : Single));
		var nested = new Div({position: Position.Absolute, left: 4, top: 4, width: 8, height: 8, bg: Brush.solid(0x00ff00)}, groupTree);
		var inner = new Div({position: Position.Absolute, left: 0, top: 0, width: 16, height: 16, bg: Brush.solid(0xff0000)}, [nested], groupTree);
		inner.node.set(Prop.Opacity, (0.5 : Single));
		var outer = new Div({position: Position.Absolute, left: 44, top: 8, width: 16, height: 16}, [inner], groupTree);
		var groupRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [group, outer], groupTree);
		pixels = offscreen.renderToRgba8(groupRoot, SIZE, SIZE);
		label = "group opacity: ";
		probe("the group's own fill at half", 12, 36, (r, g, b) -> Math.abs(r - 128) < 4 && Math.abs(g - 128) < 4 && b > 250);
		probe("a child over it shows none of the fill through", 24, 24, (r, g, b) -> r > 250 && Math.abs(g - 128) < 4 && Math.abs(b - 128) < 4);
		probe("outside the group, untouched", 60, 60, near(0xffffff));
		probe("a child of a faded group over its fill", 52, 16, (r, g, b) -> Math.abs(r - 128) < 4 && g > 250 && Math.abs(b - 128) < 4);

		var filterTree = new LayoutTree();
		function filtered(left:Int, top:Int, colour:Int, prop:ashui.layout.Prop<Single>, amount:Single) {
			var d = new Div({position: Position.Absolute, left: left, top: top, width: 16, height: 16, bg: Brush.solid(colour)}, filterTree);
			d.node.set(prop, amount);
			return d;
		}
		var filterRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [
			filtered(4, 4, 0xff0000, Prop.FilterGrayscale, 1),
			filtered(24, 4, 0x0000ff, Prop.FilterInvert, 1),
			filtered(44, 4, 0xff0000, Prop.FilterBrightness, 0.5),
			filtered(4, 24, 0xffffff, Prop.FilterSepia, 1)
		], filterTree);
		pixels = offscreen.renderToRgba8(filterRoot, SIZE, SIZE);
		label = "filters: ";
		probe("grayscale takes red to its luminance", 12, 12, (r, g, b) -> Math.abs(r - 54) < 3 && Math.abs(g - 54) < 3 && Math.abs(b - 54) < 3);
		probe("invert takes blue to yellow", 32, 12, near(0xffff00));
		probe("brightness-50 halves red", 52, 12, (r, g, b) -> Math.abs(r - 128) < 3 && g < 3 && b < 3);
		probe("sepia tints white", 12, 32, (r, g, b) -> r == 255 && Math.abs(g - 255) < 3 && Math.abs(b - 239) < 3);
		probe("next to them, untouched", 60, 60, near(0xffffff));

		var blurTree = new LayoutTree();
		var blurred = new Div({position: Position.Absolute, left: 24, top: 24, width: 16, height: 16, bg: Brush.solid(0xff0000)}, blurTree);
		blurred.node.set(Prop.FilterBlur, (4 : Single));
		var blurRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [blurred], blurTree);
		pixels = offscreen.renderToRgba8(blurRoot, SIZE, SIZE);
		label = "blur: ";
		probe("the middle stays red", 32, 32, (r, g, b) -> r > 250 && g < 90 && b < 90);
		probe("spreads past its edge", 21, 32, (r, g, b) -> r > 250 && g > 110 && g < 245);
		probe("fades out away from it", 8, 32, (r, g, b) -> r > 250 && g > 250 && b > 250);
		probe("its corner is softer than its edge's middle", 25, 25, (r, g, b) -> g > 100);

		// CSS backdrop-filter: a black stripe under a frosted box blurs; outside it, the stripe stays sharp.
		var frostSheet = ashui.css.Css.load('.frost { backdrop-filter: blur(4px); background: rgba(255, 255, 255, 0); }');
		var frostTree = new LayoutTree();
		var stripe = new Div({position: Position.Absolute, left: 30, top: 0, width: 4, height: SIZE, bg: Brush.solid(0x000000)}, frostTree);
		var frost = new Div({classes: ["frost"], position: Position.Absolute, left: 12, top: 24, width: 40, height: 32}, frostTree);
		var frostRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [stripe, frost], frostTree);
		pixels = offscreen.renderToRgba8(frostRoot, SIZE, SIZE);
		label = "backdrop-filter: ";
		probe("the stripe under the box is blurred, no longer black", 32, 40, (r, g, b) -> r > 40 && r < 220 && Math.abs(r - g) < 3);
		probe("and spread past its edge", 36, 40, (r, g, b) -> r < 250);
		probe("outside the box it stays sharp", 32, 10, near(0x000000));
		ashui.css.Css.remove(frostSheet);

		var dropTree = new LayoutTree();
		var disc = new Div({position: Position.Absolute, left: 8, top: 8, width: 16, height: 16, bg: Brush.solid(0xff0000),
			cornerRadius: CornerRadius.all(8)}, dropTree);
		disc.node.set(Prop.DropShadow, new ashui.types.Shadow(6, 6, 0, 0x000000, 1));
		var soft = new Div({position: Position.Absolute, left: 40, top: 8, width: 16, height: 16, bg: Brush.solid(0xff0000)}, dropTree);
		soft.node.set(Prop.DropShadow, new ashui.types.Shadow(0, 0, 8, 0x000000, 1));
		var dropRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [disc, soft], dropTree);
		pixels = offscreen.renderToRgba8(dropRoot, SIZE, SIZE);
		label = "drop shadow: ";
		probe("cast by the circle's shape, past it", 25, 25, near(0x000000));
		probe("not by its box: the box's empty corner stays clear", 9, 9, near(0xffffff));
		probe("under the content", 16, 16, near(0xff0000));
		probe("a blurred one shades just past the edge", 37, 16, (r, g, b) -> r < 230 && r > 60 && Math.abs(r - g) < 3);
		probe("and the content stays on top", 48, 16, near(0xff0000));

		var insetTree = new LayoutTree();
		var rimmed = new Div({position: Position.Absolute, left: 8, top: 8, width: 32, height: 32, bg: Brush.solid(0xffffff)}, insetTree);
		rimmed.node.set(Prop.Shadow, new ashui.types.Shadow(0, 0, 0, 0x000000, 1, 4, true));
		var sunk = new Div({position: Position.Absolute, left: 44, top: 8, width: 16, height: 32, bg: Brush.solid(0xffffff)}, insetTree);
		sunk.node.set(Prop.Shadow, new ashui.types.Shadow(4, 4, 4, 0x000000, 1, 0, true));
		var insetRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xc0c0c0)}, [rimmed, sunk], insetTree);
		pixels = offscreen.renderToRgba8(insetRoot, SIZE, SIZE);
		label = "inset shadow: ";
		probe("a band inside the box's edge", 10, 24, near(0x000000));
		probe("its middle untouched", 24, 24, near(0xffffff));
		probe("nothing outside the box", 6, 24, near(0xc0c0c0));
		probe("an offset one shades the top-left inner edge", 45, 9, (r, g, b) -> r < 80);
		probe("and fades toward the far side", 58, 38, (r, g, b) -> r > 200);

		var bitmapTree = new LayoutTree();
		// Two pixels: red, then blue.
		var pair = ashui.types.Bitmap.fromBytes(haxe.crypto.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4zwAE/wEHAAH/4iOeWQAAAABJRU5ErkJggg=="));
		var stretched = new ashui.ui.Image(pair, {width: 24, height: 8}, bitmapTree);
		var letterboxed = new ashui.ui.Image(pair, {width: 16, height: 16, fit: Contain}, bitmapTree);
		var cropped = new ashui.ui.Image(pair, {width: 8, height: 16, fit: Cover}, bitmapTree);
		var backed = new Div({width: 24, height: 24, bg: Brush.bitmap(pair, Fill), cornerRadius: CornerRadius.all(12)}, bitmapTree);
		var tiled = new Div({width: 24, height: 24, bg: Brush.bitmap(pair, Tile)}, bitmapTree);
		var bitmapRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), gap: 4, padding: 4, flexDirection: Row, flexWrap: Wrap},
			[stretched, letterboxed, cropped, backed, tiled], bitmapTree);
		pixels = offscreen.renderToRgba8(bitmapRoot, SIZE, SIZE);
		label = "bitmap: ";
		probe("stretched, red on the left", 5, 8, (r, g, b) -> r > 200 && b < 60);
		probe("and blue on the right", 26, 8, (r, g, b) -> b > 200 && r < 60);
		probe("letterboxed, clear above", 40, 6, near(0xffffff));
		probe("and drawn in its band", 34, 12, (r, g, b) -> r > 200 && b < 60);
		probe("cropped to cover, its middle where red meets blue", 52, 12, (r, g, b) -> r > 60 && b > 60);
		probe("as a background, clipped to its rounded corner", 5, 29, near(0xffffff));
		probe("and filling its middle", 10, 40, (r, g, b) -> r > 150 && b < 120);
		probe("tiled, red in an even column", 36, 40, (r, g, b) -> r > 200 && b < 60);
		probe("blue in the odd one after", 37, 40, (r, g, b) -> b > 200 && r < 60);
		probe("and red again a cell on", 38, 40, (r, g, b) -> r > 200 && b < 60);
		probe("repeated across the box", 47, 44, (r, g, b) -> b > 200 && r < 60);

		// An image under two clips, the outer a squircle: where the inner clip cuts its corners away, it clips square, at full coverage.
		var nestTree = new LayoutTree();
		var nestedImage = new ashui.ui.Image(pair, {width: 16, height: 16}, nestTree);
		var innerClip = new Div({width: 16, height: 16, overflow: Overflow.Clip}, [nestedImage], nestTree);
		var outerClip = new Div({position: Position.Absolute, left: 4, top: 4, width: 56, height: 56, padding: 20, overflow: Overflow.Clip,
			cornerRadius: CornerRadius.all(18), cornerShape: ashui.types.CornerShape.squircle()}, [innerClip], nestTree);
		pixels = offscreen.renderToRgba8(new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [outerClip], nestTree), SIZE, SIZE);
		label = "nested clips: ";
		probe("an image inside a square clip inside a squircle one is drawn whole", 25, 32, (r, g, b) -> r > 230 && g < 20 && b < 40);

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
		// Frames of an animated UI in time the test keeps: a bar a CSS animation widens over a second.
		var motionSheet = ashui.css.Css.load('
			@keyframes slide { from { width: 10px } to { width: 50px } }
			.slide { width: 8px; height: 10px; background: #ff0000; animation: slide 1s linear; }
		');
		var motionTree = new LayoutTree();
		var bar = new Div({classes: ["slide"]}, motionTree);
		var motionRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), alignItems: Start}, [bar], motionTree);
		label = "animated: ";
		pixels = offscreen.renderAnimatedToRgba8(motionRoot, SIZE, SIZE, 0);
		probe("the first frame, the bar 10 wide", 20, 5, near(0xffffff));
		pixels = offscreen.renderAnimatedToRgba8(motionRoot, SIZE, SIZE, 0.5);
		probe("half a second on, 30 wide", 25, 5, near(0xff0000));
		probe("and no wider", 35, 5, near(0xffffff));
		pixels = offscreen.renderAnimatedToRgba8(motionRoot, SIZE, SIZE, 0.6);
		probe("ended, back to its own width, 8", 25, 5, near(0xffffff));
		probe("which it draws, and keeps: it does not start again", 5, 5, near(0xff0000));
		pixels = offscreen.renderAnimatedToRgba8(motionRoot, SIZE, SIZE, 0.5);
		probe("half a second later still its own width", 9, 5, near(0xffffff));
		ashui.css.Css.remove(motionSheet);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
