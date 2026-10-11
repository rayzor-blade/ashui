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
import ashui.types.TextDecoration;
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

	/** The element's `backdrop-filter` blur, which its background frosts over: 0 when it has colour filters alone, -1 or null for no backdrop filter. **/
	final ?backdropBlur:Float;

	/** Whether the element has a `background` too, which then writes the frosted brush. **/
	final ?hasBackground:Bool;

	/** The element's `background-size`, which a `url()` image in its background is fitted by. **/
	final ?backgroundSize:String;

	/** Resolved glass-* declarations, read together when `background: glass` builds its brush. **/
	final ?glassProperties:Map<String, String>;
}

/**
	CSS properties applied to a node: each reads its value with `CssValue`,
	turns it into ashui's values and writes it with the stylesheet's write,
	which leaves alone what the element set itself. Shorthands write their
	longhands. Each returns the fields it wrote, by `Node.field`, so the
	cascade can unset the ones a later match no longer writes.

	Lengths in `%` reach native layout for sizes, flex basis, padding,
	margin, insets and gaps; `em`, `rem`, `vw` and `vh` resolve to pixels
	when applied.
**/
class Properties {
	/** The supported properties, by name. **/
	static final handlers:Map<String, (Node, String, ApplyContext) -> Array<Int>> = build();

	/**
		The longhands each shorthand sets. The cascade reads it both ways: a
		shorthand drops the longhands a weaker rule declared, and is applied
		before those a stronger rule declares, which then win.
	**/
	public static final LONGHANDS:Map<String, Array<String>> = {
		var sides = ["top", "right", "bottom", "left"];
		var m:Map<String, Array<String>> = [
			"margin" => [for (s in sides) 'margin-$s'],
			"padding" => [for (s in sides) 'padding-$s'],
			"inset" => sides.copy(),
			"gap" => ["row-gap", "column-gap"],
			"flex" => ["flex-grow", "flex-shrink", "flex-basis"],
			"background" => ["background-color", "background-image"],
			"overflow" => ["overflow-x", "overflow-y"],
			"place-content" => ["align-content", "justify-content"],
			"place-items" => ["align-items", "justify-items"],
			"place-self" => ["align-self", "justify-self"],
			"outline" => ["outline-width", "outline-color"],
			"border-width" => [for (s in sides) 'border-$s-width'],
			"border-color" => [for (s in sides) 'border-$s-color']
		];
		for (s in sides)
			m.set('border-$s', ['border-$s-width', 'border-$s-color']);
		var all = ["border-width", "border-color", "border-style"];
		for (s in sides)
			all = all.concat(['border-$s', 'border-$s-width', 'border-$s-color']);
		m.set("border", all);
		m;
	};

	/** 0 for a shorthand no other covers, 1 for one another covers, 2 for the rest: the order the cascade applies them in. **/
	public static function rank(name:String):Int {
		if (!LONGHANDS.exists(name))
			return 2;
		for (list in LONGHANDS)
			if (list.indexOf(name) >= 0)
				return 1;
		return 0;
	}

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
		h.set("visibility", (n, v, _) -> [enumWrite(n, Prop.Visibility, v,
			["visible" => Visibility.Visible, "hidden" => Visibility.Hidden, "collapse" => Visibility.Collapse])]);
		h.set("pointer-events", (n, v, _) -> [enumWrite(n, Prop.PointerEvents, v,
			["auto" => PointerEvents.Auto, "none" => PointerEvents.None])]);
		h.set("cursor", (_, v, _) -> {
			ashui.input.Cursor.parse(v);
			[];
		});

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
		function sides(name:String, keys:Array<Prop<Single>>, percentKeys:Array<Prop<Single>>, auto:Bool, negative:Bool) {
			function one(n:Node, part:String, c:ApplyContext, i:Int) {
				lengthWrite(n, keys[i], percentKeys[i], part, c, auto, negative);
			}
			h.set(name, (n, v, c) -> {
				var parts = CssValue.split(v, " ");
				var four = boxSides(parts, name);
				for (i in 0...4)
					one(n, four[i], c, i);
				[for (k in keys) Node.field(k)];
			});
			for (i => side in ["top", "right", "bottom", "left"])
				h.set('$name-$side', (n, v, c) -> {
					one(n, v, c, i);
					[Node.field(keys[i])];
				});
		}
		sides("padding", [Prop.PaddingTop, Prop.PaddingRight, Prop.PaddingBottom, Prop.PaddingLeft],
			[Prop.PaddingTopPercent, Prop.PaddingRightPercent, Prop.PaddingBottomPercent, Prop.PaddingLeftPercent], false, false);
		sides("margin", [Prop.MarginTop, Prop.MarginRight, Prop.MarginBottom, Prop.MarginLeft],
			[Prop.MarginTopPercent, Prop.MarginRightPercent, Prop.MarginBottomPercent, Prop.MarginLeftPercent], true, true);
		h.set("row-gap", (n, v, c) -> [lengthWrite(n, Prop.GapY, Prop.GapYPercent, v, c, false, false)]);
		h.set("column-gap", (n, v, c) -> [lengthWrite(n, Prop.GapX, Prop.GapXPercent, v, c, false, false)]);
		h.set("gap", (n, v, c) -> {
			var parts = CssValue.split(v, " ");
			if (parts.length < 1 || parts.length > 2)
				throw "gap takes a row gap and an optional column gap";
			[lengthWrite(n, Prop.GapY, Prop.GapYPercent, parts[0], c, false, false),
				lengthWrite(n, Prop.GapX, Prop.GapXPercent, parts.length > 1 ? parts[1] : parts[0], c, false, false)];
		});

