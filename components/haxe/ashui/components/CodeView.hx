package ashui.components;

/**
	Selectable code with highlighting, line numbers and folding (e53597f).
	Accepts the same source, grammar and display options as CodeEditor;
	selection/copy/scroll stay available, and source edits are refused.
**/
class CodeView extends CodeEditor {
	override function editable():Bool return false;
}
