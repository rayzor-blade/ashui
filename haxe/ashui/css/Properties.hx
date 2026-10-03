package ashui.css;

import ashui.css.CssValue;
import ashui.layout.Node;
import ashui.layout.Prop;
import ashui.types.Brush;
import ashui.types.Color;
import ashui.types.CornerRadius;
import ashui.types.CornerShape;
import ashui.types.Shadow;
import ashui.types.Style;
import ashui.types.Transform;

/** What a declaration's relative values resolve against. **/
typedef ApplyContext = {
	final viewportWidth:Float;
	final viewportHeight:Float;

	/** The element's font size, for `em`; its parent's while its own `font-size` is read. **/
	final fontSize:Float;

	final rootFontSize:Float;

	/** What `currentcolor` is: the element's `color`. **/
	final currentColor:CssColor;
}

/**
	CSS properties applied to a node: each reads its value with `CssValue`,
	turns it into ashui's values and writes it with the stylesheet's write,
	which leaves alone what the element set itself. Shorthands write their
	longhands. Each returns the fields it wrote, by `Node.field`, so the
	cascade can unset the ones a later match no longer writes.

	Lengths in `%` work where the layout takes them (`width`, `height`, the
	min and max sizes, `flex-basis`); `em`, `rem`, `vw` and `vh` resolve to
	pixels when applied.
**/
class Properties {
	/** The supported properties, by name. **/
	static final handlers:Map<String, (Node, String, ApplyContext) -> Array<Int>> = build();

	/** Whether `name` is a property this applies. **/
	public static function known(name:String):Bool
		return handlers.exists(name);

	/** Applies `name: value` to `node`; the fields written. Throws a `String` for a value it cannot read. **/
	public static function apply(node:Node, name:String, value:String, ctx:ApplyContext):Array<Int> {
		var handler = handlers.get(name);
		if (handler == null)
			throw '$name is not a property this supports';
		return handler(node, value, ctx);
	}

