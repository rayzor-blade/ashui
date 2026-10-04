package ashui.canvaskit;

import ashui.draw.DrawContext;
import ashui.draw3d.Material;
import ashui.draw3d.MeshData;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.types.Bitmap;
import haxe.io.Bytes;

/** A mesh of a glTF scene and where its node places it. **/
typedef GltfDraw = {mesh:MeshData, transform:Mat4};

/**
	A glTF 2.0 scene, read from a `.gltf` file and the buffers and images
	beside it, or from a `.glb`: each triangle mesh of the default scene's
	nodes with the transform its node and those above it give, its
	material as glTF's metallic-roughness describes it, its textures
	decoded once and shared between materials.

	```haxe
	var helmet = Gltf.load("assets/DamagedHelmet/DamagedHelmet.gltf");
	<scene-kit draw={ctx -> helmet.draw(ctx)} />;
	```

	Normals and tangents left out of a mesh are worked out (see
	`MeshData.build`). Animations and skins are not read yet.
**/
class Gltf {
	public final draws:Array<GltfDraw>;

	/** The corners of the box round every mesh where its node places it. **/
	public final min:Vec3;

	public final max:Vec3;

	function new(draws:Array<GltfDraw>) {
		this.draws = draws;
		var lo = new Vec3(Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY);
		var hi = new Vec3(Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY);
		for (d in draws)
			for (x in [d.mesh.min.x, d.mesh.max.x])
				for (y in [d.mesh.min.y, d.mesh.max.y])
					for (z in [d.mesh.min.z, d.mesh.max.z]) {
						var p = d.transform.transformPoint(new Vec3(x, y, z));
						lo = new Vec3(Math.min(lo.x, p.x), Math.min(lo.y, p.y), Math.min(lo.z, p.z));
						hi = new Vec3(Math.max(hi.x, p.x), Math.max(hi.y, p.y), Math.max(hi.z, p.z));
					}
		min = draws.length > 0 ? lo : Vec3.ZERO;
		max = draws.length > 0 ? hi : Vec3.ZERO;
	}

	/** Draws every mesh, all placed by `transform` too when it is given. **/
	public function draw(ctx:DrawContext, ?transform:Mat4):Void
		for (d in draws)
			ctx.drawMesh(d.mesh, transform != null ? transform.mul(d.transform) : d.transform);

	#if sys
	/** The `.gltf` or `.glb` file at `path`, its buffers and images read from beside it. **/
	public static function load(path:String):Gltf {
		var dir = haxe.io.Path.directory(path);
		return parse(sys.io.File.getBytes(path), uri -> sys.io.File.getBytes(dir == "" ? uri : haxe.io.Path.join([dir, uri])));
	}
	#end

	/**
		A scene from the bytes of a `.gltf` or `.glb`; `read` gives the bytes
		of a file it names by a relative `uri`. Throws when it is not glTF 2.0.
	**/
	public static function parse(file:Bytes, read:String->Bytes):Gltf {
		var json:Dynamic, bin:Null<Bytes> = null;
		if (file.length >= 12 && file.getInt32(0) == 0x46546C67) {
			// GLB: a header, a JSON chunk, then the binary chunk the first buffer is.
			var at = 12;
			json = null;
			while (at + 8 <= file.length) {
				var length = file.getInt32(at), kind = file.getInt32(at + 4);
				if (kind == 0x4E4F534A)
					json = haxe.Json.parse(file.getString(at + 8, length));
				else if (kind == 0x004E4942)
					bin = file.sub(at + 8, length);
				at += 8 + length;
			}
			if (json == null)
				throw "glb: no JSON chunk";
		} else
			json = haxe.Json.parse(file.toString());
		if (json.asset == null || !StringTools.startsWith(Std.string(json.asset.version), "2"))
			throw "not glTF 2.0";
		return new Reader(json, bin, read).scene();
	}
}

/** Reads one file's JSON: its buffers, accessors, textures, materials and nodes, each once. **/
private class Reader {
	final json:Dynamic;
	final bin:Null<Bytes>;
	final read:String->Bytes;
	final buffers = new Map<Int, Bytes>();
	final images = new Map<Int, Bitmap>();
	final materials = new Map<Int, Material>();
	final meshes = new Map<Int, Array<MeshData>>();

	public function new(json:Dynamic, bin:Null<Bytes>, read:String->Bytes) {
		this.json = json;
		this.bin = bin;
		this.read = read;
	}

