package ashui.core.render;

import ashui.types.ObjectFit;
import ashui.types.PixelSurface;
import gpu.GpuBindGroup;
import gpu.GpuBindings;
import gpu.GpuDevice;
import gpu.GpuExtent3D;
import gpu.GpuOrigin3D;
import gpu.GpuPipeline;
import gpu.GpuTexelCopyBufferLayout;
import gpu.GpuTexelCopyTextureInfo;
import gpu.GpuTexture;
import gpu.GpuTextureDescriptor;
import gpu.GpuTextureView;
import gpu.GpuTextureViewDescriptor;
import haxe.io.Bytes;

/**
	A `PixelSurface` on the GPU: a texture made once at its size, to which
	each frame uploads only the rectangle that changed since the last one,
	and the quad that draws it inside a canvas.
**/
class SurfaceTexture {
	public final surface:PixelSurface;
	final infoBytes = Bytes.alloc(48);
	var reader:Null<ashui.types.SurfaceReader> = null;
	var device:Null<GpuDevice> = null;
	var texture:Null<GpuTexture> = null;
	var view:Null<GpuTextureView> = null;
	var info:Null<GpuTexture> = null;
	var infoView:Null<GpuTextureView> = null;
	var group:Null<GpuBindGroup> = null;
	var pipeline:Null<GpuPipeline> = null;
	var disposed = false;

	/** Bytes sent to the GPU, for a test to see that an unchanged surface sends none. **/
	public var uploaded(default, null) = 0;

	public function new(surface:PixelSurface)
		this.surface = surface;

	/** Whether the next `paint` has something new to send. **/
	public function stale():Bool
		return reader == null || reader.pending();

	/** Draws the surface in the canvas's box, or in the `w` by `h` rectangle at `(x, y)` of it when `w` is not negative. **/
	public function paint(frame:CanvasFrame, fit:ObjectFit, x = 0.0, y = 0.0, w = -1.0, h = -1.0):Void {
		if (disposed || frame.width <= 0 || frame.height <= 0)
			return;
		var boxW = w < 0 ? frame.width : w, boxH = w < 0 ? frame.height : h;
		if (boxW <= 0 || boxH <= 0)
			return;
		if (device != frame.device) {
			releaseGpu();
			device = frame.device;
		}
		if (texture == null) {
			var size = new GpuExtent3D(surface.width);
			size.height(surface.height);
			texture = frame.device.texture(new GpuTextureDescriptor(size, Rgba8unorm, GpuFlags.TEXTURE_COPY_DST | GpuFlags.TEXTURE_BINDING));
			view = texture.createView(new GpuTextureViewDescriptor());
			info = frame.device.texture(new GpuTextureDescriptor(new GpuExtent3D(3), Rgba32float, GpuFlags.TEXTURE_COPY_DST | GpuFlags.TEXTURE_BINDING));
			infoView = info.createView(new GpuTextureViewDescriptor());
			if (reader != null)
				reader.dispose();
			reader = surface.reader();
		}
		var rect = reader.take();
		if (rect != null)
			upload(frame, rect[0], rect[1], rect[2], rect[3]);
		geometry(boxW, boxH, fit, x, y);
		frame.device.queue().writeTexture(info, infoBytes, 3, 1, 48);
		var pass = frame.bind(SurfaceShader.WGSL);
		if (group == null || pipeline != pass.pipeline) {
			if (group != null)
				group.destroy();
			var bindings = new GpuBindings();
			bindings.texture(view);
			bindings.sampler(frame.imageSampler);
			bindings.texture(infoView);
			group = frame.device.bindGroup(pass.pipeline, SurfaceShader.TEXTURE_canvasSurface_GROUP, bindings);
			bindings.destroy();
			pipeline = pass.pipeline;
		}
		frame.encoder.renderSetBindGroup(SurfaceShader.TEXTURE_canvasSurface_GROUP, group);
		frame.encoder.renderDrawRange(6, 1, 0, frame.record);
	}

	function upload(frame:CanvasFrame, x:Int, y:Int, w:Int, h:Int):Void {
		var origin = new GpuOrigin3D();
		origin.x(x);
		origin.y(y);
		var destination = new GpuTexelCopyTextureInfo(texture);
		destination.origin(origin);
		var layout = new GpuTexelCopyBufferLayout();
		layout.offset(haxe.Int64.ofInt((y * surface.width + x) * 4));
		layout.bytesPerRow(surface.width * 4);
		layout.rowsPerImage(h);
		var extent = new GpuExtent3D(w);
		extent.height(h);
		frame.device.queue().writeTextureWith(destination, surface.pixels, layout, extent);
		uploaded += w * h * 4;
	}

	/** Where the surface lands in a `w` by `h` box under `fit`, and which part of it shows. **/
	function geometry(w:Float, h:Float, fit:ObjectFit, ox:Float, oy:Float):Void {
		var sw = surface.width, sh = surface.height;
		var x = 0.0, y = 0.0, dw = w, dh = h, u = 0.0, v = 0.0, uw = 1.0, vh = 1.0;
		if (fit != Fill && fit != Tile) {
			var contain = Math.min(w / sw, h / sh);
			var scale = switch fit {
				case Cover: Math.max(w / sw, h / sh);
				case Contain: contain;
				case ScaleDown: Math.min(1, contain);
				default: 1.0;
			}
			var shownW = sw * scale, shownH = sh * scale;
			dw = Math.min(w, shownW);
			dh = Math.min(h, shownH);
			uw = dw / shownW;
			vh = dh / shownH;
			u = (1 - uw) / 2;
			v = (1 - vh) / 2;
			x = (w - dw) / 2;
			y = (h - dh) / 2;
		}
		var values = [ox + x, oy + y, dw, dh, u, v, uw, vh, 0.0, 0, 0, 0];
		for (i in 0...values.length)
			infoBytes.setFloat(i * 4, values[i]);
	}

	public function dispose():Void {
		if (disposed)
			return;
		disposed = true;
		releaseGpu();
	}

	function releaseGpu():Void {
		if (reader != null) {
			reader.dispose();
			reader = null;
		}
		if (group != null) {
			group.destroy();
			group = null;
		}
		if (view != null) {
			view.destroy();
			view = null;
		}
		if (infoView != null) {
			infoView.destroy();
			infoView = null;
		}
		if (texture != null) {
			texture.destroy();
			texture = null;
		}
		if (info != null) {
			info.destroy();
			info = null;
		}
		pipeline = null;
	}
}
