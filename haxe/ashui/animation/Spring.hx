package ashui.animation;

/**
	A damped spring pulling a value toward a target, integrated with RK4 in
	steps of at most 1/120 s. Settled within 0.01 of the target at a speed
	under 0.1.
**/
class Spring {
	static inline var EPSILON = 0.01;
	static inline var VELOCITY_EPSILON = 0.1;
	static inline var MAX_SUBSTEP = 1.0 / 120.0;

	public final config:SpringConfig;
	public var value(default, null):Float;
	public var velocity(default, null) = 0.0;
	public var target:Float;
	public var paused(default, null) = false;

	public function new(config:SpringConfig, initial:Float) {
		this.config = config;
		value = initial;
		target = initial;
	}

	public function isSettled():Bool {
		return paused || (Math.abs(value - target) < EPSILON && Math.abs(velocity) < VELOCITY_EPSILON);
	}

	public function pause():Void
		paused = true;

	public function resume():Void
		paused = false;

	/** Advances `dt` seconds; a settled spring snaps to its target. **/
	public function step(dt:Float):Void {
		if (paused)
			return;
		if (isSettled()) {
			value = target;
			velocity = 0;
			return;
		}
		var substeps = Std.int(Math.max(1, Math.ceil(dt / MAX_SUBSTEP)));
		var h = dt / substeps;
		for (_ in 0...substeps)
			rk4(h);
	}

	function rk4(dt:Float):Void {
		var k1v = acceleration(value, velocity);
		var k1x = velocity;
		var k2v = acceleration(value + k1x * dt * 0.5, velocity + k1v * dt * 0.5);
		var k2x = velocity + k1v * dt * 0.5;
		var k3v = acceleration(value + k2x * dt * 0.5, velocity + k2v * dt * 0.5);
		var k3x = velocity + k2v * dt * 0.5;
		var k4v = acceleration(value + k3x * dt, velocity + k3v * dt);
		var k4x = velocity + k3v * dt;
		velocity += (k1v + 2 * k2v + 2 * k3v + k4v) * dt / 6;
		value += (k1x + 2 * k2x + 2 * k3x + k4x) * dt / 6;
	}

	inline function acceleration(x:Float, v:Float):Float {
		return (-config.stiffness * (x - target) - config.damping * v) / config.mass;
	}
}
