package ashui.layout;

/**
	How display-list records lie in the records texture the UI shaders read:
	shared by `DisplayList`, the renderer and `UiFramework`'s shader prelude,
	which runs at compile time, so it depends on nothing.
**/
class RecordLayout {
	/** A record is this many rows of four floats, each a texel of the records texture. **/
	public static inline var RECORD_ROWS = 16;

	/** The records texture's width in texels: whole records to a row, within WebGL2's 2048. **/
	public static inline var ROW_TEXELS = 2048;

	public static inline var RECORDS_PER_ROW = 128;
}
