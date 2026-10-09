package ashui.animation;

/**
	Advances every registered spring together and drops each one as it
	settles. Driven by `tick`, from a frame loop or from `run` on a thread
	of its own.

	It also keeps timers: a callback due at a wall-clock time, such as a
	caret's next blink. A timer is not animation, so a window waiting on
	one sleeps until it is due (`untilNextTimer`) instead of drawing frames.
**/
class AnimationScheduler {
	/** The scheduler transitions run on; a window's loop ticks it. **/
	public static final main = new AnimationScheduler();

	final springs = new Map<Int, Spring>();
	/** Each spring's move being recorded, while a motion trace records. **/
	final springTracks = new Map<Int, {track:ashui.debug.MotionTrack, start:Float, target:Float}>();
	/** Called each tick with the seconds passed; dropped once they return false. **/
	final tickers:Array<Float->Bool> = [];
	var nextId = 1;
	var running = false;
	final timers:Array<Timer> = [];
	var realtime = false;
	var tickedAt = 0.0;
	#if target.threaded
	final lock = new sys.thread.Mutex();
	#end

	public function new() {}

	/** `f` with the springs to itself: `run` ticks them from another thread. **/
	inline function locked<T>(f:() -> T):T {
		#if target.threaded
		lock.acquire();
		var result = try f() catch (e:haxe.Exception) {
			lock.release();
			throw e;
		}
		lock.release();
		return result;
		#else
		return f();
		#end
	}

	/** Starts advancing `spring`; its id, for reading and retargeting it. **/
	public function register(spring:Spring):Int {
		var id = locked(() -> {
			var id = nextId++;
			springs.set(id, spring);
			traceSpring(id, spring);
			id;
		});
		ashui.core.Work.notify();
		return id;
	}

	/** `id`'s value, or null once it has settled and been dropped. **/
	public function value(id:Int):Null<Float> {
		return locked(() -> {
			var spring = springs.get(id);
			spring == null ? null : spring.value;
		});
	}

	/** Points `id`'s spring at `target`, from where it is. **/
	public function setTarget(id:Int, target:Float):Void {
		locked(() -> {
			var spring = springs.get(id);
			if (spring != null) {
				spring.target = target;
				traceSpring(id, spring);
			}
			null;
		});
		ashui.core.Work.notify();
	}

	/** Stops advancing `id`'s spring and forgets it: `value` gives null after. **/
	public function remove(id:Int):Void {
		locked(() -> {
			var traced = springTracks.get(id);
			if (traced != null) {
				traced.track.finish(Interrupted);
				springTracks.remove(id);
			}
			springs.remove(id);
		});
	}

	/** Starts recording `spring`'s move toward its target, while a motion trace records; a move already recorded ends, interrupted. **/
	function traceSpring(id:Int, spring:Spring):Void {
		if (ashui.debug.MotionTrace.current == null)
			return;
		var was = springTracks.get(id);
		if (was != null)
			was.track.finish(Interrupted);
		var span = spring.target - spring.value;
		var track = ashui.debug.MotionTrace.begin(Spring, null, null, "value", Std.string(Math.round(spring.value * 1000) / 1000),
			Std.string(Math.round(spring.target * 1000) / 1000), 0, 0, null, spring.config, 'spring #$id');
		if (track == null)
			return;
		// Its speed at release, in moves per second, for the closed form it is checked against.
		track.v0 = span == 0 ? 0 : spring.velocity / span;
		springTracks.set(id, {track: track, start: spring.value, target: spring.target});
	}

	/** Whether `id`'s spring is still moving. **/
	public function isAnimating(id:Int):Bool {
		return locked(() -> {
			var spring = springs.get(id);
			spring != null && !spring.isSettled();
		});
	}

	/** Calls `callback` once `seconds` from now, at the first tick after. **/
	public function after(seconds:Float, callback:Void->Void):Timer {
		var timer = locked(() -> {
			var timer = new Timer(time() + seconds, callback);
			timers.push(timer);
			timer;
		});
		ashui.core.Work.notify();
		return timer;
	}

	/** A native loop enables this so timers created while it sleeps start now. Offscreen ticks stay deterministic. **/
	public function useRealtime(enabled:Bool):Void {
		locked(() -> {
			realtime = enabled;
			tickedAt = haxe.Timer.stamp();
			null;
		});
	}

