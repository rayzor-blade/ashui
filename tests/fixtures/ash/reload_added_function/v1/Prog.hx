class Box {
	public var value = 7;

	public function new() {}

	public function describe():String {
		var tripled = () -> value * 3;
		return "v1 value=" + value + " tripled=" + tripled();
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
