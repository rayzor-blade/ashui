package ashui.core.render;

import ashui.draw3d.BcEncoder;
import ashui.types.Bitmap;
import gpu.GpuDevice;
import gpu.GpuExtent3D;
import gpu.GpuTexelCopyBufferLayout;
import gpu.GpuTexelCopyTextureInfo;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureView;
import gpu.GpuTextureViewDescriptor;
import gpu.TextureFormat;
import haxe.io.Bytes;

/** What a material reads a texture as, which decides how it is stored. **/
enum abstract TextureRole(Int) to Int {
	/** Base or emissive colour: sRGB, BC1, or BC3 where it has alpha. **/
	var Color = 0;

	/** Metallic in blue and roughness in green: BC1. **/
	var Data = 1;

	/** Occlusion in red: BC4. **/
	var Occlusion = 2;

	/** A normal map's x and y in red and green: BC5; the shader works out z. **/
	var Normal = 3;
}

/**
	Meshes' textures on the GPU, shared by every canvas on the one device,
	kept until their bitmap is disposed.

	A texture is uploaded as it is, eight bits a channel with every mip
	level, the first time a material asks for it, so it is drawn at once.
	Where the GPU samples block-compressed textures (BC, on desktop GPUs),
	the `Worker` thread then compresses each level (`BcEncoder`) as its
	role says, one texture after another,
	and the compressed texture takes the uncompressed one's place on the
	main thread: a quarter of its memory for colour, an eighth for
	occlusion. `revision` counts the replacements, and each painter's
	`repaint` is called after them, to draw with the new ones.

	A `gpuOnly` bitmap's pixels are freed once nothing more is made from them.
**/
class MeshTextures {
	/** Counts textures put in place after compression; what bound a stand-in binds them now. **/
	public static var revision(default, null) = 0;

	/** Called on the main thread after textures are replaced. **/
	public static final repaints:Array<Void->Void> = [];

	static final textures = new Map<String, {texture:GpuTexture, view:GpuTextureView}>();
	static var device:Null<GpuDevice> = null;
	static var watchingDisposal = false;

	/** Pixels resampled for an upload, reused from level to level and texture to texture. **/
	static var scratch:Null<Bytes> = null;

	/** Compressions running, by bitmap slot; its pixels are freed when they are done. **/
	static final running = new Map<Int, Int>();

	/** Bitmaps whose pixels go at the end of the frame, nothing more to be made from them. **/
	static final releasing:Array<Bitmap> = [];

	/** Whether to compress at all: a GPU that cannot sample BC, or `-D ashui_no_bc`, leaves textures as they are. **/
	public static var compress = #if ashui_no_bc false #else true #end;

	/** Keys of textures being compressed, not yet on the GPU. **/
	static final pending = new Map<String, Bool>();

	/** `bitmap` on the GPU, as `role` reads it; null while it is being compressed. **/
	public static function get(gpu:GpuDevice, bitmap:Bitmap, role:TextureRole):Null<{texture:GpuTexture, view:GpuTextureView}> {
		var key = '${bitmap.slot}/${(role : Int)}';
		var known = textures.get(key);
		if (known != null || pending.exists(key))
			return known;
		device = gpu;
		watchDisposal();
		var w = bitmap.width, h = bitmap.height;
		var levels = levelCount(w, h);
		// BC blocks are 4×4: a texture whose sides are not a multiple of 4 stays as it is.
		if (compress && w % 4 == 0 && h % 4 == 0 && gpu.supports(TextureCompressionBc)) {
			pending.set(key, true);
			compressLater(key, bitmap, role, levels);
			return null;
		}
		var size = new GpuExtent3D(w);
		size.height(h);
		var descriptor = new GpuTextureDescriptor(size, role == Color ? TextureFormat.Rgba8unormSrgb : TextureFormat.Rgba8unorm,
			GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST);
		descriptor.mipLevelCount(levels);
		var t = gpu.texture(descriptor);
		if (scratch == null || scratch.length < w * h * 4)
			scratch = Bytes.alloc(w * h * 4);
		for (level in 0...levels) {
			var lw = Std.int(Math.max(1, w >> level)), lh = Std.int(Math.max(1, h >> level));
			resample(bitmap, lw, lh, scratch);
			write(gpu, t, level, scratch, lw * 4, lw, lh);
		}
		var made = {texture: t, view: t.createView(new GpuTextureViewDescriptor())};
		textures.set(key, made);
		if (bitmap.gpuOnly)
			releasing.push(bitmap);
		return made;
	}

	/** After a frame: frees the pixels of bitmaps nothing more is to be made from. **/
	public static function endFrame():Void {
		for (b in releasing)
			if (!running.exists(b.slot))
				@:privateAccess ashui.core.externs.BitmapNative.blinc_bitmap_release(b.slot);
		releasing.resize(0);
	}

	/** Pixels the worker resamples a level into, reused from level to level and texture to texture: only the worker uses it. **/
	static var workBuffer:Null<Bytes> = null;

