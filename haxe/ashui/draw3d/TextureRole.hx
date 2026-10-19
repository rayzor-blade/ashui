package ashui.draw3d;

/** What a material reads a texture as, which decides how it is stored. **/
enum abstract TextureRole(Int) to Int {
	/** Base or emissive colour: sRGB, BC1, or BC3 where it has alpha. **/
	var Color = 0;

	/** Metallic in blue and roughness in green: BC1. **/
	var Data = 1;

	/** Occlusion in red: BC4. **/
	var Occlusion = 2;

	/** A normal map's x and y in red and green: BC5; the shader works out z. **/
	var Normal = 3;

	/** The word a pre-compressed file's name carries for it: `colour.color.dds`. **/
	public function word():String
		return switch (cast this : Int) {
			case 0: "color";
			case 1: "data";
			case 2: "occlusion";
			case _: "normal";
		};
}