	static function build():Map<String, (Node, String, ApplyContext) -> Array<Int>> {
		var h = new Map<String, (Node, String, ApplyContext) -> Array<Int>>();

		// --- Sizes: px, %, auto ---
		var sizes:Array<{name:String, px:Prop<Single>, pct:Prop<Single>}> = [
			{name: "width", px: Prop.Width, pct: Prop.WidthPercent},
			{name: "height", px: Prop.Height, pct: Prop.HeightPercent},
			{name: "min-width", px: Prop.MinWidth, pct: Prop.MinWidthPercent},
			{name: "max-width", px: Prop.MaxWidth, pct: Prop.MaxWidthPercent},
			{name: "min-height", px: Prop.MinHeight, pct: Prop.MinHeightPercent},
			{name: "max-height", px: Prop.MaxHeight, pct: Prop.MaxHeightPercent},
			{name: "flex-basis", px: Prop.FlexBasis, pct: Prop.FlexBasisPercent}
		];
		for (size in sizes)
			h.set(size.name, (n, v, c) -> {
				var l = CssValue.length(v, true);
				switch l {
					case Percent(p):
						write(n, size.pct, p / 100);
					case Calc(_) if (!CssValue.isFixed(l)):
						throw 'calc() of anything but pixels is not supported for ${size.name}';
					case _:
						write(n, size.px, pixels(l, c));
				}
				[Node.field(size.px)];
			});

		// --- Spacing ---
		function sides(name:String, keys:Array<Prop<Single>>, auto:Bool, negative:Bool) {
			function one(n:Node, part:String, c:ApplyContext, p:Prop<Single>) {
				var l = CssValue.length(part, auto);
				if (l.match(Percent(_)))
					throw '$name in % is not supported';
				var px = pixels(l, c);
				if (!negative && px < 0)
					throw '$name cannot be negative';
				write(n, p, px);
			}
			h.set(name, (n, v, c) -> {
				var parts = CssValue.split(v, " ");
				var four = boxSides(parts, name);
				for (i in 0...4)
					one(n, four[i], c, keys[i]);
				[for (k in keys) Node.field(k)];
			});
			for (i => side in ["top", "right", "bottom", "left"])
				h.set('$name-$side', (n, v, c) -> {
					one(n, v, c, keys[i]);
					[Node.field(keys[i])];
				});
		}
		sides("padding", [Prop.PaddingTop, Prop.PaddingRight, Prop.PaddingBottom, Prop.PaddingLeft], false, false);
		sides("margin", [Prop.MarginTop, Prop.MarginRight, Prop.MarginBottom, Prop.MarginLeft], true, true);
		h.set("row-gap", (n, v, c) -> [single(n, Prop.GapY, v, c)]);
		h.set("column-gap", (n, v, c) -> [single(n, Prop.GapX, v, c)]);
		h.set("gap", (n, v, c) -> {
			var parts = CssValue.split(v, " ");
			if (parts.length > 2)
				throw "gap takes a row gap and an optional column gap";
			[single(n, Prop.GapY, parts[0], c), single(n, Prop.GapX, parts.length > 1 ? parts[1] : parts[0], c)];
		});

		// --- Position ---
		var insets:Array<{name:String, prop:Prop<Single>}> = [
			{name: "top", prop: Prop.Top}, {name: "right", prop: Prop.Right}, {name: "bottom", prop: Prop.Bottom}, {name: "left", prop: Prop.Left}
		];
		for (inset in insets)
			h.set(inset.name, (n, v, c) -> [single(n, inset.prop, v, c, true)]);
		h.set("inset", (n, v, c) -> {
			var four = boxSides(CssValue.split(v, " "), "inset");
			[
				single(n, Prop.Top, four[0], c, true), single(n, Prop.Right, four[1], c, true),
				single(n, Prop.Bottom, four[2], c, true), single(n, Prop.Left, four[3], c, true)
			];
		});
		h.set("position", (n, v, _) -> [
			enumWrite(n, Prop.Position, v, ["relative" => Position.Relative, "static" => Position.Relative, "absolute" => Position.Absolute])
		]);

		// --- Flexbox ---
		h.set("display", (n, v, _) -> [
			enumWrite(n, Prop.Display, v, ["flex" => Display.Flex, "block" => Display.Block, "grid" => Display.Grid, "none" => Display.None])
		]);
		h.set("flex-direction", (n, v, _) -> [
			enumWrite(n, Prop.FlexDirection, v, [
				"row" => FlexDirection.Row,
				"column" => FlexDirection.Column,
				"row-reverse" => FlexDirection.RowReverse,
				"column-reverse" => FlexDirection.ColumnReverse
			])
		]);
		h.set("flex-wrap", (n, v, _) -> [
			enumWrite(n, Prop.FlexWrap, v, ["nowrap" => FlexWrap.NoWrap, "wrap" => FlexWrap.Wrap, "wrap-reverse" => FlexWrap.WrapReverse])
		]);
		var aligns = [
			"start" => Align.Start, "end" => Align.End, "flex-start" => Align.FlexStart, "flex-end" => Align.FlexEnd, "center" => Align.Center,
			"baseline" => Align.Baseline, "stretch" => Align.Stretch
		];
		h.set("align-items", (n, v, _) -> [enumWrite(n, Prop.AlignItems, v, aligns)]);
		h.set("align-self", (n, v, _) -> [enumWrite(n, Prop.AlignSelf, v, aligns)]);
		h.set("justify-content", (n, v, _) -> [
			enumWrite(n, Prop.JustifyContent, v, [
				"start" => Justify.Start, "end" => Justify.End, "flex-start" => Justify.FlexStart, "flex-end" => Justify.FlexEnd,
				"center" => Justify.Center, "stretch" => Justify.Stretch, "space-between" => Justify.SpaceBetween,
				"space-evenly" => Justify.SpaceEvenly, "space-around" => Justify.SpaceAround
			])
		]);
		h.set("flex-grow", (n, v, _) -> [number(n, Prop.FlexGrow, v, 0)]);
		h.set("flex-shrink", (n, v, _) -> [number(n, Prop.FlexShrink, v, 0)]);
		h.set("flex", (n, v, c) -> {
			var t = v.toLowerCase();
			var parts:Array<String> = switch t {
				case "none": ["0", "0", "auto"];
				case "auto": ["1", "1", "auto"];
				case "initial": ["0", "1", "auto"];
				case _:
					var p = CssValue.split(t, " ");
					if (p.length == 1 && CssValue.dimension(p[0]) != null && CssValue.dimension(p[0]).unit == "") [p[0], "1", "0%"]
					else if (p.length == 2) [p[0], p[1], "0%"]
					else p;
			}
			if (parts.length != 3)
				throw "flex takes a grow, a shrink and a basis";
			[
				number(n, Prop.FlexGrow, parts[0], 0),
				number(n, Prop.FlexShrink, parts[1], 0)
			].concat(handlers.get("flex-basis")(n, parts[2], c));
		});
		h.set("overflow", (n, v, _) -> [
			enumWrite(n, Prop.Overflow, v, ["visible" => Overflow.Visible, "clip" => Overflow.Clip, "hidden" => Overflow.Hidden, "scroll" => Overflow.Scroll,
				"auto" => Overflow.Scroll])
		]);

		// --- Paint ---
		h.set("opacity", (n, v, _) -> {
			write(n, Prop.Opacity, clamp01(CssValue.amount(v)));
			[Node.field(Prop.Opacity)];
		});
		h.set("color", (n, v, c) -> {
			write(n, Prop.Color, colorOf(CssValue.color(v), c));
			[Node.field(Prop.Color)];
		});
		h.set("background-color", (n, v, c) -> {
			var col = colorOf(CssValue.color(v), c);
			write(n, Prop.Background, Brush.solid(col.rgb, col.alpha));
			[Node.field(Prop.Background)];
		});
		h.set("background-image", (n, v, _) -> {
			write(n, Prop.Background, image(v));
			[Node.field(Prop.Background)];
		});
		h.set("background", (n, v, c) -> {
			var t = StringTools.trim(v);
			var brush = if (t.toLowerCase() == "none") Brush.solid(0, 0) else if (CssValue.call(t) != null
				&& CssValue.call(t).name.indexOf("gradient") >= 0 || CssValue.call(t) != null && CssValue.call(t).name == "url") image(t) else {
				var col = colorOf(CssValue.color(t), c);
				Brush.solid(col.rgb, col.alpha);
			}
			write(n, Prop.Background, brush);
			[Node.field(Prop.Background)];
		});

		// --- Borders and outlines ---
		var widthProps:Array<Prop<Single>> = [Prop.BorderTopWidth, Prop.BorderRightWidth, Prop.BorderBottomWidth, Prop.BorderLeftWidth];
		var colorProps:Array<Prop<Color>> = [Prop.BorderTopColor, Prop.BorderRightColor, Prop.BorderBottomColor, Prop.BorderLeftColor];
		function borderWidth(part:String, c:ApplyContext):Float {
			return switch part.toLowerCase() {
				case "thin": 1;
				case "medium": 3;
				case "thick": 5;
				case _: Math.max(0, pixels(CssValue.length(part), c));
			}
		}
		h.set("border-width", (n, v, c) -> {
			var four = boxSides(CssValue.split(v, " "), "border-width");
			[for (i in 0...4) {
				write(n, widthProps[i], borderWidth(four[i], c));
				Node.field(widthProps[i]);
			}];
		});
		h.set("border-color", (n, v, c) -> {
			var four = boxSides(CssValue.split(v, " "), "border-color");
			[for (i in 0...4) {
				write(n, colorProps[i], colorOf(CssValue.color(four[i]), c));
				Node.field(colorProps[i]);
			}];
		});
		h.set("border-style", (n, v, _) -> {
			// Only whether there is a border: none and hidden draw none; every other style draws solid.
			var none = CssValue.split(v, " ").map(s -> s.toLowerCase() == "none" || s.toLowerCase() == "hidden");
			if (none.indexOf(true) < 0)
				return [];
			var four = boxSides([for (x in none) x ? "1" : "0"], "border-style");
			[for (i in 0...4) if (four[i] == "1") {
				write(n, widthProps[i], 0);
				Node.field(widthProps[i]);
			}];
		});
		/** `1px solid red`: a width, a style and a colour, any of them, in any order. **/
		function border(n:Node, v:String, c:ApplyContext, which:Array<Int>):Array<Int> {
			var width = 3.0, col:CssColor = c.currentColor, none = false;
			for (part in CssValue.split(v, " ")) {
				var p = part.toLowerCase();
				if (STYLES.indexOf(p) >= 0)
					none = p == "none" || p == "hidden";
				else if (p == "thin" || p == "medium" || p == "thick" || CssValue.dimension(p) != null)
					width = borderWidth(p, c);
				else
					col = CssValue.color(p);
			}
			var out = [];
			for (i in which) {
				write(n, widthProps[i], none ? 0 : width);
				write(n, colorProps[i], colorOf(col, c));
				out.push(Node.field(widthProps[i]));
				out.push(Node.field(colorProps[i]));
			}
			return out;
		}
		h.set("border", (n, v, c) -> border(n, v, c, [0, 1, 2, 3]));
		for (i => side in ["top", "right", "bottom", "left"]) {
			h.set('border-$side', (n, v, c) -> border(n, v, c, [i]));
			h.set('border-$side-width', (n, v, c) -> {
				write(n, widthProps[i], borderWidth(v, c));
				[Node.field(widthProps[i])];
			});
			h.set('border-$side-color', (n, v, c) -> {
				write(n, colorProps[i], colorOf(CssValue.color(v), c));
				[Node.field(colorProps[i])];
			});
		}
		h.set("border-radius", (n, v, c) -> {
			if (v.indexOf("/") >= 0)
				throw "elliptical corners (a / in border-radius) are not supported";
			var four = boxSides(CssValue.split(v, " "), "border-radius");
			var r = [for (part in four) {
				var l = CssValue.length(part);
				if (l.match(Percent(_)))
					throw "border-radius in % is not supported";
				Math.max(0, pixels(l, c));
			}];
			write(n, Prop.CornerRadius, new CornerRadius(r[0], r[1], r[2], r[3]));
			[Node.field(Prop.CornerRadius)];
		});
		h.set("corner-shape", (n, v, _) -> {
			var t = v.toLowerCase();
			var shape = switch t {
				case "round": CornerShape.round();
				case "squircle": CornerShape.squircle();
				case "bevel": CornerShape.bevel();
				case "scoop": CornerShape.scoop();
				case "notch": CornerShape.notch();
				case "square": CornerShape.square();
				case _:
					var call = CssValue.call(t);
					if (call == null || call.name != "superellipse")
						throw 'expected round, squircle, bevel, scoop, notch, square or superellipse(n), not "$v"';
					CornerShape.superellipse(CssValue.number(call.args));
			}
			n.style(cast Prop.CornerRadius, shape, true);
			[Node.CORNER_SHAPE];
		});
		h.set("outline", (n, v, c) -> {
			var width = 3.0, col:CssColor = c.currentColor, none = false;
			for (part in CssValue.split(v, " ")) {
				var p = part.toLowerCase();
				if (STYLES.indexOf(p) >= 0 || p == "auto")
					none = p == "none";
				else if (p == "thin" || p == "medium" || p == "thick" || CssValue.dimension(p) != null)
					width = borderWidth(p, c);
				else
					col = CssValue.color(p);
			}
			write(n, Prop.OutlineWidth, none ? 0 : width);
			write(n, Prop.OutlineColor, colorOf(col, c));
			[Node.field(Prop.OutlineWidth), Node.field(Prop.OutlineColor)];
		});
		h.set("outline-width", (n, v, c) -> {
			write(n, Prop.OutlineWidth, borderWidth(v, c));
			[Node.field(Prop.OutlineWidth)];
		});
		h.set("outline-color", (n, v, c) -> {
			write(n, Prop.OutlineColor, colorOf(CssValue.color(v), c));
			[Node.field(Prop.OutlineColor)];
		});
		h.set("outline-offset", (n, v, c) -> [single(n, Prop.OutlineOffset, v, c)]);

		// --- Effects ---
		h.set("box-shadow", (n, v, c) -> {
			var layers = CssValue.shadows(v);
			var shadow:Null<Shadow> = null;
			for (s in layers) {
				var col = colorOf(s.color, c);
				var x = pixels(s.x, c), y = pixels(s.y, c), blur = pixels(s.blur, c), spread = pixels(s.spread, c);
				shadow = shadow == null ? new Shadow(x, y, blur, col.rgb, col.alpha, spread, s.inset) : shadow.and(x, y, blur, col.rgb, col.alpha, spread, s.inset);
			}
			write(n, Prop.Shadow, shadow == null ? new Shadow(0, 0, 0, 0, 0) : shadow);
			[Node.field(Prop.Shadow)];
		});
		h.set("transform", (n, v, c) -> {
			write(n, Prop.Transform, transform(CssValue.transforms(v), c));
			[Node.field(Prop.Transform)];
		});
		h.set("filter", (n, v, c) -> {
			// Every filter back to its identity first, so one a rule leaves out is off.
			var props:Array<Prop<Single>> = [
				Prop.FilterBrightness, Prop.FilterContrast, Prop.FilterGrayscale, Prop.FilterHueRotate, Prop.FilterInvert, Prop.FilterSaturate,
				Prop.FilterSepia, Prop.FilterBlur
			];
			var values = [1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0];
			var dropped:Null<Shadow> = null;
			for (f in CssValue.filters(v))
				switch f {
					case Brightness(x): values[0] = x;
					case Contrast(x): values[1] = x;
					case Grayscale(x): values[2] = clamp01(x);
					case HueRotate(r): values[3] = r * 180 / Math.PI;
					case Invert(x): values[4] = clamp01(x);
					case Saturate(x): values[5] = x;
					case Sepia(x): values[6] = clamp01(x);
					case Blur(l): values[7] = pixels(l, c);
					case Opacity(_): throw "the opacity() filter is not supported; use opacity";
					case DropShadow(s):
						var col = colorOf(s.color, c);
						dropped = new Shadow(pixels(s.x, c), pixels(s.y, c), pixels(s.blur, c), col.rgb, col.alpha);
				}
			var out = [];
			for (i => p in props) {
				write(n, p, values[i]);
				out.push(Node.field(p));
			}
			if (dropped != null) {
				write(n, Prop.DropShadow, dropped);
				out.push(Node.field(Prop.DropShadow));
			}
			out;
		});
		h.set("clip-path", (n, v, _) -> {
			var path = try ashui.types.ClipPath.parse(v) catch (e:String) throw e;
			write(n, Prop.ClipPath, path);
			[Node.field(Prop.ClipPath)];
		});
		h.set("overflow-fade", (n, v, c) -> {
			var four = boxSides(CssValue.split(v, " "), "overflow-fade");
			var props:Array<Prop<Single>> = [Prop.FadeTop, Prop.FadeRight, Prop.FadeBottom, Prop.FadeLeft];
			[for (i in 0...4) single(n, props[i], four[i], c)];
		});

		// --- Text ---
		h.set("font-size", (n, v, c) -> {
			var l = CssValue.length(v);
			var px = switch l {
				case Percent(p): p / 100 * c.fontSize;
				case _: pixels(l, c);
			}
			if (px <= 0)
				throw "font-size must be more than 0";
			write(n, Prop.FontSize, px);
			[Node.field(Prop.FontSize)];
		});
		h.set("font-weight", (n, v, _) -> {
			var w:FontWeight = switch v.toLowerCase() {
				case "normal": Normal;
				case "bold": Bold;
				case "lighter": Light;
				case "bolder": Bold;
				case t:
					var x = Std.int(CssValue.number(t));
					if (x < 1 || x > 1000)
						throw "font-weight is 1 to 1000";
					x;
			}
			write(n, Prop.FontWeight, w);
			[Node.field(Prop.FontWeight)];
		});
		h.set("font-style", (n, v, _) -> [
			enumWrite(n, Prop.FontStyle, v, ["normal" => FontStyle.Normal, "italic" => FontStyle.Italic, "oblique" => FontStyle.Italic])
		]);
		h.set("font-family", (n, v, _) -> {
			// The first family named; generic names select the theme's.
			var first = StringTools.trim(CssValue.split(v, ",")[0]);
			if ((StringTools.startsWith(first, '"') && StringTools.endsWith(first, '"'))
				|| (StringTools.startsWith(first, "'") && StringTools.endsWith(first, "'")))
				first = first.substr(1, first.length - 2);
			write(n, Prop.FontFamily, first);
			[Node.field(Prop.FontFamily)];
		});
		h.set("line-height", (n, v, c) -> {
			var t = v.toLowerCase();
			var d = CssValue.dimension(t);
			var multiple = if (t == "normal") 1.2 else if (d != null && d.unit == "") d.value else if (d != null && d.unit == "%") d.value / 100 else
				pixels(CssValue.length(t), c) / c.fontSize;
			write(n, Prop.LineHeight, multiple);
			[Node.field(Prop.LineHeight)];
		});
		h.set("letter-spacing", (n, v, c) -> {
			var px = v.toLowerCase() == "normal" ? 0.0 : pixels(CssValue.length(v), c);
			write(n, Prop.LetterSpacing, px);
			[Node.field(Prop.LetterSpacing)];
		});
		h.set("text-align", (n, v, _) -> [
			enumWrite(n, Prop.TextAlign, v, [
				"left" => TextAlign.Left,
				"start" => TextAlign.Left,
				"center" => TextAlign.Center,
				"right" => TextAlign.Right,
				"end" => TextAlign.Right
			])
		]);
		return h;
	}

