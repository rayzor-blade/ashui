import ashui.components.CodeEditor;
import ashui.components.code.CodeHighlighter;
import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.ui.Ref;

class CodeReactiveSyntax {
	static function check(ok:Bool,message:String):Void if (!ok) throw message;
	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.RestrainedTheme.bundle(),Dark);
		var tree=new LayoutTree(),ref=new Ref<CodeEditor>(),dispose:Void->Void=null;
		var source=[for (i in 0...200) 'var value$i = "' + [for (_ in 0...100) "wide source "].join("") + '";'].join("\n");
		var grammar=Signal.make((null:Null<CodeHighlighter>));
		var root=Owner.root(tree,cleanup->{dispose=cleanup;return <div width={800} height={500} class="flex flex-col"><code-editor ref={ref} value={source} highlighterSource={grammar} class="flex-1 min-h-0"/></div>;});
		function settle():Void for (_ in 0...6) {Offscreen.advance(.02);Css.setViewport(800,500);Css.update();tree.flush();tree.computeLayout(root.node,800,500);}
		try {
			settle();var editor=ref.get();editor.focus();ashui.input.Keyboard.text(tree,"x");settle();
			check(editor.value.get()!=source,"Typing did not record an edit");
			editor.select(5,15);editor.scroll.jumpTo(1500,800);settle();
			var text=editor.value.get(),caret=editor.editing.caret.get(),anchor=editor.editing.anchor.get(),x=editor.scroll.x.get(),y=editor.scroll.y.get();
			grammar.set(new OneKind(Keyword));settle();
			check(editor.document.lines[0].tokenKind(0)==Keyword,"Reactive grammar did not recolor the mounted document");
			check(editor.value.get()==text&&editor.editing.caret.get()==caret&&editor.editing.anchor.get()==anchor,"Grammar changed text or selection");
			check(Math.abs(editor.scroll.x.get()-x)<.1&&Math.abs(editor.scroll.y.get()-y)<.1,"Grammar moved the viewport back to the caret");
			grammar.set(new OneKind(Comment));settle();
			check(editor.document.lines[0].tokenKind(0)==Comment,"Second grammar result was not applied");
			editor.undo();settle();check(editor.value.get()==source,"Grammar replacement lost undo history");
			Sys.println("Reactive syntax: recoloring preserves source, selection, viewport and undo history");
		} catch (error:Dynamic) {dispose();tree.dispose();throw error;}
		dispose();tree.dispose();
	}
}

private class OneKind implements CodeHighlighter {
	final kind:CodeTokenKind;
	public function new(kind:CodeTokenKind) this.kind=kind;
	public function highlight(line:String,state:String):CodeHighlight return {tokens:line==""?[]:[{from:0,to:line.length,kind:kind}],state:""};
}
