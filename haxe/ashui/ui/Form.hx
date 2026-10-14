package ashui.ui;

import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.LayoutTree;
import ashui.layout.Node;

typedef FormProps = {
	/** Called with what the form submits, when it is submitted and valid (or `novalidate`). **/
	?onSubmit:FormData->Void,

	/** Called after a reset puts each control's first value back. **/
	?onReset:Void->Void,

	/** Submits without checking its controls' constraints. **/
	?novalidate:Bool,
	/** dialog also closes the containing dialog after valid submission. **/
	?method:String,

	?id:String,
	?name:String
}

/** What a form submits: each named control's value, in document order, as HTML's `FormData`. **/
class FormData {
	/** Each name and value, in document order; a name may come more than once. **/
	public final entries:Array<{name:String, value:String}> = [];

	public function new() {}

	/** The first value under `name`, null for none. **/
	public function get(name:String):Null<String> {
		for (e in entries)
			if (e.name == name)
				return e.value;
		return null;
	}

	/** Every value under `name`, as checkboxes of one name give. **/
	public function getAll(name:String):Array<String>
		return [for (e in entries) if (e.name == name) e.value];
}

/**
	HTML's `<form>`, built in: the controls inside it, submitted together.
	A click on a `<button>` in it submits it (a button's type is `submit`
	unless it says `button` or `reset`), as does Enter in a text input or a
	number. Submitting first checks every control's constraints, unless the
	form is `novalidate`: when any is invalid, each is marked touched, so
	`:user-invalid` shows, the first invalid one takes focus, and nothing is
	submitted. Otherwise `onSubmit` gets each named control's value. A
	`reset` button puts every control's first value back.
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

	/** Enter uses the first submit button in tree order, as clicking that button would. **/
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

	/** The controls in it, in document order: inputs, text areas and selects. **/
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

	/** Whether every control in it is valid now; each that is not has its `onInvalid` called. **/
	public function checkValidity():Bool {
		var valid = true;
		for (c in controls())
			if (!c.checkValidity())
				valid = false;
		return valid;
	}

	/**
		As `checkValidity`; when any control is invalid, every control is
		marked touched, so `:user-invalid` shows, and the first invalid one
		takes focus, as a submit that fails does.
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

	/** Submits it, as its submit button does: checked first unless `novalidate`. **/
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

	/** Puts each control's first value back, untouched, as its reset button does. **/
	public function reset():Void {
		for (c in controls())
			c.reset();
		if (props.onReset != null)
			props.onReset();
	}
}
