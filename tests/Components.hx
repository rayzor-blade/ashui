import ashui.components.Accordion;
import ashui.components.Alert;
import ashui.components.Badge;
import ashui.components.Button;
import ashui.components.Card;
import ashui.components.Dialog;
import ashui.components.DropdownMenu;
import ashui.components.Popover;
import ashui.components.Toast;
import ashui.components.Checkbox;
import ashui.components.RadioGroup;
import ashui.components.Select;
import ashui.components.NumberInput;
import ashui.components.Toggle;
import ashui.components.Sheet;
import ashui.components.HoverCard;
import ashui.components.ContextMenu;
import ashui.components.Breadcrumb;
import ashui.components.Pagination;
import ashui.components.Table;
import ashui.components.Kbd;
import ashui.components.Menubar;
import ashui.components.NavigationMenu;
import ashui.components.ScrollArea;
import ashui.components.Command;
import ashui.components.Combobox;
import ashui.components.Calendar;
import ashui.components.Chart;
import ashui.components.Sidebar;
import ashui.components.AspectRatio;
import ashui.components.Avatar;
import ashui.components.AvatarGroup;
import ashui.components.InputOtp;
import ashui.components.Resizable;
import ashui.components.Drawer;
import ashui.components.TreeView;
import ashui.components.Typography;
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

	static function key(k:window.Key, code:window.KeyCode, pressed = true):window.KeyEvent
		return Input(Code(code), k, None, Standard, pressed ? Pressed : Released, false, Unavailable);

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

		// --- Popover and DropdownMenu: anchored panels; a menu's keys ---
		var flTree = new LayoutTree();
		var popOpen = Signal.make(false), menuOpen = Signal.make(false), picked = Signal.make("");
		var flRoot:Div = Owner.root(flTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Row} gap={40} padding={20} alignItems={Start}>
				<popover open={popOpen}><popover-trigger id="p">Open</popover-trigger><popover-content><p>Hi</p></popover-content></popover>
				<dropdown-menu open={menuOpen}>
					<dropdown-menu-trigger id="m">Options</dropdown-menu-trigger>
					<dropdown-menu-content>
						<dropdown-menu-item onSelect={() -> picked.set("one")}>One</dropdown-menu-item>
						<dropdown-menu-item disabled={true}>Off</dropdown-menu-item>
						<dropdown-menu-item onSelect={() -> picked.set("two")}>Two</dropdown-menu-item>
					</dropdown-menu-content>
				</dropdown-menu>
			</div>
		'));
		function flSettle() {
			ashui.animation.AnimationScheduler.main.tick(0.5);
			flTree.flush();
			flTree.computeLayout(flRoot.node, 600, 400);
			flTree.flush();
			flTree.computeLayout(flRoot.node, 600, 400);
		}
		function flFind(at:haxe.Int64, id:String):Null<haxe.Int64> {
			var identity = identity2(flTree, at);
			if (identity != null && identity.id == id)
				return at;
			for (c in flTree.children(at)) {
				var f = flFind(c, id);
				if (f != null)
					return f;
			}
			return null;
		}
		function flPress(id:String) {
			flSettle();
			var b = flTree.getBounds(new ashui.layout.Node(flFind(flRoot.node.id, id)));
			ashui.input.Pointer.move(flTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(flTree);
			ashui.input.Pointer.release(flTree);
			flSettle();
		}
		flSettle();
		flPress("p");
		var popShown = popOpen.get() && ashui.ui.TopLayer.openEntries().length == 1;
		var trigger = flTree.getBounds(new ashui.layout.Node(flFind(flRoot.node.id, "p")));
		var panel = ashui.ui.TopLayer.openEntries()[0].content;
		var pb = flTree.getBounds(panel.node);
		var below = pb != null && Math.abs(pb.y - (trigger.y + trigger.height + 4)) < 1.5;
		ashui.input.Keyboard.input(flTree, key(Named(Escape), Escape));
		flSettle();
		check("a Popover opens under its trigger, 4 from it, and Escape closes it", popShown && below && !popOpen.get(), [popShown, below, popOpen.get()]);

		ashui.input.Keyboard.input(flTree, key(Named(Tab), Tab));
		flSettle();
		var m = ashui.input.Interaction.byId(flTree, flFind(flRoot.node.id, "m"));
		ashui.input.Focus.set(m, true);
		ashui.input.Keyboard.input(flTree, key(Named(Enter), Enter));
		ashui.input.Keyboard.input(flTree, key(Named(Enter), Enter, false));
		flSettle();
		var firstFocused = ashui.input.Focus.of(flTree);
		var firstIsOne = firstFocused != null && identity2(flTree, firstFocused.node.id).hasClass("ui-menu-item");
		ashui.input.Keyboard.input(flTree, key(Named(ArrowDown), ArrowDown));
		flSettle();
		ashui.input.Keyboard.input(flTree, key(Named(Enter), Enter));
		ashui.input.Keyboard.input(flTree, key(Named(Enter), Enter, false));
		flSettle();
		var back = ashui.input.Focus.of(flTree) == m;
		check("a DropdownMenu opened by the keyboard focuses its first item; the arrows skip a disabled item; Enter chooses and closes it, focus back on the trigger",
			firstIsOne && picked.get() == "two" && !menuOpen.get() && back, [firstIsOne, picked.get(), menuOpen.get(), back]);

		// --- Toasts: shown, gone after their time, held while the pointer is on one, dismissed by their handle ---
		var toastTree = new LayoutTree();
		var toastRoot:Div = Owner.root(toastTree, _ -> hxx('<div width={720} height={420}><toaster /></div>'));
		function toastFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				toastTree.flush();
				toastTree.computeLayout(toastRoot.node, 720, 420);
				toastTree.flush();
			}
		function count()
			return @:privateAccess Toaster.current.toasts.get().length;
		toastFrames(1);
		Toaster.show({title: "Brief", duration: 0.2});
		var kept = Toaster.show({title: "Kept", duration: 0});
		toastFrames(2);
		var both = count() == 2;
		toastFrames(40);
		var afterTime = count();
		kept.dismiss();
		toastFrames(30);
		check("a toast goes after its time and when dismissed; one with no time stays until then", both && afterTime == 1 && count() == 0,
			[both, afterTime, count()]);

		// --- Forms: a checkbox's text checks it, a radio group's arrows choose, a select's placeholder, steppers that stop at the bounds ---
		var formTree = new LayoutTree();
		var agree = Signal.make(false), pick = Signal.make("a"), fruitPick = Signal.make(""), qty = Signal.make(1.0);
		var formRoot:Div = Owner.root(formTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Column} gap={12} padding={10}>
				<checkbox id="agree" checked={agree}>I agree</checkbox>
				<radio-group value={pick}><radio-group-item id="ra" value="a">A</radio-group-item><radio-group-item value="b">B</radio-group-item></radio-group>
				<select id="fr" value={fruitPick} placeholder="Choose"><select-item value="apple">Apple</select-item></select>
				<number-input value={qty} min={0} max={2} />
			</div>
		'));
		function formSettle() {
			formTree.flush();
			formTree.computeLayout(formRoot.node, 600, 400);
			formTree.flush();
			formTree.computeLayout(formRoot.node, 600, 400);
		}
		function formFind(at:haxe.Int64, pred:ashui.css.Identity->Bool):Array<haxe.Int64> {
			var out = [];
			var identity = identity2(formTree, at);
			if (identity != null && pred(identity))
				out.push(at);
			for (c in formTree.children(at))
				out = out.concat(formFind(c, pred));
			return out;
		}
		function formClick(id:haxe.Int64) {
			var b = formTree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(formTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(formTree);
			ashui.input.Pointer.release(formTree);
			formSettle();
		}
		formSettle();
		formClick(formFind(formRoot.node.id, i -> i.hasClass("ui-checkbox-text"))[0]);
		check("a press on a Checkbox's text checks it", agree.get());
		var dialA = formFind(formRoot.node.id, i -> i.id == "ra")[0];
		ashui.input.Focus.set(ashui.input.Interaction.byId(formTree, dialA), true);
		ashui.input.Keyboard.input(formTree, key(Named(ArrowDown), ArrowDown));
		formSettle();
		check("a RadioGroup's arrows move to the next item and choose it", pick.get() == "b", pick.get());
		var fr = formFind(formRoot.node.id, i -> i.id == "fr")[0];
		check("a Select with a placeholder keeps no value and says so", fruitPick.get() == "" && identity2(formTree, fr).attribute("data-placeholder") != null);
		var steps = formFind(formRoot.node.id, i -> i.hasClass("ui-number-step"));
		formClick(steps[1]);
		formClick(steps[1]);
		var top = qty.get();
		for (_ in 0...3)
			formClick(steps[0]);
		check("a NumberInput's buttons step it and stop at its bounds", top == 2 && qty.get() == 0, [top, qty.get()]);

		// --- Toggles, a sheet, a hover card and a context menu ---
		var pnTree = new LayoutTree();
		var one = Signal.make(["a"]), many = Signal.make(([] : Array<String>)), sheetOpen = Signal.make(false), ctxPick = Signal.make("");
		var pnRoot:Div = Owner.root(pnTree, _ -> hxx('
			<div width={800} height={500} flexDirection={Column} gap={12} padding={10}>
				<toggle-group value={one}><toggle-group-item id="ga" value="a">A</toggle-group-item><toggle-group-item id="gb" value="b">B</toggle-group-item></toggle-group>
				<toggle-group type="multiple" value={many}><toggle-group-item id="ma" value="a">A</toggle-group-item><toggle-group-item id="mb" value="b">B</toggle-group-item></toggle-group>
				<sheet open={sheetOpen}><sheet-trigger id="sh">Open</sheet-trigger><sheet-content side="left"><p>Hi</p></sheet-content></sheet>
				<hover-card openDelay={0.2}><hover-card-trigger id="hc"><p>@me</p></hover-card-trigger><hover-card-content><p>Card</p></hover-card-content></hover-card>
				<context-menu><context-menu-trigger id="ctx"><div width={200} height={80} /></context-menu-trigger>
					<context-menu-content><context-menu-item onSelect={() -> ctxPick.set("x")}>X</context-menu-item></context-menu-content></context-menu>
			</div>
		'));
		function pnFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				pnTree.flush();
				pnTree.computeLayout(pnRoot.node, 800, 500);
				pnTree.flush();
			}
		function pnAt(id:String, ?root:haxe.Int64):{x:Float, y:Float} {
			var found:Null<haxe.Int64> = null;
			function walk(at:haxe.Int64) {
				var identity = identity2(pnTree, at);
				if (identity != null && identity.id == id)
					found = at;
				for (c in pnTree.children(at))
					walk(c);
			}
			walk(root != null ? root : pnRoot.node.id);
			var b = pnTree.getBounds(new ashui.layout.Node(found));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function pnClick(id:String, ?button:window.MouseButton) {
			var p = pnAt(id);
			ashui.input.Pointer.move(pnTree, p.x, p.y);
			ashui.input.Pointer.press(pnTree, button == null ? Left : button);
			ashui.input.Pointer.release(pnTree, button == null ? Left : button);
			pnFrames(30);
		}
		pnFrames(2);
		pnClick("gb");
		var singleMoved = one.get().join(",") == "b";
		pnClick("gb");
		pnClick("ma");
		pnClick("mb");
		check("a single ToggleGroup moves its one choice and keeps it; a multiple one gathers them", singleMoved && one.get().join(",") == "b"
			&& many.get().join(",") == "a,b", [one.get(), many.get()]);

		pnClick("sh");
		var entry = ashui.ui.TopLayer.openEntries()[0];
		var sb2 = entry == null ? null : pnTree.getBounds(entry.content.node);
		var atLeft = sb2 != null && sb2.x > 0 && sb2.x <= 8.5 && sb2.height > 450;
		var closeBox = Lambda.find(pnTree.order(), id -> identity2(pnTree, id) != null && identity2(pnTree, id).hasClass("ui-sheet-close"));
		var cb = pnTree.getBounds(new ashui.layout.Node(closeBox));
		ashui.input.Pointer.move(pnTree, cb.x + cb.width / 2, cb.y + cb.height / 2);
		ashui.input.Pointer.press(pnTree);
		ashui.input.Pointer.release(pnTree);
		pnFrames(30);
		check("a Sheet opens floating just inside its edge, its full height less the inset, and its corner button closes it", sheetOpen.get() == false && atLeft, [atLeft, sheetOpen.get()]);

		var hp = pnAt("hc");
		ashui.input.Pointer.move(pnTree, hp.x, hp.y);
		pnFrames(6);
		var tooSoon = ashui.ui.TopLayer.openEntries().length;
		pnFrames(12);
		var opened2 = ashui.ui.TopLayer.openEntries().length;
		var card = ashui.ui.TopLayer.openEntries()[0].content;
		var cardBox = pnTree.getBounds(card.node);
		ashui.input.Pointer.move(pnTree, cardBox.x + 10, cardBox.y + 10);
		pnFrames(30);
		var stayed2 = ashui.ui.TopLayer.openEntries().length;
		ashui.input.Pointer.move(pnTree, 790, 490);
		pnFrames(40);
		check("a HoverCard opens after its delay, stays as the pointer moves onto the card, and closes once it leaves both",
			tooSoon == 0 && opened2 == 1 && stayed2 == 1 && ashui.ui.TopLayer.openEntries().length == 0, [tooSoon, opened2, stayed2]);

		var cp = pnAt("ctx");
		ashui.input.Pointer.move(pnTree, cp.x, cp.y);
		ashui.input.Pointer.press(pnTree, Right);
		ashui.input.Pointer.release(pnTree, Right);
		pnFrames(20);
		var menu = ashui.ui.TopLayer.openEntries()[0];
		var mb2 = menu == null ? null : pnTree.getBounds(menu.content.node);
		var atPointer = mb2 != null && Math.abs(mb2.x - cp.x) < 1 && Math.abs(mb2.y - cp.y) < 1;
		ashui.input.Pointer.move(pnTree, mb2.x + 20, mb2.y + 15);
		ashui.input.Pointer.press(pnTree);
		ashui.input.Pointer.release(pnTree);
		pnFrames(20);
		check("a right-click opens a ContextMenu with its corner at the pointer; an item chosen closes it", atPointer && ctxPick.get() == "x"
			&& ashui.ui.TopLayer.openEntries().length == 0, [atPointer, ctxPick.get()]);

		// --- Breadcrumb, pagination, table, kbd ---
		var dtTree = new LayoutTree();
		var pg = Signal.make(1);
		var dtRoot:Div = Owner.root(dtTree, _ -> hxx('
			<div width={800} height={500} flexDirection={Column} gap={12} padding={10}>
				<breadcrumb><breadcrumb-item>Home</breadcrumb-item><breadcrumb-item current={true}>Here</breadcrumb-item></breadcrumb>
				<pagination page={pg} total={10} />
				<table><table-body>
					<table-row><table-cell>A</table-cell><table-cell>B</table-cell></table-row>
					<table-row><table-cell>CC</table-cell><table-cell>D</table-cell></table-row>
				</table-body></table>
				<kbd>K</kbd>
			</div>
		'));
		function dtSettle() {
			dtTree.flush();
			dtTree.computeLayout(dtRoot.node, 800, 500);
			dtTree.flush();
			dtTree.computeLayout(dtRoot.node, 800, 500);
		}
		function dtAll(pred:ashui.css.Identity->Bool):Array<haxe.Int64>
			return [for (id in dtTree.order()) if (identity2(dtTree, id) != null && pred(identity2(dtTree, id))) id];
		function dtClick(id:haxe.Int64) {
			var b = dtTree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(dtTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(dtTree);
			ashui.input.Pointer.release(dtTree);
			dtSettle();
		}
		dtSettle();
		var crumbs = dtAll(i -> i.hasClass("ui-breadcrumb-item")), seps = dtAll(i -> i.hasClass("ui-breadcrumb-separator"));
		check("a Breadcrumb puts a separator between its items and marks the current one", crumbs.length == 2 && seps.length == 1
			&& identity2(dtTree, crumbs[1]).attribute("data-current") == "page");
		var steps = dtAll(i -> i.hasClass("ui-pagination-button") && i.attribute("data-step") != null);
		var prevDisabled = ashui.input.Interaction.byId(dtTree, steps[0]).disabled.get();
		dtClick(steps[1]);
		var afterNext = pg.get();
		// On page 2 the numbers are 1, 2, 3 and 10.
		var numbers = dtAll(i -> i.hasClass("ui-pagination-button") && i.attribute("data-step") == null);
		dtClick(numbers[2]);
		var active = dtAll(i -> i.hasClass("ui-pagination-button") && i.attribute("data-state") == "active");
		check("Pagination follows its page: previous disabled on the first, next and a number step it, the current one active",
			prevDisabled && afterNext == 2 && pg.get() == 3 && active.length == 1, [prevDisabled, afterNext, pg.get(), active.length]);
		var cells = dtAll(i -> i.hasClass("ui-table-cell"));
		var c0 = dtTree.getBounds(new ashui.layout.Node(cells[1])), c1 = dtTree.getBounds(new ashui.layout.Node(cells[3]));
		check("a Table's rows share their columns", Math.abs(c0.x - c1.x) < 0.5, [c0.x, c1.x]);
		check("a Kbd is a kbd keycap", dtAll(i -> i.hasClass("ui-kbd") && i.types.indexOf("kbd") >= 0).length == 1);

		// --- Menubar and navigation menu ---
		var mbTree = new LayoutTree();
		var mbRoot:Div = Owner.root(mbTree, _ -> hxx('
			<div width={800} height={500} flexDirection={Column} gap={60} padding={10}>
				<menubar>
					<menubar-menu><menubar-trigger id="mf">File</menubar-trigger><menubar-content><menubar-item>New</menubar-item></menubar-content></menubar-menu>
					<menubar-menu><menubar-trigger id="me">Edit</menubar-trigger><menubar-content><menubar-item>Undo</menubar-item></menubar-content></menubar-menu>
				</menubar>
				<navigation-menu>
					<navigation-menu-item><navigation-menu-trigger id="na">A</navigation-menu-trigger><navigation-menu-content><navigation-menu-link>a</navigation-menu-link></navigation-menu-content></navigation-menu-item>
					<navigation-menu-item><navigation-menu-trigger id="nb">B</navigation-menu-trigger><navigation-menu-content><navigation-menu-link>b</navigation-menu-link></navigation-menu-content></navigation-menu-item>
				</navigation-menu>
			</div>
		'));
		function mbFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				mbTree.flush();
				mbTree.computeLayout(mbRoot.node, 800, 500);
				mbTree.flush();
			}
		function mbAt(id:String):{x:Float, y:Float} {
			var found:Null<haxe.Int64> = null;
			for (n in mbTree.order())
				if (identity2(mbTree, n) != null && identity2(mbTree, n).id == id)
					found = n;
			var b = mbTree.getBounds(new ashui.layout.Node(found));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		function openLabel():Null<String> {
			var entries = ashui.ui.TopLayer.openEntries();
			if (entries.length == 0)
				return null;
			var b = mbTree.getBounds(entries[entries.length - 1].content.node);
			return b == null ? null : Std.string(Math.round(b.x));
		}
		mbFrames(2);
		var f = mbAt("mf"), e = mbAt("me");
		ashui.input.Pointer.move(mbTree, f.x, f.y);
		ashui.input.Pointer.press(mbTree);
		ashui.input.Pointer.release(mbTree);
		mbFrames(20);
		var fileMenuX = openLabel();
		ashui.input.Pointer.move(mbTree, e.x, e.y);
		mbFrames(20);
		var editMenuX = openLabel();
		ashui.input.Keyboard.input(mbTree, key(Named(ArrowLeft), ArrowLeft));
		mbFrames(20);
		var backX = openLabel();
		ashui.input.Keyboard.input(mbTree, key(Named(Escape), Escape));
		mbFrames(20);
		check("a Menubar: the pointer crossing to another trigger opens its menu in place, the arrows move between menus, each lined up with its trigger",
			fileMenuX != null && editMenuX != null && fileMenuX != editMenuX && backX == fileMenuX && ashui.ui.TopLayer.openEntries().length == 0,
			[fileMenuX, editMenuX, backX]);
		var na = mbAt("na"), nb = mbAt("nb");
		ashui.input.Pointer.move(mbTree, na.x, na.y);
		mbFrames(20);
		var oneOpen = ashui.ui.TopLayer.openEntries().length;
		ashui.input.Pointer.move(mbTree, nb.x, nb.y);
		mbFrames(30);
		var stillOne = ashui.ui.TopLayer.openEntries().length;
		ashui.input.Pointer.move(mbTree, 790, 490);
		mbFrames(40);
		check("a NavigationMenu opens an item resting on it, one at a time, and closes once the pointer leaves",
			oneOpen == 1 && stillOne == 1 && ashui.ui.TopLayer.openEntries().length == 0, [oneOpen, stillOne]);

		// --- ScrollArea: its scrollbar mode from CSS, the wheel scrolling it ---
		var saTree = new LayoutTree();
		var saRoot:Div = Owner.root(saTree, _ -> hxx('
			<div width={600} height={300} flexDirection={Row} gap={10}>
				<scroll-area height={100} width={120}><div height={400} /></scroll-area>
				<scroll-area height={100} width={120} scrollbars="always"><div height={400} /></scroll-area>
				<scroll-area height={100} width={120} scrollbars="hidden"><div height={400} /></scroll-area>
			</div>
		'));
		saTree.flush();
		saTree.computeLayout(saRoot.node, 600, 300);
		saTree.flush();
		saTree.computeLayout(saRoot.node, 600, 300);
		var areas = saTree.children(saRoot.node.id);
		var modes = [for (a in areas) {
			var sc = ashui.input.Scroll.at(a);
			sc == null ? "none" : sc.visibility;
		}];
		var first = ashui.input.Scroll.at(areas[0]);
		var ab = saTree.getBounds(new ashui.layout.Node(areas[0]));
		ashui.input.Pointer.move(saTree, ab.x + 10, ab.y + 10);
		@:privateAccess ashui.input.Pointer.wheel(saTree, 0, -60);
		check("a ScrollArea scrolls under the wheel; its scrollbars mode comes from the library's CSS", modes.join(",") == "auto,always,hidden"
			&& first != null && first.y.get() > 0, [modes, first == null ? -1 : first.y.get()]);

		// --- Command and Combobox ---
		var cmTree = new LayoutTree();
		var cmPick = Signal.make(""), cbValue = Signal.make("");
		var cmRoot:Div = Owner.root(cmTree, _ -> hxx('
			<div width={800} height={500} flexDirection={Row} gap={20} padding={10} alignItems={Start}>
				<command onSelect={v -> cmPick.set(v)}>
					<command-input id="q" />
					<command-list>
						<command-empty>None</command-empty>
						<command-group heading="A"><command-item value="apple">Apple</command-item><command-item value="apricot">Apricot</command-item></command-group>
						<command-group heading="B"><command-item value="banana">Banana</command-item></command-group>
					</command-list>
				</command>
				<combobox id="cb" value={cbValue} options={[{value: "x", label: "Ex"}, {value: "y", label: "Why"}]} />
			</div>
		'));
		function cmFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				cmTree.flush();
				cmTree.computeLayout(cmRoot.node, 800, 500);
				cmTree.flush();
			}
		function cmFind(pred:ashui.css.Identity->Bool):Array<haxe.Int64>
			return [for (id in cmTree.order()) if (identity2(cmTree, id) != null && pred(identity2(cmTree, id))) id];
		function cmPress(id:haxe.Int64) {
			var b = cmTree.getBounds(new ashui.layout.Node(id));
			ashui.input.Pointer.move(cmTree, b.x + b.width / 2, b.y + b.height / 2);
			ashui.input.Pointer.press(cmTree);
			ashui.input.Pointer.release(cmTree);
			cmFrames(20);
		}
		cmFrames(2);
		cmPress(cmFind(i -> i.id == "q")[0]);
		ashui.input.Keyboard.text(cmTree, "ap");
		cmFrames(3);
		var hiddenGroups = cmFind(i -> i.hasClass("ui-command-group") && i.attribute("data-hidden") != null).length;
		var emptyHidden = cmFind(i -> i.hasClass("ui-command-empty") && i.attribute("data-hidden") != null).length;
		ashui.input.Keyboard.input(cmTree, key(Named(ArrowDown), ArrowDown));
		ashui.input.Keyboard.input(cmTree, key(Named(Enter), Enter));
		cmFrames(2);
		ashui.input.Keyboard.text(cmTree, "zz");
		cmFrames(3);
		var emptyShown = cmFind(i -> i.hasClass("ui-command-empty") && i.attribute("data-hidden") == null).length;
		check("a Command filters as it is typed in, hiding a group with nothing left; the arrows and Enter choose; it says when nothing matches",
			hiddenGroups == 1 && emptyHidden == 1 && cmPick.get() == "apricot" && emptyShown == 1, [hiddenGroups, emptyHidden, cmPick.get(), emptyShown]);
		cmPress(cmFind(i -> i.id == "cb")[0]);
		ashui.input.Keyboard.text(cmTree, "why");
		cmFrames(3);
		ashui.input.Keyboard.input(cmTree, key(Named(Enter), Enter));
		cmFrames(20);
		check("a Combobox opens a search on its options and the one chosen is its value", cbValue.get() == "y" && ashui.ui.TopLayer.openEntries().length == 0,
			cbValue.get());

		// --- Calendar: a press chooses, the keys cross into the next month ---
		var calTree = new LayoutTree();
		var day = Signal.make((null : Null<ashui.components.Calendar.CalendarDay>));
		var calRoot:Div = Owner.root(calTree, _ -> hxx('<div width={400} height={400}><calendar value={day} today={{year: 2026, month: 9, day: 4}} /></div>'));
		function calFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				calTree.flush();
				calTree.computeLayout(calRoot.node, 400, 400);
				calTree.flush();
			}
		calFrames(2);
		var cells = [for (id in calTree.order()) if (identity2(calTree, id) != null && identity2(calTree, id).hasClass("ui-calendar-day")) id];
		var first = identity2(calTree, cells[0]);
		var cb2 = calTree.getBounds(new ashui.layout.Node(cells[33]));
		ashui.input.Pointer.move(calTree, cb2.x + cb2.width / 2, cb2.y + cb2.height / 2);
		ashui.input.Pointer.press(calTree);
		ashui.input.Pointer.release(calTree);
		calFrames(5);
		var pressed = day.get();
		ashui.input.Keyboard.input(calTree, key(Named(ArrowDown), ArrowDown));
		calFrames(5);
		function calGrids()
			return [for (id in calTree.order()) if (identity2(calTree, id) != null && identity2(calTree, id).hasClass("ui-calendar-grid")) identity2(calTree, id)];
		var turning = [for (g in calGrids()) '${g.attribute("data-enter")}/${g.attribute("data-leaving")}'].join(",");
		ashui.input.Keyboard.input(calTree, key(Named(Enter), Enter));
		ashui.input.Keyboard.input(calTree, key(Named(Enter), Enter, false));
		calFrames(5);
		var stepped = day.get();
		check("a Calendar shows six weeks from the month's first week, a press chooses a day, the arrows cross into the next month",
			first.attribute("data-outside") != null && pressed != null && pressed.month == 9 && pressed.day == 30 && stepped != null
			&& stepped.month == 10 && stepped.day == 6, [pressed, stepped]);
		calFrames(20);
		check("turning the month slides the next one in and the shown one out, which then goes", turning == "null/next,next/null" && calGrids().length == 1,
			[turning, calGrids().length]);

		// --- Charts: the tooltip shows the values at the label under the pointer; new values are moved to, not jumped to ---
		var chTree = new LayoutTree();
		var chData = Signal.make(([{name: "Desktop", values: [10.0, 30, 20]}, {name: "Mobile", values: [5.0, 15, 25]}] : Array<ChartSeries>));
		var chRoot:Div = Owner.root(chTree, _ -> hxx('<div width={400} height={300} padding={20}><line-chart series={chData} labels={["Jan", "Feb", "Mar"]} /></div>'));
		function chFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				chTree.flush();
				chTree.computeLayout(chRoot.node, 400, 300);
				chTree.flush();
			}
		function chFind(cls:String):Array<haxe.Int64>
			return [for (id in chTree.order()) if (identity2(chTree, id) != null && identity2(chTree, id).hasClass(cls)) id];
		function chText(id:haxe.Int64):String {
			var out = [];
			function walk(n:haxe.Int64) {
				var t = ashui.ui.Text.at(n);
				if (t != null)
					out.push(t.text());
				for (c in chTree.children(n))
					walk(c);
			}
			walk(id);
			return out.join("|");
		}
		chFrames(60);
		var plotBox = chTree.getBounds(new ashui.layout.Node(chFind("ui-chart-plot")[0]));
		var tipShown = () -> chTree.getBounds(new ashui.layout.Node(chFind("ui-chart-tooltip")[0])).width > 0;
		var hiddenBefore = !tipShown();
		// The middle third of the plot, past the value axis's labels: Feb.
		ashui.input.Pointer.move(chTree, plotBox.x + plotBox.width * 0.55, plotBox.y + plotBox.height / 2);
		chFrames(2);
		var tipText = chText(chFind("ui-chart-tooltip")[0]);
		check("a chart's tooltip shows the label under the pointer and each series' value there", hiddenBefore && tipShown()
			&& tipText == "Feb|Desktop|30|Mobile|15", [hiddenBefore, tipShown(), tipText]);
		ashui.input.Pointer.move(chTree, 5, 5);
		chFrames(2);
		check("and goes when the pointer leaves", !tipShown());
		var legend = [for (id in chFind("ui-chart-legend-item")) chText(id)].join(",");
		check("a chart of more than one series has a legend of their names", legend == "Desktop,Mobile", legend);

		// --- Pie chart: the slice under the pointer, by its angle, its label, value and share in the tooltip ---
		var pieTree = new LayoutTree();
		var pieRoot:Div = Owner.root(pieTree, _ -> hxx('<div width={300} height={300}><pie-chart slices={[{label: "A", value: 3.0}, {label: "B", value: 1.0}]} height={200} legend={false} /></div>'));
		for (_ in 0...60) {
			ashui.animation.AnimationScheduler.main.tick(1 / 60);
			pieTree.flush();
			pieTree.computeLayout(pieRoot.node, 300, 300);
			pieTree.flush();
		}
		var piePlot = Lambda.find(pieTree.order(), n -> identity2(pieTree, n) != null && identity2(pieTree, n).hasClass("ui-chart-plot"));
		var pb = pieTree.getBounds(new ashui.layout.Node(piePlot));
		// A, three quarters from the top clockwise, holds the right side; B, the last quarter, the upper left.
		ashui.input.Pointer.move(pieTree, pb.x + pb.width * 0.8, pb.y + pb.height * 0.5);
		pieTree.flush();
		var pieTip = Lambda.find(pieTree.order(), n -> identity2(pieTree, n) != null && identity2(pieTree, n).hasClass("ui-chart-tooltip-value"));
		var tipA = ashui.ui.Text.at(pieTree.children(pieTip)[0]).text();
		ashui.input.Pointer.move(pieTree, pb.x + pb.width * 0.3, pb.y + pb.height * 0.3);
		pieTree.flush();
		var tipB = ashui.ui.Text.at(pieTree.children(pieTip)[0]).text();
		check("a pie chart's tooltip names the slice under the pointer, its value and share", tipA == "3 · 75%" && tipB == "1 · 25%", [tipA, tipB]);

		// --- ref= on a component holds the component itself, typed as its class ---
		var cardRef = new ashui.ui.Ref<Card>();
		var refTree = new LayoutTree();
		Owner.root(refTree, _ -> hxx('<div><card ref={cardRef} width={120}><card-content>Hi</card-content></card></div>'));
		refTree.flush();
		check("ref= on a component holds the component", cardRef.get() != null && Std.isOfType(cardRef.get(), Card));

		// --- Sidebar: collapsing eases its width, the inset moving with it, its items kept on one line ---
		var sbTree = new LayoutTree();
		var folded = Signal.make(false);
		var sbRoot:Div = Owner.root(sbTree, _ -> hxx('
			<div width={700} height={400} flexDirection={Column}>
				<sidebar-layout height={300}>
					<sidebar collapsed={folded}><sidebar-item active={true}>Dashboard</sidebar-item><sidebar-group label="MORE"><sidebar-item>Settings</sidebar-item></sidebar-group></sidebar>
					<sidebar-inset><div height={20} /></sidebar-inset>
				</sidebar-layout>
			</div>
		'));
		function sbFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				sbTree.flush();
				sbTree.computeLayout(sbRoot.node, 700, 400);
				sbTree.flush();
			}
		function sbFind(cls:String):Array<haxe.Int64>
			return [for (id in sbTree.order()) if (identity2(sbTree, id) != null && identity2(sbTree, id).hasClass(cls)) id];
		function sbBox(id:haxe.Int64)
			return sbTree.getBounds(new ashui.layout.Node(id));
		sbFrames(2);
		var bar = sbFind("ui-sidebar")[0], inset = sbFind("ui-sidebar-inset")[0], item = sbFind("ui-sidebar-item")[0];
		var wide = sbBox(bar).width, itemHigh = sbBox(item).height;
		folded.set(true);
		sbFrames(6);
		var midway = sbBox(bar).width, insetMidway = sbBox(inset).x, itemMidway = sbBox(item).height;
		sbFrames(30);
		var narrow = sbBox(bar).width;
		check("a Sidebar collapses to its icons, its width easing and the inset moving with it, its items kept on one line, its state on data-state",
			narrow < midway && midway < wide && insetMidway < sbBox(bar).x + wide && itemMidway == itemHigh
			&& identity2(sbTree, bar).attribute("data-state") == "collapsed", [wide, midway, narrow, itemHigh, itemMidway]);


		// --- AspectRatio, AvatarGroup, InputOtp ---
		var exTree = new LayoutTree();
		var otpCode = Signal.make("");
		var otpDone = Signal.make("");
		var exRoot:Div = Owner.root(exTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Column} gap={10}>
				<div width={160} flexDirection={Row}><aspect-ratio id="ar"><div /></aspect-ratio></div>
				<div width={90}><aspect-ratio id="sq" ratio={1}><div /></aspect-ratio></div>
				<div flexDirection={Row}>
					<avatar-group id="ag" max={2}><avatar><avatar-fallback>A</avatar-fallback></avatar><avatar><avatar-fallback>B</avatar-fallback></avatar><avatar><avatar-fallback>C</avatar-fallback></avatar><avatar><avatar-fallback>D</avatar-fallback></avatar></avatar-group>
					<div id="after" width={10} height={10} />
				</div>
				<input-otp id="otp" length={4} value={otpCode} onComplete={c -> otpDone.set(c)} />
			</div>
		'));
		function exFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				exTree.flush();
				exTree.computeLayout(exRoot.node, 600, 400);
				exTree.flush();
			}
		function exFind(pred:ashui.css.Identity->Bool):Array<haxe.Int64>
			return [for (id in exTree.order()) if (identity2(exTree, id) != null && pred(identity2(exTree, id))) id];
		function exBounds(name:String)
			return exTree.getBounds(new ashui.layout.Node(exFind(i -> i.id == name)[0]));
		exFrames(2);
		var ar = exBounds("ar"), sq = exBounds("sq");
		check("an AspectRatio is as wide as its container and as tall as its ratio makes it, 16 / 9 by default",
			ar.width == 160 && Math.abs(ar.height - 90) < 1 && sq.width == 90 && Math.abs(sq.height - 90) < 1, [ar.width, ar.height, sq.width, sq.height]);
		var ag = exBounds("ag"), after = exBounds("after");
		var more = exFind(i -> i.hasClass("ui-avatar-more"));
		check("an AvatarGroup overlaps its avatars, as wide as they are together, and counts past max in a bubble",
			more.length == 1 && exFind(i -> i.hasClass("ui-avatar")).length == 2 && ag.width == 100 && after.x == ag.x + ag.width,
			[more.length, ag.width, after.x]);
		var otpBox = exBounds("otp");
		ashui.input.Pointer.move(exTree, otpBox.x + 10, otpBox.y + otpBox.height / 2);
		ashui.input.Pointer.press(exTree);
		ashui.input.Pointer.release(exTree);
		exFrames(2);
		var activeFirst = exFind(i -> i.hasClass("ui-input-otp-slot") && i.attribute("data-active") != null).length;
		ashui.input.Keyboard.text(exTree, "1a2");
		exFrames(2);
		var partial = otpCode.get(), filled = exFind(i -> i.hasClass("ui-input-otp-slot") && i.attribute("data-filled") != null).length;
		ashui.input.Keyboard.text(exTree, "345");
		exFrames(2);
		check("an InputOtp keeps digits up to its length, marks the slots filled and the next active, and calls onComplete once full",
			activeFirst == 1 && partial == "12" && filled == 2 && otpCode.get() == "1234" && otpDone.get() == "1234",
			[activeFirst, partial, filled, otpCode.get(), otpDone.get()]);


		// --- Resizable: a handle drags the space between two panels within their bounds; its keys step it ---
		var rzTree = new LayoutTree();
		var rzLeft = Signal.make(150.0);
		var rzRoot:Div = Owner.root(rzTree, _ -> hxx('
			<div width={600} height={400} flexDirection={Column}>
				<resizable height={200}>
					<resizable-panel size={rzLeft} minSize={100} maxSize={300}><div /></resizable-panel>
					<resizable-panel id="mid" minSize={60}><div /></resizable-panel>
					<resizable-panel id="end"><div /></resizable-panel>
				</resizable>
			</div>
		'));
		function rzFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				rzTree.flush();
				rzTree.computeLayout(rzRoot.node, 600, 400);
				rzTree.flush();
			}
		function rzFind(pred:ashui.css.Identity->Bool):Array<haxe.Int64>
			return [for (id in rzTree.order()) if (identity2(rzTree, id) != null && pred(identity2(rzTree, id))) id];
		function rzBounds(id:haxe.Int64)
			return rzTree.getBounds(new ashui.layout.Node(id));
		rzFrames(2);
		var rzHandles = rzFind(i -> i.hasClass("ui-resizable-handle"));
		var h0 = rzBounds(rzHandles[0]);
		var hcx = h0.x + h0.width / 2, hcy = h0.y + h0.height / 2;
		ashui.input.Pointer.move(rzTree, hcx, hcy);
		ashui.input.Pointer.press(rzTree);
		rzFrames(1);
		var draggingSet = identity2(rzTree, rzHandles[0]).attribute("data-dragging") != null;
		ashui.input.Pointer.move(rzTree, hcx + 80, hcy);
		rzFrames(1);
		var dragged = rzLeft.get();
		ashui.input.Pointer.move(rzTree, hcx + 400, hcy);
		rzFrames(1);
		var atMax = rzLeft.get();
		ashui.input.Pointer.move(rzTree, hcx - 400, hcy);
		rzFrames(1);
		var atMin = rzLeft.get(), leftWidth = rzBounds(rzFind(i -> i.hasClass("ui-resizable-panel"))[0]).width;
		ashui.input.Pointer.release(rzTree);
		rzFrames(1);
		check("a Resizable handle drags its panel's size, kept within its min and max, marked while it drags",
			draggingSet && dragged == 230 && atMax == 300 && atMin == 100 && leftWidth == 100
			&& identity2(rzTree, rzHandles[0]).attribute("data-dragging") == null, [draggingSet, dragged, atMax, atMin, leftWidth]);
		ashui.input.Keyboard.input(rzTree, key(Named(ArrowRight), ArrowRight));
		ashui.input.Keyboard.input(rzTree, key(Named(ArrowRight), ArrowRight));
		var stepped = rzLeft.get();
		ashui.input.Keyboard.input(rzTree, key(Named(End), End));
		rzFrames(1);
		check("a focused Resizable handle steps by its arrow keys, and End takes it as far as the panels allow", stepped == 120 && rzLeft.get() == 300,
			[stepped, rzLeft.get()]);
		// The middle panel took a size when the first handle moved; the last, still sharing the space, takes what the middle gives up.
		var h1 = rzBounds(rzHandles[1]);
		var mid = rzFind(i -> i.id == "mid")[0], end = rzFind(i -> i.id == "end")[0];
		var midBefore = rzBounds(mid).width, endBefore = rzBounds(end).width;
		ashui.input.Pointer.move(rzTree, h1.x + h1.width / 2, h1.y + 20);
		ashui.input.Pointer.press(rzTree);
		ashui.input.Pointer.move(rzTree, h1.x + h1.width / 2 - 200, h1.y + 20);
		rzFrames(1);
		ashui.input.Pointer.release(rzTree);
		var midAfter = rzBounds(mid).width, endAfter = rzBounds(end).width;
		check("a Resizable handle gives a panel's space to the one beyond it, down to the panel's min, the last still filling the group",
			midAfter == 60 && Math.abs(endAfter - (endBefore + midBefore - 60)) <= 1, [midBefore, endBefore, midAfter, endAfter]);


		// --- Drawer: a short pull springs back, a long one or a flick closes it; its controls keep their presses ---
		var drTree = new LayoutTree();
		// A window sets the viewport its drawer's height is kept within.
		ashui.css.Css.setViewport(800, 600);
		var drOpen = Signal.make(false), drPressed = Signal.make(0);
		var drRoot:Div = Owner.root(drTree, _ -> hxx('
			<div width={800} height={600} flexDirection={Column}>
				<drawer open={drOpen}>
					<drawer-trigger id="drOpen">Open</drawer-trigger>
					<drawer-content>
						<drawer-header><drawer-title>Goal</drawer-title></drawer-header>
						<button id="drButton" onClick={_ -> drPressed.set(drPressed.get() + 1)}>Go</button>
					</drawer-content>
				</drawer>
			</div>
		'));
		function drFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				drTree.flush();
				drTree.computeLayout(drRoot.node, 800, 600);
				drTree.flush();
			}
		function drFind(pred:ashui.css.Identity->Bool):Null<haxe.Int64>
			return Lambda.find(drTree.order(), id -> identity2(drTree, id) != null && pred(identity2(drTree, id)) && drTree.getBounds(new ashui.layout.Node(id)) != null);
		function drCentre(id:haxe.Int64) {
			var b = drTree.getBounds(new ashui.layout.Node(id));
			return {x: b.x + b.width / 2, y: b.y + b.height / 2};
		}
		// Pulls the handle down by `by` over `steps` frames and lets go.
		function drPull(by:Float, steps:Int) {
			var c = drCentre(drFind(i -> i.hasClass("ui-drawer-handle")));
			ashui.input.Pointer.move(drTree, c.x, c.y);
			ashui.input.Pointer.press(drTree);
			for (k in 1...steps + 1) {
				drFrames(1);
				ashui.input.Pointer.move(drTree, c.x, c.y + by * k / steps);
			}
			drFrames(1);
			ashui.input.Pointer.release(drTree);
		}
		function drPanelTop():Float
			return drTree.getBounds(new ashui.layout.Node(drFind(i -> i.hasClass("ui-drawer")))).y;
		drFrames(2);
		var dc = drCentre(drFind(i -> i.id == "drOpen"));
		ashui.input.Pointer.move(drTree, dc.x, dc.y);
		ashui.input.Pointer.press(drTree);
		ashui.input.Pointer.release(drTree);
		drFrames(40);
		var restTop = drPanelTop();
		var drTrace = ashui.debug.MotionTrace.start();
		var c0 = drCentre(drFind(i -> i.hasClass("ui-drawer-handle")));
		ashui.input.Pointer.move(drTree, c0.x, c0.y);
		ashui.input.Pointer.press(drTree);
		ashui.input.Pointer.move(drTree, c0.x, c0.y + 30);
		drFrames(1);
		var whileDragging = identity2(drTree, drFind(i -> i.hasClass("ui-drawer"))).attribute("data-dragging") != null;
		ashui.input.Pointer.release(drTree);
		drFrames(60);
		drTrace.stop();
		var springs = [for (t in drTrace.tracks) if (t.kind == Spring) t];
		check("a Drawer pulled a little is marked dragging, and let go it springs back from where it was", drOpen.get() && whileDragging
			&& springs.length == 1 && springs[0].from == "30" && springs[0].to == "0" && springs[0].end == Completed,
			[for (t in springs) '${t.from}->${t.to} ${t.end}']);
		var bc = drCentre(drFind(i -> i.id == "drButton"));
		ashui.input.Pointer.move(drTree, bc.x, bc.y);
		ashui.input.Pointer.press(drTree);
		ashui.input.Pointer.move(drTree, bc.x, bc.y + 200);
		drFrames(1);
		var heldTop = drPanelTop();
		ashui.input.Pointer.move(drTree, bc.x, bc.y);
		ashui.input.Pointer.release(drTree);
		drFrames(2);
		check("a press on a Drawer's control does not drag it, and the control is clicked", heldTop == restTop && drPressed.get() == 1 && drOpen.get(),
			[heldTop, restTop, drPressed.get()]);
		drPull(400, 20);
		drFrames(40);
		check("a Drawer pulled past a third of its height closes", !drOpen.get(), drOpen.get());
		ashui.input.Pointer.move(drTree, dc.x, dc.y);
		ashui.input.Pointer.press(drTree);
		ashui.input.Pointer.release(drTree);
		drFrames(40);
		drPull(36, 2);
		drFrames(40);
		check("a Drawer flicked toward its edge closes, though it went only a little way", !drOpen.get(), drOpen.get());


		// --- TreeView: a press chooses and opens, the group grows in; the arrows walk the rows shown, Left steps out and closes ---
		var tvTree = new LayoutTree();
		var tvPick = Signal.make((null : Null<String>));
		var tvRoot:Div = Owner.root(tvTree, _ -> hxx('
			<div width={400} height={400} flexDirection={Column}>
				<tree-view selected={tvPick}>
					<tree-item id="tvA" value="a" label="A">
						<tree-item value="a1" label="A1" />
						<tree-item value="a2" label="A2" />
					</tree-item>
					<tree-item id="tvB" value="b" label="B" />
				</tree-view>
			</div>
		'));
		function tvFrames(n:Int)
			for (_ in 0...n) {
				ashui.animation.AnimationScheduler.main.tick(1 / 60);
				tvTree.flush();
				tvTree.computeLayout(tvRoot.node, 400, 400);
				tvTree.flush();
			}
		function tvItem(id:String):haxe.Int64
			return Lambda.find(tvTree.order(), n -> identity2(tvTree, n) != null && identity2(tvTree, n).id == id);
		function tvRowY(id:String):Float
			return tvTree.getBounds(new ashui.layout.Node(tvTree.children(tvItem(id))[0])).y;
		tvFrames(2);
		var bClosed = tvRowY("tvB");
		var aRow = tvTree.getBounds(new ashui.layout.Node(tvTree.children(tvItem("tvA"))[0]));
		ashui.input.Pointer.move(tvTree, aRow.x + 20, aRow.y + aRow.height / 2);
		ashui.input.Pointer.press(tvTree);
		ashui.input.Pointer.release(tvTree);
		tvFrames(1);
		var tvAnims:Map<String, ashui.animation.LayoutAnimation> = @:privateAccess ashui.animation.LayoutAnimation.animated.get(tvTree);
		var bMoving = @:privateAccess tvAnims.get(haxe.Int64.toStr(tvItem("tvB"))).running;
		tvFrames(40);
		var bOpen = tvRowY("tvB");
		check("a TreeView row pressed is chosen and opens, the rows below easing down as its items grow in",
			tvPick.get() == "a" && identity2(tvTree, tvItem("tvA")).attribute("data-state") == "open" && bMoving && bOpen - bClosed > 50,
			[tvPick.get(), bClosed, bMoving, bOpen]);
		ashui.input.Keyboard.input(tvTree, key(Named(ArrowDown), ArrowDown));
		ashui.input.Keyboard.input(tvTree, key(Named(ArrowDown), ArrowDown));
		ashui.input.Keyboard.input(tvTree, key(Named(Enter), Enter));
		var walked = tvPick.get();
		ashui.input.Keyboard.input(tvTree, key(Named(ArrowLeft), ArrowLeft));
		ashui.input.Keyboard.input(tvTree, key(Named(ArrowLeft), ArrowLeft));
		tvFrames(40);
		check("a TreeView's arrows walk the rows shown and Enter chooses; Left steps out to the parent, then closes it",
			walked == "a2" && identity2(tvTree, tvItem("tvA")).attribute("data-state") == "closed" && Math.abs(tvRowY("tvB") - bClosed) < 0.5,
			[walked, identity2(tvTree, tvItem("tvA")).attribute("data-state"), tvRowY("tvB")]);


		// --- Typography: prose spaces its elements by what follows what; lead, large and muted are their own text styles ---
		var tyTree = new LayoutTree();
		var tyRoot:Div = Owner.root(tyTree, _ -> hxx('
			<div width={800} height={800} flexDirection={Column}>
				<prose><h1 id="tyH1">Title</h1><p id="tyP1">First.</p><h2 id="tyH2">Section</h2><p id="tyP2">Second.</p></prose>
				<lead id="tyLead">Lead</lead><large id="tyLarge">Large</large><muted id="tyMuted">Muted</muted>
			</div>
		'));
		tyTree.flush();
		tyTree.computeLayout(tyRoot.node, 800, 800);
		tyTree.flush();
		function tyBox(id:String)
			return tyTree.getBounds(new ashui.layout.Node(Lambda.find(tyTree.order(), n -> identity2(tyTree, n) != null && identity2(tyTree, n).id == id)));
		var h1 = tyBox("tyH1"), p1 = tyBox("tyP1"), h2 = tyBox("tyH2"), p2 = tyBox("tyP2");
		var afterTitle = p1.y - (h1.y + h1.height), beforeSection = h2.y - (p1.y + p1.height), afterSection = p2.y - (h2.y + h2.height);
		check("Prose spaces a title's paragraph by 16, a section by 40 above and 24 below, its first element flush",
			h1.y == 0 && Math.abs(afterTitle - 16) < 0.5 && Math.abs(beforeSection - 40) < 0.5 && Math.abs(afterSection - 24) < 0.5,
			[h1.y, afterTitle, beforeSection, afterSection]);
		check("Lead, Large and Muted step the text size: larger, a little larger, smaller",
			tyBox("tyLead").height > tyBox("tyLarge").height && tyBox("tyLarge").height > tyBox("tyMuted").height,
			[tyBox("tyLead").height, tyBox("tyLarge").height, tyBox("tyMuted").height]);

		Sys.println(failures == 0 ? "ALL PASSED" : '$failures FAILED');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