	/** Called under the scheduler lock. **/
	inline function time():Float
		return clock + (realtime ? Math.max(0, haxe.Timer.stamp() - tickedAt) : 0);

	/** Seconds until the next timer is due, at least 0; null with none waiting. **/
	public function untilNextTimer():Null<Float> {
		return locked(() -> {
			var soonest:Null<Float> = null;
			for (t in timers)
				if (!t.cancelled && (soonest == null || t.at < soonest))
					soonest = t.at;
			soonest == null ? null : Math.max(0, soonest - time());
		});
	}

	/** Whether any spring or ticker is running, so the frame loop should keep drawing. **/
	public function hasActive():Bool {
		return locked(() -> springs.keys().hasNext() || tickers.length > 0);
	}

	/** Calls `ticker` every tick until it returns false. **/
	public function addTicker(ticker:Float->Bool):Void {
		locked(() -> {
			tickers.push(ticker);
			null;
		});
		ashui.core.Work.notify();
	}

	/**
		The timers' clock, in seconds: what the ticks have added up to, so a
		timer is due after the time ticked, as an animation is, and a program
		that ticks a fixed step, a test or an offscreen render, sees the same
		timers fire on every run.
	**/
	public var clock(default, null) = 0.0;

	/**
		Advances every spring `dt` seconds, dropping those that settle, and
		the timers' clock `elapsed` seconds, `dt` unless given: a frame loop
		that limits its step still passes the whole time slept, so a timer it
		woke for is due.
	**/
	public function tick(dt:Float, ?elapsed:Float):Void {
		locked(() -> {
			clock += elapsed == null ? dt : elapsed;
			if (realtime)
				tickedAt = haxe.Timer.stamp();
			var settled = [];
			for (id => spring in springs) {
				spring.step(dt);
				var traced = springTracks.get(id);
				if (traced != null) {
					var span = traced.target - traced.start;
					traced.track.sample(span == 0 ? 1 : (spring.value - traced.start) / span, 0, Std.string(Math.round(spring.value * 1000) / 1000));
				}
				if (spring.isSettled())
					settled.push(id);
			}
			for (id in settled) {
				springs.remove(id);
				var traced = springTracks.get(id);
				if (traced != null) {
					traced.track.finish(Completed);
					springTracks.remove(id);
				}
			}
			null;
		});
		// Outside the lock: a ticker may add another.
		var running = locked(() -> tickers.splice(0, tickers.length));
		var kept = [for (ticker in running) if (ticker(dt)) ticker];
		locked(() -> {
			for (i in 0...kept.length)
				tickers.insert(i, kept[i]);
			null;
		});
		// Due timers, after the tickers, so one a timer starts begins at the next tick
		// rather than taking this tick's whole step at once. Outside the lock: a
		// callback may set another.
		var now = clock;
		var due = locked(() -> {
			var fire = [for (t in timers) if (t.at <= now || t.cancelled) t];
			for (t in fire)
				timers.remove(t);
			fire;
		});
		for (t in due)
			if (!t.cancelled)
				t.callback();
	}

	#if target.threaded
	/** Ticks on a thread of its own every `interval` seconds until `stop`. **/
	public function run(interval = 1.0 / 120.0):Void {
		if (running)
			return;
		running = true;
		sys.thread.Thread.create(() -> {
			var last = haxe.Timer.stamp();
			while (running) {
				Sys.sleep(interval);
				var now = haxe.Timer.stamp();
				tick(now - last);
				last = now;
			}
		});
	}
	#end

	/** Stops `run`'s thread after its current tick. **/
	public function stop():Void {
		running = false;
	}
}

/** A callback `AnimationScheduler.after` will call; `cancel` stops it. **/
class Timer {
	/** When it is due, on the scheduler's `clock`. **/
	public final at:Float;
	public final callback:Void->Void;
	public var cancelled(default, null) = false;

	@:allow(ashui.animation.AnimationScheduler)
	function new(at:Float, callback:Void->Void) {
		this.at = at;
		this.callback = callback;
	}

	public function cancel():Void {
		cancelled = true;
		ashui.core.Work.notify();
	}
}
