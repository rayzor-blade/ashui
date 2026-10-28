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
	/** Whether the dialog is open. A supplied signal is read and updated; a constant sets the initial state. **/
	?open:IntoReactive<Bool>,
	/** Receives the open state whenever it changes. **/
	?onOpenChange:Bool->Void,
	?id:String
}

/** Dialog maximum width: 400, 500 (default), 600, or 800 layout units. **/
enum abstract DialogSize(String) to String {
	var Sm = "sm";
	var Md = "md";
	var Lg = "lg";
	var Full = "full";
}

/**
	A modal dialog built on `ashui.ui.Dialog`. `DialogTrigger` opens the
	`DialogContent` panel above a dimmed backdrop. Escape, a backdrop press
	or `DialogClose` closes it. Tab stays within the open dialog; closing
	restores the previous focus.

	```haxe
	<dialog>
	    <dialog-trigger variant={Outline}>Edit profile</dialog-trigger>
	    <dialog-content>
	        <dialog-header>
	            <dialog-title>Edit profile</dialog-title>
	            <dialog-description>Press Save to apply changes.</dialog-description>
	        </dialog-header>
	        <dialog-footer>
	            <dialog-close>Cancel</dialog-close>
	            <button onClick={save}>Save</button>
	        </dialog-footer>
	    </dialog-content>
	</dialog>
	```

	CSS: `.ui-dialog-root[data-state="open"|"closed"]` and `.ui-dialog`
	with `[data-size]`, `[open]` and `[closing]`. Header, title, description
	and footer parts use the `ui-dialog-` prefix.
	Tokens: `--ui-dialog-bg`, `-border`, `-radius`, `-padding`, `-gap`,
	`-shadow` and `-width`.
**/
class Dialog extends Component<DialogProps> {
	/** Current open state. Uses the supplied signal when available. **/
	public var opened(default, null):Signal<Bool>;

	/** Registers each dialog by root and panel nodes so triggers and close buttons can find their dialog. **/
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

	/** Finds the dialog associated with a root, trigger, or panel node. **/
	public static function near(tree:LayoutTree, id:haxe.Int64):Null<Dialog>
		return registry.near(tree, id);
}

/** Button that opens its containing dialog. Accepts button `variant` and `size`. **/
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

/** Button that closes its containing dialog. Defaults to the outline variant. **/
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
	/** Allowed user dismissal: `any` for Escape or backdrop, `closerequest` for Escape, or `none` for explicit controls only. **/
	?closedby:String,
	?onCancel:ashui.ui.Dialog.DialogCancelEvent->Void,
	?onClose:Void->Void,
	/** Sheet edge: `right`, `left`, `top`, or `bottom`. Omit for a centered dialog. **/
	?side:String,
	?id:String
}

/** Dialog panel displayed in the top layer while open. **/
class DialogContent extends Component<DialogContentProps> {
	/** Panel open state, synchronized with the parent dialog. **/
	final open = Signal.make(false);

	var panel:Null<ashui.ui.Div> = null;

	/** Returns whether Escape and backdrop clicks can dismiss the panel. **/
	function dismissible():Bool
		return true;

	/** Returns the CSS class used for the panel type. **/
	function panelClass():String
		return "ui-dialog";

	function placement():ashui.ui.TopLayer.Placement
		return Centered;

	/** Returns the backdrop brush. **/
	function backdrop():ashui.types.Brush
		return ashui.types.Brush.solid(0x000000, 0.5);

	/** Returns panel children, including any content added by a subclass. **/
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
			backdrop: backdrop(),
			dismissible: dismissible(),
			closedby: props.closedby,
			onCancel: props.onCancel,
			onClose: props.onClose,
			placement: placement()
		}, contents());
		panel = dialog.panel;
		ashui.css.Identity.of(panel.tree, panel.node.id).setAttribute("data-size", size());
		// A panel built after its dialog, as inside an `<if>`, is in the tree by the next tick, and finds its dialog then.
		var gone = false;
		ashui.reactive.Owner.onCleanup(() -> gone = true);
		ashui.animation.AnimationScheduler.main.after(0, () -> {
			if (!gone && !bound) {
				var d = Dialog.near(panel.tree, dialog.node.id);
				if (d != null)
					bindTo(d);
			}
		});
		return dialog;
	}

	/** Whether a parent dialog manages this panel open state. **/
	var bound = false;

	@:allow(ashui.components.Dialog)
	function bindTo(d:Dialog):Void {
		bound = true;
		if (panel != null)
			@:privateAccess Dialog.registry.add(panel.tree, panel.node.id, d);
		var opened = d.opened;
		open.set(opened.get());
		new Watch(() -> opened.get(), v -> if (open.get() != v) open.set(v));
		new Watch(() -> open.get(), v -> if (opened.get() != v) opened.set(v));
	}
}

/** Header containing the dialog title and description. **/
class DialogHeader extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-dialog-header", null, null, children, props.id);
}

/** Title text for a dialog. **/
class DialogTitle extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-dialog-title", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** Supporting text explaining the dialog purpose. **/
class DialogDescription extends Component<{?id:String}> {
	function render():Element {
		var box = Library.part("ui-dialog-description", null, null, children, props.id);
		ashui.text.InlineFlow.attach(box);
		return box;
	}
}

/** Footer containing dialog actions. **/
class DialogFooter extends Component<{?id:String}> {
	function render():Element
		return Library.part("ui-dialog-footer", null, null, children, props.id);
}

/**
	A modal dialog that requires an explicit decision.
	Escape and backdrop clicks do not dismiss it. Use `AlertDialogContent`
	with the standard dialog parts, including `DialogTrigger`, `DialogHeader`,
	and `DialogClose`.
**/
class AlertDialog extends Dialog {}

/** Alert dialog panel that closes only through explicit controls. **/
class AlertDialogContent extends DialogContent {
	override function dismissible():Bool
		return false;
}
