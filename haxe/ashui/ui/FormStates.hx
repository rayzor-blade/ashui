package ashui.ui;

import ashui.input.Interaction;
import ashui.reactive.Signal;
import ashui.reactive.Watch;

/** The form states CSS reads of a control, kept as its value and constraints make them. **/
class FormStates {
	/**
		Keeps `i`'s `:required` and `:optional`, and its `:valid`,
		`:invalid`, `:user-valid` and `:user-invalid` as `problem` and
		`touched` say: the user ones once the user has changed it.
	**/
	public static function keep(i:Interaction, required:Bool, problem:Void->Null<String>, touched:Signal<Bool>):Void {
		i.formState("required").set(required);
		i.formState("optional").set(!required);
		new Watch(() -> {
			var bad = problem() != null;
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

	/** Why text is too long or, once the user has edited it, too short, as a browser says it; null when neither. **/
	public static function lengthProblem(text:String, minlength:Null<Int>, maxlength:Null<Int>, touched:Bool):Null<String> {
		if (minlength != null && text.length < minlength && touched)
			return 'Please lengthen this text to $minlength characters or more.';
		if (maxlength != null && text.length > maxlength)
			return 'Please shorten this text to $maxlength characters or less.';
		return null;
	}
}
