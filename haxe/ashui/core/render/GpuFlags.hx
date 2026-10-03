package ashui.core.render;

/**
	The GPU's usage and write flags, the same names on each backend: hlwgpu
	has them as constants and caribou-gpu (`-D ashui_caribou`) as
	functions, so the renderer reads them here.
**/
class GpuFlags {
	public static var BUFFER_UNIFORM(get, never):Int;
	public static var BUFFER_COPY_DST(get, never):Int;
	public static var BUFFER_MAP_READ(get, never):Int;
	public static var TEXTURE_COPY_SRC(get, never):Int;
	public static var TEXTURE_COPY_DST(get, never):Int;
	public static var TEXTURE_BINDING(get, never):Int;
	public static var TEXTURE_RENDER_ATTACHMENT(get, never):Int;
	public static var COLOR_WRITE_ALL(get, never):Int;

	#if ashui_caribou
	static inline function get_BUFFER_UNIFORM():Int return gpu.BufferUsage.UNIFORM();
	static inline function get_BUFFER_COPY_DST():Int return gpu.BufferUsage.COPY_DST();
	static inline function get_BUFFER_MAP_READ():Int return gpu.BufferUsage.MAP_READ();
	static inline function get_TEXTURE_COPY_SRC():Int return gpu.TextureUsage.COPY_SRC();
	static inline function get_TEXTURE_COPY_DST():Int return gpu.TextureUsage.COPY_DST();
	static inline function get_TEXTURE_BINDING():Int return gpu.TextureUsage.TEXTURE_BINDING();
	static inline function get_TEXTURE_RENDER_ATTACHMENT():Int return gpu.TextureUsage.RENDER_ATTACHMENT();
	static inline function get_COLOR_WRITE_ALL():Int return gpu.ColorWrite.ALL();
	#else
	static inline function get_BUFFER_UNIFORM():Int return gpu.BufferUsage.UNIFORM;
	static inline function get_BUFFER_COPY_DST():Int return gpu.BufferUsage.COPY_DST;
	static inline function get_BUFFER_MAP_READ():Int return gpu.BufferUsage.MAP_READ;
	static inline function get_TEXTURE_COPY_SRC():Int return gpu.TextureUsage.COPY_SRC;
	static inline function get_TEXTURE_COPY_DST():Int return gpu.TextureUsage.COPY_DST;
	static inline function get_TEXTURE_BINDING():Int return gpu.TextureUsage.TEXTURE_BINDING;
	static inline function get_TEXTURE_RENDER_ATTACHMENT():Int return gpu.TextureUsage.RENDER_ATTACHMENT;
	static inline function get_COLOR_WRITE_ALL():Int return gpu.ColorWrite.ALL;
	#end
}
