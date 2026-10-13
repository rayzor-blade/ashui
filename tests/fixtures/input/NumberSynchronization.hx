import ashui.layout.LayoutTree;
import ashui.reactive.Owner;
import ashui.reactive.Signal;
import ashui.reactive.Watch;
import ashui.ui.Input;

/** A parent reset supersedes numeric formatting already waiting in the reactive queue. */
class NumberSynchronization {
	static function main():Void {
		ashui.theme.ThemeState.init(ashui.theme.themes.RestrainedTheme.bundle(),Dark);
		var tree=new LayoutTree(), stop:Void->Void=null, source=Signal.make(.25), number=Signal.make(.25);
		var input=Owner.root(tree,dispose -> {
			stop=dispose;
			new Watch(() -> source.get(),v -> number.set(v));
			return new Input({type:"number",valueAsNumber:number});
		});
		function drain():Void {
			for(_ in 0...32) if(!Watch.runQueued()) return;
			throw "Number input synchronization did not settle";
		}
		try {
			drain(); source.set(.374742181); Watch.runQueued(); source.set(0); drain();
			if(number.get()!=0 || input.value.get()!="0") throw "Queued formatting overrode the parent reset";
			input.value.set("1e"); drain();
			if(number.get()!=0 || input.value.get()!="1e") throw "Partial numeric input was lost";
			input.value.set("2.50"); drain();
			if(number.get()!=2.5 || input.value.get()!="2.50") throw "Manual numeric entry was not preserved";
			source.set(4.25); drain(); if(number.get()!=4.25 || input.value.get()!="4.25") throw "Parent numeric update was lost";
			source.set(7.125); source.set(7.5); drain();
			if(number.get()!=7.5 || input.value.get()!="7.5") throw "Latest numeric value did not win";
			Sys.println("numeric synchronization: queued reset, partial text, manual entry and latest parent value passed");
		} catch(e:Dynamic) {stop();tree.dispose();throw e;}
		stop();tree.dispose();
	}
}
