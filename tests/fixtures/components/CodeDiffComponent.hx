import ashui.components.CodeDiff;
import ashui.components.code.CodeDiffer;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** The diff view: its rows by layout, the placeholders, navigation, supplied changes, scroll sync, a worker comparison and cleanup. **/
class CodeDiffComponent {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	/** A one-stroke icon as SVG markup, which an icon prop takes. **/
	static function mark(path:String):String
		return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="$path"/></svg>';

	/** How many icon elements draw the document of this markup. **/
	static function drawn(markup:String):Int {
		var document = ashui.svg.SvgDocument.parse(markup), n = 0;
		for (_ => svg in @:privateAccess ashui.ui.Svg.intrinsic)
			if (svg.document == document)
				n++;
		return n;
	}

	static function kinds(rows:Array<{row:Int, kind:String, text:String, oldNumber:String, newNumber:String}>):String
		return [for (r in rows) r.kind].join(",");

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		// One view made and disposed first, so the hooks the framework registers once, for its own use, are in the counts.
		var warm = new LayoutTree(), warmStop:Void->Void = null;
		var warmRoot = Owner.root(warm, stop -> {
			warmStop = stop;
			return <div width={200} height={100}><code-diff original={signal("a")} modified={signal("b")} navigation={true} width={200} height={100} /></div>;
		});
		for (_ in 0...4) {
			Css.update();
			warm.flush();
			warm.computeLayout(warmRoot.node, 200, 100);
		}
		warmStop();
		warm.dispose();
		var hooks = LayoutTree.layoutHooks.length, restyles = Css.restyled.length;
		var before = "class A {\n  var x = 1;\n  var y = 2;\n}\n", after = "class A {\n  var x = 10;\n  var y = 2;\n  var z = 3;\n}\n";
		var original = signal(before), modified = signal(after), layout = signal("inline");
		var diff = new Ref<CodeDiff>(), tree = new LayoutTree(), dispose:Void->Void = null;
		var root = Owner.root(tree, stop -> {
			dispose = stop;
			return <div width={640} height={300}>
				<code-diff ref={diff} original={original} modified={modified} language="haxe" layout={layout} width={640} height={300} />
			</div>;
		});
		function settle()
			for (_ in 0...8) {
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 640, 300);
			}
		settle();
		var d = diff.get();
		check("two changes are counted", d.changeCount.get() == 2, d.changes());
		var shown = d.shownNow()[0];
		check("inline, the rows are context, a removed and an added line, context, an added line, context",
			kinds(shown) == "context,removed,added,context,added,context,context", kinds(shown));
		check("the removed line has an original number and no modified number, the added one the reverse",
			shown[1].oldNumber == "2" && shown[1].newNumber == "" && shown[2].oldNumber == "" && shown[2].newNumber == "2", shown[1]);
		check("rows show the text of their lines", shown[1].text == "  var x = 1;" && shown[2].text == "  var x = 10;", [shown[1].text, shown[2].text]);

		layout.set("split");
		settle();
		var panes = d.shownNow();
		check("a layout change makes two panes", panes.length == 2);
		check("side by side, the original pane has a filler opposite the added line", kinds(panes[0]) == "context,removed,context,filler,context,context", kinds(panes[0]));
		check("and the modified pane has the added lines", kinds(panes[1]) == "context,added,context,added,context,context", kinds(panes[1]));
		check("each pane numbers its own side", panes[0][1].oldNumber == "2" && panes[1][1].newNumber == "2" && panes[0][1].newNumber == "" && panes[1][1].oldNumber == "");

		// Scroll sync: the vertical scroll of one pane is the other's.
		var long = [for (i in 0...400) 'line $i'], longEdited = long.copy();
		for (i in [20, 200, 380])
			longEdited[i] = 'changed $i';
		original.set(long.join("\n"));
		modified.set(longEdited.join("\n"));
		settle();
		check("three changes in four hundred lines", d.changeCount.get() == 3, d.changes());
		var rows = d.shownNow()[0];
		check("context of three lines folds the runs between the changes", [for (r in rows) if (r.kind == "placeholder") 1].length >= 1, kinds(rows));
		check("a placeholder says how many lines it hides", [for (r in rows) if (r.kind == "placeholder") r.text][0].indexOf("unchanged lines") > 0, [for (r in rows) r.text]);
		layout.set("inline");
		settle();
		d.goToChange(1);
		settle();
		check("going to the next change makes it current", d.currentChange.get() == 0, d.currentChange.get());
		d.goToChange(1);
		d.goToChange(1);
		check("and the one after, and the one after that", d.currentChange.get() == 2, d.currentChange.get());
		d.goToChange(1);
		check("past the last change it wraps to the first", d.currentChange.get() == 0, d.currentChange.get());
		d.goToChange(-1);
		check("before the first it wraps to the last", d.currentChange.get() == 2, d.currentChange.get());
		d.showChange(1);
		check("showChange makes a change the current one", d.currentChange.get() == 1, d.currentChange.get());
		d.showChange(99);
		check("an index past the last is brought to the last", d.currentChange.get() == 2, d.currentChange.get());
		d.showChange(-5);
		check("and one before the first to the first", d.currentChange.get() == 0, d.currentChange.get());
		settle();
		d.nextChange();
		check("nextChange goes on from the current change", d.currentChange.get() == 1, d.currentChange.get());
		d.previousChange();
		check("previousChange goes back", d.currentChange.get() == 0, d.currentChange.get());
		d.reveal(100);
		settle();
		var around = [for (r in d.shownNow()[0]) r.text];
		check("revealing a folded line opens the run that hid it and shows the line", around.indexOf("line 100") >= 0, around.slice(0, 6));
		d.collapseAll();
		settle();
		check("collapsing folds it again", around != null && [for (r in d.shownNow()[0]) r.text].indexOf("line 100") < 0);
		d.expandAll();
		settle();
		check("expanding opens everything", [for (r in d.shownNow()[0]) r.kind].indexOf("placeholder") < 0);

		// Changes the caller supplies are used when they fit the texts and ignored when they do not.
		var given = signal(([{originalStart: 1, originalLines: 1, modifiedStart: 1, modifiedLines: 1}] : Array<ashui.components.code.CodeDiffer.CodeChange>));
		var tree2 = new LayoutTree(), diff2 = new Ref<CodeDiff>(), dispose2:Void->Void = null;
		var root2 = Owner.root(tree2, stop -> {
			dispose2 = stop;
			return <div width={640} height={300}>
				<code-diff ref={diff2} original={signal("a\nb\nc")} modified={signal("a\nB\nc")} hunks={given} context={-1} width={640} height={300} />
			</div>;
		});
		function settle2()
			for (_ in 0...8) {
				Css.update();
				tree2.flush();
				tree2.computeLayout(root2.node, 640, 300);
			}
		settle2();
		check("supplied changes that fit are the changes", diff2.get().changeCount.get() == 1 && diff2.get().changes()[0].originalStart == 1);
		given.set([{originalStart: 0, originalLines: 1, modifiedStart: 0, modifiedLines: 1}]);
		settle2();
		check("supplied changes that do not fit are ignored, and the texts are compared", diff2.get().changeCount.get() == 1 && diff2.get().changes()[0].originalStart == 1, diff2.get().changes());
		dispose2();
		tree2.dispose();

		// The navigation bar says where the view is among the changes, and its buttons step through them.
		var staged:Array<Int> = [], reverted:Array<Int> = [], copied:Array<Int> = [];
		var tree3 = new LayoutTree(), diff3 = new Ref<CodeDiff>(), dispose3:Void->Void = null;
		var root3 = Owner.root(tree3, stop -> {
			dispose3 = stop;
			return <div width={640} height={300}>
				<code-diff ref={diff3} original={signal(long.join("\n"))} modified={signal(longEdited.join("\n"))} navigation={true}
					onStage={c -> staged.push(c.modifiedStart)} onRevert={c -> reverted.push(c.modifiedStart)}
					hunkActions={[{label: "Copy", icon: mark("M9 7 L4 12 L9 17"), run: c -> copied.push(c.modifiedStart)}]} width={640} height={300} />
			</div>;
		});
		function settle3()
			for (_ in 0...8) {
				Css.update();
				tree3.flush();
				tree3.computeLayout(root3.node, 640, 300);
			}
		settle3();
		function barText():String {
			var found = Css.query(tree3, root3.node.id, ".ui-code-diff-bar-text");
			return found.length == 0 ? "(none)" : ashui.ui.Text.at(found[0]).text();
		}
		check("the bar counts the changes before any is gone to", barText() == "3 changes", barText());
		diff3.get().nextChange();
		check("and says which one the view is at after", barText() == "1 of 3", barText());
		diff3.get().nextChange();
		check("and follows", barText() == "2 of 3", barText());
		check("it has a button for each way", Css.query(tree3, root3.node.id, ".ui-code-diff-nav").length == 2);

		// Alignment: what shares a line shares its centre, to within a pixel and a half.
		function bounds(selector:String):Array<ashui.layout.Bounds> {
			var found = [];
			for (id in Css.query(tree3, root3.node.id, selector)) {
				var b = tree3.getBounds(new ashui.layout.Node(id));
				if (b != null)
					found.push(b);
			}
			return found;
		}
		function centre(b:ashui.layout.Bounds):Float
			return b.y + b.height / 2;
		var bar = bounds(".ui-code-diff-bar")[0];
		var offBar = [for (selector in [".ui-code-diff-bar-text", ".ui-code-diff-nav", ".ui-code-diff-nav-glyph"]) for (b in bounds(selector)) if (Math.abs(centre(b) - centre(bar)) > 1.5) selector + " " + (centre(b) - centre(bar))];
		check("in the bar, the text, the buttons and their icons are centred on it", bar != null && offBar.length == 0, offBar);
		var nav = bounds(".ui-code-diff-nav"), glyphs = bounds(".ui-code-diff-nav-glyph");
		check("the two buttons are side by side on one line, each with its icon in the middle", Math.abs(centre(nav[0]) - centre(nav[1])) < 0.5 && glyphs.length == 2
			&& Math.abs((glyphs[0].x + glyphs[0].width / 2) - (nav[0].x + nav[0].width / 2)) < 1 && Math.abs((glyphs[1].x + glyphs[1].width / 2) - (nav[1].x + nav[1].width / 2)) < 1, [nav, glyphs]);
		var rows = bounds(".ui-code-diff-row");
		function rowOf(y:Float):Null<ashui.layout.Bounds> {
			for (r in rows)
				if (y >= r.y && y < r.y + r.height)
					return r;
			return null;
		}
		var offFold = [];
		var folded = 0;
		for (selector in [".ui-code-diff-fold-icon", ".ui-code-diff-action", ".ui-code-diff-action-glyph"])
			for (b in bounds(selector)) {
				var row = rowOf(centre(b));
				if (row == null)
					continue;
				folded++;
				if (Math.abs(centre(b) - centre(row)) > 1.5)
					offFold.push(selector + " " + (centre(b) - centre(row)));
			}
		check("a folded run's icon and a change's buttons are centred in their row", folded > 0 && offFold.length == 0, [folded, offFold]);
		var numbers = [for (n in bounds(".ui-code-diff-number")) n], signs = bounds(".ui-code-diff-sign"), off = [];
		for (b in numbers.concat(signs)) {
			var row = rowOf(centre(b));
			if (row != null && Math.abs(centre(b) - centre(row)) > 1.5)
				off.push(centre(b) - centre(row));
		}
		check("line numbers and signs are centred in their rows", numbers.length > 0 && off.length == 0, off);
		check("a custom hunk action draws the icon it is given", drawn(mark("M9 7 L4 12 L9 17")) > 0);
		function buttons(label:String)
			return [for (id in Css.query(tree3, root3.node.id, '.ui-code-diff-action[aria-label="$label"]')) tree3.getBounds(new ashui.layout.Node(id))];
		check("onStage and onRevert put a Stage and a Revert button on each row slot, and a custom action follows them", buttons("Stage change").length > 0 && buttons("Revert change").length == buttons("Stage change").length && buttons("Copy").length == buttons("Stage change").length, [buttons("Stage change").length, buttons("Revert change").length, buttons("Copy").length]);
		// A press on a button gives the app the change: the buttons are shown on the first row of the change in view.
		diff3.get().showChange(2);
		settle3();
		var third = diff3.get().changes()[2];
		var stage:Array<ashui.layout.Bounds> = [];
		for (id in Css.query(tree3, root3.node.id, '.ui-code-diff-actions[data-first="true"] .ui-code-diff-action[aria-label="Stage change"]')) {
			var b = tree3.getScrolledBounds(new ashui.layout.Node(id));
			if (b != null && b.y > 40 && b.y < 300)
				stage.push(b);
		}
		check("the Stage button of the change in view is found", stage.length == 1, stage.length);
		var pressed = stage[0];
		// The pointer over the row shows its buttons; the press then lands on one.
		ashui.input.Pointer.move(tree3, pressed.x - 40, pressed.y + pressed.height / 2);
		settle3();
		ashui.input.Pointer.move(tree3, pressed.x + pressed.width / 2, pressed.y + pressed.height / 2);
		settle3();
		ashui.input.Pointer.press(tree3);
		ashui.input.Pointer.release(tree3);
		settle3();
		check("pressing Stage calls onStage with the change", staged.length == 1 && reverted.length == 0 && copied.length == 0, [staged, reverted, copied]);
		function press(label:String):Void {
			var found:Array<ashui.layout.Bounds> = [];
			for (id in Css.query(tree3, root3.node.id, '.ui-code-diff-actions[data-first="true"] .ui-code-diff-action[aria-label="$label"]')) {
				var b = tree3.getScrolledBounds(new ashui.layout.Node(id));
				if (b != null && b.y > 40 && b.y < 300)
					found.push(b);
			}
			var b = found[0];
			ashui.input.Pointer.move(tree3, b.x + b.width / 2, b.y + b.height / 2);
			settle3();
			ashui.input.Pointer.press(tree3);
			ashui.input.Pointer.release(tree3);
			settle3();
		}
		// The current change's buttons are shown without the pointer, and Enter on a focused one presses it.
		ashui.input.Pointer.move(tree3, 5, 5);
		settle3();
		var shownCurrent = [for (id in Css.query(tree3, root3.node.id, '.ui-code-diff-actions[data-current="true"]')) id];
		check("the current change's buttons are marked to stay shown", shownCurrent.length == 1, shownCurrent.length);
		var focusTarget = Css.query(tree3, root3.node.id, '.ui-code-diff-actions[data-current="true"] .ui-code-diff-action[aria-label="Revert change"]')[0];
		ashui.input.Focus.set(@:privateAccess ashui.input.Interaction.byId(tree3, focusTarget), true);
		var before = reverted.length;
		ashui.input.Keyboard.input(tree3, Input(Code(Enter), Named(Enter), None, Standard, Pressed, false, Unavailable));
		settle3();
		check("Enter on a focused button calls its hook with the current change", reverted.length == before + 1 && reverted[reverted.length - 1] == third.modifiedStart, reverted);
		reverted.pop();
		press("Revert change");
		press("Copy");
		check("Revert and a custom action each call their own function, once", staged.length == 1 && reverted.length == 1 && copied.length == 1 && staged[0] == third.modifiedStart && reverted[0] == third.modifiedStart, [staged, reverted, copied, third]);
		dispose3();
		tree3.dispose();

		// Icons the app gives replace the ones the diff has.
		var tree4 = new LayoutTree(), dispose4:Void->Void = null;
		var up = mark("M4 16 L12 8 L20 16"), down = mark("M4 8 L12 16 L20 8"), fold = mark("M4 12 H20");
		var root4 = Owner.root(tree4, stop -> {
			dispose4 = stop;
			return <div width={640} height={300}>
				<code-diff original={signal(long.join("\n"))} modified={signal(longEdited.join("\n"))} navigation={true}
					icons={{previous: up, next: down, folded: fold}} width={640} height={300} />
			</div>;
		});
		for (_ in 0...8) {
			Css.update();
			tree4.flush();
			tree4.computeLayout(root4.node, 640, 300);
		}
		check("the navigation buttons draw the icons they are given", drawn(up) == 1 && drawn(down) == 1, [drawn(up), drawn(down)]);
		check("a folded run draws the icon it is given", drawn(fold) >= 1, drawn(fold));
		dispose4();
		tree4.dispose();

		// A large pair is compared on the worker thread, and the view says so until it is done.
		var big = [for (i in 0...30000) 'line $i of the file'], bigEdited = big.copy();
		bigEdited[10] = "changed";
		bigEdited[29000] = "changed too";
		original.set(big.join("\n"));
		modified.set(bigEdited.join("\n"));
		tree.flush();
		check("a large pair is being compared", d.comparing.get());
		var deadline = haxe.Timer.stamp() + 20;
		while (d.comparing.get() && haxe.Timer.stamp() < deadline) {
			Sys.sleep(0.02);
			ashui.animation.AnimationScheduler.main.tick(0.02);
		}
		settle();
		check("and its two changes are found", !d.comparing.get() && d.changeCount.get() == 2, [d.comparing.get(), d.changeCount.get()]);
		var bigRows = d.shownNow()[0];
		var consecutive = true;
		for (i in 1...bigRows.length)
			if (bigRows[i].row != bigRows[i - 1].row + 1)
				consecutive = false;
		check("the rows shown are a screenful, one after the other", bigRows.length > 5 && bigRows.length < 60 && consecutive, bigRows.length);

		dispose();
		tree.dispose();
		// Hooks the framework makes once, the first time something is used (a focused button's, say), stay for the process; a view
		// made and disposed now must leave the counts as it found them.
		var settledHooks = LayoutTree.layoutHooks.length, settledRestyles = Css.restyled.length;
		var tree5 = new LayoutTree(), stop5:Void->Void = null;
		var root5 = Owner.root(tree5, stop -> {
			stop5 = stop;
			return <div width={300} height={100}><code-diff original={signal("a\nb")} modified={signal("a\nc")} navigation={true} onStage={c -> {}} width={300} height={100} /></div>;
		});
		for (_ in 0...4) {
			Css.update();
			tree5.flush();
			tree5.computeLayout(root5.node, 300, 100);
		}
		check("a view made while the others are gone adds hooks", LayoutTree.layoutHooks.length > settledHooks);
		stop5();
		tree5.dispose();
		check("disposing the view takes its layout and restyle hooks away", LayoutTree.layoutHooks.length == settledHooks && Css.restyled.length == settledRestyles, [LayoutTree.layoutHooks.length - settledHooks, Css.restyled.length - settledRestyles]);
		check("and the first views' hooks went too, but for those the framework keeps", LayoutTree.layoutHooks.length - hooks <= 1 && Css.restyled.length == restyles, [LayoutTree.layoutHooks.length - hooks, Css.restyled.length - restyles]);

		Sys.println('$checks checks: ALL PASSED');
	}
}
