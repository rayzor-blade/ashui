package ashui.media.render;

import ashui.core.render.CanvasFrame;
import ashui.media.Player;
import ashui.media.VideoFit;
import gpu.GpuBindGroup;
import gpu.GpuBindings;
import gpu.GpuDevice;
import gpu.GpuExtent3D;
import gpu.GpuPipeline;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureView;
import gpu.GpuTextureViewDescriptor;
import gpu.TextureFormat;
import gpu.TextureUsage;
import haxe.Int64;
import haxe.io.Bytes;
import media.VideoFrame;
import media.VideoFrameCopyToOptions;
import media.VideoPixelFormat;

/**
	Uploads each new native frame once, reusing its CPU buffer and GPU textures.
	Native playback supplies BGRA. RGBA/RGBX/BGRX CPU frames are supported too;
	planar buffers belong to hlavi's data API and need a YUV conversion renderer.
**/
class VideoTexture {
	final player:Player;
	final copy = new VideoFrameCopyToOptions();
	final infoBytes = Bytes.alloc(48);
	var pixels:Bytes = null;
	var device:Null<GpuDevice> = null;
	var texture:Null<GpuTexture> = null;
	var view:Null<GpuTextureView> = null;
	var info:Null<GpuTexture> = null;
	var infoView:Null<GpuTextureView> = null;
	var group:Null<GpuBindGroup> = null;
	var pipeline:Null<GpuPipeline> = null;
	var version = -1;
	var width = 0;
	var height = 0;
	var displayWidth = 0;
	var displayHeight = 0;
	var format:VideoPixelFormat = VideoPixelFormat.BGRA;
	var forceOpaque = false;
	var disposed = false;

	public function new(player:Player) this.player = player;

	public function paint(frame:CanvasFrame, fit:VideoFit):Void {
		if (disposed) return;
		if (device != frame.device) {
			releaseGpu();
			device = frame.device;
			version = -1;
		}
		if (version != player.frameVersion.get()) {
			var source = player.currentFrame();
			if (source == null) {
				releaseGpu();
				version = player.frameVersion.get();
				return;
			}
			try upload(frame, source) catch (e:Dynamic) { source.close(); throw e; }
			source.close();
			version = player.frameVersion.get();
		}
		if (texture == null || frame.width <= 0 || frame.height <= 0) return;
		geometry(frame.width, frame.height, fit);
		frame.device.queue().writeTexture(info, infoBytes, 3, 1, 48);
		var pass = frame.bind(VideoShader.WGSL);
		if (group == null || pipeline != pass.pipeline) {
			if (group != null) group.destroy();
			var bindings = new GpuBindings();
			bindings.texture(view);
			bindings.sampler(frame.imageSampler);
			bindings.texture(infoView);
			group = frame.device.bindGroup(pass.pipeline, VideoShader.TEXTURE_canvasVideo_GROUP, bindings);
			bindings.destroy();
			pipeline = pass.pipeline;
		}
		frame.encoder.renderSetBindGroup(VideoShader.TEXTURE_canvasVideo_GROUP, group);
		frame.encoder.renderDrawRange(6, 1, 0, frame.record);
	}

	function upload(frame:CanvasFrame, source:VideoFrame):Void {
		var nextFormat = source.format();
		if (nextFormat != BGRA && nextFormat != RGBA && nextFormat != BGRX && nextFormat != RGBX)
			throw "Video playback rendering requires BGRA, RGBA, BGRX or RGBX frames";
		// The native default copy crops to visibleRect, rather than coded dimensions.
		var w = 0, h = 0;
		switch source.visibleRect() { case Value(_, _, rw, rh): w = Int64.toInt(rw); h = Int64.toInt(rh); }
		var required = Int64.toInt(source.allocationSize(copy));
		if (pixels == null || pixels.length != required) pixels = Bytes.alloc(required);
		var pending = source.copyTo(pixels, copy);
		// hlavi's current CPU backend resolves this future after the copy, synchronously.
		if (!pending.isReady()) throw "Asynchronous video copies require a staging queue";
		var layouts = pending.await();
		var stride = 0;
		try {
			if (layouts.count() != 1 || Int64.toInt(layouts.offset(0)) != 0) throw "Unexpected packed video layout";
			stride = Int64.toInt(layouts.stride(0));
		} catch (e:Dynamic) { layouts.close(); throw e; }
		layouts.close();
		if (texture == null || width != w || height != h || format != nextFormat) {
			releaseGpu();
			width = w; height = h; format = nextFormat;
			var size = new GpuExtent3D(w);
			size.height(h);
			var bgra = nextFormat == BGRA || nextFormat == BGRX;
			texture = frame.device.texture(new GpuTextureDescriptor(size, bgra ? Bgra8unorm : Rgba8unorm, TextureUsage.COPY_DST | TextureUsage.TEXTURE_BINDING));
			view = texture.createView(new GpuTextureViewDescriptor());
			info = frame.device.texture(new GpuTextureDescriptor(new GpuExtent3D(3), Rgba32float, TextureUsage.COPY_DST | TextureUsage.TEXTURE_BINDING));
			infoView = info.createView(new GpuTextureViewDescriptor());
		}
		displayWidth = Int64.toInt(source.displayWidth());
		displayHeight = Int64.toInt(source.displayHeight());
		forceOpaque = nextFormat == BGRX || nextFormat == RGBX;
		frame.device.queue().writeTexture(texture, pixels, w, h, stride);
	}

	function geometry(w:Float, h:Float, fit:VideoFit):Void {
		var x = 0.0, y = 0.0, dw = w, dh = h;
		var u = 0.0, v = 0.0, uw = 1.0, vh = 1.0;
		var aspect = displayWidth / displayHeight;
		if (fit == Contain) {
			if (w / h > aspect) dw = h * aspect; else dh = w / aspect;
			x = (w - dw) / 2; y = (h - dh) / 2;
		} else if (fit == Cover) {
			if (w / h > aspect) vh = aspect * h / w; else uw = w / (h * aspect);
			u = (1 - uw) / 2; v = (1 - vh) / 2;
		}
		var values = [x, y, dw, dh, u, v, uw, vh, forceOpaque ? 1.0 : 0.0, 0, 0, 0];
		for (i in 0...values.length) infoBytes.setFloat(i * 4, values[i]);
	}

	public function dispose():Void {
		if (disposed) return;
		disposed = true;
		releaseGpu();
		pixels = null;
	}

	function releaseGpu():Void {
		if (group != null) { group.destroy(); group = null; }
		if (view != null) { view.destroy(); view = null; }
		if (infoView != null) { infoView.destroy(); infoView = null; }
		if (texture != null) { texture.destroy(); texture = null; }
		if (info != null) { info.destroy(); info = null; }
		pipeline = null;
	}
}
