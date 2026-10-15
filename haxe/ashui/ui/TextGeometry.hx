package ashui.ui;

import ashui.ui.TextEditing.CaretStop;

/**
	Geometry supplied by a virtual text view (e53597f). Indices remain in the
	original string; lines are display rows, so folded lines need no nodes.
	The shared TextEditing engine still owns selection, clipboard and IME.
**/
interface TextGeometry {
	public var lineHeight(default, null):Float;
	public var lines(default, null):Int;
	public function prepare(text:String):Void;
	public function stopAt(index:Int):CaretStop;
	public function indexAt(x:Float, line:Int):Int;
	public function lineWidth(line:Int):Float;
	public function step(index:Int, forward:Bool):Int;
	public function lineEdge(index:Int, end:Bool):Int;
}
