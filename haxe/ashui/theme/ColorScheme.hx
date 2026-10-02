package ashui.theme;

enum abstract ColorScheme(Int) to Int {
	var Light = 0;
	var Dark = 1;

	/** The other scheme. **/
	public inline function toggle():ColorScheme {
		return (cast this : ColorScheme) == Light ? Dark : Light;
	}
}
