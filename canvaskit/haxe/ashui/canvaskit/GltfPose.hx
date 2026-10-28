package ashui.canvaskit;

import ashui.canvaskit.GltfAnimation;
import ashui.draw.DrawContext;
import ashui.math.Mat4;
import ashui.math.Quat;
import ashui.math.Vec3;
import haxe.io.Bytes;

/**
	Node transforms and morph weights for a glTF scene.

	Starts at rest; `play` samples an animation at a caller-supplied time.
	The application controls the clock, looping, blending, and scrubbing.

	```haxe
	var pose = new GltfPose(drone);
	var clip = drone.animations[0];
	<scene-kit draw={ctx -> {
		pose.play(clip, time.get() % clip.duration);
		pose.draw(ctx);
	}} />;
	```

	`update` writes world transforms into `matrices`; `palette` writes skin
	joint matrices into an upload buffer. `weights` stores node morph weights.
	Custom skinning and morph passes can read these buffers, or use the
	`world` and `joints` matrix arrays.
**/
class GltfPose {
	public final scene:Gltf;
	public final translations:Array<Vec3>;
	public final rotations:Array<Quat>;
	public final scales:Array<Vec3>;

	/** Morph-target weights per node. **/
	public final weights:Array<Array<Float>>;

	/** Whether each node mesh is drawn. Defaults to true for every node. **/
	public final visible:Array<Bool>;

	/** Bytes per column-major matrix: sixteen 32-bit floats. **/
	public static inline var MATRIX_BYTES = 64;

	/** World transforms after `update`, with `MATRIX_BYTES` per node in `Gltf.nodes` order. **/
	public final matrices:Bytes;

	/** Default-scene nodes in parent-before-child order. **/
	final order:Array<Int> = [];

	/** Parent indices in the default scene, or -1 for roots and nodes outside it. **/
	final above:Array<Int>;

	final reached:Array<Bool>;

	/** Lazily converted inverse bind matrices per skin, stored as 32-bit floats. **/
	final binds:Array<Null<Bytes>>;

	final sampled:Array<Float> = [0, 0, 0, 0];
	final scratch = Bytes.alloc(MATRIX_BYTES);

	public function new(scene:Gltf) {
		this.scene = scene;
		translations = [for (n in scene.nodes) n.translation];
		rotations = [for (n in scene.nodes) n.rotation];
		scales = [for (n in scene.nodes) n.scale];
		weights = [for (n in scene.nodes) n.weights.copy()];
		visible = [for (_ in scene.nodes) true];
		matrices = Bytes.alloc(scene.nodes.length * MATRIX_BYTES);
		above = [for (_ in scene.nodes) -1];
		reached = [for (_ in scene.nodes) false];
		binds = [for (_ in scene.skins) null];
		function visit(i:Int, parent:Int, depth:Int) {
			if (depth > 64 || i < 0 || i >= reached.length || reached[i])
				return;
			reached[i] = true;
			above[i] = parent;
			order.push(i);
			for (c in scene.nodes[i].children)
				visit(c, i, depth + 1);
		}
		for (r in scene.roots)
			visit(r, -1, 0);
	}

	/** Restores every node to its file-defined rest state. **/
	public function reset():Void {
		for (i in 0...scene.nodes.length) {
			var n = scene.nodes[i];
			translations[i] = n.translation;
			rotations[i] = n.rotation;
			scales[i] = n.scale;
			for (k in 0...n.weights.length)
				weights[i][k] = n.weights[k];
		}
	}

	/** Samples animated properties at `time` seconds. Leaves untargeted properties unchanged. **/
	public function play(animation:GltfAnimation, time:Float):Void {
		for (c in animation.channels) {
			if (c.node < 0 || c.node >= scene.nodes.length)
				continue;
			switch c.path {
				case Translation:
					c.sampler.sample(time, sampled);
					translations[c.node] = new Vec3(sampled[0], sampled[1], sampled[2]);
				case Rotation:
					c.sampler.sample(time, sampled, true);
					rotations[c.node] = new Quat(sampled[0], sampled[1], sampled[2], sampled[3]);
				case Scale:
					c.sampler.sample(time, sampled);
					scales[c.node] = new Vec3(sampled[0], sampled[1], sampled[2]);
				case Weights:
					var into = weights[c.node];
					while (into.length < c.sampler.width)
						into.push(0);
					c.sampler.sample(time, into);
			}
		}
	}

	/** Returns the node parent-relative transform, preserving any explicit file matrix. **/
	public function local(node:Int):Mat4 {
		var n = scene.nodes[node];
		return n.matrix != null ? n.matrix : Mat4.compose(translations[node], rotations[node], scales[node]);
	}

	/**
		Writes world transforms to `matrices` in parent-before-child order.
		Nodes outside the default scene use their local transform.
		`-D ash_simd` enables SIMD matrix multiplication.
	**/
	public function update():Void {
		for (i in 0...scene.nodes.length)
			if (!reached[i])
				writeLocal(i, matrices, i * MATRIX_BYTES);
		for (i in order)
			if (above[i] < 0)
				writeLocal(i, matrices, i * MATRIX_BYTES);
			else {
				writeLocal(i, scratch, 0);
				multiply(matrices, above[i] * MATRIX_BYTES, scratch, 0, matrices, i * MATRIX_BYTES, SIMD);
			}
	}

