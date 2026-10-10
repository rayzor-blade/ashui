package ashui.ui;

import ashui.input.Interaction;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

/** Which constraint a control breaks, as the field of HTML's `ValidityState` that says so. **/
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

/** One broken constraint: which, and what a browser would say of it. **/
typedef ValidityProblem = {
	flag:ValidityFlag,
	message:String
}

/** What a control's constraints say of it, as HTML's `ValidityState` does: each broken one, and whether none is. **/
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
	A control's validity: the constraints its own `check` finds broken, and
	a message a script sets with `setCustomValidity`, which makes the
	control invalid while it is not empty and is the message it reports
	first, as a browser's is.
**/
class Validity {
	/** A script's message; empty for none. **/
	public final custom = Signal.make("");

	final check:Void->Array<ValidityProblem>;

	public function new(check:Void->Array<ValidityProblem>)
		this.check = check;

	/** Every constraint broken now, a script's message first. **/
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

	/** Why it is invalid, the first reason as a browser says it; empty when it is valid. **/
	public function message():String {
		var found = problems();
		return found.length == 0 ? "" : found[0].message;
	}

	/** Sets the script's message; empty clears it. **/
	public function setCustom(message:String):Void
		custom.set(message == null ? "" : message);
}

/** The form states CSS reads of a control, kept as its value and constraints make them. **/
class FormStates {
	/**
		Keeps `i`'s `:required` and `:optional`, and its `:valid`,
		`:invalid`, `:user-valid` and `:user-invalid` as `validity` and
		`touched` say: the user ones once the user has changed it.
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

	/** Text too long or, once the user has edited it, too short, as a browser says it; empty when neither. **/
	public static function lengthProblems(text:String, minlength:Null<Int>, maxlength:Null<Int>, touched:Bool):Array<ValidityProblem> {
		var out:Array<ValidityProblem> = [];
		if (minlength != null && text.length < minlength && touched)
			out.push({flag: TooShort, message: 'Please lengthen this text to $minlength characters or more.'});
		if (maxlength != null && text.length > maxlength)
			out.push({flag: TooLong, message: 'Please shorten this text to $maxlength characters or less.'});
		return out;
	}

	/**
		Checks `control` as a form or a script does: true when it is valid,
		and otherwise calls `onInvalid`, as HTML fires `invalid`.
	**/
	public static function check(control:FormControl, onInvalid:Null<Void->Void>):Bool {
		if (control.validity().valid)
			return true;
		if (onInvalid != null)
			onInvalid();
		return false;
	}
}
