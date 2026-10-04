package ashui.core.render;

/**
	A canvas's drawing: triangles from the canvas's own data texture, read
	by vertex index, each vertex two texels: its position in layout units,
	its coverage and the texel where its paint starts; then its distances
	inside up to four edges of its shape, in pixels, which cover the pixels
	just inside an edge by how far inside they are. A paint is eight
	texels: its kind (0 solid, 1 linear, 2 radial, 3 image), stop count and
	opacity; its geometry, in layout units; up to four stop offsets; and
	the stops' colours. An image's paint is its opacity, then the map from
	a pixel to where in the image it is, 0 to 1 across, as two rows of
	an affine, then the image's rect in `canvasImages`, the image atlas.
	A paint's first texel ends with the texel its clip starts at, 0 for
	none; a clip is four texels, its kind and the clip outside it, and
	its shape (`CanvasPainter.encodeClip`), up to `CLIP_DEPTH` deep.
	Gradients are mixed premultiplied, as CSS mixes them. Drawn with the canvas's record as its instance, it is clipped as
	the canvas is (`canvasClip`).
**/
class PathShader implements UiShader {
	/** Texels to a row of the canvas's data texture. **/
	public static inline var ROW_TEXELS = 2048;

	/** Texels to a paint. **/
	public static inline var PAINT_TEXELS = 8;

	/** Texels to a clip. **/
	public static inline var CLIP_TEXELS = 4;

	/** Clips, one inside another, a draw is kept inside; those further out are not applied. **/
	public static inline var CLIP_DEPTH = 8;

	/** Texels to a vertex. **/
	public static inline var VERTEX_TEXELS = 2;

	static var SRC = {
		@:import ashui.core.render.Sdf;

		// The atlas first: its sampler is used and the canvas's is not, so bindings made in order run images, sampler, canvas.
		@param var canvasImages : Sampler2D;
		@param var canvas : Sampler2D;

		var output : { position : Vec4, color : Vec4 };
		var pixel : Vec2;
		var coverage : Float;
		var paint : Float;
		var edges : Vec4;

		function canvasTexel(t : Int) : Vec4 {
			return canvas.fetch(ivec2(t % 2048, t / 2048));
		}

		function vertex() {
			var v = canvasTexel(vertexID * 2);
			pixel = v.xy;
			coverage = v.z;
			paint = v.w;
			edges = canvasTexel(vertexID * 2 + 1);
			output.position = pixelToClip(pixel, viewport);
		}

		function premultiplied(c : Vec4) : Vec4 {
			return vec4(c.rgb * c.a, c.a);
		}

		// How much of this pixel the clip at texel `t` keeps: inside by half a pixel or more, all of it.
		function drawClipCoverage(t : Int) : Float {
			var head = canvasTexel(t);
			var row0 = canvasTexel(t + 1);
			var row1 = canvasTexel(t + 2);
			var shape = canvasTexel(t + 3);
			var p = vec2(dot(row0.xyz, vec3(pixel, 1.)), dot(row1.xyz, vec3(pixel, 1.))) - shape.xy;
			var d = 0.;
			if (head.x > 1.5) {
				// Ellipse: exact for a circle, close for the rest.
				var k0 = length(p / shape.zw);
				var k1 = length(p / (shape.zw * shape.zw));
				d = k1 > 0.000001 ? k0 * (k0 - 1.) / k1 : -min(shape.z, shape.w);
			} else {
				var q = abs(p) - shape.zw + vec2(head.z, head.z);
				d = length(max(q, vec2(0., 0.))) + min(max(q.x, q.y), 0.) - head.z;
			}
			return head.x > 0.5 ? clamp(0.5 - d * head.w, 0., 1.) : 0.;
		}

		function fragment() {
			var at = int(paint + 0.5);
			var head = canvasTexel(at);
			var color = canvasTexel(at + 3);
			if (head.x > 2.5) {
				var row0 = canvasTexel(at + 1);
				var row1 = canvasTexel(at + 2);
				var rect = canvasTexel(at + 3);
				var st = clamp(vec2(dot(row0.xyz, vec3(pixel, 1.)), dot(row1.xyz, vec3(pixel, 1.))), vec2(0., 0.), vec2(1., 1.));
				// Kept half a texel inside its rect, so filtering does not reach its neighbours in the atlas.
				var where = clamp(mix(rect.xy, rect.zw, st), rect.xy + vec2(0.5, 0.5), rect.zw - vec2(0.5, 0.5));
				color = textureLod(canvasImages, where / textureSize(canvasImages), 0.);
			} else if (head.x > 0.5) {
				var geo = canvasTexel(at + 1);
				var offsets = canvasTexel(at + 2);
				var t = 0.;
				if (head.x < 1.5) {
					var d = geo.zw - geo.xy;
					t = dot(pixel - geo.xy, d) / max(dot(d, d), 0.000001);
				} else {
					t = length(pixel - geo.xy) / max(geo.z, 0.000001);
				}
				t = clamp(t, 0., 1.);
				var p0 = premultiplied(canvasTexel(at + 3));
				var p1 = premultiplied(canvasTexel(at + 4));
				var p2 = premultiplied(canvasTexel(at + 5));
				var p3 = premultiplied(canvasTexel(at + 6));
				var mixed = p0;
				if (head.y > 1.5 && t > offsets.x)
					mixed = mix(p0, p1, clamp((t - offsets.x) / max(offsets.y - offsets.x, 0.000001), 0., 1.));
				if (head.y > 2.5 && t > offsets.y)
					mixed = mix(p1, p2, clamp((t - offsets.y) / max(offsets.z - offsets.y, 0.000001), 0., 1.));
				if (head.y > 3.5 && t > offsets.z)
					mixed = mix(p2, p3, clamp((t - offsets.z) / max(offsets.w - offsets.z, 0.000001), 0., 1.));
				color = mixed.a > 0.000001 ? vec4(mixed.rgb / mixed.a, mixed.a) : vec4(0., 0., 0., 0.);
			}
			// Inside each edge by half a pixel or more, fully covered; on the edge, half.
			var inside = clamp(edges + vec4(0.5, 0.5, 0.5, 0.5), vec4(0., 0., 0., 0.), vec4(1., 1., 1., 1.));
			var covered = coverage * inside.x * inside.y * inside.z * inside.w;
			var clip = int(head.w + 0.5);
			var depth = 0;
			while (depth < 8) {
				if (clip > 0) {
					covered *= drawClipCoverage(clip);
					clip = int(canvasTexel(clip).y + 0.5);
				}
				depth++;
			}
			output.color = vec4(color.rgb, color.a * head.z * covered * canvasClip(pixel));
		}
	};
}
