package dashboard;

/** A colour the car comes in. **/
class Paint {
	public static final ALL:Array<Paint> = [
		new Paint("Silver", 0xb9bec6, 0.35),
		new Paint("Midnight", 0x23283a, 0.5),
		new Paint("Crimson", 0xb3262e, 0.3),
		new Paint("Ocean", 0x2f6fb5, 0.4),
		new Paint("Forest", 0x2f6b49, 0.3),
		new Paint("Pearl", 0xe9e7e1, 0.2)
	];

	public final name:String;
	public final color:Int;
	public final metallic:Float;

	public function new(name:String, color:Int, metallic:Float) {
		this.name = name;
		this.color = color;
		this.metallic = metallic;
	}
}
