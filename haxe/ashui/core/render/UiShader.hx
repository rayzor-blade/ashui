package ashui.core.render;

/**
	A shader of ashui's renderer. `UiFramework` gives each one the display-list
	primitive it draws, as instance input, and the frame it draws into.
**/
#if ashui_caribou
interface UiShader extends caribou.hxsl.Shader {}
#else
interface UiShader extends hlwgpu.hxsl.Shader {}
#end
