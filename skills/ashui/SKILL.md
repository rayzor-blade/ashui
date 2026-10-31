---
name: ashui
description: Build, style, debug and test native UI with ashui, the Haxe UI framework (HXX templates, Solid-style signals, Tailwind-style classes over theme tokens, CSS, windows, web). Use when the task touches ashui code, `ashui.*` imports, `.hx` files with HXX markup, `class="…"` utility strings in Haxe, or a UI built on `WindowedApp`. Maps what you already know from React/JSX, SolidJS and Tailwind onto ashui's API, and lists where it differs.
---

# ashui for agents

ashui is a native, reactive UI framework for Haxe. This guide maps JSX,
SolidJS and Tailwind concepts to its APIs. Check the named sources when
behavior or support is unclear.

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

Text directly inside a `<div>` becomes a `<text>` element. `<switch>` and
`<let>` are unsupported. `bg={…}` sets `Prop.Background`; other attributes
map to the node property with the same name.

## Cheat sheet: SolidJS → ashui

| Solid | ashui |
| --- | --- |
| `createSignal(0)` → `[get, set]` | `signal(0)` → object; `s.get()`, `s.set(v)` |
| `createMemo(fn)` | `computed(fn)` propagates each recomputation, even if the result is equal. To suppress unchanged values, use `new Watch(() -> value(), v -> sig.set(v))` and read `sig`. Watches react only when their result changes. |
| `createEffect(fn)` | `watch(read, react)`: `read` tracks dependencies and **must only read**; `react` runs once at creation, then at the **next layout flush** when the value changed. Several writes before a flush give one reaction with the latest value. `react` may set signals and build/remove UI. |
| `onCleanup(fn)` | `Owner.onCleanup(fn)` |
| `createRoot(fn)` | `Owner.root(tree, stop -> element)` (tests and tools; `WindowedApp.run` does it for you) |
| `<Show when>` / `<Else>` | `<if {cond}>…<else>…</if>` |
| `<For each>` | `<for {x in list}>` |
| `<Switch>/<Match>` | not available; nest `<if>` or compute a value |
| stores, context | Pass signals as props or share a model/module. Check `ashui.reactive` for available state APIs before assuming store or context support. |
| props are getters | Props typed `IntoReactive<T>` track their attribute expressions. Other props are read once. |

Import `ashui.reactive.Reactive` for `signal`, `computed` and `watch`.
`Owner` manages elements, computeds, watches and cleanup callbacks.
Components, `<if>` branches and `<for>` items each have an owner.
Removing them disposes their bindings. Signals can outlive an owner.

### The reactivity rules that cause real bugs

1. **Interpolation detects direct signal reads.** `${count.get()}` updates reactively.
   A helper such as `${format()}` does not expose its internal reads to the macro.
   Wrap it in `var t = computed(() -> format())`, then interpolate `${t.get()}`.
2. **Build conditional and repeated elements inside their branch.** Use a builder call,
   such as `<if {x}>${panel()}</if>`. An element built before the branch outlives it
   and is not recreated on reentry. Conditions are tracked at runtime, so calls
   such as `${m.flag()}` work there.
3. **Watch reactions run after canvas draws are recorded for that flush.** A reaction
   that changes non-signal drawing state can leave the canvas one update behind.
   Apply that state inside the draw callback.
4. **Computeds propagate each recomputation.** Use a watch feeding a signal when
   unchanged values should stop propagation.
5. **Use `ticker.running` for ticker state.** A separate flag becomes stale if the
   scheduler removes a finished or failed ticker.
6. **Web native calls may complete asynchronously.** Reading state immediately after
   calls such as `play()` can return the previous state.

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

Run `haxe build.hxml && ash --preset application bin/hello.hl`.
Requires Haxe 4.3.6+ and Ash. Quote macro arguments in zsh, for example
`--macro 'ashui.ui.Markup.enable()'`; unquoted parentheses can prevent the
command from running correctly. Window code requires `-D ashui_window`.

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
- See `docs/css.md` for utility classes and rules. `haxe/ashui/style/Tw.hx` implements them.

**Attributes** set node properties directly and win over classes: `width={420} height={240} gap={8} padding={24} flexDirection={Column} position={Absolute} left={150}`. Numbers are layout px. A `<div>` lays out as a **row** by default (give wrappers `flex-col` / `flexDirection={Column}`), unlike a block element.

**CSS** — `Css.add(CompiledCss.file("app.css"))` (parsed and embedded at compile time); declare class names for compile-time checking with `-D ashui_css=app.css`. Supports selectors, inheritance of typography, custom properties and theme variables (`var(--primary)`), `@media` (including `prefers-color-scheme`), `:hover/:active/:focus-visible/:disabled/:checked`, transitions and keyframes. Details: `docs/css.md`.

**Do not select utility classes from a stylesheet.** `class="overflow-auto"` leaves no `overflow-auto` class for a selector; add your own class (`scrolls`) and select that.

**Themes**: three built in (Restrained, Hybrid default, Expressive), each light/dark, following the system. Tokens (`--primary`, `--surface`, `--radius-lg`) and motion/shape tokens drive classes and controls. `docs/themes.md`.

## Elements and controls you will reach for

