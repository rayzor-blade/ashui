package ashui.css;

import ashui.css.CssMotion;
import ashui.css.Properties;
import ashui.css.Stylesheet;
import ashui.theme.Easing;

/** One property's keyframes: values at offsets, each with the timing to the next. **/
private typedef Track = Array<{offset:Float, value:String, easing:Null<Easing>}>;

/**
	The `@keyframes` animations running on elements, ticked by
	`AnimationScheduler.main`. Each frame writes the animated properties
	through the stylesheet's write, at once rather than by any transition.
**/
class Animations {
	static final running = new haxe.ds.ObjectMap<Identity, Array<Run>>();

	/**
		Starts, keeps or stops `identity`'s animations for the values it has
		now: one is kept while its entry is the same, and started again when
		it changes. The property names the animations hold, which the
		cascade then leaves to them.
	**/
	public static function update(identity:Identity, resolved:Map<String, String>, values:Map<String, String>, ctx:ApplyContext,
			from:Map<String, Declaration>):Map<String, Bool> {
		var specs = try CssMotion.animations(resolved) catch (e:String) {
			@:privateAccess Css.problem(from.get("animation") != null ? from.get("animation") : from.get("animation-name"), 'animation: $e');
			[];
		}
		var list = running.get(identity);
		if (list == null)
			list = [];
		var next = [];
		for (spec in specs) {
			var key = signature(spec);
			var kept = Lambda.find(list, r -> r.key == key && !r.stopped);
			if (kept != null) {
				kept.paused = spec.paused;
				kept.ctx = ctx;
				next.push(kept);
				continue;
			}
			var frames = @:privateAccess Css.keyframes(spec.name);
			if (frames == null) {
				@:privateAccess Css.problem(from.get("animation") != null ? from.get("animation") : from.get("animation-name"),
					'animation: no @keyframes ${spec.name}');
				continue;
			}
			var run = new Run(identity, spec, key, frames, resolved, values, ctx);
			next.push(run);
			run.start();
		}
		for (r in list)
			if (next.indexOf(r) < 0)
				r.stop();
		if (next.length == 0)
			running.remove(identity);
		else
			running.set(identity, next);
		var held = new Map<String, Bool>();
		for (r in next)
			if (r.holds())
				for (name in r.tracks.keys())
					held.set(name, true);
		return held;
	}

	/** The fields `identity`'s animations write while they hold them. **/
	public static function fields(identity:Identity):Array<Int> {
		var out = [];
		var list = running.get(identity);
		if (list != null)
			for (r in list)
				if (r.holds())
					for (f in r.fields)
						if (out.indexOf(f) < 0)
							out.push(f);
		return out;
	}

	/** Stops `identity`'s animations, its element removed. **/
	public static function release(identity:Identity):Void {
		var list = running.get(identity);
		if (list == null)
			return;
		for (r in list)
			r.stop();
		running.remove(identity);
	}

	/** Whether `identity` has an animation running. **/
	public static function active(identity:Identity):Bool
		return running.exists(identity);

	@:allow(ashui.css.Run)
	static function ended(run:Run):Void {
		var list = running.get(run.identity);
		if (list != null) {
			list.remove(run);
			if (list.length == 0)
				running.remove(run.identity);
		}
		// The cascade takes the properties back.
		@:privateAccess Css.markAgain(run.identity);
	}

	static function signature(s:AnimationSpec):String
		return '${s.name}|${s.duration}|${s.easing}|${s.delay}|${s.iterations}|${s.direction}|${s.fill}';
}

@:allow(ashui.css.Animations)
private class Run {
	public final identity:Identity;
	public final key:String;
	final spec:AnimationSpec;
	public final tracks = new Map<String, Track>();
	public final fields:Array<Int> = [];
	public var paused:Bool;
	public var ctx:ApplyContext;
	public var stopped(default, null) = false;
	var finished = false;
	var elapsed = 0.0;
	final reported = new Map<String, Bool>();

