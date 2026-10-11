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

### Element defaults and layout

`<a>`, `<u>` and `<ins>` are underlined; `<s>` and `<del>` have a strike;
`<abbr title="...">` has a dotted underline. Application CSS can restyle
these defaults. The global `hidden` attribute accepts a boolean or reactive
value and defaults to `display: none`, removing the element from layout,
drawing and hit testing. An explicit display style can override that default.

```tsx
<p>A <a href="https://example.com">link</a> and an <abbr title="Application Programming Interface">API</abbr>.</p>
<div hidden={isClosed}>Content shown when isClosed becomes false.</div>
```

Padding, margins, insets and gaps accept percentages in runtime and compiled
CSS. Padding and margin percentages use the containing block's **width**, on
all four sides. Insets and gaps resolve along their respective axes. Typed
attributes such as `paddingLeftPercent={0.1}` and `topPercent={0.5}` use
fractions; final layout coordinates follow native pixel snapping.

```css
.tiles { display: grid; place-items: center; gap: 5%; padding: 4%; }
.tiles .last { justify-self: end; }
.wrapped { flex-wrap: wrap; align-content: space-between; }
.scroll { overflow: hidden auto; }
```

Grid supports `justify-items` and `justify-self`; `align-content` distributes
wrapped flex lines or grid tracks. `place-items`, `place-self` and
`place-content` pair the corresponding align/justify properties. Utilities
include `place-items-center`, `justify-self-end`, `content-between` and
fractional insets such as `left-1/2`.

`overflow-x` and `overflow-y` accept `visible`, `hidden`, `clip`, `auto` and
`scroll`. CSS `auto`/`scroll` enables wheel and trackpad scrolling on that axis;
changing or removing it updates the existing scroll container. Typed
`overflowX`/`overflowY` attributes also keep input in step with reactive values. Equivalent
utilities include `overflow-x-auto` and `overflow-y-auto`. Native rectangular
clipping currently clips both axes when either axis needs clipping.

`object-fit` supports `cover`, `contain`, `fill`, `none` (intrinsic size), and
`scale-down` (contain without enlarging). `object-position` positions the
image within its content box, including cropping. It inherits, defaults to
`50% 50%`, and accepts axis keywords, percentage/length pairs, and edge lengths
such as `right 8px bottom 4px`. Percentages apply to the space left after fitting;
fractional values are preserved. Edge percentage offsets and percentage terms
inside `calc()` are currently unsupported.

```tsx
<img src={photo} class="object-cover object-left hover:object-right rounded-xl"
     width={240} height={160} />
```

Matching utilities include `object-none`, `object-scale-down`, `object-center`,
`object-top`, and `object-right-bottom`, with state variants. `fit` accepts
`ashui.types.ObjectFit` and existing `Brush.ImageFit` values; typed
`objectPosition` takes `{x, y, offsetX, offsetY}` (fractions and pixel offsets).
Explicit attributes win over CSS and utilities. Removing a stylesheet restores
`fill` and centered positioning while keeping local utility declarations.
Bitmaps are decoded once; positioned images share size-bucketed atlas entries,
so changing position reuses the texture.

### List markers and cursors

`list-style-type` inherits through lists and can be overridden on individual
`<li>` elements. Supported types are `disc`, `circle`, `square`, `decimal`,
`decimal-leading-zero`, `lower-alpha`/`upper-alpha`, `lower-latin`/`upper-latin`,
`lower-roman`/`upper-roman` and `none`. `none` removes the marker and its space.
The existing `<ol>` `start`, `reversed`, `type` and `<li value>` counting rules
still apply; removing CSS restores their default markers.

```css
.steps { list-style-type: lower-roman; }
.steps > li:last-child { list-style-type: none; }
.draggable { cursor: grab; }
.draggable:active { cursor: grabbing; }
```

`cursor` inherits and accepts the standard platform keywords, including
`pointer`, `text`, `grab`, resize cursors and `none` to hide the cursor.
Custom cursor images are not supported. Built-in controls choose pointer
or text cursors through the user-agent stylesheet. Updates use the cached
hit target and do not add pointer movement watchers.

Equivalent utilities include `list-disc`, `list-decimal`, `list-lower-roman`,
`list-none` and `cursor-*`, including state variants:

```tsx
<ol class="list-lower-roman"><li>Prepare</li><li>Publish</li></ol>
<div class="cursor-grab active:cursor-grabbing">Drag this card</div>
```

### Visibility, pointer events and scrollbars

`visibility: hidden` keeps an element's layout space while suppressing its
painting and pointer hits. `visible` restores it; `collapse` currently behaves
like `hidden`. `pointer-events: none` passes pointer hits through an element
while keeping it drawn and available to keyboard focus; `auto` restores hits.
These use native subtree suppression: descendants cannot override a hidden
or pointer-disabled ancestor. Table row/column collapsing is not implemented.

```tsx
<div visibility={Hidden}>Reserved space</div>
<div class="pointer-events-none">A painted overlay that passes pointer hits through.</div>
```

Both typed attributes accept signals and computeds. Utilities include
`visible`, `invisible`, `collapse`, `pointer-events-auto` and
`pointer-events-none`, with the usual state variants. Changing these values
invalidates the existing pointer hit cache.

Scroll containers support `scrollbar-color: <thumb> <track>` or `auto` to
restore the theme's thumb and transparent track. Colors inherit; `currentColor`,
theme variables and alpha are supported. `scrollbar-width` accepts `auto`
(4 layout units), `thin` (2) or `none`. The bars overlay content without
changing layout; `none` hides them while wheel and trackpad scrolling continue.
Utilities are `scrollbar-auto`, `scrollbar-thin` and `scrollbar-none`.

```css
.activity {
    overflow-y: auto;
    scrollbar-width: thin;
    scrollbar-color: var(--primary) transparent;
    scrollbar-visibility: hover;
}
```

The existing `scrollbar-visibility` property accepts `auto` (show during
scrolling, then fade), `always`, `hover` or `hidden`. Custom thumbs and tracks
follow the same visibility and fade behavior. Styling reuses the scroll
container's existing watcher; hiding the scrollbar avoids fade timers.

### Sticky positioning, stacking and text limits

`position: sticky` keeps an element in normal flow and holds it at an inset
of its nearest scroll container. For example, a heading with `top: 0` stays
at the top while its section scrolls. It leaves when its containing section
ends. `z-index` accepts signed integers or `auto`; drawing and hit testing
use the same sibling order. Each element stacks its children locally.

```css
.heading { position: sticky; top: 0; z-index: 10; }
.title { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.summary { line-clamp: 2; }
```

`text-overflow: ellipsis` fits a single line to its box. `line-clamp` limits
wrapped text and ends the last visible line with an ellipsis. `line-clamp:
none` restores all lines; `-webkit-line-clamp` accepts the same values.
Both work on `<text>` and paragraph flows, including styled inline text.

Utilities include `sticky`, `z-0` through `z-50` in steps of ten (and their
negative forms), `truncate`, `text-ellipsis`, `text-clip`, `whitespace-nowrap`,
and `line-clamp-1` through `line-clamp-6` or `line-clamp-none`:

```tsx
<text class="truncate" width={240}>A title that fits its available width</text>
<p class="line-clamp-2" width={240}>A longer summary with <strong>styled text</strong>.</p>
```

HXX also exposes typed `position={Sticky}`, `zIndex={10}`,
`textOverflow={Ellipsis}` and `lineClamp={2}` attributes. `lineClamp={0}`
removes the limit. These accept reactive values like other properties.

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
