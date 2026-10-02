package ashui.core;

/**
	Strings as they cross to Rust: NUL-terminated UTF-8. A HashLink `String`
	holds UTF-16, so its `bytes` cannot be passed as they are.
**/
class Utf8 {
	public static inline function encode(s:String):hl.Bytes {
		return s == null ? null : @:privateAccess s.toUtf8();
	}

	public static inline function decode(b:hl.Bytes):String {
		return b == null ? null : @:privateAccess String.fromUTF8(b);
	}
}