	static final STYLES = ["none", "hidden", "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset"];

	// --- Helpers ---

	static inline function write<T>(n:Node, prop:Prop<T>, value:T):Void
		n.style(prop, value);

	/** CSS's one-to-four values for the four sides, top, right, bottom, left. **/
	static function boxSides(parts:Array<String>, name:String):Array<String> {
		return switch parts.length {
			case 1: [parts[0], parts[0], parts[0], parts[0]];
			case 2: [parts[0], parts[1], parts[0], parts[1]];
			case 3: [parts[0], parts[1], parts[2], parts[1]];
			case 4: parts;
			case _: throw '$name takes one to four values';
		}
	}

	static function pixels(l:CssLength, c:ApplyContext):Float {
		if (l.match(Percent(_)))
			throw "a percentage is not supported here";
		return CssValue.resolve(l, {
			percentOf: 0,
			fontSize: c.fontSize,
			rootFontSize: c.rootFontSize,
			viewportWidth: c.viewportWidth,
			viewportHeight: c.viewportHeight
		});
	}

	/** A pixel length; NaN for `auto` where `auto` is allowed. **/
	static function single(n:Node, p:Prop<Single>, v:String, c:ApplyContext, auto = false):Int {
		write(n, p, pixels(CssValue.length(v, auto), c));
		return Node.field(p);
	}

