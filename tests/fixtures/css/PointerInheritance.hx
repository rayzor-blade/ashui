import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;

/** Explicit Auto descendants override None, including CSS resets and cached hits (0fe11ba). **/
class PointerInheritance {
	static var checks = 0;
	static function check(name:String, ok:Bool) {
		if (!ok) throw name; checks++; Sys.println('ok   $name');
	}
	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Dark);
		var tree = new LayoutTree(), stop:Void->Void = null, enabled = Signal.make(PointerEvents.Auto);
		var enters = 0, clicks = 0, bubbled = 0;
		var root = Owner.root(tree, cleanup -> {
			stop = cleanup;
			return <div width={400} height={300}>
				<div id="back" width={400} height={300} />
				<div id="overlay" position={Absolute} width={400} height={300} pointerEvents={PointerEvents.None} onClick={_ -> bubbled++}>
					<div id="child" width={100} height={50} pointerEvents={enabled} onPointerEnter={_ -> enters++} onClick={_ -> clicks++} />
					<div id="inherited" width={100} height={50} />
					<div id="css" width={100} height={50} />
				</div>
			</div>;
		});
		function node(id:String):Node return new Node(Css.query(tree, root.node.id, "#" + id)[0]);
		function settle() { tree.flush(); tree.computeLayout(root.node, 400, 300); }
		function at(id:String):Bool { var b=tree.getBounds(node(id)); return tree.hitTest(b.x+5,b.y+5)[0].id == node(id).id; }
		settle();
		check("explicit Auto receives hits through a None parent", at("child"));
		var b = tree.getBounds(node("child")); Pointer.move(tree,b.x+5,b.y+5); Pointer.press(tree); Pointer.release(tree);
		check("hover and click reach the child", enters == 1 && clicks == 1);
		check("events bubble through the None ancestor", bubbled == 1);
		check("unspecified descendants inherit None", !at("inherited"));
		check("empty overlay space reaches the background", tree.hitTest(350,250)[0].id == node("back").id);
		check("hit region can be cached inside the active child", Pointer.quietRegion(tree) != null);
		enabled.set(PointerEvents.None); tree.flush();
		check("reactive changes invalidate the cached region", Pointer.quietRegion(tree) == null);
		check("reactive None disables the child", !at("child"));
		enabled.set(PointerEvents.Auto); tree.flush(); check("reactive Auto restores it", at("child"));
		var sheet = Css.load('#css {pointer-events:auto;}'); settle(); check("CSS Auto restores a descendant", at("css"));
		Css.remove(sheet); settle(); check("removing the override restores inheritance", !at("css"));
		Identity.of(tree,node("css").id).setInline("pointer-events","auto"); settle(); check("inline CSS restores a descendant", at("css"));
		Identity.of(tree,node("css").id).setInline("pointer-events",null); settle(); check("removing inline CSS restores inheritance", !at("css"));
		stop(); tree.dispose(); Sys.println('$checks checks: ALL PASSED');
	}
}
