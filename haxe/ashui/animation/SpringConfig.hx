package ashui.animation;

/** A spring's stiffness, damping and mass. **/
@:structInit
final class SpringConfig {
	public final stiffness:Float;
	public final damping:Float;
	public final mass:Float;

	public function new(stiffness:Float, damping:Float, mass:Float) {
		this.stiffness = stiffness;
		this.damping = damping;
		this.mass = mass;
	}

	/** Slow and soft; overshoots a little. **/
	public static function gentle():SpringConfig
		return new SpringConfig(120, 14, 1);

	public static function wobbly():SpringConfig
		return new SpringConfig(180, 12, 1);

	/** The default. **/
	public static function stiff():SpringConfig
		return new SpringConfig(400, 30, 1);

	public static function snappy():SpringConfig
		return new SpringConfig(600, 40, 1);

	public static function molasses():SpringConfig
		return new SpringConfig(100, 20, 1);

	public function criticalDamping():Float
		return 2 * Math.sqrt(stiffness * mass);

	public function isUnderdamped():Bool
		return damping < criticalDamping();

	public function isCriticallyDamped():Bool
		return Math.abs(damping - criticalDamping()) < 0.01;

	public function isOverdamped():Bool
		return damping > criticalDamping();
}