	public function scene():Gltf {
		var draws:Array<GltfDraw> = [];
		var scenes:Array<Dynamic> = json.scenes != null ? json.scenes : [];
		var roots:Array<Int> = if (scenes.length > 0) {
			var s:Dynamic = scenes[json.scene != null ? json.scene : 0];
			s.nodes != null ? s.nodes : [];
		} else [for (i in 0...list(json.nodes).length) i];
		for (r in roots)
			visit(r, Mat4.IDENTITY, draws, 0);
		return @:privateAccess new Gltf(draws);
	}

	function visit(index:Int, parent:Mat4, out:Array<GltfDraw>, depth:Int):Void {
		if (depth > 64)
			return;
		var node:Dynamic = list(json.nodes)[index];
		var local = if (node.matrix != null) Mat4.ofColumns([for (v in (node.matrix : Array<Float>)) (v : Float)]) else {
			var t:Array<Float> = node.translation, r:Array<Float> = node.rotation, s:Array<Float> = node.scale;
			Mat4.compose(t != null ? new Vec3(t[0], t[1], t[2]) : Vec3.ZERO, r != null ? new Quat(r[0], r[1], r[2], r[3]) : Quat.IDENTITY,
				s != null ? new Vec3(s[0], s[1], s[2]) : Vec3.ONE);
		}
		var world = parent.mul(local);
		if (node.mesh != null)
			for (m in mesh(node.mesh))
				out.push({mesh: m, transform: world});
		if (node.children != null)
			for (c in (node.children : Array<Int>))
				visit(c, world, out, depth + 1);
	}

	function mesh(index:Int):Array<MeshData> {
		var known = meshes.get(index);
		if (known != null)
			return known;
		var made = [];
		var m:Dynamic = list(json.meshes)[index];
		for (p in (m.primitives : Array<Dynamic>)) {
			// Triangles only: points, lines and strips are not drawn.
			if (p.mode != null && p.mode != 4)
				continue;
			var a:Dynamic = p.attributes;
			if (a.POSITION == null)
				continue;
			var positions = floats(a.POSITION);
			var count = Std.int(positions.length / 3);
			var indices = p.indices != null ? ints(p.indices) : [for (i in 0...count) i];
			var normals = a.NORMAL != null ? floats(a.NORMAL) : null;
			var uvs = a.TEXCOORD_0 != null ? floats(a.TEXCOORD_0) : null;
			var tangents = a.TANGENT != null && normals != null ? floats(a.TANGENT) : null;
			made.push(MeshData.build(positions, indices, normals, uvs, tangents, p.material != null ? material(p.material) : Material.DEFAULT));
		}
		meshes.set(index, made);
		return made;
	}

	function material(index:Int):Material {
		var known = materials.get(index);
		if (known != null)
			return known;
		var m:Dynamic = list(json.materials)[index];
		var pbr:Dynamic = m.pbrMetallicRoughness != null ? m.pbrMetallicRoughness : {};
		var base:Array<Float> = pbr.baseColorFactor != null ? pbr.baseColorFactor : [1, 1, 1, 1];
		var emissive:Array<Float> = m.emissiveFactor != null ? m.emissiveFactor : [0, 0, 0];
		// glTF's factors are linear and may pass 1 with KHR_materials_emissive_strength; Material's colours are sRGB.
		var strength = m.extensions != null && Reflect.field(m.extensions, "KHR_materials_emissive_strength") != null ? (Reflect.field(m.extensions,
			"KHR_materials_emissive_strength").emissiveStrength : Float) : 1.0;
		var made = new Material({
			baseColor: srgb(base[0], base[1], base[2]),
			alpha: base[3],
			metallic: pbr.metallicFactor != null ? pbr.metallicFactor : 1,
			roughness: pbr.roughnessFactor != null ? pbr.roughnessFactor : 1,
			emissive: srgb(emissive[0], emissive[1], emissive[2]),
			emissiveStrength: strength,
			baseColorTexture: texture(pbr.baseColorTexture),
			metallicRoughnessTexture: texture(pbr.metallicRoughnessTexture),
			normalTexture: texture(m.normalTexture),
			normalScale: m.normalTexture != null && m.normalTexture.scale != null ? m.normalTexture.scale : 1,
			occlusionTexture: texture(m.occlusionTexture),
			occlusionStrength: m.occlusionTexture != null && m.occlusionTexture.strength != null ? m.occlusionTexture.strength : 1,
			emissiveTexture: texture(m.emissiveTexture),
			alphaMode: switch (m.alphaMode : String) {
				case "MASK": Mask;
				case "BLEND": Blend;
				case _: Opaque;
			},
			alphaCutoff: m.alphaCutoff != null ? m.alphaCutoff : 0.5,
			doubleSided: m.doubleSided == true
		});
		materials.set(index, made);
		return made;
	}

