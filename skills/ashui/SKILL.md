---
name: ashui
description: Build, style, debug and test native UI with ashui, the Haxe UI framework (HXX templates, Solid-style signals, Tailwind-style classes over theme tokens, CSS, windows, web). Use when the task touches ashui code, `ashui.*` imports, `.hx` files with HXX markup, `class="…"` utility strings in Haxe, or a UI built on `WindowedApp`. Maps what you already know from React/JSX, SolidJS and Tailwind onto ashui's API, and lists where it differs.
---

# ashui for agents

ashui is a native, reactive UI framework for Haxe. If you know **JSX**, **SolidJS** and **Tailwind**, most of it transfers, with Haxe types and a few deliberate differences. This file is the map. Where it says "check", read the named source rather than guessing.

## The mental model (30 seconds)

- **HXX** is JSX for Haxe: typed, lowercase kebab-case tags, compiled by a macro. `<div>`, `<text>`, `<button>`, `<input>`, `<dialog>`… are built in (HTML-like); imported components add tags (`Card` brings `<card>`, `<card-header>`).
- **No virtual DOM, no re-render.** Like Solid: a component's `render` runs **once**; fine-grained **signals** update exactly the bound attributes and text. Never write React-style "rebuild on state change" or polling.
- **Signals are objects with `get()` / `set()`**, not tuples. Reading one inside an HXX binding, a `computed` or a `watch` records the dependency.
- **Tailwind classes are compiled and checked.** `class="p-4 bg-surface rounded-lg"` is resolved at compile time over the **theme's tokens**; a typo is a compile error. They follow the theme (light/dark) without rebuilding.
- **CSS also works** (real cascade, selectors, `var()`, `@media`, transitions, keyframes). Utility classes beat stylesheet rules.
- Runs on **Ash** (HashLink bytecode) natively, with a wasm build for pages. Layout is **Blinc** (flexbox/grid via taffy), drawing is wgpu.

## Cheat sheet: JSX → HXX

| JSX / React | ashui HXX |
| --- | --- |
| `className="…"` | `class="…"` |
| `<Button>` (a component) | `<button>`; `MyCard` is `<my-card>`; `ui.MyCard` is `<ui.my-card>`. Import the module to get the tag. |
| `{expr}` | `${expr}` for text and children; `attr={expr}` for attributes |
| `onClick={e => …}` | `onClick={_ -> …}` (Haxe lambda) |
| `useState` | `var n = signal(0);` then `n.get()` / `n.set(v)` |
| `useMemo` | `var d = computed(() -> n.get() * 2);` |
| `useEffect` | `watch(() -> read(), v -> react(v))` (see below) |
| `useRef` | `var r = new Ref<Div>();` and `<div ref={r}>`; read with `r.get()` (may be null) |
| conditional `cond && <A/>` | `<if {cond}><a/><else><b/></if>` |
| `list.map(x => <li/>)` | `<for {x in list}><li>${x}</li></for>` (array, or a signal/computed of one) |
| `children` | `children` field of a `Component` |
| `style={{…}}` | `style={s}` with an `ashui.style.Style`, or layout attributes: `width={420} gap={8} flexDirection={Column}` |
| `key` | none; `<for>` keeps item objects it already has by `==` |
| fragments | none needed; a branch/loop body of several elements is wrapped in a `<div>` (watch your layout) |

Text directly inside a `<div>` becomes a `<text>`. `<switch>` and `<let>` do not exist (compile error). `bg={…}` is the background attribute; any other attribute name is the node property of that name.

## Cheat sheet: SolidJS → ashui

