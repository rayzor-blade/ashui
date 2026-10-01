package ashui.reactive;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

@:forward(get, set, computed)
abstract Signal<T>(ISignal<T>) from ISignal<T> to ISignal<T> {
    
    /**
     * Statically routes the allocation to the optimal C ABI primitive
     * based on the type of the `initialValue`.
     */
    macro public static function make(initialValue: Expr): Expr {
        var type = Context.typeof(initialValue);
        
        switch (Context.follow(type)) {
            // 1. Handle Class Instances (String, Array)
            case TInst(t, _):
                switch (t.get().name) {
                    case "String": 
                        return macro new ashui.reactive.SignalString($initialValue);
                    case "Array":  
                        return macro new ashui.reactive.SignalArray($initialValue);
                    default:       
                        return macro new ashui.reactive.SignalDynamic($initialValue);
                }

            // 2. Handle Primitives (Int, Float, Single, Bool)
            case TAbstract(t, _):
                switch (t.get().name) {
                    case "Int":    
                        return macro new ashui.reactive.SignalI32($initialValue);
                    case "Single": 
                        return macro new ashui.reactive.SignalF32($initialValue);
                    case "Float":  
                        return macro new ashui.reactive.SignalF64($initialValue);
                    case "Bool":   
                        return macro new ashui.reactive.SignalBool($initialValue);
                    default:       
                        return macro new ashui.reactive.SignalDynamic($initialValue);
                }

            // 3. Fallback (Anonymous Structs, Typedefs that follow to dynamic, Enums)
            default:
                return macro new ashui.reactive.SignalDynamic($initialValue);
        }
    }
}

@:forward(get)
abstract Computed<T>(IComputed<T>) from IComputed<T> to IComputed<T> {}