package ashui.canvaskit;

import ashui.canvaskit.GltfAnimation;
import ashui.draw.DrawContext;
import ashui.draw3d.Material;
import ashui.draw3d.MeshData;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import ashui.types.Bitmap;
import haxe.io.Bytes;
import haxe.io.Float32Array;
import haxe.io.UInt16Array;

/** A mesh of a glTF scene and where its node places it. **/
typedef GltfDraw = {mesh:MeshData, transform:Mat4};

/** A node of the scene's tree: where it sits in its parent, as the file gives it, and what it holds. **/
class GltfNode {
	public final name:Null<String>;

	/** Its parent's index in `Gltf.nodes`, -1 for a root. **/
	public final parent:Int;

	public final children:Array<Int>;
	public final translation:Vec3;
	public final rotation:Quat;
	public final scale:Vec3;

	/** Its transform when the file gives it as a matrix, which animations do not move; null when given as `translation`, `rotation` and `scale`. **/
	public final matrix:Null<Mat4>;

	/** Its mesh's index in `Gltf.meshes`, -1 for none. **/
	public final mesh:Int;

	/** Its skin's index in `Gltf.skins`, -1 for none. **/
	public final skin:Int;

	/** Its mesh's morph target weights, its own or else its mesh's. **/
	public final weights:Array<Float>;

	public function new(name, parent, children, translation, rotation, scale, matrix, mesh, skin, weights) {
		this.name = name;
		this.parent = parent;
		this.children = children;
		this.translation = translation;
		this.rotation = rotation;
		this.scale = scale;
		this.matrix = matrix;
		this.mesh = mesh;
		this.skin = skin;
		this.weights = weights;
	}

	/** Its transform in its parent, at rest. **/
	public function local():Mat4
		return matrix != null ? matrix : Mat4.compose(translation, rotation, scale);
}

/** A glTF mesh: its triangle primitives, and the morph target weights it starts with. **/
class GltfMesh {
	public final name:Null<String>;
	public final primitives:Array<GltfPrimitive>;
	public final weights:Array<Float>;

	public function new(name, primitives, weights) {
		this.name = name;
		this.primitives = primitives;
		this.weights = weights;
	}
}

/**
	One primitive of a mesh: the triangles ashui draws, and what a skinned
	or morphed drawing of them needs besides, each per vertex in the order
	of `mesh`'s vertices.
**/
class GltfPrimitive {
	public final mesh:MeshData;

	/** Four joints a vertex, each an index into its skin's `joints`; null when it is not skinned. **/
	public final joints:Null<UInt16Array>;

	/** Four weights a vertex, one for each of its `joints`. **/
	public final weights:Null<Float32Array>;

	/** What each morph target moves its vertices by. **/
	public final targets:Array<GltfMorphTarget>;

	public function new(mesh, joints, weights, targets) {
		this.mesh = mesh;
		this.joints = joints;
		this.weights = weights;
		this.targets = targets;
	}
}

/** How far a morph target moves each vertex's position, normal and tangent at full weight, three numbers a vertex; null where it moves none. **/
class GltfMorphTarget {
	public final positions:Null<Float32Array>;
	public final normals:Null<Float32Array>;
	public final tangents:Null<Float32Array>;

	public function new(positions, normals, tangents) {
		this.positions = positions;
		this.normals = normals;
		this.tangents = tangents;
	}
}

/** A skin: the nodes that are its joints, and each one's inverse bind matrix, from the mesh's space into the joint's at rest. **/
class GltfSkin {
	public final name:Null<String>;
	public final joints:Array<Int>;
	public final inverseBindMatrices:Array<Mat4>;

	/** The node its skeleton hangs from, -1 when the file does not say. **/
	public final skeleton:Int;

