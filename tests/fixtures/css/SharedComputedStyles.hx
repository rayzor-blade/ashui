import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/** Shared style snapshots must remain immutable and state interest sparse (0973e0c). **/
class SharedComputedStyles {
 static var checks = 0;
 static function check(name:String, ok:Bool) {
  if(!ok) throw name;
  checks++; Sys.println('ok   $name');
 }
 static function main() {
  ThemeState.init(DefaultTheme.bundle(), Dark);
  Css.useUserAgent();
  Css.load('#parent { font-size: 20px; --ink: red; } #a, #b { color: var(--ink); font-size: 1.5em; } #a:hover, #b:hover { opacity: .5; } .other { --ink: blue; } #a.validation:invalid { opacity: .2; } #c:disabled { opacity: .3; } #c:enabled { opacity: 1; }');
  var tree = new LayoutTree(), stop:Void->Void = null;
  var root = Owner.root(tree, d -> {stop = d; return <div id="parent"><text id="a">One</text><text id="b">Two</text><text id="c">Static</text><input type="number" value="1" /></div>;});
  function settle() {tree.flush(); tree.computeLayout(root.node,500,100);}
  function id(selector:String) return Identity.of(tree,Css.query(tree,root.node.id,selector)[0]);
  settle();
  var a=id('#a'),b=id('#b');
  check('numeric stepper rules do not subscribe unrelated containers', Interaction.find(root.node) == null);
  var up = id('.step-up');
  check('numeric stepper dimensions still use the existing named controls', Css.resolved(up,'width') == '20px' && Css.resolved(up,'height') == '14px');
  Interaction.of(up.node).hovered.set(true); settle();
  check('numeric stepper hover styling remains active', Css.computed(up,'background') == 'var(--accent-subtle)');
  var av = @:privateAccess Css.applied.get(a).values, bv = @:privateAccess Css.applied.get(b).values;
  check('equivalent styles share a snapshot within the batch', av == bv);
  check('parent font sizes are applied before em-sized children', Css.fontSize(a) == 30 && Css.fontSize(b) == 30);
  check('hover selectors do not allocate unrelated validation state', @:privateAccess Interaction.of(a.node).formStates == null);
  var c = id('#c');
  check('static focus and disabled selectors do not create input state', Interaction.find(c.node) == null && Css.resolved(c,'opacity') == '1');
  Interaction.of(c.node).setDisabled(true); settle();
  check('gaining input attaches deferred CSS state readers', Css.resolved(c,'opacity') == '.3');
  Interaction.of(c.node).setDisabled(false); settle();
  check('deferred enabled and disabled states keep following changes', Css.resolved(c,'opacity') == '1');
  Interaction.of(a.node).hovered.set(true); settle();
  check('requested hover state still updates the cascade', Css.resolved(a,'opacity') == '.5');
  a.addClasses(['other']); settle();
  check('changing a node does not mutate its former shared snapshot', Css.resolved(a,'color') == 'blue' && Css.resolved(b,'color') == 'red' && bv.get('--ink') == 'red');
  Css.load('#parent {font-size: 24px; --ink: green;}'); settle();
  check('font and variable inheritance still update on restyle', Css.fontSize(a) == 36 && Css.fontSize(b) == 36 && Css.resolved(b,'color') == 'green');
  a.addClasses(['validation']); var interaction=Interaction.of(a.node); interaction.formState('invalid').set(true); settle();
  check('new selector interest picks up an already-set form state', Css.resolved(a,'opacity') == '.2');
  stop(); tree.flush();
  check('disposing releases the state-interest entry', !@:privateAccess ashui.css.NativeCascade.watchedStates.exists(haxe.Int64.toStr(a.node.id)));
  tree.dispose();
  Sys.println('$checks checks: ALL PASSED');
 }
}
