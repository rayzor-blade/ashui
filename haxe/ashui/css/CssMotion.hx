package ashui.css;

import ashui.animation.Transition;
import ashui.css.CssValue;
import ashui.css.Stylesheet;
import ashui.layout.PropertyId;
import ashui.theme.Easing;

/** One `transition` entry: properties, and how they move. **/
typedef TransitionSpec = {
	final properties:Array<PropertyId>;
	final milliseconds:Int;
	final easing:Easing;
	final delay:Int;
}

/** One `animation` entry. **/
typedef AnimationSpec = {
	final name:String;
	final duration:Float;
	final easing:Easing;
	final delay:Float;

	/** Infinity for `infinite`. **/
	final iterations:Float;

	/** `normal`, `reverse`, `alternate` or `alternate-reverse`. **/
	final direction:String;

	/** `none`, `forwards`, `backwards` or `both`. **/
	final fill:String;

	final paused:Bool;
}

/**
	A stylesheet's transition: its own timing for each property, as CSS's
	`transition` gives, so a property moves by the entry naming it last.
**/
class CssTransition extends Transition {
	final byProperty = new Map<Int, Transition>();

	public function new(specs:Array<TransitionSpec>) {
		var all = [];
		for (spec in specs)
			for (p in spec.properties) {
				byProperty.set(p, new Transition([p], null, spec.milliseconds, null, spec.easing, spec.delay));
				if (all.indexOf(p) < 0)
					all.push(p);
			}
		super(all);
	}

	override public function forProperty(prop:PropertyId):Transition {
		var t = byProperty.get(prop);
		return t == null ? this : t;
	}
}

/** CSS transitions and keyframe animations read from declarations, and values interpolated between keyframes. **/
class CssMotion {
	/** What each CSS property name moves, as ashui properties, for `transition-property`. **/
	static final MOVES:Map<String, Array<Int>> = {
		var colors = [1, 67, 68, 69, 70];
		var widths = [2, 60, 61, 62, 63];
		var outline = [9, 66];
		var m = [
			"background" => [0], "background-color" => [0], "color" => [7], "opacity" => [4], "transform" => [5], "box-shadow" => [6],
			"border-color" => colors, "border-width" => widths, "border" => colors.concat(widths), "border-radius" => [3],
			"outline-color" => outline, "outline-width" => [64], "outline-offset" => [65], "outline" => outline.concat([64, 65]),
			"width" => [10, 53], "height" => [11, 54], "min-width" => [12, 55], "max-width" => [13, 56], "min-height" => [14, 57],
			"max-height" => [15, 58], "flex-basis" => [26, 59], "flex-grow" => [23], "flex-shrink" => [24], "padding" => [43, 44, 45, 46],
			"margin" => [47, 48, 49, 50], "gap" => [51, 52], "row-gap" => [52], "column-gap" => [51], "top" => [30], "right" => [31],
			"bottom" => [32], "left" => [33], "inset" => [30, 31, 32, 33], "font-size" => [34], "letter-spacing" => [38],
			"line-height" => [39], "filter" => [76, 77, 78, 79, 80, 81, 82, 83, 84], "overflow-fade" => [71, 72, 73, 74]
		];
		for (i => side in ["top", "right", "bottom", "left"]) {
			m.set('padding-$side', [43 + i]);
			m.set('margin-$side', [47 + i]);
			m.set('border-$side-color', [67 + i]);
			m.set('border-$side-width', [60 + i]);
			m.set('border-$side', [67 + i, 60 + i]);
		}
		m;
	};

