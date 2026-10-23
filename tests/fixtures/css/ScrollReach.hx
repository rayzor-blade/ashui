import ashui.css.Css;
import ashui.input.Scroll;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Div;
import ashui.ui.Ref;

/** A scroll container follows what it hides past each edge, as signals and, with scroll-shadow, as attributes the user-agent sheet draws. **/
class ScrollReach {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic):Void {
		if (!ok)
			throw name + (detail == null ? "" : ' ($detail)');
		checks++;
		Sys.println('ok   $name');
	}

	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Light);
		var sheet = Css.load('#shadowed { overflow-y: auto; scroll-shadow: auto; width: 200px; height: 100px; flex-direction: column; } #plain { overflow-y: auto; width: 200px; height: 100px; flex-direction: column; } .row { height: 20px; flex-shrink: 0; }');
		var tree = new LayoutTree(), stop:Void->Void = null, shadowed = new Ref<Div>(), plain = new Ref<Div>();
		var root = Owner.root(tree, s -> {
			stop = s;
			return <div width={500} height={300} class="flex-row">
				<div ref={shadowed} id="shadowed">${[for (i in 0...20) <div height={20} flexShrink={0}>x</div>]}</div>
				<div ref={plain} id="plain">${[for (i in 0...20) <div height={20} flexShrink={0}>x</div>]}</div>
			</div>;
		});
		function settle()
			for (_ in 0...6) {
				Css.update();
				tree.flush();
				tree.computeLayout(root.node, 500, 300);
			}
		settle();
		var a = Scroll.of(shadowed.get().node), b = Scroll.of(plain.get().node);
		var id = ashui.css.Identity.of(tree, shadowed.get().node.id), plainId = ashui.css.Identity.of(tree, plain.get().node.id);
		check("at the top, content is hidden below and not above", !a.moreAbove.get() && a.moreBelow.get() && !a.moreLeft.get() && !a.moreRight.get(), [a.moreAbove.get(), a.moreBelow.get()]);
		check("a container with scroll-shadow is marked for the edge that hides content", id.attribute("data-more-below") != null && id.attribute("data-more-above") == null && id.attribute("data-scroll-shadow") != null);
		check("one without scroll-shadow is not marked", plainId.attribute("data-scroll-shadow") == null && plainId.attribute("data-more-below") == null);
		var seen = [];
		new ashui.reactive.Watch(() -> a.moreAbove.get(), v -> seen.push(v));
		a.scrollTo(0, 150);
		settle();
		check("scrolling into the middle hides content on both sides", a.moreAbove.get() && a.moreBelow.get(), [a.y.get(), a.limits()]);
		check("the attributes follow", id.attribute("data-more-above") != null && id.attribute("data-more-below") != null);
		a.scrollTo(0, 100000);
		settle();
		check("at the end, content is hidden above only", a.moreAbove.get() && !a.moreBelow.get() && id.attribute("data-more-below") == null);
		check("a reader of the signal is told when an edge is crossed", seen.length >= 2 && seen[seen.length - 1] == true, seen);
		a.scrollTo(0, 0);
		settle();
		check("back at the top it is as at first", !a.moreAbove.get() && a.moreBelow.get());
		check("a container nothing asked about makes no reach signals", @:privateAccess b.reachSignals == null);
		check("and asking makes the signal and follows it", b.moreBelow.get());
		// The shadow rule is in the user-agent sheet for each combination.
		check("the user-agent sheet has shadow rules for each of the fifteen combinations", StringTools.startsWith(ashui.css.UserAgent.CSS.substr(ashui.css.UserAgent.CSS.indexOf("[data-scroll-shadow]")), "[data-scroll-shadow]") && ashui.css.UserAgent.CSS.split("[data-scroll-shadow]").length == 16);
		Css.remove(sheet);
		stop();
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
