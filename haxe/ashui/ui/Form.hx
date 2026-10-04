package ashui.ui;

import ashui.css.Identity;
import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.LayoutTree;

typedef FormProps = {
	/** Called with what the form submits, when it is submitted and valid (or `novalidate`). **/
	?onSubmit:FormData->Void,

	/** Called after a reset puts each control's first value back. **/
	?onReset:Void->Void,

	/** Submits without checking its controls' constraints. **/
	?novalidate:Bool,

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
	function render():Element {
		var box = new Div({tag: "form", id: props.id}, children);
		if (props.name != null)
			Identity.of(box.tree, box.node.id).setAttribute("name", props.name);
		var tree = box.tree, id = box.node.id;
		var interaction = Interaction.of(box.node);
		interaction.onClick(e -> {
			// The button the click is on, if any, between the target and the form.
			var at:Null<haxe.Int64> = e.target.id;
			var path = [e.target.id].concat(tree.ancestors(e.target.id));
			for (n in path) {
				if (n == id)
					break;
				var identity = Identity.of(tree, n);
				if (identity != null && identity.types.indexOf("button") >= 0) {
					switch identity.attribute("type") {
						case "reset": reset();
						case "button":
						case _: requestSubmit();
					}
					return;
				}
			}
		});
		interaction.onKeyDown(e -> switch e.key {
			case Named(Enter):
				var input = Input.at(tree, e.target.id);
				if (input != null && input.submitsOnEnter()) {
					e.preventDefault();
					requestSubmit();
				}
			case _:
		});
		return box;
	}

	/** The inputs and selects in it, in document order. **/
	function controls():{inputs:Array<Input>, all:Array<{name:Null<String>, value:Void->Null<String>}>} {
		var inputs = [], all = [];
		var tree = node.tree;
		function walk(n:haxe.Int64) {
			for (c in tree.children(n)) {
				var input = Input.at(tree, c);
				if (input != null) {
					inputs.push(input);
					all.push({name: input.name(), value: input.formValue});
					continue;
				}
				var select = Select.at(c);
				if (select != null) {
					all.push({name: select.name(), value: () -> select.value.get()});
					continue;
				}
				walk(c);
			}
		}
		walk(node.id);
		return {inputs: inputs, all: all};
	}

	/** Whether every control in it is valid now. **/
	public function checkValidity():Bool
		return Lambda.foreach(controls().inputs, i -> i.checkValidity());

	/** Submits it, as its submit button does: checked first unless `novalidate`. **/
	public function requestSubmit():Void {
		var c = controls();
		if (props.novalidate != true) {
			var invalid = c.inputs.filter(i -> !i.checkValidity());
			if (invalid.length > 0) {
				for (i in c.inputs)
					i.touch();
				invalid[0].focus();
				return;
			}
		}
		var data = new FormData();
		for (control in c.all) {
			var v = control.value();
			if (control.name != null && v != null)
				data.entries.push({name: control.name, value: v});
		}
		if (props.onSubmit != null)
			props.onSubmit(data);
	}

	/** Puts each control's first value back, untouched, as its reset button does. **/
	public function reset():Void {
		for (i in controls().inputs)
			i.reset();
		if (props.onReset != null)
			props.onReset();
	}
}