	/** The transition `values` give, from `transition` and its longhands; null for none. Throws a `String` for a bad one. **/
	public static function transition(values:Map<String, String>):Null<CssTransition> {
		var props:Array<String> = [], durations:Array<String> = [], easings:Array<String> = [], delays:Array<String> = [];
		var shorthand = values.get("transition");
		if (shorthand != null && StringTools.trim(shorthand).toLowerCase() != "none")
			for (item in CssValue.split(shorthand, ",")) {
				var prop = "all", times = [], easing = "ease";
				for (word in CssValue.split(item, " ")) {
					var w = word.toLowerCase();
					var d = CssValue.dimension(w);
					if (d != null && (d.unit == "s" || d.unit == "ms"))
						times.push(w);
					else if (isEasing(w))
						easing = w;
					else
						prop = w;
				}
				props.push(prop);
				durations.push(times.length > 0 ? times[0] : "0s");
				easings.push(easing);
				delays.push(times.length > 1 ? times[1] : "0s");
			}
		// Longhands over the shorthand's parts.
		inline function list(name:String, into:Array<String>) {
			var v = values.get(name);
			if (v != null) {
				into.resize(0);
				for (x in CssValue.split(v, ","))
					into.push(x.toLowerCase());
			}
		}
		list("transition-property", props);
		list("transition-duration", durations);
		list("transition-timing-function", easings);
		list("transition-delay", delays);
		if (props.length == 0 || (props.length == 1 && props[0] == "none"))
			return null;
		var specs = [];
		for (i => p in props) {
			// A shorter list repeats, as CSS's does.
			inline function at(l:Array<String>, fallback:String):String
				return l.length == 0 ? fallback : l[i % l.length];
			var moved:Array<Int> = if (p == "all") {
				var all = [];
				for (ids in MOVES)
					for (id in ids)
						if (all.indexOf(id) < 0)
							all.push(id);
				all;
			} else {
				var ids = MOVES.get(p);
				if (ids == null)
					throw 'transition: $p is not a property that moves';
				ids;
			}
			specs.push({
				properties: [for (id in moved) (id : PropertyId)],
				milliseconds: Math.round(CssValue.time(at(durations, "0s")) * 1000),
				easing: easing(at(easings, "ease")),
				delay: Math.round(CssValue.time(at(delays, "0s")) * 1000)
			});
		}
		return new CssTransition(specs);
	}

	/** The animations `values` give, from `animation` and its longhands. Throws a `String` for a bad one. **/
	public static function animations(values:Map<String, String>):Array<AnimationSpec> {
		var names:Array<String> = [], durations:Array<String> = [], easings:Array<String> = [], delays:Array<String> = [];
		var counts:Array<String> = [], directions:Array<String> = [], fills:Array<String> = [], states:Array<String> = [];
		var shorthand = values.get("animation");
		if (shorthand != null && StringTools.trim(shorthand).toLowerCase() != "none")
			for (item in CssValue.split(shorthand, ",")) {
				var name = "none", times = [], easing = "ease", count = "1", direction = "normal", fill = "none", state = "running";
				for (word in CssValue.split(item, " ")) {
					var w = word.toLowerCase();
					var d = CssValue.dimension(w);
					if (d != null && (d.unit == "s" || d.unit == "ms"))
						times.push(w);
					else if (d != null && d.unit == "" || w == "infinite")
						count = w;
					else if (isEasing(w))
						easing = w;
					else if (["normal", "reverse", "alternate", "alternate-reverse"].indexOf(w) >= 0)
						direction = w;
					else if (["forwards", "backwards", "both"].indexOf(w) >= 0)
						fill = w;
					else if (w == "paused" || w == "running")
						state = w;
					else
						name = word;
				}
				names.push(name);
				durations.push(times.length > 0 ? times[0] : "0s");
				easings.push(easing);
				delays.push(times.length > 1 ? times[1] : "0s");
				counts.push(count);
				directions.push(direction);
				fills.push(fill);
				states.push(state);
			}
		inline function list(name:String, into:Array<String>, lower = true) {
			var v = values.get(name);
			if (v != null) {
				into.resize(0);
				for (x in CssValue.split(v, ","))
					into.push(lower ? x.toLowerCase() : x);
			}
		}
		list("animation-name", names, false);
		list("animation-duration", durations);
		list("animation-timing-function", easings);
		list("animation-delay", delays);
		list("animation-iteration-count", counts);
		list("animation-direction", directions);
		list("animation-fill-mode", fills);
		list("animation-play-state", states);
		var out = [];
		for (i => name in names) {
			if (name == "none")
				continue;
			inline function at(l:Array<String>, fallback:String):String
				return l.length == 0 ? fallback : l[i % l.length];
			var count = at(counts, "1");
			out.push({
				name: name,
				duration: CssValue.time(at(durations, "0s")),
				easing: easing(at(easings, "ease")),
				delay: CssValue.time(at(delays, "0s")),
				iterations: count == "infinite" ? Math.POSITIVE_INFINITY : CssValue.number(count),
				direction: at(directions, "normal"),
				fill: at(fills, "none"),
				paused: at(states, "running") == "paused"
			});
		}
		return out;
	}

	static function isEasing(w:String):Bool
		return ["linear", "ease", "ease-in", "ease-out", "ease-in-out", "step-start", "step-end"].indexOf(w) >= 0
			|| StringTools.startsWith(w, "cubic-bezier(") || StringTools.startsWith(w, "steps(");