	/**
		Writes skin joint matrices into `out` at `offset`, with `MATRIX_BYTES`
		per joint in skin order. Uses the latest world transforms from `update`
		multiplied by inverse bind matrices. The result maps rest vertices to
		world space; draw skinned meshes without another node transform.
	**/
	public function palette(skin:Int, out:Bytes, offset = 0):Void {
		var s = scene.skins[skin];
		var b = binds[skin];
		if (b == null) {
			b = Bytes.alloc(s.joints.length * MATRIX_BYTES);
			for (j in 0...s.joints.length)
				writeMat4(s.inverseBindMatrices[j], b, j * MATRIX_BYTES);
			binds[skin] = b;
		}
		for (j in 0...s.joints.length)
			multiply(matrices, s.joints[j] * MATRIX_BYTES, b, j * MATRIX_BYTES, out, offset + j * MATRIX_BYTES, SIMD);
	}

	/** Returns world transforms in `Gltf.nodes` order. **/
	public function world():Array<Mat4> {
		update();
		return [for (i in 0...scene.nodes.length) readMat4(matrices, i * MATRIX_BYTES)];
	}

	/** Returns one joint matrix per skin joint, equivalent to the `palette` buffer. **/
	public function joints(skin:Int):Array<Mat4> {
		update();
		var n = scene.skins[skin].joints.length;
		var out = Bytes.alloc(n * MATRIX_BYTES);
		palette(skin, out);
		return [for (j in 0...n) readMat4(out, j * MATRIX_BYTES)];
	}

	/**
		Draws visible, unskinned meshes with the current pose. Optionally adds
		a transform and maps materials through `material`. Does not apply morph
		targets; the application draws skinned geometry in its own pass.
	**/
	public function draw(ctx:DrawContext, ?transform:Mat4, ?material:ashui.draw3d.Material->ashui.draw3d.Material):Void {
		update();
		for (i in 0...scene.nodes.length) {
			var n = scene.nodes[i];
			if (n.mesh < 0 || n.skin >= 0 || !reached[i] || !visible[i])
				continue;
			var w = readMat4(matrices, i * MATRIX_BYTES);
			var m = transform != null ? transform.mul(w) : w;
			for (p in scene.meshes[n.mesh].primitives)
				ctx.drawMesh(p.mesh, m, material != null ? material(p.mesh.material) : null);
		}
	}

	/** Writes a node local transform as column-major 32-bit floats at the given byte offset. **/
	function writeLocal(i:Int, out:Bytes, o:Int):Void {
		var m = scene.nodes[i].matrix;
		if (m != null) {
			writeMat4(m, out, o);
			return;
		}
		var t = translations[i], q = rotations[i], s = scales[i];
		var x = q.x, y = q.y, z = q.z, w = q.w;
		inline function put(k:Int, v:Float)
			out.setFloat(o + k * 4, v);
		put(0, (1 - 2 * (y * y + z * z)) * s.x);
		put(1, 2 * (x * y + w * z) * s.x);
		put(2, 2 * (x * z - w * y) * s.x);
		put(3, 0);
		put(4, 2 * (x * y - w * z) * s.y);
		put(5, (1 - 2 * (x * x + z * z)) * s.y);
		put(6, 2 * (y * z + w * x) * s.y);
		put(7, 0);
		put(8, 2 * (x * z + w * y) * s.z);
		put(9, 2 * (y * z - w * x) * s.z);
		put(10, (1 - 2 * (x * x + y * y)) * s.z);
		put(11, 0);
		put(12, t.x);
		put(13, t.y);
		put(14, t.z);
		put(15, 1);
	}

	static function writeMat4(m:Mat4, out:Bytes, o:Int):Void
		for (c in 0...4)
			for (r in 0...4)
				out.setFloat(o + (c * 4 + r) * 4, m.get(c, r));

	static function readMat4(b:Bytes, o:Int):Mat4
		return Mat4.ofColumns([for (k in 0...16) b.getFloat(o + k * 4)]);

	/** Whether matrix products go through ash-simd. **/
	static inline var SIMD = #if (ash_simd && hl) true #else false #end;

	/** Multiplies column-major float matrices into a distinct output buffer. **/
	static function multiply(a:Bytes, ai:Int, b:Bytes, bi:Int, out:Bytes, oi:Int, simd:Bool):Void {
		#if (ash_simd && hl)
		if (simd) {
			var pa:hl.Bytes = a, pb:hl.Bytes = b, po:hl.Bytes = out;
			var c0 = ash.simd.Float32x4.load(pa, ai),
				c1 = ash.simd.Float32x4.load(pa, ai + 16);
			var c2 = ash.simd.Float32x4.load(pa, ai + 32),
				c3 = ash.simd.Float32x4.load(pa, ai + 48);
			// Each column of the product: `a`'s columns weighted by that column of `b`.
			for (j in 0...4) {
				var o = bi + j * 16;
				var col = c0 * ash.simd.Float32x4.splat(pb.getF32(o)) + c1 * ash.simd.Float32x4.splat(pb.getF32(o + 4))
					+ c2 * ash.simd.Float32x4.splat(pb.getF32(o + 8)) + c3 * ash.simd.Float32x4.splat(pb.getF32(o + 12));
				col.store(po, oi + j * 16);
			}
			return;
		}
		#end
		for (j in 0...4)
			for (r in 0...4) {
				var v = 0.0;
				for (k in 0...4)
					v += a.getFloat(ai + (k * 4 + r) * 4) * b.getFloat(bi + (j * 4 + k) * 4);
				out.setFloat(oi + (j * 4 + r) * 4, v);
			}
	}
}