| Solid | ashui |
| --- | --- |
| `createSignal(0)` → `[get, set]` | `signal(0)` → object; `s.get()`, `s.set(v)` |
| `createMemo(fn)` | `computed(fn)` — **it does not cut off equal values**: dependents re-run on every recompute. To stop propagation when a value is unchanged, `new Watch(() -> value(), v -> sig.set(v))` (a watch reacts only when its value differs) and read `sig`. |
| `createEffect(fn)` | `watch(read, react)`: `read` tracks dependencies and **must only read**; `react` runs once at creation, then at the **next layout flush** when the value changed. Several writes before a flush give one reaction with the latest value. `react` may set signals and build/remove UI. |
| `onCleanup(fn)` | `Owner.onCleanup(fn)` |
| `createRoot(fn)` | `Owner.root(tree, stop -> element)` (tests and tools; `WindowedApp.run` does it for you) |
| `<Show when>` / `<Else>` | `<if {cond}>…<else>…</if>` |
| `<For each>` | `<for {x in list}>` |
| `<Switch>/<Match>` | not available; nest `<if>` or compute a value |
| stores, context | none that I found; pass signals as props or share them from a module/model class (check `ashui.reactive` before assuming) |
| props are getters | a prop typed `IntoReactive<T>` follows what its attribute expression reads; other props are read once |

Imports: `import ashui.reactive.Reactive;` gives the `signal`, `computed` and `watch` shortcuts. `Owner` scopes elements, computeds, watches and cleanup: removing UI (an `<if>` branch, a `<for>` item, a component) disposes its bindings. Signals may outlive a scope.

### The reactivity rules that cause real bugs

1. **`${f()}` is frozen.** A text or attribute interpolation re-evaluates only when it reads a signal **itself, in plain sight**: `${count.get()}` yes, `${format()}` where `format` reads signals no. Wrap it: `var t = computed(() -> format()); … ${t.get()}`.
2. **An `<if>`/`<for>` body is built inside its branch.** What it shows must be created there: make it a **call** (`<if {x}>${panel()}</if>`), not a variable declared before the tag (that one is never disposed or rebuilt). The condition itself runs reactively, so `${m.flag()}` is fine in it.
3. A `watch`'s `react` runs **after** that flush's canvas draws are recorded. Changing non-signal state a canvas draws from `react` shows one selection late; apply the state inside the draw instead.
4. `computed` never cuts off (above). Use `watch` + a signal to dedupe.
5. A mutable flag meaning "my ticker is running" goes stale when the scheduler drops the ticker; ask the `Ticker` (`ticker.running`).
6. State read right after a native call that the web build answers asynchronously (e.g. `play()` then `state()`) is the old state.

## Hello world and build

```haxe
import ashui.app.WindowedApp;
import ashui.reactive.Reactive;

class Hello {
    static function main() {
        WindowedApp.run({title: "Hello ashui", width: 420, height: 240}, () -> {
            var count = signal(0);
            var label = computed(() -> 'Clicked ${count.get()} times');
            return <div class="flex flex-col items-center justify-center gap-4 p-6 bg-background" width={420} height={240}>
                <text class="text-2xl font-semibold">Hello, ashui</text>
                <button type="button" onClick={_ -> count.set(count.get() + 1)}>${label.get()}</button>
            </div>;
        });
    }
}
```

`build.hxml` (both macros are required; `-lib ashui` supplies them via `extraParams.hxml` too):

```hxml
-lib ashui
-lib ashui-components      # built-in controls: Button, Card, Dialog, Input, CodeEditor, …
--macro ashui.core.render.UiFramework.register()
--macro ashui.ui.Markup.enable()
-main Hello
-hl bin/hello.hl
```

`haxe build.hxml && ash --preset application bin/hello.hl`. Needs Haxe 4.3.6+ and the Ash runtime. **Quote macro arguments in zsh** (`--macro 'ashui.ui.Markup.enable()'`): unquoted `()` makes the whole haxe command silently do nothing. Window code compiles only with `-D ashui_window`.

## Components

