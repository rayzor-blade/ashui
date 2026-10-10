package ashui.debugger;

/** The debugger's views and their stylesheet, on top of ashui.components. **/
class Library {
	static var used = false;

	public static function use():Void {
		if (used)
			return;
		used = true;
		ashui.components.Library.use();
		ashui.css.Css.useLibrary("ashui-debugger", ashui.css.CompiledCss.file("../../../css/debugger.css"));
	}
}