	public function new(identity:Identity, spec:AnimationSpec, key:String, frames:Keyframes, base:Map<String, String>, values:Map<String, String>,
			ctx:ApplyContext) {
		this.identity = identity;
		this.spec = spec;
		this.key = key;
		this.paused = spec.paused;
		this.ctx = ctx;
		for (frame in frames.frames) {
			var easing:Null<Easing> = null;
			for (d in frame.declarations)
				if (d.name == "animation-timing-function")
					easing = try CssMotion.easing(d.value) catch (_:String) null;
			for (d in frame.declarations) {
				if (d.name == "animation-timing-function" || StringTools.startsWith(d.name, "--"))
					continue;
				var track = tracks.get(d.name);
				if (track == null)
					tracks.set(d.name, track = []);
				var value = @:privateAccess Css.substitute(d.value, values, identity);
				for (o in frame.offsets)
					track.push({offset: o, value: value, easing: easing});
			}
		}
		// A missing first or last frame is the element's own value, as CSS fills it.
		for (name => track in tracks) {
			track.sort((a, b) -> a.offset < b.offset ? -1 : a.offset > b.offset ? 1 : 0);
			var own = base.get(name);
			if (track[0].offset > 0)
				track.unshift({offset: 0, value: own != null ? own : track[0].value, easing: null});
			if (track[track.length - 1].offset < 1)
				track.push({offset: 1, value: own != null ? own : track[track.length - 1].value, easing: null});
		}
	}

	/** Whether the cascade leaves its properties to it now: while it runs, and after with `forwards`. **/
	public function holds():Bool {
		if (stopped)
			return false;
		if (finished)
			return spec.fill == "forwards" || spec.fill == "both";
		if (elapsed < spec.delay)
			return spec.fill == "backwards" || spec.fill == "both";
		return true;
	}

	public function start():Void {
		frame();
		if (!finished)
			ashui.animation.AnimationScheduler.main.addTicker(tick);
	}

	public function stop():Void
		stopped = true;

	function tick(dt:Float):Bool {
		if (stopped)
			return false;
		if (!paused)
			elapsed += dt;
		frame();
		return !finished;
	}

	/** Writes where the animation is now; ends it when its iterations are done. **/
	function frame():Void {
		var active = elapsed - spec.delay;
		var progress:Float;
		if (active < 0) {
			if (!holds())
				return;
			progress = reversed(0) ? 1 : 0;
		} else {
			var total = spec.duration * spec.iterations;
			if (spec.duration <= 0 || active >= total) {
				// The end: where the last iteration stops.
				var last = Math.max(0, Math.ceil(spec.iterations) - 1);
				var partial = spec.iterations - Math.ffloor(spec.iterations);
				var at = partial > 0 ? partial : 1.0;
				progress = reversed(Std.int(last)) ? 1 - at : at;
				finished = true;
				if (!holds()) {
					Animations.ended(this);
					return;
				}
			} else {
				var iteration = Math.ffloor(active / spec.duration);
				var local = (active - iteration * spec.duration) / spec.duration;
				progress = reversed(Std.int(iteration)) ? 1 - local : local;
			}
		}
		write(progress);
	}

	function reversed(iteration:Int):Bool {
		return switch spec.direction {
			case "reverse": true;
			case "alternate": iteration % 2 == 1;
			case "alternate-reverse": iteration % 2 == 0;
			case _: false;
		}
	}

	function write(progress:Float):Void {
		@:privateAccess ashui.layout.Node.immediate = true;
		for (name => track in tracks) {
			var k = 0;
			while (k < track.length - 2 && track[k + 1].offset <= progress)
				k++;
			var a = track[k], b = track[k + 1];
			var span = b.offset - a.offset;
			var local = span <= 0 ? 1.0 : (progress - a.offset) / span;
			var eased = ashui.theme.Easing.EasingTools.evaluate(a.easing != null ? a.easing : spec.easing, local);
			var value = CssMotion.interpolate(a.value, b.value, eased);
			try {
				for (f in Properties.apply(identity.node, name, value, ctx))
					if (fields.indexOf(f) < 0)
						fields.push(f);
			} catch (e:String) {
				if (!reported.exists(name)) {
					reported.set(name, true);
					@:privateAccess Css.problem(null, '@keyframes ${spec.name}: $name: $e');
				}
			}
		}
		@:privateAccess ashui.layout.Node.immediate = false;
	}
}
