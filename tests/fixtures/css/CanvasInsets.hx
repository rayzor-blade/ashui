import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;

/** Canvas defaults must yield to insets and keep draw dimensions synchronized (34d767c). **/
class CanvasInsets {
	static var checks = 0;
	static function check(name:String, ok:Bool) { if (!ok) throw name; checks++; Sys.println('ok   $name'); }
	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var tree=new LayoutTree(), stop:Void->Void=null, width=Signal.make((500:Single)), position=Signal.make(Position.Absolute);
		var drawWidth=0., drawHeight=0., draws=0;
		var root=Owner.root(tree, cleanup -> {
			stop=cleanup;
			return <div width={width} height={400} alignItems={Start}>
				<canvas id="stretch" position={position} left={10} right={20} top={30} bottom={40}
					draw={ctx -> {drawWidth=ctx.width;drawHeight=ctx.height;draws++;}} />
				<canvas id="natural" />
				<canvas id="explicit" position={Absolute} left={0} right={0} top={0} bottom={0} width={80} height={60} />
				<canvas id="partial" position={Absolute} left={0} top={0} bottom={0} />
				<canvas id="percent" position={Absolute} left={0} right={0} top={0} bottom={0} widthPercent={.5} />
				<canvas id="css" />
			</div>;
		});
		function node(id:String) return new Node(Css.query(tree,root.node.id,"#"+id)[0]);
		function bounds(id:String) return tree.getBounds(node(id));
		function settle() for (_ in 0...3) {tree.flush();tree.computeLayout(root.node,width.get(),400);}
		settle();
		check("paired insets stretch both axes", bounds("stretch").width==470 && bounds("stretch").height==330);
		check("draw dimensions follow the measured content", drawWidth==470 && drawHeight==330);
		check("unsized canvas retains its default dimensions", bounds("natural").width==300 && bounds("natural").height==150);
		check("explicit size wins over insets", bounds("explicit").width==80 && bounds("explicit").height==60);
		check("a single horizontal inset keeps the fallback width", bounds("partial").width==300 && bounds("partial").height==400);
		check("percentage width wins and height still stretches", bounds("percent").width==250 && bounds("percent").height==400);
		width.set(600); settle(); check("parent resize updates the box and drawing", bounds("stretch").width==570 && drawWidth==570);
		position.set(Position.Relative); settle(); check("relative position restores fallback dimensions", bounds("stretch").width==300 && drawHeight==150);
		position.set(Position.Absolute); settle(); check("reactive absolute position stretches again", drawWidth==570 && drawHeight==330);
		var sheet=Css.load('#css {position:absolute;inset:5px;}');settle();
		check("CSS insets work without HXX positioning",bounds("css").width==590 && bounds("css").height==390);
		Identity.of(tree,node("css").id).setInline("width","120px");settle();check("authored CSS size overrides insets",bounds("css").width==120);
		Identity.of(tree,node("css").id).setInline("width",null);settle();check("removing CSS size restores stretching",bounds("css").width==590);
		Css.remove(sheet);settle();check("removing positioning CSS restores default size",bounds("css").width==300 && bounds("css").height==150);
		var before=draws;settle();check("settled geometry does not record new drawing",before==draws);
		stop();tree.dispose();Sys.println('$checks checks: ALL PASSED');
	}
}
