package ashui.media;

/** Aspect-preserving contain (default), center-cropped cover, or stretched fill. **/
enum abstract VideoFit(String) from String to String {
	var Contain = "contain";
	var Cover = "cover";
	var Fill = "fill";
}