	static function number(n:Node, p:Prop<Single>, v:String, min:Float):Int {
		var x = CssValue.number(v);
		if (x < min)
			throw 'expected a number of $min or more, not "$v"';
		write(n, p, x);
		return Node.field(p);
	}

	static function enumWrite<T>(n:Node, p:Prop<T>, v:String, values:Map<String, T>):Int {
		var x = values.get(StringTools.trim(v).toLowerCase());
		if (x == null)
			throw 'expected ${[for (k in values.keys()) k].join(", ")}, not "$v"';
		write(n, p, x);
		return Node.field(p);
	}

	static function colorOf(c:CssColor, ctx:ApplyContext):Color {
		return switch c {
			case Rgba(rgb, a): new Color(rgb, a);
			case CurrentColor:
				ctx.currentColor == CurrentColor ? new Color(0, 1) : colorOf(ctx.currentColor, ctx);
		}
	}

	static inline function clamp01(v:Float):Float
		return Math.max(0, Math.min(1, v));

	/** A gradient or `url()` as a brush; the gradient's points are fractions of the box. **/
	static function image(v:String):Brush {
		var call = CssValue.call(v);
		if (call != null && call.name == "url") {
			var src = StringTools.trim(call.args);
			if ((StringTools.startsWith(src, '"') || StringTools.startsWith(src, "'")) && src.length >= 2)
				src = src.substr(1, src.length - 2);
			return Brush.image(src);
		}
		var brush:Brush;
		var stops:Array<GradientStop>;
		switch CssValue.gradient(v) {
			case Linear(angle, s):
				// Along the angle through the centre, reaching the corners as CSS's gradient line does, in the unit box.
				var dx = Math.sin(angle), dy = -Math.cos(angle);
				var half = (Math.abs(dx) + Math.abs(dy)) / 2;
				brush = Brush.linear(0.5 - dx * half, 0.5 - dy * half, 0.5 + dx * half, 0.5 + dy * half, true);
				stops = s;
			case Radial(_, x, y, s):
				var far = 0.0;
				for (corner in [[0, 0], [1, 0], [0, 1], [1, 1]])
					far = Math.max(far, Math.sqrt(Math.pow(corner[0] - x, 2) + Math.pow(corner[1] - y, 2)));
				brush = Brush.radial(x, y, far, true);
				stops = s;
		}
		for (s in placed(stops))
			switch s.color {
				case Rgba(rgb, a): brush.stop(s.offset, rgb, a);
				case CurrentColor: brush.stop(s.offset, 0, 1);
			}
		return brush;
	}

