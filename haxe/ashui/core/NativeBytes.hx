package ashui.core;

/**
	A byte buffer that crosses to the native library. On HashLink it is `hl.Bytes` and every call
	compiles to the same access as before; on Rayzor it is `haxe.io.Bytes`, which the native plugin
	reads and writes in place. Multi-byte values are little-endian.
**/
#if hl
@:forward
abstract NativeBytes(hl.Bytes) from hl.Bytes to hl.Bytes {
	public inline function new(size:Int)
		this = new hl.Bytes(size);

	@:from public static inline function ofBytes(b:haxe.io.Bytes):NativeBytes
		return hl.Bytes.fromBytes(b);
}
#else
/** The 32-bit float type of the native boundary: `Single` where the target has one, `Float` on the interpreter. **/
#if rayzor
private typedef F32 = Single;
#else
private typedef F32 = Float;
#end

abstract NativeBytes(haxe.io.Bytes) from haxe.io.Bytes to haxe.io.Bytes {
	public inline function new(size:Int)
		this = haxe.io.Bytes.alloc(size);

	public inline function getUI8(pos:Int):Int
		return this.get(pos);

	public inline function setUI8(pos:Int, v:Int):Void
		this.set(pos, v);

	public inline function getF32(pos:Int):F32
		return cast this.getFloat(pos);

	public inline function setF32(pos:Int, v:F32):Void
		this.setFloat(pos, v);

	public inline function getI32(pos:Int):Int
		return this.getInt32(pos);

	public inline function setI32(pos:Int, v:Int):Void
		this.setInt32(pos, v);

	/** Copies `len` bytes from `src` at `srcPos` to `pos`. **/
	public inline function blit(pos:Int, src:NativeBytes, srcPos:Int, len:Int):Void
		this.blit(pos, src, srcPos, len);

	/** Compares `len` bytes at `pos` with those of `other` at `otherPos`: 0 when equal, else the difference of the first bytes that differ. **/
	public function compare(pos:Int, other:NativeBytes, otherPos:Int, len:Int):Int {
		var b:haxe.io.Bytes = other;
		for (i in 0...len) {
			var d = this.get(pos + i) - b.get(otherPos + i);
			if (d != 0)
				return d;
		}
		return 0;
	}

	/** The `len` bytes at `pos`, sharing this buffer's storage. **/
	public inline function sub(pos:Int, len:Int):NativeBytes
		return this.sub(pos, len);
}
#end