	public function new(name, joints, inverseBindMatrices, skeleton) {
		this.name = name;
		this.joints = joints;
		this.inverseBindMatrices = inverseBindMatrices;
		this.skeleton = skeleton;
	}
}

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
	`MeshData.build`). Its images are `gpuOnly`: their decoded pixels are
	freed once they are on the GPU.

	The whole file is read: its node tree, its skins, each primitive's
	joints, weights and morph targets, and its animations. A `GltfPose`
	plays an animation at a time: the nodes' transforms, each skin's joint
	matrices and the morph weights it gives, and the rigid meshes drawn
	where it puts them. Skinning and morphing the vertices are the game's,
	in a `ScenePass` of its own.
**/
class Gltf {
	/** Each triangle mesh where the scene's nodes place it at rest. **/
	public final draws:Array<GltfDraw>;

	public final nodes:Array<GltfNode>;

	/** The default scene's top nodes. **/
	public final roots:Array<Int>;

	public final meshes:Array<GltfMesh>;
	public final skins:Array<GltfSkin>;
	public final animations:Array<GltfAnimation>;

	/** The corners of the box round every mesh where its node places it. **/
	public final min:Vec3;

	public final max:Vec3;

	function new(draws:Array<GltfDraw>, nodes:Array<GltfNode>, roots:Array<Int>, meshes:Array<GltfMesh>, skins:Array<GltfSkin>,
			animations:Array<GltfAnimation>) {
		this.draws = draws;
		this.nodes = nodes;
		this.roots = roots;
		this.meshes = meshes;
		this.skins = skins;
		this.animations = animations;
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

	/** The animation named `name`, if there is one. **/
	public function animation(name:String):Null<GltfAnimation> {
		for (a in animations)
			if (a.name == name)
				return a;
		return null;
	}

	/** Draws every mesh at rest, all placed by `transform` too when it is given. **/
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

	public function new(json:Dynamic, bin:Null<Bytes>, read:String->Bytes) {
		this.json = json;
		this.bin = bin;
		this.read = read;
	}

	public function scene():Gltf {
		var meshes = [for (i in 0...list(json.meshes).length) mesh(i)];
		var parents = [for (_ in list(json.nodes)) -1];
		for (i in 0...parents.length) {
			var children:Array<Int> = list(json.nodes)[i].children;
			if (children != null)
				for (c in children)
					if (c >= 0 && c < parents.length)
						parents[c] = i;
		}
		var nodes = [for (i in 0...parents.length) node(i, parents[i], meshes)];
		var scenes:Array<Dynamic> = list(json.scenes);
		var roots:Array<Int> = if (scenes.length > 0) {
			var s:Dynamic = scenes[json.scene != null ? json.scene : 0];
			s.nodes != null ? s.nodes : [];
		} else [for (i in 0...nodes.length) if (parents[i] < 0) i];
		var draws:Array<GltfDraw> = [];
		for (r in roots)
			visit(nodes, meshes, r, Mat4.IDENTITY, draws, 0);
		var skins = [for (s in list(json.skins)) skin(s)];
		var animations = [for (a in list(json.animations)) animation(a, nodes, meshes)];
		return @:privateAccess new Gltf(draws, nodes, roots, meshes, skins, animations);
	}

	function node(index:Int, parent:Int, meshes:Array<GltfMesh>):GltfNode {
		var n:Dynamic = list(json.nodes)[index];
		var t:Array<Float> = n.translation, r:Array<Float> = n.rotation, s:Array<Float> = n.scale;
		var meshIndex:Int = n.mesh != null ? n.mesh : -1;
		var weights:Array<Float> = n.weights != null ? [for (w in (n.weights : Array<Float>)) (w : Float)] : meshIndex >= 0 ? meshes[meshIndex].weights.copy() : [];
		return new GltfNode(n.name, parent, n.children != null ? [for (c in (n.children : Array<Int>)) c] : [],
			t != null ? new Vec3(t[0], t[1], t[2]) : Vec3.ZERO, r != null ? new Quat(r[0], r[1], r[2], r[3]) : Quat.IDENTITY,
			s != null ? new Vec3(s[0], s[1], s[2]) : Vec3.ONE, n.matrix != null ? Mat4.ofColumns([for (v in (n.matrix : Array<Float>)) (v : Float)]) : null,
			meshIndex, n.skin != null ? n.skin : -1, weights);
	}

	function visit(nodes:Array<GltfNode>, meshes:Array<GltfMesh>, index:Int, parent:Mat4, out:Array<GltfDraw>, depth:Int):Void {
		if (depth > 64 || index < 0 || index >= nodes.length)
			return;
		var node = nodes[index];
		var world = parent.mul(node.local());
		if (node.mesh >= 0)
			for (p in meshes[node.mesh].primitives)
				out.push({mesh: p.mesh, transform: world});
		for (c in node.children)
			visit(nodes, meshes, c, world, out, depth + 1);
	}

	function mesh(index:Int):GltfMesh {
		var made = [];
		var m:Dynamic = list(json.meshes)[index];
		var targetCount = 0;
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
			var data = MeshData.build(positions, indices, normals, uvs, tangents, p.material != null ? material(p.material) : Material.DEFAULT);
			var joints:Null<UInt16Array> = null, weights:Null<Float32Array> = null;
			if (a.JOINTS_0 != null && a.WEIGHTS_0 != null) {
				var j = floats(a.JOINTS_0);
				joints = new UInt16Array(j.length);
				for (i in 0...j.length)
					joints[i] = Std.int(j[i]);
				weights = Float32Array.fromArray(floats(a.WEIGHTS_0));
			}
			var targets = [
				for (t in list(p.targets))
					new GltfMorphTarget(t.POSITION != null ? Float32Array.fromArray(floats(t.POSITION)) : null,
						t.NORMAL != null ? Float32Array.fromArray(floats(t.NORMAL)) : null,
						t.TANGENT != null ? Float32Array.fromArray(floats(t.TANGENT)) : null)
			];
			targetCount = Std.int(Math.max(targetCount, targets.length));
			made.push(new GltfPrimitive(data, joints, weights, targets));
		}
		var weights:Array<Float> = m.weights != null ? [for (w in (m.weights : Array<Float>)) (w : Float)] : [for (_ in 0...targetCount) 0.0];
		return new GltfMesh(m.name, made, weights);
	}

