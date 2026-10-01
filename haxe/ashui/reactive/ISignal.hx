package ashui.reactive;

interface ISignal<T> {
    function get(): T;
    function set(val: T): Void;
    function computed<R>(computeFn: T->R): Computed<R>;
}

interface IComputed<T> {
    function get(): T;
}