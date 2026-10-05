package ashui.shaders;

/**
	A mesh draw's own settings, for `@:import ashui.shaders.MeshDraw;`:
	read from the `draws` buffer, `ROWS` rows of four floats a draw, the
	draw's instance index naming its own. The rows are the model matrix's
	columns, the normal matrix's (the first two's `w` the texture offset),
	the base colour and alpha (linear), then metallic, roughness, normal
	scale and occlusion strength, the emissive colour (linear, times its
	strength) and the alpha cut-off, then whether it has a normal texture,
	whether it is unlit (1, or 2 unlit and out of the fog), its alpha mode (0 opaque, 1 mask, 2 blend, 3 a
	blended one's solid half) and its opacity, then the texture transform's
	2×2 matrix by rows, then the previous frame's model matrix columns, for
	motion blur. The importing shader declares
	`@param var draws : StorageBuffer<Vec4>;` itself, as HXSL imports
	bring functions and not parameters.
**/
class MeshDraw implements #if ashui_caribou caribou.hxsl.Shader #else hlwgpu.hxsl.Shader #end {
	public static inline var ROWS = 16;

	static var SRC = {
		@param var draws : StorageBuffer<Vec4>;

		/** A point (`w` 1) or direction (`w` 0) of draw `i`'s mesh, placed in the scene. **/
		function modelToWorld(i : Int, p : Vec4) : Vec4 {
			var d = i * 16;
			return draws[d] * p.x + draws[d + 1] * p.y + draws[d + 2] * p.z + draws[d + 3] * p.w;
		}

		/** A normal of draw `i`'s mesh, turned as its surface is in the scene; not of unit length. **/
		function normalToWorld(i : Int, n : Vec3) : Vec3 {
			var d = i * 16;
			return (draws[d + 4] * n.x + draws[d + 5] * n.y + draws[d + 6] * n.z).xyz;
		}

		function drawBaseColor(i : Int) : Vec4 {
			return draws[i * 16 + 7];
		}

		/** Metallic, roughness, normal scale, occlusion strength. **/
		function drawSurface(i : Int) : Vec4 {
			return draws[i * 16 + 8];
		}

		/** The emissive colour, and the alpha cut-off. **/
		function drawEmissive(i : Int) : Vec4 {
			return draws[i * 16 + 9];
		}

		/** A texture coordinate of draw `i`'s mesh where its material's texture transform puts it. **/
		function drawTexcoord(i : Int, uv : Vec2) : Vec2 {
			var d = i * 16;
			var m = draws[d + 11];
			return vec2(m.x * uv.x + m.y * uv.y + draws[d + 4].w, m.z * uv.x + m.w * uv.y + draws[d + 5].w);
		}

		/** A point (`w` 1) or direction (`w` 0) of draw `i`'s mesh, placed where it was in the previous frame, for motion blur. **/
		function modelToWorldBefore(i : Int, p : Vec4) : Vec4 {
			var d = i * 16;
			return draws[d + 12] * p.x + draws[d + 13] * p.y + draws[d + 14] * p.z + draws[d + 15] * p.w;
		}

		/** Has a normal texture, unlit, alpha mode, opacity. **/
		function drawFlags(i : Int) : Vec4 {
			return draws[i * 16 + 10];
		}
	};
}
