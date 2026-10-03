package ashui.style;

/** What `tw`'s variant classes read inside the values they make. **/
class Variant {
	/**
		A spacing token's pixels from the installed theme; read in a computed,
		follows it. Reads only, so it is safe inside a computed, which may not
		make signals or computeds.
	**/
	public static function space(token:ashui.theme.SpacingToken):Float {
		var theme = ashui.theme.ThemeState.tryGet();
		if (theme == null)
			return ashui.theme.SpacingTokens.defaults().get(token);
		theme.revision.get();
		return theme.spacingValue(token);
	}

	/** Whether the installed theme is in its dark scheme; read in a computed, follows it. **/
	public static function dark():Bool {
		var theme = ashui.theme.ThemeState.tryGet();
		if (theme == null)
			return false;
		theme.revision.get();
		return theme.scheme() == Dark;
	}
}
