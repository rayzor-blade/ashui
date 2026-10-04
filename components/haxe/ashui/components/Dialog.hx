package ashui.components;

import ashui.components.Button;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.layout.LayoutTree;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef DialogProps = {
	/** Whether it is open. A signal is read and written, so the dialog and your code share it; a constant sets it once. **/
	?open:IntoReactive<Bool>,
	/** Called with whether it is open, each time that changes. **/
	?onOpenChange:Bool->Void,
	?id:String
}

/** How wide a dialog may grow: 400, 500 (the default), 600 or 800 units. **/
enum abstract DialogSize(String) to String {
	var Sm = "sm";
	var Md = "md";
	var Lg = "lg";
	var Full = "full";
}

/**
	A dialog: a `DialogTrigger` that opens it and a `DialogContent`, the
	panel, which opens in the top layer over a dimmed page, growing in.
	Inside the panel, a `DialogHeader` holds a `DialogTitle` and a
	`DialogDescription`, and a `DialogFooter` its actions, a `DialogClose`
	among them. Escape, a press on the page behind, or a `DialogClose`
	closes it, and focus goes back where it was; Tab stays inside while it
	is open. It is HTML's modal `<dialog>` (`ashui.ui.Dialog`) underneath.

	```haxe
	<dialog>
		<dialog-trigger variant={Outline}>Edit profile</dialog-trigger>
		<dialog-content>
			<dialog-header><dialog-title>Edit profile</dialog-title><dialog-description>Changes save when you press Save.</dialog-description></dialog-header>
			<dialog-footer><dialog-close>Cancel</dialog-close><button onClick={save}>Save</button></dialog-footer>
		</dialog-content>
	</dialog>
	```

	CSS: `.ui-dialog-root` (`[data-state]` open, closed), `.ui-dialog` (the
	panel, `[data-size]`, `[open]`, `[closing]`), `.ui-dialog-header`,
	`.ui-dialog-title`, `.ui-dialog-description`, `.ui-dialog-footer`;
	`--ui-dialog-bg`, `-border`, `-radius`, `-padding`, `-gap`, `-shadow`,
	`-width`.
**/
class Dialog extends Component<DialogProps> {
	/** Whether it is open; the caller's signal when `open` was one. **/
	public var opened(default, null):Signal<Bool>;

	/** Each dialog by its root's node and its panel's, so a trigger or a close button inside finds the one it is in. **/
	static final registry = new Registry<Dialog>();

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
		var open = opened;
		if (props.onOpenChange != null) {
			var first = true;
			new Watch(() -> open.get(), v -> if (first) first = false else props.onOpenChange(v));
		}
		var root = Library.part("ui-dialog-root", null, ["state" => Computed.make(() -> (open.get() ? "open" : "closed" : Null<String>))], children,
			props.id);
		registry.add(root.tree, root.node.id, this);
		for (c in children)
			if (Std.isOfType(c, DialogContent))
				(cast c : DialogContent).bindTo(this);
		return root;
	}

	/** The dialog the node `id` of `tree` is in: its panel's, or the one whose trigger it is. **/
	public static function near(tree:LayoutTree, id:haxe.Int64):Null<Dialog>
		return registry.near(tree, id);
}

/** A button that opens the dialog it is in; it takes a Button's `variant` and `size`. **/
class DialogTrigger extends Component<{?variant:ButtonVariant, ?size:ButtonSize, ?id:String}> {
	function render():Element {
		var button:Null<Button> = null;
		button = new Button({
			variant: props.variant,
			size: props.size,
			type: "button",
			id: props.id,
			onClick: _ -> {
				var d = Dialog.near(button.tree, button.node.id);
				if (d != null)
					d.opened.set(true);
			}
		}, children);
		return button;
	}
}

/** A button that closes the dialog it is in; an outline button unless given a `variant`. **/
class DialogClose extends Component<{?variant:ButtonVariant, ?size:ButtonSize, ?id:String}> {
	function render():Element {
		var button:Null<Button> = null;
		button = new Button({
			variant: props.variant == null ? Outline : props.variant,
			size: props.size,
			type: "button",
			id: props.id,
			onClick: _ -> {
				var d = Dialog.near(button.tree, button.node.id);
				if (d != null)
					d.opened.set(false);
			}
		}, children);
		return button;
	}
}

typedef DialogContentProps = {
	?size:DialogSize,
	/** A sheet's edge: "right", "left", "top" or "bottom"; a dialog has none. **/
	?side:String,
	?id:String
}

/** The dialog's panel, in the top layer while it is open. **/
class DialogContent extends Component<DialogContentProps> {
	/** Whether the panel is open: the dialog keeps it and its own `opened` together. **/
	final open = Signal.make(false);

	var panel:Null<ashui.ui.Div> = null;

	/** Whether Escape and the page behind close it. **/
	function dismissible():Bool
		return true;

	/** The panel's class, and where it opens. **/
	function panelClass():String
		return "ui-dialog";

	function placement():ashui.ui.TopLayer.Placement
		return Centered;

	/** What the panel holds: its children, and for a subclass anything it adds. **/
	function contents():Array<Element>
		return children;

	function size():String
		return props.size == null ? DialogSize.Md : props.size;

	function render():Element {
		Library.use();
		var dialog = new ashui.ui.Dialog({
			open: open,
			classes: [panelClass()],
			id: props.id,
			backdrop: ashui.types.Brush.solid(0x000000, 0.5),
			dismissible: dismissible(),
			placement: placement()
		}, contents());
		panel = dialog.panel;
		ashui.css.Identity.of(panel.tree, panel.node.id).setAttribute("data-size", size());
		return dialog;
	}

	@:allow(ashui.components.Dialog)
	function bindTo(d:Dialog):Void {
		if (panel != null)
			@:privateAccess Dialog.registry.add(panel.tree, panel.node.id, d);
		var opened = d.opened;
		open.set(opened.get());
		new Watch(() -> opened.get(), v -> if (open.get() != v) open.set(v));
		new Watch(() -> open.get(), v -> if (opened.get() != v) opened.set(v));
	}
}

/** The panel's title and description. **/
class DialogHeader extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-dialog-header", null, null, children, props.id);
}

/** The dialog's title, a flow of text. **/
class DialogTitle extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-dialog-title", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** What the dialog is for, under its title, a flow of text. **/
class DialogDescription extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-dialog-description", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** The panel's actions, at its end. **/
class DialogFooter extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-dialog-footer", null, null, children, props.id);
}

/**
	A dialog that asks for a decision: as `Dialog`, but Escape and the page
	behind do not close it, only its own actions. Its parts are
	`AlertDialogContent` and the dialog's own (`DialogTrigger`,
	`DialogHeader`, `DialogClose` and the rest).
**/
class AlertDialog extends Dialog {}

/** An alert dialog's panel: only its own actions close it. **/
class AlertDialogContent extends DialogContent {
	override function dismissible():Bool
		return false;
}
