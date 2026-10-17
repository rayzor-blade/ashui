import ashui.components.Accordion;
import ashui.components.Select;
import ashui.css.Css;
import ashui.css.Identity;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;

/**
	Select and Accordion take their options and sections from `<for>` and
	`<if>` as from authored children: kept in a value they must hold, listed,
	chosen, bound, reached by the keys, and released with their owner (b410c4c).
**/
class ComponentFragments {
	static var checks = 0;

	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok)
			throw name + (detail == null ? "" : " " + Std.string(detail));
		checks++;
		Sys.println('ok   $name');
	}

	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);

	static function watches():Int
		return [for (w in @:privateAccess Watch.bySlot) if (w != null) w].length;

	static function main() {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		ashui.components.Library.use();
		var baseWatches = watches(), baseHooks = LayoutTree.childrenHooks.length;
		var tree = new LayoutTree(), stop:Void->Void = null;
		var direct = Signal.make("walk"), repeated = Signal.make("walk"), conditional = Signal.make("walk"), grouped = Signal.make("run");
		var names = Signal.make(["walk"]), later = Signal.make(false), extra = Signal.make(false);
		var root = Owner.root(tree, dispose -> {
			stop = dispose;
			return <div class="flex flex-col" width={500} height={700}>
				<select id="direct" value={direct}><select-item value="">Setup</select-item><select-item value="walk">Walk</select-item></select>
				<select id="repeated" value={repeated}><select-item value="">Setup</select-item><for {name in names.get()}><select-item value={name}>{name}</select-item></for></select>
				<select id="conditional" value={conditional}><select-item value="">Setup</select-item><if {true}><select-item value="walk">Walk</select-item></if></select>
				<select id="grouped" value={grouped}>
					<select-item value="">Setup</select-item>
					<optgroup label="Moves"><for {name in ["walk", "run"]}><select-item value={name}>{name}</select-item></for></optgroup>
					<if {extra.get()}><optgroup label="More"><select-item value="swim">swim</select-item></optgroup></if>
				</select>
				<accordion id="direct-accordion" value={["a"]}>
					<accordion-item value="a"><accordion-trigger id="a-trigger">A</accordion-trigger><accordion-content>Content</accordion-content></accordion-item>
				</accordion>
				<accordion id="fragment-accordion" value={["b"]}>
					<accordion-item value="first"><accordion-trigger id="first-trigger">First</accordion-trigger><accordion-content>Content</accordion-content></accordion-item>
					<if {true}><accordion-item value="b"><accordion-trigger id="b-trigger">Conditional</accordion-trigger><accordion-content>Content</accordion-content></accordion-item></if>
					<for {name in ["c", "d"]}><accordion-item value={name}><accordion-trigger id={name + "-trigger"}>{name}</accordion-trigger><accordion-content>Content</accordion-content></accordion-item></for>
					<if {later.get()}><accordion-item value="late"><accordion-trigger id="late-trigger">Late</accordion-trigger><accordion-content>Content</accordion-content></accordion-item></if>
				</accordion>
			</div>;
		});
		function settle() {
			tree.flush();
			tree.computeLayout(root.node, 500, 700);
			tree.flush();
		}
		function node(id:String):Node
			return Identity.of(tree, Css.query(tree, root.node.id, "#" + id)[0]).node;
		function state(id:String):String
			return Identity.of(tree, node(id).id).attribute("data-state");
		function press(k:window.Key, code:window.KeyCode) {
			Keyboard.input(tree, key(k, code));
			settle();
		}
		function rows():Array<String> {
			var out = [];
			for (id in Css.query(tree, tree.root.id, "listbox > option, listbox > optgroup")) {
				var types = Identity.of(tree, id).types;
				out.push(types[types.length - 1]);
			}
			return out;
		}
		/** What opening the select `id` lists, as option and group tags in order; it is left closed. **/
		function listed(id:String):Array<String> {
			Focus.set(Interaction.of(node(id)), true);
			press(Named(ArrowDown), ArrowDown);
			var out = rows();
			press(Named(Escape), Escape);
			return out;
		}
		settle();

		check("a select keeps the value its first options hold, whether authored, repeated or conditional",
			direct.get() == "walk" && repeated.get() == "walk" && conditional.get() == "walk",
			[direct.get(), repeated.get(), conditional.get()]);
		check("a grouped select finds its options through a <for> inside the group", grouped.get() == "run", grouped.get());
		check("opening a select lists the options a <for> and an <if> hold",
			listed("direct").length == 2 && listed("repeated").length == 2 && listed("conditional").length == 2,
			[listed("direct"), listed("repeated"), listed("conditional")]);
		check("a grouped select lists its group's heading and the options in it", listed("grouped").length == 4, listed("grouped"));

		names.set(["walk", "run"]);
		settle();
		settle();
		check("options a <for> adds later are listed", listed("repeated").length == 3, listed("repeated"));
		Focus.set(Interaction.of(node("repeated")), true);
		press(Named(ArrowDown), ArrowDown);
		press(Named(ArrowDown), ArrowDown);
		press(Named(Enter), Enter);
		check("one of them can be chosen by the keys", repeated.get() == "run", repeated.get());
		extra.set(true);
		settle();
		settle();
		check("a group an <if> adds later is listed", listed("grouped").length == 6, listed("grouped"));

		check("an accordion's authored section opens from its value", state("a-trigger") == "open");
		check("sections an <if> and a <for> hold are bound: the conditional one starts open from the value, the others closed",
			state("b-trigger") == "open" && state("c-trigger") == "closed" && state("d-trigger") == "closed"
				&& state("first-trigger") == "closed",
			[state("b-trigger"), state("c-trigger"), state("d-trigger"), state("first-trigger")]);
		Focus.set(Interaction.of(node("b-trigger")), true);
		press(Named(Enter), Enter);
		check("Enter closes the conditional section", state("b-trigger") == "closed", state("b-trigger"));
		press(Named(Enter), Enter);
		check("and opens it again", state("b-trigger") == "open", state("b-trigger"));
		Focus.set(Interaction.of(node("c-trigger")), true);
		press(Named(Enter), Enter);
		check("a repeated section opens, closing the one open (single mode)", state("c-trigger") == "open" && state("b-trigger") == "closed",
			[state("c-trigger"), state("b-trigger")]);
		press(Named(End), End);
		check("End moves to the last section's trigger, past the repeated ones", Interaction.of(node("d-trigger")).focused.get());
		press(Named(Home), Home);
		check("Home moves to the first", Interaction.of(node("first-trigger")).focused.get());
		press(Named(ArrowDown), ArrowDown);
		check("the arrows follow the sections' order through the fragments", Interaction.of(node("b-trigger")).focused.get());

		later.set(true);
		settle();
		settle();
		check("a section an <if> adds later is bound and closed", state("late-trigger") == "closed", state("late-trigger"));
		Focus.set(Interaction.of(node("late-trigger")), true);
		press(Named(Enter), Enter);
		check("it opens", state("late-trigger") == "open", state("late-trigger"));
		Focus.set(Interaction.of(node("first-trigger")), true);
		press(Named(End), End);
		check("and is the last the keys reach", Interaction.of(node("late-trigger")).focused.get());
		later.set(false);
		settle();
		settle();
		Focus.set(Interaction.of(node("first-trigger")), true);
		press(Named(End), End);
		check("withdrawn again, the keys end at the last one left", Interaction.of(node("d-trigger")).focused.get());

		stop();
		tree.dispose();
		check("disposing releases every watch and children hook", watches() == baseWatches && LayoutTree.childrenHooks.length == baseHooks,
			[watches() - baseWatches, LayoutTree.childrenHooks.length - baseHooks]);
		Sys.println('ALL PASSED ($checks)');
	}
}
