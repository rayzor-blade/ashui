package ashui.css;

import ashui.css.CssValue;
import ashui.css.Properties;
import ashui.css.Stylesheet;
import ashui.layout.LayoutTree;

/** How an element reads the pointer: `pointer-space`, `pointer-origin`, `pointer-range`, `pointer-smoothing`. **/
typedef PointerConfig = {
	/** `self`, `parent` or `viewport`: the box the position is measured in. **/
	final space:String;

	/** `center`, `top-left` or `bottom-left`: where the range's ends lie. **/
	final origin:String;

	final min:Float;
	final max:Float;

	/** Seconds to ease toward a new reading; 0 follows at once. **/
	final smoothing:Float;
}

/**
	CSS pointer queries: an element whose declarations read
	`env(pointer-…)` has those declarations applied again as the pointer
	moves, with these values:

	- `pointer-x`, `pointer-y`: where the pointer is in the box
	  `pointer-space` names, mapped onto `pointer-range` (`-1 1` by default,
	  from the centre); measured outside the box too, beyond the range, so a
	  rule can respond to the pointer coming near;
	- `pointer-vx`, `pointer-vy`, `pointer-speed`: how fast it moves, in
	  range units a second;
	- `pointer-distance` and `pointer-angle` from the origin;
	- `pointer-inside`: 1 over the element, 0 off it, eased by the smoothing;
	- `pointer-active`: 1 while pressed over it; `pointer-pressure` the same,
	  eased;
	- `pointer-hover-duration`: seconds since it came over the element.

	Any property may read them, through `calc()` or alone.
**/
class PointerQueries {
	static final trackers = new haxe.ds.ObjectMap<Identity, Tracker>();
	static var hooked = false;

	/** Tracks `identity` with `config`, applying `live`'s declarations as the pointer moves; none stops it. **/
	public static function track(identity:Identity, config:Null<PointerConfig>, live:Map<String, String>, ctx:ApplyContext,
			from:Map<String, Declaration>):Void {
		var empty = !live.keys().hasNext();
		var tracker = trackers.get(identity);
		if (config == null && empty) {
			if (tracker != null) {
				tracker.stopped = true;
				trackers.remove(identity);
			}
			if (hooked && !trackers.keys().hasNext()) {
				ashui.input.Pointer.hooks.remove(moved);
				hooked = false;
			}
			return;
		}
		if (!hooked) {
			hooked = true;
			ashui.input.Pointer.hooks.push(moved);
		}
		if (tracker == null)
			trackers.set(identity, tracker = new Tracker(identity));
		tracker.config = config != null ? config : {space: "self", origin: "center", min: -1, max: 1, smoothing: 0};
		tracker.live = live;
		tracker.ctx = ctx;
		tracker.from = from;
		tracker.update(0);
	}

	/** The fields `identity`'s pointer-driven declarations write. **/
	public static function fields(identity:Identity):Array<Int> {
		var t = trackers.get(identity);
		return t == null ? [] : t.fields;
	}

	/** Reads `config` from an element's values; null when it sets no `pointer-` property. Throws a `String` for a bad one. **/
	public static function config(values:Map<String, String>):Null<PointerConfig> {
		var space = values.get("pointer-space"), origin = values.get("pointer-origin");
		var range = values.get("pointer-range"), smoothing = values.get("pointer-smoothing");
		if (space == null && origin == null && range == null && smoothing == null)
			return null;
		var s = space == null ? "self" : StringTools.trim(space).toLowerCase();
		if (["self", "parent", "viewport", "none"].indexOf(s) < 0)
			throw 'pointer-space is self, parent, viewport or none, not "$space"';
		var o = origin == null ? "center" : StringTools.trim(origin).toLowerCase();
		if (["center", "top-left", "bottom-left"].indexOf(o) < 0)
			throw 'pointer-origin is center, top-left or bottom-left, not "$origin"';
		var min = -1.0, max = 1.0;
		if (range != null) {
			var parts = CssValue.split(range, " ");
			if (parts.length != 2)
				throw "pointer-range takes a minimum and a maximum";
			min = CssValue.number(parts[0]);
			max = CssValue.number(parts[1]);
		}
		var smooth = smoothing == null ? 0.0 : {
			var d = CssValue.dimension(smoothing);
			if (d == null || (d.unit != "" && d.unit != "s" && d.unit != "ms"))
				throw 'pointer-smoothing is a time, not "$smoothing"';
			d.unit == "ms" ? d.value / 1000 : d.value;
		}
		return {space: s, origin: o, min: min, max: max, smoothing: smooth};
	}

	static function moved(tree:LayoutTree):Void {
		for (identity => tracker in trackers)
			if (identity.tree == tree)
				tracker.update(0);
	}
}

@:allow(ashui.css.PointerQueries)
private class Tracker {
	final identity:Identity;
	var config:PointerConfig;
	var live:Map<String, String> = [];
	var ctx:ApplyContext;
	var from:Map<String, Declaration> = [];
	final fields:Array<Int> = [];
	var stopped = false;
	var ticking = false;