Built-in tags need no imports: `<div>`, `<span>`, `<p>`, headings, links, lists,
buttons, inputs, forms, dialogs, tables, progress, meters, SVG and 2D canvas.
Ashui also supplies `<text>`. `<img>` accepts `src={bitmap}`.
`<surface source={pixelSurface} fit={Contain}>` draws a `PixelSurface`, RGBA pixels a program
replaces (`write` a rectangle, `writeAll` the whole); only the changed rectangle is uploaded.
Any element takes `onTouchStart`/`onTouchMove`/`onTouchEnd`/`onTouchCancel` (a touch's events follow
where it began), and a pointer-down handler can call `e.capturePointer()` to get every move and the
release until the button comes up.
A `<canvas sketch={mySketch}>` runs `setup`/`draw(ctx, t, dt)` every frame; `ctx.events` holds every input
event since the last frame in order, `ctx.mouseX`/`mouseIsPressed`/`keyIsDown` the latest state (`docs/sketch.md`).

Import styled controls from `ashui-components`; see `components/README.md`.
Use `ashui-canvaskit` for `<scene-kit>` and `ashui-media` for audio/video.
`ashui-icons` is a separate Remix package. Components accept icons as props
and do not depend on an icon set.

Mount only visible or active content. `CodeEditor` and `CodeDiff` pool rows;
`Select` supports `virtualRowHeight`. Build heavy panels on first use with
`<if {opened.get()}>${panel()}</if>`. Mounted controls consume native and
language-side resources even when hidden.

## Windows, menus, web

`WindowedApp.run({title, width, height}, build)` starts the application loop.
Use `WindowedApp.open(...)` for additional windows. `docs/windows.md` covers
window-local services, application menus and file dialogs.
`docs/web.md` covers browser builds. Add `?debug` to log browser frame
statistics, or `?log` to display output on the page.

## Verify your work

Choose checks for the change. Documentation edits need accurate references, working
links and valid examples. UI or runtime changes also need the relevant build and
behavior checks below.

1. **Compile**: `haxe build.hxml`. Typed HXX means most mistakes are compile errors, including unknown props, bad classes and missing variant base classes.
2. **See it**: render a scene to a PNG instead of describing it: write a scene class (see `tools/snapshot/scenes/*.hx`, e.g. `CodeEditorZones.hx`), run `sh tools/snapshot/run.sh path/to/Scene.hx`, and **look at** `.ashui/snapshots/<Name>-*.png`. `SCHEME=light` renders light; `Snapshot.sequence` takes callbacks to drive state between frames. Kill any interactive window you start.
3. **Test headless**: fixtures build a tree under `Owner.root(tree, …)` and drive it: `Css.update(); tree.flush(); tree.computeLayout(root.node, w, h);` a few times, then assert (`Css.query(tree, id, "#x")`, bounds). Add one under `tests/fixtures/…` and register it in `tests/run.sh`. `sh tests/run.sh` runs everything; **a crashing fixture prints "Uncaught exception", not FAIL**: check the exit code and the "ALL PASSED" count. `sh tests/run.sh render` runs the pixel tests.
4. **Frame stats**: `ASHUI_FRAME_STATS=1` prints frame and loop lines each second.
   `ASHUI_FRAME_LATENCY=1|2` and `ASHUI_PRESENT_MODE=fifo|fifo-relaxed|mailbox|immediate` override `WindowedApp.frameLatency` and `preferredPresentMode`; Metal offers Fifo and Immediate, latency 1 to 2.

Working on ashui itself (not an app): the repo's scripts expect sibling checkouts next to it (`../ash`, `../hlwgpu`, `../hlwindow`).

## Documentation

Start API comments with the purpose. Use short sentences and explicit names.
Keep units, ownership, timing and error behavior clear. Put long reference
material in a guide and link to it from hover text. Use current HXX syntax in
examples, and check issue status before documenting a workaround.

## Pitfalls checklist

- `${f()}` that reads signals is frozen: wrap in `computed`.
- `<if>` body made before the tag: make it a call.
- Variant class without its plain base class: compile error.
- `bg-blue-500`-style palette classes: use theme tokens.
- Selecting `.overflow-auto` etc. in CSS: add your own class.
- `computed` expecting equality cutoff: it has none.
- `pointerEvents={None}` suppresses descendant input, including children set to `Auto` (git-bug 0fe11ba). For overlays, use a zero-size root with absolutely positioned children.
- `var()` in gradient color stops is tracked in open issue 07b31c3. Use literal colors per scheme until that issue is resolved.
- A `<div>` is a row; `<if>`/`<for>` bodies of several elements add a wrapping `<div>`.
- Hover/focus state comes from `Interaction`; don't poll the pointer.
- Do not add per-element maps, polling loops or "rebuild everything" refreshes: the framework is push-based.

## Where to look

`README.md` (overview, reactive state), `docs/css.md`, `docs/themes.md`, `docs/elements.md`, `docs/windows.md`, `docs/web.md`, `docs/code-editor.md`, `docs/code-diff.md`, `components/README.md`, `haxe/ashui/ui/Hxx.hx` (the HXX rules, in its header), `haxe/ashui/ui/Component.hx`, `haxe/ashui/style/Tw.hx`, `apps/dashboard/` (a full app), `tools/snapshot/` and `tests/fixtures/` (examples of every API).