	public static function easing(text:String):Easing {
		return switch CssValue.easing(text) {
			case CubicBezier(a, b, c, d) if (a == 0 && b == 0 && c == 1 && d == 1): Linear;
			case CubicBezier(a, b, c, d): CubicBezier(a, b, c, d);
			case Steps(n, start): Steps(n, start);
		}
	}

	// --- Interpolation ---

	/**
		The value `t` of the way from `a` to `b`, as CSS text: colours made
		`rgba()` and then every number moved, where the two have the same
		shape; otherwise `a` before halfway and `b` after, as CSS animates
		what it cannot interpolate.
	**/
	public static function interpolate(a:String, b:String, t:Float):String {
		// `none` against a transform list is that list's identity: rotate(0deg) to rotate(360deg).
		if (StringTools.trim(a).toLowerCase() == "none" && b.indexOf("(") > 0)
			a = identity(b);
		else if (StringTools.trim(b).toLowerCase() == "none" && a.indexOf("(") > 0)
			b = identity(a);
		var na = numbers(normalize(a)), nb = numbers(normalize(b));
		if (na.skeleton != nb.skeleton || na.values.length != nb.values.length)
			return t < 0.5 ? a : b;
		var out = new StringBuf();
		for (i in 0...na.values.length) {
			out.add(na.parts[i]);
			var x = na.values[i] + (nb.values[i] - na.values[i]) * t;
			out.add(Math.round(x * 10000) / 10000);
			out.add(na.units[i] != "" ? na.units[i] : nb.units[i]);
		}
		out.add(na.parts[na.values.length]);
		return out.toString();
	}

	/** What a property is where nothing sets it, for keyframes that leave out their first or last frame. **/
	public static final INITIAL:Map<String, String> = [
		"opacity" => "1", "transform" => "none", "background-color" => "transparent", "background" => "transparent", "color" => "black",
		"border-color" => "transparent", "box-shadow" => "none", "filter" => "none", "border-radius" => "0px", "padding" => "0px", "margin" => "0px",
		"gap" => "0px", "letter-spacing" => "0px", "outline-offset" => "0px", "outline-width" => "0px"
	];

	/** A transform list with each function's identity arguments, its numbers 0 or, for scale, 1. **/
	static function identity(list:String):String {
		return ~/([a-zA-Z]+)\(([^)]*)\)/g.map(list, r -> {
			var name = r.matched(1);
			var args = r.matched(2);
			var one = name.toLowerCase().indexOf("scale") == 0;
			var zero = ~/[+-]?(?:\d+\.?\d*|\.\d+)/g.map(args, _ -> one ? "1" : "0");
			'$name($zero)';
		});
	}

	/** Colours in `text` written as `rgba(r, g, b, a)`, so two of them interpolate number by number. **/
	static function normalize(text:String):String {
		function color(word:String):Null<String> {
			return try switch CssValue.color(word) {
				case Rgba(rgb, alpha): 'rgba(${(rgb >> 16) & 255}, ${(rgb >> 8) & 255}, ${rgb & 255}, $alpha)';
				case CurrentColor: null;
			} catch (_:String) null;
		}
		// Colour functions and hex colours, then names.
		var out = ~/(#[0-9a-fA-F]{3,8}\b|(?:rgba?|hsla?)\([^)]*\))/g.map(text, r -> {
			var c = color(r.matched(1));
			c == null ? r.matched(1) : c;
		});
		return ~/\b([a-zA-Z]+)\b(?![(-])/g.map(out, r -> {
			var w = r.matched(1);
			if (!CssValue.isNamedColor(w))
				return w;
			var c = color(w);
			c == null ? w : c;
		});
	}

	/** `text` as the text around its numbers, the numbers and their units; units count as part of the shape only when both have one. **/
	static function numbers(text:String):{skeleton:String, parts:Array<String>, values:Array<Float>, units:Array<String>} {
		var parts = [], values = [], units = [];
		var r = ~/([+-]?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?)([a-zA-Z%]*)/;
		var rest = text;
		while (r.match(rest)) {
			parts.push(r.matchedLeft());
			values.push(Std.parseFloat(r.matched(1)));
			units.push(r.matched(2));
			rest = r.matchedRight();
		}
		parts.push(rest);
		// "0" and "10px" have the same shape: a unitless zero takes the other's unit.
		var skeleton = [for (i in 0...values.length) parts[i] + "#"].join("") + rest;
		return {skeleton: skeleton, parts: parts, values: values, units: units};
	}
}
