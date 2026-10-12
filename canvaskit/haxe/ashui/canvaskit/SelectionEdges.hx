package ashui.canvaskit;

import ashui.draw3d.MeshData;
import ashui.draw3d.ScenePass;
import ashui.math.Mat4;
import ashui.math.Vec3;

private typedef Edge = {a:Int, b:Int, n0:Vec3, n1:Vec3, boundary:Bool};
private typedef EdgeDraw = {mesh:MeshData, transform:Mat4, opacity:Float};

/**
	Selected-object silhouettes (git-bug 8ceba8d, 67cca2c), using the scene's depth buffer.
	Welds coincident positions across UV/normal seams, suppresses coplanar
	triangle diagonals, and lets the shader find silhouettes for each view.
	Geometry and GPU resources are cached for the current selected meshes;
	no render target, timer or duplicate mesh vertex upload is needed.
**/
class SelectionEdges implements ScenePass {
	final draws:Array<EdgeDraw> = [];
	var logicalWidth = 1.0;
	var frame = 0;

	public function new() {}
	public function begin(width:Float):Void { draws.resize(0); logicalWidth = width; frame++; }
	public function add(mesh:MeshData, transform:Mat4, opacity:Float):Void
		if (opacity > 0) draws.push({mesh: mesh, transform: transform, opacity: opacity});
	public function empty():Bool return draws.length == 0;
	public function stage():SceneStage return Overlay;
	public function animated():Bool return false;

	/** Noncoplanar adjacency and open boundaries; the shader keeps only visible contours (67cca2c). **/
	public static function geometry(mesh:MeshData):haxe.io.Bytes {
		var ids = new haxe.ds.Vector<Int>(mesh.vertexCount), positions = new Map<String, Int>();
		var extent = mesh.max.sub(mesh.min);
		var zero = Math.max(extent.x, Math.max(extent.y, extent.z)) * 1e-7;
		for (i in 0...mesh.vertexCount) {
			var at = i * MeshData.STRIDE;
			// Normalize signed zero and trigonometric zero residue in weld keys only.
			// The endpoints uploaded below retain their original fractional coordinates.
			var x = Math.abs(mesh.vertices.getFloat(at)) <= zero ? 0 : mesh.vertices.getInt32(at);
			var y = Math.abs(mesh.vertices.getFloat(at + 4)) <= zero ? 0 : mesh.vertices.getInt32(at + 4);
			var z = Math.abs(mesh.vertices.getFloat(at + 8)) <= zero ? 0 : mesh.vertices.getInt32(at + 8);
			var key = '$x:$y:$z', id = positions.get(key);
			if (id == null) { id = i; positions.set(key, i); }
			ids[i] = id;
		}
		var edges = new Map<String, Edge>();
		inline function point(i:Int):Vec3 {
			var at = i * MeshData.STRIDE;
			return new Vec3(mesh.vertices.getFloat(at), mesh.vertices.getFloat(at + 4), mesh.vertices.getFloat(at + 8));
		}
		function edge(a:Int, b:Int, n:Vec3):Void {
			if (a > b) { var swap = a; a = b; b = swap; }
			var key = '$a:$b', known = edges.get(key);
			if (known == null) edges.set(key, {a: a, b: b, n0: n, n1: n, boundary: true});
			else { known.n1 = n; known.boundary = false; }
		}
		var i = 0;
		while (i + 2 < mesh.indexCount) {
			var a = ids[mesh.indices.getInt32(i * 4)], b = ids[mesh.indices.getInt32((i + 1) * 4)], c = ids[mesh.indices.getInt32((i + 2) * 4)];
			// One normal per face, without allocating temporary vectors for each triangle.
			var pa = a * MeshData.STRIDE, pb = b * MeshData.STRIDE, pc = c * MeshData.STRIDE;
			var x = mesh.vertices.getFloat(pa), y = mesh.vertices.getFloat(pa + 4), z = mesh.vertices.getFloat(pa + 8);
			var ux = mesh.vertices.getFloat(pb) - x, uy = mesh.vertices.getFloat(pb + 4) - y, uz = mesh.vertices.getFloat(pb + 8) - z;
			var vx = mesh.vertices.getFloat(pc) - x, vy = mesh.vertices.getFloat(pc + 4) - y, vz = mesh.vertices.getFloat(pc + 8) - z;
			var nx = uy * vz - uz * vy, ny = uz * vx - ux * vz, nz = ux * vy - uy * vx;
			var length = Math.sqrt(nx * nx + ny * ny + nz * nz);
			if (length > 0) {
				var n = new Vec3(nx / length, ny / length, nz / length);
				edge(a, b, n); edge(b, c, n); edge(c, a, n);
			}
			i += 3;
		}
		var kept = [for (e in edges) if (e.boundary || e.n0.dot(e.n1) < 0.999999) e];
		var out = haxe.io.Bytes.alloc(kept.length * 64);
		inline function row(at:Int, p:Vec3, w:Float):Void {
			out.setFloat(at, p.x); out.setFloat(at + 4, p.y); out.setFloat(at + 8, p.z); out.setFloat(at + 12, w);
		}
		for (i in 0...kept.length) {
			var e = kept[i], at = i * 64;
			row(at, point(e.a), 0); row(at + 16, point(e.b), 0);
			row(at + 32, e.n0, e.boundary ? 1 : 0);
			row(at + 48, e.n1, 0);
		}
		return out;
	}

