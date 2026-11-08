package ashui.core;

/**
	Text as it crosses to the native library: NUL-terminated UTF-8 bytes where the library reads bytes (HashLink,
	Caribou), and the string itself on Rayzor, whose plugin takes strings as they are, so none is encoded or
	decoded per call. `Utf8.toNative` and `Utf8.fromNative` convert.
**/
#if ashui_rayzor
typedef NativeText = String;
#else
typedef NativeText = NativeBytes;
#end
