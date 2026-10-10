package ashui.css;

import ashui.core.externs.CssNative;
import ashui.layout.LayoutTree;

/**
	The cascade run by the native CSS engine (`CssNative`), with
	`-D ashui_native_css`: the sheets in force, every element's names and
	states, the theme's variables and what `@media` asks about go to it, and
	it answers which elements' styles changed and what they are. `Css`
	applies those as it applies its own.
**/
class NativeCascade {
	static var handle:Null<hl.Abstract<"blinc_css">> = null;

	/** Each sheet's id in the engine. **/
	static final ids = new haxe.ds.ObjectMap<Stylesheet, Int>();

	/** The sheets in the engine, in its order. **/
	static var order:Array<Stylesheet> = [];

	/** Parents whose children changed since the last restyle, by tree. **/
	static final reordered = new haxe.ds.ObjectMap<LayoutTree, Map<String, haxe.Int64>>();

	/** A watch for each node state a selector tests, by `node:bit`. **/
	static final watches = new Map<String, ashui.reactive.Watch<Bool>>();

	static inline final RECORD = "\x01";
	static inline final PAIR = "\x02";
	static inline final ITEM = "\x03";

	static function css():hl.Abstract<"blinc_css"> {
		if (handle == null)
			handle = CssNative.blinc_css_new();
		return handle;
	}

	static inline function utf8(s:String):hl.Bytes
		return @:privateAccess s.toUtf8();

	static inline function text(b:hl.Bytes):String
		return b == null ? "" : @:privateAccess String.fromUTF8(b);

	/** Puts `sheets` in force in the engine, in this order: those gone are taken out, new ones added in their place. **/
	public static function sync(sheets:Array<Stylesheet>):Void {
		for (sheet in order)
			if (sheets.indexOf(sheet) < 0) {
				var id = ids.get(sheet);
				if (id != null && id >= 0)
					CssNative.blinc_css_remove(css(), id);
				ids.remove(sheet);
			}
		order = [for (sheet in order) if (sheets.indexOf(sheet) >= 0) sheet];
		for (at => sheet in sheets) {
			if (ids.exists(sheet))
				continue;
			var id = -1;
			var source = sheet.source == null ? "" : sheet.source;
			CssNative.blinc_css_add(css(), utf8(source), utf8(sheet.file == null ? "" : sheet.file), at, id);
			ids.set(sheet, id);
			order.insert(at, sheet);
		}
	}

	/** The theme's variables, `var()`'s last answer. **/
	public static function setTheme(variables:Map<String, String>):Void {
		var records = [for (name => value in variables) (StringTools.startsWith(name, "--") ? name.substr(2) : name) + PAIR + value];
		CssNative.blinc_css_set_theme(css(), utf8(records.join(RECORD)));
	}

	public static function setEnvironment(width:Float, height:Float, dark:Bool, rootFontSize:Float):Void
		CssNative.blinc_css_set_environment(css(), width, height, dark ? 1 : 0, rootFontSize);

	/** Tells the engine what `identity` is now: its types, id, classes, attributes and own declarations. **/
	public static function describe(identity:Identity):Void {
		var attributes = @:privateAccess identity.attributes;
		var declared = identity.inlineDeclarations();
		var desc = [
			identity.types.join(" "),
			identity.id == null ? "" : identity.id,
			identity.classes().join(" "),
			attributes == null ? "" : [for (k => v in attributes) k + PAIR + v].join(ITEM),
			declared == null ? "" : [for (k => v in declared) k + PAIR + v].join(ITEM),
			identity.anonymous ? "1" : ""
		].join(RECORD);
		CssNative.blinc_css_set_element(css(), identity.node.id, utf8(desc));
	}

	public static function forget(identity:Identity):Void {
		var node = identity.node.id;
		CssNative.blinc_css_forget(css(), node);
		var prefix = haxe.Int64.toStr(node) + ":";
		for (key => w in watches)
			if (StringTools.startsWith(key, prefix)) {
				w.stop();
				watches.remove(key);
			}
	}

	/** `parent`'s children are changing: they and what is under them are matched again. **/
	public static function childrenChanged(tree:LayoutTree, parent:haxe.Int64):Void {
		var nodes = reordered.get(tree);
		if (nodes == null)
			reordered.set(tree, nodes = new Map());
		nodes.set(haxe.Int64.toStr(parent), parent);
	}

	/** `node`'s identity, in whichever tree it is: every tree's nodes are in the one native tree. **/
	static function find(node:haxe.Int64):Null<Identity> {
		for (tree in @:privateAccess Identity.trees.keys()) {
			var identity = Identity.of(tree, node);
			if (identity != null)
				return identity;
		}
		return null;
	}

