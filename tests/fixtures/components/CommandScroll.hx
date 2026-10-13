import ashui.components.Command;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Scroll;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Selection reveal follows layout and respects manual scrolling (08938d7). **/
class CommandScroll {
	static var checks = 0;
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) { if (detail != null) Sys.println(Std.string(detail)); throw name; }
		checks++;
		Sys.println('ok   $name');
	}
	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
	static function watches():Int return [for (w in @:privateAccess Watch.bySlot) if (w != null) w].length;
	static function warmup() {
		// Initialize shared text-flow/editing hooks before measuring per-owner cleanup (08938d7).
		var tree = new LayoutTree(), stop:Void->Void = null;
		var root = Owner.root(tree, dispose -> {
			stop = dispose;
			return <command><command-input /><command-list><command-item value="warmup">Warmup</command-item></command-list></command>;
		});
		tree.flush(); tree.computeLayout(root.node, 320, 200);
		stop(); tree.dispose();
	}
	static function main() {
		for (dark in [true, false]) {
			ThemeState.init(DefaultTheme.bundle(), dark ? Dark : Light);
			ashui.components.Library.use();
			warmup();
			var baseHooks = LayoutTree.layoutHooks.length, baseWatches = watches();
			var tree = new LayoutTree(), stop:Void->Void = null;
			var tools = Signal.make([for (i in 0...24) 'tool-$i']), shown = Signal.make(true), detail = Signal.make(false);
			var command = new Ref<Command>();
			var root = Owner.root(tree, dispose -> {
				stop = dispose;
				return <div width={420} height={300}>
					<if {shown.get()}>
						<command id="command" ref={command} width={320}>
							<command-input id="search" />
							<command-list id="list" maxHeight={136}>
								<command-empty id="empty">No results</command-empty>
								<command-group heading="Tools">
								<for {tool in tools.get()}><command-item value={tool} id={tool}>{tool}<if {tool == "tool-5" && detail.get()}><span>details</span></if></command-item></for>
								</command-group>
							</command-list>
						</command>
					</if>
				</div>;
			});
			function settle() { tree.flush(); tree.computeLayout(root.node, 420, 300); }
			function node(id:String):Node return Identity.of(tree, Css.query(tree, root.node.id, "#" + id)[0]).node;
			function press(k:window.Key, code:window.KeyCode) { Keyboard.input(tree, key(k, code)); settle(); }
			settle();
			var field = node("search"), list = node("list"), scroll = Scroll.of(list);
			function visible():Bool {
				var row = tree.getBounds(node(command.get().active.get())), viewport = tree.getBounds(list), y = scroll.y.get();
				return row.y - viewport.y >= y - 0.1 && row.y + row.height - viewport.y <= y + viewport.height + 0.1;
			}
			Focus.set(Interaction.of(field), true);
			check("catalog exceeds the viewport", scroll != null && scroll.limits().y > 400);
			press(Named(End), End);
			check("End reveals the last row without moving input focus", command.get().active.get() == "tool-23" && visible() && Focus.of(tree).node == field);
			press(Named(Home), Home);
			check("Home reveals the first row", command.get().active.get() == "tool-0" && visible());
			for (_ in 0...10) { press(Named(ArrowDown), ArrowDown); check("ArrowDown keeps the selected row visible", visible()); }
			for (_ in 0...5) { press(Named(ArrowUp), ArrowUp); check("ArrowUp keeps the selected row visible", visible()); }
			scroll.scrollTo(0, 0); settle();
			var manual = scroll.y.get();
			for (_ in 0...5) settle();
			check("manual scroll persists while selection is unchanged", scroll.y.get() == manual && !visible());
			detail.set(true); settle();
			check("changing a row's label structure preserves manual scroll", scroll.y.get() == manual && !visible());
			press(Named(ArrowDown), ArrowDown);
			check("the next navigation reveals after manual scroll", visible());
			press(Named(End), End);
			command.get().query.set("tool-1"); settle();
			check("filtering reveals the replacement selection in its new layout", command.get().active.get() == "tool-1" && visible());
			command.get().query.set("not-found"); settle();
			check("empty results reset the old scroll offset", command.get().active.get() == "" && scroll.y.get() == 0);
			command.get().query.set(""); settle(); press(Named(End), End);
			tools.set([for (i in 0...23) 'tool-$i']); settle();
			check("removing the selected row reveals its replacement", command.get().active.get() == "tool-0" && visible());
			press(Named(End), End);
			tools.set([for (i in 0...23) 'tool-${22 - i}']); settle();
			check("reordering retained selection reveals its new position", command.get().active.get() == "tool-22" && visible());
			shown.set(false); settle();
			check("closing while scrolled removes reveal hooks", !command.bound() && LayoutTree.layoutHooks.length == baseHooks,
				[command.bound(), LayoutTree.layoutHooks.length, baseHooks]);
			shown.set(true); settle(); list = node("list"); scroll = Scroll.of(list);
			Focus.set(Interaction.of(node("search")), true); press(Named(End), End);
			check("remounted command reveals its selection", visible());
			stop(); tree.flush();
			check("disposal removes all reveal watches and hooks", LayoutTree.layoutHooks.length == baseHooks && watches() == baseWatches);
			tree.dispose();
		}
		Sys.println('$checks checks: ALL PASSED');
	}
}
