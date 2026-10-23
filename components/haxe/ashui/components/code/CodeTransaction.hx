package ashui.components.code;

import ashui.components.code.CodeHistory.CodePatch;
import ashui.components.code.CodeHistory.CodeSelection;

/** One local edit, with ordered non-overlapping ranges in the previous text's UTF-16 coordinates. */
typedef CodeTransaction = {
	final before:String;
	final after:String;
	final parts:Array<CodePatch>;
	final selection:CodeSelection;
	final next:CodeSelection;
}

/** Presentation data only; a participant never retains an editor or layout element. */
typedef CodePeer = {
	final id:String;
	final name:String;
	final caret:Int;
	final anchor:Int;
	final color:Int;
}
