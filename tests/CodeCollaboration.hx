import ashui.components.CodeEditor;
import ashui.components.code.CodeEditorState;
import ashui.components.code.CodeHistory;
import ashui.components.code.CodeTransaction;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;

@:access(ashui.components.code.CodeEditorState)
class CodeCollaboration {
	static function check(ok:Bool,message:String):Void { if (!ok) throw message; }
	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(),Light);
		var state=new CodeEditorState(), events:Array<CodeTransaction>=[], inputs=0, undos:Array<Bool>=[];
		state.value.set("a🦀b"); state.onTransaction=edit -> events.push(edit); state.onUndo=redo -> undos.push(redo);
		var tree=new LayoutTree(), stop:Void->Void=null;
		var editor=Owner.root(tree,cleanup -> { stop=cleanup; return new CodeEditor({state:state,onInput:_ -> inputs++}); });
		function settle():Void { tree.flush(); Css.setViewport(600,300); Css.update(); tree.computeLayout(editor.node,600,300); }
		settle();
		editor.applyEdits([{from:0,to:1,text:"A"},{from:3,to:4,text:"B"}]); settle();
		check(events.length==1 && events[0].parts.length==2 && state.value.get()=="A🦀B","An atomic multi-range transaction was flattened");
		editor.select(1,3); editor.editing.replace("🦊"); settle();
		check(events.length==2 && events[1].parts[0].from==1 && events[1].parts[0].removed=="🦀" && events[1].parts[0].inserted=="🦊","A Unicode transaction split a surrogate pair");
		editor.undo(); editor.redo(); check(undos.length==2 && !undos[0] && undos[1],"Undo did not delegate to document ownership");
		state.applyRemote("remote",{caret:2,anchor:0}); settle();
		check(events.length==2 && inputs==2 && editor.editing.caret.get()==2 && editor.editing.anchor.get()==0,"Remote input echoed or lost selection");
		state.onUndo=null;
		editor.applyEdits([{from:0,to:0,text:"local "}]); editor.undo(); settle();
		check(events.length==4 && events[3].after=="remote","Ordinary undo was omitted from the transaction stream");
		state.peers.set([{id:"peer",name:"Peer",caret:2,anchor:0,color:1}]); settle();
		check(Css.query(tree,editor.node.id,".ui-code-peer-caret").length==1,"Peer caret was not drawn");
		Css.add(ashui.css.Stylesheet.parse(".ui-code-peer-name { font-family: sans-serif; }"));
		function labelWidth(name:String):Float {
			state.peers.set([{id:"peer",name:name,caret:2,anchor:0,color:1}]); settle();
			var labels=Css.query(tree,editor.node.id,".ui-code-peer-name");
			check(labels.length==1,"Peer name label was not drawn");
			return tree.getBounds(new ashui.layout.Node(labels[0])).width;
		}
		var narrow=labelWidth("iiii"), wide=labelWidth("WWWW");
		check(narrow > 6 && wide > narrow + 10,"Peer label width did not follow glyph measurements");
		var normal=labelWidth("raikage"), unicode=labelWidth("Miyuki 美雪 🌊");
		check(normal > 6 && unicode > normal,"Unicode peer labels lost their measured content");
		check(labelWidth([for (_ in 0...100) "W"].join("")) <= 220.1,"Long peer labels escaped their width cap");
		check(Math.abs(labelWidth("iiii")-narrow)<.1,"Replacing a long name retained its old label width");
		stop(); check(!state.mounted && state.receive==null,"State retained a disposed presentation"); tree.dispose();
		state.applyRemote("unmounted",{caret:4,anchor:4});
		var replacement=new LayoutTree();
		editor=Owner.root(replacement,cleanup -> { stop=cleanup; return new CodeEditor({state:state}); });
		replacement.flush(); check(editor.value.get()=="unmounted" && editor.editing.caret.get()==4,"External text was lost between presentations");
		stop(); replacement.dispose();
		Sys.println("Editor collaboration: exact ranges, Unicode, delegated undo, external apply, peer marks, content-sized capped labels and presentation cleanup");
	}
}
