import ashui.components.CodeEditor;
import ashui.components.CodeView;
import ashui.components.code.CodeEditorState;
import ashui.components.code.CodeSearch;
import ashui.css.Css;
import ashui.input.Keyboard;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Reactive;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

class CodeFindTest {
	static function check(name:String, ok:Bool):Void { if (!ok) throw name; Sys.println('ok   $name'); }
	static function main():Void {
		var s = new CodeSearch("hello HELLO shello héllo", "hello");
		check("literal case-insensitive matches", s.matches.length == 3);
		check("whole-word boundaries", new CodeSearch("hello HELLO shello", "hello", false, true).matches.length == 2);
		check("whole-word Unicode boundaries", new CodeSearch("cat écat cat猫 cat", "cat", false, true).matches.length == 2);
		check("literal punctuation is escaped", new CodeSearch("a.b axb", "a.b").matches.length == 1);
		check("case-sensitive matches", new CodeSearch("hello HELLO", "hello", true).matches.length == 1);
		var haxe = new CodeSearch("item12 ITEM34\nitem56", "~/item(\\d+)/i", true, false, true);
		check("Haxe regex syntax and explicit flags", haxe.error == null && haxe.matches.length == 3);
		check("Haxe capture replacements and dollar escaping", haxe.edits("value$1 $$")[1].text == "value34 $");
		check("regex flags control multiline anchors", new CodeSearch("a\na", "~/^a$/m", true, false, true).matches.length == 2 && new CodeSearch("a\na", "~/^a$/", true, false, true).matches.length == 0);
		check("escaped slash in Haxe literal", new CodeSearch("a/b", "~/a\\/b/", true, false, true).matches.length == 1);
		check("regex dotall", new CodeSearch("a\nb", "~/a.b/s", true, false, true).matches.length == 1);
		check("bare regex patterns", new CodeSearch("cat12 dog34", "[a-z]+\\d+", true, false, true).matches.length == 2);
		check("invalid regex is data", new CodeSearch("a", "[", false, false, true).error != null);
		check("invalid Haxe flags are data", new CodeSearch("a", "~/a/q", false, false, true).error != null);
		check("zero-width regex terminates including EOF", new CodeSearch("ab", "(?=)|$", true, false, true).matches.length == 3);
		check("zero-width Unicode does not split surrogate pairs", new CodeSearch("🌍", "(?=)", true, false, true).matches.length == 2);
		check("literal replacement keeps dollars", new CodeSearch("x", "x").edits("$1")[0].text == "$1");
		for (dark in [true, false]) {
			ThemeState.init(DefaultTheme.bundle(), dark ? Dark : Light);
			var initial = 'class Example {\n    var item12 = 1;\n    var item34 = 2;\n}\n' + [for (i in 0...200) '// line$i\n'].join("");
			var state = new CodeEditorState(signal(initial)), shown = signal(true), readOnly = signal(false), disabled = signal(false), ref = new Ref<CodeEditor>(), viewer = new Ref<CodeView>();
			var tree = new LayoutTree(), dispose:Void->Void = null;
			var root = Owner.root(tree, stop -> {
				dispose = stop;
				return <div width={760} height={600} class="flex-col">
					<if {shown.get()}><code-editor ref={ref} state={state} readOnly={readOnly} disabled={disabled} language="haxe" minimap={true} width={760} height={400}/></if>
					<code-view ref={viewer} value="read only example" width={760} height={180}/>
				</div>;
			});
			function settle() for (_ in 0...6) { Css.update(); tree.flush(); tree.computeLayout(root.node,760,600); ashui.animation.AnimationScheduler.main.tick(.016); }
			function press(k:window.Key, shift=false, mod=false, alt=false):Void {
				var mac = Sys.systemName() == "Mac";
				Keyboard.input(tree, Input(Unidentified(Unidentified),k,None,Standard,Pressed,false,Unavailable), window.Modifiers.State(shift,!mac && mod,alt,mac && mod,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown)); settle();
			}
			settle(); var ed = ref.get(); ed.focus(); press(Character("f"),false,true);
			var panelId = Css.query(tree,ed.node.id,".ui-code-find")[0];
			var panelBounds = tree.getBounds(new ashui.layout.Node(panelId));
			check("find floats at a compact width", panelBounds.width < 500 && panelBounds.width < tree.getBounds(ed.node).width);
			ed.node.set(ashui.layout.Prop.Width,(320:Single)); settle();
			panelBounds = tree.getBounds(new ashui.layout.Node(panelId));
			var editorBounds = tree.getBounds(ed.node);
			check("find stays within a narrow editor", panelBounds.width <= editorBounds.width-15 && panelBounds.x >= editorBounds.x);
			ed.node.set(ashui.layout.Prop.Width,(760:Single)); settle();
			check("shortcut opens built-in find", state.search.opened.get() && Css.query(tree,ed.node.id,".ui-code-find-query").length == 1);
			state.search.regex.set(true); state.search.query.set("~/item(12|34)/"); settle();
			check("editor search finds two captured results", ed.search.result.get().matches.length == 2 && Css.query(tree,ed.node.id,".ui-code-find-mark").length == 2);
			var first = ed.editing.anchor.get(); press(Named(Enter)); check("Enter selects next result", ed.editing.anchor.get() > first);
			press(Named(Enter)); check("navigation wraps", ed.editing.anchor.get() == first);
			press(Named(Enter),true); check("Shift+Enter selects previous result", ed.editing.anchor.get() > first);
			state.search.replacing.set(true); state.search.replacement.set("entry$1"); settle(); ed.search.replaceAll(); settle();
			check("replace all uses captures", state.value.get().indexOf("var entry12") >= 0 && state.value.get().indexOf("var entry34") >= 0);
			ed.focus(); ed.undo(); settle(); check("replace all is one undo step", state.value.get() == initial);
			ed.redo(); settle(); check("replace all redo", state.value.get().indexOf("var entry34") >= 0); ed.undo(); settle();
			ed.select(0,0); ed.applyEdits([{from:0,to:0,text:"// edit\n"}]); settle();
			check("editing with find open does not jump to a match", ed.editing.caret.get() == 0); ed.undo(); settle();
			state.search.query.set("item34"); state.search.regex.set(false); state.search.replacement.set("changed"); ed.search.replaceAll();
			check("replace uses the current input before an event-batch flush", state.value.get().indexOf("var changed") >= 0 && state.value.get().indexOf("var item12") >= 0); ed.undo(); settle();
			state.search.query.set("line199"); state.search.regex.set(false); settle();
			check("find reveals offscreen result without editor focus", ed.scroll.y.get() > 1000);
			state.search.query.set("line"); settle();
			check("highlight nodes are bounded to visible rows", ed.search.result.get().matches.length == 200 && Css.query(tree,ed.node.id,".ui-code-find-mark").length > 0 && Css.query(tree,ed.node.id,".ui-code-find-mark").length <= 30);
			state.search.query.set("item12"); settle(); ed.toggleFold(0); settle(); ed.findNext(); settle();
			check("find unfolds a hidden result", !ed.document.lines[0].folded);
			readOnly.set(true); settle(); var before = state.value.get(); ed.search.replaceAll(); ed.search.replaceOne(); settle();
			check("read-only search refuses replacements", state.value.get() == before && Css.query(tree,ed.node.id,".ui-code-find-replace-row").length == 0);
			readOnly.set(false); settle(); check("replacement controls remount after unlocking", Css.query(tree,ed.node.id,".ui-code-find-replacement").length == 1); disabled.set(true); settle(); ed.search.replaceAll(); check("disabled search refuses replacements", state.value.get() == before); disabled.set(false); settle();
			shown.set(false); settle(); check("unmount releases controls and state capture", ref.get() == null && !state.mounted && Css.query(tree,root.node.id,".ui-code-find").length == 0);
			shown.set(true); settle(); ed=ref.get(); check("search inputs restore without retaining a view", state.search.query.get() == "item12" && ed.search.result.get().matches.length == 1);
			ed.hideFind(); settle(); check("closing find releases matches and controls", ed.search.result.get().matches.length == 0 && Css.query(tree,ed.node.id,".ui-code-find").length == 0);
			ed.focus();
			Keyboard.input(tree, Input(Unidentified(Unidentified),Character("f"),None,Standard,Pressed,false,Unavailable), window.Modifiers.State(false,true,false,true,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown)); settle();
			check("extra modifiers do not steal application shortcuts", !state.search.opened.get());
			viewer.get().focus(); press(Character("f"),false,true); check("CodeView also supports find", viewer.get().state.search.opened.get());
			dispose(); tree.dispose();
		}
	}
}