	#if ashui_gpu
	var pipeline:Null<gpu.GpuPipeline>;
	final meshes = new haxe.ds.ObjectMap<MeshData, {buffer:gpu.GpuBuffer, count:Int, used:Int}>();
	final slots:Array<{settings:gpu.GpuBuffer, group:Null<gpu.GpuBindGroup>, scene:Int, edges:Int}> = [];
	final bytes = haxe.io.Bytes.alloc(144);

	public function prepare(frame:ScenePassFrame):Void {
		if (pipeline == null) {
			var builder = frame.pipelineBuilder(SelectionEdgeShader.WGSL, true, false);
			builder.primitive(TriangleList, None, Ccw);
			builder.depth(frame.depthFormat, false, LessEqual);
			pipeline = builder.build();
		}
		for (d in draws) {
			var known = meshes.get(d.mesh);
			if (known == null) {
				var data = geometry(d.mesh), count = Std.int(data.length / 64);
				var buffer = frame.device.createBuffer(new gpu.GpuBufferDescriptor(Std.int(Math.max(64, data.length)),
					ashui.core.render.GpuFlags.BUFFER_STORAGE | ashui.core.render.GpuFlags.BUFFER_COPY_DST));
				if (data.length > 0) frame.device.queue().writeBuffer(buffer, 0, data, data.length);
				known = {buffer: buffer, count: count, used: this.frame}; meshes.set(d.mesh, known);
			}
			known.used = this.frame;
		}
		for (mesh => entry in meshes) if (entry.used != this.frame) { entry.buffer.destroy(); meshes.remove(mesh); }
		while (slots.length > draws.length) { var slot = slots.pop(); slot.group.destroy(); slot.settings.destroy(); }
		for (i in 0...draws.length) {
			var d = draws[i], edges = meshes.get(d.mesh);
			if (slots.length <= i) slots.push({settings: frame.device.createBuffer(new gpu.GpuBufferDescriptor(144,
				ashui.core.render.GpuFlags.BUFFER_STORAGE | ashui.core.render.GpuFlags.BUFFER_COPY_DST)), group: null, scene: -1, edges: -1});
			var slot = slots[i];
			if (slot.group == null || slot.scene != (frame.sceneBuffer : Int) || slot.edges != (edges.buffer : Int)) {
				if (slot.group != null) slot.group.destroy();
				var bindings = new gpu.GpuBindings();
				bindings.buffer(frame.sceneBuffer); bindings.buffer(edges.buffer); bindings.buffer(slot.settings);
				slot.group = frame.device.bindGroup(pipeline, 0, bindings); bindings.destroy();
				slot.scene = (frame.sceneBuffer : Int); slot.edges = (edges.buffer : Int);
			}
			d.transform.write(bytes, 0);
			var a = d.transform.m;
			var c0 = new Vec3(a[5] * a[10] - a[6] * a[9], a[6] * a[8] - a[4] * a[10], a[4] * a[9] - a[5] * a[8]);
			var c1 = new Vec3(a[9] * a[2] - a[10] * a[1], a[10] * a[0] - a[8] * a[2], a[8] * a[1] - a[9] * a[0]);
			var c2 = new Vec3(a[1] * a[6] - a[2] * a[5], a[2] * a[4] - a[0] * a[6], a[0] * a[5] - a[1] * a[4]);
			var sign = a[0] * c0.x + a[1] * c0.y + a[2] * c0.z < 0 ? -1 : 1;
			inline function row(at:Int, x:Float, y:Float, z:Float, w:Float) {
				bytes.setFloat(at * 16, x); bytes.setFloat(at * 16 + 4, y); bytes.setFloat(at * 16 + 8, z); bytes.setFloat(at * 16 + 12, w);
			}
			row(4, c0.x * sign, c0.y * sign, c0.z * sign, 0); row(5, c1.x * sign, c1.y * sign, c1.z * sign, 0); row(6, c2.x * sign, c2.y * sign, c2.z * sign, 0);
			row(7, frame.width, frame.height, 0.65 * frame.width / Math.max(1, logicalWidth), 0);
			row(8, 0.74, 0.88, 1, 0.72 * d.opacity);
			frame.device.queue().writeBuffer(slot.settings, 0, bytes, bytes.length);
		}
	}

	public function draw(frame:ScenePassFrame):Void {
		frame.encoder.renderSetPipeline(pipeline);
		for (i in 0...draws.length) {
			var edges = meshes.get(draws[i].mesh);
			if (edges.count == 0) continue;
			frame.encoder.renderSetBindGroup(0, slots[i].group);
			frame.encoder.renderDraw(6, edges.count);
		}
	}

	/** Drop geometry when selection clears; retain the compiled pipeline until owner disposal. **/
	public function clear():Void {
		for (entry in meshes) entry.buffer.destroy();
		meshes.clear();
		for (slot in slots) { if (slot.group != null) slot.group.destroy(); slot.settings.destroy(); }
		slots.resize(0);
		draws.resize(0);
	}

	public function dispose():Void {
		clear();
		if (pipeline != null) pipeline.destroy();
		pipeline = null; draws.resize(0);
	}
	#else
	public function prepare(frame:ScenePassFrame):Void {}
	public function draw(frame:ScenePassFrame):Void {}
	public function clear():Void { draws.resize(0); }
	public function dispose():Void { draws.resize(0); }
	#end
}
