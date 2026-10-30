import ashui.core.UiContext;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.css.NativeCascade;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;

/** Decode reuse stays bounded, context-local and sensitive to complete native responses (e1a026f / a1b5f09). **/
@:access(ashui.css.NativeCascade)
class StyleSnapshotReuse {
	static var checks=0;
	static function check(name:String,ok:Bool) {if(!ok)throw name;checks++;Sys.println('ok   $name');}
	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(),Dark);
		var sheet=Css.load('#reuse {opacity:1;--ink:red;color:var(--ink);} #reuse.on {opacity:.5;}');
		var tree=new LayoutTree(),stop:Void->Void=null;
		var root=Owner.root(tree,cleanup -> {stop=cleanup;return <div id="reuse"/>;});
		function settle() {tree.flush();tree.computeLayout(root.node,100,100);}
		settle();var identity=Identity.of(tree,root.node.id),first=NativeCascade.style(identity);
		check("identical responses reuse their decoded maps",NativeCascade.style(identity)==first);
		identity.setClasses(["on"]);settle();var hovered=NativeCascade.style(identity);
		check("a different state gets a different snapshot",hovered!=first && hovered.resolved.get("opacity")==".5");
		identity.setClasses([]);settle();check("returning to a state reuses its immutable snapshot",NativeCascade.style(identity)==first);
		identity.setInline("--ink","blue");settle();
		check("inherited/custom values participate in the cache key",NativeCascade.style(identity).resolved.get("color")=="blue" && first.values.get("--ink")=="red");
		for(i in 0...100) {identity.setInline("--change",Std.string(i));settle();}
		var cache=NativeCascade.local_styles.value;
		check("the cache bounds entries",@:privateAccess cache.count<=32);
		check("the cache bounds retained source text",@:privateAccess cache.characters<=65536);
		var oldCount=@:privateAccess cache.count;
		identity.setInline("--large",StringTools.lpad("x","x",20000));settle();NativeCascade.style(identity);
		check("oversized snapshots are not retained",@:privateAccess cache.count==oldCount);
		var context=new UiContext();
		context.run(() -> check("another UI context has its own cache",NativeCascade.local_styles.value!=cache));
		context.clear();
		var original=root.node.id;
		Css.remove(sheet);stop();tree.dispose();
		check("cached values do not retain element identities",Identity.of(tree,original)==null);
		Sys.println('$checks checks: ALL PASSED');
	}
}
