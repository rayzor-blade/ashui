package ashui.debug;

import ashui.theme.Easing;

/** What moved a track: a property tween (a CSS or Tw transition), a CSS `@keyframes` run, a layout animation, or a spring. **/
enum abstract MotionKind(String) to String {
	var Transition = "transition";
	var Keyframes = "keyframes";
	var Layout = "layout";
	var Spring = "spring";
}

/** Why a track ended: it ran its course, something retargeted or stopped it, or the trace stopped while it ran. **/
enum abstract MotionEnd(String) to String {
	var Completed = "completed";
	var Interrupted = "interrupted";
	var Snapped = "snapped";
	var Running = "running";
}

/**
	One frame of a track, at `clock` seconds on the scheduler's clock.
	`progress` is how far along its course the animation put the value, 0 at
	`from` and 1 at `to` (past either for a curve that overshoots); `local`
	is the time fraction it thought it was at, before its curve. A layout
	animation's frame also has where the element was drawn away from its
	layout and at what size (`dx`, `dy`, `w`, `h`, a size of -1 when not
	sized).
**/
typedef MotionSample = {
	clock:Float,
	progress:Float,
	local:Float,
	?value:String,
	/** A keyframes run's: where its first property's segment curve put it, 0 at the segment's start and 1 at its end. **/
	?eased:Float,
	?dx:Float,
	?dy:Float,
	?w:Float,
	?h:Float
}

/** Where a track's element was drawn in one frame, as the overlay and trails read it. **/
typedef MotionRect = {
	clock:Float,
	x:Float,
	y:Float,
	w:Float,
	h:Float
}

/**
	One animation from its start to its end: what it was declared to do
	(property, values, delay, duration, curve) and what it did, frame by
	frame. `MotionCheck` compares the two.
**/
class MotionTrack {
	public final id:Int;
	public final kind:MotionKind;
	/** The tree and node it moves, when it moves one. **/
	public final tree:Null<ashui.layout.LayoutTree>;
	public final node:Null<haxe.Int64>;
	/** The element as a selector, `button.ui-button#save`, or what moves when no element does. **/
	public final label:String;
	public final property:String;
	public final from:String;
	public final to:String;
	/** Seconds, as declared. **/
	public final delay:Float;
	public final duration:Float;
	/** The curve, when the track has one; its CSS text for the report. **/
	public final easing:Null<Easing>;
	public final curve:String;
	/** A spring's constants, for a spring track. **/
	public final spring:Null<ashui.animation.SpringConfig>;
	/** A keyframes run's iterations and direction, as CSS's `animation-iteration-count` and `animation-direction`. **/
	public var iterations = 1.0;
	public var direction = "normal";
	/** A keyframes run's keyframes, for its first property: each one's offset and the curve to the next. **/
	public var keyframes:Null<Array<{offset:Float, easing:Easing}>> = null;
	/** A spring's speed when released, in moves per second. **/
	public var v0 = 0.0;
	/** The scheduler's clock when it was asked to start. **/
	public final began:Float;
	public var ended(default, null):Null<Float> = null;
	public var end(default, null):MotionEnd = Running;
	public final samples:Array<MotionSample> = [];
	public final rects:Array<MotionRect> = [];

	@:allow(ashui.debug.MotionTrace)
	function new(id:Int, kind:MotionKind, tree:Null<ashui.layout.LayoutTree>, node:Null<haxe.Int64>, label:String, property:String, from:String, to:String,
			delay:Float, duration:Float, easing:Null<Easing>, curve:String, spring:Null<ashui.animation.SpringConfig>, began:Float) {
		this.id = id;
		this.kind = kind;
		this.tree = tree;
		this.node = node;
		this.label = label;
		this.property = property;
		this.from = from;
		this.to = to;
		this.delay = delay;
		this.duration = duration;
		this.easing = easing;
		this.curve = curve;
		this.spring = spring;
		this.began = began;
	}

	public var running(get, never):Bool;

	inline function get_running():Bool
		return end == Running;

	/** Records a frame at the scheduler's clock. **/
	public function sample(progress:Float, local:Float, ?value:String, ?visual:{dx:Float, dy:Float, w:Float, h:Float}, ?eased:Float):Void {
		if (end != Running)
			return;
		var s:MotionSample = {clock: MotionTrace.clock(), progress: progress, local: local};
		if (value != null)
			s.value = value;
		if (eased != null)
			s.eased = eased;
		if (visual != null) {
			s.dx = visual.dx;
			s.dy = visual.dy;
			s.w = visual.w;
			s.h = visual.h;
		}
		samples.push(s);
	}

	/** Ends it, `why`, at the scheduler's clock; a track already ended stays as it ended. **/
	public function finish(why:MotionEnd):Void {
		if (end != Running)
			return;
		end = why;
		ended = MotionTrace.clock();
	}

	/** Where it expected to be at `clock`: its curve at the time fraction then, or null for a spring or a track with no curve. **/
	public function expected(clock:Float):Null<Float> {
		if (kind == Spring)
			return spring == null ? null : MotionCheck.springProgress(spring, clock - began, v0);
		if (easing == null && kind != Layout && kind != Transition)
			return null;
		var t = duration <= 0 ? 1.0 : Math.max(0, Math.min(1, (clock - began - delay) / duration));
		if (kind == Keyframes)
			return timeline(clock);
		return EasingTools.evaluate(easing == null ? Linear : easing, t);
	}

	/**
		Where a keyframes run's first property should be within its segment
		when its timeline is at `at`, by the declared keyframes: the segment
		and its curve there. Null without keyframes. The timeline's own
		timing is judged by `expected`.
	**/
	public function expectedEased(at:Float):Null<{segment:Int, eased:Float}> {
		if (keyframes == null || keyframes.length < 2)
			return null;
		var k = 0;
		while (k < keyframes.length - 2 && keyframes[k + 1].offset <= at)
			k++;
		var a = keyframes[k], b = keyframes[k + 1];
		var span = b.offset - a.offset;
		return {segment: k, eased: EasingTools.evaluate(a.easing, span <= 0 ? 1.0 : (at - a.offset) / span)};
	}

	/** Where a keyframes run's timeline should be at `clock`, as CSS runs one: iterations repeat, a direction reverses some. **/
	function timeline(clock:Float):Float {
		var active = clock - began - delay;
		if (active <= 0 || duration <= 0)
			return reversed(0) ? 1 : 0;
		var total = duration * iterations;
		if (active >= total) {
			var last = Std.int(Math.max(0, Math.ceil(iterations) - 1));
			var partial = iterations - Math.ffloor(iterations);
			var at = partial > 0 ? partial : 1.0;
			return reversed(last) ? 1 - at : at;
		}
		var iteration = Math.ffloor(active / duration);
		var local = (active - iteration * duration) / duration;
		return reversed(Std.int(iteration)) ? 1 - local : local;
	}

	function reversed(iteration:Int):Bool
		return switch direction {
			case "reverse": true;
			case "alternate": iteration % 2 == 1;
			case "alternate-reverse": iteration % 2 == 0;
			case _: false;
		}

	/** Its last drawn rect, if one was observed. **/
	public function lastRect():Null<MotionRect>
		return rects.length == 0 ? null : rects[rects.length - 1];

	/** The same element and property, for spotting one that starts again. **/
	public function key():String
		return '${node == null ? label : haxe.Int64.toStr(node)}|$property';
}
