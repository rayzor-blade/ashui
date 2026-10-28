package ashui.ui;

import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;

typedef FormProps = {
	/** Receives named control values after a valid submission, or any submission with `novalidate`. **/
	?onSubmit:FormData->Void,

	/** Runs after reset restores the initial control values. **/
	?onReset:Void->Void,

	/** Skips constraint validation on submission. **/
	?novalidate:Bool,
	/** Set to `dialog` to close the containing dialog after a valid submission. **/
	?method:String,

	?id:String,
	?name:String
}

/** Named control values collected during form submission, in document order. **/
class FormData {
	/** Name/value entries in document order. Names may repeat. **/
	public final entries:Array<{name:String, value:String}> = [];

	public function new() {}

	/** Returns the first value for a name, or null when absent. **/
	public function get(name:String):Null<String> {
		for (e in entries)
			if (e.name == name)
				return e.value;
		return null;
	}

	/** Returns every value for a name, such as a group of checkboxes. **/
	public function getAll(name:String):Array<String>
		return [for (e in entries) if (e.name == name) e.value];
}

/**
	A group of controls submitted together, written as `<form>` in HXX.

	Submit with a submit button or Enter in a text or number input. Buttons
	inside a form default to `type="submit"`; use `button` or `reset` for
	other actions. Submission validates controls unless `novalidate` is set.
	Invalid forms mark controls touched, expose `:user-invalid`, and focus
	the first invalid control. Valid forms pass named values to `onSubmit`.
	A reset button restores the initial values.
**/
class Form extends Component<FormProps> {
	static final registry = new ashui.layout.Registry<Form>();

	@:noCompletion public static function near(tree:LayoutTree, id:haxe.Int64):Null<Form>
		return registry.near(tree, id);

	function render():Element {
		var box = new Div({tag: "form", id: props.id}, children);
		registry.add(box.tree, box.node.id, this);
		if (props.name != null)
			Identity.of(box.tree, box.node.id).setAttribute("name", props.name);
		if (props.method != null)
			Identity.of(box.tree, box.node.id).setAttribute("method", props.method);
		var tree = box.tree, id = box.node.id;
		var interaction = Interaction.of(box.node);
		interaction.onClick(e -> {
			if (e.defaultPrevented)
				return;
			// The button the click is on, if any, between the target and the form.
			var path = [e.target.id].concat(tree.ancestors(e.target.id));
			for (n in path) {
				if (n == id)
					break;
				var identity = Identity.of(tree, n);
				if (identity.types.indexOf("form") >= 0)
					return;
				if (identity != null && identity.types.indexOf("button") >= 0) {
					switch identity.attribute("type") {
						case "reset": reset();
						case "button":
						case _: requestSubmit(identity.node);
					}
					return;
				}
			}
		});
		interaction.onKeyDown(e -> switch e.key {
			case Named(Enter):
				if (e.defaultPrevented)
					return;
				var input = Input.at(tree, e.target.id);
				if (input != null && input.submitsOnEnter()) {
					e.preventDefault();
					requestSubmit(defaultSubmitter());
				}
			case _:
		});
		return box;
	}

	/** Handles Enter by activating the first submit button in document order. **/
	@:allow(ashui.ui.Input)
	function defaultSubmitter():Null<Node> {
		function find(id:haxe.Int64):Null<Node> {
			for (child in tree.children(id)) {
				var identity = Identity.of(tree, child);
				if (identity.types.indexOf("form") >= 0)
					continue;
				if (identity.types.indexOf("button") >= 0
					&& identity.attribute("type") != "button"
					&& identity.attribute("type") != "reset")
					return identity.node;
				var found = find(child);
				if (found != null)
					return found;
			}
			return null;
		}
		return find(node.id);
	}

	/** Returns input, text area, and select controls in document order. **/
	function controls():Array<FormControl> {
		var found:Array<FormControl> = [];
		var tree = node.tree;
		function walk(n:haxe.Int64) {
			for (c in tree.children(n)) {
				if (Identity.of(tree, c).types.indexOf("form") >= 0)
					continue;
				var control = controlAt(c);
				if (control != null) {
					found.push(control);
					continue;
				}
				walk(c);
			}
		}
		walk(node.id);
		return found;
	}

	function controlAt(id:haxe.Int64):Null<FormControl> {
		var control:Null<FormControl> = Input.at(tree, id);
		if (control == null)
			control = TextArea.at(id);
		if (control == null)
			control = Select.at(id);
		return control;
	}

	/** Returns whether every control is valid. Calls `onInvalid` on each invalid control. **/
	public function checkValidity():Bool {
		var valid = true;
		for (c in controls())
			if (!c.checkValidity())
				valid = false;
		return valid;
	}

	/**
		Checks validity and calls `onInvalid` on invalid controls. On failure, marks
		controls touched and focuses the first invalid control, as submission does.
	**/
	public function reportValidity():Bool {
		var all = controls();
		var invalid = all.filter(c -> !c.checkValidity());
		if (invalid.length == 0)
			return true;
		for (c in all)
			c.touch();
		invalid[0].focus();
		return false;
	}

	/** Submits as a submit button would, validating controls unless `novalidate` is set. **/
	public function requestSubmit(?submitter:Node):Void {
		if (submitter != null && submitter.tree != tree)
			throw "requestSubmit needs a submit button belonging to this form";
		var button = submitter == null ? null : Identity.of(tree, submitter.id);
		if (button != null) {
			if (button.types.indexOf("button") < 0
				|| button.attribute("type") == "button"
				|| button.attribute("type") == "reset"
				|| tree.ancestors(submitter.id).indexOf(node.id) < 0)
				throw "requestSubmit needs a submit button belonging to this form";
			var interaction = Interaction.byId(tree, submitter.id);
			if (interaction != null && interaction.disabled.get())
				return;
		}
		if (props.novalidate != true && !reportValidity())
			return;
		var data = new FormData();
		function gather(id:haxe.Int64) {
			for (child in tree.children(id)) {
				if (Identity.of(tree, child).types.indexOf("form") >= 0)
					continue;
				if (submitter != null && child == submitter.id && button.attribute("name") != null)
					data.entries.push({name: button.attribute("name"), value: button.attribute("value") == null ? "" : button.attribute("value")});
				var control = controlAt(child);
				if (control == null)
					gather(child)
				else {
					var name = control.name(), value = control.formValue();
					if (name != null && value != null)
						data.entries.push({name: name, value: value});
				}
			}
		}
		gather(node.id);
		if (props.onSubmit != null)
			props.onSubmit(data);
		if (props.method != null && StringTools.trim(props.method).toLowerCase() == "dialog") {
			var dialog = Dialog.near(tree, node.id);
			if (dialog != null)
				dialog.close(button == null ? null : button.attribute("value") == null ? "" : button.attribute("value"));
		}
	}

	/** Restores the initial control values and clears touched state. **/
	public function reset():Void {
		for (c in controls())
			c.reset();
		if (props.onReset != null)
			props.onReset();
	}
}
