// Cached Haxe-side decode by native revision check (git-bug 2059910).
import ashui.reactive.Signal;

class SignalStringCache {
	static var failures = 0;
	static var checks = 0;
	static function check(label:String, ok:Bool):Void {
		checks++;
		if (!ok) failures++;
		Sys.println((ok ? "ok   " : "FAIL ") + label);
	}

	// hl.Gc.stats() reports its own prior call's bookkeeping one call late,
	// so a bare before/after pair sees a phantom few dozen bytes on the
	// first use. An extra throwaway call settles it before the real baseline.
	static function allocated():Float {
		hl.Gc.stats();
		return hl.Gc.stats().totalAllocated;
	}

	static function main() {
		var s:Signal<String> = Signal.make("hello");
		check("initial value reads back", s.get() == "hello");

		hl.Gc.major();
		var before = allocated();
		var last = "";
		for (i in 0...2000) last = s.get();
		var after = allocated();
		check("repeated unchanged reads allocate nothing", after == before);
		check("repeated reads keep returning the cached value", last == "hello");

		s.set("world");
		check("a native write is visible on the next read", s.get() == "world");

		hl.Gc.major();
		before = allocated();
		for (i in 0...2000) last = s.get();
		after = allocated();
		check("unchanged reads after a write still allocate nothing", after == before && last == "world");

		var reads = 0;
		var upper = s.computed(v -> { reads++; return v.toUpperCase(); });
		check("a dependent computed sees the current value", upper.get() == "WORLD");
		var afterFirstRead = reads;
		for (i in 0...10) upper.get();
		check("repeated computed reads do not re-run it", reads == afterFirstRead);
		s.set("changed");
		check("a changed write still invalidates a dependent computed", upper.get() == "CHANGED" && reads > afterFirstRead);

		var n:Signal<String> = Signal.make((null:String));
		check("a null initial value reads back null", n.get() == null);
		n.set("now set");
		check("setting a null signal to a value is visible", n.get() == "now set");
		n.set(null);
		check("setting back to null is visible", n.get() == null);

		Sys.println('$checks checks, $failures failures');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