	// Readings, raw and eased.
	var x = 0.0;
	var y = 0.0;
	var vx = 0.0;
	var vy = 0.0;
	var inside = 0.0;
	var pressure = 0.0;
	var active = false;
	var entered = -1.0;
	var lastX = Math.NaN;
	var lastY = Math.NaN;
	var lastTime = 0.0;
	final reported = new Map<String, Bool>();

	function new(identity:Identity)
		this.identity = identity;

	/** Reads the pointer, eases toward it, and applies the declarations; keeps ticking while easing. **/
	function update(dt:Float):Bool {
		if (stopped || config.space == "none")
			return false;
		var tree = identity.tree;
		var p = ashui.input.Pointer.at(tree);
		var own = tree.getBounds(identity.node);
		if (own == null)
			return false;
		var box = switch config.space {
			case "viewport": {x: 0.0, y: 0.0, w: Css.viewportWidth, h: Css.viewportHeight};
			case "parent":
				var up = tree.ancestors(identity.node.id);
				var b = up.length == 0 ? null : tree.getBounds(new ashui.layout.Node(up[0]));
				b == null ? {x: own.x, y: own.y, w: own.width, h: own.height} : {x: b.x, y: b.y, w: b.width, h: b.height};
			case _: {x: own.x, y: own.y, w: own.width, h: own.height};
		}
		var u = box.w > 0 ? (p.x - box.x) / box.w : 0.0;
		var v = box.h > 0 ? (p.y - box.y) / box.h : 0.0;
		var span = config.max - config.min;
		var tx, ty;
		switch config.origin {
			case "top-left":
				tx = config.min + u * span;
				ty = config.min + v * span;
			case "bottom-left":
				tx = config.min + u * span;
				ty = config.min + (1 - v) * span;
			case _:
				var mid = (config.min + config.max) / 2;
				tx = mid + (u - 0.5) * span;
				ty = mid + (v - 0.5) * span;
		}
		var over = p.inside && p.x >= own.x && p.x < own.x + own.width && p.y >= own.y && p.y < own.y + own.height;
		var now = ashui.input.InputClock.now();
		if (over && entered < 0)
			entered = now;
		else if (!over)
			entered = -1;
		active = over && p.pressed;
		// Velocity from the raw positions over the time between readings.
		if (!Math.isNaN(lastX) && now > lastTime) {
			vx = (tx - lastX) / (now - lastTime);
			vy = (ty - lastY) / (now - lastTime);
		}
		lastX = tx;
		lastY = ty;
		lastTime = now;
		var settled = true;
		inline function ease(current:Float, target:Float):Float {
			if (config.smoothing <= 0 || dt <= 0 && Math.isNaN(current))
				return target;
			var step = dt <= 0 ? 0 : 1 - Math.exp(-dt / config.smoothing);
			var next = current + (target - current) * step;
			if (Math.abs(target - next) > 0.0005)
				settled = false;
			return next;
		}
		x = ease(x, tx);
		y = ease(y, ty);
		inside = ease(inside, over ? 1 : 0);
		pressure = ease(pressure, active ? 1 : 0);
		apply();
		// Easing goes on between pointer events, ticked until it settles.
		if (config.smoothing > 0 && !settled && !ticking) {
			ticking = true;
			ashui.animation.AnimationScheduler.main.addTicker(d -> {
				var go = update(d);
				if (!go)
					ticking = false;
				go;
			});
		}
		return config.smoothing > 0 && !settled;
	}

	function env(name:String):Null<Float> {
		return switch name {
			case "pointer-x": x;
			case "pointer-y": y;
			case "pointer-vx": vx;
			case "pointer-vy": vy;
			case "pointer-speed": Math.sqrt(vx * vx + vy * vy);
			case "pointer-distance": Math.sqrt(x * x + y * y);
			case "pointer-angle": Math.atan2(y, x);
			case "pointer-inside": inside;
			case "pointer-active": active ? 1 : 0;
			case "pointer-pressure": pressure;
			case "pointer-hover-duration": entered < 0 ? 0 : ashui.input.InputClock.now() - entered;
			case "pointer-touch-count": 0;
			case _: null;
		}
	}

	function apply():Void {
		@:privateAccess ashui.layout.Node.immediate = true;
		for (name => value in live) {
			try {
				var settled = CssValue.settle(value, env, {
					percentOf: 0,
					fontSize: ctx.fontSize,
					rootFontSize: ctx.rootFontSize,
					viewportWidth: ctx.viewportWidth,
					viewportHeight: ctx.viewportHeight,
					env: env
				});
				for (f in Properties.apply(identity.node, name, settled, ctx))
					if (fields.indexOf(f) < 0)
						fields.push(f);
			} catch (e:String) {
				if (!reported.exists(name)) {
					reported.set(name, true);
					@:privateAccess Css.problem(from.get(name), '$name: $e');
				}
			}
		}
		@:privateAccess ashui.layout.Node.immediate = false;
	}
}
