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
import ashui.canvaskit.Skybox;

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
		var device = ashui.core.render.Renderer.requestDevice(new GpuInstance().requestAdapter(Power.HighPerformance).await());
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

		// A canvas painting with its own shader over more than its box: the scissor and canvasClip keep it to its box and its parent's rounded clip.
		var canvasTree = new LayoutTree();
		var painted = 0;
		var canvasRoot:Div = ashui.reactive.Owner.root(canvasTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				paint: frame -> {
					painted++;
					frame.draw(CanvasProbeShader.WGSL, 6);
				}
			});
			canvas.node.set(Prop.Width, (40 : Single));
			canvas.node.set(Prop.Height, (40 : Single));
			var rounded = new Div({
				position: Position.Absolute, left: 8, top: 8, width: 48, height: 32, cornerRadius: CornerRadius.all(12), overflow: Overflow.Clip
			}, [canvas]);
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [rounded]);
		});
		pixels = offscreen.renderToRgba8(canvasRoot, SIZE, SIZE);
		label = "canvas: ";
		probe("its own shader paints its box", 28, 24, near(0xff0000));
		probe("its quad, larger than its box, is cut at the box's right edge", 52, 24, near(0xffffff));
		probe("and at its parent's bottom edge", 28, 44, near(0xffffff));
		probe("and its parent's rounded corner", 9, 9, near(0xffffff));
		probe("but not inside the corner's curve", 14, 14, near(0xff0000));
		probe("outside, the page", 4, 60, near(0xffffff));
		Sys.println('${painted > 0 ? "ok  " : "FAIL"} canvas: its paint ran: $painted');
		if (painted == 0)
			failures++;

		// A canvas's draw: shapes filled and stroked through a DrawContext, played on the GPU in the frame it is first laid out in.
		var drawTree = new LayoutTree();
		var drawRoot:Div = ashui.reactive.Owner.root(drawTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.fillRect(0, 0, 24, 24, Brush.solid(0xff0000), 4);
					ctx.fillCircle(36, 36, 10, Brush.solid(0x0000ff));
					ctx.strokeRect(26, 2, 20, 20, new ashui.draw.Stroke(4), Brush.solid(0x00ff00));
					ctx.fillCircle(46, 10, 0, Brush.solid(0x000000));
					ctx.fillCircle(-4, 40, 8, Brush.solid(0xff00ff));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(drawRoot, SIZE, SIZE);
		label = "canvas draw: ";
		probe("a filled rect", 18, 18, near(0xff0000));
		probe("its rounded corner left out", 8, 8, near(0xffffff));
		probe("a filled circle", 44, 44, near(0x0000ff));
		probe("a stroked rect's edge", 34, 20, near(0x00ff00));
		probe("and not its inside", 44, 20, near(0xffffff));
		probe("a shape past the canvas's edge, cut there", 6, 48, near(0xffffff));
		probe("and inside it, drawn", 9, 48, (r, g, b) -> r > 200 && g < 60 && b > 200);

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

		// Backdrop colour filters: a red stripe turns grey under a box with backdrop-filter: grayscale(1), with no blur, and stays red outside it.
		var greySheet = ashui.css.Css.load('.grey { backdrop-filter: grayscale(1); } .grey-tinted { backdrop-filter: invert(1); background: rgba(0, 0, 255, 0.5); }');
		var greyTree = new LayoutTree();
		var redStripe = new Div({position: Position.Absolute, left: 0, top: 20, width: SIZE, height: 12, bg: Brush.solid(0xff0000)}, greyTree);
		var greyBox = new Div({classes: ["grey"], position: Position.Absolute, left: 8, top: 8, width: 20, height: 40}, greyTree);
		var invertBox = new Div({classes: ["grey-tinted"], position: Position.Absolute, left: 36, top: 8, width: 20, height: 40}, greyTree);
		var greyRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [redStripe, greyBox, invertBox], greyTree);
		pixels = offscreen.renderToRgba8(greyRoot, SIZE, SIZE);
		label = "backdrop colour filters: ";
		probe("grayscale(1) turns the red under it grey", 16, 26, (r, g, b) -> Math.abs(r - g) < 4 && Math.abs(g - b) < 4 && r > 30 && r < 120);
		probe("and leaves the white round it white", 16, 12, near(0xffffff));
		probe("red stays red outside it", 32, 26, near(0xff0000));
		// invert(1) makes red cyan, then half blue is painted over: the filter applies before the background's tint.
		probe("invert(1) under a tint: the filter first, the tint over it", 46, 26, (r, g, b) -> r < 30 && g > 100 && g < 160 && b > 220);
		ashui.css.Css.remove(greySheet);
		// Tw's backdrop classes: backdrop-invert with no blur class turns the red behind cyan.
		var twTree = new LayoutTree();
		var twStripe = new Div({position: Position.Absolute, left: 0, top: 20, width: SIZE, height: 12, bg: Brush.solid(0xff0000)}, twTree);
		var twBox = new Div({position: Position.Absolute, left: 8, top: 8, width: 20, height: 40, style: ashui.style.Tw.tw("backdrop-invert")}, twTree);
		var twRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff)}, [twStripe, twBox], twTree);
		pixels = offscreen.renderToRgba8(twRoot, SIZE, SIZE);
		probe("Tw's backdrop-invert, with no blur class, inverts the red behind", 16, 26, near(0x00ffff));
		probe("and the white round it", 16, 12, near(0x000000));

		// Liquid glass's colour split follows the bevel, responds to a bound brush,
		// and leaves its centre, what is outside, and plain frosted glass alone.
		var glassTree = new LayoutTree();
		var glassBrush = ashui.reactive.Signal.make(Brush.glass(1, 0xffffff, 0.05, false, 0, 0));
		var checker:Array<ashui.layout.Element> = [];
		for (y in 0...8)
			for (x in 0...12)
				checker.push(new Div({position: Position.Absolute, left: x * 16, top: y * 16, width: 16, height: 16,
					bg: Brush.solid((x + y) % 2 == 0 ? 0x202020 : 0xffffff)}, glassTree));
		checker.push(new Div({position: Position.Absolute, left: 32, top: 16, width: 128, height: 96,
			cornerRadius: CornerRadius.all(24), bg: glassBrush}, glassTree));
		var glassRoot = new Div({width: 192, height: 128}, checker, glassTree);
		function glassCheck(name:String, ok:Bool, ?detail:Dynamic) {
			if (!ok)
				failures++;
			Sys.println('${ok ? "ok  " : "FAIL"} liquid glass: $name' + (detail == null ? "" : ': $detail'));
		}
		function chroma(p:haxe.io.Bytes):Int {
			var total = 0;
			for (y in 16...112)
				for (x in 32...160) {
					var i = (y * 192 + x) * 4;
					total += Std.int(Math.abs(p.get(i) - p.get(i + 1)) + Math.abs(p.get(i + 2) - p.get(i + 1)));
				}
			return total;
		}
		function glassDifference(a:haxe.io.Bytes, b:haxe.io.Bytes, left:Int, top:Int, right:Int, bottom:Int):Int {
			var total = 0;
			for (y in top...bottom)
				for (x in left...right)
					for (c in 0...4) {
						var i = (y * 192 + x) * 4 + c;
						total += Std.int(Math.abs(a.get(i) - b.get(i)));
					}
			return total;
		}
		var unsplit = offscreen.renderToRgba8(glassRoot, 192, 128);
		glassBrush.set(Brush.glass(1, 0xffffff, 0.05));
		var subtle = offscreen.renderToRgba8(glassRoot, 192, 128);
		glassBrush.set(Brush.glass(1, 0xffffff, 0.05, false, 0, 1));
		var strong = offscreen.renderToRgba8(glassRoot, 192, 128);
		glassCheck("0 disables the split; the default adds colour, and 1 increases it", chroma(unsplit) == 0
			&& chroma(subtle) > 1000 && chroma(strong) > chroma(subtle), [chroma(unsplit), chroma(subtle), chroma(strong)]);
		glassCheck("the split stays in the bevel", glassDifference(unsplit, strong, 64, 48, 128, 80) == 0
			&& glassDifference(unsplit, strong, 0, 0, 24, 128) == 0);
		glassBrush.set(Brush.glass(1, 0xffffff, 0.05, true, 0, 0));
		var frosted = offscreen.renderToRgba8(glassRoot, 192, 128);
		glassBrush.set(Brush.glass(1, 0xffffff, 0.05, true, 0, 1));
		glassCheck("simple frosted glass ignores aberration", frosted.compare(offscreen.renderToRgba8(glassRoot, 192, 128)) == 0);
		var clearTree = new LayoutTree();
		var clearBrush = ashui.reactive.Signal.make(Brush.glass(1, 0xffffff, 0.05, false, 0, 0));
		var clearGlass = new Div({position: Position.Absolute, left: 32, top: 16, width: 128, height: 96,
			cornerRadius: CornerRadius.all(24), bg: clearBrush}, clearTree);
		var clearRoot = new Div({width: 192, height: 128}, [clearGlass], clearTree);
		var clearUnsplit = offscreen.renderToRgba8(clearRoot, 192, 128);
		clearBrush.set(Brush.glass(1, 0xffffff, 0.05, false, 0, 1));
		var clearSplit = offscreen.renderToRgba8(clearRoot, 192, 128);
		glassCheck("a transparent window's rim highlights also disperse", chroma(clearUnsplit) == 0 && chroma(clearSplit) > 1000,
			[chroma(clearUnsplit), chroma(clearSplit)]);
		// A class and a stylesheet must produce the same pixels as the brush API,
		// and change the existing panel when a state or CSS variable changes.
		function styledGlass(?style:ashui.style.Style, ?classes:ashui.layout.IntoReactive<Array<String>>) {
			var styledTree = new LayoutTree();
			var backdrop:Array<ashui.layout.Element> = [];
			for (y in 0...8)
				for (x in 0...12)
					backdrop.push(new Div({position: Position.Absolute, left: x * 16, top: y * 16, width: 16, height: 16,
						bg: Brush.solid((x + y) % 2 == 0 ? 0x202020 : 0xffffff)}, styledTree));
			var panel = new Div({position: Position.Absolute, left: 32, top: 16, width: 128, height: 96,
				cornerRadius: CornerRadius.all(24), style: style, classes: classes}, styledTree);
			backdrop.push(panel);
			return {root: new Div({width: 192, height: 128}, backdrop, styledTree), panel: panel};
		}
		var twGlass = styledGlass(ashui.style.Tw.tw("bg-glass glass-blur-1 glass-tint-white/5 glass-aberration-0 hover:glass-aberration-100"));
		glassCheck("bg-glass utilities match the brush", unsplit.compare(offscreen.renderToRgba8(twGlass.root, 192, 128)) == 0);
		ashui.input.Interaction.of(twGlass.panel.node).hovered.set(true);
		glassCheck("a hover utility changes the existing glass bevel", strong.compare(offscreen.renderToRgba8(twGlass.root, 192, 128)) == 0);
		ashui.input.Interaction.of(twGlass.panel.node).hovered.set(false);
		glassCheck("leaving hover restores its base aberration", unsplit.compare(offscreen.renderToRgba8(twGlass.root, 192, 128)) == 0);
		var glassSheet = ashui.css.Css.load('
			.css-glass { background: glass; glass-blur: 1px; glass-tint: rgba(255,255,255,0.05); glass-aberration: var(--split, 0); glass-noise: 0; glass-mode: liquid; }
			.css-glass.strong { --split: 100%; }
			.css-glass.frosted { glass-mode: frosted; }
		');
		var glassClasses = ashui.reactive.Signal.make(["css-glass"]);
		var cssGlass = styledGlass(null, glassClasses);
		glassCheck("CSS glass settings match the brush", unsplit.compare(offscreen.renderToRgba8(cssGlass.root, 192, 128)) == 0);
		glassClasses.set(["css-glass", "strong"]);
		glassCheck("CSS class and variable updates change the bevel", strong.compare(offscreen.renderToRgba8(cssGlass.root, 192, 128)) == 0);
		glassClasses.set(["css-glass", "strong", "frosted"]);
		glassCheck("CSS can switch to frosted glass", frosted.compare(offscreen.renderToRgba8(cssGlass.root, 192, 128)) == 0);
		ashui.css.Css.remove(glassSheet);
		var frostedUtility = styledGlass(ashui.style.Tw.tw("bg-glass glass-frosted glass-blur-1 glass-tint-white/5 glass-aberration-100"));
		glassCheck("glass-frosted uses the existing frosted brush", frosted.compare(offscreen.renderToRgba8(frostedUtility.root, 192, 128)) == 0);
		var arbitraryGlass = styledGlass(ashui.style.Tw.tw("bg-glass [glass-blur:1px] [glass-tint:rgba(255,255,255,0.05)] [glass-aberration:1]"));
		glassCheck("arbitrary glass settings share the CSS path", strong.compare(offscreen.renderToRgba8(arbitraryGlass.root, 192, 128)) == 0);
		var backdropGlass = styledGlass(ashui.style.Tw.tw("bg-glass backdrop-blur-none glass-blur-1 glass-tint-white/5 glass-aberration-100"));
		glassCheck("backdrop utilities preserve the glass brush and explicit blur", strong.compare(offscreen.renderToRgba8(backdropGlass.root, 192, 128)) == 0);

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

		// CSS's url() reads an image file into a background, fitted by background-size.
		var pairFile = haxe.io.Path.join([Sys.getCwd(), "pixels-pair.png"]);
		sys.io.File.saveBytes(pairFile, haxe.crypto.Base64.decode("iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAIAAAB7QOjdAAAADUlEQVR4nGP4zwAE/wEHAAH/4iOeWQAAAABJRU5ErkJggg=="));
		var urlSheet = ashui.css.Css.load('.urlbg { background: url("$pairFile"); background-size: 100% 100%; }');
		var urlTree = new LayoutTree();
		var urlBox = new Div({classes: ["urlbg"], width: 48, height: 24}, urlTree);
		var urlRoot = new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [urlBox], urlTree);
		pixels = offscreen.renderToRgba8(urlRoot, SIZE, SIZE);
		label = "css url(): ";
		probe("the file stretched over the box, red on the left", 16, 20, (r, g, b) -> r > 200 && b < 60);
		probe("and blue on the right", 48, 20, (r, g, b) -> b > 200 && r < 60);
		ashui.css.Css.remove(urlSheet);
		sys.FileSystem.deleteFile(pairFile);

		// A canvas draws a bitmap into a rect, resampled for its size on screen, and at an opacity.
		var canvasImageTree = new LayoutTree();
		var canvasImageRoot:Div = ashui.reactive.Owner.root(canvasImageTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.image(pair, 0, 0, 32, 16);
					ctx.pushOpacity(0.5);
					ctx.image(pair, 0, 24, 32, 16);
					ctx.popOpacity();
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(canvasImageRoot, SIZE, SIZE);
		label = "canvas image: ";
		probe("stretched into its rect, red on the left", 14, 16, (r, g, b) -> r > 200 && b < 60);
		probe("and blue on the right", 34, 16, (r, g, b) -> b > 200 && r < 60);
		probe("nothing past its rect", 44, 16, near(0xffffff));
		probe("at half opacity, over the white under it", 14, 40, (r, g, b) -> r > 200 && g > 100 && g < 160 && b > 100 && b < 160);
		probe("its blue half too", 34, 40, (r, g, b) -> b > 200 && r > 100 && r < 160);

		// A pattern brush: dots every 12 units, 4 pixels across; scaled down, every fourth is kept.
		function patternRoot(kind:ashui.types.Brush.PatternKind, scale:Float):Div {
			var tree = new LayoutTree();
			return ashui.reactive.Owner.root(tree, _ -> {
				var canvas = new ashui.ui.Canvas({
					draw: ctx -> {
						ctx.pushTransform(new ashui.draw.Affine(scale, 0, 0, scale, 0, 0));
						ctx.fillRect(0, 0, 48 / scale, 48 / scale, Brush.pattern(kind, 0xff0000, 1, 12, 4));
						ctx.popTransform();
					}
				});
				canvas.node.set(Prop.Width, (48 : Single));
				canvas.node.set(Prop.Height, (48 : Single));
				new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
			});
		}
		var red = (r, g, b) -> r > 200 && g < 60 && b < 60;
		pixels = offscreen.renderToRgba8(patternRoot(Dots, 1), SIZE, SIZE);
		label = "pattern dots: ";
		probe("a dot at a crossing", 20, 20, red);
		probe("the next crossing too", 32, 20, red);
		probe("nothing between them", 26, 26, near(0xffffff));
		pixels = offscreen.renderToRgba8(patternRoot(Dots, 0.25), SIZE, SIZE);
		label = "pattern dots scaled down: ";
		probe("every fourth crossing is kept, the same size", 20, 20, red);
		probe("and those between are gone", 14, 14, near(0xffffff));
		pixels = offscreen.renderToRgba8(patternRoot(Lines, 1), SIZE, SIZE);
		label = "pattern lines: ";
		probe("on a line", 20, 14, red);
		probe("between lines", 14, 14, near(0xffffff));

		// One path drawn three times, moved: the third reuses the triangles made for the second, moved again.
		var reusedTree = new LayoutTree();
		var reusedRoot:Div = ashui.reactive.Owner.root(reusedTree, _ -> {
			var square = new ashui.draw.Path().rect(0, 0, 8, 8);
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					for (x in [0, 16, 32]) {
						ctx.pushTransform(new ashui.draw.Affine(1, 0, 0, 1, x, 20));
						ctx.fillPath(square, Brush.solid(0xff0000));
						ctx.popTransform();
					}
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(reusedRoot, SIZE, SIZE);
		label = "a path drawn again: ";
		probe("first where it was put", 12, 32, red);
		probe("second where it was put", 28, 32, red);
		probe("third, from the second's triangles, where it was put", 44, 32, red);
		probe("and nothing between them", 20, 32, near(0xffffff));

		// A canvas's clips: what is drawn is kept inside them, nested, until each is popped.
		var canvasClipTree = new LayoutTree();
		var canvasClipRoot:Div = ashui.reactive.Owner.root(canvasClipTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.pushClipCircle(24, 24, 16);
					ctx.fillRect(0, 0, 48, 48, Brush.solid(0x0000ff));
					ctx.pushClipRect(0, 0, 24, 48);
					ctx.fillRect(0, 0, 48, 48, Brush.solid(0xff0000));
					ctx.popClip();
					ctx.popClip();
					ctx.fillRect(0, 44, 48, 4, Brush.solid(0x00ff00));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(canvasClipRoot, SIZE, SIZE);
		label = "canvas clip: ";
		probe("kept inside the circle", 40, 32, (r, g, b) -> b > 200 && r < 60);
		probe("inside both clips, the inner draw", 24, 32, (r, g, b) -> r > 200 && b < 60);
		probe("nothing in the canvas's corner, outside the circle", 12, 12, near(0xffffff));
		probe("nor past the circle's edge", 52, 32, near(0xffffff));
		probe("drawn whole once the clips are popped", 32, 54, (r, g, b) -> g > 200 && r < 60 && b < 60);

		// Meshes on a canvas: the nearer hides the further, whatever order they are drawn in, inside the canvas's rounded clip.
		function quad(color:Int, z:Float):ashui.draw3d.MeshData
			return ashui.draw3d.MeshData.build([-1, -1, z, 1, -1, z, 1, 1, z, -1, 1, z], [0, 1, 2, 0, 2, 3], null, null, null,
				new ashui.draw3d.Material({baseColor: color, unlit: true}));
		var front = quad(0xff0000, 0), back = quad(0x0000ff, -1);
		var meshTree = new LayoutTree();
		var meshRoot:Div = ashui.reactive.Owner.root(meshTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setCamera(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 0, 3), ashui.math.Vec3.ZERO, null, 1.2));
					ctx.drawMesh(front, ashui.math.Mat4.scaling(new ashui.math.Vec3(0.5, 0.5, 1)));
					ctx.drawMesh(back, ashui.math.Mat4.scaling(new ashui.math.Vec3(2, 2, 1)));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			var rounded = new Div({width: 48, height: 48, overflow: Overflow.Clip, cornerRadius: CornerRadius.all(24)}, [canvas]);
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [rounded]);
		});
		pixels = offscreen.renderToRgba8(meshRoot, SIZE, SIZE);
		label = "canvas mesh: ";
		probe("the nearer quad in the middle, drawn first", 32, 32, (r, g, b) -> r > 200 && b < 60 && g < 60);
		probe("the further one around it", 18, 32, (r, g, b) -> b > 200 && r < 60);
		probe("cut by the rounded clip at the corner", 10, 10, near(0xffffff));

		// An environment from the kit: a LightRig lights with it and a SkyboxPass draws it behind, sky above and ground below; a polished sphere reflects it.
		var skyEnv = ashui.canvaskit.Environment.gradient(0x2060ff, 0x2060ff, 0x20c040, 1, 16);
		var skyPass = new ashui.canvaskit.SkyboxPass(Sky(skyEnv));
		var ballMesh:ashui.draw3d.MeshData = {
			var p:Array<Float> = [], idx:Array<Int> = [];
			for (r in 0...17)
				for (sg in 0...33) {
					var phi = r / 16 * Math.PI, theta = sg / 32 * Math.PI * 2;
					p.push(-Math.cos(theta) * Math.sin(phi));
					p.push(Math.cos(phi));
					p.push(Math.sin(theta) * Math.sin(phi));
				}
			for (r in 0...16)
				for (sg in 0...32) {
					var a = r * 33 + sg, b = a + 33;
					for (i in [a, b, a + 1, a + 1, b, b + 1])
						idx.push(i);
				}
			ashui.draw3d.MeshData.build(p, idx, p.copy(), null, null, new ashui.draw3d.Material({baseColor: 0xffffff, metallic: 1, roughness: 0.05}));
		};
		var envTree = new LayoutTree();
		var envRoot:Div = ashui.reactive.Owner.root(envTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setScene(ashui.draw3d.Scene3D.DEFAULT.with(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 0, 4), ashui.math.Vec3.ZERO, null, 1.0),
						new ashui.canvaskit.LightRig([], 0xffffff, 0.25, skyEnv, 1)));
					ctx.drawPass(skyPass);
					ctx.drawMesh(ballMesh, ashui.math.Mat4.scaling(new ashui.math.Vec3(0.6, 0.6, 0.6)));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(envRoot, SIZE, SIZE);
		label = "environment: ";
		probe("the skybox shows the sky at the top", 32, 10, (r, g, b) -> b > 150 && g < b && r < 120);
		probe("and the ground at the bottom", 32, 54, (r, g, b) -> g > 120 && g > b && r < 120);
		probe("a polished sphere reflects the sky near its top", 32, 26, (r, g, b) -> b > g && b > 100);
		probe("and the ground near its bottom", 32, 38, (r, g, b) -> g > b && g > 80);

		// A mesh's texture is compressed on the worker; the mesh is held back until it is in place, and the canvas says it is loading meanwhile.
		var loadingSeen:Array<Bool> = [];
		var halves = haxe.io.Bytes.alloc(8 * 8 * 4);
		for (i in 0...64) {
			var right = i % 8 >= 4;
			halves.set(i * 4, right ? 0 : 255);
			halves.set(i * 4 + 2, right ? 255 : 0);
			halves.set(i * 4 + 3, 255);
		}
		var halvesBitmap = ashui.types.Bitmap.fromBytes(ashui.core.render.Png.encode(8, 8, halves));
		var texturedQuad = ashui.draw3d.MeshData.build([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0], [0, 1, 2, 0, 2, 3], null, [0, 1, 1, 1, 1, 0, 0, 0], null,
			new ashui.draw3d.Material({baseColorTexture: halvesBitmap, unlit: true}));
		var restyled = ashui.reactive.Signal.make((null : ashui.draw3d.Material));
		var bcTree = new LayoutTree();
		var bcRoot:Div = ashui.reactive.Owner.root(bcTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setCamera(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 0, 2.4), ashui.math.Vec3.ZERO, null, 0.8));
					ctx.drawMesh(texturedQuad, null, restyled.get());
				},
				onLoading: v -> loadingSeen.push(v)
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		var before = ashui.core.render.MeshTextures.revision;
		pixels = offscreen.renderToRgba8(bcRoot, SIZE, SIZE);
		label = "compressed texture: ";
		probe("held back while it is compressed: the page shows through", 22, 32, (r, g, b) -> r > 200 && g > 200 && b > 200);
		// The compression finishes on its thread, then the scheduler puts it in place.
		var waited = 0;
		while (ashui.core.render.MeshTextures.revision == before && waited < 200) {
			Sys.sleep(0.01);
			ashui.animation.AnimationScheduler.main.tick(0);
			waited++;
		}
		var swapped = ashui.core.render.MeshTextures.revision > before;
		Sys.println('${swapped ? "ok  " : "FAIL"} compressed texture: its compression is put in place, after ${waited * 10}ms');
		if (!swapped)
			failures++;
		pixels = offscreen.renderToRgba8(bcRoot, SIZE, SIZE);
		probe("then compressed: red on its left", 22, 32, (r, g, b) -> r > 200 && b < 60);
		probe("and blue on its right", 42, 32, (r, g, b) -> b > 200 && r < 60);
		ashui.animation.AnimationScheduler.main.tick(0);
		var told = loadingSeen.join(",");
		Sys.println('${told == "true,false" ? "ok  " : "FAIL"} compressed texture: the canvas says it is loading, then that it is not: $told');
		if (told != "true,false")
			failures++;
		// Drawn in another material, its texture moved half across by a texture transform: the halves change places.
		restyled.set(texturedQuad.material.with({textureTransform: new ashui.draw3d.TextureTransform(1, 1, 0, 0.5, 0)}));
		pixels = offscreen.renderToRgba8(bcRoot, SIZE, SIZE);
		label = "texture transform: ";
		probe("moved half across, blue on the left", 22, 32, (r, g, b) -> b > 200 && r < 60);
		probe("and red on the right", 42, 32, (r, g, b) -> r > 200 && b < 60);

		// Fog: a mesh past where it is whole takes its colour; one nearer than where it starts keeps its own.
		var fogQuad = ashui.draw3d.MeshData.build([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0], [0, 1, 2, 0, 2, 3], null, null, null,
			new ashui.draw3d.Material({baseColor: 0xff0000, unlit: true}));
		var fogFar = ashui.reactive.Signal.make(true);
		var fogTree = new LayoutTree();
		var fogRoot:Div = ashui.reactive.Owner.root(fogTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					var z = fogFar.get() ? -30.0 : 0.0;
					ctx.setScene(ashui.draw3d.Scene3D.DEFAULT.with(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 0, 3), new ashui.math.Vec3(0, 0, z), null, 0.8),
						null, null, null, null, new ashui.draw3d.Fog(0x00ff00, 5, 20)));
					ctx.drawMesh(fogQuad, ashui.math.Mat4.translation(new ashui.math.Vec3(0, 0, z)).mul(ashui.math.Mat4.scaling(new ashui.math.Vec3(fogFar.get() ? 14 : 1, fogFar.get() ? 14 : 1, 1))));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(fogRoot, SIZE, SIZE);
		label = "fog: ";
		probe("a mesh past the fog's far end is the fog's colour", 32, 32, (r, g, b) -> g > 200 && r < 60);
		fogFar.set(false);
		pixels = offscreen.renderToRgba8(fogRoot, SIZE, SIZE);
		probe("one nearer than it starts keeps its own", 32, 32, (r, g, b) -> r > 200 && g < 60);

		// A 3D canvas moved out of view gives up its layer, and makes it again when it comes back.
		ashui.core.render.ScenePainter.idleRelease = 0;
		var awayQuad = ashui.draw3d.MeshData.build([-1, -1, 0, 1, -1, 0, 1, 1, 0, -1, 1, 0], [0, 1, 2, 0, 2, 3], null, null, null,
			new ashui.draw3d.Material({baseColor: 0x00ff00, unlit: true}));
		var awayTree = new LayoutTree();
		var mover:Null<Div> = null;
		var awayRoot:Div = ashui.reactive.Owner.root(awayTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setCamera(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 0, 2), ashui.math.Vec3.ZERO, null, 1.2));
					ctx.drawMesh(awayQuad, ashui.math.Mat4.scaling(new ashui.math.Vec3(3, 3, 1)));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			mover = new Div({position: Position.Relative}, [canvas]);
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8, overflow: Overflow.Clip}, [mover]);
		});
		pixels = offscreen.renderToRgba8(awayRoot, SIZE, SIZE);
		label = "3D out of view: ";
		var held = ashui.core.render.ScenePainter.layerBytes();
		probe("drawn in view", 32, 32, (r, g, b) -> g > 200 && r < 60);
		mover.node.set(Prop.Left, (200 : Single));
		pixels = offscreen.renderToRgba8(awayRoot, SIZE, SIZE);
		var away = ashui.core.render.ScenePainter.layerBytes();
		Sys.println('${held > 0 && away == 0 ? "ok  " : "FAIL"} 3D out of view: its layer is freed once it goes unpainted: $held bytes, then $away');
		if (!(held > 0 && away == 0))
			failures++;
		mover.node.set(Prop.Left, (0 : Single));
		pixels = offscreen.renderToRgba8(awayRoot, SIZE, SIZE);
		probe("made again and drawn when it comes back", 32, 32, (r, g, b) -> g > 200 && r < 60);
		ashui.core.render.ScenePainter.idleRelease = 1;

		// A ground grid seen from above: its major lines where whole units fall, nothing between them, hidden where a mesh is in front.
		var gridTree = new LayoutTree();
		var testGrid = new ashui.canvaskit.GroundGrid({size: 1, subdivisions: 1, major: 0xffffff, majorAlpha: 1, axes: false, fadeNear: 50, fadeFar: 60});
		var gridBlock = ashui.draw3d.MeshData.build([-0.3, 0.2, -0.3, 0.3, 0.2, -0.3, 0.3, 0.2, 0.3, -0.3, 0.2, 0.3], [0, 2, 1, 0, 3, 2], null, null, null,
			new ashui.draw3d.Material({baseColor: 0x0000ff, unlit: true}));
		var gridRoot:Div = ashui.reactive.Owner.root(gridTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					// Straight down at the origin, a little off so the view keeps a direction for up.
					ctx.setScene(ashui.draw3d.Scene3D.DEFAULT.with(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 3, 0.001), ashui.math.Vec3.ZERO, null, 1.2),
						new ashui.draw3d.SceneLighting.BasicLighting([]), null, 0x000000, 1));
					ctx.drawPass(testGrid);
					ctx.drawMesh(gridBlock);
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(gridRoot, SIZE, SIZE);
		label = "grid: ";
		// From 3 up with a 1.2 radian view the canvas spans about ±2 units: x = 1 lies about a quarter of the way in from its right.
		var lineX = 8 + 24 + Std.int(24 / (3 * Math.tan(0.6)));
		probe("a major line at x = 1, a pixel wide", lineX, 14, (r, g, b) -> r > 80 && g > 80 && b > 80);
		probe("nothing between the lines", lineX - 6, 14, (r, g, b) -> r < 60 && g < 60 && b < 60);
		probe("hidden by the mesh in front of it, at the origin", 32, 32, (r, g, b) -> b > 200 && r < 60);

		// Shadows: a quad held over a lit floor, the light slanting along +x, darkens the floor beside it and leaves the rest lit.
		var floor = ashui.draw3d.MeshData.build([-2, 0, -2, 2, 0, -2, 2, 0, 2, -2, 0, 2], [0, 2, 1, 0, 3, 2], null, null, null,
			new ashui.draw3d.Material({baseColor: 0xffffff, roughness: 1}));
		function blockerOf(material:ashui.draw3d.Material)
			return ashui.draw3d.MeshData.build([-1, 0.6, -0.3, -0.6, 0.6, -0.3, -0.6, 0.6, 0.3, -1, 0.6, 0.3], [0, 2, 1, 0, 3, 2], null, null, null, material);
		var blocker = ashui.reactive.Signal.make(blockerOf(new ashui.draw3d.Material({baseColor: 0x0000ff, unlit: true})));
		var shadowRig = new ashui.canvaskit.LightRig([Directional(new ashui.math.Vec3(1, -1, 0), 0xffffff, 3)], 0xffffff, 0.05, null, 1, {strength: 1});
		var shadowTree = new LayoutTree();
		var shadowRoot:Div = ashui.reactive.Owner.root(shadowTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setScene(ashui.draw3d.Scene3D.DEFAULT.with(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 3, 0.001), ashui.math.Vec3.ZERO, null, 1.2),
						shadowRig, null, 0x000000, 1));
					ctx.drawMesh(floor);
					ctx.drawMesh(blocker.get());
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(shadowRoot, SIZE, SIZE);
		label = "shadows: ";
		// The canvas spans about ±2 units: the shadow falls from x = -0.4 to 0, the floor at x = 0.8 is open to the light.
		var unit = 24 / (3 * Math.tan(0.6));
		function brightness(x:Int, y:Int)
			return pixels.get(y * ROW + x * 4) + pixels.get(y * ROW + x * 4 + 1) + pixels.get(y * ROW + x * 4 + 2);
		var dark = brightness(32 - Std.int(0.2 * unit), 32), lit = brightness(32 + Std.int(0.8 * unit), 32);
		Sys.println('${dark * 2 < lit ? "ok  " : "FAIL"} shadows: the floor in the shadow of the quad is darker than in the open: $dark against $lit');
		if (!(dark * 2 < lit))
			failures++;
		// Blended, it casts where it is solid and not where light passes through it.
		blocker.set(blockerOf(new ashui.draw3d.Material({baseColor: 0x0000ff, unlit: true, alphaMode: Blend})));
		pixels = offscreen.renderToRgba8(shadowRoot, SIZE, SIZE);
		var solidBlend = brightness(32 - Std.int(0.2 * unit), 32);
		blocker.set(blockerOf(new ashui.draw3d.Material({baseColor: 0x0000ff, unlit: true, alphaMode: Blend, alpha: 0.3})));
		pixels = offscreen.renderToRgba8(shadowRoot, SIZE, SIZE);
		var seeThrough = brightness(32 - Std.int(0.2 * unit), 32);
		var casts = solidBlend * 2 < lit && seeThrough > lit * 0.8;
		Sys.println('${casts ? "ok  " : "FAIL"} shadows: a blended quad casts when solid, $solidBlend, and not at alpha 0.3, $seeThrough, against $lit');
		if (!casts)
			failures++;

		// On the ground grid a shadow is as dark as the light it keeps off is strong against the rest: a second light on the floor lifts it.
		var catcher = new ashui.canvaskit.GroundGrid({minorAlpha: 0, majorAlpha: 0, axes: false, fadeNear: 50, fadeFar: 60});
		var post = ashui.canvaskit.Geometry.box(0.4, 0.6, 0.4, new ashui.draw3d.Material({baseColor: 0x0000ff, unlit: true}));
		var keyOnly = [ashui.draw3d.Light.Directional(new ashui.math.Vec3(1, -1, 0), 0xffffff, 3)];
		var catcherLights = ashui.reactive.Signal.make(keyOnly);
		var catcherTree = new LayoutTree();
		var catcherRoot:Div = ashui.reactive.Owner.root(catcherTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setScene(ashui.draw3d.Scene3D.DEFAULT.with(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 3, 0.001), ashui.math.Vec3.ZERO, null, 1.2),
						new ashui.canvaskit.LightRig(catcherLights.get(), 0xffffff, 0.05, null, 1, {strength: 1}), null, 0xffffff, 1));
					ctx.drawPass(catcher);
					ctx.drawMesh(post, ashui.math.Mat4.translation(new ashui.math.Vec3(-0.3, 0.3, 0)));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		// The post's shadow falls from x = -0.1 to 0.5; x = 0.1 is in it.
		var inShadow = 32 + Std.int(0.1 * unit) + 1;
		pixels = offscreen.renderToRgba8(catcherRoot, SIZE, SIZE);
		var keyAlone = brightness(inShadow, 32), open = brightness(32 + Std.int(1.2 * unit), 32);
		catcherLights.set(keyOnly.concat([ashui.draw3d.Light.Directional(new ashui.math.Vec3(0, -1, 0), 0xffffff, 3)]));
		pixels = offscreen.renderToRgba8(catcherRoot, SIZE, SIZE);
		var withFill = brightness(inShadow, 32);
		var catches = keyAlone * 2 < open && withFill > keyAlone + 90;
		Sys.println('${catches ? "ok  " : "FAIL"} shadows: the grid darkens under the key light alone, $keyAlone against $open in the open, less with a second light, $withFill');
		if (!catches)
			failures++;

		// A grounded sky's floor catches the shadows where no grid does.
		var studio = ashui.canvaskit.Environment.gradient(0x909090, 0x909090, 0x909090, 1, 16);
		var groundedSky = new ashui.canvaskit.SkyboxPass(Grounded(studio, 1.5, 20, 0));
		var groundedTree = new LayoutTree();
		var groundedRoot:Div = ashui.reactive.Owner.root(groundedTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setScene(ashui.draw3d.Scene3D.DEFAULT.with(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 3, 0.001), ashui.math.Vec3.ZERO, null, 1.2),
						new ashui.canvaskit.LightRig(keyOnly, 0xffffff, 0.05, studio, 1, {strength: 1}), null, 0x000000, 1));
					ctx.drawPass(groundedSky);
					ctx.drawMesh(post, ashui.math.Mat4.translation(new ashui.math.Vec3(-0.3, 0.3, 0)));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(groundedRoot, SIZE, SIZE);
		var onFloor = brightness(inShadow, 32), openFloor = brightness(32 + Std.int(1.2 * unit), 32);
		var caught = onFloor < openFloor * 0.75;
		Sys.println('${caught ? "ok  " : "FAIL"} shadows: the floor of a grounded sky darkens under the post, $onFloor against $openFloor in the open');
		if (!caught)
			failures++;

		// A material marked blended but solid hides what is behind it: its solid fragments are drawn with the opaque meshes, writing depth.
		// The quad in front is wide, so its middle is further from the eye and it is sorted to be drawn first.
		function blendQuad(x0:Float, x1:Float, z:Float, color:Int)
			return ashui.draw3d.MeshData.build([x0, -0.3, z, x1, -0.3, z, x1, 0.3, z, x0, 0.3, z], [0, 1, 2, 0, 2, 3], null, null, null,
				new ashui.draw3d.Material({baseColor: color, unlit: true, alphaMode: Blend}));
		var wideFront = blendQuad(-0.5, 4.5, 0.5, 0xff0000), smallBack = blendQuad(-0.4, 0.4, 0, 0x00ff00);
		var splitTree = new LayoutTree();
		var splitRoot:Div = ashui.reactive.Owner.root(splitTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setCamera(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 0, 3), ashui.math.Vec3.ZERO, null, 1.0));
					ctx.drawMesh(wideFront);
					ctx.drawMesh(smallBack);
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(splitRoot, SIZE, SIZE);
		label = "blended but solid: ";
		probe("the quad in front hides the one behind, though sorted first", 32, 32, (r, g, b) -> r > 200 && g < 60);

		// Frustum culling: a mesh behind the camera is left out, and drawn as soon as the camera turns to it.
		var ahead = ashui.draw3d.MeshData.build([-0.4, -0.4, 0, 0.4, -0.4, 0, 0.4, 0.4, 0, -0.4, 0.4, 0], [0, 1, 2, 0, 2, 3], null, null, null,
			new ashui.draw3d.Material({baseColor: 0x00ff00, unlit: true, doubleSided: true}));
		var lookBack = ashui.reactive.Signal.make(false);
		var cullTree = new LayoutTree();
		var cullRoot:Div = ashui.reactive.Owner.root(cullTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					var eye = new ashui.math.Vec3(0, 0, 3);
					ctx.setCamera(new ashui.draw3d.Camera(eye, new ashui.math.Vec3(0, 0, lookBack.get() ? 6 : 0), null, 1.0));
					ctx.drawMesh(ahead);
					ctx.drawMesh(ahead, ashui.math.Mat4.translation(new ashui.math.Vec3(0, 0, 6)));
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(cullRoot, SIZE, SIZE);
		label = "culling: ";
		var leftOut = ashui.core.render.ScenePainter.culled;
		Sys.println('${leftOut == 1 ? "ok  " : "FAIL"} culling: the mesh behind the camera is left out: $leftOut culled');
		if (leftOut != 1)
			failures++;
		probe("the mesh ahead is drawn", 32, 32, (r, g, b) -> g > 200 && r < 60);
		lookBack.set(true);
		pixels = offscreen.renderToRgba8(cullRoot, SIZE, SIZE);
		probe("turned round, the other is drawn", 32, 32, (r, g, b) -> g > 200 && r < 60);

		// One's own GPU drawing in a scene: a pass's quad and a mesh share depth, each hiding the other where it is in front.
		var front = new TestQuadPass(0.5), back = new TestQuadPass(-0.5);
		var passMesh = ashui.draw3d.MeshData.build([-0.4, -0.4, 0, 0.4, -0.4, 0, 0.4, 0.4, 0, -0.4, 0.4, 0], [0, 1, 2, 0, 2, 3], null, null, null,
			new ashui.draw3d.Material({baseColor: 0xff0000, unlit: true}));
		var passIn = ashui.reactive.Signal.make(back);
		var passTree = new LayoutTree();
		var passRoot:Div = ashui.reactive.Owner.root(passTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setCamera(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 0, 3), ashui.math.Vec3.ZERO, null, 1.0));
					ctx.drawMesh(passMesh);
					ctx.drawPass(passIn.get());
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(passRoot, SIZE, SIZE);
		label = "scene pass: ";
		probe("behind the mesh, the pass's quad shows around it", 22, 32, (r, g, b) -> g > 200 && r < 60);
		probe("and the mesh hides it in the middle", 32, 32, (r, g, b) -> r > 200 && g < 60);
		passIn.set(front);
		pixels = offscreen.renderToRgba8(passRoot, SIZE, SIZE);
		probe("in front of the mesh, the pass's quad hides it", 32, 32, (r, g, b) -> g > 200 && r < 60);

		// A material with a shader of its own, extending ashui's mesh shader: its colour as it is, where ashui's own lights and tone-maps it.
		function redQuad(x:Float, shader:Null<String>)
			return ashui.draw3d.MeshData.build([x - 0.45, -0.45, 0, x + 0.45, -0.45, 0, x + 0.45, 0.45, 0, x - 0.45, 0.45, 0], [0, 1, 2, 0, 2, 3], null, null,
				null, new ashui.draw3d.Material({baseColor: 0xff0000, shader: shader}));
		var ownShaded = redQuad(-0.5, FlatShade.WGSL), coreShaded = redQuad(0.5, null);
		var shadeTree = new LayoutTree();
		var shadeRoot:Div = ashui.reactive.Owner.root(shadeTree, _ -> {
			var canvas = new ashui.ui.Canvas({
				draw: ctx -> {
					ctx.setCamera(new ashui.draw3d.Camera(new ashui.math.Vec3(0, 0, 2.2), ashui.math.Vec3.ZERO, null, 1.0));
					ctx.drawMesh(ownShaded);
					ctx.drawMesh(coreShaded);
				}
			});
			canvas.node.set(Prop.Width, (48 : Single));
			canvas.node.set(Prop.Height, (48 : Single));
			new Div({width: SIZE, height: SIZE, bg: Brush.solid(0xffffff), padding: 8}, [canvas]);
		});
		pixels = offscreen.renderToRgba8(shadeRoot, SIZE, SIZE);
		label = "extended shader: ";
		probe("its own shade and present draw the colour as it is", 23, 32, (r, g, b) -> r == 255 && g == 0 && b == 0);
		probe("beside ashui's own, lit and tone-mapped", 41, 32, (r, g, b) -> r > 60 && r < 250 && g < 60);

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