	/** Stops without an offset spread evenly between the ones around them, the first at 0 and the last at 1, as CSS spreads them. **/
	static function placed(stops:Array<GradientStop>):Array<{color:CssColor, offset:Float}> {
		var offsets:Array<Null<Float>> = [for (s in stops) s.offset];
		if (offsets[0] == null)
			offsets[0] = 0;
		if (offsets[offsets.length - 1] == null)
			offsets[offsets.length - 1] = 1;
		var i = 0;
		while (i < offsets.length) {
			if (offsets[i] != null) {
				i++;
				continue;
			}
			var start = i - 1, end = i;
			while (offsets[end] == null)
				end++;
			for (k in i...end)
				offsets[k] = offsets[start] + (offsets[end] - offsets[start]) * (k - start) / (end - start);
			i = end;
		}
		// An offset before an earlier one moves up to it.
		for (k in 1...offsets.length)
			if (offsets[k] < offsets[k - 1])
				offsets[k] = offsets[k - 1];
		return [for (k in 0...stops.length) {color: stops[k].color, offset: offsets[k]}];
	}

	/** CSS's transform functions composed into one matrix, then split into ashui's parts: translate, rotate, skew, scale. **/
	static function transform(list:Array<CssTransform>, c:ApplyContext):Transform {
		var m = [1.0, 0.0, 0.0, 1.0, 0.0, 0.0];
		inline function mul(n:Array<Float>) {
			m = [
				m[0] * n[0] + m[2] * n[1],
				m[1] * n[0] + m[3] * n[1],
				m[0] * n[2] + m[2] * n[3],
				m[1] * n[2] + m[3] * n[3],
				m[0] * n[4] + m[2] * n[5] + m[4],
				m[1] * n[4] + m[3] * n[5] + m[5]
			];
		}
		for (t in list)
			switch t {
				case Translate(x, y):
					if (x.match(Percent(_)) || y.match(Percent(_)))
						throw "translate in % of the element's own size is not supported";
					mul([1, 0, 0, 1, pixels(x, c), pixels(y, c)]);
				case Scale(x, y):
					mul([x, 0, 0, y, 0, 0]);
				case Rotate(r):
					mul([Math.cos(r), Math.sin(r), -Math.sin(r), Math.cos(r), 0, 0]);
				case Skew(x, y):
					mul([1, Math.tan(y), Math.tan(x), 1, 0, 0]);
				case Matrix(a, b, cc, d, e, f):
					mul([a, b, cc, d, e, f]);
			}
		// m = R·K·S: R a rotation, K a skew along x, S a scale.
		var sx = Math.sqrt(m[0] * m[0] + m[1] * m[1]);
		if (sx == 0)
			return new Transform(m[4], m[5], 0, 0, 0);
		var rotation = Math.atan2(m[1], m[0]);
		var cos = Math.cos(rotation), sin = Math.sin(rotation);
		var sy = m[3] * cos - m[2] * sin;
		var kx = sy == 0 ? 0 : (m[2] * cos + m[3] * sin) / sy;
		return new Transform(m[4], m[5], rotation * 180 / Math.PI, sx, sy, Math.atan(kx) * 180 / Math.PI, 0);
	}
}