	function skin(s:Dynamic):GltfSkin {
		var joints:Array<Int> = [for (j in (s.joints : Array<Int>)) j];
		// Identity for each joint when the file gives no inverse bind matrices.
		var matrices = if (s.inverseBindMatrices != null) {
			var f = floats(s.inverseBindMatrices);
			[for (i in 0...joints.length) Mat4.ofColumns(f.slice(i * 16, i * 16 + 16))];
		} else [for (_ in joints) Mat4.IDENTITY];
		return new GltfSkin(s.name, joints, matrices, s.skeleton != null ? s.skeleton : -1);
	}

	function animation(a:Dynamic, nodes:Array<GltfNode>, meshes:Array<GltfMesh>):GltfAnimation {
		var samplers:Array<Dynamic> = list(a.samplers);
		var channels = [];
		for (c in list(a.channels)) {
			var target:Dynamic = c.target;
			// A channel without a node is for an extension to aim.
			if (target == null || target.node == null)
				continue;
			var node:Int = target.node;
			var path:GltfPath = switch (target.path : String) {
				case "translation": Translation;
				case "rotation": Rotation;
				case "scale": Scale;
				case "weights": Weights;
				case _: continue;
			}
			var sm:Dynamic = samplers[c.sampler];
			var interpolation:GltfInterpolation = switch (sm.interpolation : String) {
				case "STEP": Step;
				case "CUBICSPLINE": CubicSpline;
				case _: Linear;
			}
			var times = Float32Array.fromArray(floats(sm.input));
			var values = Float32Array.fromArray(floats(sm.output));
			var keys = times.length * (interpolation == CubicSpline ? 3 : 1);
			var width = keys > 0 ? Std.int(values.length / keys) : 0;
			channels.push(new GltfChannel(node, path, new GltfSampler(times, values, interpolation, width)));
		}
		return new GltfAnimation(a.name, channels);
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
			doubleSided: m.doubleSided == true,
			textureTransform: textureTransform([pbr.baseColorTexture, m.normalTexture, pbr.metallicRoughnessTexture, m.emissiveTexture, m.occlusionTexture])
		});
		materials.set(index, made);
		return made;
	}

	/**
		A material's `KHR_texture_transform`: the first of its textures' that
		has one, the base colour's first. ashui places all of a material's
		textures by one transform, as Blinc does; glTF lets each have its own.
	**/
	static function textureTransform(infos:Array<Dynamic>):Null<ashui.draw3d.TextureTransform> {
		for (info in infos) {
			var t:Dynamic = info != null && info.extensions != null ? Reflect.field(info.extensions, "KHR_texture_transform") : null;
			if (t == null)
				continue;
			var offset:Array<Float> = t.offset != null ? t.offset : [0, 0];
			var scale:Array<Float> = t.scale != null ? t.scale : [1, 1];
			return new ashui.draw3d.TextureTransform(scale[0], scale[1], t.rotation != null ? t.rotation : 0, offset[0], offset[1]);
		}
		return null;
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
		// Drawn only on meshes: once on the GPU, its decoded pixels are freed.
		made.gpuOnly = true;
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

	/**
		An accessor's elements, each component a float; integer components
		scaled to 0..1 (or -1..1) when normalized. A sparse accessor is its
		buffer view's elements, or zeros, with those it lists replaced.
	**/
	function floats(index:Int):Array<Float> {
		var a:Dynamic = list(json.accessors)[index];
		var n = components(a.type), count:Int = a.count;
		var out = [for (_ in 0...count * n) 0.0];
		var normalized = a.normalized == true;
		if (a.bufferView != null) {
			var v:Dynamic = list(json.bufferViews)[a.bufferView];
			var size = componentSize(a.componentType);
			var start = (v.byteOffset != null ? v.byteOffset : 0) + (a.byteOffset != null ? a.byteOffset : 0);
			var stride:Int = v.byteStride != null ? v.byteStride : n * size;
			elements(buffer(v.buffer), start, stride, count, n, a.componentType, normalized, i -> i, out);
		}
		var sparse:Dynamic = a.sparse;
		if (sparse != null) {
			var k:Int = sparse.count;
			var at = [for (_ in 0...k) 0.0];
			var iv:Dynamic = list(json.bufferViews)[sparse.indices.bufferView];
			var isize = componentSize(sparse.indices.componentType);
			elements(buffer(iv.buffer), (iv.byteOffset != null ? iv.byteOffset : 0) + (sparse.indices.byteOffset != null ? sparse.indices.byteOffset : 0), isize,
				k, 1, sparse.indices.componentType, false, i -> i, at);
			var vv:Dynamic = list(json.bufferViews)[sparse.values.bufferView];
			elements(buffer(vv.buffer), (vv.byteOffset != null ? vv.byteOffset : 0) + (sparse.values.byteOffset != null ? sparse.values.byteOffset : 0),
				n * componentSize(a.componentType), k, n, a.componentType, normalized, i -> Std.int(at[i]), out);
		}
		return out;
	}

	/** `count` elements of `n` components from `data`, element `i` into `out` at element `into(i)`. **/
	static function elements(data:Bytes, start:Int, stride:Int, count:Int, n:Int, type:Int, normalized:Bool, into:Int->Int, out:Array<Float>):Void {
		var size = componentSize(type);
		for (i in 0...count) {
			var o = into(i) * n;
			for (c in 0...n)
				out[o + c] = component(data, start + i * stride + c * size, type, normalized);
		}
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