	function texture(info:Dynamic):Null<Bitmap> {
		if (info == null || info.index == null)
			return null;
		var t:Dynamic = list(json.textures)[info.index];
		if (t == null || t.source == null)
			return null;
		var known = images.get(t.source);
		if (known != null)
			return known;
		var image:Dynamic = list(json.images)[t.source];
		var bytes = if (image.bufferView != null) view(image.bufferView) else uri(image.uri);
		var made = Bitmap.fromBytes(bytes);
		images.set(t.source, made);
		return made;
	}

	function uri(u:String):Bytes {
		if (StringTools.startsWith(u, "data:")) {
			var comma = u.indexOf(",");
			return haxe.crypto.Base64.decode(u.substr(comma + 1));
		}
		return read(StringTools.urlDecode(u));
	}

	function buffer(index:Int):Bytes {
		var known = buffers.get(index);
		if (known != null)
			return known;
		var b:Dynamic = list(json.buffers)[index];
		var made = b.uri != null ? uri(b.uri) : bin;
		if (made == null)
			throw 'glTF buffer $index has no data';
		buffers.set(index, made);
		return made;
	}

	/** A buffer view's bytes. **/
	function view(index:Int):Bytes {
		var v:Dynamic = list(json.bufferViews)[index];
		return buffer(v.buffer).sub(v.byteOffset != null ? v.byteOffset : 0, v.byteLength);
	}

	/** An accessor's elements, each component a float; integer components scaled to 0..1 (or -1..1) when normalized. **/
	function floats(index:Int):Array<Float> {
		var a:Dynamic = list(json.accessors)[index];
		var n = components(a.type), count:Int = a.count;
		var out = [for (_ in 0...count * n) 0.0];
		if (a.bufferView == null)
			return out;
		var v:Dynamic = list(json.bufferViews)[a.bufferView];
		var data = buffer(v.buffer);
		var size = componentSize(a.componentType);
		var start = (v.byteOffset != null ? v.byteOffset : 0) + (a.byteOffset != null ? a.byteOffset : 0);
		var stride:Int = v.byteStride != null ? v.byteStride : n * size;
		var normalized = a.normalized == true;
		for (i in 0...count)
			for (c in 0...n)
				out[i * n + c] = component(data, start + i * stride + c * size, a.componentType, normalized);
		return out;
	}

	function ints(index:Int):Array<Int>
		return [for (f in floats(index)) Std.int(f)];

	static function component(data:Bytes, at:Int, type:Int, normalized:Bool):Float
		return switch type {
			case 5126: data.getFloat(at);
			case 5125: (data.getInt32(at) : Float) + (data.getInt32(at) < 0 ? 4294967296.0 : 0);
			case 5123: var v = data.getUInt16(at); normalized ? v / 65535 : v;
			case 5122: var v = data.getUInt16(at); var s = v >= 0x8000 ? v - 0x10000 : v; normalized ? Math.max(s / 32767, -1) : s;
			case 5121: var v = data.get(at); normalized ? v / 255 : v;
			case 5120: var v = data.get(at); var s = v >= 0x80 ? v - 0x100 : v; normalized ? Math.max(s / 127, -1) : s;
			case _: 0;
		}

	static function componentSize(type:Int):Int
		return switch type {
			case 5126 | 5125: 4;
			case 5123 | 5122: 2;
			case _: 1;
		}

	static function components(type:String):Int
		return switch type {
			case "SCALAR": 1;
			case "VEC2": 2;
			case "VEC3": 3;
			case "VEC4" | "MAT2": 4;
			case "MAT3": 9;
			case "MAT4": 16;
			case _: 1;
		}

	static function list(v:Dynamic):Array<Dynamic>
		return v != null ? v : [];

	/** A linear colour as `0xRRGGBB` sRGB, each channel clamped to 0..1. **/
	static function srgb(r:Float, g:Float, b:Float):Int {
		inline function channel(c:Float):Int {
			var v = Math.max(0, Math.min(1, c));
			var s = v <= 0.0031308 ? v * 12.92 : 1.055 * Math.pow(v, 1 / 2.4) - 0.055;
			return Std.int(Math.round(s * 255));
		}
		return channel(r) << 16 | channel(g) << 8 | channel(b);
	}
}
