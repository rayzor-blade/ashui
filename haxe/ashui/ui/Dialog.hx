package ashui.ui;

import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.TopLayer;

/** A close request; preventDefault keeps the dialog open. Programmatic close and form submission do not send it. **/
class DialogCancelEvent {
	public final target:Dialog;
	public var defaultPrevented(default, null) = false;
	@:allow(ashui.ui.Dialog)
	function new(target:Dialog) this.target = target;
	public function preventDefault():Void defaultPrevented = true;
}

typedef DialogProps = {
	/** Whether it is open. A signal is read and written: closing it with Escape or the backdrop sets it false. **/
	?open:IntoReactive<Bool>,

	/** In the top layer over a dimmed backdrop, holding focus, as `showModal()` opens HTML's; true by default. In place when false. **/
	?modal:Bool,

	?id:String,

	/** Classes of the dialog itself, for a component library that styles it. **/
	?classes:Array<String>,

	/** What dims the page behind a modal one; black at 40% by default. **/
	?backdrop:ashui.types.Brush,

	/** Whether Escape and a press on the backdrop close it; true by default, as HTML's. False for one only its own controls close. **/
	?dismissible:Bool,
	/** User dismissal: any (Escape/backdrop), closerequest (Escape) or none. Omitted, preserves dismissible's behavior. **/
	?closedby:String,
	/** Called before a user or requestClose closes it; preventDefault refuses the request. **/
	?onCancel:DialogCancelEvent->Void,

	/** Where a modal one opens in the top layer: centred by default, or along an edge (a sheet). **/
	?placement:ashui.ui.TopLayer.Placement,

	/** Called when it closes, however it closes. **/
	?onClose:Void->Void
}

/**
	HTML's `<dialog>`, built in. Modal, as by default, it opens in the top
	layer, centred over a dimmed backdrop; Tab and Shift+Tab stay inside it,
	its first focusable element takes focus, and Escape or a press on the
	backdrop closes it, giving focus back to what had it. Not modal, it is
	shown in place while open. Either way it is a `dialog` element marked
	`[open]` while open, for CSS.
**/
class Dialog extends Component<DialogProps> {
	static final registry = new ashui.layout.Registry<Dialog>();

	/** Whether it is open; the caller's signal when `open` was one. **/
	public var opened(default, null):Signal<Bool>;

	/** The dialog element itself: in place when not modal, in the top layer while a modal one is open. **/
	public var panel(default, null):Div;
	/** The value supplied by close(), requestClose() or a method=dialog submit button. **/
	public var returnValue = "";

	var entry:Null<TopEntry> = null;
	var release:Null<Void->Void> = null;
	var before:Null<Interaction> = null;
	var pending:Null<LayoutTree->Void> = null;

	/** The dialog containing a node, including a modal panel moved into the top layer. **/
	@:noCompletion public static function near(tree:LayoutTree, node:haxe.Int64):Null<Dialog> {
		return registry.near(tree, node);
	}

	function register(dialog:Div):Void {
		var tree = dialog.tree, id = dialog.node.id;
		registry.add(tree, id, this);
		if (props.closedby != null) ashui.css.Identity.of(tree, id).setAttribute("closedby", props.closedby);
	}

	function dismissal():String {
		var policy = props.closedby == null ? null : StringTools.trim(props.closedby).toLowerCase();
		return switch policy {
			case "any" | "closerequest" | "none": policy;
			case _: props.dismissible == false ? "none" : "any";
		};
	}

	/** Closes without sending cancel. Omitting a value preserves the previous returnValue. **/
	public function close(?value:String):Void {
		if (!opened.get()) return;
		if (value != null) returnValue = value;
		opened.set(false);
		hide();
	}

	/** Sends cancel, then closes unless a handler prevents it. closedby restricts user actions, not this API. **/
	public function requestClose(?value:String):Void {
		if (!opened.get()) return;
		var event = new DialogCancelEvent(this);
		if (props.onCancel != null) props.onCancel(event);
		if (!event.defaultPrevented && opened.get()) close(value);
	}

