package ashui.core.render;

/**
	A glyph of text: its quad samples the glyph's rect in a glyph atlas, a
	texture the text engine packs rasterized glyphs into. Ordinary glyphs
	come from `atlas`, one coverage byte per pixel, tinted with the text's
	colour; colour glyphs such as emoji come from `colorAtlas` as they are.

	A record's `gradient` row holds the glyph's rect in its atlas in pixels,
	so a grown atlas keeps every rect valid; `typeInfo.y` is 1 for a colour
	glyph. Glyphs are rasterized at the size they cover on screen, so a
	texel maps to about one pixel and linear filtering does not blur them.
	Ported from the text branch of Blinc's `sdf_core.wgsl`.
**/
class TextShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var atlas : Sampler2D;
		@param var colorAtlas : Sampler2D;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;
		/** Where the fragment is in the glyph's quad, 0 to 1. **/
		var uv : Vec2;

		function vertex() {
			var b = primitive.bounds;
			uv = quadCorner(vertexID);
			pixel = placed(b.xy, primitive.affine, uv * b.zw);
			output.position = pixelToClip(pixel, viewport);
		}

		function fragment() {
			var local = uv * primitive.bounds.zw;
			var aa = halfPixel(local);
			var clip = clipCoverage(pixel, primitive.clipBounds, primitive.clipRadius, primitive.typeInfo.z, primitive.typeInfo.w)
				* localClipCoverage(local, primitive.shadow, primitive.shadowColor, primitive.typeInfo.z, primitive.typeInfo.w, aa)
				* fadeCoverage(pixel, primitive.fadeBounds, primitive.fade);
			if (clip < 0.001)
				discard;
			var rect = primitive.gradient;
			var result = vec4(0., 0., 0., 0.);
			if (primitive.typeInfo.y > 0.5) {
				var size = textureSize(colorAtlas);
				result = textureLod(colorAtlas, mix(rect.xy, rect.zw, uv) / size, 0.);
				result.a *= primitive.color.a;
			} else {
				var size = textureSize(atlas);
				var coverage = textureLod(atlas, mix(rect.xy, rect.zw, uv) / size, 0.).r;
				// Lifts thin strokes, which linear coverage renders too light against gamma-space blending.
				result = vec4(primitive.color.rgb, primitive.color.a * pow(coverage, 0.7));
			}
			output.color = vec4(result.rgb, result.a * clip);
		}
	};
}