```haxe
typedef BadgeProps = {?variant:String, ?id:String}

class Badge extends ashui.ui.Component<BadgeProps> {
    @:state var shown:Bool = true;                  // reactive field; it needs an explicit type
    function render():ashui.layout.Element
        return <div class="px-2 rounded-full bg-primary">${children}</div>;
}
```

- `render` runs once, under the component's own owner. Props are a typedef; optional ones are `?name`. A prop typed `IntoReactive<Bool>` accepts a constant, a signal or a computed.
- Editable controls take **signals** for `value`, `checked`, `open`: user edits write back to the signal, your writes update the control: `<toggle-switch checked={on} />`.
- Built-in controls follow HTML: `<button>` focuses and activates with Enter/Space and submits forms by default (use `type="button"`); `<dialog>` is modal with focus handling; `<form method="dialog">` validates and closes its dialog. See `docs/elements.md`.
- A panel built later (inside an `<if>`) is fine, including `<dialog-content>`.

## Styling

**Utility classes (`class="…"`)** — Tailwind names over **theme tokens**, not Tailwind's palette:

- Colors are tokens: `bg-background`, `bg-surface`, `bg-surface-elevated`, `bg-primary`, `text-secondary`, `border-border`, `bg-primary/50` (opacity). There is **no** `bg-blue-500`.
- Spacing steps follow Tailwind's scale (`p-4`, `gap-3`, `w-1/2`, `w-full`); `rounded-2xl`, `shadow-md`, `text-lg font-semibold`, `flex flex-col items-center justify-between grow`, `overflow-hidden`, `overflow-auto` (a scroll container), `absolute`, `z-10`.
- **Variants** `hover: focus: focus-visible: active: disabled: dark: group-hover: peer-…`: the string also needs the **plain class for the same property**, or the value is a compile error (`bg-surface hover:bg-primary`). Add `transition-colors` for the change to animate.
- Not Tailwind: `bg-glass` + `glass-*` (liquid glass), `corner-squircle`, `fade-*`, `ease-spring`.
- Arbitrary values exist only for `[clip-path:…]` and `[glass-*:…]` (`w-[317px]` is a compile error: "use a token or an attribute otherwise"). For one-off numbers use attributes (`width={317}`) or CSS.
- The full list and rules are the header of `haxe/ashui/style/Tw.hx`.

**Attributes** set node properties directly and win over classes: `width={420} height={240} gap={8} padding={24} flexDirection={Column} position={Absolute} left={150}`. Numbers are layout px. A `<div>` lays out as a **row** by default (give wrappers `flex-col` / `flexDirection={Column}`), unlike a block element.

**CSS** — `Css.add(CompiledCss.file("app.css"))` (parsed and embedded at compile time); declare class names for compile-time checking with `-D ashui_css=app.css`. Supports selectors, inheritance of typography, custom properties and theme variables (`var(--primary)`), `@media` (including `prefers-color-scheme`), `:hover/:active/:focus-visible/:disabled/:checked`, transitions and keyframes. Details: `docs/css.md`.

**Do not select utility classes from a stylesheet.** `class="overflow-auto"` leaves no `overflow-auto` class for a selector; add your own class (`scrolls`) and select that.

**Themes**: three built in (Restrained, Hybrid default, Expressive), each light/dark, following the system. Tokens (`--primary`, `--surface`, `--radius-lg`) and motion/shape tokens drive classes and controls. `docs/themes.md`.

## Elements and controls you will reach for

Built-ins follow HTML names, import-free: `<div>`, `<span>`, `<p>`, `<h1>`…, `<a>`, `<ul>/<ol>/<li>`, `<button>`, `<input>`, `<textarea>`, `<select>`, `<label>`, `<form>`, `<dialog>`, `<details>`, `<table>` and its parts, `<progress>`, `<meter>`, `<svg>`, `<canvas>` (2D drawing), and ashui's own `<text>`. `<img>` needs `src={bitmap}`. From `ashui-components`: Card, Dialog, Tabs, Accordion, Select, Slider, ToggleSwitch, NumberInput, Calendar, Command, Tooltip, TreeView, CodeEditor, CodeDiff, and more (`components/README.md`). 3D and scenes: `ashui-canvaskit` (`<scene-kit>`). Audio/video: `ashui-media`. Icons: `ashui-icons` is a **separate package** (Remix, licence reasons): components never depend on it; pass icons as props.