/** A green quad two units square at depth `z`, drawn with its own pipeline and buffer after the opaque meshes, as a game's renderer would. **/
class TestQuadPass implements ashui.draw3d.ScenePass {
	final z:Float;
	var pipeline:Null<gpu.GpuPipeline> = null;
	var place:Null<gpu.GpuBuffer> = null;
	var group:Null<gpu.GpuBindGroup> = null;

	public function new(z:Float)
		this.z = z;

	public function stage():ashui.draw3d.ScenePass.SceneStage
		return Opaque;

	public function animated():Bool
		return false;

	public function prepare(frame:ashui.core.render.ScenePassFrame):Void {
		if (pipeline == null) {
			var builder = frame.pipelineBuilder(TestQuadShader.WGSL);
			builder.primitive(TriangleList, None, Ccw);
			pipeline = builder.build();
			place = frame.device.createBuffer(new gpu.GpuBufferDescriptor(16, ashui.core.render.GpuFlags.BUFFER_STORAGE | ashui.core.render.GpuFlags.BUFFER_COPY_DST));
			var b = haxe.io.Bytes.alloc(16);
			b.setFloat(0, z);
			frame.device.queue().writeBuffer(place, 0, b, 16);
		}
		if (group != null)
			group.destroy();
		var bindings = new gpu.GpuBindings();
		bindings.buffer(frame.sceneBuffer);
		bindings.buffer(place);
		group = frame.device.bindGroup(pipeline, 0, bindings);
		bindings.destroy();
	}

