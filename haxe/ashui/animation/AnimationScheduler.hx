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
	/** Called each tick with the seconds passed; dropped once they return false. **/
	final tickers:Array<Float->Bool> = [];
	var nextId = 1;
	var running = false;
	final timers:Array<Timer> = [];
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
		return locked(() -> {
			var id = nextId++;
			springs.set(id, spring);
			id;
		});
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
			if (spring != null)
				spring.target = target;
			null;
		});
	}

	/** Stops advancing `id`'s spring and forgets it: `value` gives null after. **/
	public function remove(id:Int):Void {
		locked(() -> springs.remove(id));
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
		var timer = new Timer(haxe.Timer.stamp() + seconds, callback);
		locked(() -> {
			timers.push(timer);
			null;
		});
		return timer;
	}

	/** Seconds until the next timer is due, at least 0; null with none waiting. **/
	public function untilNextTimer():Null<Float> {
		return locked(() -> {
			var soonest:Null<Float> = null;
			for (t in timers)
				if (!t.cancelled && (soonest == null || t.at < soonest))
					soonest = t.at;
			soonest == null ? null : Math.max(0, soonest - haxe.Timer.stamp());
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
	}

	/** Advances every spring `dt` seconds, dropping those that settle. **/
	public function tick(dt:Float):Void {
		locked(() -> {
			var settled = [];
			for (id => spring in springs) {
				spring.step(dt);
				if (spring.isSettled())
					settled.push(id);
			}
			for (id in settled)
				springs.remove(id);
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
		var now = haxe.Timer.stamp();
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
	/** When it is due, in `haxe.Timer.stamp` seconds. **/
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
	}
}
