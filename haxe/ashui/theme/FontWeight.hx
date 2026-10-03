package ashui.theme;

/** A font weight of the theme's type, as CSS numbers weights. **/
enum abstract FontWeight(Int) to Int {
	var Thin = 100;
	var ExtraLight = 200;
	var Light = 300;
	var Normal = 400;
	var Medium = 500;
	var Semibold = 600;
	var Bold = 700;
	var ExtraBold = 800;
	var Black = 900;
}
