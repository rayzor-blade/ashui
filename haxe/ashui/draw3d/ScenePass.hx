package ashui.draw3d;

#if ashui_gpu
typedef ScenePassFrame = ashui.core.render.ScenePassFrame;
#else
/** A build without the renderer records passes and never draws them. **/
typedef ScenePassFrame = Dynamic;
#end

/**
	A pass that casts shadows: `drawShadow` draws its geometry's depth into
	the scene's shadow map, `frame.encoder` in the shadow pass, through
	`frame.shadowPipelineBuilder`, a shader that writes its light-space
	depth as `ashui.shaders.Shadows.shadowDepth` does.
**/
interface ShadowCaster {
	function drawShadow(frame:ScenePassFrame):Void;
}

/** When in a 3D scene a pass draws. **/
enum abstract SceneStage(Int) to Int {
	/** After the layer is cleared and the skybox drawn, before any mesh: backdrops. **/
	var Background = 0;

	/** After the opaque meshes: more solid things, writing depth as they do. **/
	var Opaque = 1;

	/** After everything opaque, before blended meshes: grids, glass, particles. **/
	var Transparent = 2;

	/** After everything: gizmos, outlines, labels in the scene. **/
	var Overlay = 3;
}

/**
	Drawing of one's own in a 3D scene, with the GPU directly: a skinned
	character, a particle system, a terrain, a grid. ashui's meshes and a
	pass share the scene's colour and depth, so they hide each other where
	they should, and the scene is composited under the UI as a canvas is.

	```haxe
	class Characters implements ScenePass {
		public function stage() return Opaque;
		public function animated() return true;
		public function prepare(frame) { upload joint matrices; run skinning }
		public function draw(frame) { set pipeline and buffers; draw }
	}
	ctx.drawPass(characters);    // in a canvas's or <scene-kit>'s draw
	```

	`frame` (`ashui.core.render.ScenePassFrame`) gives the device and
	encoder, the layer's formats and size, the camera, and the `scene`
	buffer that ashui's own shaders light with: a shader that declares it
	and `@:import`s `ashui.shaders.Scene`, `Pbr` and `ColorSpace` sees and
	lights the scene as ashui's meshes do. The pass owns what it makes and
	frees it itself.
**/
interface ScenePass {
	/** When it draws. **/
	function stage():SceneStage;

	/** Whether it changes every frame: the scene is drawn again each frame the canvas is, rather than kept. **/
	function animated():Bool;

	/** Before the scene's render pass begins, `frame.encoder` free for passes of its own: uploads, compute, drawing into its own targets. **/
	function prepare(frame:ScenePassFrame):Void;

	/** In the scene's render pass, at its stage: pipelines set and draws made on `frame.encoder`. **/
	function draw(frame:ScenePassFrame):Void;
}
