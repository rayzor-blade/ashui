package ashui.theme;

/** A font and the ones to fall back to, in order. **/
@:structInit
final class FontFamily {
	public final name:String;
	public final fallbacks:Array<String>;

	public function new(name:String, fallbacks:Array<String>) {
		this.name = name;
		this.fallbacks = fallbacks;
	}

	public static function systemSans():FontFamily {
		return new FontFamily("system-ui", ["-apple-system", "BlinkMacSystemFont", "Segoe UI", "Roboto", "Oxygen", "Ubuntu", "sans-serif"]);
	}

	public static function systemMono():FontFamily {
		return new FontFamily("ui-monospace", ["SFMono-Regular", "SF Mono", "Menlo", "Consolas", "Liberation Mono", "monospace"]);
	}

	public static function systemSerif():FontFamily {
		return new FontFamily("ui-serif", ["Georgia", "Cambria", "Times New Roman", "Times", "serif"]);
	}
}
