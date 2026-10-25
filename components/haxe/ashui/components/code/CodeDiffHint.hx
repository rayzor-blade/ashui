package ashui.components.code;

/** A short inline annotation on a changed source line; line numbers start at zero. */
typedef CodeDiffHint = {
	/** "original" or "modified"; inline layout preserves the source side. */
	final side:String;

	final line:Int;
	final text:String;
	final ?detail:String;
}
