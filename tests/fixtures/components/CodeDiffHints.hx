import ashui.components.CodeDiff;
import ashui.components.code.CodeDiffHint;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Reactive annotations follow source sides and pooled changed rows, and leave no hooks on disposal. */
class CodeDiffHints {
	static function check(ok:Bool, why:String):Void {
		if (!ok)
			throw why;
	}

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		run(false);
		run(true);
		Sys.println("CodeDiff hints: inline/split side mapping, context exclusion, reactive replacement, scrolling and cleanup passed");
	}

	static function run(verify:Bool):Void {
		var tree = new LayoutTree(), stop:Void->Void = null;
		var hints = Signal.make(([
			{side: "original", line: 1, text: "Ada"},
			{side: "modified", line: 1, text: "Bob"},
			{side: "modified", line: 0, text: "Never on context"}
		] : Array<CodeDiffHint>));
		var layout = Signal.make("inline"),
			original = Signal.make("same\nold\nsame"),
			modified = Signal.make("same\nnew\nsame");
		var before = LayoutTree.flushHooks.length;
		var root = Owner.root(tree, cleanup -> {
			stop = cleanup;
			return
				<div width={640} height={200}><code-diff original={original} modified={modified} lineHints={hints} layout={layout} context={-1} width={640} height={200}/></div>;
		});
		function settle():Void
			for (_ in 0...8) {
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 640, 200);
			}
		function labels():Array<String>
			return [
				for (id in Css.query(tree, root.node.id, ".ui-code-diff-hint-text")) ashui.ui.Text.at(id).text()
			];
		settle();
		check(labels().join(",") == "— Ada,— Bob", "Inline labels lost source-side mapping: " + labels());
		layout.set("split");
		settle();
		check(labels().join(",") == "— Ada,— Bob", "Split labels lost source-side mapping: " + labels());
		hints.set([
			{
				side: "modified",
				line: 1,
				text: "raikage",
				detail: "Jam participant"
			}
		]);
		settle();
		check(labels().join(",") == "— raikage", "Replacing hints retained an old author: " + labels());
		var a = [for (i in 0...500) "line " + i], b = a.copy();
		b[480] = "changed";
		original.set(a.join("\n"));
		modified.set(b.join("\n"));
		hints.set([{side: "modified", line: 480, text: "Later author"}]);
		settle();
		// With unfolded long input, no offscreen hint should mount.
		check(labels().length == 0, "Offscreen hints mounted");
		hints.set([]);
		settle();
		check(labels().length == 0, "Clearing hints retained labels");
		stop();
		tree.dispose();
		if (verify)
			check(LayoutTree.flushHooks.length == before, "Diff hints retained a flush hook");
	}
}
