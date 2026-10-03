package ashui.theme;

/**
	A theme's light and dark schemes, with style sheets that come with it.
	The sheets are queued when the bundle is installed, for the style system
	to take in order.
**/
final class ThemeBundle {
	public final name:String;
	public final light:Theme;
	public final dark:Theme;
	public final cssSources:Array<String> = [];

	public function new(name:String, light:Theme, dark:Theme) {
		this.name = name;
		this.light = light;
		this.dark = dark;
	}

	/** The light or the dark theme. **/
	public function forScheme(scheme:ColorScheme):Theme {
		return scheme == Dark ? dark : light;
	}

	/** Adds a style sheet, as text. **/
	public function withCss(css:String):ThemeBundle {
		cssSources.push(css);
		return this;
	}

	/** Adds the style sheet in `path`; one that cannot be read becomes a CSS comment saying why. **/
	public function withCssFile(path:String):ThemeBundle {
		#if sys
		try {
			cssSources.push(sys.io.File.getContent(path));
		} catch (e:haxe.Exception) {
			cssSources.push('/* ThemeBundle.withCssFile($path) failed: ${e.message} */');
		}
		#else
		cssSources.push('/* ThemeBundle.withCssFile($path) failed: no file system */');
		#end
		return this;
	}

	public function toString():String {
		return 'ThemeBundle($name, ${cssSources.length} css sources)';
	}
}
