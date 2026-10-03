package ashui.style;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

/**
	Tailwind-style utility classes over the theme's tokens, resolved at
	compile time:

	    final card = tw("p-4 gap-2 bg-surface rounded-lg shadow-md");
	    hxx('<div class="flex flex-col p-4 bg-surface-elevated">...</div>');

	The classes come from the token families, so a token added to the theme
	gets its classes with it:

	- spacing, `SpacingToken` steps: `p-`, `m-`, `gap-`, `w-`, `h-`, `size-`,
	  `min-w-`, `max-w-`, `min-h-`, `max-h-`, `top-`, `right-`, `bottom-`,
	  `left-`, `inset-` with `0`, `0.5`, `1` … `32`;
	- colours, `ColorToken` by its CSS variable name: `bg-`, `text-`,
	  `border-` with `primary`, `surface-elevated`, `text-secondary` …;
	- corners, `RadiusToken`: `rounded`, `rounded-sm` … `rounded-3xl`,
	  `rounded-full`, and the shapes `corner-squircle`, `corner-bevel`,
	  `corner-scoop`, `corner-notch`, `corner-square`, `corner-round`;
	- shadows, `ShadowToken`: `shadow`, `shadow-sm` … `shadow-2xl`,
	  `shadow-inner`, `shadow-none`;
	- type, `TypographyToken`: `text-xs` … `text-5xl`, `font-thin` …
	  `font-black`, `leading-none` … `leading-loose`.

	A class bound to a token follows the theme: a scheme switch or an
	override updates it, and nothing is rebuilt. Layout keywords with no
	token are Tailwind's: `flex`, `flex-col`, `items-center`,
	`justify-between`, `grow`, `shrink-0`, `overflow-hidden`, `absolute`,
	`opacity-50`, `border`, `border-2` and the like.

	An unknown class is a compile error at the class, naming the nearest
	known one; a class ashui cannot bind yet says why.
**/
class Tw {
	/** `classes`, a string literal, as a `Style`. **/
	public static macro function tw(classes:ExprOf<String>):ExprOf<Style> {
		var sets = setters(classes, macro __node);
		return macro @:pos(classes.pos) ashui.style.Style.of([(__node : ashui.layout.Node) -> $b{sets}]);
	}

	#if macro
	static var known:Null<Map<String, Expr->Array<Expr>>>;
	static var refused:Null<Array<{pattern:EReg, why:String}>>;

