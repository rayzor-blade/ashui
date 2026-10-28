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

/**
	A pass that contributes to bloom. In the scene's glow pass, `drawGlow`
	draws the pass again with `frame.encoder`, through
	`frame.glowPipelineBuilder`, writing its exposed light without tone
	mapping. Whatever is brighter than the bloom's threshold then glows.
	A pass that does not implement this does not glow.
**/
interface GlowCaster {
	function drawGlow(frame:ScenePassFrame):Void;
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
	Adds custom GPU drawing to a 3D scene, such as characters, particles,
	terrain or a grid. Custom passes share scene color and depth with Ashui
	meshes, so occlusion works between them. The scene composites beneath the UI.

	Implement `stage`, `animated`, `prepare` and `draw`, then submit the pass
	with `ctx.drawPass(pass)` from a canvas or `<scene-kit>` draw callback.

	`ScenePassFrame` provides the device, encoder, target formats, dimensions,
	camera and shared `scene` buffer. Shaders can declare that buffer and
	import `ashui.shaders.Scene`, `Pbr` and `ColorSpace` to use the same
	lighting as built-in meshes.

	The pass owns its resources and must release them itself.
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
