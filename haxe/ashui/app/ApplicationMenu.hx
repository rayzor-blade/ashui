package ashui.app;

import ashui.core.UiContext;
import ashui.reactive.Owner;

/** A command or a separator in an application menu. */
typedef MenuItem = {
	?label:String,
	?separator:Bool,
	?enabled:Bool,
	?shortcut:String,
	?key:{
		key:String,
		meta:Bool,
		ctrl:Bool,
		alt:Bool,
		shift:Bool
	},
	?run:Void->Void
};

typedef MenuGroup = {label:String, items:Array<MenuItem>};

#if (hlwindow || ashui_window)
/** A focused window's application menus; native on macOS, a Menubar elsewhere. */
class ApplicationMenu {
	static var nextId = 1;
	static final actions = new Map<Int, Void->Void>();
	static final local = new ashui.core.UiContext.Local<Null<ApplicationMenu>>(() -> null);

	final ids:Array<Int> = [];
	final name:String;
	final quit:Void->Void;
	var groups:Array<MenuGroup>;
	var payload:String;

	public static function native():Bool
		return Sys.systemName() == "Mac";

	public function new(name:String, quit:Void->Void) {
		this.name = name;
		this.quit = quit;
		local.value = this;
		Owner.onCleanup(() -> {
			release();
			local.value = null;
		});
	}

	function release():Void {
		for (id in ids)
			actions.remove(id);
		ids.resize(0);
	}

	function action(fn:Void->Void):Int {
		var id = nextId++, context = UiContext.current;
		ids.push(id);
		actions.set(id, () -> context.run(fn));
		return id;
	}

	/** Updates this window's menu, without replacing the focused window's menu. */
	public function update(groups:Array<MenuGroup>):Void {
		release();
		this.groups = groups;
		payload = haxe.Json.stringify({
			name: name,
			quit: action(quit),
			menus: [
				for (group in groups)
					{
						label: group.label,
						items: [
							for (item in group.items)
								{
									label: item.label,
									separator: item.separator == true,
									enabled: item.enabled != false,
									key: item.key,
									id: item.run == null ? 0 : action(item.run)
								}
						]
					}
			]
		});
		var app = WindowedApp.current;
		if (native() && app != null && app.window.hasFocus())
			activate();
	}

	function activate():Void {
		if (payload != null)
			MenuNative.ui_menu_install(@:privateAccess payload.toUtf8());
	}

	@:allow(ashui.app.WindowedApp)
	static function focus():Void {
		var menu = local.value;
		if (native() && menu != null)
			menu.activate();
	}

	/** Drains native actions after the platform pump, never reentering Haxe from a Cocoa callback. */
	@:allow(ashui.app.WindowedApp)
	static function pump():Void {
		if (!native())
			return;
		while (true) {
			var id = MenuNative.ui_menu_poll();
			if (id == 0)
				return;
			var run = actions.get(id);
			if (run != null)
				run();
		}
	}

	@:allow(ashui.app.WindowedApp)
	static function shutdown():Void {
		actions.clear();
		if (native())
			MenuNative.ui_menu_clear();
	}
}

@:hlNative("blinc_abi")
private extern class MenuNative {
	static function ui_menu_install(json:hl.Bytes):Bool;
	static function ui_menu_poll():Int;
	static function ui_menu_clear():Void;
}
#end
