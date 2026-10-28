package ashui.ui;

import ashui.ui.FormStates.ValidityState;

/**
	Shared form behavior implemented by `Input`, `TextArea`, and `Select`.
	Defines submitted values, validation, focus, and reset.
**/
interface FormControl {
	/** Returns the form field name, or null when unnamed. **/
	function name():Null<String>;

	/** Returns the value to submit, or null to omit the control. **/
	function formValue():Null<String>;

	/** Returns whether the value is valid. Calls `onInvalid` when invalid. **/
	function checkValidity():Bool;

	/** Checks validity. An invalid control is marked touched and focused. **/
	function reportValidity():Bool;

	/** Returns the current constraint flags, following HTML `ValidityState`. **/
	function validity():ValidityState;

	/** Returns the validation message, or an empty string when valid. **/
	function validationMessage():String;

	/**
		Sets a custom validation error, such as a password mismatch.
		An empty string clears the custom error; other constraints still apply.
	**/
	function setCustomValidity(message:String):Void;

	/** Marks the control touched so user-validity styles can appear. **/
	function touch():Void;

	/** Restores the initial value and clears touched state. **/
	function reset():Void;

	/** Moves focus to this control. **/
	function focus():Void;
}
