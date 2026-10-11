package ashui.input;

import ashui.css.Css;
import ashui.css.Identity;
import ashui.layout.LayoutTree;
import ashui.layout.LayoutTree.Hit;
import window.CursorIcon;

/** CSS cursors, resolved on target changes and restyles without subscribing to pointer movement. **/
class Cursor {
	/** `none` hides the native cursor; other values are hlwindow's CursorIcon. **/
	@:noCompletion public static inline var HIDDEN = -1;
	static final sinks = new haxe.ds.ObjectMap<LayoutTree, {write:Int->Void, value:Null<String>, code:Int}>();
	static final pending = new haxe.ds.ObjectMap<LayoutTree, Bool>();
	static var hooked = false;

	/** The standard keyword cursors hlwindow provides. Custom cursor images are not supported here. **/
	public static function parse(value:String):Int {
		return switch StringTools.trim(value).toLowerCase() {
			case "auto" | "default": CursorIcon.Default;
			case "none": HIDDEN;
			case "context-menu": CursorIcon.ContextMenu;
			case "help": CursorIcon.Help;
			case "pointer": CursorIcon.Pointer;
			case "progress": CursorIcon.Progress;
			case "wait": CursorIcon.Wait;
			case "cell": CursorIcon.Cell;
			case "crosshair": CursorIcon.Crosshair;
			case "text": CursorIcon.Text;
			case "vertical-text": CursorIcon.VerticalText;
			case "alias": CursorIcon.Alias;
			case "copy": CursorIcon.Copy;
			case "move": CursorIcon.Move;
			case "no-drop": CursorIcon.NoDrop;
			case "not-allowed": CursorIcon.NotAllowed;
			case "grab": CursorIcon.Grab;
			case "grabbing": CursorIcon.Grabbing;
			case "e-resize": CursorIcon.EResize;
			case "n-resize": CursorIcon.NResize;
			case "ne-resize": CursorIcon.NeResize;
			case "nw-resize": CursorIcon.NwResize;
			case "s-resize": CursorIcon.SResize;
			case "se-resize": CursorIcon.SeResize;
			case "sw-resize": CursorIcon.SwResize;
			case "w-resize": CursorIcon.WResize;
			case "ew-resize": CursorIcon.EwResize;
			case "ns-resize": CursorIcon.NsResize;
			case "nesw-resize": CursorIcon.NeswResize;
			case "nwse-resize": CursorIcon.NwseResize;
			case "col-resize": CursorIcon.ColResize;
			case "row-resize": CursorIcon.RowResize;
			case "all-scroll": CursorIcon.AllScroll;
			case "zoom-in": CursorIcon.ZoomIn;
			case "zoom-out": CursorIcon.ZoomOut;
			case _: throw "cursor takes a standard keyword; custom cursor images are not supported";
		};
	}

	/** Attaches a window's cursor setter. No per-element maps or watches are needed. **/
	@:noCompletion public static function bind(tree:LayoutTree, write:Int->Void):Void {
		if (!hooked) {
			hooked = true;
			Css.restyled.push(identity -> {
				if (sinks.exists(identity.tree)) pending.set(identity.tree, true);
			});
			LayoutTree.flushHooks.push(tree -> {
				if (pending.remove(tree)) retarget(tree, ashui.input.Pointer.hoverChain(tree));
			});
		}
		sinks.set(tree, {write: write, value: null, code: -2});
		retarget(tree, ashui.input.Pointer.hoverChain(tree));
	}

	@:noCompletion public static function unbind(tree:LayoutTree):Void {
		sinks.remove(tree);
		pending.remove(tree);
	}

	/** Called only on hit-test paths; quiet moves return before reaching it. **/
	@:noCompletion public static function retarget(tree:LayoutTree, chain:Array<Hit>):Void {
		var sink = sinks.get(tree);
		if (sink == null) return;
		var value:Null<String> = null;
		for (hit in chain) {
			var identity = Identity.of(tree, hit.id);
			if (identity != null) value = Css.resolved(identity, "cursor");
			if (value != null) break;
		}
		if (value == null) value = "auto";
		if (sink.value == value) return;
		var code = try parse(value) catch (_:String) CursorIcon.Default;
		sink.value = value;
		if (code != sink.code) {
			sink.code = code;
			sink.write(code);
		}
	}
}
