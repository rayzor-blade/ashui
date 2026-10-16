// A disabled debug probe reads the environment once, not per lookup (git-bug 9764792).
import ashui.theme.ColorToken;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

class ThemeColorDebugProbe {
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
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var theme = ThemeState.get();
		var primary = theme.color(Primary);
		check("a token resolves to a colour", primary.a > 0);

		hl.Gc.major();
		var before = allocated();
		for (i in 0...2000) theme.color(Primary);
		var after = allocated();
		check("repeated lookups with debugging disabled allocate nothing", after == before);

		Sys.println('$checks checks, $failures failures');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
