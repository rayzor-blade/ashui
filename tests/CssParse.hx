import ashui.css.Selector;
import ashui.css.Stylesheet;

/**
	The CSS parser on its own: rules, selectors, declarations, `:root`
	variables, `@keyframes` and how it reports and recovers from errors.
	Pure Haxe, run under `haxe --interp`.
**/
class CssParse {
	static var failures = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		Sys.println((ok ? "ok   " : "FAIL ") + name + (ok || detail == null ? "" : ': $detail'));
		if (!ok)
			failures++;
	}

	static function selectors(css:String):Array<String> {
		var sheet = Stylesheet.parse(css + " {}");
		return sheet.rules.length == 0 ? [sheet.report()] : [for (s in sheet.rules[0].selectors) s.toString()];
	}

	static function specificity(selector:String):Int
		return Stylesheet.parse(selector + " {}").rules[0].selectors[0].specificity();

	static function main() {
		// --- Rules and declarations ---
		var sheet = Stylesheet.parse('
			/* a comment */
			.card { padding: 16px; background: #fff; }
			#save:hover { opacity: 0.8 !important }
			button, .link { color: rgb(0, 0, 255); }
		');
		check("rules in source order", sheet.rules.length == 3 && sheet.rules[0].order == 0 && sheet.rules[2].order == 2, sheet.report());
		var card = sheet.rules[0].declarations;
		check("declarations keep their text", card.length == 2 && card[0].name == "padding" && card[0].value == "16px" && card[1].value == "#fff",
			card);
		var save = sheet.rules[1].declarations[0];
		check("!important is noted and removed", save.important && save.value == "0.8", save);
		check("a value's parentheses hold its commas", sheet.rules[2].declarations[0].value == "rgb(0, 0, 255)");
		check("a selector list gives one selector each", selectors("button, .link").join("|") == "button|.link");
		check("a clean sheet has no diagnostics", sheet.diagnostics.length == 0, sheet.report());
		check("property names are lower case, custom ones kept",
			Stylesheet.parse(".a { COLOR: red; --Brand-Color: blue }").rules[0].declarations.map(d -> d.name).join(",") == "color,--Brand-Color");
		check("a string may hold ; and }", Stylesheet.parse('.a { content: "a;b}c"; color: red }').rules[0].declarations.length == 2);

		// --- Selectors ---
		check("compounds and combinators read back", selectors("nav > ul li + li ~ a.x#y:hover").join("") == "nav > ul li + li ~ a#y.x:hover",
			selectors("nav > ul li + li ~ a.x#y:hover"));
		check("combinators need no spaces", selectors("a>b+c~d").join("") == "a > b + c ~ d", selectors("a>b+c~d"));
		check("states", selectors(".b:hover:active:focus:focus-visible:focus-within:disabled:checked")[0]
			== ".b:hover:active:focus:focus-visible:focus-within:disabled:checked");
		check("structural pseudo-classes", selectors("li:first-child:last-child:only-child:empty")[0] == "li:first-child:last-child:only-child:empty");
		check("an+b forms", selectors("li:nth-child(odd):nth-child(even):nth-child(3):nth-child(-n + 3):nth-last-child(2n-1)")[0]
			== "li:nth-child(2n+1):nth-child(2n+0):nth-child(3):nth-child(-1n+3):nth-last-child(2n-1)",
			selectors("li:nth-child(odd):nth-child(even):nth-child(3):nth-child(-n + 3):nth-last-child(2n-1)"));
		check(":not, :is, :where take selector lists", selectors(".a:not(.b, #c):is(p, span):where(.d .e)")[0] == ".a:not(.b, #c):is(p, span):where(.d .e)",
			selectors(".a:not(.b, #c):is(p, span):where(.d .e)"));
		check(":has takes relative selectors", selectors(".card:has(> img, .icon)")[0] == ".card:has(> img, .icon)", selectors(".card:has(> img, .icon)"));
		check("::placeholder", selectors("#name::placeholder")[0] == "#name::placeholder");
		check("an escaped class name", Stylesheet.parse(".hover\\:bg-x {}").rules[0].selectors[0].subject.classes[0] == "hover:bg-x");
		check("* alone and with more", selectors("*")[0] == "*" && selectors("*.a")[0] == ".a");
		check("type names are lower case", selectors("BUTTON")[0] == "button");
		check("the subject is the last compound", Stylesheet.parse(".a .b > .c {}").rules[0].selectors[0].subject.classes[0] == "c");

		// --- Specificity ---
		check("ids, then classes and pseudo-classes, then types",
			specificity("#a") == 1000000 && specificity(".a.b:hover") == 3000 && specificity("div p") == 2 && specificity("#a .b div") == 1001001,
			[specificity("#a"), specificity(".a.b:hover"), specificity("div p"), specificity("#a .b div")]);
		check(":is and :not count their most specific argument", specificity(".x:is(#a, .b)") == 1001000 && specificity(":not(.a, div)") == 1000,
			[specificity(".x:is(#a, .b)"), specificity(":not(.a, div)")]);
		check(":where counts nothing", specificity(".x:where(#a)") == 1000, specificity(".x:where(#a)"));

		// --- Variables ---
		var vars = Stylesheet.parse(':root { --brand: #3b82f6; --gap: 8px; color: red } .a { --local: 1 }');
		check(":root's custom properties are the sheet's variables", vars.variables.get("brand") == "#3b82f6" && vars.variables.get("gap") == "8px"
			&& !vars.variables.exists("local"), [for (k => v in vars.variables) '$k=$v']);
		check(":root stays a rule too", vars.rules.length == 2 && vars.rules[0].declarations.length == 3);

		// --- Keyframes ---
		var frames = Stylesheet.parse('@keyframes pulse { from { opacity: 1 } 50%, 75% { opacity: 0.5 } to { opacity: 1 } }').keyframes.get("pulse");
		check("@keyframes steps and offsets", frames != null && frames.frames.length == 3 && frames.frames[1].offsets.join(",") == "0.5,0.75"
			&& frames.frames[2].offsets[0] == 1, frames);

		// --- Errors: reported with a position, the rest still parses ---
		var bad = Stylesheet.parse('.a { color: red }\n.b[title] { color: blue }\n.c:nope { x: 1 }\n.d { color }\n.e { color: green }');
		check("a bad rule is skipped and the rest kept", bad.rules.length == 3 && bad.rules[2].selectors[0].toString() == ".e", bad.rules.map(r -> r.selectors[0].toString()));
		check("errors carry lines and columns", bad.diagnostics.length == 3 && bad.diagnostics[0].line == 2 && bad.diagnostics[0].column == 3
			&& bad.diagnostics[1].line == 3 && bad.diagnostics[2].line == 4, bad.report("x.css"));
		check("the report names the file", StringTools.startsWith(bad.report("x.css"), "x.css:2:3: error: attribute selectors"), bad.report("x.css"));
		var skipped = Stylesheet.parse('@media (min-width: 600px) { .a { color: red } }\n.b { color: blue }');
		check("@media is skipped with a warning", skipped.rules.length == 1 && skipped.diagnostics[0].severity == Warning, skipped.report());
		var nested = Stylesheet.parse('.a { color: red; .b { color: blue } padding: 4px }');
		check("a nested rule is skipped, its parent kept", nested.rules[0].declarations.map(d -> d.name).join(",") == "color,padding", nested.report());
		var unclosed = Stylesheet.parse('.a { color: red');
		check("an unclosed block keeps what it has", unclosed.rules.length == 1 && unclosed.rules[0].declarations.length == 1
			&& unclosed.diagnostics[0].severity == Error, unclosed.report());
		check("a pseudo-element other than ::placeholder is refused", Stylesheet.parse('.a::before {}').rules.length == 0);

		// --- Class names, for checking hxx class= ---
		check("every class a selector mentions", Stylesheet.parse('.a .b:not(.c) {} .d:has(> .e) {}').classNames().join(",") == "a,b,c,d,e");

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
