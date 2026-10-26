import ashui.input.Keyboard;
import ashui.input.Events.KeyEvent;
import ashui.reactive.Signal;
import ashui.theme.ThemeState;
import ashui.theme.themes.DefaultTheme;
import ashui.ui.TextEditing;

class KeyboardPlatformTest {
	static function check(ok:Bool, what:String):Void if (!ok) throw what;
	static function main():Void {
		ThemeState.init(DefaultTheme.bundle(), Dark);
		var original = Keyboard.platform;
		for (platform in ["Mac","Windows","Linux"]) {
			Keyboard.platform = platform;
			var mac = platform == "Mac";
			check(Keyboard.isMac() == mac,"application keyboard platform override");
			var editing = new TextEditing(Signal.make("first\nsecond"),true,0);
			editing.metrics = new SampleGeometry();
			editing.caret.set(7); editing.anchor.set(7);
			var event = @:privateAccess new KeyEvent(null,Named(ArrowRight),Unidentified(Unidentified),Standard,false,window.Modifiers.State(false,!mac,false,mac,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown,Unknown));
			editing.key(event);
			check(editing.caret.get() == 12,"line navigation uses the application keyboard platform");
		}
		Keyboard.platform = null;
		check(Keyboard.isMac() == (Sys.systemName() == "Mac"),"native platform default");
		Keyboard.platform = original;
		Sys.println("keyboard platform: explicit Mac/Control conventions and native defaults passed");
	}
}

private class SampleGeometry implements ashui.ui.TextGeometry {
	public var lineHeight(default,null) = 1.;
	public var lines(default,null) = 2;
	public function new() {}
	public function prepare(text:String):Void {}
	public function stopAt(index:Int):ashui.ui.TextEditing.CaretStop return {index:index,x:index < 6 ? index : index-6,line:index < 6 ? 0 : 1};
	public function indexAt(x:Float,line:Int):Int return Std.int(x)+(line == 0 ? 0 : 6);
	public function lineWidth(line:Int):Float return line == 0 ? 5 : 6;
	public function step(index:Int,forward:Bool):Int return Std.int(Math.max(0,Math.min(12,index+(forward ? 1 : -1))));
	public function lineEdge(index:Int,end:Bool):Int return index < 6 ? (end ? 5 : 0) : (end ? 12 : 6);
}
