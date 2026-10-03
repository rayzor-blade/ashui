package ashui.style;

/** What `tw`'s variant classes read inside the values they make. **/
class Variant {
	/** Whether the installed theme is in its dark scheme; read in a computed, follows it. **/
	public static function dark():Bool {
		var theme = ashui.theme.ThemeState.tryGet();
		if (theme == null)
			return false;
		theme.revision.get();
		return theme.scheme() == Dark;
	}
}
