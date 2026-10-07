# Themes

A `Theme` defines one light or dark scheme. A `ThemeBundle` pairs both
schemes and can include CSS. `ThemeState` holds the active bundle for the
application; components, theme utilities and `Themed` bindings use its tokens.

## Choose a theme

Use the [quick setup](https://github.com/rayzor-blade/ashui#quick-setup), then
pass a bundle to `WindowedApp.run` before building the UI:

```tsx
import ashui.app.WindowedApp;
import ashui.theme.themes.HybridTheme;

class ThemeDemo {
    static function main() {
        WindowedApp.run({
            title: "Theme demo",
            width: 420,
            height: 240,
            theme: HybridTheme.bundle()
        }, () -> <div class="flex flex-col items-center justify-center gap-4 p-6 bg-background"
            width={420} height={240}>
            <div class="p-6 rounded bg-surface shadow-md">
                <text class="text-lg font-semibold text-primary">Your theme, everywhere</text>
            </div>
        </div>);
    }
}
```

Replace `HybridTheme` with `RestrainedTheme` or `ExpressiveTheme`, all in
`ashui.theme.themes`. Omitting `theme` selects Hybrid. The window follows
the system appearance; add `appearance: window.Theme.Dark` or
`appearance: window.Theme.Light` to the options to choose its appearance.
The UI uses the matching scheme from the bundle.

## Extend a built-in theme

Reuse the base theme's token sets and replace the ones you want to change.
Apply the same customization to both schemes so they share typography,
shape and motion while keeping their own colors and shadows.

Save this as `AppTheme.hx`:

```haxe
import ashui.theme.ShapeTokens;
import ashui.theme.Theme;
import ashui.theme.ThemeBundle;
import ashui.theme.themes.HybridTheme;
import ashui.theme.themes.RestrainedTheme;

class AppTheme {
    public static function bundle():ThemeBundle {
        return new ThemeBundle("My app", extend(HybridTheme.light()), extend(HybridTheme.dark()));
    }

    static function extend(base:Theme):Theme {
        return new Theme(
            "My app",
            base.colorScheme,
            base.colors,
            base.typography.with({textBase: 16.0}),
            base.spacing,
            base.radii,
            base.shadows,
            RestrainedTheme.animations(),
            new ShapeTokens(0.55, 4.0, 12.0)
        );
    }
}
```

Use `theme: AppTheme.bundle()` in the window options above. This keeps
Hybrid's palette, spacing, radii and shadows, increases the base text size,
uses Restrained's quicker motion and adds stronger corner smoothing.
`Theme` is final: extending a theme means composing a new bundle from its
tokens.

To design a theme from scratch, supply your own `ColorTokens`,
`TypographyTokens`, `SpacingTokens`, `RadiusTokens`, `ShadowTokens`,
`AnimationTokens` and `ShapeTokens` to each `Theme`. The built-in
[Hybrid implementation](https://github.com/rayzor-blade/ashui/blob/main/haxe/ashui/theme/themes/HybridTheme.hx)
shows every field. Leaving out `shape` disables automatic corner smoothing.

## Shape and motion

`RadiusTokens` controls corner size. `ShapeTokens(smoothing, exponent,
threshold)` controls their contour: smoothing ranges from 0 to 1, an
exponent of 2 gives circular corners, and the threshold is the minimum
corner radius in pixels that receives smoothing. Keep the default radius
at or above the threshold if default surfaces should have smoothed corners.

`AnimationTokens` defines duration steps and easing curves for state
changes, navigation, spring motion and sheets. Use tokens in your UI so
it follows the bundle's character:

```tsx
<div class="rounded bg-surface shadow-md transition duration-normal ease-spring
    hover:bg-surface-elevated">
    <text class="text-primary">Theme-aware surface</text>
</div>
```

`duration-normal` follows the theme's duration; `duration-200` fixes it at
200 ms. `ease-spring` follows the theme's spring curve. CSS can use the same
values through `var(--radius-default)`, `var(--duration-normal)` and
`var(--ease-spring)`.

## Include theme CSS

Attach CSS when creating the bundle:

```haxe
var bundle = AppTheme.bundle().withCss(
    ".app-card { background: var(--surface); border-radius: var(--radius-default); }"
);
```

Pass `bundle` as the window's `theme`. For a separate stylesheet, read and
embed it with `Css.add(CompiledCss.file("app.css"))`, importing both classes
from `ashui.css`. Declare custom class names with `-D ashui_css=app.css` in
`build.hxml` so HXX and `tw` can validate them at compile time.

See the [CSS guide](css.md) for stylesheet compilation, the cascade and
how theme tokens become utility classes.

## Change themes at runtime

After initialization, replace the bundle while preserving the active scheme:

```haxe
import ashui.theme.ThemeState;
import ashui.theme.themes.ExpressiveTheme;

ThemeState.init(ExpressiveTheme.bundle(), ThemeState.get().scheme());
```

Token bindings and CSS variables update reactively. Installing a bundle
clears runtime overrides. For individual color, spacing or radius changes,
use the active state instead:

```haxe
import ashui.theme.ColorToken;
import ashui.theme.RadiusToken;
import ashui.theme.Rgba;
import ashui.theme.ThemeState;

var state = ThemeState.get();
state.setColorOverride(ColorToken.Primary, Rgba.fromHex(0x2563eb));
state.setRadiusOverride(RadiusToken.Default, 16);

// Restore the bundle's values.
state.removeColorOverride(ColorToken.Primary);
state.clearOverrides();
```

Overrides persist across light/dark switches. Put permanent, scheme-specific
values in the bundle, and use overrides for changes made while the app runs.
