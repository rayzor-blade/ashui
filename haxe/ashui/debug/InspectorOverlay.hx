package ashui.debug;

import ashui.core.render.FrameOverlay;
import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.input.Pointer;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.ui.Div;

/** One element as the inspector shows it. **/
typedef Inspected = {
	id:haxe.Int64,
	label:String,
	/** Its ancestors' labels, the root first. **/
	path:Array<String>,
	x:Float,
	y:Float,
	w:Float,
	h:Float,
	/** Margin, border and padding as layout resolved them, in layout units: top, right, bottom, left. **/
	margin:Array<Float>,
	border:Array<Float>,
	padding:Array<Float>,
	states:Array<String>,
	handlers:Array<String>,
	/** The CSS declarations that win for it, `var()`s replaced, each with where it came from; custom properties left out. **/
	style:Array<{name:String, value:String, from:String}>,
	/** How many declarations that match it were overridden. **/
	overridden:Int
}

/**
	The element under the pointer, as a browser's inspector shows it: its
	margin, border, padding and content boxes shaded over the UI, and a
	panel with its place in the tree, its size, its interaction states and
	handlers, and the CSS declarations that win for it with the rule and
	line each came from.

	Set `ASHUI_INSPECT=1`, or add `new InspectorOverlay()` to
	`Offscreen.overlays`. `pin` holds it on one element. Like the other
	overlays, its elements live in a tree of their own.
**/
class InspectorOverlay implements FrameOverlay {
	/** The most properties the panel lists. **/
	public var maxProperties = 18;

	/** The element it shows whatever the pointer is over; null to follow the pointer. **/
	public var pinned:Null<haxe.Int64> = null;

	var pointerX = Math.NaN;
	var pointerY = Math.NaN;
	var inside = false;

	public function new() {}

	/** The overlay for this process, or null when `ASHUI_INSPECT` does not ask for one. **/
	public static function fromEnvironment():Null<InspectorOverlay> {
		return switch Sys.getEnv("ASHUI_INSPECT") {
			case "1" | "overlay": new InspectorOverlay();
			case _: null;
		}
	}

	/** Holds the inspector on `id`; null follows the pointer again. **/
	public function pin(id:Null<haxe.Int64>):Void
		pinned = id;

	/** Whether the pointer moved since the last call, so the window draws again. **/
	public function pointerChanged(tree:LayoutTree):Bool {
		var at = Pointer.at(tree);
		var changed = at.inside != inside || (at.inside && (at.x != pointerX || at.y != pointerY));
		pointerX = at.x;
		pointerY = at.y;
		inside = at.inside;
		return changed;
	}

	/** The element the inspector shows now: the pinned one, or the topmost under the pointer. **/
	public function target(tree:LayoutTree):Null<haxe.Int64> {
		if (pinned != null)
			return pinned;
		var at = Pointer.at(tree);
		if (!at.inside)
			return null;
		var path = tree.hitTest(at.x, at.y);
		return path.length == 0 ? null : path[0].id;
	}

	/** What the inspector shows of `id` in `tree`; null when it is not laid out. **/
	public function inspect(tree:LayoutTree, id:haxe.Int64):Null<Inspected> {
		var b = tree.getBounds(new Node(id));
		if (b == null)
			return null;
		var identity = Identity.of(tree, id);
		var up = tree.ancestors(id);
		var style = [], overridden = 0;
		if (identity != null)
			for (o in ashui.css.Css.explain(identity)) {
				if (!o.wins) {
					overridden++;
					continue;
				}
				if (StringTools.startsWith(o.name, "--"))
					continue;
				var v = o.value.indexOf("var(") >= 0 ? ashui.css.Css.resolve(identity, o.value) : o.value;
				style.push({name: o.name, value: v, from: ashui.css.Css.where(o)});
			}
		var box = tree.getBox(new Node(id));
		var none = [0.0, 0.0, 0.0, 0.0];
		var input = Interaction.byId(tree, id);
		var path = [for (a in up) MotionTrace.describe(tree, a)];
		path.reverse();
		return {
			id: id,
			label: MotionTrace.describe(tree, id),
			path: path,
			x: b.x,
			y: b.y,
			w: b.width,
			h: b.height,
			margin: box == null ? none : box.margin,
			border: box == null ? none : box.border,
			padding: box == null ? none : box.padding,
			states: TreeSnapshot.states(tree, id),
			handlers: input == null ? [] : input.handlerKinds(),
			style: style,
			overridden: overridden
		};
	}

