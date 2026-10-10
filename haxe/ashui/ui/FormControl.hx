package ashui.ui;

/**
	A control a `Form` gathers: what it submits, whether its constraints
	hold, and how a reset puts it back. `Input`, `TextArea` and `Select` are.
**/
interface FormControl {
	/** Its name, which a form submits its value under; null for none. **/
	function name():Null<String>;

	/** What a form submits for it; null for nothing. **/
	function formValue():Null<String>;

	/** Whether it is valid now. **/
	function checkValidity():Bool;

	/** Why it is invalid, as a browser would say it; empty when it is valid. **/
	function validationMessage():String;

	/** Marks it as the user having changed it, as submitting its form does, so `:user-invalid` shows. **/
	function touch():Void;

	/** Puts back the value it was built with, untouched, as a form's reset does. **/
	function reset():Void;

	/** Takes focus, as a form does to the first control that is invalid. **/
	function focus():Void;
}
