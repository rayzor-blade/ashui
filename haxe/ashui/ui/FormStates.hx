package ashui.ui;

import ashui.input.Interaction;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

/** Constraint identifiers matching the fields of HTML `ValidityState`. **/
enum abstract ValidityFlag(String) to String {
	var ValueMissing = "valueMissing";
	var TypeMismatch = "typeMismatch";
	var PatternMismatch = "patternMismatch";
	var TooLong = "tooLong";
	var TooShort = "tooShort";
	var RangeUnderflow = "rangeUnderflow";
	var RangeOverflow = "rangeOverflow";
	var StepMismatch = "stepMismatch";
	var BadInput = "badInput";
	var CustomError = "customError";
}

/** A validation failure and its message. **/
typedef ValidityProblem = {
	flag:ValidityFlag,
	message:String
}

/** Current constraint flags and overall validity, following HTML `ValidityState`. **/
typedef ValidityState = {
	valueMissing:Bool,
	typeMismatch:Bool,
	patternMismatch:Bool,
	tooLong:Bool,
	tooShort:Bool,
	rangeUnderflow:Bool,
	rangeOverflow:Bool,
	stepMismatch:Bool,
	badInput:Bool,
	customError:Bool,
	valid:Bool
}

/**
	Combines built-in validation failures with an application error message.
	A nonempty custom message makes the control invalid and takes priority
	over built-in messages.
**/
class Validity {
	/** Custom validation message. Empty means no custom error. **/
	public final custom = Signal.make("");

	final check:Void->Array<ValidityProblem>;

	public function new(check:Void->Array<ValidityProblem>)
		this.check = check;

	/** Returns all current validation failures, with the custom error first. **/
	public function problems():Array<ValidityProblem> {
		var out = check();
		var message = custom.get();
		if (message != "")
			out.unshift({flag: CustomError, message: message});
		return out;
	}

	public function state():ValidityState {
		var found = problems();
		inline function has(flag:ValidityFlag):Bool
			return Lambda.exists(found, p -> p.flag == flag);
		return {
			valueMissing: has(ValueMissing),
			typeMismatch: has(TypeMismatch),
			patternMismatch: has(PatternMismatch),
			tooLong: has(TooLong),
			tooShort: has(TooShort),
			rangeUnderflow: has(RangeUnderflow),
			rangeOverflow: has(RangeOverflow),
			stepMismatch: has(StepMismatch),
			badInput: has(BadInput),
			customError: has(CustomError),
			valid: found.length == 0
		};
	}

	/** Returns the first validation message, or an empty string when valid. **/
	public function message():String {
		var found = problems();
		return found.length == 0 ? "" : found[0].message;
	}

	/** Sets the custom validation message. Empty clears the custom error. **/
	public function setCustom(message:String):Void
		custom.set(message == null ? "" : message);
}

/** Keeps CSS form states synchronized with validation and user interaction. **/
class FormStates {
	/**
		Updates `:required`, `:optional`, `:valid`, and `:invalid` from the control
		constraints. Applies `:user-valid` and `:user-invalid` once `touched` is true.
	**/
	public static function keep(i:Interaction, required:Bool, validity:Validity, touched:Signal<Bool>):Void {
		i.formState("required").set(required);
		i.formState("optional").set(!required);
		new Watch(() -> {
			var bad = validity.problems().length > 0;
			var user = touched.get();
			[bad, user];
		}, v -> {
			var bad = v[0], user = v[1];
			i.formState("invalid").set(bad);
			i.formState("valid").set(!bad);
			i.formState("user-invalid").set(bad && user);
			i.formState("user-valid").set(!bad && user);
		});
	}

	/** Returns text-length failures. Minimum length applies after user edits; maximum length always applies. **/
	public static function lengthProblems(text:String, minlength:Null<Int>, maxlength:Null<Int>, touched:Bool):Array<ValidityProblem> {
		var out:Array<ValidityProblem> = [];
		if (minlength != null && text.length < minlength && touched)
			out.push({flag: TooShort, message: 'Please lengthen this text to $minlength characters or more.'});
		if (maxlength != null && text.length > maxlength)
			out.push({flag: TooLong, message: 'Please shorten this text to $maxlength characters or less.'});
		return out;
	}

	/** Returns whether a control is valid and calls `onInvalid` on failure. **/
	public static function check(control:FormControl, onInvalid:Null<Void->Void>):Bool {
		if (control.validity().valid)
			return true;
		if (onInvalid != null)
			onInvalid();
		return false;
	}
}
