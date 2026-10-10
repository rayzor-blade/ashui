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
	  `left-`, `inset-` with `0`, `0.5`, `1` … `32`; one side with `pt-`,
	  `pr-`, `pb-`, `pl-`, two with `px-`, `py-`, the same for `m`, and
	  `gap-x-`, `gap-y-`;
	- `auto` margins, sizes and insets (`mx-auto`, `w-auto`), and fractions of
	  the parent (`w-full`, `w-1/2`, `h-2/3`, `basis-1/4` …);
	- colours, `ColorToken` by its CSS variable name, and `white`, `black`
	  and `transparent`: `bg-`, `text-`, `border-`, `outline-` and `ring-`
	  with `primary`, `surface-elevated`, `text-secondary` …, each at an
	  opacity with `/0` … `/100`, `bg-primary/50`, `border-white/40`;
	- a backdrop blur, `backdrop-blur-xs` … `backdrop-blur-3xl`
	  (`backdrop-blur` is `-sm`): what is behind the box blurred, under the
	  box's background colour, so `bg-white/30 backdrop-blur-md` is frosted
	  glass; and backdrop colour filters at Tailwind's scales,
	  `backdrop-brightness-`, `-contrast-`, `-saturate-`, `-hue-rotate-`,
	  `backdrop-grayscale`, `-invert`, `-sepia`, which filter what is behind
	  with or without a blur;
	- liquid glass, `bg-glass`, with `glass-blur-2` (pixels),
	  `glass-tint-white/20` (fixed or theme colours), `glass-aberration-30`
	  and `glass-noise-3` (percent), `glass-bevel-35`, `glass-inset` or
	  `glass-outset`, and `glass-frosted` or `glass-liquid`.
	  These declare CSS's `background: glass` and `glass-*` settings, so
	  variables, stylesheets and state variants use the same brush. Defaults:
	  12px blur, white/10 tint, 30% aberration, no noise, liquid mode;
	- borders, `border`, `border-0` … `border-8`, and one side or two over
	  it, `border-t`, `border-x-2`, `border-b-0` …, each side in the
	  border's colour or its own, `border-t-primary`, `border-x-error` …;
	- overflow fades, ashui's own: on a box that clips its children
	  (`overflow-hidden`, `overflow-y-auto` …), `fade-4` fades them out
	  over the spacing step in from every edge, `fade-y-8` from the top and
	  bottom, `fade-t-2` from one side;
	- colour filters over the element and everything inside it, drawn as
	  one layer: `grayscale`, `sepia`, `invert` (and `-0`), `brightness-50`
	  … `brightness-200`, `contrast-50` … `contrast-200`, `saturate-0` …
	  `saturate-200`, `hue-rotate-15` … `hue-rotate-180` and their minus;
	  and `blur-xs` … `blur-3xl` (`blur` is `blur-sm`), Tailwind 4's scale;
	  `drop-shadow-xs` … `drop-shadow-2xl`, a shadow cast by what is drawn,
	  its shape and its children, rather than by the box;
	  `opacity-` over more than one painted element fades them as a group;
	- clip paths, Tailwind's arbitrary property `[clip-path:…]` with any
	  CSS shape, underscores for spaces: `[clip-path:circle()]`,
	  `[clip-path:inset(8px_round_16px)]`,
	  `[clip-path:polygon(50%_0,100%_100%,0_100%)]`, `[clip-path:none]`;
	  checked at compile time (see `ashui.types.ClipPath`);
	- outlines, a ring outside the border box that follows its corners:
	  `outline`, `outline-2`, `outline-offset-2`, `outline-none`, and
	  Tailwind's rings drawn the same way, `ring` (3), `ring-2`,
	  `ring-offset-2`; the gap of an offset is left clear;
	- corners, `RadiusToken`: `rounded`, `rounded-sm` … `rounded-3xl`,
	  `rounded-full`, and the shapes `corner-squircle`, `corner-bevel`,
	  `corner-scoop`, `corner-notch`, `corner-square`, `corner-round`;
	- shadows, `ShadowToken`: `shadow`, `shadow-sm` … `shadow-2xl`,
	  `shadow-inner`, `shadow-none`;
	- type, `TypographyToken`: `text-xs` … `text-5xl`, `font-thin` …
	  `font-black`, `leading-none` … `leading-loose`, `tracking-tighter` …
	  `tracking-wider` (in ems of the element's font size). These, `text-left`
	  … `text-justify`, `italic` and the `text-` colours are the element's
	  own CSS declarations, so the text it holds inherits them, as in
	  Tailwind;
	- transitions, composed into one `ashui.animation.Transition`:
	  `transition` (colours, opacity, shadow, transform), `transition-colors`,
	  `-opacity`, `-shadow`, `-transform`, `-all`, `-none`; `duration-fastest`
	  … `duration-slowest` from `AnimationToken`, or Tailwind's
	  `duration-150` and so on in milliseconds; `ease-default`, `ease-in`,
	  `ease-out`, `ease-in-out`, `ease-state`, `ease-nav`, `ease-spring`,
	  `ease-sheet` from the theme's curves, and `ease-linear`; `delay-150`
	  and the like. Without a duration or curve the theme's fast duration
	  and default curve apply;
	- transforms, composed into one `Transform` about the element's centre:
	  `translate-x-` and `translate-y-` over the spacing steps, `rotate-`
	  (degrees: 0, 1, 2, 3, 6, 12, 45, 90, 180), `scale-`, `scale-x-`,
	  `scale-y-` (percent: 0, 50, 75, 90, 95, 100, 105, 110, 125, 150),
	  `skew-x-`, `skew-y-` (degrees: 0, 1, 2, 3, 6, 12), a minus sign before
	  translate, rotate and skew; and the state variants below on any of them;
	- Tailwind's looping animations `animate-spin`, `animate-ping`,
	  `animate-pulse`, `animate-bounce`, which replace the transform as CSS
	  animations do;
	- gradients over the colours: a direction, `bg-linear-to-r` (or
	  Tailwind 3's `bg-gradient-to-r`) for each side and corner or
	  `bg-radial`, with `from-`, `via-` and `to-` stops and positions such
	  as `via-30%`. Where Tailwind composes these in the browser through CSS
	  variables, they are composed here at compile time into one fill.

	`hover:`, `focus:`, `focus-visible:`, `active:`, `disabled:` and `dark:`
	before a class apply it while the pointer is over the element, while it
	has focus, while it has focus the keyboard gave it, while it is pressed,
	while it is disabled, or in the dark scheme (see `ashui.input`).
	`focus-within:` applies it while the element or anything inside it has
	focus. `group-hover:` applies it while the nearest ancestor with the
	class `group` is hovered, and `peer-hover:` while the nearest earlier
	sibling with the class `peer` is; both take `focus`, `focus-visible`,
	`focus-within`, `active` and `disabled` too. Where several hold, the
	later wins, in Tailwind's order: `dark`, `group-`, `peer-`,
	`focus-within`, `hover`, `focus`, `focus-visible`, `active`,
	`disabled`. The string needs the plain class for the same property
	too, the value otherwise. With `transition-colors` the change animates.

	A class bound to a token follows the theme: a scheme switch or an
	override updates it, and nothing is rebuilt. Layout keywords with no
	token are Tailwind's: `flex`, `flex-col`, `items-center`,
	`justify-between`, `grow`, `shrink-0`, `overflow-hidden`, `absolute`,
	scroll containers `overflow-auto`, `overflow-scroll` and their `-x-`/`-y-`
	forms (see `ashui.input.Scroll`),
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
	// The sides a spacing class names, and the properties' suffixes for them.
	static final SIDES = [
		{name: "t", keys: ["Top"]}, {name: "r", keys: ["Right"]}, {name: "b", keys: ["Bottom"]}, {name: "l", keys: ["Left"]},
		{name: "x", keys: ["Left", "Right"]}, {name: "y", keys: ["Top", "Bottom"]}
	];
	static var refused:Null<Array<{pattern:EReg, why:String}>>;
	/** Colour class names to `ColorToken` names: `surface-elevated` is `SurfaceElevated`. **/
	@:allow(ashui.style.Gradient) static var colors:Map<String, String>;

	/** One `node.set` per property the classes in `classes`, a string literal, give. **/
	public static function setters(classes:Expr, node:Expr, ?cssClasses:Array<String>):Array<Expr> {
		var text = switch classes.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("tw: classes must be a string literal, resolved at compile time", classes.pos);
		}
		var vocabulary = vocabulary();
		var out = [];
		var gradient = new Gradient();
		var motion = new Motion();
		var transform = new TransformClasses();
		// hover:, active: and dark: classes, by property, then by variant.
		var variants = new Map<String, Map<String, {value:Expr, pos:Position}>>();
		var variant = VARIANT;
		// A backdrop blur and the background colour class it is painted under, merged after the loop.
		var backdrop:Null<{radius:Float, pos:Position}> = null;
		// Where the first backdrop colour filter class is, which needs a backdrop even with no blur class.
		var backdropColor:Null<Position> = null;
		var background:Null<{name:String, alpha:Float}> = null;
		var bgColor = ~/^bg-([a-z0-9-]+?)(?:\/(\d{1,3}))?$/;
		var start = 0;
		for (word in ~/\s+/g.split(text)) {
			var offset = text.indexOf(word, start);
			start = offset + word.length;
			if (word == "")
				continue;
			var pos = within(classes.pos, offset, word.length);
			if (transform.take(word, pos))
				continue;
			if (variant.match(word)) {
				var state = variant.matched(1), rest = variant.matched(2);
				if (variant.match(rest))
					Context.error('tw: $word: one variant per class', pos);
				var make = lookup(vocabulary, rest, pos);
				if (make == null && ashui.css.DeclaredCss.has(rest))
					Context.error('tw: $word: a variant takes Tw classes; for a CSS class, write .$rest:$state in the stylesheet', pos);
				if (make == null)
					Context.error('tw: $word: $rest is not a class a variant can take', pos);
				for (set in make(node))
					switch keyValue(set) {
						case null:
						case kv:
							if (!variants.exists(kv.key))
								variants.set(kv.key, new Map());
							variants.get(kv.key).set(state, {value: kv.value, pos: pos});
					}
				continue;
			}
			if (gradient.take(word, pos) || motion.take(word, pos))
				continue;
			var radius = BACKDROP_BLUR.get(word);
			if (radius != null) {
				backdrop = {radius: radius, pos: pos};
				continue;
			}
			// A backdrop colour filter: what is behind filtered, unblurred unless a backdrop-blur class blurs it too.
			var filter = BACKDROP_COLORS.get(word);
			if (filter != null) {
				var key = filter.prop, value = filter.value;
				out.push(macro @:pos(pos) $node.set(ashui.layout.Prop.$key, ($v{value} : Single)));
				if (backdropColor == null)
					backdropColor = pos;
				continue;
			}
			if (bgColor.match(word) && (colors.exists(bgColor.matched(1)) || fixedColor(bgColor.matched(1)) != null)) {
				var percent = bgColor.matched(2);
				background = {name: bgColor.matched(1), alpha: percent == null ? 1.0 : Std.parseInt(percent) / 100};
			}
			// A class of an inherited text property is the element's own declaration, which what it holds inherits, as in Tailwind.
			var declared = inheritedCss(word);
			if (declared != null) {
				var name = declared.name, value = declared.value;
				out.push(macro @:pos(pos) ashui.css.Identity.declare($node, $v{name}, $v{value}));
				continue;
			}
			var make = lookup(vocabulary, word, pos);
			if (make != null) {
				for (set in make(node))
					out.push({expr: set.expr, pos: pos});
				continue;
			}
			// Not Tw's: a class of the CSS the build declares, for the element's identity.
			if (ashui.css.DeclaredCss.has(word)) {
				if (cssClasses == null)
					Context.error('tw: $word is a CSS class, which goes in an element\'s class=, not in a style', pos);
				if (cssClasses.indexOf(word) < 0)
					cssClasses.push(word);
				continue;
			}
			for (rule in refused)
				if (rule.pattern.match(word))
					Context.error('tw: $word: ${rule.why}', pos);
			var candidates:Map<String, Dynamic> = [for (k in vocabulary.keys()) k => true];
			for (k in ashui.css.DeclaredCss.classes().keys())
				candidates.set(k, true);
			var near = nearest(word, candidates);
			Context.error('tw: unknown class $word' + (near != null ? '; did you mean $near?' : "")
				+ (Context.definedValue("ashui_css") == null ? "" : ", or a class of the CSS in -D ashui_css"), pos);
		}
		if (backdrop == null && backdropColor != null)
			backdrop = {radius: 0.0, pos: backdropColor};
		var glassBackground = Lambda.exists(out, e -> {
			var kv = keyValue(e);
			kv != null && kv.key == "css:background" && switch kv.value.expr {
				case EConst(CString("glass", _)): true;
				case _: false;
			};
		});
		if (glassBackground && backdrop != null) {
			// Keep the glass brush when a backdrop blur or colour filter accompanies it.
			if (backdropColor == null || backdrop.radius != 0) {
				var value = 'blur(${backdrop.radius}px)';
				out.push(macro ashui.css.Identity.declare($node, "backdrop-filter", $v{value}));
			}
		} else if (backdrop != null) {
			if (variants.exists("Background"))
				Context.error("tw: a state variant of the background would replace the backdrop blur; vary something else", backdrop.pos);
			var set = Lambda.find(out, e -> {
				var kv = keyValue(e);
				kv != null && kv.key == "Background";
			});
			if (set != null && background == null)
				Context.error("tw: backdrop-blur paints a background colour over the blur, not a gradient or an image", backdrop.pos);
			out.remove(set);
			var r = backdrop.radius;
			var fixed = background == null ? null : fixedColor(background.name);
			var brush = if (background == null) {
				macro ashui.types.Brush.blur($v{r});
			} else if (fixed != null) {
				macro ashui.types.Brush.blur($v{r}, $v{fixed.hex}, $v{fixed.alpha * background.alpha});
			} else {
				var token = colors.get(background.name);
				macro ashui.theme.Themed.blur($v{r}, ashui.theme.ColorToken.$token, $v{background.alpha});
			}
			out.push({expr: (macro $node.set(ashui.layout.Prop.Background, $brush)).expr, pos: backdrop.pos});
		}
		var moved = transform.build(node);
		if (moved != null) {
			out.push(moved.base);
			for (state => value in moved.states) {
				if (!variants.exists("Transform"))
					variants.set("Transform", new Map());
				variants.get("Transform").set(state, value);
			}
		}

		// Each property a variant sets becomes one value that follows the pointer and the scheme:
		// active over hover over dark over the base class of the same property.
		var interaction = false, grouped = false, peered = false;
		for (key => states in variants) {
			var base:Null<Expr> = null;
			var at:Null<Position> = null;
			for (set in out)
				switch keyValue(set) {
					case null:
					case kv if (kv.key == key):
						base = kv.value;
						at = set.pos;
					case _:
				}
			if (base == null) {
				var any = states.iterator().next();
				Context.error('tw: a variant needs a class for the same property without one, such as bg-surface beside hover:bg-primary', any.pos);
			}
			out = [
				for (set in out) {
					var kv = keyValue(set);
					if (kv == null || kv.key != key) set;
				}
			];
			var lets = [macro var __base = $base];
			var reactive = new Map<String, Bool>();
			// A signal's or computed's value is read; a constant is used as it is.
			function mark(name:String, value:Expr) {
				var type = try haxe.macro.TypeTools.toString(Context.typeof(value)) catch (_:Dynamic) "";
				reactive.set(name, StringTools.startsWith(type, "ashui.reactive.Computed") || StringTools.startsWith(type, "ashui.reactive.Signal"));
			}
			function read(name:String):Expr
				return reactive.get(name) ? macro $i{name}.get() : macro $i{name};
			mark("__base", base);
			var pick = read("__base");
			// Later wins, in Tailwind's order.
			for (state in STATES) {
				var v = states.get(state);
				if (v == null)
					continue;
				var name = '__' + StringTools.replace(state, "-", "_");
				lets.push(macro var $name = ${v.value});
				mark(name, v.value);
				var test = if (state == "dark") {
					macro ashui.style.Variant.dark();
				} else if (StringTools.startsWith(state, "group-") || StringTools.startsWith(state, "peer-")) {
					var group = StringTools.startsWith(state, "group-");
					var other = group ? "__group" : "__peer";
					if (group)
						grouped = true;
					else
						peered = true;
					var field = signalOf(state.substr(group ? 6 : 5));
					macro {
						var __other = $i{other}.get();
						__other != null && __other.$field.get();
					}
				} else {
					interaction = true;
					var field = signalOf(state);
					macro __interaction.$field.get();
				}
				pick = macro $test ? ${read(name)} : $pick;
			}
			// One block: the values are made before the computed that reads them, not inside it.
			var apply = if (StringTools.startsWith(key, "css:")) {
				var name = key.substr(4);
				macro new ashui.reactive.Watch(() -> $pick, value -> ashui.css.Identity.declare($node, $v{name}, value));
			} else {
				macro $node.set(ashui.layout.Prop.$key, ashui.reactive.Computed.make(() -> $pick));
			}
			out.push({
				expr: EBlock(lets.concat([apply])),
				pos: at
			});
		}
		if (interaction)
			out.unshift(macro var __interaction = ashui.input.Interaction.of($node));
		if (grouped)
			out.unshift(macro var __group = ashui.input.Relations.groupOf($node));
		if (peered)
			out.unshift(macro var __peer = ashui.input.Relations.peerOf($node));
		var background = gradient.build(node);
		if (background != null)
			out.push(background);
		// The transition goes first: it covers the properties set after it.
		var transition = motion.build(node);
		if (transition != null)
			out.unshift(transition);
		return out;
	}

	/** The property and value of a `node.set(Prop.Key, value)`, or null for anything else. **/
	/**
		The class `word` names: a vocabulary entry, or Tailwind's arbitrary
		property `[clip-path:…]`, its underscores spaces, read now so a
		malformed one is a compile error at `pos`; null if neither.
	**/
	static function lookup(vocabulary:Map<String, Expr->Array<Expr>>, word:String, pos:Position):Null<Expr->Array<Expr>> {
		var glass = glassCss(word, pos);
		if (glass != null) {
			var name = glass.name, value = glass.value;
			return node -> [macro ashui.css.Identity.declare($node, $v{name}, $v{value})];
		}
		var known = vocabulary.get(word);
		if (known != null)
			return known;
		// A colour class with an opacity, `bg-primary/50`: its alpha times 0.5.
		var faded = ~/^(.+)\/(\d{1,3})$/;
		if (faded.match(word)) {
			var percent = Std.parseInt(faded.matched(2));
			var base = faded.matched(1);
			for (target in COLOR_TARGETS) {
				if (!StringTools.startsWith(base, target.prefix + "-"))
					continue;
				var name = base.substr(target.prefix.length + 1);
				if (fixedColor(name) == null && !colors.exists(name))
					continue;
				if (percent > 100)
					Context.error('tw: $word: an opacity is 0 to 100', pos);
				return colorSetter(target, name, percent / 100);
			}
			return null;
		}
		var arbitrary = ~/^\[clip-path:(.+)\]$/;
		if (!arbitrary.match(word))
			return null;
		var css = StringTools.replace(arbitrary.matched(1), "_", " ");
		var shape = try ashui.types.ClipPathCss.parse(css) catch (e:String) Context.error('tw: $word: $e', pos);
		var made = clipExpr(shape, pos);
		return node -> [macro $node.set(ashui.layout.Prop.ClipPath, $made)];
	}

	/** The expression making the clip path `shape` describes. **/
	static function clipExpr(shape:ashui.types.ClipPathCss.ClipShape, pos:Position):Expr {
		function len(l:Null<ashui.types.ClipLength>):Expr {
			return switch l {
				case null: macro null;
				case Px(v): macro ashui.types.ClipLength.Px($v{v});
				case Percent(v): macro ashui.types.ClipLength.Percent($v{v});
			}
		}
		return switch shape {
			case NoClip: macro ashui.types.ClipPath.none();
			case Circle(r, x, y): macro ashui.types.ClipPath.circle(${len(r)}, ${len(x)}, ${len(y)});
			case Ellipse(rx, ry, x, y): macro ashui.types.ClipPath.ellipse(${len(rx)}, ${len(ry)}, ${len(x)}, ${len(y)});
			case Inset(t, r, b, l, round): macro ashui.types.ClipPath.inset(${len(t)}, ${len(r)}, ${len(b)}, ${len(l)}, $v{round});
			case Rect(t, r, b, l, round): macro ashui.types.ClipPath.rect(${len(t)}, ${len(r)}, ${len(b)}, ${len(l)}, $v{round});
			case Xywh(x, y, w, h, round): macro ashui.types.ClipPath.xywh(${len(x)}, ${len(y)}, ${len(w)}, ${len(h)}, $v{round});
			case Polygon(points):
				var items = [for (p in points) macro {x: ${len(p.x)}, y: ${len(p.y)}}];
				macro ashui.types.ClipPath.polygon([$a{items}]);
			case Path(d):
				// Checked now, so a mistake in the path data is a compile error too.
				try ashui.svg.PathData.parse(d) catch (e:haxe.Exception) Context.error('tw: path data: ${e.message}', pos);
				macro ashui.types.ClipPath.path($v{d});
			case EvenOdd(inner):
				var made = clipExpr(inner, pos);
				macro $made.evenOdd();
		}
	}

	/** The state variants, in Tailwind's order: a later one wins over an earlier. **/
	static final OWN = ["hover", "focus", "focus-visible", "active", "disabled"];

	static final RELATED = ["hover", "focus", "focus-visible", "focus-within", "active", "disabled"];

	@:noCompletion public static final STATES = ["dark"].concat([for (s in RELATED) 'group-$s']).concat([for (s in RELATED) 'peer-$s']).concat(["focus-within"]).concat(OWN);

	@:noCompletion public static final VARIANT = new EReg('^(' + [for (s in STATES) StringTools.replace(s, "-", "\\-")].join("|") + '):(.+)$$', "");

	/** The `Interaction` signal a state reads. **/
	static function signalOf(state:String):String {
		return switch state {
			case "hover": "hovered";
			case "focus": "focused";
			case "focus-visible": "focusVisible";
			case "focus-within": "focusWithin";
			case "disabled": "disabled";
			case _: "pressed";
		}
	}

	static function keyValue(e:Expr):Null<{key:String, value:Expr}> {
		return switch e.expr {
			case ECall({expr: EField(_, "set", _)}, [{expr: EField(_, key, _)}, value]): {key: key, value: value};
			case ECall({expr: EField(_, "declare", _)}, [_, {expr: EConst(CString(name, _))}, value]): {key: 'css:$name', value: value};
			case _: null;
		}
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
			// One side, or two: px- is left and right, py- top and bottom.
			for (box in [["p", "Padding"], ["m", "Margin"]])
				for (side in SIDES)
					v.set('${box[0]}${side.name}-$step', node -> [for (k in side.keys) set(node, box[1] + k, value)]);
			one('gap-x-$step', "GapX", value);
			one('gap-y-$step', "GapY", value);
			// ashui's own: what a clipping box clips fades out over this far in from its edges.
			v.set('fade-$step', node -> [for (k in ["Top", "Right", "Bottom", "Left"]) set(node, "Fade" + k, value)]);
			for (side in SIDES)
				v.set('fade-${side.name}-$step', node -> [for (k in side.keys) set(node, "Fade" + k, value)]);
		}

		// Auto margins, sizes and insets: NaN is `auto` to the layout.
		var auto = macro(Math.NaN : Single);
		one("m-auto", "Margin", auto);
		for (side in SIDES)
			v.set('m${side.name}-auto', node -> [for (k in side.keys) set(node, "Margin" + k, auto)]);
		for (entry in [["w", "Width"], ["h", "Height"], ["basis", "FlexBasis"], ["top", "Top"], ["right", "Right"], ["bottom", "Bottom"], ["left", "Left"]])
			one('${entry[0]}-auto', entry[1], auto);
		v.set("size-auto", node -> [set(node, "Width", auto), set(node, "Height", auto)]);
		v.set("inset-auto", node -> [for (k in ["Top", "Right", "Bottom", "Left"]) set(node, k, auto)]);

		// Fractions of the parent, as Tailwind spells them.
		var fractions:Array<{name:String, value:Float}> = [{name: "full", value: 1.0}];
		for (d in [2, 3, 4, 5, 6, 12])
			for (n in 1...d)
				fractions.push({name: '$n/$d', value: n / d});
		for (f in fractions) {
			var name = f.name, value = macro($v{f.value} : Single);
			for (entry in [
				["w", "WidthPercent"], ["h", "HeightPercent"], ["min-w", "MinWidthPercent"], ["max-w", "MaxWidthPercent"],
				["min-h", "MinHeightPercent"], ["max-h", "MaxHeightPercent"], ["basis", "FlexBasisPercent"]
			])
				one('${entry[0]}-$name', entry[1], value);
			v.set('size-$name', node -> [set(node, "WidthPercent", value), set(node, "HeightPercent", value)]);
		}

		// Colours, from ColorToken, named as their CSS variables (tooltipBg is
		// "tooltip-bg"), and Tailwind's white, black and transparent.
		colors = new Map();
		for (token in tokenNames("ashui.theme.ColorToken"))
			colors.set(kebab(tokenValue("ashui.theme.ColorToken", token)), token);
		for (name in colorNames())
			for (target in COLOR_TARGETS) {
				var made = colorSetter(target, name, 1.0);
				v.set('${target.prefix}-$name', made);
			}
		// The glass utilities are CSS declarations, composed by the same background handler as a stylesheet.
		for (word in ["bg-glass", "glass-liquid", "glass-frosted", "glass-inset", "glass-outset"].concat([for (name in colorNames()) 'glass-tint-$name'])
			.concat([for (i in 0...101) 'glass-blur-$i']).concat([for (i in 0...101) 'glass-aberration-$i'])
			.concat([for (i in 0...101) 'glass-noise-$i']).concat([for (i in 0...101) 'glass-bevel-$i'])) {
			var declaration = glassCss(word, Context.currentPos());
			var name = declaration.name, value = declaration.value;
			v.set(word, node -> [macro ashui.css.Identity.declare($node, $v{name}, $v{value})]);
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
		for (entry in [["visible", "Visible"], ["hidden", "Hidden"], ["clip", "Clip"]])
			keyword('overflow-${entry[0]}', "Overflow", "Overflow", entry[1]);
		// Scroll containers: the content moves under the wheel or trackpad along the axes they name.
		for (entry in [
			{name: "auto", x: true, y: true}, {name: "scroll", x: true, y: true}, {name: "x-auto", x: true, y: false},
			{name: "y-auto", x: false, y: true}, {name: "x-scroll", x: true, y: false}, {name: "y-scroll", x: false, y: true}
		]) {
			var x = entry.x, y = entry.y;
			v.set('overflow-${entry.name}', node -> [
				set(node, "Overflow", macro $style.Overflow.Scroll),
				macro ashui.input.Scroll.attach($node, $v{x}, $v{y})
			]);
		}
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
		// An element whose state what is inside it, or its later siblings, can follow.
		v.set("group", node -> [macro ashui.input.Interaction.of($node).markGroup()]);
		v.set("peer", node -> [macro ashui.input.Interaction.of($node).markPeer()]);
		v.set("flex-auto", node -> [set(node, "FlexGrow", macro(1 : Single)), set(node, "FlexShrink", macro(1 : Single))]);
		v.set("flex-none", node -> [set(node, "FlexGrow", macro(0 : Single)), set(node, "FlexShrink", macro(0 : Single))]);
		float("border", "BorderWidth", 1);
		for (width in [0, 2, 4, 8])
			float('border-$width', "BorderWidth", width);
		// One side, or two: a side's width over the border's.
		var sideKeys = [
			"t" => ["BorderTopWidth"], "r" => ["BorderRightWidth"], "b" => ["BorderBottomWidth"], "l" => ["BorderLeftWidth"],
			"x" => ["BorderLeftWidth", "BorderRightWidth"], "y" => ["BorderTopWidth", "BorderBottomWidth"]
		];
		for (side => keys in sideKeys)
			for (width in [null, 0, 2, 4, 8]) {
				var w:Float = width == null ? 1 : width;
				v.set(width == null ? 'border-$side' : 'border-$side-$width', node -> [for (k in keys) set(node, k, macro($v{w} : Single))]);
			}
		// Outlines, and Tailwind's rings, drawn as an outline: a ring outside the border box.
		float("outline", "OutlineWidth", 1);
		float("outline-none", "OutlineWidth", 0);
		for (width in [0, 1, 2, 4, 8]) {
			float('outline-$width', "OutlineWidth", width);
			float('outline-offset-$width', "OutlineOffset", width);
			float('ring-$width', "OutlineWidth", width);
			float('ring-offset-$width', "OutlineOffset", width);
		}
		float("ring", "OutlineWidth", 3);
		// Tailwind's colour filters, at its scales.
		float("grayscale", "FilterGrayscale", 1);
		float("grayscale-0", "FilterGrayscale", 0);
		float("sepia", "FilterSepia", 1);
		float("sepia-0", "FilterSepia", 0);
		float("invert", "FilterInvert", 1);
		float("invert-0", "FilterInvert", 0);
		for (p in [0, 50, 75, 90, 95, 100, 105, 110, 125, 150, 200])
			float('brightness-$p', "FilterBrightness", p / 100);
		for (p in [0, 50, 75, 100, 125, 150, 200])
			float('contrast-$p', "FilterContrast", p / 100);
		for (p in [0, 50, 100, 150, 200])
			float('saturate-$p', "FilterSaturate", p / 100);
		// Tailwind 4's blur scale, in pixels.
		for (entry in [
			{name: "none", px: 0}, {name: "xs", px: 4}, {name: "sm", px: 8}, {name: "md", px: 12}, {name: "lg", px: 16}, {name: "xl", px: 24},
			{name: "2xl", px: 40}, {name: "3xl", px: 64}
		])
			float('blur-${entry.name}', "FilterBlur", entry.px);
		float("blur", "FilterBlur", 8);
		// Tailwind 4's drop shadows: offset y, blur radius, black's alpha.
		for (entry in [
			{name: "xs", y: 1, blur: 1, alpha: 0.05}, {name: "sm", y: 1, blur: 2, alpha: 0.15}, {name: "md", y: 3, blur: 3, alpha: 0.12},
			{name: "lg", y: 4, blur: 4, alpha: 0.15}, {name: "xl", y: 9, blur: 7, alpha: 0.1}, {name: "2xl", y: 25, blur: 25, alpha: 0.15}
		])
			one('drop-shadow-${entry.name}', "DropShadow", macro new ashui.types.Shadow(0, $v{entry.y}, $v{entry.blur}, 0x000000, $v{entry.alpha}));
		one("drop-shadow", "DropShadow", macro new ashui.types.Shadow(0, 1, 2, 0x000000, 0.15));
		one("drop-shadow-none", "DropShadow", macro new ashui.types.Shadow(0, 0, 0, 0x000000, 0));
		for (d in [0, 15, 30, 60, 90, 180]) {
			float('hue-rotate-$d', "FilterHueRotate", d);
			float('-hue-rotate-$d', "FilterHueRotate", -d);
		}
		for (percent in 0...21)
			float('opacity-${percent * 5}', "Opacity", percent * 5 / 100);

		refused = [
			{pattern: ~/^-/, why: "only translate, rotate, skew and hue-rotate take a minus sign"},
			{pattern: ~/^backdrop-opacity/, why: "backdrop-opacity is not drawn; tint the background with bg-*/opacity instead"},
			{pattern: ~/^-?translate-[xy]-(full|\d+\/\d+)$/, why: "translating by a fraction of the element's own size is not bound yet"},
			{pattern: ~/-(screen|svh|dvh|lvh|min|max|fit)$/, why: "sizes relative to the window or the content are not bound; size a full-window root with w-full and h-full"},
			{pattern: ~/^animate-/, why: "the animations are animate-spin, animate-ping, animate-pulse, animate-bounce and animate-none"},
			{pattern: ~/\[.*\]/, why: "arbitrary values are supported for [clip-path:…] and [glass-*:…]; use a token or an attribute otherwise"}
		];
		known = v;
		return v;
	}

	/** Tailwind's backdrop colour filters, at its scales: the backdrop property each sets, and the value. **/
	static final BACKDROP_COLORS:Map<String, {prop:String, value:Float}> = {
		var m = new Map<String, {prop:String, value:Float}>();
		m.set("backdrop-grayscale", {prop: "BackdropGrayscale", value: 1});
		m.set("backdrop-grayscale-0", {prop: "BackdropGrayscale", value: 0});
		m.set("backdrop-sepia", {prop: "BackdropSepia", value: 1});
		m.set("backdrop-sepia-0", {prop: "BackdropSepia", value: 0});
		m.set("backdrop-invert", {prop: "BackdropInvert", value: 1});
		m.set("backdrop-invert-0", {prop: "BackdropInvert", value: 0});
		for (p in [0, 50, 75, 90, 95, 100, 105, 110, 125, 150, 200])
			m.set('backdrop-brightness-$p', {prop: "BackdropBrightness", value: p / 100});
		for (p in [0, 50, 75, 100, 125, 150, 200])
			m.set('backdrop-contrast-$p', {prop: "BackdropContrast", value: p / 100});
		for (p in [0, 50, 100, 150, 200])
			m.set('backdrop-saturate-$p', {prop: "BackdropSaturate", value: p / 100});
		for (d in [0, 15, 30, 60, 90, 180]) {
			m.set('backdrop-hue-rotate-$d', {prop: "BackdropHueRotate", value: d});
			m.set('-backdrop-hue-rotate-$d', {prop: "BackdropHueRotate", value: -d});
		}
		m;
	};

	/** Tailwind's backdrop blur sizes, in pixels of deviation. **/
	static final BACKDROP_BLUR:Map<String, Float> = [
		"backdrop-blur-none" => 0.0, "backdrop-blur-xs" => 4.0, "backdrop-blur-sm" => 8.0, "backdrop-blur" => 8.0, "backdrop-blur-md" => 12.0,
		"backdrop-blur-lg" => 16.0, "backdrop-blur-xl" => 24.0, "backdrop-blur-2xl" => 40.0, "backdrop-blur-3xl" => 64.0
	];

	/** What colour classes set: `bg-` a brush, the rest a colour, to each of `props`. **/
	static final COLOR_TARGETS:Array<{prefix:String, props:Array<String>, brush:Bool}> = [
		{prefix: "bg", props: ["Background"], brush: true},
		{prefix: "text", props: ["Color"], brush: false},
		{prefix: "border", props: ["BorderColor"], brush: false},
		{prefix: "border-t", props: ["BorderTopColor"], brush: false},
		{prefix: "border-r", props: ["BorderRightColor"], brush: false},
		{prefix: "border-b", props: ["BorderBottomColor"], brush: false},
		{prefix: "border-l", props: ["BorderLeftColor"], brush: false},
		{prefix: "border-x", props: ["BorderLeftColor", "BorderRightColor"], brush: false},
		{prefix: "border-y", props: ["BorderTopColor", "BorderBottomColor"], brush: false},
		{prefix: "outline", props: ["OutlineColor"], brush: false},
		{prefix: "ring", props: ["OutlineColor"], brush: false},
	];

	/** The colour tokens' class names, then Tailwind's fixed colours. **/
	static function colorNames():Array<String> {
		var names = [for (name in colors.keys()) name];
		names.sort(Reflect.compare);
		return names.concat(["white", "black", "transparent"]);
	}

	/** Tailwind's colours that no theme changes: `0xRRGGBB` and alpha. **/
	/**
		`word` as the CSS declaration of the inherited text property it sets,
		over the theme's variables: `text-xl` is `font-size: var(--text-xl)`,
		`text-muted/70` a mix of `--muted` at 70%. Null for any other class.
	**/
	static function inheritedCss(word:String):Null<{name:String, value:String}> {
		var size = ~/^text-(xs|sm|base|lg|xl|[2-9]xl)$/;
		if (size.match(word))
			return {name: "font-size", value: 'var(--text-${size.matched(1)})'};
		var align = ~/^text-(left|center|right|justify)$/;
		if (align.match(word))
			return {name: "text-align", value: align.matched(1)};
		if (word == "italic" || word == "not-italic")
			return {name: "font-style", value: word == "italic" ? "italic" : "normal"};
		var font = ~/^font-([a-z]+)$/;
		if (font.match(word)) {
			var name = font.matched(1);
			if (["sans", "mono", "serif"].indexOf(name) >= 0)
				return {name: "font-family", value: 'var(--font-$name)'};
			if (["thin", "light", "normal", "medium", "semibold", "bold", "black"].indexOf(name) >= 0)
				return {name: "font-weight", value: 'var(--font-$name)'};
			return null;
		}
		var leading = ~/^leading-([a-z]+)$/;
		if (leading.match(word))
			return {name: "line-height", value: 'var(--leading-${leading.matched(1)})'};
		var tracking = ~/^tracking-(tighter|tight|normal|wide|wider)$/;
		if (tracking.match(word))
			return {name: "letter-spacing", value: 'var(--tracking-${tracking.matched(1)})'};
		var color = ~/^text-([a-z0-9-]+?)(?:\/(\d{1,3}))?$/;
		if (color.match(word)) {
			var name = color.matched(1), percent = color.matched(2);
			if (colors == null)
				vocabulary();
			var fixed = fixedColor(name);
			var base = fixed != null ? (fixed.alpha == 0 ? "transparent" : '#${StringTools.hex(fixed.hex, 6)}') : colors.exists(name) ? 'var(--$name)' : null;
			if (base == null)
				return null;
			return {name: "color", value: percent == null ? base : 'color-mix(in srgb, $base $percent%, transparent)'};
		}
		return null;
	}

	/** A glass utility's CSS property and value, including arbitrary glass settings. **/
	static function glassCss(word:String, pos:Position):Null<{name:String, value:String}> {
		if (word == "bg-glass")
			return {name: "background", value: "glass"};
		if (word == "glass-liquid" || word == "glass-frosted")
			return {name: "glass-mode", value: word.substr(6)};
		if (word == "glass-inset" || word == "glass-outset")
			return {name: "glass-curvature", value: word.substr(6)};
		var amount = ~/^glass-(blur|aberration|noise|bevel)-(\d+(?:\.\d+)?)$/;
		if (amount.match(word)) {
			var property = amount.matched(1), value = amount.matched(2);
			if (property != "blur" && Std.parseFloat(value) > 100)
				Context.error('tw: $word: $property is 0 to 100', pos);
			return {name: 'glass-$property', value: value + (property == "blur" ? "px" : "%")};
		}
		var tint = ~/^glass-tint-([a-z0-9-]+?)(?:\/(\d{1,3}))?$/;
		if (tint.match(word)) {
			var name = tint.matched(1), percent = tint.matched(2);
			var fixed = fixedColor(name);
			var base = fixed != null ? (fixed.alpha == 0 ? "transparent" : '#${StringTools.hex(fixed.hex, 6)}') : colors.exists(name) ? 'var(--$name)' : null;
			if (base == null)
				return null;
			if (percent != null && Std.parseInt(percent) > 100)
				Context.error('tw: $word: an opacity is 0 to 100', pos);
			return {name: "glass-tint", value: percent == null ? base : 'color-mix(in srgb, $base $percent%, transparent)'};
		}
		var arbitrary = ~/^\[(glass-(?:blur|tint|aberration|bevel|curvature|noise|mode)):(.+)\]$/;
		if (arbitrary.match(word))
			return {name: arbitrary.matched(1), value: StringTools.replace(arbitrary.matched(2), "_", " ")};
		return null;
	}

	static function fixedColor(name:String):Null<{hex:Int, alpha:Float}> {
		return switch name {
			case "white": {hex: 0xffffff, alpha: 1.0};
			case "black": {hex: 0x000000, alpha: 1.0};
			case "transparent": {hex: 0x000000, alpha: 0.0};
			case _: null;
		}
	}

	/** Sets `target`'s props to colour `name`, its alpha scaled by `alpha`; a theme colour follows the theme. **/
	static function colorSetter(target:{prefix:String, props:Array<String>, brush:Bool}, name:String, alpha:Float):Expr->Array<Expr> {
		var fixed = fixedColor(name);
		var value = if (fixed != null) {
			var a = fixed.alpha * alpha;
			target.brush ? macro ashui.types.Brush.solid($v{fixed.hex}, $v{a}) : macro new ashui.types.Color($v{fixed.hex}, $v{a});
		} else {
			var token = colors.get(name);
			target.brush ? macro ashui.theme.Themed.brush(ashui.theme.ColorToken.$token, $v{alpha}) : macro ashui.theme.Themed.color(ashui.theme.ColorToken.$token,
				$v{alpha});
		}
		return node -> [for (key in target.props) macro $node.set(ashui.layout.Prop.$key, $value)];
	}

	@:allow(ashui.style.Gradient) static function colorToken(name:String):Null<String> {
		vocabulary();
		return colors.get(name);
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

#if macro
/**
	The transform classes of one class string, composed into one transform,
	as Tailwind's `--tw-translate-x` and the like compose in the browser;
	`hover:` and `active:` ones compose over the plain ones. An `animate-`
	class replaces the transform, and for ping and pulse the opacity.
**/
private class TransformClasses {
	static final ROTATIONS = [0, 1, 2, 3, 6, 12, 45, 90, 180];
	static final SCALES = [0, 50, 75, 90, 95, 100, 105, 110, 125, 150];
	static final SKEWS = [0, 1, 2, 3, 6, 12];

	// Parts by state: "" for the plain classes.
	final parts = new Map<String, Map<String, Expr>>();
	var at:Null<Position> = null;
	var animation:Null<String> = null;
	var animationAt:Null<Position> = null;

	public function new() {}

	public function take(word:String, pos:Position):Bool {
		var anim = ~/^animate-(spin|ping|pulse|bounce|none)$/;
		if (anim.match(word)) {
			animation = anim.matched(1);
			animationAt = pos;
			return true;
		}
		var state = "";
		var rest = word;
		var prefixed = Tw.VARIANT;
		if (prefixed.match(word)) {
			state = prefixed.matched(1);
			rest = prefixed.matched(2);
		}
		var negative = StringTools.startsWith(rest, "-");
		if (negative)
			rest = rest.substr(1);
		var sign = negative ? -1.0 : 1.0;
		var part:Null<String> = null;
		var value:Null<Expr> = null;
		var translate = ~/^translate-([xy])-(.+)$/;
		var rotate = ~/^rotate-(\d+)$/;
		var scale = ~/^scale-(?:([xy])-)?(\d+)$/;
		var skew = ~/^skew-([xy])-(\d+)$/;
		if (translate.match(rest)) {
			var token = "Space" + translate.matched(2).split(".").join("_");
			if (!Lambda.has(@:privateAccess Tw.tokenNames("ashui.theme.SpacingToken"), token))
				return false;
			part = translate.matched(1) == "x" ? "translateX" : "translateY";
			value = macro ashui.style.Variant.space(ashui.theme.SpacingToken.$token) * $v{sign};
		} else if (rotate.match(rest)) {
			var degrees = Std.parseInt(rotate.matched(1));
			if (ROTATIONS.indexOf(degrees) < 0)
				Context.error('tw: $word: rotations are ${ROTATIONS.join(", ")} degrees', pos);
			part = "rotate";
			value = macro $v{degrees * sign};
		} else if (scale.match(rest)) {
			if (negative)
				return false;
			var percent = Std.parseInt(scale.matched(2));
			if (SCALES.indexOf(percent) < 0)
				Context.error('tw: $word: scales are ${SCALES.join(", ")} percent', pos);
			var axis = scale.matched(1);
			var axes = if (axis == null) ["scaleX", "scaleY"] else if (axis == "x") ["scaleX"] else ["scaleY"];
			for (p in axes)
				put(state, p, macro $v{percent / 100});
			at = at == null ? pos : at;
			return true;
		} else if (skew.match(rest)) {
			var degrees = Std.parseInt(skew.matched(2));
			if (SKEWS.indexOf(degrees) < 0)
				Context.error('tw: $word: skews are ${SKEWS.join(", ")} degrees', pos);
			part = skew.matched(1) == "x" ? "skewX" : "skewY";
			value = macro $v{degrees * sign};
		} else {
			return false;
		}
		put(state, part, value);
		at = at == null ? pos : at;
		return true;
	}

	function put(state:String, part:String, value:Expr):Void {
		if (!parts.exists(state))
			parts.set(state, new Map());
		parts.get(state).set(part, value);
	}

	/** The plain transform's set, and each state's transform; null if the string has neither. **/
	public function build(node:Expr):Null<{base:Expr, states:Map<String, {value:Expr, pos:Position}>}> {
		if (animation != null) {
			if ([for (k in parts.keys()) k].filter(k -> k != "").length > 0)
				Context.error("tw: an animate- class replaces the transform, so state variants of transforms do nothing beside it", animationAt);
			function set(key:String, value:Expr):Expr
				return macro $node.set(ashui.layout.Prop.$key, $value);
			var sets = switch animation {
				case "spin": [set("Transform", macro ashui.animation.Keyframes.spin())];
				case "ping": [set("Transform", macro ashui.animation.Keyframes.pingScale()), set("Opacity", macro ashui.animation.Keyframes.pingOpacity())];
				case "pulse": [set("Opacity", macro ashui.animation.Keyframes.pulse())];
				case "bounce": [set("Transform", macro ashui.animation.Keyframes.bounce($node))];
				case _: [];
			}
			return {base: {expr: EBlock(sets), pos: animationAt}, states: new Map()};
		}
		if (at == null)
			return null;
		var base = parts.exists("") ? parts.get("") : new Map();
		function transform(own:Map<String, Expr>):Expr {
			function part(name:String, fallback:Float):Expr {
				var v = own.exists(name) ? own.get(name) : base.get(name);
				return v != null ? v : macro $v{fallback};
			}
			var made = macro new ashui.types.Transform(${part("translateX", 0)}, ${part("translateY", 0)}, ${part("rotate", 0)}, ${part("scaleX", 1)},
				${part("scaleY", 1)}, ${part("skewX", 0)}, ${part("skewY", 0)});
			// Spacing tokens follow the theme, so a transform that reads one is a computed.
			return macro ashui.reactive.Computed.make(() -> $made);
		}
		var states = new Map<String, {value:Expr, pos:Position}>();
		for (state in Tw.STATES)
			if (parts.exists(state))
				states.set(state, {value: transform(parts.get(state)), pos: at});
		var value = transform(new Map());
		return {base: {expr: (macro $node.set(ashui.layout.Prop.Transform, $value)).expr, pos: at}, states: states};
	}
}

/** The transition classes of one class string, composed into one `Transition`. **/
private class Motion {
	static final GROUPS = [
		"transition" => "DEFAULT", "transition-all" => "ALL", "transition-colors" => "COLORS", "transition-opacity" => "opacity",
		"transition-shadow" => "shadow", "transition-transform" => "transform", "transition-none" => "none"
	];
	static final DURATIONS = [
		"fastest" => "DurationFastest", "faster" => "DurationFaster", "fast" => "DurationFast", "normal" => "DurationNormal",
		"slow" => "DurationSlow", "slower" => "DurationSlower", "slowest" => "DurationSlowest"
	];
	static final EASINGS = [
		"default" => "Default", "in" => "In", "out" => "Out", "in-out" => "InOut", "state" => "State", "nav" => "Nav", "spring" => "Spring",
		"sheet" => "Sheet"
	];
	// Tailwind's millisecond steps for durations and delays.
	static final MILLISECONDS = [0, 75, 100, 150, 200, 300, 500, 700, 1000];

	var group:Null<String> = null;
	var at:Null<Position> = null;
	var duration:Null<Expr> = null;
	var milliseconds:Null<Int> = null;
	var easing:Null<Expr> = null;
	var curve:Null<Expr> = null;
	var delay = 0;
	var loose:Null<Position> = null;

	public function new() {}

	public function take(word:String, pos:Position):Bool {
		var g = GROUPS.get(word);
		if (g != null) {
			group = g;
			at = pos;
			return true;
		}
		var timed = ~/^(duration|delay)-(.+)$/;
		if (timed.match(word)) {
			var which = timed.matched(1), value = timed.matched(2);
			loose = loose == null ? pos : loose;
			var token = DURATIONS.get(value);
			if (which == "duration" && token != null) {
				duration = macro ashui.theme.AnimationToken.$token;
				milliseconds = null;
				return true;
			}
			var ms = Std.parseInt(value);
			if (ms == null || MILLISECONDS.indexOf(ms) < 0 || Std.string(ms) != value)
				Context.error('tw: $word: use a theme duration (fastest … slowest) or one of ${MILLISECONDS.join(", ")} ms', pos);
			if (which == "duration") {
				milliseconds = ms;
				duration = null;
			} else
				delay = ms;
			return true;
		}
		var eased = ~/^ease-(.+)$/;
		if (eased.match(word)) {
			loose = loose == null ? pos : loose;
			var name = eased.matched(1);
			if (name == "linear") {
				curve = macro ashui.theme.Easing.Linear;
				easing = null;
				return true;
			}
			var token = EASINGS.get(name);
			if (token == null)
				Context.error('tw: $word: the curves are ${[for (k in EASINGS.keys()) 'ease-$k'].join(", ")} and ease-linear', pos);
			easing = macro ashui.theme.EasingToken.$token;
			curve = null;
			return true;
		}
		return false;
	}

	public function build(node:Expr):Null<Expr> {
		if (group == null) {
			if (loose != null)
				Context.error("tw: duration-, ease- and delay- need a transition class, such as transition or transition-colors", loose);
			return null;
		}
		var properties = switch group {
			case "none": macro [];
			case "DEFAULT" | "ALL" | "COLORS":
				var name = group;
				macro ashui.animation.Transition.$name;
			case single:
				var key = single.charAt(0).toUpperCase() + single.substr(1);
				macro [ashui.layout.PropertyId.$key];
		}
		var d = duration != null ? duration : macro null;
		var ms = milliseconds != null ? macro $v{milliseconds} : macro null;
		var e = easing != null ? easing : macro null;
		var c = curve != null ? curve : macro null;
		var value = macro new ashui.animation.Transition($properties, $d, $ms, $e, $c, $v{delay});
		return {expr: (macro $node.transition = $value).expr, pos: at};
	}
}

/**
	The gradient classes of one class string, composed into one fill as
	Tailwind's CSS variables compose them in the browser: a direction
	(`bg-gradient-to-r`, `bg-linear-to-br`, `bg-radial`) and `from-`, `via-`
	and `to-` stops, each a theme colour, with positions such as `from-10%`.
	A missing first or last stop is the nearest stop made transparent.
**/
private class Gradient {
	// Start and end of each direction, as fractions of the box; y down.
	static final DIRECTIONS:Map<String, Array<Float>> = [
		"t" => [0.5, 1, 0.5, 0], "tr" => [0, 1, 1, 0], "r" => [0, 0.5, 1, 0.5], "br" => [0, 0, 1, 1],
		"b" => [0.5, 0, 0.5, 1], "bl" => [1, 0, 0, 1], "l" => [1, 0.5, 0, 0.5], "tl" => [1, 1, 0, 0]
	];

	var geometry:Null<Array<Float>> = null;
	var radial = false;
	var at:Null<Position> = null;
	final stops = new Map<String, {token:Null<String>, offset:Null<Float>, pos:Position}>();

	public function new() {}

	/** Takes `word` if it is a gradient class; false if it is not one. **/
	public function take(word:String, pos:Position):Bool {
		var direction = ~/^bg-(?:gradient|linear)-to-(t|tr|r|br|b|bl|l|tl)$/;
		if (direction.match(word)) {
			geometry = DIRECTIONS.get(direction.matched(1));
			radial = false;
			at = pos;
			return true;
		}
		if (word == "bg-radial") {
			// About the centre, out to the corners as CSS's farthest-corner reaches them.
			geometry = [0.5, 0.5, 0.70710678, 0];
			radial = true;
			at = pos;
			return true;
		}
		var stop = ~/^(from|via|to)-(.+)$/;
		if (!stop.match(word))
			return false;
		var which = stop.matched(1);
		var rest = stop.matched(2);
		var entry = stops.get(which);
		if (entry == null) {
			entry = {token: null, offset: null, pos: pos};
			stops.set(which, entry);
		}
		var percent = ~/^(\d+)%$/;
		if (percent.match(rest)) {
			var value = Std.parseInt(percent.matched(1));
			if (value > 100 || value % 5 != 0)
				Context.error('tw: $word: stop positions go from 0% to 100% in steps of 5', pos);
			entry.offset = value / 100;
			return true;
		}
		var token = Tw.colorToken(rest);
		if (token == null) {
			// Not a gradient stop after all, as `top-4` is not; let the vocabulary have it.
			if (entry.token == null && entry.offset == null)
				stops.remove(which);
			return false;
		}
		entry.token = token;
		entry.pos = pos;
		return true;
	}

	/** The fill these classes give, or null if there were none. **/
	public function build(node:Expr):Null<Expr> {
		if (geometry == null && !stops.keys().hasNext())
			return null;
		if (geometry == null) {
			var any = stops.iterator().next();
			Context.error("tw: from-, via- and to- need a direction, such as bg-linear-to-r or bg-radial", any.pos);
		}
		var from = stops.get("from"), via = stops.get("via"), to = stops.get("to");
		var colored = [for (s in [from, via, to]) if (s != null && s.token != null) s];
		if (colored.length == 0)
			Context.error("tw: a gradient needs at least one of from-, via- or to- with a colour", at);
		for (s in [from, via, to])
			if (s != null && s.token == null)
				Context.error("tw: a stop position needs its colour too, such as from-primary from-10%", s.pos);
		function stop(token:String, offset:Float, alpha:Float):Expr
			return macro {token: ashui.theme.ColorToken.$token, offset: $v{offset}, alpha: $v{alpha}};
		var list = [];
		var first = from != null ? from : colored[0];
		list.push(stop(first.token, from != null && from.offset != null ? from.offset : 0, from != null ? 1 : 0));
		if (via != null)
			list.push(stop(via.token, via.offset != null ? via.offset : 0.5, 1));
		var last = to != null ? to : colored[colored.length - 1];
		list.push(stop(last.token, to != null && to.offset != null ? to.offset : 1, to != null ? 1 : 0));
		var g = geometry;
		var value = macro ashui.theme.Themed.gradient($v{radial}, $v{g[0]}, $v{g[1]}, $v{g[2]}, $v{g[3]}, $a{list});
		return {expr: (macro $node.set(ashui.layout.Prop.Background, $value)).expr, pos: at};
	}
}
#end
