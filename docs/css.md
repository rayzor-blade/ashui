# CSS and utility classes

ashui styles native elements with CSS selectors, inherited typography,
custom properties, media queries and motion. HXX can combine application
CSS classes with typed Tailwind-style utility classes. Both read values from the
active [theme](themes.md).

## Start with a compiled stylesheet

Follow the [quick setup](https://github.com/rayzor-blade/ashui#quick-setup).
Save `app.css` beside `StyledApp.hx`:

```css
.page {
    flex-direction: column;
    justify-content: center;
    padding: var(--space-6);
    background: var(--background);
    color: var(--text-primary);
}

.surface {
    flex-direction: column;
    gap: var(--space-3);
    padding: var(--space-6);
    border: 1px solid var(--border);
    border-radius: var(--radius-xl);
    background: var(--surface);
    box-shadow: var(--shadow-md);
}

.surface .title { font-size: var(--text-xl); font-weight: 600; }
.surface .description { color: var(--text-secondary); }
```

```tsx
import ashui.app.WindowedApp;
import ashui.components.Button;
import ashui.css.CompiledCss;
import ashui.css.Css;

class StyledApp {
    static function main() {
        Css.add(CompiledCss.file("app.css"));
        WindowedApp.run({title: "Styled app", width: 520, height: 340}, () ->
            <div class="page" width={520} height={340}>
                <div class="surface">
                    <text class="title">CSS meets HXX</text>
                    <text class="description">Colors, shape and spacing follow your theme.</text>
                    <button type="button" class="mt-2">Continue</button>
                </div>
            </div>
        );
    }
}
```

Use this `build.hxml`:

```hxml
-lib ashui
-lib ashui-components
-D ashui_css=app.css

--macro ashui.core.render.UiFramework.register()
--macro ashui.ui.Markup.enable()

-main StyledApp
-hl bin/app.hl
```

Run `haxe build.hxml`, then `ash --preset application bin/app.hl`.

`-D ashui_css=app.css` declares the stylesheet's class names to the compiler,
including classes in imported files. HXX accepts them alongside utilities
and reports misspelled names at their location in the source. Multiple
files use a comma-separated list: `-D ashui_css=app.css,widgets.css`.
Declaring a file checks its names and syntax; `Css.add(...)` installs its
rules in the running application.

## Compiled and runtime stylesheets

[`CompiledCss.file`](https://github.com/rayzor-blade/ashui/blob/main/haxe/ashui/css/CompiledCss.hx)
parses a stylesheet during Haxe compilation and emits its rules, selectors,
media queries and keyframes as typed data. Startup constructs those objects
without parsing the CSS text. Theme variables, selector matching and state
changes still resolve at runtime.

- Paths passed to `CompiledCss.file` are relative to the calling Haxe file.
- Paths in `ashui_css` resolve on the class path or from the compiler's
  working directory. Local `@import` paths resolve from the importing CSS file.
- Syntax and selector errors are compile errors at the CSS line and column;
  parser warnings become compiler warnings. Imported files retain their
  own diagnostic locations.
- Both the stylesheet and its imports are registered as compiler dependencies.
  Their class names are also made available to HXX when the macro runs.

| API | Use |
| --- | --- |
| `Css.add(CompiledCss.file("app.css"))` | Embed and install application CSS. |
| `Css.useLibrary("my-controls", CompiledCss.file("controls.css"))` | Install a library's compiled CSS once, below application styles. |
| `Css.load(cssText)` | Parse and install CSS text at runtime. |
| `Css.loadFile(path)` | Read and parse a runtime file. With `-D ashui_hot_reload`, the renderer reloads it and its imports when changed. |
| `Css.remove(sheet)` / `Css.replace(previous, next)` | Remove or replace a loaded stylesheet. |

`Css.load` and `Css.loadFile` return a `Stylesheet` with parsing diagnostics.
Property application problems, such as an unsupported value, are collected
in `Css.problems`. Embedding CSS keeps runtime `url()` assets as references;
package those assets with your application.

## Cascade, inheritance and states

Stylesheets are installed in this order: built-in element defaults,
component library CSS, then application CSS. Within stylesheet rules, each
property is resolved by `!important`, selector specificity, then source
order. Later sheets win ties. Component CSS is inserted below application
styles even when the component is first created afterward.

An element's own settings take precedence over stylesheet rules, including
`!important`. HXX applies utility classes first, then `style={...}`, then
explicit attributes such as `padding={24}`. This lets a local element
override a shared stylesheet deliberately.

Typography inherits through the element tree: font family, size, weight,
style, line height, letter spacing and alignment. Color also reaches the
text inside a container. Custom properties resolve from the element and
its ancestors, then `:root` rules, then theme tokens. Use a fallback with
`var(--card-padding, var(--space-4))`.

| Feature | Examples |
| --- | --- |
| Selectors and relationships | `.surface`, `#player`, `button`, `.surface > .title`, `.row + .row`, `[data-variant="outline"]` |
| Structural selectors | `:first-child`, `:nth-child(2n)`, `:is()`, `:where()`, `:not()`, `:has()` |
| Interaction and form states | `:hover`, `:active`, `:focus-visible`, `:focus-within`, `:disabled`, `:checked`, `:invalid` |
| Responsive rules | `@media (max-width: 600px)`, `@media (prefers-color-scheme: dark)` |
| Organization | Local `@import`, nested rules with `&`, `@mixin` and `@include` |
| Native layout and rendering | Flex and grid, spacing, borders, transforms, shadows, filters, clipping and masks |

State selectors read the controls' interaction state. Rules are reapplied
at the next layout flush when relevant states, classes, structure, viewport
conditions or theme values change. Compiled CSS retains this behavior.

Components expose their parts through `ui-*` classes, variants through
`data-*` attributes, and styling values through custom properties. For
example, this adjusts buttons within `.page`:

```css
.page { --ui-button-radius: var(--radius-xl); }
.page .ui-button[data-variant="outline"] { border-color: var(--primary); }
```

See the [component stylesheet](https://github.com/rayzor-blade/ashui/blob/main/components/css/components.css)
for part names and customization variables, and
[`Properties`](https://github.com/rayzor-blade/ashui/blob/main/haxe/ashui/css/Properties.hx)
for the supported native properties and values.

## How tokens generate utility classes

[`Tw`](https://github.com/rayzor-blade/ashui/blob/main/haxe/ashui/style/Tw.hx)
reads the framework's token enums during compilation and builds a class
vocabulary from their keys. It combines each family with its utility
prefixes and emits typed property setters or inline CSS declarations.

| Token key | Utilities | Value source |
| --- | --- | --- |
| `SpacingToken.Space4` | `p-4`, `px-4`, `m-4`, `gap-4`, `w-4`, `size-4` | The theme's spacing step. |
| `ColorToken.SurfaceElevated` | `bg-surface-elevated`, `border-surface-elevated` | The token's field name, converted to kebab case, selects its color. |
| `RadiusToken.Default` / `Xxl` | `rounded` / `rounded-2xl` | The theme's corner radii. |
| `ShadowToken.Md` | `shadow-md` | The theme's shadow stack. |
| `TypographyToken.TextLg` / `FontSemibold` | `text-lg` / `font-semibold` | Typography values, inherited by child text. |
| `AnimationToken.DurationNormal` | `duration-normal` | The theme's duration in a transition. |
| `EasingToken.Spring` | `ease-spring` | The theme's spring curve in a transition. |

Spacing, color, radius, shadow and typography classes are derived from the
token enums; timing utilities map to `AnimationToken` and `EasingToken`.
[`TokenKeys`](https://github.com/rayzor-blade/ashui/blob/main/haxe/ashui/theme/TokenKeys.hx)
checks that string token keys match their token record fields. Class names
are determined by those keys at compile time; a theme bundle supplies the
values for them at runtime.

For example, `p-4` binds padding to `Themed.spacing(SpacingToken.Space4)`;
`bg-surface` binds the background to `Themed.brush(ColorToken.Surface)`.
Those bindings read the theme's reactive revision. Switching themes or
schemes updates their values without rebuilding the element. Text utilities
declare inherited CSS values such as `font-size: var(--text-lg)`.

Layout keywords such as `flex-col` and `items-center` use fixed values.
Utilities also cover gradients, opacity, transforms and effects. For
example, `bg-primary/20` scales the theme color's alpha; `bg-glass` with
`glass-blur-2 glass-tint-white/10 glass-aberration-30` sets the same
`background: glass` and `glass-*` properties available in CSS.

```tsx
<div class="flex flex-col gap-3 p-6 rounded-xl bg-surface shadow-md
    hover:bg-surface-elevated transition duration-normal ease-state">
    <text class="text-lg font-semibold">Theme-aware utilities</text>
</div>
```

Use the [theme guide](themes.md) to change the values behind these classes.
Application-specific styles go in declared CSS classes, which can be mixed
with utilities in the same `class` attribute.

## Variants and reusable styles

Utilities support `hover:`, `active:`, `focus:`, `focus-visible:`,
`focus-within:`, `disabled:` and `dark:`. `group-hover:` reads the nearest
ancestor marked `group`; `peer-hover:` reads the nearest earlier sibling
marked `peer`. Group and peer variants also support the focus, active and
disabled states.

Each variant needs a plain utility for the same property, such as
`bg-surface hover:bg-surface-elevated`, to supply its resting value. Each
class takes one variant. Use CSS selectors for custom class states:
`.surface:hover { ... }`. Responsive styling uses `@media` rules.

For shared utility styles, import `ashui.style.Tw.tw` and apply the resulting
`Style` with HXX's `style` attribute:

```tsx
import ashui.style.Tw.tw;

var surface = tw("p-4 rounded-xl bg-surface shadow-md");
var compact = surface.and(tw("p-2"));
var element = <div style={compact}>
    <text>Reusable style</text>
</div>;
```

`tw` takes a string literal and returns a style that can be applied to
multiple elements. `and` applies the second style after the first.
Custom stylesheet classes belong in `class="..."`, where they identify the
element for selector matching. Unknown utilities, invalid variants and
misspelled declared classes produce compile errors.

## Transitions and keyframes

CSS transitions animate changes to the named properties. Use theme variables
to follow the active theme's motion:

```css
.surface {
    transition: background-color var(--duration-normal) var(--ease-state),
                opacity var(--duration-fast) var(--ease-out);
}
.surface:hover { background: var(--surface-elevated); }

@keyframes breathe {
    from { opacity: 1; }
    50% { opacity: 0.6; }
    to { opacity: 1; }
}
.status-pulse { animation: breathe 1.4s ease-in-out infinite; }
```

Utilities express transitions with a property group, duration and easing:
`transition-colors duration-fast ease-state` or
`transition-transform duration-normal ease-spring`. A duration or easing
utility needs a transition class. `duration-200` fixes the duration at 200 ms;
`duration-normal` uses the theme's value. Built-in loops include
`animate-spin`, `animate-ping`, `animate-pulse` and `animate-bounce`.

CSS motion runs on ashui's animation scheduler. Properties interpolate
where their values have compatible shapes; other values switch during the
animation. State variants and CSS state selectors can both trigger
transitions.