		// --- Position ---
		var insets:Array<{name:String, prop:Prop<Single>, percent:Prop<Single>}> = [
			{name: "top", prop: Prop.Top, percent: Prop.TopPercent}, {name: "right", prop: Prop.Right, percent: Prop.RightPercent},
			{name: "bottom", prop: Prop.Bottom, percent: Prop.BottomPercent}, {name: "left", prop: Prop.Left, percent: Prop.LeftPercent}
		];
		for (inset in insets)
			h.set(inset.name, (n, v, c) -> [lengthWrite(n, inset.prop, inset.percent, v, c, true)]);
		h.set("inset", (n, v, c) -> {
			var four = boxSides(CssValue.split(v, " "), "inset");
				[for (i in 0...4) lengthWrite(n, insets[i].prop, insets[i].percent, four[i], c, true)];
		});
		h.set("position", (n, v, _) -> [
			enumWrite(n, Prop.Position, v, ["relative" => Position.Relative, "static" => Position.Relative, "absolute" => Position.Absolute,
				"sticky" => Position.Sticky])
		]);
		h.set("z-index", (n, v, _) -> {
			if (StringTools.trim(v).toLowerCase() == "auto")
				n.styleInitial(Prop.ZIndex);
			else
				write(n, Prop.ZIndex, integer(v, -2147483648.0));
			[Node.field(Prop.ZIndex)];
		});