	/**
		Restyles what changed and returns the elements whose styles changed,
		parents first. The native tree holds every tree's nodes, so this
		covers them all; `tree` is the one flushing.
	**/
	public static function restyle(tree:LayoutTree):Array<Identity> {
		var nodes = reordered.get(tree);
		if (nodes != null) {
			reordered.remove(tree);
			for (parent in nodes) {
				CssNative.blinc_css_children_changed(css(), parent);
				for (child in tree.children(parent))
					CssNative.blinc_css_moved(css(), child);
			}
		}
		// The whole forest: an element made on its own, not yet placed, is styled too, and `:root` is any with no parent.
		var changed:Array<Identity> = [];
		// A state a selector began to test is read now and the engine told, so it holds in this frame: once more while there are new ones.
		for (_ in 0...4) {
			var count = CssNative.blinc_css_restyle(css(), tree.ptr, haxe.Int64.make(0, 0));
			if (count > 0) {
				var out = new hl.Bytes(count * 8);
				var n = CssNative.blinc_css_take_changed(css(), out, count);
				for (i in 0...n) {
					var identity = find(haxe.Int64.make(out.getI32(i * 8 + 4), out.getI32(i * 8)));
					if (identity != null && changed.indexOf(identity) < 0)
						changed.push(identity);
				}
			}
			if (!watchStates())
				break;
		}
		return changed;
	}

	/** The elements under `root` that `selectors` match, in document order; throws for selectors that do not read. **/
	public static function select(tree:LayoutTree, root:haxe.Int64, selectors:String):Array<haxe.Int64> {
		var capacity = 256;
		while (true) {
			var out = new hl.Bytes(capacity * 8);
			var n = CssNative.blinc_css_select(css(), tree.ptr, root, utf8(selectors), out, capacity);
			if (n < 0)
				throw 'bad selector "$selectors"';
			if (n <= capacity)
				return [for (i in 0...n) haxe.Int64.make(out.getI32(i * 8 + 4), out.getI32(i * 8))];
			capacity = n;
		}
	}

	/** `identity`'s style as the engine computed it. **/
	public static function style(identity:Identity):{resolved:Map<String, String>, values:Map<String, String>, fontSize:Float} {
		var records = text(CssNative.blinc_css_style(css(), identity.node.id)).split(RECORD);
		function pairs(record:Null<String>):Map<String, String> {
			var map = new Map<String, String>();
			if (record != null && record != "")
				for (item in record.split(ITEM)) {
					var at = item.indexOf(PAIR);
					if (at > 0)
						map.set(item.substr(0, at), item.substr(at + 1));
				}
			return map;
		}
		var size = records.length > 2 ? Std.parseFloat(records[2]) : Math.NaN;
		return {resolved: pairs(records[0]), values: pairs(records[1]), fontSize: Math.isNaN(size) ? Css.rootFontSize : size};
	}

	/** The states a selector began to test: each is watched, and its changes told to the engine. **/
	static function watchStates():Bool {
		var set = false;
		var capacity = 64;
		while (true) {
			var nodes = new hl.Bytes(capacity * 8), bits = new hl.Bytes(capacity * 4);
			var n = CssNative.blinc_css_take_watched(css(), nodes, bits, capacity);
			for (i in 0...n) {
				var node = haxe.Int64.make(nodes.getI32(i * 8 + 4), nodes.getI32(i * 8));
				if (watch(node, bits.getI32(i * 4)))
					set = true;
			}
			if (n < capacity)
				break;
		}
		return set;
	}

	/** The state names the engine knows, by bit. **/
	static var names:Null<Map<Int, String>> = null;

	static function stateName(bit:Int):Null<String> {
		if (names == null) {
			names = new Map();
			for (name in STATES) {
				var b = CssNative.blinc_css_state_bit(utf8(name));
				if (b != 0)
					names.set(b, name);
			}
		}
		return names.get(bit);
	}

	static final STATES = [
		"hover", "active", "focus", "focus-visible", "focus-within", "disabled", "enabled", "checked", "indeterminate", "placeholder-shown", "valid",
		"invalid", "user-valid", "user-invalid", "required", "optional"
	];

	/** Watches state `bit` of `node`; true when it found a state set, which the engine was told. **/
	static function watch(node:haxe.Int64, bit:Int):Bool {
		var key = haxe.Int64.toStr(node) + ":" + bit;
		if (watches.exists(key))
			return false;
		var name = stateName(bit);
		var identity = find(node);
		if (name == null || identity == null)
			return false;
		var signal = stateSignal(identity, name);
		watches.set(key, new ashui.reactive.Watch(() -> signal.get(), on -> {
			CssNative.blinc_css_set_states(css(), node, mask(identity));
			ashui.core.Work.notify();
		}));
		var states = mask(identity);
		CssNative.blinc_css_set_states(css(), node, states);
		return states != 0;
	}

	static function stateSignal(identity:Identity, name:String):ashui.reactive.Signal<Bool> {
		var interaction = ashui.input.Interaction.of(identity.node);
		return switch name {
			case "hover": interaction.hovered;
			case "active": interaction.pressed;
			case "focus": interaction.focused;
			case "focus-visible": interaction.focusVisible;
			case "focus-within": interaction.focusWithin;
			case "checked": interaction.checked;
			case "indeterminate": interaction.indeterminate;
			case n if (Selector.FORM_STATES.indexOf(n) >= 0): interaction.formState(n);
			case _: interaction.disabled;
		}
	}

	/** Every state of `identity` the engine knows, as its mask; `:enabled` is not disabled. **/
	static function mask(identity:Identity):Int {
		stateName(0);
		var out = 0;
		for (bit => name in names) {
			var on = stateSignal(identity, name).get();
			if (name == "enabled")
				on = !on;
			if (on)
				out |= bit;
		}
		return out;
	}
}
