package ashui.components;

import ashui.input.Interaction;
import ashui.layout.Element;
import ashui.layout.IntoReactive;
import ashui.reactive.Computed;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Component;

typedef InputOtpProps = {
	/** Number of character slots. Defaults to 6. **/
	?length:Int,
	/** Entered code. A supplied signal is read and updated; a constant sets the initial value. **/
	?value:IntoReactive<String>,
	/** Number of slots before a separator dash. Defaults to no separator. **/
	?separator:Int,
	/** Restricts input to digits. Defaults to true. **/
	?digits:Bool,
	?disabled:IntoReactive<Bool>,
	/** Receives the code when all slots are filled. **/
	?onComplete:String->Void,
	/** Small, medium (default), or large slots and spacing (e8a1b50). **/
	?size:Size,
	?id:String
}

/**
	A one-time-code input with one character per visible slot.
	A transparent text field handles typing, paste, and Backspace; slots
	display its value and highlight the active position while focused.
	CSS: `.ui-input-otp`, `.ui-input-otp-slot` with `[data-filled]` and
	`[data-active]`, `.ui-input-otp-separator`, and `.ui-input-otp-field`.
**/
class InputOtp extends Component<InputOtpProps> {
	public var value(default, null):Signal<String>;

	function render():Element {
		value = switch props.value {
			case null: Signal.make("");
			case Const(v): Signal.make(v);
			case Bound(s): s;
			case Derived(c):
				var s = Signal.make(c.get());
				new Watch(() -> c.get(), v -> s.set(v));
				s;
		}
		var length = props.length == null ? 6 : props.length;
		var digits = props.digits != false;
		var v = value;
		// What the field holds, kept to the slots' number and, for digits, to digits.
		var typed = Signal.make(v.get());
		new Watch(() -> typed.get(), t -> {
			var kept = digits ? ~/[^0-9]/g.replace(t, "") : t;
			if (kept.length > length)
				kept = kept.substr(0, length);
			if (kept != t)
				typed.set(kept);
			if (kept != v.get()) {
				v.set(kept);
				if (kept.length == length && props.onComplete != null)
					props.onComplete(kept);
			}
		});
		new Watch(() -> v.get(), x -> if (x != typed.get()) typed.set(x));
		var field = new ashui.ui.Input({value: typed, maxlength: length, disabled: props.disabled, id: props.id});
		ashui.css.Identity.of(field.tree, field.node.id).addClasses(["ui-input-otp-field"]);
		var focused = Interaction.of(field.node).focused;
		var slots:Array<Element> = [];
		for (i in 0...length) {
			if (props.separator != null && i == props.separator)
				slots.push(Library.part("ui-input-otp-separator", null, null, [new ashui.ui.Text("–")]));
			var at = i;
			slots.push(Library.part("ui-input-otp-slot", null, [
				"filled" => Computed.make(() -> (v.get().length > at ? "" : null : Null<String>)),
				"active" => Computed.make(() -> (focused.get() && (v.get().length == at || (at == length - 1 && v.get().length == length)) ? "" : null : Null<String>))
			], [new ashui.ui.Text(Computed.make(() -> v.get().length > at ? v.get().charAt(at) : ""))]));
		}
		var row = Library.part("ui-input-otp-slots", null, null, slots);
		return Library.part("ui-input-otp", null, ["size" => (props.size == null ? Size.Md : props.size : String)], [row, field]);
	}
}
