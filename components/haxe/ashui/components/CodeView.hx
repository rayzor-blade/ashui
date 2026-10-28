package ashui.components;

typedef CodeViewProps = ashui.components.CodeEditor.CodeEditorProps;

/**
	A read-only code view with highlighting, line numbers, and folding (e53597f).
	Accepts the source, grammar, and display options of `CodeEditor`.
	Selection, copying, and scrolling remain available; source edits are disabled.
**/
class CodeView extends CodeEditor {
	override function editable():Bool return false;
}
