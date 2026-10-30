import ashui.style.Tw;
import ashui.style.Tw.TwCompletion;

/** Every class Tw.completions lists, and every pattern's example, is accepted by `tw`; the list holds what an editor needs. **/
class TwCompletionCheck {
	/** The completions, and a `tw` call for each class and example, which compile only if `tw` accepts them. **/
	static macro function check() {
		var all = Tw.completions();
		var calls = [];
		var names = new Map<String, TwCompletion>();
		for (c in all) {
			names.set(c.name, c);
			switch c.kind {
				case "class": calls.push(macro ashui.style.Tw.tw($v{c.with == null ? c.name : c.name + " " + c.with}));
				case "pattern": calls.push(macro ashui.style.Tw.tw($v{c.example}));
				case _:
			}
		}
		var missing = [];
		for (needed in ["flex", "p-4", "bg-primary", "rounded-lg", "text-xl", "animate-spin", "transition-colors", "cursor-pointer", "hover:", "dark:", "<state>:<class>", "bg-<color>/<0-100>"])
			if (!names.exists(needed))
				missing.push(needed);
		var undocumented = [for (c in all) if (c.doc == null || c.doc == "") c.name];
		var count = all.length;
		return macro {
			var calls = [$a{calls}];
			{count: $v{count}, called: calls.length, missing: $v{missing}, undocumented: $v{undocumented}};
		};
	}

	static var failures = 0;

	static function verify(name:String, ok:Bool, ?detail:Dynamic) {
		Sys.println((ok ? "ok   " : "FAIL ") + name + (ok || detail == null ? "" : " " + detail));
		if (!ok)
			failures++;
	}

	static function main() {
		var r = check();
		verify("the list is large", r.count > 300, r.count);
		verify("every class and example went through tw", r.called > 300 && r.called < r.count, [r.called, r.count]);
		verify("the expected names are listed", r.missing.length == 0, r.missing);
		verify("every entry has a doc", r.undocumented.length == 0, r.undocumented);
		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
