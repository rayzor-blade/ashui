class Box {
	public var value = 7;

	public function new() {}

	// One more closure of a type v1 already has: no type or class layout
	// changes, but every function compiled after it moves to a new findex.
	public function describe():String {
		var doubled = () -> value * 2;
		var tripled = () -> value * 3;
		return "v2 value=" + value + " doubled=" + doubled() + " tripled=" + tripled();
	}
}

class Prog {
	static function main() {
		var box = new Box();
		Sys.println("ready " + box.describe());
		var deadline = Sys.time() + 120.0;
		while (Sys.time() < deadline) {
			if (hl.Api.checkReload()) {
				Sys.println("reloaded " + box.describe());
				return;
			}
			Sys.sleep(0.02);
		}
		Sys.println("no reload");
	}
}
