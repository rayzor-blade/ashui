package ashui.animation;

/**
	A number that springs to each new target on `scheduler`. Reads the
	target once the spring has settled and the scheduler dropped it.
**/
class AnimatedValue {
	final scheduler:AnimationScheduler;
	final config:SpringConfig;
	var springId:Null<Int> = null;
	var current:Float;
	var target:Float;

	/** A value at `initial`, springing as `config` says, `SpringConfig.stiff` by default. **/
	public function new(scheduler:AnimationScheduler, initial:Float, ?config:SpringConfig) {
		this.scheduler = scheduler;
		this.config = config != null ? config : SpringConfig.stiff();
		current = initial;
		target = initial;
	}

	/** Springs toward `target` from where the value is now, mid-flight or not. **/
	public function setTarget(target:Float):Void {
		this.target = target;
		if (springId != null && scheduler.value(springId) != null) {
			scheduler.setTarget(springId, target);
		} else if (target != current) {
			var spring = new Spring(config, springId != null ? get() : current);
			spring.target = target;
			springId = scheduler.register(spring);
		}
	}

	/** The value now. **/
	public function get():Float {
		if (springId == null)
			return current;
		var value = scheduler.value(springId);
		return value != null ? value : target;
	}

	/** Jumps to `value`, dropping any spring. **/
	public function setImmediate(value:Float):Void {
		if (springId != null) {
			scheduler.remove(springId);
			springId = null;
		}
		current = value;
		target = value;
	}

	/** Whether a spring is still moving it. **/
	public function isAnimating():Bool {
		return springId != null && scheduler.isAnimating(springId);
	}
}