Big lists and panels: only mount what is shown. `CodeEditor`/`CodeDiff` pool their rows; `Select` takes `virtualRowHeight`; build a heavy panel on first open (`<if {opened.get()}>${panel()}</if>`). A styled control costs real memory; thousands of mounted controls is the thing to avoid.

## Windows, menus, web

`WindowedApp.run({title, width, height}, build)` runs the loop; more windows with `WindowedApp.open(...)`, native application menus and file dialogs in `docs/windows.md`. A page build (wasm) is described in `docs/web.md`; `?debug` on the page address logs frame statistics to the browser console, `?log` also shows the log on the page.

## Verify your work (do this, don't guess)

1. **Compile**: `haxe build.hxml`. Typed HXX means most mistakes are compile errors, including unknown props, bad classes and missing variant base classes.
2. **See it**: render a scene to a PNG instead of describing it: write a scene class (see `tools/snapshot/scenes/*.hx`, e.g. `CodeEditorZones.hx`), run `sh tools/snapshot/run.sh path/to/Scene.hx`, and **look at** `.ashui/snapshots/<Name>-*.png`. `SCHEME=light` renders light; `Snapshot.sequence` takes callbacks to drive state between frames. Kill any interactive window you start.
3. **Test headless**: fixtures build a tree under `Owner.root(tree, …)` and drive it: `Css.update(); tree.flush(); tree.computeLayout(root.node, w, h);` a few times, then assert (`Css.query(tree, id, "#x")`, bounds). Add one under `tests/fixtures/…` and register it in `tests/run.sh`. `sh tests/run.sh` runs everything; **a crashing fixture prints "Uncaught exception", not FAIL**: check the exit code and the "ALL PASSED" count. `sh tests/run.sh render` runs the pixel tests.
4. **Frame stats**: `ASHUI_FRAME_STATS=1` prints frame and loop lines each second.

Working on ashui itself (not an app): the repo's scripts expect sibling checkouts next to it (`../ash`, `../hlwgpu`, `../hlwindow`).

## Pitfalls checklist

- `${f()}` that reads signals is frozen: wrap in `computed`.
- `<if>` body made before the tag: make it a call.
- Variant class without its plain base class: compile error.
- `bg-blue-500`-style palette classes: use theme tokens.
- Selecting `.overflow-auto` etc. in CSS: add your own class.
- `computed` expecting equality cutoff: it has none.
- `pointerEvents={None}` on a parent also hid its `Auto` children from input (git-bug 0fe11ba when written; test before relying on either behaviour); for a full-size overlay use a zero-size root with absolutely placed children.
- `var()` inside a gradient's color stop raised a null access (git-bug 07b31c3 when written): write literal colors per scheme.
- A `<div>` is a row; `<if>`/`<for>` bodies of several elements add a wrapping `<div>`.
- Hover/focus state comes from `Interaction`; don't poll the pointer.
- Do not add per-element maps, polling loops or "rebuild everything" refreshes: the framework is push-based.

## Where to look

`README.md` (overview, reactive state), `docs/css.md`, `docs/themes.md`, `docs/elements.md`, `docs/windows.md`, `docs/web.md`, `docs/code-editor.md`, `docs/code-diff.md`, `components/README.md`, `haxe/ashui/ui/Hxx.hx` (the HXX rules, in its header), `haxe/ashui/ui/Component.hx`, `haxe/ashui/style/Tw.hx`, `apps/dashboard/` (a full app), `tools/snapshot/` and `tests/fixtures/` (examples of every API).
