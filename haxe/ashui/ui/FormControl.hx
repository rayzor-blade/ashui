package ashui.ui;

import ashui.ui.FormStates.ValidityState;

/**
	A control a `Form` gathers: what it submits, whether its constraints
	hold, and how a reset puts it back. `Input`, `TextArea` and `Select` are.
**/
interface FormControl {
	/** Its name, which a form submits its value under; null for none. **/
	function name():Null<String>;

	/** What a form submits for it; null for nothing. **/
	function formValue():Null<String>;

	/** Whether it is valid now; when it is not, its `onInvalid` is called, as HTML fires `invalid`. **/
	function checkValidity():Bool;

	/** As `checkValidity`; when it is invalid, it is also marked touched, so `:user-invalid` shows, and takes focus. **/
	function reportValidity():Bool;

	/** Which of its constraints it breaks now, as HTML's `ValidityState` says. **/
	function validity():ValidityState;

	/** Why it is invalid, as a browser would say it; empty when it is valid. **/
	function validationMessage():String;

	/**
		Makes it invalid with `message`, as HTML's `setCustomValidity` does:
		for a rule the built-in constraints cannot say, such as two
		passwords matching. An empty message makes it valid again.
	**/
	function setCustomValidity(message:String):Void;

	/** Marks it as the user having changed it, as submitting its form does, so `:user-invalid` shows. **/
	function touch():Void;

	/** Puts back the value it was built with, untouched, as a form's reset does. **/
	function reset():Void;

	/** Takes focus, as a form does to the first control that is invalid. **/
	function focus():Void;
}
