import ashui.components.CodeEditor;
import ashui.components.code.CodeEditorState;
import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;

class CodePointerSelection {
	static function check(ok:Bool, message:String):Void if (!ok) throw message;
	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var tree = new LayoutTree(), stop:Void->Void = null, state = new CodeEditorState();
		var source = "first line\nsecond line\nthird line\nfourth line";
		state.value.set(source);
		var edits = 0, actions = 0;
		state.onTransaction = _ -> edits++;
		var editor = Owner.root(tree, cleanup -> {
			stop = cleanup;
			return new CodeEditor({state:state, minimap:true, codeActions:[{line:2,actions:[{label:"Run",run:() -> actions++}]}]});
		});
		function settle():Void for (_ in 0...5) {
			Offscreen.advance(.025); Css.setViewport(700,400); Css.update(); tree.flush(); tree.computeLayout(editor.node,700,400);
		}
		function move(offset:Int):Void {
			var box = editor.rectAt(offset);
			Pointer.move(tree,box.x + 1,box.y + box.height / 2);
		}
		try {
			settle();
			for (readOnly in [false,true]) {
				editor.editing.readOnly = readOnly;
				for (_ in 0...4) for (back in [false,true]) {
					move(back ? 33 : 0); Pointer.press(tree); settle();
					move(back ? 0 : 33); settle(); Pointer.release(tree); settle();
					check(editor.editing.selection() == source.substr(0,33),"Drag selection lost its anchor or direction");
					check(Css.query(tree,editor.node.id,".ui-code-selection").length == 3,"Multiline selection was not painted");
				}
			}
			var bar = tree.getScrolledBounds(new Node(Css.query(tree,editor.node.id,".ui-code-action")[0]));
			move(0); Pointer.press(tree); settle();
			Pointer.move(tree,bar.x + bar.width / 2,bar.y + bar.height / 2); settle();
			check(editor.editing.caret.get() > 0,"Inline actions intercepted an active text drag");
			Pointer.move(tree,750,420); settle(); Pointer.release(tree); settle();
			check(editor.editing.caret.get() == source.length && editor.editing.anchor.get() == 0,"Selection stopped at the editor boundary");
			move(33); settle();
			check(editor.editing.caret.get() == source.length,"Released drag continued selecting");
			move(33); Pointer.press(tree); move(0); Pointer.release(tree); settle();
			check(editor.editing.caret.get() == 0 && editor.editing.anchor.get() == 33,"A subsequent drag retained the previous capture");
			check(edits == 0 && actions == 0 && state.value.get() == source,"Pointer selection invoked a command or a document transaction");
		} catch (error:Dynamic) { stop(); tree.dispose(); throw error; }
		stop(); tree.dispose();
		Sys.println("Code selection: repeated directions, read-only text, inline actions, captured boundaries and no document edits");
	}
}