	/** Compresses `bitmap`'s levels on the worker, then has them put in place on the main thread. **/
	static function compressLater(key:String, bitmap:Bitmap, role:TextureRole, levels:Int):Void {
		running.set(bitmap.slot, (running.exists(bitmap.slot) ? running.get(bitmap.slot) : 0) + 1);
		var w = bitmap.width, h = bitmap.height;
		ashui.core.Worker.run(() -> {
			if (workBuffer == null || workBuffer.length < w * h * 4)
				workBuffer = Bytes.alloc(w * h * 4);
			var px = workBuffer;
			var out = [];
			var format = TextureFormat.Bc4RUnorm, blockBytes = 8;
			for (level in 0...levels) {
				var lw = Std.int(Math.max(1, w >> level)), lh = Std.int(Math.max(1, h >> level));
				resample(bitmap, lw, lh, px);
				switch role {
					case Color:
						// Alpha is decided by the sharpest level, so every level is the same format.
						if (level == 0)
							format = BcEncoder.opaque(px, lw * lh) ? TextureFormat.Bc1RgbaUnormSrgb : TextureFormat.Bc3RgbaUnormSrgb;
						blockBytes = format == TextureFormat.Bc1RgbaUnormSrgb ? 8 : 16;
						out.push(blockBytes == 8 ? BcEncoder.bc1(px, lw, lh) : BcEncoder.bc3(px, lw, lh));
					case Data:
						format = TextureFormat.Bc1RgbaUnorm;
						out.push(BcEncoder.bc1(px, lw, lh));
					case Occlusion:
						format = TextureFormat.Bc4RUnorm;
						out.push(BcEncoder.bc4(px, lw, lh, 0));
					case Normal:
						format = TextureFormat.Bc5RgUnorm;
						blockBytes = 16;
						out.push(BcEncoder.bc5(px, lw, lh));
				}
			}
			return {key: key, bitmap: bitmap, format: format, blockBytes: blockBytes, levels: out};
		}, job -> upload(job));
	}

	/** On the main thread: a finished compression's texture in place of the uncompressed one. **/
	static function upload(job:{key:String, bitmap:Bitmap, format:TextureFormat, blockBytes:Int, levels:Array<Bytes>}):Void {
		if (device == null)
			return;
		var slot = job.bitmap.slot;
		var left = running.get(slot) - 1;
		if (left > 0) running.set(slot, left) else running.remove(slot);
		// Disposed while it was being compressed: nothing to put in place.
		if (!pending.remove(job.key))
			return;
		var w = job.bitmap.width, h = job.bitmap.height;
		var size = new GpuExtent3D(w);
		size.height(h);
		var descriptor = new GpuTextureDescriptor(size, job.format, GpuFlags.TEXTURE_BINDING | GpuFlags.TEXTURE_COPY_DST);
		descriptor.mipLevelCount(job.levels.length);
		var t = device.texture(descriptor);
		for (level in 0...job.levels.length) {
			// A level smaller than a block is a whole block on the GPU.
			var lw = Std.int(Math.max(1, w >> level)), lh = Std.int(Math.max(1, h >> level));
			var bw = (lw + 3) >> 2, bh = (lh + 3) >> 2;
			write(device, t, level, job.levels[level], bw * job.blockBytes, bw * 4, bh * 4, bh);
		}
		textures.set(job.key, {texture: t, view: t.createView(new GpuTextureViewDescriptor())});
		if (job.bitmap.gpuOnly && !running.exists(slot))
			@:privateAccess ashui.core.externs.BitmapNative.blinc_bitmap_release(slot);
		revision++;
		for (r in repaints.copy())
			r();
	}

	static function watchDisposal():Void {
		if (watchingDisposal)
			return;
		watchingDisposal = true;
		Bitmap.disposing.push(b -> for (role in 0...4) {
			var k = '${b.slot}/$role';
			pending.remove(k);
			var t = textures.get(k);
			if (t != null) {
				t.view.destroy();
				t.texture.destroy();
				textures.remove(k);
			}
		});
	}

	static function levelCount(w:Int, h:Int):Int {
		var levels = 1;
		while ((w >> levels) > 0 || (h >> levels) > 0)
			levels++;
		return levels;
	}

	static inline function resample(bitmap:Bitmap, w:Int, h:Int, out:Bytes):Void
		@:privateAccess ashui.core.externs.BitmapNative.blinc_bitmap_resample(bitmap.slot, w, h, (Fill : ashui.types.Brush.ImageFit), out);

	/** `data` into level `level` of `t`, `width` × `height` texels, rows `bytesPerRow` apart, `rows` of them (texel rows, or block rows). **/
	static function write(gpu:GpuDevice, t:GpuTexture, level:Int, data:Bytes, bytesPerRow:Int, width:Int, height:Int, ?rows:Int):Void {
		var destination = new GpuTexelCopyTextureInfo(t);
		destination.mipLevel(level);
		var layout = new GpuTexelCopyBufferLayout();
		layout.bytesPerRow(bytesPerRow);
		layout.rowsPerImage(rows != null ? rows : height);
		var extent = new GpuExtent3D(width);
		extent.height(height);
		gpu.queue().writeTextureWith(destination, data, layout, extent);
	}
}
