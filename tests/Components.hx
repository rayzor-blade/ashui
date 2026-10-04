import ashui.components.Accordion;
import ashui.components.Alert;
import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Dialog;
import ashui.components.Separator;
import ashui.components.ToggleSwitch;
import ashui.components.Tabs;
import ashui.components.Tooltip;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.types.Style;
import ashui.ui.Div;
import ashui.ui.Hxx.hxx;

/** The ashui.components library: its sheet's place, its components' parts, states and behaviour. **/
class Components {
	static var failures = 0;

	static function check(what:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			failures++;
			Sys.println('FAIL $what' + (detail != null ? ': $detail' : ''));
		} else
			Sys.println('ok   $what');
	}

	static function identity2(tree:LayoutTree, id:haxe.Int64)
		return ashui.css.Identity.of(tree, id);

	static function key(k:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), k, None, Standard, Pressed, false, Unavailable);

	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		var tree = new LayoutTree();
		var clicks = 0;
		var on = Signal.make(false);
		var tab = Signal.make("account");
		var page:Div = Owner.root(tree, _ -> hxx('
			<div width={600} height={600} flexDirection={Column} alignItems={Start} gap={8}>
				<button variant={Outline} size={Sm} onClick={_ -> clicks++}>Save</button>
				<badge variant={Success}>New</badge>
				<card><card-header><card-title>Title</card-title><card-description>Words</card-description></card-header></card>
				<alert variant={Destructive}><alert-title>Oops</alert-title></alert>
				<separator orientation="vertical" />
				<toggle-switch checked={on} />
				<tabs value={tab}>
					<tabs-list><tabs-trigger value="account">Account</tabs-trigger><tabs-trigger value="password">Password</tabs-trigger></tabs-list>
					<tabs-content value="account">A</tabs-content>
					<tabs-content value="password">P</tabs-content>
				</tabs>
				<tooltip label="Saves your work" delay={0.2}><div width={40} height={20} /></tooltip>
			</div>
		'));
		function settle() {
			tree.flush();
			tree.computeLayout(page.node, 600, 600);
			tree.flush();
		}
		settle();
		var kids = tree.children(page.node.id);
		function identity(id:haxe.Int64)
			return ashui.css.Identity.of(tree, id);
		function clickAt(id:haxe.Int64) {
			var b = tree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(tree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(tree);
			ashui.input.Pointer.release(tree);
			settle();
		}

		var sheets:Array<ashui.css.Stylesheet> = @:privateAccess ashui.css.Css.sheets;
		var library = @:privateAccess ashui.css.Css.libraries.get("ashui-components");
		var page2 = ashui.css.Css.load(".x { width: 1px }");
		check("the library's sheet is in force after the user-agent sheet, before the page's", library != null
			&& sheets.indexOf(library) == sheets.indexOf(ashui.css.Css.userAgent) + 1 && sheets.indexOf(page2) > sheets.indexOf(library),
			[for (s in sheets) s == library ? "library" : s == ashui.css.Css.userAgent ? "ua" : "page"]);
		check("its sheet reads with no problems", library.diagnostics.length == 0, library.report());

		var button = identity(kids[0]);
		check("an imported Button is <button>: the built-in element, its variant and size attributes", button.types.indexOf("button") >= 0
			&& button.hasClass("ui-button") && button.attribute("data-variant") == "outline" && button.attribute("data-size") == "sm",
			[button.types, button.classes()]);
		clickAt(kids[0]);
		check("a Button is clicked as a button is", clicks == 1, clicks);
		check("a Badge, a Card's parts and an Alert's carry their classes and variants", identity(kids[1]).attribute("data-variant") == "success"
			&& identity(kids[2]).hasClass("ui-card") && identity(tree.children(kids[2])[0]).hasClass("ui-card-header")
			&& identity(kids[3]).attribute("data-variant") == "destructive");
		check("a vertical Separator says so", identity(kids[4]).attribute("data-orientation") == "vertical");

		var switchId = kids[5];
		clickAt(switchId);
		check("a ToggleSwitch turns when clicked, its signal, data-state and :checked with it", on.get() && identity(switchId).attribute("data-state") == "on"
			&& ashui.input.Interaction.byId(tree, switchId).checked.get(), [on.get(), identity(switchId).attribute("data-state")]);
		on.set(false);
		settle();
		check("and follows its signal", identity(switchId).attribute("data-state") == "off");

		var tabsId = kids[6];
		var tabsKids = tree.children(tabsId);
		var triggers = tree.children(tabsKids[0]);
		var stateOf = (id:haxe.Int64) -> identity(id).attribute("data-state");
		var first = [stateOf(triggers[0]), stateOf(triggers[1]), stateOf(tabsKids[1]), stateOf(tabsKids[2])].join(",");
		clickAt(triggers[1]);
		var afterClick = [stateOf(triggers[0]), stateOf(triggers[1]), stateOf(tabsKids[1]), stateOf(tabsKids[2])].join(",");
		check("Tabs show the content of the trigger chosen, by data-state, and set their signal",
			first == "active,inactive,active,inactive" && afterClick == "inactive,active,inactive,active" && tab.get() == "password", [first, afterClick]);
		ashui.input.Keyboard.input(tree, key(Named(ArrowLeft), ArrowLeft));
		settle();
		check("the arrows move among the triggers, choosing as they go", tab.get() == "account", tab.get());

		var tipId = kids[7];
		var tipState = () -> identity(tipId).attribute("data-state");
		var tb = tree.getBounds(new ashui.layout.Node(tipId));
		ashui.input.Pointer.move(tree, tb.x + 5, tb.y + 5);
		settle();
		var waiting = tipState(), before = ashui.ui.TopLayer.openEntries().length;
		ashui.animation.AnimationScheduler.main.tick(0.3);
		settle();
		var open = tipState(), shown = ashui.ui.TopLayer.openEntries().length;
		var rootKids = tree.children(page.node.id).length;
		ashui.input.Pointer.move(tree, 590, 590);
		settle();
		var closing = tipState(), stillDrawn = tree.children(page.node.id).length == rootKids;
		ashui.animation.AnimationScheduler.main.tick(0.5);
		settle();
		check("a Tooltip waits, opens after its delay, fades as the pointer leaves, then closes, each its data-state",
			waiting == "waiting" && before == 0 && open == "open" && shown == 1 && closing == "closing" && stillDrawn && tipState() == "closed"
			&& tree.children(page.node.id).length == rootKids - 1, [waiting, open, closing, tipState(), stillDrawn]);

		// --- Accordion: one item open at a time, opening by layout animation ---
		var accTree = new LayoutTree();
		var openItems = Signal.make(([] : Array<String>));
		var accRoot:Div = Owner.root(accTree, _ -> hxx('
			<div width={400} height={400} flexDirection={Column}>
				<accordion value={openItems}>
					<accordion-item value="a"><accordion-trigger>First</accordion-trigger><accordion-content><div height={60} /></accordion-content></accordion-item>
					<accordion-item value="b"><accordion-trigger>Second</accordion-trigger><accordion-content><div height={60} /></accordion-content></accordion-item>
				</accordion>
			</div>
		'));
		function accSettle() {
			accTree.flush();
			accTree.computeLayout(accRoot.node, 400, 400);
			accTree.flush();
		}
		accSettle();
		var accordion = accTree.children(accRoot.node.id)[0];
		var accItems = accTree.children(accordion);
		var firstTrigger = accTree.children(accItems[0])[0], firstContent = accTree.children(accItems[0])[1];
		var closedHeight = accTree.getBounds(new ashui.layout.Node(firstContent)).height;
		var tb2 = accTree.getBounds(new ashui.layout.Node(firstTrigger));
		ashui.input.Pointer.move(accTree, tb2.x + 10, tb2.y + 5);
		ashui.input.Pointer.press(accTree);
		ashui.input.Pointer.release(accTree);
		accSettle();
		var openHeight = accTree.getBounds(new ashui.layout.Node(firstContent)).height;
		var anims:Map<String, ashui.animation.LayoutAnimation> = @:privateAccess ashui.animation.LayoutAnimation.animated.get(accTree);
		var growing = @:privateAccess anims.get(haxe.Int64.toStr(firstContent)).running;
		var secondSliding = @:privateAccess anims.get(haxe.Int64.toStr(accItems[1])).shown.dy < 0;
		ashui.animation.AnimationScheduler.main.tick(1);
		check("an accordion item opens on its trigger, growing by layout animation as the next makes room", closedHeight == 0 && openHeight >= 60
			&& openItems.get().join(",") == "a" && growing && secondSliding && identity2(accTree, firstContent).attribute("data-state") == "open",
			[closedHeight, openHeight, growing, secondSliding]);
		var secondTrigger = accTree.children(accItems[1])[0];
		var sb = accTree.getBounds(new ashui.layout.Node(secondTrigger));
		ashui.input.Pointer.move(accTree, sb.x + 10, sb.y + 5);
		ashui.input.Pointer.press(accTree);
		ashui.input.Pointer.release(accTree);
		accSettle();
		check("one open at a time: opening the second closes the first", openItems.get().join(",") == "b", openItems.get());

		// --- Dialog and AlertDialog: open from a trigger, close from a close button, Escape only for a dialog ---
		var dlgTree = new LayoutTree();
		var dlgOpen = Signal.make(false), alertOpen = Signal.make(false);
		var dlgRoot:Div = Owner.root(dlgTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Column} gap={8}>
				<dialog open={dlgOpen}>
					<dialog-trigger id="open">Open</dialog-trigger>
					<dialog-content><dialog-header><dialog-title>Title</dialog-title></dialog-header>
						<dialog-footer><dialog-close id="close">Cancel</dialog-close></dialog-footer></dialog-content>
				</dialog>
				<alert-dialog open={alertOpen}>
					<dialog-trigger id="ask">Delete</dialog-trigger>
					<alert-dialog-content><dialog-footer><dialog-close id="no">Cancel</dialog-close></dialog-footer></alert-dialog-content>
				</alert-dialog>
			</div>
		'));
		function dlgSettle() {
			dlgTree.flush();
			dlgTree.computeLayout(dlgRoot.node, 600, 400);
			dlgTree.flush();
			dlgTree.computeLayout(dlgRoot.node, 600, 400);
		}
		function find(at:haxe.Int64, id:String):Null<haxe.Int64> {
			var identity = identity2(dlgTree, at);
			if (identity != null && identity.id == id)
				return at;
			for (c in dlgTree.children(at)) {
				var f = find(c, id);
				if (f != null)
					return f;
			}
			return null;
		}
		function press(id:String) {
			// Past any opening animation: a panel growing from nothing is not yet where a press lands.
			ashui.animation.AnimationScheduler.main.tick(0.5);
			dlgSettle();
			var b = dlgTree.getBounds(new ashui.layout.Node(find(dlgRoot.node.id, id)));
			ashui.input.Pointer.move(dlgTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(dlgTree);
			ashui.input.Pointer.release(dlgTree);
			dlgSettle();
		}
		dlgSettle();
		var rootShown = dlgTree.getBounds(new ashui.layout.Node(dlgTree.children(dlgRoot.node.id)[0])).height > 0;
		check("a Dialog's root is not HTML's closed dialog: its trigger shows", rootShown);
		press("open");
		var opened = dlgOpen.get() && ashui.ui.TopLayer.openEntries().length == 1;
		var focusRing = ashui.input.Focus.of(dlgTree) != null && ashui.input.Focus.of(dlgTree).focusVisible.get();
		press("close");
		check("a DialogTrigger opens it, a DialogClose closes it; opened by a press, its first control takes focus without a ring",
			opened && !focusRing && !dlgOpen.get(), [opened, focusRing, dlgOpen.get()]);
		press("open");
		ashui.input.Keyboard.input(dlgTree, key(Named(Escape), Escape));
		dlgSettle();
		check("Escape closes a dialog", !dlgOpen.get());
		press("ask");
		ashui.input.Keyboard.input(dlgTree, key(Named(Escape), Escape));
		dlgSettle();
		var stayed = alertOpen.get();
		press("no");
		check("an AlertDialog stays open on Escape; its own action closes it", stayed && !alertOpen.get(), [stayed, alertOpen.get()]);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