	public function draw(tree:LayoutTree, root:Node, width:Int, height:Int, paint:Element->Void):Void {
		var id = target(tree);
		var e = id == null ? null : inspect(tree, id);
		var own = new LayoutTree();
		Owner.root(own, dispose -> {
			var out:Array<Element> = [];
			if (e != null) {
				var m = e.margin, b = e.border, p = e.padding;
				// Margin outside the border box, then the border, the padding and the content inside it, as a browser shades them.
				band(own, out, e.x - m[3], e.y - m[0], e.w + m[1] + m[3], e.h + m[0] + m[2], m, MARGIN);
				band(own, out, e.x, e.y, e.w, e.h, b, BORDER);
				var px = e.x + b[3], py = e.y + b[0], pw = e.w - b[1] - b[3], ph = e.h - b[0] - b[2];
				band(own, out, px, py, pw, ph, p, PADDING);
				out.push(MotionOverlay.box(own, px + p[3], py + p[0], pw - p[1] - p[3], ph - p[0] - p[2], CONTENT, 0.25));
				out.push(MotionOverlay.box(own, e.x, e.y, e.w, e.h, null, 0, 0x4cc9f0, 0.9));
				panel(own, e, width, height, out);
			}
			paint(new Div({width: width, height: height}, out, own));
			dispose();
		});
		own.dispose();
	}

	/** The band `widths` deep inside the box at `(x, y)`, sized `w` by `h`: four strips, top, right, bottom and left. **/
	static function band(own:LayoutTree, out:Array<Element>, x:Float, y:Float, w:Float, h:Float, widths:Array<Float>, colour:Int):Void {
		var t = widths[0], r = widths[1], b = widths[2], l = widths[3];
		if (t > 0)
			out.push(MotionOverlay.box(own, x, y, w, t, colour, 0.45));
		if (b > 0)
			out.push(MotionOverlay.box(own, x, y + h - b, w, b, colour, 0.45));
		if (l > 0)
			out.push(MotionOverlay.box(own, x, y + t, l, h - t - b, colour, 0.45));
		if (r > 0)
			out.push(MotionOverlay.box(own, x + w - r, y + t, r, h - t - b, colour, 0.45));
	}

	function panel(own:LayoutTree, e:Inspected, width:Int, height:Int, out:Array<Element>):Void {
		var w = Math.min(360, Math.max(0, width - 16));
		var count = Std.int(Math.min(e.style.length, maxProperties));
		var h = 112 + count * 28 + (e.style.length > count ? 15 : 0);
		// Beside the element where there is room, so it does not cover it; in the bottom corner for one that fills the view.
		var x = e.x + e.w + 8 + w <= width ? e.x + e.w + 8 : e.x - w - 8 >= 0 ? e.x - w - 8 : width - w - 8;
		var y = Math.max(8, Math.min(e.y, height - h - 8));
		if (e.x - w - 8 < 0 && e.x + e.w + 8 + w > width)
			y = Math.max(8, height - h - 8);
		var dim = 0xaab0c0;
		out.push(MotionOverlay.box(own, x, y, w, h, 0x0b0d14, 0.95, 0x4cc9f0, 0.8, 6));
		out.push(MotionOverlay.text(own, x + 10, y + 8, shorten('${e.label}  ${round(e.w)} × ${round(e.h)}', w - 20, 12), 0xffffff, 1, 12));
		out.push(MotionOverlay.text(own, x + 10, y + 26, shorten(e.path.concat([e.label]).join(" > "), w - 20, 10), dim, 1, 10));
		out.push(MotionOverlay.text(own, x + 10, y + 44, shorten('margin ${list(e.margin)}  border ${list(e.border)}  padding ${list(e.padding)}', w - 20, 10),
			0xd0d5e0, 1, 10));
		out.push(MotionOverlay.text(own, x + 10, y + 60, shorten('states ${e.states.length == 0 ? "none" : e.states.join(", ")}', w - 20, 10), 0xd0d5e0, 1, 10));
		out.push(MotionOverlay.text(own, x + 10, y + 76, shorten('handlers ${e.handlers.length == 0 ? "none" : e.handlers.join(", ")}', w - 20, 10), 0xd0d5e0,
			1, 10));
		out.push(MotionOverlay.text(own, x + 10, y + 94, e.overridden > 0 ? 'css · ${e.overridden} overridden' : "css", dim, 1, 10));
		for (i in 0...count) {
			var s = e.style[i];
			out.push(MotionOverlay.text(own, x + 10, y + 110 + i * 28, shorten('${s.name}: ${s.value}', w - 20, 10), 0x93c47d, 1, 10));
			out.push(MotionOverlay.text(own, x + 18, y + 123 + i * 28, shorten(s.from, w - 28, 9), dim, 1, 9));
		}
		if (e.style.length > count)
			out.push(MotionOverlay.text(own, x + 10, y + 110 + count * 28, '+${e.style.length - count} more', dim, 1, 10));
	}

	static function list(sides:Array<Float>):String
		return sides[0] == sides[1] && sides[1] == sides[2] && sides[2] == sides[3] ? round(sides[0]) : [for (s in sides) round(s)].join(" ");

	static function round(v:Float):String
		return Std.string(Math.round(v * 10) / 10);

	static function shorten(s:String, width:Float, size:Float):String {
		var length = Std.int(Math.max(0, width / (size * 0.6)));
		return s.length <= length ? s : s.substr(0, Std.int(Math.max(0, length - 1))) + "…";
	}

	static inline var MARGIN = 0xf6b26b;
	static inline var BORDER = 0xffe599;
	static inline var PADDING = 0x93c47d;
	static inline var CONTENT = 0x6fa8dc;
}
