package ashui.canvaskit;

/** Selected-object tool: world rotation rings or local scale handles. git-bug 6a3a68b. **/
enum abstract GizmoMode(Int) {
	var Orbit = 0;
	var Scale = 1;
}