	function render():Element {
		opened = switch props.open {
			case null: Signal.make(false);
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var modal = props.modal != false;
		var box = new Div({tag: "dialog", id: modal ? null : props.id}, modal ? [] : children);
		// Given only when there are some: a null wrapped as a constant would be read as classes.
		if (!modal && props.classes != null)
			ashui.css.Identity.of(box.tree, box.node.id).addClasses(props.classes);
		if (!modal) {
			var identity = ashui.css.Identity.of(box.tree, box.node.id);
			var first = true;
			new Watch(() -> opened.get(), v -> {
				identity.setAttribute("open", v ? "" : null);
				if (!first && !v && props.onClose != null) props.onClose();
				first = false;
			});
			panel = box;
			register(box);
			Interaction.of(box.node).onKeyDown(e -> switch e.key {
				case Named(Escape):
					if (!e.defaultPrevented && dismissal() != "none") {
						e.preventDefault();
						requestClose();
					}
				case _:
			});
			return box;
		}
		// Modal: a placeholder in place, and the dialog itself in the top layer while open.
		var dialog = new Div({tag: "dialog", id: props.id}, children);
		if (props.classes != null)
			ashui.css.Identity.of(dialog.tree, dialog.node.id).addClasses(props.classes);
		panel = dialog;
		register(dialog);
		box.node.set(ashui.layout.Prop.Display, ashui.types.Style.Display.None);
		new Watch(() -> opened.get(), v -> if (v) show(dialog) else hide());
		Owner.onCleanup(hide);
		return box;
	}

	function show(dialog:Div):Void {
		if (entry != null)
			return;
		var tree = dialog.tree;
		// The top layer needs the tree laid out; until it is, open at the next flush.
		if (tree.root == null) {
			if (pending != null) return;
			pending = t -> if (t == tree && tree.root != null) {
				LayoutTree.flushHooks.remove(pending);
				pending = null;
				if (opened.get())
					show(dialog);
			};
			LayoutTree.flushHooks.push(pending);
			return;
		}
		before = Focus.of(tree);
		// Reopened during its closing animation, the panel still belongs to the old holder.
		// A modal panel is that holder's only child; detach it before placing it in the new layer.
		var parent = tree.ancestors(dialog.node.id);
		if (parent.length > 0) tree.detachChildren(parent[0]);
		// Marked open as it is shown, so its opening animation starts then.
		var identity = ashui.css.Identity.of(tree, dialog.node.id);
		identity.setAttribute("open", "");
		entry = TopLayer.open(tree, dialog, props.placement != null ? props.placement : Centered, props.backdrop != null ? props.backdrop : ashui.types.Brush.solid(0x000000, 0.4), () -> {
			identity.setAttribute("open", null);
			entry = null;
			if (release != null)
				release();
			release = null;
			if (opened.get())
				opened.set(false);
			if (before != null)
				Focus.set(before, false);
			if (props.onClose != null)
				props.onClose();
		}, false, true, false, reason -> {
			var policy = dismissal();
			if (policy == "any" || policy == "closerequest" && reason == Escape) requestClose();
		});
		release = Focus.trap(dialog.node);
		// The first focusable element inside takes focus.
		var focused = false;
		for (id in tree.order())
			if (id != dialog.node.id && tree.ancestors(id).indexOf(dialog.node.id) >= 0) {
				var i = Interaction.byId(tree, id);
				if (i != null && i.focusable && !i.disabled.get()) {
					Focus.set(i, Focus.byKeyboard);
					focused = true;
					break;
				}
			}
		if (!focused) Focus.set(Interaction.of(dialog.node).setFocusable(true), Focus.byKeyboard);
	}

	function hide():Void {
		var waiting = pending != null;
		if (pending != null) {
			LayoutTree.flushHooks.remove(pending);
			pending = null;
		}
		if (entry != null)
			entry.close();
		else if (waiting) {
			if (opened.get()) opened.set(false);
			if (props.onClose != null) props.onClose();
		}
	}
}
