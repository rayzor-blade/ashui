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
	public static function active(identity:Identity):Bool {
		var list = running.get(identity);
		return list != null && Lambda.exists(list, r -> !r.finished && !r.stopped);
	}

	/** How long, in seconds, the longest of `identity`'s running animations has left to play; infinite for one that repeats forever. **/
	public static function remaining(identity:Identity):Float {
		var list = running.get(identity);
		var left = 0.0;
		if (list != null)
			for (r in list)
				if (!@:privateAccess r.finished && !r.stopped)
					left = Math.max(left, @:privateAccess r.spec.delay + r.spec.duration * r.spec.iterations - r.elapsed);
		return left;
	}

	/**
		Calls `done` once the animations of `identities` have played: those
		running, and those a restyle starts within `atLeast` seconds, as one
		does on the frame after an attribute marks an element leaving. None
		is waited on past `limit` seconds, so one that repeats forever still
		lets it go. With no theme's clock running, at once.
	**/
	public static function whenPlayed(identities:Array<Null<Identity>>, atLeast:Float, done:Void->Void, limit = 2.0):Void {
		if (atLeast <= 0) {
			done();
			return;
		}
		var waited = 0.0;
		ashui.animation.AnimationScheduler.main.addTicker(dt -> {
			waited += dt;
			// Left after this tick, whether the animations' tickers run before this one or after.
			var left = 0.0;
			for (identity in identities)
				if (identity != null)
					left = Math.max(left, remaining(identity) - dt);
			if (waited < limit && (waited < atLeast || left > 0))
				return true;
			done();
			return false;
		});
	}

	/**
		A run that played to its end and holds nothing: kept on the list,
		finished, so the same entry does not start it again when the cascade
		takes its properties back; it goes when the entry does.
	**/
	@:allow(ashui.css.Run)
	static function ended(run:Run):Void
		@:privateAccess Css.markAgain(run.identity);

	static function signature(s:AnimationSpec):String
		return '${s.name}|${s.duration}|${s.easing}|${s.delay}|${s.iterations}|${s.direction}|${s.fill}';
}

@:allow(ashui.css.Animations)
private class Run {
	public final identity:Identity;
	public final key:String;
	final spec:AnimationSpec;
	public final tracks = new Map<String, Track>();

	/** Each track's pairs of keyframes, read once, as they are first mixed. **/
	final pairs = new Map<String, Array<Null<CssMotion.PreparedPair>>>();
	public final fields:Array<Int> = [];
	public var paused:Bool;
	public var ctx:ApplyContext;
	public var stopped(default, null) = false;
	var finished = false;
	var elapsed = 0.0;
	final reported = new Map<String, Bool>();
	/** The run being recorded, while a motion trace records. **/
	var motion:Null<ashui.debug.MotionTrack> = null;

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
		// A missing first or last frame is the element's own value, or the property's initial one, as CSS fills it.
		for (name => track in tracks) {
			track.sort((a, b) -> a.offset < b.offset ? -1 : a.offset > b.offset ? 1 : 0);
			var own = base.get(name);
			if (own == null)
				own = CssMotion.INITIAL.get(name);
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
		if (ashui.debug.MotionTrace.current != null) {
			var names = [for (name in tracks.keys()) name];
			names.sort(Reflect.compare);
			var first = names.length == 0 ? null : tracks.get(names[0]);
			motion = ashui.debug.MotionTrace.begin(Keyframes, identity.tree, identity.node.id, '@keyframes ${spec.name} (${names.join(", ")})',
				first == null ? "" : first[0].value, first == null ? "" : first[first.length - 1].value, spec.delay, spec.duration, spec.easing);
			if (motion != null) {
				motion.iterations = spec.iterations;
				motion.direction = spec.direction;
			}
		}
		frame();
		if (!finished)
			ashui.animation.AnimationScheduler.main.addTicker(tick);
	}

	public function stop():Void {
		stopped = true;
		if (motion != null)
			motion.finish(Interrupted);
	}

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
				if (motion != null) {
					motion.sample(progress, progress);
					motion.finish(Completed);
				}
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
		if (motion != null && !finished)
			motion.sample(progress, progress);
		// Out of view it changes nothing drawn: its clock runs on, and it writes where it is once it is seen again.
		if (!finished && !identity.tree.inView(identity.node.id))
			return;
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
			var ready = pairs.get(name);
			if (ready == null)
				pairs.set(name, ready = []);
			var pair = ready[k];
			if (pair == null)
				ready[k] = pair = CssMotion.prepare(a.value, b.value);
			var value = CssMotion.at(pair, eased);
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
