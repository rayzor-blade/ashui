package ashui.animation;

/**
	Advances every registered spring together and drops each one as it
	settles. Driven by `tick`, from a frame loop or from `run` on a thread
	of its own.
**/
class AnimationScheduler {
	final springs = new Map<Int, Spring>();
	var nextId = 1;
	var running = false;
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

	public function setTarget(id:Int, target:Float):Void {
		locked(() -> {
			var spring = springs.get(id);
			if (spring != null)
				spring.target = target;
			null;
		});
	}

	public function remove(id:Int):Void {
		locked(() -> springs.remove(id));
	}

	public function isAnimating(id:Int):Bool {
		return locked(() -> {
			var spring = springs.get(id);
			spring != null && !spring.isSettled();
		});
	}

	public function hasActive():Bool {
		return locked(() -> springs.keys().hasNext());
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

	public function stop():Void {
		running = false;
	}
}
