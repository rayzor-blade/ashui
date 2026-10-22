package ashui.components.code;

import ashui.reactive.Signal;

/** Only search input/options survive an unmounted editor; matches, controls and callbacks belong to its view. */
class CodeFindState {
	public final opened = Signal.make(false);
	public final replacing = Signal.make(false);
	public final query = Signal.make("");
	public final replacement = Signal.make("");
	public final matchCase = Signal.make(false);
	public final wholeWord = Signal.make(false);
	public final regex = Signal.make(false);
	public function new() {}
}
