package ashui.core;

/**
	Converts strings for the native library, which takes and returns text
	as NUL-terminated UTF-8. A HashLink `String` holds UTF-16, so its
	`bytes` cannot be passed as they are.
**/
class Utf8 {
	#if hl
	/** `s` as NUL-terminated UTF-8; null stays null. **/
	public static inline function encode(s:String):NativeBytes {
		return s == null ? null : @:privateAccess s.toUtf8();
	}

	/** The string in NUL-terminated UTF-8 `b`; null stays null. **/
	public static inline function decode(b:NativeBytes):String {
		return b == null ? null : @:privateAccess String.fromUTF8(b);
	}
	#else
	/** `s` as NUL-terminated UTF-8; null stays null. **/
	public static function encode(s:String):NativeBytes {
		if (s == null)
			return null;
		var utf8 = haxe.io.Bytes.ofString(s);
		var out = haxe.io.Bytes.alloc(utf8.length + 1);
		out.blit(0, utf8, 0, utf8.length);
		return out;
	}

	/** The string in NUL-terminated UTF-8 `b`; null stays null. **/
	public static function decode(b:NativeBytes):String {
		if (b == null)
			return null;
		var bytes:haxe.io.Bytes = b;
		var n = 0;
		while (n < bytes.length && bytes.get(n) != 0)
			n++;
		return bytes.getString(0, n);
	}
	#end
}
