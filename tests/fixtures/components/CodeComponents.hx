import ashui.components.CodeEditor;
import ashui.components.CodeView;
import ashui.components.code.CodeAnnotations;
import ashui.components.code.CodeDocument;
import ashui.components.code.CodeSyntax;
import ashui.components.code.CodeHighlighter;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.types.Style.Display;
import ashui.ui.Ref;

/** Real input, native grapheme geometry, incremental lexing and viewport bounds (e53597f). **/
@:access(ashui.components.CodeEditor)
@:access(ashui.components.code.CodeCompletions)
class CodeComponents {
	static var checks = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok) { if (detail != null) Sys.println(Std.string(detail)); throw name; }
		checks++; Sys.println('ok   $name');
	}
	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
	static function kindAt(doc:CodeDocument, line:Int, text:String):CodeTokenKind {
		var at = doc.lines[line].text.indexOf(text);
		for (token in doc.lines[line].tokens) if (token.from <= at && token.to > at) return token.kind;
		throw 'No token for $text on line $line';
	}
	static function main() {
		var syntax = CodeSyntax.forLanguage("haxe");
		var source = 'class Greeting {\n    // not a fold: {\n    function hello() {\n        var text = "}";\n        return "Hello 🌍";\n    }\n}\n';
		var doc = new CodeDocument(source, syntax);
		check("folds ignore brackets in comments and strings", doc.lines[0].foldEnd == 6 && doc.lines[2].foldEnd == 5 && doc.lines[1].foldEnd == -1);
		var opening = source.indexOf("{"), closing = source.lastIndexOf("}");
		check("matching braces use actual code spans", doc.matchingBrackets(opening).join(",") == '$opening,$closing'
			&& doc.matchingBrackets(closing + 1).join(",") == '$opening,$closing');
		check("string and comment braces have no bracket match", !doc.brackets.exists(source.indexOf("// not a fold: {") + "// not a fold: ".length)
			&& !doc.brackets.exists(source.indexOf('"}"') + 1));
		doc.toggleFold(2); doc.toggleFold(0); doc.toggleFold(0);
		check("nested folds survive closing and reopening their parent", doc.lines[2].folded && doc.visible.indexOf(3) < 0 && doc.visible.indexOf(6) >= 0);
		doc.update(StringTools.replace(source, "Hello", "Goodbye"), syntax);
		check("single-line edit reuses unchanged highlight cache", doc.highlighted == 1, doc.highlighted);
		var multiline = new CodeDocument('/* start\ninside {\nend */\nvar a = 1;', syntax);
		// A line's tokens are kept as integers, and read back as the highlighter gave them.
		var packedLine = new CodeDocument("var a = 'x'; // note\nplain", syntax).lines[0];
		var given = syntax.highlight(packedLine.text, "").tokens;
		var readBack = packedLine.tokens;
		var same = readBack.length == given.length && packedLine.tokenCount == given.length;
		for (i in 0...given.length)
			same = same && readBack[i].from == given[i].from && readBack[i].to == given[i].to && readBack[i].kind == given[i].kind
				&& packedLine.tokenFrom(i) == given[i].from && packedLine.tokenTo(i) == given[i].to && packedLine.tokenKind(i) == given[i].kind;
		var revision = packedLine.tokenRevision;
		packedLine.tokens = [];
		check("a line's tokens are kept packed and read back as the highlighter gave them", same && given.length > 4 && packedLine.tokenCount == 0 && packedLine.tokens.length == 0 && packedLine.tokenRevision == revision + 1,
			[given.length, packedLine.tokenCount]);
		check("block comments propagate to following lines", multiline.lines[1].tokens[0].kind == Comment && multiline.lines[1].foldEnd == -1);
		multiline.update('/* start */\ninside {\nend */\nvar a = 1;', syntax);
		check("changed lexical state re-highlights until it converges", multiline.lines[1].tokens[0].kind != Comment && multiline.highlighted >= 3);
		// HXX text is language data, not an uppercase type identifier (fb9ee3b).
		var markupSource = 'return <div class="stack">\n    <button onClick={_ -> {\n        trace("}");\n    }}>\n        Add one\n    </button>\n    <text>$' + '{count.get()}</text>\n    <Widget />\n</div>;\nvar count = 42;';
		var markupDoc = new CodeDocument(markupSource, syntax);
		check("HXX child text is a markup text token", kindAt(markupDoc, 4, "Add") == MarkupText && kindAt(markupDoc, 4, "one") == MarkupText);
		check("HXX tags and attributes have distinct token kinds", kindAt(markupDoc, 0, "div") == Tag && kindAt(markupDoc, 0, "class") == Attribute
			&& kindAt(markupDoc, 1, "onClick") == Attribute && kindAt(markupDoc, 7, "Widget") == Tag);
		check("HXX attribute expressions use the host lexer across lines", kindAt(markupDoc, 2, "trace") == Function && kindAt(markupDoc, 2, '"}"') == StringLiteral);
		check("HXX text interpolation returns to markup then host code", kindAt(markupDoc, 6, "get") == Function && kindAt(markupDoc, 9, "var") == Keyword && kindAt(markupDoc, 9, "42") == Number);
		for (line in markupDoc.lines) {
			var end = 0;
			for (token in line.tokens) {
				check("syntax spans are ordered and cover the source without gaps", token.from == end && token.to > token.from && token.to <= line.text.length);
				end = token.to;
			}
			check("syntax spans keep original line offsets", end == line.text.length);
		}
		markupDoc.update(StringTools.replace(markupSource, "Add one", "Add two"), syntax);
		check("markup text edits preserve incremental highlighting", markupDoc.highlighted == 1, markupDoc.highlighted);
		var branches = new CodeDocument('return <div>\n<if {ok}><icon/>\n<else><if {other}><text>Other</text>\n<else><div/></if></if>\n<elsewhere/>\n</div>;\nif (ok) return row;\n/** Documentation */\nfunction message():Element { return <text/>; }', syntax);
		check("HXX else markers leave the enclosing markup depth unchanged", kindAt(branches, 6, "if") == Keyword && kindAt(branches, 6, "return") == Keyword);
		check("code after HXX branches keeps comments and function tokens", kindAt(branches, 7, "/**") == Comment && kindAt(branches, 8, "function") == Keyword && kindAt(branches, 8, "message") == Function);
		var jsxElse = new CodeDocument('return <div><else>content</else></div>;\nreturn value;', CodeSyntax.forLanguage("javascript"));
		check("JSX else is an ordinary element", kindAt(jsxElse, 1, "return") == Keyword);
		var generic = new CodeDocument('var items:Map<String, Array<Int>>;\nif (a<b) return a;', syntax);
		check("generic types and comparisons do not enter markup mode", kindAt(generic, 0, "String") == Type && kindAt(generic, 1, "return") == Keyword);
		// What follows the edits: a start stays with the text after it, an end does not grow, and a marker is its line's.
		var annoText = "abcdef\nghijkl\nmnop", annoDoc = new CodeDocument(annoText, syntax), anno = new CodeAnnotations(annoDoc);
		function annoEdit(next:String) { anno.edited(annoText, next); annoDoc.update(next, syntax); annoText = next; }
		anno.decorate("o", [{from: 2, to: 4, className: "x"}], true);
		annoEdit("abXcdef\nghijkl\nmnop");
		check("typing at the start of a range leaves the range after it", anno.decorationsOf("o")[0].from == 3 && anno.decorationsOf("o")[0].to == 5);
		annoEdit("abXcdYef\nghijkl\nmnop");
		check("typing at the end of a range does not grow it", anno.decorationsOf("o")[0].from == 3 && anno.decorationsOf("o")[0].to == 5);
		annoEdit("abXcYdYef\nghijkl\nmnop");
		check("typing inside a range grows it", anno.decorationsOf("o")[0].from == 3 && anno.decorationsOf("o")[0].to == 6);
		anno.mark("m", [{line: 1, className: "dot"}, {line: 2, className: "dot"}], true);
		annoEdit("abXcYdYef\n\nghijkl\nmnop");
		check("a line break before a marker's text moves the marker down with it", anno.markerLinesOf("m").join(",") == "2,3", anno.markerLinesOf("m"));
		annoEdit("abXcYdYef\nghijkl\nmnop");
		check("taking the line break out moves it back", anno.markerLinesOf("m").join(",") == "1,2", anno.markerLinesOf("m"));
		anno.mark("m", [{line: 9, className: "dot"}, {line: -1, className: "dot"}]);
		check("a marker on a line the document does not have is left out", anno.markerLinesOf("m").length == 0);
		// A file read again: the lines both texts have keep their markers, and a changed line keeps its own.
		var reloadText = "a\nb\nc\nd\ne\nf", reloadDoc = new CodeDocument(reloadText, syntax), reload = new CodeAnnotations(reloadDoc);
		function reloaded(next:String) { reload.edited(reloadText, next); reloadDoc.update(next, syntax); reloadText = next; }
		reload.mark("m", [{line: 1, className: "dot"}, {line: 3, className: "dot"}, {line: 4, className: "dot"}], true);
		reloaded("a\nX\nb\nc\nd\nQ\ne\nf");
		check("markers stay with their lines when lines come in around them", reload.markerLinesOf("m").join(",") == "2,4,6", reload.markerLinesOf("m"));
		reloaded("a\nX\nB\nC\nd\nQ\ne\nf");
		check("two lines changed together keep a marker each", reload.markerLinesOf("m").join(",") == "2,4,6", reload.markerLinesOf("m"));
		reloaded("a\nX\nB\nC\nQ\ne\nf");
		check("a marker's line taken out goes to the line that took its place", reload.markerLinesOf("m").join(",") == "2,4,5", reload.markerLinesOf("m"));
		anno.decorate("o", [{from: 0, to: 0, className: "line", wholeLine: true}], true);
		annoEdit("abXcYdYe\nghijkl\nmnop");
		check("a whole-line decoration is kept when text near it goes", anno.decorationsOf("o").length == 1);
		for (dark in [true, false]) {
			ThemeState.init(DefaultTheme.bundle(), dark ? Dark : Light);
			var hooks = LayoutTree.layoutHooks.length, tree = new LayoutTree(), dispose:Void->Void = null;
			var editor = new Ref<CodeEditor>(), viewer = new Ref<CodeView>();
			var editorHeight = signal(270.);
			var value = signal(source), readOnly = signal(false), disabled = signal(false), mounted = signal(true), shown = signal(true), changes = 0;
			var root = Owner.root(tree, stop -> {
				dispose = stop;
				return <div width={760} height={600} class="flex-col gap-4 p-4">
					<if {mounted.get()}><code-editor ref={editor} id="editor" language="haxe" value={value} readOnly={readOnly} disabled={disabled} height={editorHeight} indentGuides={true}
						display={computed(() -> shown.get() ? Display.Flex : Display.None)} onInput={_ -> changes++} /></if>
					<code-view ref={viewer} id="viewer" language="json" value={'{"name": "Ashui",\n "ready": true\n}'} height={200} />
				</div>;
			});
			function settle() { tree.flush(); tree.computeLayout(root.node, 760, 600); }
			function press(k:window.Key, code:window.KeyCode, ?modifiers:window.Modifiers) { Keyboard.input(tree, key(k, code), modifiers); settle(); }
			settle();
			var ed = editor.get(), e = ed.editing;
			check("native font metrics have a usable line height", ed.metrics.lineHeight > 10 && ed.metrics.characterWidth > 3);
			check("short documents build one row and gutter slot per visible line", Css.query(tree, ed.node.id, ".ui-code-line").length == ed.document.visible.length
				&& Css.query(tree, ed.node.id, ".ui-code-gutter-line").length == ed.document.visible.length);
			check("short read-only views do not allocate empty row slots", Css.query(tree, viewer.get().node.id, ".ui-code-line").length == viewer.get().document.visible.length);
			ed.focus(); ed.select(opening, opening); settle();
			check("a caret next to a brace highlights both matched glyphs", Css.query(tree, ed.node.id, ".ui-code-bracket").length == 2);
			var editorBox = tree.getBounds(ed.scroll.node), gutterBox = tree.getBounds(Identity.of(tree, Css.query(tree, ed.node.id, ".ui-code-gutter")[0]).node);
			var contentBox = tree.getBounds(Identity.of(tree, Css.query(tree, ed.node.id, ".ui-code-content")[0]).node);
			check("the gutter and the content fill the view when the code is shorter than it", gutterBox.height >= editorBox.height - 1 && contentBox.height >= editorBox.height - 1,
				[gutterBox.height, contentBox.height, editorBox.height]);
			var braceStop = e.stopAt(opening, value.get());
			ed.select(0, 0); settle();
			Pointer.move(tree, editorBox.x + gutterBox.width + 12 + braceStop.x + ed.metrics.characterWidth * .25, editorBox.y + 12 + braceStop.line * ed.metrics.lineHeight + ed.metrics.lineHeight / 2);
			Pointer.press(tree); Pointer.release(tree); settle();
			check("clicking a brace moves the caret and highlights its pair", (e.caret.get() == opening || e.caret.get() == opening + 1)
				&& Css.query(tree, ed.node.id, ".ui-code-bracket").length == 2);
			ed.select(source.indexOf('"}"') + 1, source.indexOf('"}"') + 1); settle();
			check("clicking inside string braces does not highlight code pairs", Css.query(tree, ed.node.id, ".ui-code-bracket").length == 0);
			var numberBounds = [for (id in Css.query(tree, ed.node.id, ".ui-code-line-number")) tree.getBounds(Identity.of(tree, id).node)];
			check("line numbers align with and without fold carets", numberBounds.length >= 6
				&& !Lambda.exists(numberBounds, b -> Math.abs(b.x - numberBounds[0].x) > .05 || Math.abs(b.width - numberBounds[0].width) > .05), numberBounds);
			check("every gutter row reserves its fold-caret column", Css.query(tree, ed.node.id, ".ui-code-fold-slot").length == numberBounds.length);
			ed.focus(); ed.select(0, 0); Keyboard.text(tree, "// Hello\n"); settle();
			check("typing writes the shared signal and callback", StringTools.startsWith(value.get(), "// Hello\n") && changes == 1);
			ed.undo(); settle(); check("undo restores text and selection", value.get() == source && e.caret.get() == 0);
			ed.redo(); settle(); check("redo restores the edit", StringTools.startsWith(value.get(), "// Hello\n"));
			// Retained editor tabs must not rebuild signals, tokens or shaped rows (2aca664).
			ed.toggleFold(3); settle();
			var foldedNumbers = [for (id in Css.query(tree, ed.node.id, ".ui-code-line-number")) Std.parseInt(ashui.ui.Text.at(id).text())];
			foldedNumbers.sort((a, b) -> a - b);
			check("folding a short document releases unused slots and keeps every visible row", foldedNumbers.join(",") == [for (line in ed.document.visible) line + 1].join(","));
			var retainedRows = Css.query(tree, ed.node.id, ".ui-code-line").copy();
			var retainedCaret = e.caret.get(), retainedHeight = @:privateAccess ed.viewHeight.get();
			for (_ in 0...4) { shown.set(false); settle(); shown.set(true); settle(); }
			check("tab visibility keeps the editor and its native row nodes", editor.get() == ed
				&& retainedRows.join(",") == Css.query(tree, ed.node.id, ".ui-code-line").join(","));
			check("inactive tabs retain selection, folds and viewport measurements", e.caret.get() == retainedCaret
				&& ed.document.lines[3].folded && @:privateAccess ed.viewHeight.get() == retainedHeight);
			ed.toggleFold(3); settle();
			ed.undo(); settle();
			check("undo history survives tab visibility changes", value.get() == source);
			ed.select(source.indexOf("{") + 1, source.indexOf("{") + 1); press(Named(Enter), Enter);
			check("Enter indents a new block line", value.get().indexOf("{\n    \n") >= 0, value.get());
			ed.undo(); settle();
			ed.select(0, 0); press(Named(Tab), Tab);
			check("Tab inserts indentation and retains focus", StringTools.startsWith(value.get(), "    class") && e.focused.get());
			ed.undo(); settle();
			ed.select(0, source.indexOf("    //")); press(Named(Tab), Tab);
			check("Tab indents the selected source lines", StringTools.startsWith(value.get(), "    class Greeting"));
			var indented = value.get(), selectedTo = e.caret.get();
			ed.undo(); settle();
			check("indent undo restores original selection", e.anchor.get() == 0 && e.caret.get() == source.indexOf("    //"));
			ed.redo(); settle(); check("indent redo restores selected indented lines", value.get() == indented && e.anchor.get() == 0 && e.caret.get() == selectedTo);
			ed.undo(); settle();
			ed.select(5, 5); press(Named(Backspace), Backspace); ed.undo(); settle();
			check("delete undo restores a collapsed caret", value.get() == source && e.caret.get() == 5 && e.anchor.get() == 5);
			var shifted = window.Modifiers.State(true, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown);
			var indentedAt = source.indexOf("    //") + 4;
			ed.select(indentedAt, indentedAt); press(Named(Tab), Tab, shifted);
			check("Shift+Tab outdents without selecting the line", e.caret.get() == indentedAt - 4 && e.anchor.get() == e.caret.get());
			ed.undo(); settle();
			ed.select(0, 0); readOnly.set(true); settle(); Keyboard.text(tree, "refused"); press(Named(Delete), Delete);
			check("read-only keeps source immutable", value.get() == source);
			readOnly.set(false); settle();
			disabled.set(true); settle(); e.replace("refused"); check("disabled editors refuse programmatic replacements too", value.get() == source);
			disabled.set(false); settle(); ed.focus();
			ed.toggleFold(0); settle();
			check("folding keeps original source and line numbers", value.get() == source && ed.document.visible.length == 2 && ed.document.visible[1] == 7);
			ed.select(source.indexOf("return"), source.indexOf("return")); settle();
			check("programmatic selection reveals folded ancestors", !ed.document.lines[0].folded);
			var emoji = source.indexOf("🌍"); ed.select(emoji, emoji); press(Named(ArrowRight), ArrowRight);
			check("right arrow crosses one native emoji grapheme", e.caret.get() == emoji + "🌍".length, [e.caret.get(), emoji]);
			ed.select(source.indexOf("return"), source.indexOf("return"));
			Keyboard.composition(tree, "日本", 1); settle();
			check("IME composition is displayed without committing the source", e.display().indexOf("日本return") >= 0 && value.get() == source);
			Keyboard.composition(tree, "", -1); Keyboard.text(tree, "日本"); settle();
			check("IME commit is one undoable source edit", value.get().indexOf("日本return") >= 0);
			ed.undo(); settle();
			var foldId = Css.query(tree, ed.node.id, ".ui-code-fold")[0], fold = tree.getBounds(Identity.of(tree, foldId).node);
			Pointer.move(tree, fold.x + fold.width / 2, fold.y + fold.height / 2); Pointer.press(tree); Pointer.release(tree); settle();
			check("existing icon button toggles a gutter fold", ed.document.lines[0].folded);
			press(Named(Enter), Enter); check("keyboard activates the focused fold button", !ed.document.lines[0].folded);
			var view = viewer.get(); view.focus(); view.select(0, 0); Keyboard.text(tree, "refused"); settle();
			check("CodeView supports selection without mutation", StringTools.startsWith(view.value.get(), "{\"name\""));
			value.set('class Wide {\n    var text = "' + [for (_ in 0...80) "long source"].join(" ") + '";\n}\n'); settle();
			ed.scroll.jumpTo(160, 0); settle();
			check("long source scrolls horizontally", ed.scroll.x.get() == 160);
			var pinnedFold = tree.getBounds(Identity.of(tree, Css.query(tree, ed.node.id, ".ui-code-fold")[0]).node);
			Pointer.move(tree, pinnedFold.x - ed.scroll.x.get() + pinnedFold.width / 2, pinnedFold.y - ed.scroll.y.get() + pinnedFold.height / 2);
			Pointer.press(tree); Pointer.release(tree); settle();
			check("gutter fold remains clickable after horizontal scrolling", ed.document.lines[0].folded);
			var large = [for (i in 0...5000) 'var item$i = $i;'].join("\n");
			value.set(large); settle();
			check("large document retains all source lines", ed.document.lines.length == 5000);
			check("only viewport lines have UI nodes", Css.query(tree, ed.node.id, ".ui-code-line").length < 40);
			var pane = tree.getBounds(ed.scroll.node);
			Pointer.move(tree, pane.x + pane.width / 2, pane.y + pane.height / 2); Pointer.wheel(tree, 0, -80); settle();
			check("wheel scrolls the code viewport", ed.scroll.y.get() > 0);
			ed.scroll.jumpTo(0, 3000); settle();
			// The row elements are pooled and a row is in slot `row % capacity`: a slot with no row shows no number, and the order is not the document's.
			var shownNumbers = [for (id in Css.query(tree, ed.node.id, ".ui-code-line-number")) Std.parseInt(ashui.ui.Text.at(id).text())].filter(n -> n != null);
			check("scrolling renders later source rows", shownNumbers.length > 10 && Lambda.foreach(shownNumbers, n -> n > 50), shownNumbers);
			var windowOf = () -> [@:privateAccess ed.windowStart(), @:privateAccess ed.windowEnd()].join("-");
			var builtRows:Dynamic = null, stayed = false;
			for (attempt in 0...12) {
				ed.scroll.jumpTo(0, 3000 + attempt * 7); settle();
				builtRows = @:privateAccess ed.cachedRows;
				var window = windowOf();
				ed.scroll.jumpTo(0, 3000 + attempt * 7 + 0.5); settle();
				if (windowOf() == window) { stayed = true; break; }
			}
			var rowsNow:Dynamic = @:privateAccess ed.cachedRows;
			check("a scroll that stays inside the built window builds nothing", stayed && rowsNow == builtRows);
			// Scrolling lines moves rows between the pooled elements: no element is made, and each number stays level with its own row.
			// A slot builds its token elements the first time it shows a row, so the window is walked through every slot before counting.
			for (_ in 0...40) { ed.scroll.jumpTo(0, ed.scroll.y.get() + ed.metrics.lineHeight); settle(); }
			var elementsBefore = Css.query(tree, ed.node.id, "*"), lh = ed.metrics.lineHeight;
			ed.scroll.jumpTo(0, ed.scroll.y.get() + lh * 12); settle();
			var elementsAfter = Css.query(tree, ed.node.id, "*");
			check("scrolling by lines reuses the row elements", elementsAfter.join(",") == elementsBefore.join(","), [elementsBefore.length, elementsAfter.length]);
			var pooled = Css.query(tree, ed.node.id, ".ui-code-line").join(",");
			editorHeight.set(160); settle();
			check("reducing viewport height retains the row pool", Css.query(tree, ed.node.id, ".ui-code-line").join(",") == pooled);
			editorHeight.set(270); settle();
			check("restoring viewport height reuses the row pool", Css.query(tree, ed.node.id, ".ui-code-line").join(",") == pooled);

			var offsets = [for (id in Css.query(tree, ed.node.id, ".ui-code-line-number")) {
				var text = ashui.ui.Text.at(id).text();
				if (text == "") continue;
				tree.getBounds(Identity.of(tree, id).node).y - Std.parseInt(text) * lh;
			}];
			check("every gutter number is level with its row after scrolling", offsets.length > 10 && Lambda.foreach(offsets, o -> Math.abs(o - offsets[0]) < 1), offsets);
			check("shaped line cache is bounded", @:privateAccess ed.metrics.recent.length <= 96);
			var cacheBefore = @:privateAccess ed.metrics.recent.copy();
			value.set("reset"); settle(); ed.undo(); settle();
			check("external source reset clears incompatible undo history", value.get() == "reset");
			check("shrinking a scrolled document releases surplus row slots", Css.query(tree, ed.node.id, ".ui-code-line").length == 1
				&& Css.query(tree, ed.node.id, ".ui-code-gutter-line").length == 1
				&& ashui.ui.Text.at(Css.query(tree, ed.node.id, ".ui-code-line-number")[0]).text() == "1",
				[Css.query(tree, ed.node.id, ".ui-code-line").length, Css.query(tree, ed.node.id, ".ui-code-gutter-line").length,
					[for (id in Css.query(tree, ed.node.id, ".ui-code-line-number")) ashui.ui.Text.at(id).text()], ed.scroll.y.get(), @:privateAccess ed.windowStart(), @:privateAccess ed.windowEnd()]);
			check("reset releases shaped lines from the old document", !Lambda.exists(cacheBefore, line -> @:privateAccess ed.metrics.recent.indexOf(line) >= 0));
			var widthBefore = ed.metrics.characterWidth;
			Css.load('#editor { --ui-code-font-size: 24px; }'); settle();
			check("CSS font changes invalidate native caret metrics", ed.metrics.characterWidth > widthBefore * 1.2);
			Css.load('#editor { --ui-code-font-size: 14px; }'); settle();
			ashui.input.Focus.clear(tree); settle();
			for (_ in 0...2) { ashui.animation.AnimationScheduler.main.tick(1); settle(); }
			check("unfocused code views have no idle animation or caret timer", !ashui.animation.AnimationScheduler.main.hasActive()
				&& ashui.animation.AnimationScheduler.main.untilNextTimer() == null);
			// A tab removes its editor while focus/CSS still have queued work (3e75041).
			var restyleHooks = Css.restyled.length;
			for (cycle in 0...4) {
				editor.get().focus(); settle();
				mounted.set(false); settle();
				check('removed editor releases its CSS listener $cycle', Css.restyled.length == restyleHooks - 1, [restyleHooks, Css.restyled.length]);
				mounted.set(true); settle();
				check('remounted editor keeps CSS listener count stable $cycle', Css.restyled.length == restyleHooks);
			}
			dispose(); ashui.animation.AnimationScheduler.main.tick(1); tree.flush();
			check("disposing code controls releases layout hooks", LayoutTree.layoutHooks.length == hooks);
			tree.dispose();
		}
		// Code longer than the view keeps its own height, and the view scrolls over it.
		ThemeState.init(DefaultTheme.bundle(), Light);
		var longTree = new LayoutTree(), longEditor = new Ref<CodeEditor>(), longDispose:Void->Void = null;
		var longRoot = Owner.root(longTree, stop -> {
			longDispose = stop;
			return <div width={760} height={400} class="flex-col p-4"><code-editor ref={longEditor} language="haxe" value={[for (i in 0...200) 'var v$i = $i;'].join("\n")} height={270} /></div>;
		});
		longTree.flush(); longTree.computeLayout(longRoot.node, 760, 400); longTree.flush();
		var long = longEditor.get();
		var longGutter = longTree.getBounds(Identity.of(longTree, Css.query(longTree, long.node.id, ".ui-code-gutter")[0]).node);
		var lines200 = 200 * long.metrics.lineHeight;
		check("long code keeps its own height in the gutter", longGutter.height >= lines200 && longGutter.height < lines200 + 100, [longGutter.height, lines200]);
		check("an editor has no minimap unless asked for", Css.query(longTree, long.node.id, ".ui-code-minimap").length == 0);
		longDispose(); longTree.dispose();
		// Underlines of many widths are a few documents, and so a few atlas entries.
		var waveTree = new LayoutTree(), waveEditor = new Ref<CodeEditor>(), waveDispose:Void->Void = null;
		var waveSource = [for (i in 0...12) [for (k in 0...80) "x"].join("")].join("\n");
		var waveRoot = Owner.root(waveTree, stop -> {
			waveDispose = stop;
			return <div width={900} height={400} class="flex-col p-4"><code-editor ref={waveEditor} language="plain" value={waveSource} height={270} /></div>;
		});
		function waveSettle() { waveTree.flush(); waveTree.computeLayout(waveRoot.node, 900, 400); waveTree.flush(); }
		waveSettle(); waveSettle();
		var wave = waveEditor.get();
		var docsBefore = Lambda.count(@:privateAccess ashui.svg.SvgDocument.byId);
		wave.decorate("w", [for (i in 0...12) {from: wave.document.lines[i].start, to: wave.document.lines[i].start + 5 + i * 6, className: "ui-code-squiggle-error"}]);
		waveSettle();
		var waveDocs = Lambda.count(@:privateAccess ashui.svg.SvgDocument.byId) - docsBefore;
		check("underlines of twelve widths are a few documents", waveDocs > 0 && waveDocs <= 7, waveDocs);
		waveDispose(); waveTree.dispose();
		// The minimap: a strip beside the viewport, a slider over what the viewport shows, and the editor follows what is pressed in it.
		var hooksBefore = LayoutTree.layoutHooks.length, restylesBefore = Css.restyled.length;
		var mapTree = new LayoutTree(), mapEditor = new Ref<CodeEditor>(), mapDispose:Void->Void = null;
		var mapRoot = Owner.root(mapTree, stop -> {
			mapDispose = stop;
			return <div width={760} height={400} class="flex-col p-4"><code-editor ref={mapEditor} language="haxe" value={[for (i in 0...300) 'var v$i = $i;'].join("\n")} height={270} minimap={true} /></div>;
		});
		function mapSettle() { mapTree.flush(); mapTree.computeLayout(mapRoot.node, 760, 400); mapTree.flush(); }
		mapSettle(); mapSettle();
		var map = mapEditor.get(), mapLine = map.metrics.lineHeight;
		function box(selector:String) return mapTree.getBounds(Identity.of(mapTree, Css.query(mapTree, map.node.id, selector)[0]).node);
		var viewport = box(".ui-code-viewport"), strip = box(".ui-code-minimap");
		check("the minimap is a strip beside the viewport, as high as it", strip.x >= viewport.x + viewport.width - 1 && strip.width > 20 && strip.width <= 97
			&& Math.abs(strip.height - viewport.height) < 2, [strip, viewport]);
		var pitch = Math.min(2, viewport.height / 300);
		var sliderSize = Math.max(12, viewport.height / mapLine * pitch);
		check("the slider covers the part of the document on screen", Math.abs(box(".ui-code-minimap-slider").height - sliderSize) < 1.5 && Math.abs(box(".ui-code-minimap-slider").y - strip.y) < 1.5,
			[box(".ui-code-minimap-slider"), sliderSize]);
		map.scroll.jumpTo(0, 1500); mapSettle();
		check("the slider follows the scrolling", Math.abs(box(".ui-code-minimap-slider").y - strip.y - (1500 - 12) / mapLine * pitch) < 1.5, [box(".ui-code-minimap-slider").y - strip.y, (1500 - 12) / mapLine * pitch]);
		// Pressing beside the slider puts the slider's middle where the pointer is.
		map.scroll.jumpTo(0, 0); mapSettle();
		var at = strip.y + strip.height * .7;
		Pointer.move(mapTree, strip.x + strip.width / 2, at); Pointer.press(mapTree); Pointer.release(mapTree); mapSettle();
		var expected = 12 + (at - strip.y - sliderSize / 2) / pitch * mapLine;
		check("pressing the strip scrolls the editor to that line", Math.abs(map.scroll.y.get() - expected) < 2, [map.scroll.y.get(), expected]);
		// Dragging from the slider moves it with the pointer, from where it was taken.
		var slider = box(".ui-code-minimap-slider"), before = map.scroll.y.get();
		Pointer.move(mapTree, strip.x + strip.width / 2, slider.y + 3); Pointer.press(mapTree);
		Pointer.move(mapTree, strip.x + strip.width / 2, slider.y + 3 + 20); mapSettle(); Pointer.release(mapTree); mapSettle();
		check("dragging the slider scrolls as it moves", Math.abs(map.scroll.y.get() - before - 20 / pitch * mapLine) < 2, [map.scroll.y.get() - before, 20 / pitch * mapLine]);
		before = map.scroll.y.get();
		Pointer.move(mapTree, strip.x + strip.width / 2, strip.y + 10); Pointer.wheel(mapTree, 0, -60); mapSettle();
		check("the wheel over the strip scrolls the editor", map.scroll.y.get() > before, [map.scroll.y.get(), before]);
		map.focus(); map.select(0, 0); mapSettle();
		mapDispose(); mapTree.dispose();
		ashui.animation.AnimationScheduler.main.tick(1);
		check("a disposed minimap leaves no hook or timer behind", LayoutTree.layoutHooks.length == hooksBefore && Css.restyled.length == restylesBefore
			&& ashui.animation.AnimationScheduler.main.untilNextTimer() == null, [LayoutTree.layoutHooks.length, hooksBefore, Css.restyled.length, restylesBefore]);
		// The strip's width follows the editor's, in no width swapping sizes with the text, so a layout is the same on each pass.
		var narrowWidth = ashui.reactive.Signal.make((318 : Single));
		var narrowTree = new LayoutTree(), narrowEditor = new Ref<CodeEditor>(), narrowDispose:Void->Void = null;
		var narrowRoot = Owner.root(narrowTree, stop -> {
			narrowDispose = stop;
			return <div width={narrowWidth} height={300} class="flex-col"><code-editor ref={narrowEditor} language="plain" value={[for (i in 0...80) 'line $i'].join("\n")} height={270} minimap={true} /></div>;
		});
		function narrowSettle() { narrowTree.flush(); narrowTree.computeLayout(narrowRoot.node, 900, 400); narrowTree.flush(); }
		function narrowViewport():Float return narrowTree.getBounds(Identity.of(narrowTree, Css.query(narrowTree, narrowEditor.get().node.id, ".ui-code-viewport")[0]).node).width;
		narrowSettle(); narrowSettle();
		var swapping:Array<Int> = [];
		for (w in 240...420) {
			narrowWidth.set((w : Single));
			for (_ in 0...5) narrowSettle();
			var settled = narrowViewport();
			narrowSettle();
			if (narrowViewport() != settled) swapping.push(w);
		}
		check("a narrow editor's minimap does not swap sizes with its text from one layout to the next", swapping.length == 0, swapping);
		narrowDispose(); narrowTree.dispose();
		// Decorations and gutter markers, sets by owner (495aa31).
		var noteTree = new LayoutTree(), noteEditor = new Ref<CodeEditor>(), noteDispose:Void->Void = null;
		var noteSource = [for (i in 0...40) 'var v$i = $i;'].join("\n");
		var noteRoot = Owner.root(noteTree, stop -> {
			noteDispose = stop;
			return <div width={760} height={400} class="flex-col p-4"><code-editor ref={noteEditor} language="haxe" value={noteSource} height={270} gutterMarkers={true} /></div>;
		});
		function noteSettle() { noteTree.flush(); noteTree.computeLayout(noteRoot.node, 760, 400); noteTree.flush(); }
		noteSettle(); noteSettle();
		var note = noteEditor.get(), noteLine = note.metrics.lineHeight;
		function lineStart(n:Int):Int return note.document.lines[n].start;
		function noteBoxes(selector:String) return [for (id in Css.query(noteTree, note.node.id, selector)) noteTree.getBounds(Identity.of(noteTree, id).node)];
		var content = noteBoxes(".ui-code-content")[0];
		check("an editor has no decorations or markers until it is given them", noteBoxes(".ui-code-decoration").length == 0 && noteBoxes(".ui-code-marker-breakpoint").length == 0);
		note.decorate("problems", [
			{from: lineStart(3) + 4, to: lineStart(3) + 6, className: "ui-code-squiggle-error", title: "first line\nsecond line"},
			{from: lineStart(5), to: lineStart(5), className: "ui-code-line-current", wholeLine: true}
		]);
		noteSettle();
		var marks = noteBoxes(".ui-code-decoration");
		check("each decoration is a mark on its row", marks.length == 2, marks);
		var squiggle = noteBoxes(".ui-code-squiggle-error")[0], current = noteBoxes(".ui-code-line-current")[0];
		check("a range is marked over its own columns", squiggle != null && Math.abs(squiggle.y - (content.y + 12 + 3 * noteLine)) < 1.5 && squiggle.width > 5 && squiggle.width < 3 * note.metrics.characterWidth + 4
			&& Math.abs(squiggle.x - content.x - noteBoxes(".ui-code-gutter")[0].width - 12 - 4 * note.metrics.characterWidth) < 2, [squiggle, content]);
		check("a whole-line decoration is the line's full width", current != null && Math.abs(current.y - (content.y + 12 + 5 * noteLine)) < 1.5 && current.width >= content.width - 1, [current, content]);
		check("what is over a character is found, with its title", note.decorationsAt(lineStart(3) + 5).length == 1 && note.decorationsAt(lineStart(3) + 5)[0].title == "first line\nsecond line"
			&& note.decorationsAt(lineStart(3) + 8).length == 0 && note.decorationsAt(lineStart(5) + 2).length == 1);
		note.decorate("search", [{from: lineStart(7), to: lineStart(7) + 3, className: "ui-code-squiggle-info"}]); noteSettle();
		check("a set replaces only its own owner's decorations", noteBoxes(".ui-code-decoration").length == 3);
		note.decorate("problems", []); noteSettle();
		check("an empty set clears its owner's decorations", noteBoxes(".ui-code-decoration").length == 1 && noteBoxes(".ui-code-squiggle-info").length == 1);
		note.decorate("search", []); noteSettle();
		// Markers.
		note.markers("debug", [{line: 2, className: "ui-code-marker-breakpoint", title: "a breakpoint"}, {line: 999, className: "ui-code-marker-breakpoint"}]); noteSettle();
		check("a marker is drawn in the gutter, and a line past the end is left out", noteBoxes(".ui-code-marker-breakpoint").length == 1 && note.markerLinesOf("debug").join(",") == "2");
		var dot = noteBoxes(".ui-code-marker-breakpoint")[0];
		check("a marker is level with its line", Math.abs(dot.y + dot.height / 2 - (content.y + 12 + 2 * noteLine + noteLine / 2)) < 2.5, [dot, content]);
		// A press in the marker slot is the app's: it is given the line and the press, whether or not the line has a marker, and the caret stays.
		var pressed:Array<String> = [];
		note.onGutterClick = (line, event) -> pressed.push(line + ":" + event.button);
		note.select(0, 0);
		var slotBox = [for (b in noteBoxes(".ui-code-marker-slot")) if (Math.abs(b.y + b.height / 2 - (content.y + 12 + 6 * noteLine + noteLine / 2)) < noteLine / 2) b][0];
		Pointer.move(noteTree, slotBox.x + slotBox.width / 2, slotBox.y + slotBox.height / 2); Pointer.press(noteTree); Pointer.release(noteTree);
		Pointer.press(noteTree, Right); Pointer.release(noteTree, Right); noteSettle();
		check("a press in the marker slot calls onGutterClick with the line and the button", pressed.join(",") == "6:Left,6:Right", pressed);
		check("a press in the marker slot does not move the caret", note.editing.caret.get() == 0);
		var runIcon = ashui.svg.SvgDocument.parse('<svg width="24" height="24" viewBox="0 0 24 24"><path d="M8 5L19 12L8 19Z" fill="currentColor"/></svg>');
		note.markers("actions", [{line:4,className:"test-action",title:"Run",icon:runIcon}], true); noteSettle();
		check("an SVG marker keeps its data and renders inside its slot", note.annotations.markerAt(4).icon == runIcon && noteBoxes(".ui-code-marker-icon").length == 1
			&& noteBoxes(".ui-code-marker-icon")[0].width == 14);
		var actionSlot = noteBoxes(".test-action")[0];
		Pointer.move(noteTree, actionSlot.x + actionSlot.width / 2, actionSlot.y + actionSlot.height / 2); Pointer.press(noteTree); Pointer.release(noteTree); noteSettle();
		check("an SVG marker still uses the editor gutter handler without moving the caret", pressed[pressed.length - 1] == "4:Left" && note.editing.caret.get() == 0, pressed);
		note.markers("debug", [{line:4,className:"ui-code-marker-breakpoint"}]); noteSettle();
		check("the first marker owner keeps priority over an SVG marker on the same line", noteBoxes(".ui-code-marker-icon").length == 0 && note.annotations.markerAt(4).icon == null);
		note.markers("debug", [{line:2,className:"ui-code-marker-breakpoint"}]); noteSettle();
		check("an SVG marker reappears when the earlier owner leaves its line", noteBoxes(".ui-code-marker-icon").length == 1);
		note.markers("actions", []); noteSettle();
		check("clearing SVG markers releases their views and leaves other owners intact", noteBoxes(".ui-code-marker-icon").length == 0 && noteBoxes(".ui-code-marker-breakpoint").length == 1);
		// An owner that follows the edits keeps its place in the text; one that does not stays where it was put.
		note.markers("debug", [{line: 10, className: "ui-code-marker-breakpoint"}], true);
		note.decorate("follow", [{from: lineStart(12) + 4, to: lineStart(12) + 8, className: "ui-code-squiggle-warning"}], true);
		note.decorate("fixed", [{from: lineStart(12) + 4, to: lineStart(12) + 8, className: "ui-code-squiggle-info"}]);
		var fixedAt = note.decorationsOf("fixed")[0].from, followAt = note.decorationsOf("follow")[0].from;
		noteSource = "// new\n// lines\n" + noteSource;
		var noteValue = @:privateAccess note.value;
		noteValue.set(noteSource); noteSettle();
		check("a marker that follows the edits stays with its line", note.markerLinesOf("debug").join(",") == "12", note.markerLinesOf("debug"));
		check("a decoration that follows the edits moves with its text", note.decorationsOf("follow")[0].from == followAt + 16 && note.decorationsOf("fixed")[0].from == fixedAt, [note.decorationsOf("follow")[0].from, followAt]);
		var movedDot = noteBoxes(".ui-code-marker-breakpoint")[0];
		check("the marker is drawn at its new line", movedDot != null && Math.abs(movedDot.y + movedDot.height / 2 - (content.y + 12 + 12 * noteLine + noteLine / 2)) < 2.5, [movedDot]);
		// Text taken out under a range takes it too.
		var span = note.decorationsOf("follow")[0];
		noteValue.set(noteValue.get().substr(0, span.from) + noteValue.get().substr(span.to)); noteSettle();
		check("a range whose text is deleted goes with it", note.decorationsOf("follow").length == 0);
		note.onGutterClick = null;
		noteDispose(); noteTree.dispose();
		// The hints popover: position lookup, a hover that is asked once the pointer rests, decoration titles, and a hint opened from code.
		var hintTree = new LayoutTree(), hintEditor = new Ref<CodeEditor>(), hintDispose:Void->Void = null, asked:Array<Int> = [];
		var hintSource = [for (i in 0...40) 'var v$i = $i;'].join("\n");
		var hintRoot = Owner.root(hintTree, stop -> {
			hintDispose = stop;
			var provide = (offset:Int) -> {
				asked.push(offset);
				var at = hintSource.indexOf("v3 =");
				offset >= at && offset < at + 2 ? ({from: at, to: at + 2, signature: "var v3:Int\nvar v3Again:Int", docs: "First paragraph,\nstill the first.\n\nSecond paragraph.", className: null} : ashui.components.code.CodeHints.CodeHint) : null;
			};
			return <div width={760} height={400} class="flex-col p-4"><code-editor ref={hintEditor} language="haxe" value={hintSource} height={270} hover={provide} /></div>;
		});
		function hintSettle() { hintTree.flush(); hintTree.computeLayout(hintRoot.node, 760, 400); hintTree.flush(); }
		hintSettle(); hintSettle();
		var hint = hintEditor.get();
		function hintStart(n:Int):Int return hint.document.lines[n].start;
		function hintOpen():Array<haxe.Int64> return Css.query(hintTree, hintTree.root.id, ".ui-code-hint");
		var sample = hintStart(5) + 6, around = hint.rectAt(sample);
		check("a character has a place in the window, and the place has the character", around != null && hint.offsetAt(around.x + around.width / 2, around.y + around.height / 2) == sample
			&& hint.offsetAt(hint.rectAt(hintStart(9) + 2).x + 1, hint.rectAt(hintStart(9) + 2).y + 5) == hintStart(9) + 2, around);
		check("nothing is at a point over the gutter or past the end of a line", hint.offsetAt(hint.rectAt(hintStart(5)).x - 30, around.y + 4) == -1 && hint.offsetAt(around.x + 400, around.y + 4) == -1);
		hint.scroll.jumpTo(0, 400); hintSettle();
		check("a character out of the view has no place", hint.rectAt(hintStart(0)) == null && hint.rectAt(hintStart(25)) != null);
		hint.scroll.jumpTo(0, 0); hintSettle();
		var over = hint.rectAt(hintStart(3) + 4);
		Pointer.move(hintTree, over.x + 2, over.y + 5); hintSettle();
		check("the hover is not asked before the pointer has rested", asked.length == 0 && hintOpen().length == 0);
		ashui.animation.AnimationScheduler.main.tick(.2); hintSettle();
		check("the hover is not asked early", asked.length == 0);
		ashui.animation.AnimationScheduler.main.tick(.3); hintSettle();
		check("the hover is asked once, for the character under the pointer", asked.join(",") == '${hintStart(3) + 4}', asked);
		check("what the hover gives opens in a popover, signature and docs", hintOpen().length == 1
			&& Css.query(hintTree, hintTree.root.id, ".ui-code-hint-line").length == 2 && Css.query(hintTree, hintTree.root.id, ".ui-code-hint-text").length == 3
			&& Css.query(hintTree, hintTree.root.id, ".ui-code-hint-gap").length == 1, [hintOpen().length, Css.query(hintTree, hintTree.root.id, ".ui-code-hint-text").length]);
		var popup = hintTree.getBounds(Identity.of(hintTree, hintOpen()[0]).node);
		check("the popover is below the start of the range", Math.abs(popup.x - hint.rectAt(hintStart(3) + 4).x) < 2 && popup.y >= over.y + over.height);
		// Staying on the range leaves it open; leaving it closes it a moment later.
		var inside = hint.rectAt(hintStart(3) + 5);
		Pointer.move(hintTree, inside.x + 1, inside.y + 5); ashui.animation.AnimationScheduler.main.tick(1); hintSettle();
		check("the popover stays while the pointer is on its range", hintOpen().length == 1);
		var elsewhere = hint.rectAt(hintStart(8) + 3);
		Pointer.move(hintTree, elsewhere.x + 1, elsewhere.y + 5); hintSettle();
		check("the popover stays a moment after the pointer leaves", hintOpen().length == 1);
		ashui.animation.AnimationScheduler.main.tick(.3); hintSettle();
		check("the popover closes after the pointer has left", hintOpen().length == 0);
		ashui.animation.AnimationScheduler.main.tick(1); hintSettle();
		check("a character the hover has nothing for opens nothing", hintOpen().length == 0);
		// A decoration's title is a hint by itself, and may be several lines.
		hint.decorate("problems", [{from: hintStart(12) + 4, to: hintStart(12) + 6, className: "ui-code-squiggle-error", title: "Unknown identifier\nDid you mean v12?"}]); hintSettle();
		var flagged = hint.rectAt(hintStart(12) + 5);
		Pointer.move(hintTree, flagged.x + 1, flagged.y + 5); ashui.animation.AnimationScheduler.main.tick(.6); hintSettle();
		check("a decoration's title opens a popover, in its colour", hintOpen().length == 1 && Css.query(hintTree, hintTree.root.id, ".ui-code-hint-error").length == 1
			&& Css.query(hintTree, hintTree.root.id, ".ui-code-hint-text").length == 2);
		check("a diagnostic's popover has an icon, and a plain hint has none", Css.query(hintTree, hintTree.root.id, ".ui-code-hint-icon").length == 1);
		// A hint opened from code stays until it is closed, whatever the pointer does.
		hint.showHint({from: hintStart(6), to: hintStart(6) + 3, docs: "Opened from code."}, true); hintSettle();
		check("a hint with no kind has no icon", Css.query(hintTree, hintTree.root.id, ".ui-code-hint-icon").length == 0);
		check("a hint opened from code replaces what is open", hintOpen().length == 1 && Css.query(hintTree, hintTree.root.id, ".ui-code-hint-text").length == 1, [hintOpen().length, Css.query(hintTree, hintTree.root.id, ".ui-code-hint-text").length, hint.hoverOffset]);
		Pointer.move(hintTree, elsewhere.x + 1, elsewhere.y + 5); ashui.animation.AnimationScheduler.main.tick(2); hintSettle();
		check("a pinned hint stays when the pointer is elsewhere", hintOpen().length == 1);
		hint.scroll.jumpTo(0, 60); hintSettle();
		check("scrolling closes it", hintOpen().length == 0);
		hint.showHint({from: hintStart(6), to: hintStart(6) + 3, docs: "Again."}, true); hintSettle();
		hint.hideHint(); hintSettle();
		check("hideHint closes it", hintOpen().length == 0);
		hint.showHint({from: hintStart(6), to: hintStart(6) + 3, docs: "Again."}, true); hintSettle();
		hint.focus(); hint.editing.onEscape(); hintSettle();
		check("Escape closes it", hintOpen().length == 0);
		hint.showHint({from: hintStart(6), to: hintStart(6) + 3, docs: "Again."}, true); hintSettle();
		hint.select(0, 0); Keyboard.text(hintTree, "x"); hintSettle();
		check("an edit closes it", hintOpen().length == 0);
		var richBuilt = 0, richDisposed = 0;
		var rich:Void->ashui.layout.Element = () -> {
			richBuilt++;
			ashui.reactive.Owner.onCleanup(() -> richDisposed++);
			return <div id="rich-hint"><text>Formatted documentation</text></div>;
		};
		hint.showHint({from: hintStart(6), to: hintStart(6) + 3, docs:"Plain fallback", renderDocs:rich}, true); hintSettle();
		check("rich hint content takes precedence over plain docs", richBuilt == 1 && Css.query(hintTree, hintTree.root.id, "#rich-hint").length == 1 && Css.query(hintTree, hintTree.root.id, ".ui-code-hint-text").length == 0);
		hint.showHint({from: hintStart(6), to: hintStart(6) + 3, renderDocs:rich}, true); hintSettle();
		check("replacing rich hint content disposes its owner", richBuilt == 2 && richDisposed == 1);
		hint.hideHint(); hintSettle();
		check("closing rich hint content disposes its owner", richDisposed == 2 && Css.query(hintTree, hintTree.root.id, "#rich-hint").length == 0);
		var call = "f(a:Int, b:String)";
		hint.showHint({from: hintStart(6), to: hintStart(6) + 1, signature: call, emphasis: {from: call.indexOf("b:"), to: call.indexOf(")")}}, true); hintSettle();
		var rowWidth = hintTree.getBounds(Identity.of(hintTree, Css.query(hintTree, hintTree.root.id, ".ui-code-hint-line")[0]).node).width;
		var bold = Css.query(hintTree, hintTree.root.id, '.ui-code-hint-token[data-emphasis="true"]'), boldWidth = 0.0;
		for (id in bold)
			boldWidth += hintTree.getBounds(Identity.of(hintTree, id).node).width;
		check("signature help draws the range it emphasises, and only that", bold.length >= 1 && Math.abs(boldWidth - rowWidth * 8 / call.length) < 1.5, [bold.length, boldWidth, rowWidth]);
		hint.hideHint(); hintSettle();
		hint.showHint({from: hintStart(6), to: hintStart(6) + 1, signature: "function longDocs():Void", docs: [for(i in 0...80) 'Documentation line $i'].join("\n")}, true); hintSettle(); hintSettle();
		var bodyId = Css.query(hintTree, hintTree.root.id, ".ui-code-hint-body")[0];
		var bodyBounds = hintTree.getScrolledBounds(Identity.of(hintTree, bodyId).node), bodyScroll = ashui.input.Scroll.at(bodyId, hintTree);
		check("long plain documentation has a bounded scrollable body", bodyBounds.height <= 320 && bodyScroll != null && bodyScroll.limits().y > 0);
		var editorY = hint.scroll.y.get();
		Pointer.move(hintTree, bodyBounds.x + 20, bodyBounds.y + 20); Pointer.wheel(hintTree, 0, -10000); hintSettle(); hintSettle();
		var docIds = Css.query(hintTree, hintTree.root.id, ".ui-code-hint-text");
		var finalLine = hintTree.getScrolledBounds(Identity.of(hintTree, docIds[docIds.length - 1]).node);
		check("hover wheel reaches the last line without moving the editor or dismissing", bodyScroll.y.get() > 0 && hint.scroll.y.get() == editorY && hintOpen().length == 1
			&& finalLine.y >= bodyBounds.y && finalLine.y + finalLine.height <= bodyBounds.y + bodyBounds.height + 1, [bodyBounds, finalLine]);
		#if ashui_completion_snapshots
		if(Sys.getEnv("ASHUI_COMPLETION_SNAPSHOTS") == "1") ashui.core.render.Snapshot.capture("hint-docs-scrolled", hintTree, hintRoot.node, 760, 400);
		#end
		hint.hideHint(); hintSettle();
		hintDispose(); ashui.animation.AnimationScheduler.main.tick(1); hintTree.dispose();
		// The completion list: narrowed by what is typed, worked by the keys, chosen as one undo step.
		var compTree = new LayoutTree(), compEditor = new Ref<CodeEditor>(), compDispose:Void->Void = null;
		var compRoot = Owner.root(compTree, stop -> {
			compDispose = stop;
			return <div width={760} height={400} class="flex-col p-4"><code-editor ref={compEditor} language="haxe" value={"let al"} height={270} /></div>;
		});
		function compSettle() { compTree.flush(); compTree.computeLayout(compRoot.node, 760, 400); compTree.flush(); }
		compSettle(); compSettle();
		var comp = compEditor.get();
		var offered:Array<ashui.components.code.CodeCompletions.CodeCompletion> = [
			{label: "alpha", kind: "function", detail: "(x:Int):Int", docs: "First line\nSecond line"}, {label: "alphabet", kind: "class"}, {label: "beta"},
			{label: "alpine", insert: "alpine()"}, {label: "parallel"}
		];
		function compRows() return Css.query(compTree, compTree.root.id, ".ui-code-completion-row").length;
		function compKey(k:window.Key, code:window.KeyCode) { Keyboard.input(compTree, key(k, code)); compSettle(); }
		comp.focus(); comp.select(6, 6); compSettle();
		comp.showCompletions(offered); compSettle();
		check("the list opens with what the typed letters match, prefixes first", comp.completionsOpen() && compRows() == 4, compRows());
		check("the selected row's documentation is under the list", Css.query(compTree, compTree.root.id, ".ui-code-completion-docs-text").length == 2);
		compKey(Named(ArrowDown), ArrowDown);
		check("Down moves the selection, and the documentation with it", Css.query(compTree, compTree.root.id, ".ui-code-completion-docs-text").length == 0 && comp.completionsOpen());
		compKey(Named(ArrowUp), ArrowUp);
		Keyboard.text(compTree, "p"); compSettle();
		check("typing narrows the list", comp.completionsOpen() && compRows() == 3, compRows());
		compKey(Named(Enter), Enter);
		check("Enter puts the choice in the text, in place of what was typed", !comp.completionsOpen() && @:privateAccess comp.value.get() == "let alpha" && comp.editing.caret.get() == 9, @:privateAccess comp.value.get());
		comp.undo(); compSettle();
		check("one undo takes the choice back to what was typed before it", @:privateAccess comp.value.get() == "let alp", @:privateAccess comp.value.get());
		comp.select(7, 7); comp.showCompletions(offered); compSettle();
		Keyboard.text(compTree, "("); compSettle();
		check("a character that is not part of a word closes the list", !comp.completionsOpen());
		comp.undo(); comp.select(7, 7); comp.showCompletions(offered); compSettle();
		compKey(Named(Escape), Escape);
		check("Escape closes the list and leaves the text", !comp.completionsOpen() && @:privateAccess comp.value.get() == "let alp");
		comp.showCompletions(offered); compSettle();
		var second = [for (id in Css.query(compTree, compTree.root.id, ".ui-code-completion-row")) compTree.getScrolledBounds(Identity.of(compTree, id).node)][1];
		Pointer.move(compTree, second.x + second.width / 2, second.y + second.height / 2); Pointer.press(compTree); Pointer.release(compTree); compSettle();
		check("a press on a row chooses it", !comp.completionsOpen() && @:privateAccess comp.value.get() == "let alphabet", @:privateAccess comp.value.get());
		comp.undo(); compSettle();
		comp.showCompletions([{label: "alpha", more: [{from: 0, to: 0, text: "import a.Alpha;\n"}]}], 4); compSettle();
		compKey(Named(Tab), Tab);
		check("a choice's other edits go in with it, in one step", @:privateAccess comp.value.get() == "import a.Alpha;\nlet alpha", @:privateAccess comp.value.get());
		comp.undo(); compSettle();
		check("and one undo takes both back", @:privateAccess comp.value.get() == "let alp", @:privateAccess comp.value.get());
		comp.showCompletions(offered, 4); compSettle();
		comp.scroll.jumpTo(0, 30); compSettle();
		check("scrolling closes the list", !comp.completionsOpen());
		comp.scroll.jumpTo(0, 0); compSettle(); comp.focus();
		var many:Array<ashui.components.code.CodeCompletions.CodeCompletion> = [for(i in 0...1000) {label: 'alp' + StringTools.lpad(Std.string(i), "0", 3), docs: 'Documentation $i', kind: "field"}];
		comp.showCompletions(many, 4); compSettle(); compSettle();
		var popupWidth = compTree.getBounds((@:privateAccess comp.completions.panel).node).width;
		check("large completion lists mount only the viewport and overscan", compRows() <= 15 && compRows() >= 10 && @:privateAccess comp.completions.rows.get().length == 200, compRows());
		function compSnapshot(name:String) {
			#if ashui_completion_snapshots
			if(Sys.getEnv("ASHUI_COMPLETION_SNAPSHOTS") == "1") ashui.core.render.Snapshot.capture(name, compTree, compRoot.node, 760, 400);
			#end
		}
		compSnapshot("completion-start");
		compKey(Named(End), End); compSettle();
		var lastSelected = Css.query(compTree, compTree.root.id, ".ui-code-completion-row[data-selected]");
		var lastBounds = compTree.getScrolledBounds(Identity.of(compTree, lastSelected[0]).node);
		var listBounds = compTree.getScrolledBounds((@:privateAccess comp.completions.list).node);
		check("End mounts the last choice and keeps it fully visible", compRows() <= 15 && lastSelected.length == 1 && @:privateAccess comp.completions.selected.get() == 199
			&& lastBounds.y >= listBounds.y && lastBounds.y + lastBounds.height <= listBounds.y + listBounds.height - 3, [lastBounds, listBounds]);
		check("virtual scrolling keeps the popup width stable", popupWidth == compTree.getBounds((@:privateAccess comp.completions.panel).node).width);
		compSnapshot("completion-end");
		compKey(Named(PageUp), PageUp);
		check("Page Up moves through unmounted choices", @:privateAccess comp.completions.selected.get() == 189);
		compKey(Named(Home), Home);
		check("Home restores the first choice", @:privateAccess comp.completions.selected.get() == 0 && comp.completions.scroll.y.get() == 0);
		var beforePixelMove = Css.query(compTree, compTree.root.id, ".ui-code-completion-row");
		@:privateAccess comp.completions.scroll.jumpTo(0, 1); compSettle();
		check("sub-row scrolling reuses mounted row views", beforePixelMove.join(",") == Css.query(compTree, compTree.root.id, ".ui-code-completion-row").join(","));
		Pointer.move(compTree, listBounds.x + 40, listBounds.y + 40); Pointer.wheel(compTree, 0, -2200); compSettle(); compSettle();
		check("wheel scrolling mounts choices beyond the first page", @:privateAccess comp.completions.scroll.y.get() > 1000 && compRows() <= 15);
		compKey(Named(End), End);
		lastSelected = Css.query(compTree, compTree.root.id, ".ui-code-completion-row[data-selected]");
		lastBounds = compTree.getScrolledBounds(Identity.of(compTree, lastSelected[0]).node);
		Pointer.move(compTree, lastBounds.x + 50, lastBounds.y + lastBounds.height / 2); Pointer.press(compTree); Pointer.release(compTree); compSettle();
		check("a virtual row accepts its filtered index", @:privateAccess comp.value.get() == "let alp199", @:privateAccess comp.value.get());
		check("accepting releases all completion metadata", @:privateAccess comp.completions.items.length == 0 && comp.completions.rows.get().length == 0);
		comp.undo(); compSettle(); comp.showCompletions(many, 4); compSettle(); compKey(Named(End), End);
		Keyboard.text(compTree, "19"); compSettle(); compSettle();
		check("filtering a scrolled list resets its viewport", @:privateAccess comp.completions.rows.get().length < 200 && comp.completions.rows.get()[0].item.label == "alp190" && comp.completions.scroll.y.get() == 0 && comp.completions.selected.get() == 0 && compRows() <= 15);
		Keyboard.text(compTree, "z"); compSettle();
		check("no remaining matches release candidates", !comp.completionsOpen() && @:privateAccess comp.completions.items.length == 0 && comp.completions.rows.get().length == 0);
		comp.undo(); comp.undo(); compSettle(); comp.showCompletions(many, 4); compSettle();
		var oldScope = @:privateAccess comp.completions.owner;
		comp.showCompletions([{label: "alpReplacement"}], 4); compSettle();
		@:privateAccess comp.completions.release(oldScope); compSettle();
		check("an old teardown leaves replacement candidates intact", comp.completionsOpen() && compRows() == 1 && @:privateAccess comp.completions.items.length == 1);
		Pointer.move(compTree, 740, 380); Pointer.press(compTree); Pointer.release(compTree); compSettle();
		check("outside dismissal releases candidates and views", !comp.completionsOpen() && compRows() == 0 && @:privateAccess comp.completions.items.length == 0 && comp.completions.rows.get().length == 0);
		comp.showCompletions([{label: "zzz"}], 4); compSettle();
		check("an offer with no matching items retains nothing", !comp.completionsOpen() && @:privateAccess comp.completions.items.length == 0);
		var invalid = new ashui.components.code.CodeCompletions({tree:compTree, rectAt:_ -> null, text:() -> "", caret:() -> 0, apply:_ -> {}});
		invalid.show(many, 0);
		check("an unavailable anchor retains no candidates", !invalid.isOpen() && @:privateAccess invalid.items.length == 0 && invalid.rows.get().length == 0);
		comp.focus();
		comp.showCompletions([{label:"alpDocs", docs:[for(i in 0...40) 'Completion documentation $i'].join("\n")}, {label:"alpOther", docs:"Another choice"}], 4); compSettle(); compSettle();
		var docsId = Css.query(compTree, compTree.root.id, ".ui-code-completion-docs")[0];
		var docsBounds = compTree.getScrolledBounds(Identity.of(compTree, docsId).node), docsScroll = ashui.input.Scroll.at(docsId, compTree);
		check("completion documentation scrolls at its maximum height", docsBounds.height <= 140 && docsScroll != null && docsScroll.limits().y > 0, docsBounds);
		compSnapshot("completion-docs-start");
		var compEditorY = comp.scroll.y.get(), choicesY = comp.completions.scroll.y.get();
		Pointer.move(compTree, docsBounds.x + 20, docsBounds.y + 20); Pointer.wheel(compTree, 0, -10000); compSettle(); compSettle();
		var lines = Css.query(compTree, compTree.root.id, ".ui-code-completion-docs-text");
		var finalDocs = compTree.getScrolledBounds(Identity.of(compTree, lines[lines.length - 1]).node);
		check("completion docs wheel reaches the last line without scrolling the choices or editor", docsScroll.y.get() > 0 && comp.scroll.y.get() == compEditorY && comp.completions.scroll.y.get() == choicesY && comp.completionsOpen()
			&& finalDocs.y >= docsBounds.y && finalDocs.y + finalDocs.height <= docsBounds.y + docsBounds.height + 1, [docsBounds, finalDocs]);
		compSnapshot("completion-docs-scrolled");
		compKey(Named(ArrowDown), ArrowDown);
		check("selecting a different completion resets documentation scrolling", docsScroll.y.get() == 0 && Css.query(compTree, compTree.root.id, ".ui-code-completion-docs-text").length == 1);
		compKey(Named(Escape), Escape);
		check("closing completion docs releases their scroll container", ashui.input.Scroll.at(docsId, compTree) == null);
		function compWatches() {
			var count = 0;
			@:privateAccess for (watch in ashui.reactive.Watch.bySlot) if(watch != null) count++;
			return count;
		}
		var watchesBefore = compWatches();
		for (_ in 0...20) { comp.showCompletions(many, 4); compSettle(); comp.hideCompletions(); compSettle(); }
		check("repeated completion popups release their reactive owners", compWatches() == watchesBefore && compRows() == 0, [watchesBefore, compWatches()]);
		comp.showCompletions(many, 4); compSettle();
		compDispose();
		check("disposing an editor releases its open completion metadata", !comp.completionsOpen() && comp.completions.items.length == 0 && comp.completions.rows.get().length == 0);
		compTree.dispose();
		// An app's keys come before the editor's.
		var keyTree = new LayoutTree(), keyEditor = new Ref<CodeEditor>(), keyDispose:Void->Void = null, seen:Array<String> = [], navigated:Array<Int> = [], taken = ["F2", "ArrowRight"];
		var keyRoot = Owner.root(keyTree, stop -> {
			keyDispose = stop;
			return <div width={760} height={400} class="flex-col p-4"><code-editor ref={keyEditor} language="haxe" value={"abc\ndef"} height={270} onNavigate={offset -> navigated.push(offset)}
				onKey={event -> { var name = switch event.key { case Named(F2): "F2"; case Named(ArrowRight): "ArrowRight"; case Named(ArrowDown): "ArrowDown"; case Character(c): (event.control ? "Ctrl+" : "") + c; case _: "?"; }; seen.push(name); taken.indexOf(name) >= 0; }} /></div>;
		});
		function keySettle() { keyTree.flush(); keyTree.computeLayout(keyRoot.node, 760, 400); keyTree.flush(); }
		keySettle(); keySettle();
		var keyed = keyEditor.get();
		keyed.focus(); keyed.select(0, 0); keySettle();
		Keyboard.input(keyTree, key(Named(F2), F2)); keySettle();
		check("a key the app takes reaches its hook and no further", seen.indexOf("F2") >= 0 && @:privateAccess keyed.value.get() == "abc\ndef");
		Keyboard.input(keyTree, key(Named(ArrowRight), ArrowRight)); keySettle();
		check("a key the app takes does not move the caret", keyed.editing.caret.get() == 0 && seen.indexOf("ArrowRight") >= 0);
		Keyboard.input(keyTree, key(Named(ArrowDown), ArrowDown)); keySettle();
		check("a key the app leaves is the editor's", keyed.editing.caret.get() > 0 && seen.indexOf("ArrowDown") >= 0, keyed.editing.caret.get());
		Keyboard.input(keyTree, key(Character(" "), Space), window.Modifiers.State(false, true, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown)); keySettle();
		check("Ctrl+Space comes to the hook", seen.indexOf("Ctrl+ ") >= 0, seen);
		keyed.select(0, 2); keySettle();
		var navSpot = keyed.rectAt(5), mac = Sys.systemName() == "Mac";
		var navModifiers = window.Modifiers.State(false, !mac, false, mac, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown);
		Pointer.move(keyTree, navSpot.x + navSpot.width / 4, navSpot.y + navSpot.height / 2);
		Pointer.modifiers(keyTree, navModifiers); Pointer.press(keyTree);
		Pointer.move(keyTree, navSpot.x + navSpot.width, navSpot.y + navSpot.height / 2, navModifiers); Pointer.release(keyTree); keySettle();
		check("modifier-click navigates at the pointer without starting selection drag", navigated.join(",") == "5" && keyed.editing.anchor.get() == 0 && keyed.editing.caret.get() == 2, navigated);
		var noModifiers = window.Modifiers.State(false, false, false, false, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown, Unknown);
		var plainSpot = keyed.rectAt(1);
		Pointer.move(keyTree, plainSpot.x + plainSpot.width / 4, plainSpot.y + plainSpot.height / 2, noModifiers); Pointer.press(keyTree); Pointer.release(keyTree); keySettle();
		check("ordinary clicks still place the caret without navigating", navigated.length == 1 && keyed.editing.caret.get() == 1 && keyed.editing.anchor.get() == 1, keyed.editing.caret.get());
		Pointer.move(keyTree, navSpot.x + navSpot.width / 4, navSpot.y + navSpot.height / 2, navModifiers); Pointer.press(keyTree, Right); Pointer.release(keyTree, Right); keySettle();
		Pointer.move(keyTree, 700, 100, navModifiers); Pointer.press(keyTree); Pointer.release(keyTree); keySettle();
		check("secondary clicks and blank editor space do not navigate", navigated.length == 1, navigated);
		keyDispose(); keyTree.dispose();
		// Edits from code are one undo step, however far apart they are.
		var editTree = new LayoutTree(), editEditor = new Ref<CodeEditor>(), editDispose:Void->Void = null, edited:Array<String> = [];
		var editSource = [for (i in 0...5000) 'var v$i = $i;'].join("\n");
		var editRoot = Owner.root(editTree, stop -> {
			editDispose = stop;
			return <div width={760} height={400} class="flex-col p-4"><code-editor ref={editEditor} language="haxe" value={editSource} height={270} onInput={t -> edited.push(t)} /></div>;
		});
		function editSettle() { editTree.flush(); editTree.computeLayout(editRoot.node, 760, 400); editTree.flush(); }
		editSettle(); editSettle();
		var many = editEditor.get();
		function manyStart(n:Int):Int return many.document.lines[n].start;
		var at3 = manyStart(3) + 4, at20 = manyStart(20) + 4, at4990 = manyStart(4990) + 4;
		var start21 = manyStart(21);
		many.select(start21 + 2, start21 + 6);
		many.applyEdits([{from: at4990, to: at4990 + "v4990".length, text: "renamed"}, {from: at3, to: at3 + 2, text: "renamed"}, {from: at20, to: at20 + 3, text: "renamed"}]);
		editSettle();
		var renamed = @:privateAccess many.value.get();
		check("edits from code, in any order, change each stretch", renamed.indexOf("var renamed = 3;") == manyStart(3) && renamed.indexOf("var renamed = 20;") > 0
			&& renamed.indexOf("var renamed = 4990;") > 0 && renamed.indexOf("var v3 =") < 0 && edited.length == 1, edited.length);
		check("the selection moves with the text", many.editing.anchor.get() == start21 + 2 + 9 && many.editing.caret.get() == start21 + 6 + 9, [many.editing.anchor.get(), many.editing.caret.get(), start21]);
		many.undo(); editSettle();
		check("one undo takes them all back, and the selection", @:privateAccess many.value.get() == editSource && many.editing.anchor.get() == start21 + 2);
		many.redo(); editSettle();
		check("one redo makes them again", @:privateAccess many.value.get() == renamed);
		many.undo(); editSettle();
		check("edits far apart in a long document are one step of a few bytes", @:privateAccess many.value.get() == editSource);
		var refused = false;
		try many.applyEdits([{from: 10, to: 20, text: "a"}, {from: 15, to: 25, text: "b"}]) catch (e:Dynamic) refused = true;
		check("edits that overlap are refused", refused && @:privateAccess many.value.get() == editSource);
		many.applyEdits([{from: 3, to: 3, text: ""}]);
		check("an edit that changes nothing is none", @:privateAccess many.value.get() == editSource && edited.length == 4, edited.length);
		editDispose(); editTree.dispose();
		var styleTree = new LayoutTree(), styleStop:Void->Void = null, styledView = new Ref<CodeView>(), plainView = new Ref<CodeView>();
		var styledValue = signal("styled token");
		var styleRoot = Owner.root(styleTree, stop -> {
			styleStop = stop;
			return <div width={600} height={400} class="flex-col">
				<code-view ref={styledView} value={styledValue} highlighter={new FormattedHighlighter()} tokenStyles={true} height={150}/>
				<code-view ref={plainView} value={styledValue} highlighter={new FormattedHighlighter()} height={150}/>
			</div>;
		});
		function styleSettle() { Css.update(); styleTree.flush(); styleTree.computeLayout(styleRoot.node, 600, 400); }
		styleSettle(); styleSettle();
		var styledIds = Css.query(styleTree, styledView.get().node.id, ".ui-code-token");
		var tokenIdentity = Identity.of(styleTree, styledIds[0]);
		var declarations = tokenIdentity.inlineDeclarations();
		check("styled highlight spans survive compact token storage", styledView.get().document.lines[0].tokenStyle(0).color == "#123456"
			&& styledView.get().document.lines[0].tokens[0].style.background == "#654321");
		check("opt-in spans render foreground, background and text attributes", declarations.get("color") == "#123456"
			&& declarations.get("background-color") == "#654321" && declarations.get("font-weight") == "700"
			&& declarations.get("font-style") == "italic" && declarations.get("text-decoration") == "underline");
		var ordinary = Identity.of(styleTree, Css.query(styleTree, plainView.get().node.id, ".ui-code-token")[0]).inlineDeclarations();
		check("ordinary viewers ignore custom styles unless enabled", ordinary == null || !ordinary.exists("color"));
		styledValue.set("plain token"); styleSettle(); styleSettle();
		check("pooled tokens clear stale inline formatting", Css.query(styleTree, styledView.get().node.id, ".ui-code-token").join(",") == styledIds.join(",")
			&& !declarations.exists("color") && !declarations.exists("background-color") && !declarations.exists("font-weight")
			&& !declarations.exists("font-style") && !declarations.exists("text-decoration"));
		styleStop(); styleTree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}

private class FormattedHighlighter implements CodeHighlighter {
	public function new() {}
	public function highlight(line:String, state:String):CodeHighlight {
		return {tokens:[{from:0, to:line.length, kind:Plain, style:StringTools.startsWith(line, "styled") ?
			{color:"#123456", background:"#654321", fontWeight:"700", fontStyle:"italic", textDecoration:"underline"} : null}], state:""};
	}
}
