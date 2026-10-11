import ashui.css.Identity;
import ashui.input.Focus;
import ashui.input.Interaction;
import ashui.input.Keyboard;
import ashui.input.Pointer;
import ashui.layout.LayoutTree;
import ashui.layout.Node;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.ui.Dialog;
import ashui.ui.Div;
import ashui.ui.Form;
import ashui.ui.Input;
import ashui.ui.Ref;
import ashui.ui.TopLayer;

/** User dismissal and form submission must share the existing dialog lifecycle. **/
class DialogForms {
	static final scopes = new haxe.ds.ObjectMap<LayoutTree, Void->Void>();
	static function build(tree:LayoutTree, render:Void->Div):Div return Owner.root(tree, dispose -> {
		scopes.set(tree, dispose);
		return render();
	});
	static function check(name:String, ok:Bool, ?detail:Dynamic) {
		if (!ok) {
			if (detail != null) Sys.println(detail);
			throw name;
		}
		Sys.println('ok   $name');
	}
	static function key(name:window.Key, code:window.KeyCode):window.KeyEvent
		return Input(Code(code), name, None, Standard, Pressed, false, Unavailable);
	static function settle(tree:LayoutTree, root:Div) {
		tree.flush();
		tree.computeLayout(root.node, 400, 300);
		tree.flush();
		tree.computeLayout(root.node, 400, 300);
	}
	static function click(tree:LayoutTree, node:Node) {
		var bounds = tree.getBounds(node);
		Pointer.move(tree, bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);
		Pointer.press(tree);
		Pointer.release(tree);
	}
	static function backdrop(tree:LayoutTree) {
		Pointer.move(tree, 2, 2);
		Pointer.press(tree);
		Pointer.release(tree);
	}
	static function finish(tree:LayoutTree, root:Div) {
		var dispose = scopes.get(tree);
		scopes.remove(tree);
		dispose();
		ashui.animation.AnimationScheduler.main.tick(1);
		tree.flush();
		tree.dispose();
	}
	static function main() {
		ashui.theme.ThemeState.init(ashui.theme.themes.DefaultTheme.bundle(), Light);
		for (policy in ["any", "closerequest", "none"]) {
			var tree = new LayoutTree(), open = Signal.make(false);
			var dialog:Dialog = null, outside:Div = null;
			var dialogRef = new Ref<Dialog>(), outsideRef = new Ref<Div>();
			var cancelled = 0, closed = 0, refuse = true, consumeKey = false;
			var root:Div = build(tree, () -> <div width={400} height={300}>
				<button ref={outsideRef}>Outside</button>
				<dialog ref={dialogRef} open={open} closedby={policy} onClose={() -> closed++}
					onCancel={event -> { check("cancel targets its dialog", event.target == dialog); cancelled++; if (refuse) event.preventDefault(); }}>
					<div width={220} height={120}><button onKeyDown={e -> {if (consumeKey) e.preventDefault();}}>Inside</button></div>
				</dialog>
			</div>);
			dialog = dialogRef.get();
			outside = outsideRef.get();
			settle(tree, root);
			Focus.set(Interaction.of(outside.node), true);
			open.set(true);
			settle(tree, root);
			check(policy + " registers the modal panel without sending an initial close", Dialog.near(tree, dialog.panel.node.id) == dialog && closed == 0);
			Keyboard.input(tree, key(Named(Escape), Escape));
			settle(tree, root);
			check(policy + " Escape obeys policy and cancelled requests retain focus", open.get() && cancelled == (policy == "none" ? 0 : 1)
				&& Focus.of(tree) != null && Focus.of(tree).node.id != outside.node.id);
			var before = cancelled;
			backdrop(tree);
			settle(tree, root);
			check(policy + " backdrop uses the same cancel policy and preserves modal focus", open.get() && cancelled == before + (policy == "any" ? 1 : 0)
				&& Focus.of(tree) != null && Focus.of(tree).node.id != outside.node.id);
			refuse = false;
			consumeKey = true;
			Keyboard.input(tree, key(Named(Escape), Escape));
			settle(tree, root);
			check(policy + " a consumed Escape does not dismiss an inner control", open.get() && cancelled == before + (policy == "any" ? 1 : 0));
			consumeKey = false;
			Keyboard.input(tree, key(Named(Escape), Escape));
			settle(tree, root);
			check(policy + " accepted Escape closes once and restores focus", policy == "none" ? open.get() && closed == 0
				: !open.get() && closed == 1 && Focus.of(tree).node.id == outside.node.id);
			if (open.get()) dialog.requestClose("explicit");
			settle(tree, root);
			check(policy + " explicit requestClose can close even with closedby none", !open.get() && closed == 1);
			var oldCancelled = cancelled;
			var closingLayer = tree.children(root.node.id)[tree.children(root.node.id).length - 1];
			open.set(true);
			settle(tree, root);
			check(policy + " reopening detaches the panel from its closing holder", tree.children(tree.children(closingLayer)[1]).length == 0);
			ashui.animation.AnimationScheduler.main.tick(1);
			settle(tree, root);
			check(policy + " finishing the old close leaves the reopened panel intact", open.get() && tree.getBounds(dialog.panel.node).width > 0);
			dialog.close("saved");
			dialog.close("ignored");
			settle(tree, root);
			check(policy + " close bypasses cancel and preserves a single return value", dialog.returnValue == "saved" && cancelled == oldCancelled && closed == 2);
			var panel = dialog.panel.node.id;
			dialog.remove();
			check(policy + " removing the dialog releases its registry entry", Dialog.near(tree, panel) == null);
			finish(tree, root);
		}

		var tree = new LayoutTree(), open = Signal.make(false), text = Signal.make("");
		var dialog:Dialog = null, form:Form = null, input:Input = null, save:Div = null, stop:Div = null;
		var dialogRef = new Ref<Dialog>(), formRef = new Ref<Form>(), inputRef = new Ref<Input>();
		var saveRef = new Ref<Div>(), stopRef = new Ref<Div>();
		var submits = 0, cancels = 0, closes = 0, preventClick = false;
		var data:ashui.ui.Form.FormData = null;
		var root:Div = build(tree, () -> <div width={400} height={300}>
			<dialog ref={dialogRef} open={open} closedby="none" onCancel={_ -> cancels++} onClose={() -> closes++}>
				<form ref={formRef} method="dialog" onSubmit={values -> {submits++; data = values;}} class="flex-col gap-2" width={220}>
					<input ref={inputRef} name="profile" required value={text} />
					<button ref={saveRef} name="action" value="saved" onClick={e -> {if (preventClick) e.preventDefault();}}>Save</button>
					<input name="after" value="last" />
					<button ref={stopRef} type="button" value="ignored">Keep open</button>
					<button type="reset">Reset</button>
				</form>
			</dialog>
		</div>);
		dialog = dialogRef.get();
		form = formRef.get();
		input = inputRef.get();
		save = saveRef.get();
		stop = stopRef.get();
		settle(tree, root);
		open.set(true);
		settle(tree, root);
		click(tree, save.node);
		settle(tree, root);
		check("invalid method=dialog submission leaves the dialog open and focuses its invalid control", open.get() && submits == 0 && closes == 0
			&& Focus.of(tree).node.id == input.node.id);
		text.set("Alex");
		settle(tree, root);
		preventClick = true;
		click(tree, save.node);
		settle(tree, root);
		check("preventDefault on a submit button suppresses dialog submission", open.get() && submits == 0);
		preventClick = false;
		click(tree, stop.node);
		settle(tree, root);
		check("type=button does not submit or close its dialog", open.get() && submits == 0);
		click(tree, save.node);
		settle(tree, root);
		check("a valid submit returns its button value and closes without cancel", !open.get() && dialog.returnValue == "saved" && submits == 1 && closes == 1 && cancels == 0);
		check("FormData includes only the chosen button in document order", data.entries.length == 3
			&& data.entries[0].name == "profile" && data.entries[1].name == "action" && data.entries[1].value == "saved" && data.entries[2].name == "after");
		open.set(true);
		settle(tree, root);
		Focus.set(Interaction.of(input.node), true);
		Keyboard.input(tree, key(Named(Enter), Enter));
		settle(tree, root);
		check("Enter submits the first button and returns its value", !open.get() && dialog.returnValue == "saved" && submits == 2 && closes == 2);
		open.set(true);
		settle(tree, root);
		form.requestSubmit();
		settle(tree, root);
		check("submission without a button preserves returnValue", !open.get() && dialog.returnValue == "saved" && data.get("action") == null);
		var invalidButton = false;
		try form.requestSubmit(stop.node) catch (_:String) invalidButton = true;
		check("requestSubmit rejects a non-submit button", invalidButton);
		finish(tree, root);

		tree = new LayoutTree();
		var modeless:Dialog = null, componentButton:ashui.components.Button = null;
		var modelessRef = new Ref<Dialog>(), componentButtonRef = new Ref<ashui.components.Button>();
		var localClosed = 0;
		root = build(tree, () -> <div width={400} height={300}>
			<dialog ref={modelessRef} modal={false} open={true} closedby="none" onClose={() -> localClosed++}>
				<form method="dialog" novalidate><input required />
					<ashui.components.button ref={componentButtonRef} name="action" value="done">Done</ashui.components.button>
				</form>
			</dialog>
		</div>);
		modeless = modelessRef.get();
		componentButton = componentButtonRef.get();
		settle(tree, root);
		ashui.animation.AnimationScheduler.main.tick(1);
		settle(tree, root);
		click(tree, componentButton.node);
		settle(tree, root);
		check("the existing Button submits modeless dialogs with novalidate", !modeless.opened.get() && modeless.returnValue == "done" && localClosed == 1,
			{open: modeless.opened.get(), value: modeless.returnValue, closes: localClosed, bounds: tree.getBounds(componentButton.node),
				form: Form.near(tree, componentButton.node.id) != null, dialog: Dialog.near(tree, componentButton.node.id) == modeless,
				panel: tree.getBounds(modeless.panel.node), marked: Identity.of(tree, modeless.panel.node.id).attribute("open"),
				hits: [for (hit in tree.hitTest(52, 75)) Identity.of(tree, hit.id).types]});
		modeless.close();
		settle(tree, root);
		check("a closed modeless dialog does not send duplicate close callbacks", localClosed == 1);
		finish(tree, root);

		tree = new LayoutTree();
		var pendingDialog = new Ref<Dialog>();
		var pendingOpen = Signal.make(true), pendingCloses = 0;
		var pending = LayoutTree.flushHooks.length;
		root = build(tree, () -> <div><dialog ref={pendingDialog} open={pendingOpen} onClose={() -> pendingCloses++}><button>Pending</button></dialog></div>);
		check("an initially open modal waits for its first layout", LayoutTree.flushHooks.length == pending + 1);
		pendingDialog.get().remove();
		check("removing an unlaid-out modal releases its retry hook", LayoutTree.flushHooks.length == pending);
		check("closing before first layout updates open and sends one close callback", !pendingOpen.get() && pendingCloses == 1);
		finish(tree, root);

		tree = new LayoutTree();
		var empty = new Ref<Dialog>();
		root = build(tree, () -> <div width={400} height={300}><dialog ref={empty} open={true}><p>No controls</p></dialog></div>);
		settle(tree, root);
		check("a modal without controls focuses its panel", Focus.of(tree) != null && Focus.of(tree).node.id == empty.get().panel.node.id);
		Keyboard.input(tree, key(Named(Escape), Escape));
		settle(tree, root);
		check("Escape also dismisses a modal without controls", !empty.get().opened.get());
		finish(tree, root);
	}
}
