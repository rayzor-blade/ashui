import ashui.components.Command;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.Ref;

/** Mounted declarative Command catalogs, selection and cleanup (6a88875). **/
class CommandItems {
	static var checks = 0;
	static function check(name:String, ok:Bool) {
		if (!ok) throw name;
		checks++;
		Sys.println('ok   $name');
	}
	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);
	static function watches():Int return [for (w in @:privateAccess Watch.bySlot) if (w != null) w].length;
	static function parts():Int return [for (p in @:privateAccess Command.parts) p].length;
	static function main() {
		for (dark in [true, false]) {
			ThemeState.init(DefaultTheme.bundle(), dark ? Dark : Light);
			ashui.components.Library.use();
			var baseWatches = watches(), baseHooks = LayoutTree.childrenHooks.length, baseParts = parts();
			var tree = new LayoutTree(), stop:Void->Void = null;
			var catalog = Signal.make(["alpha", "bravo", "charlie"]), extra = Signal.make(false);
			var command = new Ref<Command>(), choices = 0, chosen = "";
			var root = Owner.root(tree, dispose -> {
				stop = dispose;
				return <command ref={command} width={320} onSelect={v -> { choices++; chosen = v; }}>
					<command-input id="search" />
					<command-list>
						<command-empty id="empty">No results</command-empty>
						<command-group id="dynamic" heading="Tools">
							<for {tool in catalog.get()}><command-item id={"item-" + tool} value={tool} disabled={tool == "bravo"}>{tool}</command-item></for>
						</command-group>
						<command-separator id="separator" />
						<command-group id="static" heading="Utilities">
							<for {tool in ["delta", "echo"]}><command-item id={"item-" + tool} value={tool}>{tool}</command-item></for>
						</command-group>
						<if {extra.get()}><command-item id="item-foxtrot" value="foxtrot">foxtrot</command-item></if>
					</command-list>
				</command>;
			});
			function settle() { tree.flush(); tree.computeLayout(root.node, 320, 500); }
			function node(id:String):Node return Identity.of(tree, Css.query(tree, root.node.id, "#" + id)[0]).node;
			function hidden(id:String) return Identity.of(tree, node(id).id).attribute("data-hidden") != null;
			function press(k:window.Key, code:window.KeyCode) { Keyboard.input(tree, key(k, code)); settle(); }
			settle();
			Focus.set(Interaction.of(node("search")), true);
			check("static and signal for items are indexed on mount", command.get().active.get() == "alpha" && !hidden("dynamic") && !hidden("static") && hidden("empty"));
			press(Named(ArrowDown), ArrowDown);
			check("keyboard navigation skips a disabled repeated item", command.get().active.get() == "charlie");
			press(Named(Enter), Enter);
			check("Enter chooses the repeated item once", choices == 1 && chosen == "charlie" && Focus.of(tree).node == node("search"));
			command.get().query.set("echo"); settle();
			check("filtering finds static repeated items and hides the other group", command.get().active.get() == "echo" && hidden("dynamic") && !hidden("static") && hidden("separator"));
			command.get().query.set("missing"); settle();
			check("an unmatched catalog shows empty and hides all groups", command.get().active.get() == "" && !hidden("empty") && hidden("dynamic") && hidden("static"));
			command.get().query.set(""); settle();
			command.get().active.set("charlie");
			catalog.set(["charlie", "alpha", "bravo"]); settle();
			check("reordering keeps the active item and authored navigation order", command.get().active.get() == "charlie");
			press(Named(ArrowDown), ArrowDown);
			check("arrows follow the new fragment order", command.get().active.get() == "alpha");
			catalog.set(["charlie", "bravo"]); settle();
			check("removing the active row selects the first enabled result", command.get().active.get() == "charlie");
			catalog.set([]); settle();
			check("removing the group's last row hides it", hidden("dynamic") && command.get().active.get() == "delta");
			command.get().query.set("foxtrot"); settle();
			extra.set(true); settle();
			check("a conditional result joins an already filtered list", command.get().active.get() == "foxtrot" && hidden("empty"));
			extra.set(false); settle();
			check("removing a conditional result restores empty", command.get().active.get() == "" && !hidden("empty"));
			catalog.set(["alpha", "bravo", "charlie"]); command.get().query.set(""); settle();
			var stableWatches = watches();
			for (_ in 0...8) { catalog.set(["charlie", "bravo", "alpha"]); settle(); catalog.set(["alpha", "bravo", "charlie"]); settle(); }
			check("reconciliation reuses subscriptions for retained rows", watches() == stableWatches);
			var b = tree.getBounds(node("item-charlie"));
			Pointer.move(tree, b.x + 8, b.y + 8); Pointer.press(tree); Pointer.release(tree); settle();
			check("reindexing never duplicates selection callbacks", choices == 2 && chosen == "charlie");
			stop(); tree.flush();
			check("disposal removes command parts and structure subscriptions", root.node == null && parts() == baseParts
				&& LayoutTree.childrenHooks.length == baseHooks && watches() == baseWatches);
			catalog.set(["after-dispose"]); tree.flush(); tree.dispose();
		}
		Sys.println('$checks checks: ALL PASSED');
	}
}
