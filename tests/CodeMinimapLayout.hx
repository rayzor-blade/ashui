import ashui.components.CodeEditor;
import ashui.components.Library;
import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.ui.Ref;

class CodeMinimapLayout {
	static function check(on:Bool, message:String):Void { if (!on) throw message; }
	static function main():Void {
		Library.use();
		for (dark in [false,true]) for (withHeader in [false,true]) {
			ashui.theme.ThemeState.init(ashui.theme.themes.RestrainedTheme.bundle(),dark ? Dark : Light);
			var tree = new LayoutTree(), ref = new Ref<CodeEditor>(), dispose:Void->Void = null;
			var root = Owner.root(tree,cleanup -> {
				dispose = cleanup;
				var header = withHeader ? <div id="header" height={28} flexShrink={0}><text>src / Main.hx</text></div> : null;
				return <div widthPercent={1} heightPercent={1} class="flex flex-col">
					<code-editor ref={ref} header={header} minimap={true} value={[for (i in 0...1000) 'line $i'].join("\n")} class="flex-1 min-h-0"/>
				</div>;
			});
			function settle(width:Int,height:Int):Void for (_ in 0...8) {
				Offscreen.advance(.025); Css.setViewport(width,height); Css.update(); tree.flush(); tree.computeLayout(root.node,width,height);
			}
			function bounds(selector:String):ashui.layout.Bounds {
				var found=Css.query(tree,root.node.id,selector);check(found.length==1,'Missing $selector');return tree.getScrolledBounds(new Node(found[0]));
			}
			try {
				for (size in [{w:960,h:640},{w:420,h:300}]) {
					settle(size.w,size.h);
					var editor=bounds(".ui-code"), map=bounds(".ui-code-minimap"), viewport=bounds(".ui-code-viewport");
					check(Math.abs(map.y-editor.y-1)<.1 && Math.abs(map.x+map.width-editor.x-editor.width+1)<.1,"Minimap does not meet the editor's inner top/right edges");
					check(Math.abs(map.y+map.height-editor.y-editor.height+1)<.1,"Minimap height changed after resizing");
					check(Math.abs(viewport.x+viewport.width-map.x)<.1,"Text viewport overlaps or separates from the minimap");
					if (withHeader) {var header=bounds("#header");check(Math.abs(header.y-map.y)<.1 && Math.abs(viewport.y-header.y-header.height)<.1,"Header moved above the minimap or into the text viewport");}
					var x=map.x+map.width/2;
					ashui.input.Pointer.move(tree,x,map.y+map.height-1);ashui.input.Pointer.press(tree);ashui.input.Pointer.release(tree);settle(size.w,size.h);
					var bottom=bounds(".ui-code-minimap-slider");check(Math.abs(bottom.y+bottom.height-map.y-map.height)<1,"Bottom click did not position the slider at the end");
					ashui.input.Pointer.move(tree,x,map.y+1);ashui.input.Pointer.press(tree);ashui.input.Pointer.release(tree);settle(size.w,size.h);
					check(Math.abs(bounds(".ui-code-minimap-slider").y-map.y)<1,"Top click did not scroll back to the start");
				}
			} catch (error:Dynamic) {dispose();tree.dispose();throw error;}
			dispose();tree.dispose();
		}
		Sys.println("Minimap: header and bare editor edges, resize, slider mapping and click navigation in both themes");
	}
}