		// --- Flexbox ---
		h.set("list-style-type", (_, v, _) -> {
			ashui.ui.Li.cssType(v);
			// The Li restyle hook reuses the list's counter and marker signals.
			[];
		});
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
			"baseline" => Align.Baseline, "stretch" => Align.Stretch, "normal" => Align.Auto
		];
		h.set("align-items", (n, v, _) -> [enumWrite(n, Prop.AlignItems, v, aligns)]);
		h.set("justify-items", (n, v, _) -> [enumWrite(n, Prop.JustifyItems, v, aligns)]);
		var selfAligns = aligns.copy();
		selfAligns.set("auto", Align.Auto);
		h.set("align-self", (n, v, _) -> [enumWrite(n, Prop.AlignSelf, v, selfAligns)]);
		h.set("justify-self", (n, v, _) -> [enumWrite(n, Prop.JustifySelf, v, selfAligns)]);
		var justifies = [
			"start" => Justify.Start, "end" => Justify.End, "flex-start" => Justify.FlexStart, "flex-end" => Justify.FlexEnd,
			"center" => Justify.Center, "stretch" => Justify.Stretch, "space-between" => Justify.SpaceBetween,
			"space-evenly" => Justify.SpaceEvenly, "space-around" => Justify.SpaceAround, "normal" => Justify.Normal
		];
		h.set("justify-content", (n, v, _) -> [enumWrite(n, Prop.JustifyContent, v, justifies)]);
		h.set("align-content", (n, v, _) -> [enumWrite(n, Prop.AlignContent, v, justifies)]);
		for (entry in ["content", "items", "self"]) {
			var kind = entry;
			h.set('place-$kind', (n, v, c) -> {
				var parts = CssValue.split(v, " ");
				if (parts.length < 1 || parts.length > 2)
					throw 'place-$kind takes one alignment or a pair';
				var first = h.get('align-$kind')(n, parts[0], c);
				return first.concat(h.get('justify-$kind')(n, parts.length == 1 ? parts[0] : parts[1], c));
			});
		}
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
		// Width over height: "16 / 9", a number, or auto for none.
		h.set("aspect-ratio", (n, v, _) -> {
			var t = StringTools.trim(v).toLowerCase();
			var ratio:Float = Math.NaN;
			if (t != "auto") {
				var parts = t.split("/").map(StringTools.trim);
				var w = Std.parseFloat(parts[0]), hh = parts.length > 1 ? Std.parseFloat(parts[1]) : 1.0;
				if (parts.length > 2 || Math.isNaN(w) || Math.isNaN(hh) || w <= 0 || hh <= 0)
					throw "aspect-ratio takes a width over a height, 16 / 9, a number or auto";
				ratio = w / hh;
			}
			write(n, Prop.AspectRatio, ratio);
			[Node.field(Prop.AspectRatio)];
		});
		// When a scroll container's thumb shows; after overflow in the alphabetical order of a restyle, so the container exists by then.
		h.set("scrollbar-width", (_, v, _) -> {
			scrollbarWidth(v);
			[];
		});
		h.set("scrollbar-color", (_, v, c) -> {
			// Validate here; Scroll's restyle hook applies after queued overflow creates the container.
			scrollbarColors(v, c.currentColor);
			[];
		});
		h.set("scrollbar-visibility", (n, v, _) -> {
			var key = StringTools.trim(v).toLowerCase();
			if (["auto", "always", "hover", "hidden"].indexOf(key) < 0)
				throw "scrollbar-visibility takes auto, always, hover or hidden";
			var scroll = ashui.input.Scroll.of(n);
			if (scroll != null)
				scroll.visibility = key;
			[];
		});
		// Scrolling along one axis or both makes the element a scroll container, as Tw's `overflow-auto` does.
		var overflows = ["visible" => Overflow.Visible, "clip" => Overflow.Clip, "hidden" => Overflow.Hidden, "scroll" => Overflow.Scroll,
			"auto" => Overflow.Scroll];
		function overflow(n:Node, prop:Prop<Overflow>, v:String):Int {
			return enumWrite(n, prop, v, overflows);
		}
		h.set("overflow", (n, v, _) -> {
			var parts = CssValue.split(v, " ");
			if (parts.length < 1 || parts.length > 2)
				throw "overflow takes one value or a pair of axes";
			return [overflow(n, Prop.OverflowX, parts[0]), overflow(n, Prop.OverflowY, parts.length == 1 ? parts[0] : parts[1])];
		});
		for (axis in [{name: "overflow-x", prop: Prop.OverflowX}, {name: "overflow-y", prop: Prop.OverflowY}]) {
			h.set(axis.name, (n, v, _) -> [overflow(n, axis.prop, v)]);
		}

		// --- Masks: a gradient the element and what it holds are drawn through; none for none ---
		for (name in ["mask-image", "-webkit-mask-image"])
			h.set(name, (n, v, _) -> {
				var t = StringTools.trim(v).toLowerCase();
				if (t == "none")
					return [];
				var call = CssValue.call(t);
				if (call == null || call.name.indexOf("gradient") < 0)
					throw 'expected a gradient or none, not "$v"';
				write(n, Prop.MaskImage, image(v));
				[Node.field(Prop.MaskImage)];
			});

		// --- Grid: tracks and lines, passed on as CSS text with lengths in px ---
		h.set("grid-template-columns", (n, v, c) -> {
			write(n, Prop.GridTemplateColumns, gridTemplate(v, c));
			[Node.field(Prop.GridTemplateColumns)];
		});
		h.set("grid-template-rows", (n, v, c) -> {
			write(n, Prop.GridTemplateRows, gridTemplate(v, c));
			[Node.field(Prop.GridTemplateRows)];
		});
		h.set("grid-column", (n, v, _) -> {
			write(n, Prop.GridColumn, gridLines(v));
			[Node.field(Prop.GridColumn)];
		});
		h.set("grid-row", (n, v, _) -> {
			write(n, Prop.GridRow, gridLines(v));
			[Node.field(Prop.GridRow)];
		});

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
			var blur = c.backdropBlur == null ? -1.0 : c.backdropBlur;
			write(n, Prop.Background, blur >= 0 ? Brush.blur(blur, col.rgb, col.alpha) : Brush.solid(col.rgb, col.alpha));
			[Node.field(Prop.Background)];
		});
		h.set("background-image", (n, v, c) -> {
			write(n, Prop.Background, image(v, c));
			[Node.field(Prop.Background)];
		});
		// Read by `background`'s `url()` images, through the context; nothing of its own to write.
		h.set("background-size", (_, _, _) -> []);
		h.set("object-fit", (n, v, _) -> {
			ashui.ui.Image.styleFit(n, ashui.ui.Image.cssFit(v));
			[];
		});
		// These settings belong to the glass background; they have no separate native field.
		for (name in ["glass-blur", "glass-tint", "glass-aberration", "glass-bevel", "glass-curvature", "glass-noise", "glass-mode"])
			h.set(name, (_, v, c) -> {
				validateGlass(name, v, c);
				[];
			});
		h.set("background", (n, v, c) -> {
			var t = StringTools.trim(v);
			var blur = c.backdropBlur == null ? -1.0 : c.backdropBlur;
			var brush = if (t.toLowerCase() == "glass") glass(c) else if (t.toLowerCase() == "none") blur >= 0 ? Brush.blur(blur) : Brush.solid(0, 0) else if (CssValue.call(t) != null
				&& CssValue.call(t).name.indexOf("gradient") >= 0 || CssValue.call(t) != null && CssValue.call(t).name == "url") image(t, c) else {
				var col = colorOf(CssValue.color(t), c);
				blur >= 0 ? Brush.blur(blur, col.rgb, col.alpha) : Brush.solid(col.rgb, col.alpha);
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
		// Set on the element that declares it; its text and its descendants' take the nearest, as CSS inherits it.
		h.set("text-shadow", (n, v, c) -> {
			var shadow:Null<Shadow> = null;
			if (StringTools.trim(v).toLowerCase() != "none")
				// One at a time without `inset`, so a spread or inset is refused as text-shadow has neither.
				for (part in CssValue.split(v, ",")) {
					var s = CssValue.shadow(part, false);
					var col = colorOf(s.color, c);
					var x = pixels(s.x, c), y = pixels(s.y, c), blur = pixels(s.blur, c);
					shadow = shadow == null ? new Shadow(x, y, blur, col.rgb, col.alpha) : shadow.and(x, y, blur, col.rgb, col.alpha);
				}
			write(n, Prop.TextShadow, shadow == null ? new Shadow(0, 0, 0, 0, 0) : shadow);
			[Node.field(Prop.TextShadow)];
		});
		// Set on the element that declares one; its text and its descendants' stack with their
		// own, as a node's draw does walking its ancestors, so none here does not undo one above.
		for (name in ["text-decoration", "text-decoration-line", "text-decoration-style", "text-decoration-color", "text-decoration-thickness",
			"text-underline-offset"])
			h.set(name, (n, v, c) -> {
				var d = decoration(name, v, c);
				if (d == null)
					return [];
				write(n, Prop.TextDecoration, d);
				[Node.field(Prop.TextDecoration)];
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
		// What is behind the box blurred and colour-filtered, under its background; the background writes the brush when there is one.
		h.set("backdrop-filter", (n, v, c) -> {
			var r = backdropBlur(v, c);
			var props:Array<Prop<Single>> = [
				Prop.BackdropBrightness, Prop.BackdropContrast, Prop.BackdropGrayscale, Prop.BackdropHueRotate, Prop.BackdropInvert, Prop.BackdropSaturate,
				Prop.BackdropSepia
			];
			var values = backdropColors(v);
			var out = [for (i => p in props) {
				write(n, p, values[i]);
				Node.field(p);
			}];
			if (c.hasBackground != true) {
				write(n, Prop.Background, r >= 0 ? Brush.blur(r) : Brush.solid(0, 0));
				out.push(Node.field(Prop.Background));
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
			// The whole stack: the first family installed is used, or the first generic name, as the theme's monospace.
			write(n, Prop.FontFamily, StringTools.trim(v));
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
		// Whether text breaks lines at its width: nowrap and pre keep it to one line; the rest wrap.
		h.set("white-space", (n, v, _) -> {
			var keep = switch StringTools.trim(v).toLowerCase() {
				case "nowrap" | "pre": true;
				case "normal" | "pre-wrap" | "pre-line" | "break-spaces": false;
				case other: throw 'white-space takes normal, nowrap, pre, pre-wrap, pre-line or break-spaces, not "$other"';
			}
			write(n, Prop.TextWrap, keep ? 0.0 : 1.0);
			[Node.field(Prop.TextWrap)];
		});
		h.set("text-overflow", (n, v, _) -> [
			enumWrite(n, Prop.TextOverflow, v, ["clip" => TextOverflow.Clip, "ellipsis" => TextOverflow.Ellipsis])
		]);
		for (name in ["line-clamp", "-webkit-line-clamp"])
			h.set(name, (n, v, _) -> {
				write(n, Prop.LineClamp, StringTools.trim(v).toLowerCase() == "none" ? 0 : integer(v, 1));
				[Node.field(Prop.LineClamp)];
			});
		h.set("letter-spacing", (n, v, c) -> {
			var px = v.toLowerCase() == "normal" ? 0.0 : pixels(CssValue.length(v), c);
			write(n, Prop.LetterSpacing, px);
			[Node.field(Prop.LetterSpacing)];
		});
		// How a flow of text breaks a word longer than its line; InlineFlow reads them from the cascade.
		for (name in ["overflow-wrap", "word-wrap", "word-break"])
			h.set(name, (_, _, _) -> []);
		h.set("text-align", (n, v, _) -> [
			enumWrite(n, Prop.TextAlign, v, [
				"left" => TextAlign.Left,
				"start" => TextAlign.Left,
				"center" => TextAlign.Center,
				"right" => TextAlign.Right,
				"end" => TextAlign.Right,
				// A text node draws one line as it is; a flow of text justifies its lines (see InlineFlow).
				"justify" => TextAlign.Left
			])
		]);
		return h;
	}

	static final STYLES = ["none", "hidden", "solid", "dashed", "dotted", "double", "groove", "ridge", "inset", "outset"];

	// --- Helpers ---

	/**
		The radius of `backdrop-filter`'s `blur()`: 0 when it has colour
		filters alone, -1 for `none`. Throws for a filter a backdrop does not
		take: `opacity()` and `drop-shadow()`.
	**/
	public static function backdropBlur(v:Null<String>, c:ApplyContext):Float {
		if (v == null || StringTools.trim(v).toLowerCase() == "none")
			return -1;
		var r = 0.0;
		for (f in CssValue.filters(v))
			switch f {
				case Blur(l): r = pixels(l, c);
				case Opacity(_) | DropShadow(_): throw "backdrop-filter takes blur() and the colour filters, not opacity() or drop-shadow()";
				case _:
			}
		return r;
	}

	/** `backdrop-filter`'s colour filters, in the backdrop properties' order, each its identity unless given. **/
	static function backdropColors(v:String):Array<Float> {
		var values = [1.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0];
		if (StringTools.trim(v).toLowerCase() == "none")
			return values;
		for (f in CssValue.filters(v))
			switch f {
				case Brightness(x): values[0] = x;
				case Contrast(x): values[1] = x;
				case Grayscale(x): values[2] = clamp01(x);
				case HueRotate(r): values[3] = r * 180 / Math.PI;
				case Invert(x): values[4] = clamp01(x);
				case Saturate(x): values[5] = x;
				case Sepia(x): values[6] = clamp01(x);
				case _:
			}
		return values;
	}

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

	/** `v`'s top-level parts, split at `sep` or, for a space, at any whitespace, leaving parentheses whole. **/
	static function topLevel(v:String, sep:String):Array<String> {
		var out = [], depth = 0, start = 0;
		for (i in 0...v.length) {
			var ch = v.charAt(i);
			if (ch == "(")
				depth++;
			else if (ch == ")")
				depth--;
			else if (depth == 0 && (sep == " " ? StringTools.isSpace(v, i) : ch == sep)) {
				out.push(v.substring(start, i));
				start = i + 1;
			}
		}
		out.push(v.substr(start));
		return [for (p in out) if (StringTools.trim(p) != "") StringTools.trim(p)];
	}

	/** A track list checked, its lengths resolved to px, as the layout reads it. **/
	static function gridTemplate(v:String, c:ApplyContext):String {
		var value = StringTools.trim(v).toLowerCase();
		if (value == "none")
			return value;
		function size(t:String, flexible:Bool):String {
			if (t == "auto" || t == "min-content" || t == "max-content" || (flexible && Patterns.RE0.match(t)))
				return t;
			if (StringTools.endsWith(t, "%") && CssValue.number(t.substr(0, t.length - 1)) >= 0)
				return t;
			return pixels(CssValue.length(t), c) + "px";
		}
		function track(t:String):String {
			var inner = Patterns.RE1;
			if (!inner.match(t))
				return size(t, true);
			var args = topLevel(inner.matched(2), ",");
			return switch [inner.matched(1), args.length] {
				case ["minmax", 2]: 'minmax(${size(args[0], false)}, ${size(args[1], true)})';
				case ["fit-content", 1]: 'fit-content(${size(args[0], false)})';
				case _: throw 'expected minmax(min, max) or fit-content(length), not "$t"';
			}
		}
		return [
			for (part in topLevel(value, " ")) {
				var repeat = Patterns.RE2;
				if (repeat.match(part)) {
					var args = topLevel(repeat.matched(1), ",");
					var count = args.shift();
					if (args.length != 1 || (count != "auto-fill" && count != "auto-fit" && !Patterns.RE3.match(count)))
						throw 'expected repeat(count, tracks), not "$part"';
					'repeat($count, ${[for (t in topLevel(args[0], " ")) track(t)].join(" ")})';
				} else
					track(part);
			}
		].join(" ");
	}

	/** `grid-column` or `grid-row`: a start and an optional end, each a line number, `span n` or `auto`. **/
	static function gridLines(v:String):String {
		var parts = [for (p in v.split("/")) StringTools.trim(p).toLowerCase()];
		if (parts.length > 2)
			throw 'expected start / end, not "$v"';
		for (p in parts)
			if (p != "auto" && !Patterns.RE4.match(p) && !Patterns.RE5.match(p))
				throw 'expected a line, span n or auto, not "$p"';
		return parts.join(" / ");
	}

	/**
		`background: glass` defaults to liquid glass with 12px blur, white/10 tint,
		0.3 aberration, a full outward bevel and no noise. The glass-* properties override those settings.
	**/
	static function glass(c:ApplyContext):Brush {
		function setting(name:String, fallback:String):String {
			var value = c.glassProperties == null ? null : c.glassProperties.get(name);
			if (value == null)
				return fallback;
			// A bad setting is reported by its own handler, and leaves this setting at its default.
			return try {
				validateGlass(name, value, c);
				value;
			} catch (_:String) fallback;
		}
		var tint = colorOf(CssValue.color(setting("glass-tint", "rgba(255,255,255,0.1)")), c);
		var blur = c.backdropBlur != null && c.backdropBlur >= 0 ? '${c.backdropBlur}px' : "12px";
		return Brush.glass(pixels(CssValue.length(setting("glass-blur", blur)), c), tint.rgb, tint.alpha,
			StringTools.trim(setting("glass-mode", "liquid")).toLowerCase() == "frosted",
			CssValue.amount(setting("glass-noise", "0")), CssValue.amount(setting("glass-aberration", "0.3")),
			CssValue.amount(setting("glass-bevel", "1")), StringTools.trim(setting("glass-curvature", "outset")).toLowerCase() == "inset");
	}

	static function validateGlass(name:String, value:String, c:ApplyContext):Void {
		switch name {
			case "glass-blur":
				var blur = pixels(CssValue.length(value), c);
				if (!Math.isFinite(blur) || blur < 0)
					throw "expected a nonnegative length";
			case "glass-tint": CssValue.color(value);
			case "glass-aberration" | "glass-noise" | "glass-bevel":
				var amount = CssValue.amount(value);
				if (!Math.isFinite(amount) || amount < 0 || amount > 1)
					throw "expected 0 to 1, or 0% to 100%";
			case "glass-mode":
				if (["liquid", "frosted"].indexOf(StringTools.trim(value).toLowerCase()) < 0)
					throw "expected liquid or frosted";
			case "glass-curvature":
				if (["inset", "outset"].indexOf(StringTools.trim(value).toLowerCase()) < 0)
					throw "expected inset or outset";
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
	/** Pixel and percentage forms write one physical field; ownership and resets use its pixel id. **/
	static function lengthWrite(n:Node, p:Prop<Single>, percent:Prop<Single>, v:String, c:ApplyContext, auto = false, negative = true):Int {
		var l = CssValue.length(v, auto);
		switch l {
			case Percent(x):
				if (!negative && x < 0)
					throw "this length cannot be negative";
				write(n, percent, x / 100);
			case _:
				var px = pixels(l, c);
				if (!negative && px < 0)
					throw "this length cannot be negative";
				write(n, p, px);
		}
		return Node.field(p);
	}

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

	/** A complete signed 32-bit CSS integer; never silently truncate a fraction or overflow. **/
	static function integer(v:String, min:Float):Int {
		var value = StringTools.trim(v);
		var x = Std.parseFloat(value);
		if (!~/^[+-]?[0-9]+$/.match(value) || x < min || x > 2147483647.0)
			throw 'expected an integer from $min to 2147483647, not "$v"';
		return Std.int(x);
	}

	static function enumWrite<T>(n:Node, p:Prop<T>, v:String, values:Map<String, T>):Int {
		var x = values.get(StringTools.trim(v).toLowerCase());
		if (x == null)
			throw 'expected ${[for (k in values.keys()) k].join(", ")}, not "$v"';
		write(n, p, x);
		return Node.field(p);
	}

	// --- Text decoration ---

	static final DECORATION_STYLES = ["solid" => Solid, "double" => Double, "dotted" => Dotted, "dashed" => Dashed];

	/** `text-decoration-line`'s bits, or `none`'s 0. **/
	static function decorationLines(v:String):Int {
		var lines = 0, none = false;
		for (word in CssValue.split(v, " "))
			switch word.toLowerCase() {
				case "none": none = true;
				case "underline": lines |= ashui.types.DecorationLine.Underline;
				case "overline": lines |= ashui.types.DecorationLine.Overline;
				case "line-through": lines |= ashui.types.DecorationLine.LineThrough;
				case "blink" | "spelling-error" | "grammar-error": throw 'text-decoration-line $word is not supported';
				case _: throw 'expected none, underline, overline or line-through, not "$word"';
			}
		if (none && lines != 0)
			throw "none stands alone in text-decoration-line";
		if (!none && lines == 0)
			throw "expected none, underline, overline or line-through";
		return lines;
	}

	static function decorationStyle(v:String):ashui.types.DecorationStyle {
		var key = StringTools.trim(v).toLowerCase();
		if (key == "wavy")
			throw "text-decoration-style wavy is not supported";
		var s = DECORATION_STYLES.get(key);
		if (s == null)
			throw 'expected solid, double, dotted or dashed, not "${StringTools.trim(v)}"';
		return s;
	}

	/** `currentcolor` as none, the text's own. **/
	static function decorationColor(v:String, c:ApplyContext):Null<Color> {
		if (StringTools.trim(v).toLowerCase() == "currentcolor")
			return null;
		return colorOf(CssValue.color(v), c);
	}

	/** `auto`/`from-font` as none, the font's own; else a length, or a percentage of the font size, in pixels. **/
	static function decorationLength(v:String, c:ApplyContext):Null<Float> {
		var key = StringTools.trim(v).toLowerCase();
		if (key == "auto" || key == "from-font")
			return null;
		var d = CssValue.dimension(v);
		if (d != null && d.unit == "%")
			return d.value / 100 * c.fontSize;
		return pixels(CssValue.length(v), c);
	}

	/** What `text-decoration`'s shorthand names: a line, a style, a colour and a thickness, in any order. **/
	static function decorationShorthand(v:String, c:ApplyContext):{lines:Null<Int>, style:Null<ashui.types.DecorationStyle>, colorSet:Bool,
		color:Null<Color>, thicknessSet:Bool, thickness:Null<Float>} {
		var lineWords = [];
		var style:Null<ashui.types.DecorationStyle> = null;
		var colorSet = false, color:Null<Color> = null;
		var thicknessSet = false, thickness:Null<Float> = null;
		for (word in CssValue.split(v, " ")) {
			var lower = word.toLowerCase();
			if (["none", "underline", "overline", "line-through", "blink"].indexOf(lower) >= 0)
				lineWords.push(word);
			else if (DECORATION_STYLES.exists(lower) || lower == "wavy") {
				if (style != null)
					throw "text-decoration names one style";
				style = decorationStyle(word);
			} else {
				var d = CssValue.dimension(word);
				if (lower == "auto" || lower == "from-font" || (d != null && (d.unit != "" || d.value == 0))) {
					if (thicknessSet)
						throw "text-decoration names one thickness";
					thicknessSet = true;
					thickness = decorationLength(word, c);
				} else {
					if (colorSet)
						throw "text-decoration names one colour";
					colorSet = true;
					color = decorationColor(word, c);
				}
			}
		}
		return {
			lines: lineWords.length == 0 ? null : decorationLines(lineWords.join(" ")),
			style: style,
			colorSet: colorSet,
			color: color,
			thicknessSet: thicknessSet,
			thickness: thickness
		};
	}

	/**
		How the node is decorated, from `text-decoration` and its five
		longhands, the ones beside `name: v` read from `c.glassProperties`;
		null when none of them draws anything. A property other than `name`
		that fails to parse is left at its default rather than failing the
		whole declaration, as a browser does; `name`'s own failure throws.
	**/
	static function decoration(name:String, v:String, c:ApplyContext):Null<TextDecoration> {
		var declared = c.glassProperties;
		inline function of(wanted:String):Null<String>
			return name == wanted ? v : (declared == null ? null : declared.get(wanted));

		var lines:Null<Int> = null;
		var style:Null<ashui.types.DecorationStyle> = null;
		var color:Null<Color> = null, hasColor = false;
		var thickness:Null<Float> = null, hasThickness = false;

		var shorthand = of("text-decoration");
		if (shorthand != null)
			try {
				var p = decorationShorthand(shorthand, c);
				lines = p.lines == null ? 0 : p.lines;
				style = p.style;
				if (p.colorSet) {
					hasColor = true;
					color = p.color;
				}
				if (p.thicknessSet) {
					hasThickness = true;
					thickness = p.thickness;
				}
			} catch (e:String) {
				if (name == "text-decoration")
					throw e;
			}
		var line = of("text-decoration-line");
		if (line != null)
			try
				lines = decorationLines(line)
			catch (e:String) {
				if (name == "text-decoration-line")
					throw e;
			}
		var s = of("text-decoration-style");
		if (s != null)
			try
				style = decorationStyle(s)
			catch (e:String) {
				if (name == "text-decoration-style")
					throw e;
			}
		var col = of("text-decoration-color");
		if (col != null)
			try {
				color = decorationColor(col, c);
				hasColor = true;
			} catch (e:String) {
				if (name == "text-decoration-color")
					throw e;
			}
		var thick = of("text-decoration-thickness");
		if (thick != null)
			try {
				var t = decorationLength(thick, c);
				if (t != null && t < 0)
					throw "expected a nonnegative thickness, not a negative one";
				thickness = t;
				hasThickness = true;
			} catch (e:String) {
				if (name == "text-decoration-thickness")
					throw e;
			}
		var offset:Null<Float> = null;
		var off = of("text-underline-offset");
		if (off != null)
			try
				offset = decorationLength(off, c)
			catch (e:String) {
				if (name == "text-underline-offset")
					throw e;
			}
		if (lines == null)
			return null;
		return new TextDecoration(lines, style, hasColor ? color : null, hasThickness ? thickness : null, offset);
	}

	@:noCompletion public static function scrollbarWidth(value:String):Float {
		return switch StringTools.trim(value).toLowerCase() {
			case "auto": 4.0;
			case "thin": 2.0;
			case "none": 0.0;
			case _: throw "scrollbar-width takes auto, thin or none";
		};
	}

	/** Plain color data: scrollbar CSS does not allocate native style-value handles. **/
	@:noCompletion public static function scrollbarColors(value:String, current:CssColor):Null<ashui.input.Scroll.ScrollbarColors> {
		if (StringTools.trim(value).toLowerCase() == "auto") return null;
		var parts = CssValue.split(value, " ");
		if (parts.length != 2) throw "scrollbar-color takes auto or a thumb and track color";
		function rgba(value:String):ashui.input.Scroll.ScrollbarColor {
			var color = CssValue.color(value);
			if (color == CurrentColor) color = current;
			return switch color {
				case Rgba(rgb, alpha): {rgb: rgb, alpha: alpha};
				case CurrentColor: {rgb: 0, alpha: 1};
			};
		}
		return {thumb: rgba(parts[0]), track: rgba(parts[1])};
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

	/**
		A gradient or `url()` as a brush; the gradient's points are fractions
		of the box. A `url()` of a PNG, JPEG or WebP file, relative to the
		working directory, is that bitmap, read once: by `background-size` in
		`c`, covering, contained or stretched (`100% 100%`), else at its own
		size, repeated, as CSS draws one.
	**/
	static function image(v:String, ?c:ApplyContext):Brush {
		var call = CssValue.call(v);
		if (call != null && call.name == "url") {
			var src = StringTools.trim(call.args);
			if ((StringTools.startsWith(src, '"') || StringTools.startsWith(src, "'")) && src.length >= 2)
				src = src.substr(1, src.length - 2);
			#if sys
			if (~/\.(png|jpe?g|webp)$/i.match(src)) {
				var size = c == null || c.backgroundSize == null ? "auto" : StringTools.trim(c.backgroundSize).toLowerCase();
				var fit:ashui.types.Brush.ImageFit = switch size {
					case "cover": Cover;
					case "contain": Contain;
					case "100% 100%": Fill;
					case _: Tile;
				}
				// A file that cannot be read draws nothing, as a browser draws a broken image.
				var bitmap = try ashui.types.Bitmap.load(src) catch (_:Dynamic) null;
				return bitmap == null ? Brush.solid(0, 0) : Brush.bitmap(bitmap, fit);
			}
			#end
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

/** The patterns above, each made once: a `~/…/` written in a function is compiled again every time it runs. **/
private class Patterns {
	public static final RE0 = ~/^[0-9]*\.?[0-9]+fr$/;
	public static final RE1 = ~/^(minmax|fit-content)\((.*)\)$/;
	public static final RE2 = ~/^repeat\((.*)\)$/;
	public static final RE3 = ~/^[1-9][0-9]*$/;
	public static final RE4 = ~/^span [1-9][0-9]*$/;
	public static final RE5 = ~/^-?[1-9][0-9]*$/;
}
