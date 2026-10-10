package ashui.components;

import ashui.layout.Element;
import ashui.reactive.Signal;
import ashui.ui.Component;
import ashui.ui.Ref;

typedef InputProps = {
	> ashui.ui.Input.InputProps,
	/**
		A password's: a button inside the field shows its value and hides it
		again. Its state is `reveal` when that is a signal, a signal of its
		own otherwise.
	**/
	?revealable:Bool
}

/**
	A text field in the library's look: the built-in `<input>`, its
	constraints, validity and forms as they are, with the class `ui-input`.
	It takes every prop the built-in does. A checkbox, radio or range typed
	here gets the class of the library's own (`ui-checkbox`, `ui-radio`,
	`ui-slider`); `Checkbox`, `RadioGroup` and `Slider` lay those out with
	their labels. A `revealable` password has an eye button inside it that
	shows and hides its value, keeping focus in the field. CSS: `.ui-input`
	(`:hover`, `:focus`, `:disabled`, `:user-invalid`), `.ui-input-reveal`;
	`--ui-input-bg`, `-border`, `-radius`, `-height`, `-padding`.
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
						<svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
							<path d="M3 3l18 18M10.6 10.6a2 2 0 0 0 2.8 2.8M9.9 5.1A9.8 9.8 0 0 1 12 5c5 0 9 4.5 10 7a13 13 0 0 1-3 4.2M6.6 6.6C4.4 8 2.8 10.1 2 12c1 2.5 5 7 10 7a9.6 9.6 0 0 0 5.4-1.6" />
						</svg>
					<else>
						<svg viewBox="0 0 24 24" width={16} height={16} fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">
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
			ashui.css.Identity.of(built.tree, built.node.id).addClasses(["ui-input"]);
			return built;
		}
		var el = new ashui.ui.Input(props, parts);
		var cls = switch type {
			case "checkbox": "ui-checkbox";
			case "radio": "ui-radio";
			case "range": "ui-slider";
			case _: "ui-input";
		}
		ashui.css.Identity.of(el.tree, el.node.id).addClasses([cls]);
		return el;
	}
}