	/** One `node.set` per property the classes in `classes`, a string literal, give. **/
	public static function setters(classes:Expr, node:Expr):Array<Expr> {
		var text = switch classes.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("tw: classes must be a string literal, resolved at compile time", classes.pos);
		}
		var vocabulary = vocabulary();
		var out = [];
		var start = 0;
		for (word in ~/\s+/g.split(text)) {
			var offset = text.indexOf(word, start);
			start = offset + word.length;
			if (word == "")
				continue;
			var pos = within(classes.pos, offset, word.length);
			var make = vocabulary.get(word);
			if (make != null) {
				for (set in make(node))
					out.push({expr: set.expr, pos: pos});
				continue;
			}
			for (rule in refused)
				if (rule.pattern.match(word))
					Context.error('tw: $word: ${rule.why}', pos);
			var near = nearest(word, vocabulary);
			Context.error('tw: unknown class $word' + (near != null ? '; did you mean $near?' : ""), pos);
		}
		return out;
	}

	/** The part of a string literal at `pos` from `offset` for `length` characters. **/
	static function within(pos:Position, offset:Int, length:Int):Position {
		var p = Context.getPosInfos(pos);
		return Context.makePosition({file: p.file, min: p.min + 1 + offset, max: p.min + 1 + offset + length});
	}

	static function vocabulary():Map<String, Expr->Array<Expr>> {
		if (known != null)
			return known;
		var v = new Map<String, Expr->Array<Expr>>();
		inline function set(node:Expr, key:String, value:Expr):Expr
			return macro $node.set(ashui.layout.Prop.$key, $value);
		function one(name:String, key:String, value:Expr)
			v.set(name, node -> [set(node, key, value)]);

		// Spacing, from SpacingToken: Space0_5 is "0.5".
		for (token in tokenNames("ashui.theme.SpacingToken")) {
			var step = token.substr("Space".length).split("_").join(".");
			var value = macro ashui.theme.Themed.spacing(ashui.theme.SpacingToken.$token);
			for (entry in [
				["p", "Padding"], ["m", "Margin"], ["gap", "Gap"], ["w", "Width"], ["h", "Height"], ["min-w", "MinWidth"],
				["max-w", "MaxWidth"], ["min-h", "MinHeight"], ["max-h", "MaxHeight"], ["top", "Top"], ["right", "Right"],
				["bottom", "Bottom"], ["left", "Left"]
			])
				one('${entry[0]}-$step', entry[1], value);
			v.set('size-$step', node -> [set(node, "Width", value), set(node, "Height", value)]);
			v.set('inset-$step', node -> [for (k in ["Top", "Right", "Bottom", "Left"]) set(node, k, value)]);
		}

		// Colours, from ColorToken, named as their CSS variables: tooltipBg is "tooltip-bg".
		for (token in tokenNames("ashui.theme.ColorToken")) {
			var name = kebab(tokenValue("ashui.theme.ColorToken", token));
			one('bg-$name', "Background", macro ashui.theme.Themed.brush(ashui.theme.ColorToken.$token));
			one('text-$name', "Color", macro ashui.theme.Themed.color(ashui.theme.ColorToken.$token));
			one('border-$name', "BorderColor", macro ashui.theme.Themed.color(ashui.theme.ColorToken.$token));
		}

		// Corners, from RadiusToken: Default is bare `rounded`.
		for (token in tokenNames("ashui.theme.RadiusToken")) {
			var value = macro ashui.theme.Themed.radius(ashui.theme.RadiusToken.$token);
			one(token == "Default" ? "rounded" : 'rounded-${scale(token)}', "CornerRadius", value);
		}
		for (shape in ["round", "squircle", "bevel", "scoop", "notch", "square"])
			one('corner-$shape', "CornerShape", macro ashui.types.CornerShape.$shape());

		// Shadows, from ShadowToken: Default is bare `shadow`.
		for (token in tokenNames("ashui.theme.ShadowToken"))
			one(token == "Default" ? "shadow" : 'shadow-${scale(token)}', "Shadow", macro ashui.theme.Themed.shadow(ashui.theme.ShadowToken.$token));

		// Type, from TypographyToken: TextXs is text-xs, FontBold font-bold, LeadingSnug leading-snug.
		for (token in tokenNames("ashui.theme.TypographyToken")) {
			var value = macro ashui.theme.TypographyToken.$token;
			if (StringTools.startsWith(token, "Text"))
				one('text-${scale(token.substr(4))}', "FontSize", macro ashui.theme.Themed.fontSize($value));
			else if (StringTools.startsWith(token, "Font"))
				one('font-${token.substr(4).toLowerCase()}', "FontWeight", macro ashui.theme.Themed.fontWeight($value));
			else if (StringTools.startsWith(token, "Leading"))
				one('leading-${token.substr(7).toLowerCase()}', "LineHeight", macro ashui.theme.Themed.leading($value));
		}

		// Tailwind's keywords that no token stands behind.
		var style = macro ashui.types.Style;
		function keyword(name:String, key:String, type:String, value:String)
			one(name, key, macro $style.$type.$value);
		keyword("flex", "Display", "Display", "Flex");
		keyword("block", "Display", "Display", "Block");
		keyword("grid", "Display", "Display", "Grid");
		keyword("hidden", "Display", "Display", "None");
		keyword("flex-row", "FlexDirection", "FlexDirection", "Row");
		keyword("flex-row-reverse", "FlexDirection", "FlexDirection", "RowReverse");
		keyword("flex-col", "FlexDirection", "FlexDirection", "Column");
		keyword("flex-col-reverse", "FlexDirection", "FlexDirection", "ColumnReverse");
		keyword("flex-wrap", "FlexWrap", "FlexWrap", "Wrap");
		keyword("flex-wrap-reverse", "FlexWrap", "FlexWrap", "WrapReverse");
		keyword("flex-nowrap", "FlexWrap", "FlexWrap", "NoWrap");
		for (entry in [["start", "Start"], ["end", "End"], ["center", "Center"], ["baseline", "Baseline"], ["stretch", "Stretch"]]) {
			keyword('items-${entry[0]}', "AlignItems", "Align", entry[1]);
			keyword('self-${entry[0]}', "AlignSelf", "Align", entry[1]);
		}
		for (entry in [
			["start", "Start"], ["end", "End"], ["center", "Center"], ["stretch", "Stretch"], ["between", "SpaceBetween"],
			["around", "SpaceAround"], ["evenly", "SpaceEvenly"]
		])
			keyword('justify-${entry[0]}', "JustifyContent", "Justify", entry[1]);
		for (entry in [["visible", "Visible"], ["hidden", "Hidden"], ["clip", "Clip"], ["scroll", "Scroll"]])
			keyword('overflow-${entry[0]}', "Overflow", "Overflow", entry[1]);
		keyword("relative", "Position", "Position", "Relative");
		keyword("absolute", "Position", "Position", "Absolute");
		for (entry in [["left", "Left"], ["center", "Center"], ["right", "Right"]])
			keyword('text-${entry[0]}', "TextAlign", "TextAlign", entry[1]);
		keyword("italic", "FontStyle", "FontStyle", "Italic");
		keyword("not-italic", "FontStyle", "FontStyle", "Normal");
		function float(name:String, key:String, value:Float)
			one(name, key, macro($v{value} : Single));
		float("grow", "FlexGrow", 1);
		float("grow-0", "FlexGrow", 0);
		float("shrink", "FlexShrink", 1);
		float("shrink-0", "FlexShrink", 0);
		v.set("flex-1", node -> [
			set(node, "FlexGrow", macro(1 : Single)),
			set(node, "FlexShrink", macro(1 : Single)),
			set(node, "FlexBasis", macro(0 : Single))
		]);
		v.set("flex-auto", node -> [set(node, "FlexGrow", macro(1 : Single)), set(node, "FlexShrink", macro(1 : Single))]);
		v.set("flex-none", node -> [set(node, "FlexGrow", macro(0 : Single)), set(node, "FlexShrink", macro(0 : Single))]);
		float("border", "BorderWidth", 1);
		for (width in [0, 2, 4, 8])
			float('border-$width', "BorderWidth", width);
		for (percent in 0...21)
			float('opacity-${percent * 5}', "Opacity", percent * 5 / 100);

		refused = [
			{pattern: ~/^(hover|focus|active|disabled|dark|group-hover|focus-visible):/, why: "state variants need input events (e532fc0)"},
			{pattern: ~/^(p[xytrbl]|m[xytrbl]|gap-[xy])-/, why: "per-side spacing has no property to bind to yet"},
			{pattern: ~/^-/, why: "negative values have no token"},
			{pattern: ~/^(w|h|min-w|max-w|min-h|max-h|size)-(full|screen|auto|\d+\/\d+)$/, why: "relative sizes are not bound yet"},
			{pattern: ~/^tracking-/, why: "letter spacing in ems needs the font size, which is not bound yet"},
			{pattern: ~/^(duration|ease|transition|animate)/, why: "transitions need a motion system (b2fbc73)"},
			{pattern: ~/\[.*\]/, why: "arbitrary values are not supported; use a token or an attribute"}
		];
		known = v;
		return v;
	}

	/** The values of the enum abstract `path`, by name, in declaration order. **/
	static function tokenNames(path:String):Array<String> {
		return switch Context.getType(path) {
			case TAbstract(a, _):
				var impl = a.get().impl.get();
				var self = a.get().pack.concat([a.get().name]).join(".");
				// The values are the fields typed as the enum itself, not lists of them such as `ALL`.
				var fields = [
					for (f in impl.statics.get())
						if ((f.meta.has(":enum") || f.meta.has(":value")) && haxe.macro.TypeTools.toString(f.type) == self) f
				];
				fields.sort((x, y) -> Context.getPosInfos(x.pos).min - Context.getPosInfos(y.pos).min);
				[for (f in fields) f.name];
			case _: Context.error('tw: $path is not a token enum', Context.currentPos());
		}
	}

	/** A string enum abstract's value for `name`. **/
	static function tokenValue(path:String, name:String):String {
		switch Context.getType(path) {
			case TAbstract(a, _):
				for (f in a.get().impl.get().statics.get())
					if (f.name == name)
						switch f.expr() {
							case {expr: TCast({expr: TConst(TString(s))}, _)} | {expr: TConst(TString(s))}: return s;
							case _:
						}
			case _:
		}
		return Context.error('tw: no value for $path.$name', Context.currentPos());
	}

	/** A scale step as Tailwind writes it: Xxl is 2xl, Xxxl 3xl, Sm sm. **/
	static function scale(name:String):String {
		var lower = name.toLowerCase();
		var xs = ~/^(x+)l$/;
		return xs.match(lower) && xs.matched(1).length > 1 ? '${xs.matched(1).length}xl' : lower;
	}

	/** `surfaceElevated` as a class: `surface-elevated`. **/
	static function kebab(name:String):String {
		return ~/([a-z0-9])([A-Z])/g.replace(name, "$1-$2").toLowerCase();
	}

	/** The known class closest to `word` by edit distance, if one is close. **/
	static function nearest(word:String, vocabulary:Map<String, Dynamic>):Null<String> {
		var best:Null<String> = null;
		var bestDistance = 4;
		for (name in vocabulary.keys()) {
			var d = distance(word, name);
			if (d < bestDistance || (d == bestDistance && best != null && name < best)) {
				best = name;
				bestDistance = d;
			}
		}
		return best;
	}

	static function distance(a:String, b:String):Int {
		var previous = [for (j in 0...b.length + 1) j];
		for (i in 1...a.length + 1) {
			var row = [i];
			for (j in 1...b.length + 1)
				row.push(Std.int(Math.min(Math.min(row[j - 1] + 1, previous[j] + 1), previous[j - 1] + (a.charAt(i - 1) == b.charAt(j - 1) ? 0 : 1))));
			previous = row;
		}
		return previous[b.length];
	}
	#end
}
