package ashui.core.render;

/**
	An image in a box: its quad samples the image's rect in the image atlas.
	A mask image, `typeInfo.y` 0, is coverage tinted with the record's
	colour; a colour image, 1, is drawn as it is under the opacity in
	`color2.a`; a tiled one, 2, repeats from the box's top-left in cells
	`color2.xy` layout units in size. The record's `gradient` row is the
	rect, one cell for a tiled image, in atlas pixels.
**/
class ImageShader implements UiShader {
	static var SRC = {
		@:import ashui.core.render.Sdf;

		@param var images : Sampler2D;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;
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
				* fadeCoverage(pixel, primitive.fadeBounds, primitive.fade)
				* shapeCoverage(pixel);
			if (clip < 0.001)
				discard;
			var rect = primitive.gradient;
			var at = mix(rect.xy, rect.zw, uv);
			if (primitive.typeInfo.y > 1.5) {
				// Kept half a texel inside the cell, so filtering does not reach its neighbours in the atlas.
				at = clamp(mix(rect.xy, rect.zw, fract(local / primitive.color2.xy)), rect.xy + vec2(0.5, 0.5), rect.zw - vec2(0.5, 0.5));
			}
			var texel = textureLod(images, at / textureSize(images), 0.);
			var result = vec4(primitive.color.rgb, primitive.color.a * texel.a);
			if (primitive.typeInfo.y > 0.5)
				result = vec4(texel.rgb, texel.a * primitive.color2.a);
			output.color = vec4(result.rgb, result.a * clip);
		}
	};
}
