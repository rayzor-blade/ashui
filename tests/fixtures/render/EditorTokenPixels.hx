import ashui.components.CodeEditor;
import ashui.core.render.Offscreen;
import ashui.css.Css;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.ui.Ref;
import gpu.GpuTextureViewDescriptor;

/** Windowed token runs must paint like complete rows, including horizontal pans and graphemes. */
@:access(ashui.components.CodeEditor)
class EditorTokenPixels {
	static function check(name:String, ok:Bool):Void { if(!ok) throw name; Sys.println("ok   "+name); }
	static function main():Void {
		for (dark in [false,true]) {
			ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(),dark?Dark:Light);
			var tree=new LayoutTree(), left=new Ref<CodeEditor>(), right=new Ref<CodeEditor>(), stop=()->{};
			var source=[for(i in 0...70) i%4==0 ? "  \t  " : "\tvar value"+i+" = "+[for(j in 0...65) 'part$j + "λ é 😀"'].join(" + ")+";"].join("\n");
			var root=Owner.root(tree,cleanup->{stop=cleanup;return <div width={800} height={400} class="flex flex-row">
				<code-editor ref={left} value={source} language="haxe" width={400} height={400} readOnly={true} lineNumbers={true}/>
				<code-editor ref={right} value={source} language="haxe" width={400} height={400} readOnly={true} lineNumbers={true} tokenStyles={true}/>
			</div>;});
			var off=Offscreen.create(),texture=off.createTexture(800,400),view=texture.createView(new GpuTextureViewDescriptor());
			function settle():Void for(_ in 0...5) {Css.update();tree.flush();tree.computeLayout(root.node,800,400);}
			settle();
			var metrics=left.get().metrics,line=left.get().document.lines[1],stops=metrics.measure(line).stops;
			for(column in -1...line.text.length+2) {
				var expected=0.;for(stop in stops) {if(stop.index>column) break; expected=stop.x;}
				checkPosition(metrics.xAt(line,column)==expected);
			}
			check("caret lookup preserves tab and grapheme positions",true);
			for(pos in [{x:0.,y:0.},{x:260.,y:120.},{x:1600.,y:600.},{x:0.,y:0.}]) {
				left.get().scroll.jumpTo(pos.x,pos.y);right.get().scroll.jumpTo(pos.x,pos.y);settle();
				var reference=right.get();
				reference.distribute(reference.visibleRows(reference.windowStart(),reference.windowEnd(),0,1e9),reference.slotRows.length);
				off.render(root,view,800,400);
				var pixels=off.readRgba8(texture,800,400),same=true;
				for(y in 5...395) for(x in 5...395) for(channel in 0...4)
					// Integer translations can round clip-edge antialiasing by one channel value.
					if(Math.abs(pixels.get((y*800+x)*4+channel)-pixels.get((y*800+x+400)*4+channel))>1) same=false;
				check("windowed runs match full-row pixels at "+pos.x+","+pos.y+" ("+dark+")",same);
				var mounted=Css.query(tree,left.get().node.id,".ui-code-token").length;
				var complete=Css.query(tree,right.get().node.id,".ui-code-token").length;
				check("offscreen and whitespace runs avoid text widgets",mounted*2<complete);
			}
			var tokenIds=Css.query(tree,left.get().node.id,".ui-code-token").join(",");
			left.get().scroll.jumpTo(10,0);settle();
			check("a small horizontal pan reuses token widgets",Css.query(tree,left.get().node.id,".ui-code-token").join(",")==tokenIds);
			stop();tree.dispose();view.destroy();texture.destroy();
		}
	}
	static function checkPosition(ok:Bool):Void {if(!ok) throw "caret lookup changed a source boundary";}
}
