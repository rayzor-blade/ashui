package ashui.input;

import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.LayoutTree;
import window.CursorIcon;

/** CSS cursors, resolved on target changes and restyles without subscribing to pointer movement. **/
class Cursor {
	/** `none` hides the native cursor; other values are hlwindow's CursorIcon. **/
	@:noCompletion public static inline var HIDDEN = -1;

	static final sinks = new haxe.ds.ObjectMap<LayoutTree, {write:Int->Void, value:Null<String>, code:Int}>();
	static final pending = new haxe.ds.ObjectMap<LayoutTree, Bool>();
	static var hooked = false;

	/** The icons in the order of the window package's `CursorIcon`; a cursor is kept as its index, whether the package declares it as an enum or as integers. **/
	static final ICONS = ["Default", "ContextMenu", "Help", "Pointer", "Progress", "Wait", "Cell", "Crosshair", "Text", "VerticalText", "Alias", "Copy", "Move", "NoDrop", "NotAllowed", "Grab", "Grabbing", "EResize", "NResize", "NeResize", "NwResize", "SResize", "SeResize", "SwResize", "WResize", "EwResize", "NsResize", "NeswResize", "NwseResize", "ColResize", "RowResize", "AllScroll", "ZoomIn", "ZoomOut", "DndAsk", "AllResize"];

	static function code(name:String):Int
		return ICONS.indexOf(name);

	/** The window package's icon for an index of `ICONS`. **/
	@:noCompletion public static inline function icon(index:Int):CursorIcon {
		#if ashui_caribou
		return Type.createEnum(CursorIcon, ICONS[index]);
		#else
		return cast index;
		#end
	}

	/** The standard keyword cursors the window package provides. Custom cursor images are not supported here. **/
	public static function parse(value:String):Int {
		return switch StringTools.trim(value).toLowerCase() {
			case "auto" | "default": code("Default");
			case "none": HIDDEN;
			case "context-menu": code("ContextMenu");
			case "help": code("Help");
			case "pointer": code("Pointer");
			case "progress": code("Progress");
			case "wait": code("Wait");
			case "cell": code("Cell");
			case "crosshair": code("Crosshair");
			case "text": code("Text");
			case "vertical-text": code("VerticalText");
			case "alias": code("Alias");
			case "copy": code("Copy");
			case "move": code("Move");
			case "no-drop": code("NoDrop");
			case "not-allowed": code("NotAllowed");
			case "grab": code("Grab");
			case "grabbing": code("Grabbing");
			case "e-resize": code("EResize");
			case "n-resize": code("NResize");
			case "ne-resize": code("NeResize");
			case "nw-resize": code("NwResize");
			case "s-resize": code("SResize");
			case "se-resize": code("SeResize");
			case "sw-resize": code("SwResize");
			case "w-resize": code("WResize");
			case "ew-resize": code("EwResize");
			case "ns-resize": code("NsResize");
			case "nesw-resize": code("NeswResize");
			case "nwse-resize": code("NwseResize");
			case "col-resize": code("ColResize");
			case "row-resize": code("RowResize");
			case "all-scroll": code("AllScroll");
			case "zoom-in": code("ZoomIn");
			case "zoom-out": code("ZoomOut");
			case _: throw "cursor takes a standard keyword; custom cursor images are not supported";
		};
	}

	/** Attaches a window's cursor setter. No per-element maps or watches are needed. **/
	@:noCompletion public static function bind(tree:LayoutTree, write:Int->Void):Void {
		if (!hooked) {
			hooked = true;
			Css.restyled.push(identity -> {
				if (sinks.exists(identity.tree))
					pending.set(identity.tree, true);
			});
			LayoutTree.flushHooks.push(tree -> {
				if (pending.remove(tree))
					retarget(tree);
			});
		}
		sinks.set(tree, {write: write, value: null, code: -2});
		retarget(tree);
	}

	@:noCompletion public static function unbind(tree:LayoutTree):Void {
		sinks.remove(tree);
		pending.remove(tree);
	}

	/** Called only on hit-test paths; quiet moves return before reaching it. **/
	@:noCompletion public static function retarget(tree:LayoutTree):Void {
		var sink = sinks.get(tree);
		if (sink == null)
			return;
		var value:Null<String> = null;
		for (hit in ashui.input.Pointer.cursorChain(tree)) {
			var identity = Identity.of(tree, hit.id);
			if (identity != null)
				value = Css.resolved(identity, "cursor");
			if (value != null)
				break;
		}
		if (value == null)
			value = "auto";
		if (sink.value == value)
			return;
		var code = try parse(value) catch (_:String) 0;
		sink.value = value;
		if (code != sink.code) {
			sink.code = code;
			sink.write(code);
		}
	}
}
