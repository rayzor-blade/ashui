class Box {
	public function new() {}
}

/** A failed cast inside try: Std.isOfType given an Int where a class belongs. **/
class Trap {
	static function check(v:Dynamic, t:Dynamic):Bool
		return Std.isOfType(v, t);

	static function main() {
		try {
			Sys.println("isOfType: " + check(new Box(), 3));
		} catch (e:Dynamic) {
			Sys.println("caught: " + e);
		}
		Sys.println("after");
	}
}
