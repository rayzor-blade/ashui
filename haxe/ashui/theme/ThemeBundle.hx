package ashui.theme;

/**
	Groups a theme's light and dark schemes with its CSS stylesheets.
	Installing the bundle queues its stylesheets in registration order.
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

	/** Returns the theme for the requested color scheme. **/
	public function forScheme(scheme:ColorScheme):Theme {
		return scheme == Dark ? dark : light;
	}

	/** Adds a CSS stylesheet and returns this bundle. **/
	public function withCss(css:String):ThemeBundle {
		cssSources.push(css);
		return this;
	}

	/** Loads a CSS stylesheet from `path`. If loading fails, adds a CSS comment describing the error. **/
	public function withCssFile(path:String):ThemeBundle {
		try {
			cssSources.push(ashui.core.Assets.text(path));
		} catch (e:haxe.Exception) {
			cssSources.push('/* ThemeBundle.withCssFile($path) failed: ${e.message} */');
		}
		return this;
	}

	public function toString():String {
		return 'ThemeBundle($name, ${cssSources.length} css sources)';
	}
}
