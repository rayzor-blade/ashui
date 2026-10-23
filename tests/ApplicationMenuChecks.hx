import ashui.app.ApplicationMenu;
import ashui.core.UiContext;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;

@:access(ashui.app.ApplicationMenu)
class ApplicationMenuChecks {
	static function check(ok:Bool, message:String):Void { if (!ok) throw message; }
	static function queued(ids:Array<Int>):Void {
		var next = 0;
		ApplicationMenu.drain(() -> next < ids.length ? ids[next++] : 0);
	}
	static function item(menu:ApplicationMenu):Int return haxe.Json.parse(menu.payload).menus[0].items[0].id;
	static function update(context:UiContext, menu:ApplicationMenu, run:Void->Void):Void
		context.run(() -> menu.update([{label:"File",items:[{label:"Open Project…",run:run}]}]));
	static function main():Void {
		if (!ApplicationMenu.native()) { Sys.println("native menu action checks: macOS only"); return; }
		var first = new UiContext(), second = new UiContext();
		var treeA = first.run(() -> new LayoutTree()), treeB = second.run(() -> new LayoutTree());
		var stopA:Void->Void = null, stopB:Void->Void = null, oldCalls = 0, newCalls = 0;
		var a = first.run(() -> Owner.root(treeA, cleanup -> {stopA=cleanup; return new ApplicationMenu("First", () -> {});}));
		var b = second.run(() -> Owner.root(treeB, cleanup -> {stopB=cleanup; return new ApplicationMenu("Second", () -> {});}));
		update(first, a, () -> {check(UiContext.current == first, "Queued action lost its window context"); oldCalls++;});
		var old = item(a);
		update(first, a, () -> newCalls++);
		queued([old]);
		check(oldCalls == 1 && newCalls == 0, "A menu rebuild dropped or replaced a queued click");
		check(!ApplicationMenu.actions.exists(old), "Drained action retained its previous handler");
		for (_ in 0...200) {
			var pending = item(a);
			update(first, a, () -> newCalls++);
			queued([pending]);
			check(Lambda.count(ApplicationMenu.actions) == 2 && ApplicationMenu.pendingRetirement.length == 0, "Menu updates retained drained callbacks");
		}
		check(newCalls == 200, "A single menu click needed another action to be delivered");
		var visible = item(a);
		a.shown = a.ids.copy(); ApplicationMenu.installed = a;
		update(first, a, () -> newCalls++);
		queued([]);
		check(ApplicationMenu.actions.exists(visible), "An unfocused update discarded the menu still shown by the platform");
		update(first, a, () -> newCalls++); queued([visible]);
		check(newCalls == 201 && Lambda.count(ApplicationMenu.actions) == 4, "Displayed menu callbacks were lost or intermediate updates were retained");
		a.shown.resize(0); ApplicationMenu.installed = null;
		ApplicationMenu.pendingRetirement.push(a); queued([]);
		check(Lambda.count(ApplicationMenu.actions) == 2, "Replacing the displayed menu retained its handlers");
		var order:Array<String> = [];
		update(first, a, () -> {order.push("first"); update(first, a, () -> order.push("latest"));});
		var firstId = item(a);
		update(first, a, () -> order.push("second"));
		var secondId = item(a);
		queued([firstId, secondId]);
		check(order.join(",") == "first,second", "Updating a menu from a callback dropped another queued action");
		update(second, b, () -> {check(UiContext.current == second, "Second window action ran in another context"); order.push("other window");});
		var otherId = item(b), disposed = item(a);
		update(first, a, () -> order.push("disposed"));
		first.run(stopA); treeA.dispose();
		queued([disposed, otherId]);
		check(order.join(",") == "first,second,other window", "Closed menus answered a queued click or affected another window");
		second.run(stopB); treeB.dispose();
		check(Lambda.count(ApplicationMenu.actions) == 0 && ApplicationMenu.pendingRetirement.length == 0, "Closing menus retained callbacks or owners");
		Sys.println("menu actions: queued clicks survive updates, preserve order and window context, and release callbacks after draining or owner disposal");
	}
}
