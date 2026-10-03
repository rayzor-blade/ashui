package ashui.core;

/**
	Converts strings for the native library, which takes and returns text
	as NUL-terminated UTF-8. A HashLink `String` holds UTF-16, so its
	`bytes` cannot be passed as they are.
**/
class Utf8 {
	/** `s` as NUL-terminated UTF-8; null stays null. **/
	public static inline function encode(s:String):hl.Bytes {
		return s == null ? null : @:privateAccess s.toUtf8();
	}

	/** The string in NUL-terminated UTF-8 `b`; null stays null. **/
	public static inline function decode(b:hl.Bytes):String {
		return b == null ? null : @:privateAccess String.fromUTF8(b);
	}
}