	public function draw(frame:ashui.core.render.ScenePassFrame):Void {
		frame.encoder.renderSetPipeline(pipeline);
		frame.encoder.renderSetBindGroup(0, group);
		frame.encoder.renderDraw(6, 1);
	}
}

/** The quad: through the scene's camera, by ashui's `Scene` module; green, opaque. **/
class TestQuadShader implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:import ashui.shaders.Scene;

		var output : { position : Vec4, color : Vec4 };

		@param var scene : StorageBuffer<Vec4>;
		@param var place : StorageBuffer<Vec4>;

		function vertex() {
			var c = vec2(-1., -1.);
			if (vertexID == 1 || vertexID == 4)
				c = vec2(1., -1.);
			if (vertexID == 2 || vertexID == 3)
				c = vec2(-1., 1.);
			if (vertexID == 5)
				c = vec2(1., 1.);
			output.position = worldToClip(vec4(c, place[0].x, 1.));
		}

		function fragment() {
			output.color = vec4(0., 1., 0., 1.);
		}
	};
}

/** ashui's mesh shader with its colour as it is: `shade` and `present` replaced, everything else inherited. **/
class FlatShade implements hlwgpu.hxsl.Shader {
	static var SRC = {
		@:extends ashui.core.render.MeshShader;

		function shade() : Vec3 {
			return surfaceColor.rgb;
		}

		function present(lit : Vec3) : Vec3 {
			return linearToSrgb(lit);
		}
	};
}
