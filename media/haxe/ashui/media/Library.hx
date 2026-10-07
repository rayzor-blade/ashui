package ashui.media;

/** Optional media components. Add media/haxe and hlavi/haxe to the build. **/
class Library {
	static var used = false;

	public static function use():Void {
		if (used) return;
		used = true;
		ashui.components.Library.use();
		ashui.css.Css.useLibrary("ashui-media", ashui.css.CompiledCss.file("../../../css/media.css"));
	}
}
