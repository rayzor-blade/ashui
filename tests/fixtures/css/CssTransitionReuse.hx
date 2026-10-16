import ashui.animation.AnimationScheduler;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.LayoutTree;
import ashui.layout.PropertyId;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Repeated state changes reuse timing, while CSS and token edits retime it (e1a026f). **/
class CssTransitionReuse {
	static var checks = 0;
	static function check(name:String, ok:Bool):Void {
		if (!ok) throw name;
		checks++;
		Sys.println('ok   $name');
	}
	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		Css.load('#moving { width: 80px; height: 30px; opacity: 1; --time: 100ms; transition: opacity var(--time) linear; }
			#moving.on { opacity: .25; }
			#moving.retimed { transition-duration: 200ms; transition-delay: 25ms; transition-timing-function: step-end; }');
		var tree = new LayoutTree(), stop:Void->Void = null;
		var root = Owner.root(tree, dispose -> { stop = dispose; return <div id="moving" />; });
		var identity = Identity.of(tree, root.node.id);
		function settle():Void { tree.flush(); tree.computeLayout(root.node, 100, 50); }
		function transition() return @:privateAccess root.node.transition;
		settle();
		var initial = transition();
		check('initial timing is parsed', initial != null && initial.forProperty(Opacity).seconds() == .1);
		identity.setClasses(['on']); settle();
		check('state restyle keeps the parsed transition', transition() == initial);
		AnimationScheduler.main.tick(.05); settle();
		var tween = @:privateAccess root.node.tweens.get(PropertyId.Opacity);
		check('the reused transition still interpolates', Math.abs((@:privateAccess tween.current : Single) - .625) < .001);
		for (i in 0...200) {
			if (i % 2 == 0) identity.setClasses([]); else identity.setClasses(['on']);
			settle();
		}
		check('repeated state changes retain one timing object', transition() == initial);
		identity.setClasses(['on', 'retimed']); settle();
		var retimed = transition();
		check('longhand changes replace the timing', retimed != initial && retimed.forProperty(Opacity).seconds() == .2
			&& retimed.forProperty(Opacity).delay() == .025);
		check('changed easing reaches the property', switch retimed.forProperty(Opacity).curve() { case Steps(1, false): true; case _: false; });
		identity.setClasses(['on']); settle();
		Css.load('#moving { --time: 250ms; }'); settle();
		check('custom property updates invalidate the timing', transition().forProperty(Opacity).seconds() == .25);
		Css.load('#moving { transition: none; }'); settle();
		check('removing transitions clears the timing', transition() == null);
		Css.load('#moving { transition-property: transform; transition-duration: 80ms; }'); settle();
		check('longhand property changes are observed', transition() != null && transition().covers(Transform)
			&& !transition().covers(Opacity) && transition().forProperty(Transform).seconds() == .08);
		stop(); tree.flush();
		check('disposal releases the cached timing snapshot', !@:privateAccess Css.applied.exists(identity));
		tree.dispose();
		Sys.println('$checks checks: ALL PASSED');
	}
}
