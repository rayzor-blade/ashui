package ashui.components;

import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.ui.Component;
import ashui.ui.Ref;

typedef InputProps = {
	> ashui.ui.Input.InputProps,
	/** Small, medium (default), or large sizing for all field parts (e8a1b50). **/
	?size:Size,
	/**
		Adds a password visibility button. Uses a supplied `reveal` signal,
		or creates local reveal state when none is supplied.
	**/
	?revealable:Bool
}

/**
	A themed input with the core input behavior, validation, and form support.

	Accepts all built-in input props and adds `.ui-input`. Checkbox, radio,
	and range types use `.ui-checkbox`, `.ui-radio`, and `.ui-slider`; use
	`Checkbox`, `RadioGroup`, or `Slider` for their composed layouts.
	`revealable` passwords include an eye button that preserves field focus.
	`InputIcon` children add leading or trailing SVG icons (27e0124).

	CSS: `.ui-input` with `:hover`, `:focus`, `:disabled`, and `:user-invalid`,
	`.ui-input-reveal`, and `.ui-input-icon[data-side]`. Variables:
	`--ui-input-bg`, `-border`, `-radius`, `-height`, and `-padding`.
**/
class Input extends Component<InputProps> {
	function render():Element {
		Library.use();
		var type = props.type == null ? "text" : props.type.toLowerCase();
		var parts = children == null ? [] : children;
		var field:Null<ashui.ui.Input> = null;
		if (type == "password" && props.revealable == true) {
			var shown = switch (props.reveal : ashui.layout.IntoReactive.ReactiveType<Bool>) {
				case null: Signal.make(false);
				case Bound(s): s;
				case Const(on): Signal.make(on);
				case _: Signal.make(false);
			}
			props.reveal = shown;
			var toggle = new Ref<Button>();
			parts = parts.concat([
				<button ref={toggle} type="button" variant={Ghost} size={Icon} class="ui-input-reveal" disabled={props.disabled}
					onClick={_ -> {
						shown.set(!shown.get());
						if (field != null)
							field.focus();
					}}>
					<if {shown.get()}>
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
							<path d="M3 3l18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 5.1A9.8 9.8 0 0 1 12 5c5 0 9 4.5 10 7a13 13 0 0 1-3 4.2M6.6 6.6C4.4 8 2.8 10.1 2 12c1 2.5 5 7 10 7a9.6 9.6 0 0 0 5.4-1.6" />
						</svg>
					<else>
						<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
							<path d="M2 12c1-2.5 5-7 10-7s9 4.5 10 7c-1 2.5-5 7-10 7S3 14.5 2 12z" />
							<circle cx="12" cy="12" r="3" />
						</svg>
					</if>
				</button>
			]);
			var built = new ashui.ui.Input(props, parts);
			field = built;
			var identity = ashui.css.Identity.of(toggle.get().tree, toggle.get().node.id);
			identity.bindAttribute("aria-label", ashui.reactive.Computed.make(() -> shown.get() ? "Hide password" : "Show password"));
			identity.bindAttribute("aria-pressed", ashui.reactive.Computed.make(() -> shown.get() ? "true" : "false"));
			return decorate(built, "ui-input");
		}
		var el = new ashui.ui.Input(props, parts);
		var cls = switch type {
			case "checkbox": "ui-checkbox";
			case "radio": "ui-radio";
			case "range": "ui-slider";
			case _: "ui-input";
		}
		return decorate(el, cls);
	}

	/** Places leading icons before the native text clip while preserving the input node and focus (27e0124). **/
	function decorate(el:ashui.ui.Input, cls:String):Element {
		ashui.css.Identity.of(el.tree, el.node.id).addClasses([cls]).setAttribute("data-size", props.size == null ? Size.Md : props.size);
		if (cls == "ui-input") {
			var leading:Null<Array<haxe.Int64>> = null;
			for (child in children) if (Std.isOfType(child, InputIcon) && (cast child : InputIcon).props.side != Trailing) {
				if (leading == null) leading = [];
				leading.push(child.node.id);
			}
			if (leading != null) {
				var rest = el.tree.children(el.node.id).filter(id -> leading.indexOf(id) < 0);
				el.tree.replaceChildren(el.node.id, leading.concat(rest));
			}
		}
		return el;
	}
}

/** Position of a decorative icon relative to the editable text. **/
enum abstract InputIconSide(String) to String {
	var Leading = "leading";
	var Trailing = "trailing";
}

/**
	An SVG inside an Input, before its text by default; `side={Trailing}`
	places it after. CSS sizes and centers it with the input's `Size`.
	It passes pointer hits to the field and adds no keyboard focus stop.
	Use a Button child for an action such as clearing the value.
	CSS: `.ui-input-icon[data-side]`, `--ui-input-icon-size`, `-gap`, `-color`
	(git-bug 27e0124).
**/
class InputIcon extends Component<{?side:InputIconSide}> {
	function render():Element {
		var icon = Library.part("ui-input-icon", "span", ["side" => (props.side == null ? Leading : props.side : String)], children);
		ashui.css.Identity.of(icon.tree, icon.node.id).setAttribute("aria-hidden", "true");
		return icon;
	}
}
