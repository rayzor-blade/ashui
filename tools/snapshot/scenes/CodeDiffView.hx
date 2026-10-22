import ashui.components.Badge;
import ashui.components.CodeDiff;
import ashui.core.render.Snapshot;
import ashui.icons.Remix;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Two versions of a Haxe class compared, inline or side by side (LAYOUT=split), in either scheme (SCHEME=light), with the diff's own icons or Remix's (ICONS=remix) (ed51114). **/
class CodeDiffView {
	static final BEFORE = 'package app;\n\nimport haxe.Json;\n\n/** Counts what it is given. **/\nclass Counter {\n    var total = 0;\n    var names:Array<String> = [];\n\n    public function new() {}\n\n    public function add(name:String, amount:Int):Void {\n        total += amount;\n        names.push(name);\n    }\n\n    public function reset():Void {\n        total = 0;\n        names = [];\n    }\n\n    // Lines that do not change, enough of them to fold.\n    function a() return 1;\n    function b() return 2;\n    function c() return 3;\n    function d() return 4;\n    function e() return 5;\n    function f() return 6;\n    function g() return 7;\n    function h() return 8;\n\n    public function describe():String {\n        return "total: " + total;\n    }\n\n    public function dump():String {\n        return Json.stringify(names);\n    }\n}\n';
	static final AFTER = 'package app;\n\nimport haxe.Json;\nimport haxe.ds.Map;\n\n/** Counts what it is given, by name. **/\nclass Counter {\n    var total = 0;\n    var counts:Map<String, Int> = new Map();\n\n    public function new() {}\n\n    public function add(name:String, amount:Int = 1):Void {\n        total += amount;\n        counts.set(name, count(name) + amount);\n    }\n\n    public function count(name:String):Int {\n        return counts.exists(name) ? counts.get(name) : 0;\n    }\n\n    public function reset():Void {\n        total = 0;\n        counts = new Map();\n    }\n\n    // Lines that do not change, enough of them to fold.\n    function a() return 1;\n    function b() return 2;\n    function c() return 3;\n    function d() return 4;\n    function e() return 5;\n    function f() return 6;\n    function g() return 7;\n    function h() return 8;\n\n    public function describe():String {\n        return "total: " + total + " in " + Lambda.count(counts) + " names";\n    }\n\n    public function dump():String {\n        return Json.stringify(counts);\n    }\n}\n';

	static function main() {
		var light = Sys.getEnv("SCHEME") == "light", split = Sys.getEnv("LAYOUT") == "split", remix = Sys.getEnv("ICONS") == "remix";
		ThemeState.init(DefaultTheme.bundle(), light ? Light : Dark);
		var original = signal(BEFORE), modified = signal(AFTER), diff = new Ref<CodeDiff>();
		var build = () -> <div class="bg-background p-6 flex-col gap-4" width={split ? 1100 : 820} height={560}>
			<div class="flex-row items-center justify-between"><text class="text-lg font-semibold">Counter.hx</text><badge variant={Secondary}>{split ? "Side by side" : "Inline"}</badge></div>
			<code-diff ref={diff} original={original} modified={modified} language="haxe" layout={split ? "split" : "inline"} navigation={true} icons={remix ? {previous: Remix.ARROW_UP_S_LINE, next: Remix.ARROW_DOWN_S_LINE, folded: Remix.EXPAND_UP_DOWN_LINE, stage: Remix.ADD_LINE, revert: Remix.ARROW_GO_BACK_LINE} : {}} class="grow min-h-0" height={0}
				onStage={c -> {}} onRevert={c -> {}} />
		</div>;
		// The first frame is the top; the second has gone to the last change, past the folded run of unchanged lines; the third has the pointer over a change, which shows its buttons.
		Snapshot.sequence("CodeDiffView-" + (split ? "split" : "inline") + (light ? "-light" : "") + (remix ? "-remix" : ""), split ? 1100 : 820, 560, build, 30, 16, (frame, tree, root) -> {
			if (frame == 1)
				for (_ in 0...6)
					diff.get().goToChange(1);
			if (frame == 2)
				ashui.input.Pointer.move(tree, split ? 800 : 400, split ? 150 : 108);
			// The revert button is the right-hand one of the two, 12 px from the edge of the pane.
			if (frame == 3)
				ashui.input.Pointer.move(tree, split ? 1051 : 771, split ? 150 : 108);
		}, light ? 0xf8fafc : 0x0e1420, 1.0, Sys.getEnv("SCALE") == null ? 1.0 : Std.parseFloat(Sys.getEnv("SCALE")));
	}
}
