package ashui.canvaskit;

/** Selected-object tool: world rotation/translation axes or local scale handles. **/
enum abstract GizmoMode(Int) {
	var Orbit = 0;
	var Scale = 1;
	var Move = 2;
}
