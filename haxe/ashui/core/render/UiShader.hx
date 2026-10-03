package ashui.core.render;

/**
	A shader of ashui's renderer: a class whose HXSL source is its `static
	var SRC`, compiled to WGSL with the build. `UiFramework` gives each one
	`primitive`, the display-list record of the instance it draws, and
	`viewport`, the size of the frame it draws into.
**/
#if ashui_caribou
interface UiShader extends caribou.hxsl.Shader {}
#else
interface UiShader extends hlwgpu.hxsl.Shader {}
#end
