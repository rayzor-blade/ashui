import ashui.animation.AnimationScheduler;
import ashui.components.Button;
import ashui.components.Input;
import ashui.components.Tooltip;
import ashui.css.Css;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.RestrainedTheme;
import ashui.ui.TopLayer;

class TooltipDisposal {
	static function main():Void {
		for(dark in [true,false]) for(state in ["waiting","open","closing"]) for(action in ["backspace","clear","dispose"])
			run(dark,state,action);
		Sys.println("18 checks: ALL PASSED");
	}
	static function run(dark:Bool,state:String,action:String):Void {
		ThemeState.init(RestrainedTheme.bundle(),dark?Dark:Light); ashui.components.Library.use();
		var tree=new LayoutTree(), search=Signal.make(""), stop=() -> {};
		var root=Owner.root(tree,dispose -> {
			stop=dispose;
			return <div width={300} height={100}>
				<input id="search" value={search}/>
				<if {search.get()!=""}><tooltip label="Clear search"><button id="clear" onClick={_ -> search.set("")}>Clear</button></tooltip></if>
			</div>;
		});
		function flush() {tree.flush(); tree.computeLayout(root.node,300,100);}
		flush(); var initialNodes=tree.order().length, rootId=root.node.id;
		Focus.set(Interaction.byId(tree,Css.query(tree,root.node.id,"#search")[0]),true);
		Keyboard.text(tree,"a"); flush();
		var b=tree.getBounds(new Node(Css.query(tree,root.node.id,"#clear")[0]));
		Pointer.move(tree,b.x+b.width/2,b.y+b.height/2);
		AnimationScheduler.main.tick(state=="waiting"?0.1:0.6); flush();
		if(state=="open" && TopLayer.openEntries().length!=1) throw "Tooltip did not open";
		if(state=="closing") {Pointer.leave(tree); flush();}
		switch(action) {
			case "backspace":
				Keyboard.input(tree,Input(Code(Backspace),Named(Backspace),None,Standard,Pressed,false,Unavailable));
				flush();
			case "clear":
				Pointer.move(tree,b.x+b.width/2,b.y+b.height/2); Pointer.press(tree); Pointer.release(tree); flush();
			case "dispose": stop();
		}
		AnimationScheduler.main.tick(1); tree.flush();
		if(TopLayer.openEntries().length!=0) throw "Orphaned tooltip entry: "+state+"/"+action;
		if(action!="dispose") {
			flush();
			if(search.get()!="" || tree.order().length!=initialNodes) throw "Orphaned search or top-layer nodes: "+state+"/"+action;
			// A new conditional branch must remain usable after the old one is gone.
			Focus.set(Interaction.byId(tree,Css.query(tree,root.node.id,"#search")[0]),true);
			Keyboard.text(tree,"a"); flush();
			var again=tree.getBounds(new Node(Css.query(tree,root.node.id,"#clear")[0]));
			Pointer.move(tree,again.x+again.width/2,again.y+again.height/2); AnimationScheduler.main.tick(.6); flush();
			if(TopLayer.openEntries().length!=1) throw "Replacement tooltip did not open";
			stop(); AnimationScheduler.main.tick(1); tree.flush();
		}
		if(TopLayer.openEntries().length!=0 || root.node!=null || tree.children(rootId).length!=0) throw "Root disposal left top-layer nodes: "+state+"/"+action+" entries="+TopLayer.openEntries().length+" nodes="+tree.order().length;
		stop(); tree.dispose();
		Sys.println('ok   ${dark?"dark":"light"} $state/$action');
	}
}
