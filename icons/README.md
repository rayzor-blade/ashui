# ashui-icons

The [Remix](https://remixicon.com) icon set as typed [ashui](https://github.com/rayzor-blade/ashui)
constants, and the macro that makes a set from any directory of SVG files. An
icon is checked and compiled into the program when it is built, so it needs no
file when it runs, and a program carries only the icons it names.

| ![Remix icons in the dark theme](../docs/images/icons-dark.png) | ![Remix icons in the light theme](../docs/images/icons-light.png) |
| --- | --- |

## Setup

```sh
haxelib install ashui-icons
```

This installs ashui with it. Use [Ash](https://ash.rayzor.tech/#setup) to run the
compiled app. Save this as `build.hxml`; the markup needs the first line of
options and `ashui-components` brings the `<icon>` element:

```hxml
-lib ashui-icons
-lib ashui-components
--macro ashui.ui.Markup.enable()
-main IconsDemo
-hl bin/icons.hl
```

## Use

Save as `IconsDemo.hx`, then run `haxe build.hxml` and `ash bin/icons.hl`:

```tsx
import ashui.app.WindowedApp;
import ashui.components.Icon;
import ashui.icons.Remix;

class IconsDemo {
    static function main() {
        WindowedApp.run({title: "Icons", width: 320, height: 120}, () ->
            <div class="flex flex-row items-center justify-center gap-4 p-6 text-primary" width={320} height={120}>
                <icon document={Remix.PLAY_LINE} class="size-6"/>
                <icon document={Remix.PAUSE_LINE} class="size-6"/>
                <icon document={Remix.SAVE_3_LINE} class="size-6 text-success"/>
            </div>);
    }
}
```

An icon is drawn in `currentColor`, so the text colour of the element it is in,
or its own `text-*` class, tints it. Its size is the icon's own, 24 pixels, unless
CSS gives it one: `size-6`, `w-5 h-5`.

Each constant is an `ashui.svg.SvgDocument`, which also fits a component prop typed
`ashui.svg.Icon`, such as a tree item's `icon`.

## Names

A name is the file's name in upper case, every other character an underscore, and
a leading underscore before a digit: `play-line.svg` is `Remix.PLAY_LINE`,
`save-3-line.svg` is `Remix.SAVE_3_LINE`, `4k-line.svg` is `Remix._4K_LINE`. The
`-line` and `-fill` forms are separate icons. Folders, one to a category, only
organize the files: they are in `ashui/icons/remix` inside this package, and are
not part of a name.

## A set of your own

`ashui.svg.IconSet.build` makes a class like `Remix` from your own SVG files, and
from several directories at once, so an app can take Remix and its own icons as
one:

```haxe
@:build(ashui.svg.IconSet.build(["ashui/icons/remix", "assets/icons"]))
class Icons {}

var move = Icons._3D_MOVE; // assets/icons/3d-move.svg
var play = Icons.PLAY_LINE;
```

A directory is looked up on Haxe's class paths, so give `assets/icons`' parent as a
`-cp`. A missing directory, malformed XML, an invalid path and two files that make
the same name are errors at the file; the files are dependencies of the class,
so a compilation server rebuilds it when one changes. Use `currentColor` in
your own icons for them to follow the text colour.

## Licence

The ashui packages are under the Apache License 2.0. The icons are Remix Icon
4.8.0 by Remix Design, [remixicon.com](https://remixicon.com), the last version
under the Apache License 2.0 as well; its text is in
[`ashui/icons/remix/LICENSE`](https://github.com/rayzor-blade/ashui/blob/main/icons/haxe/ashui/icons/remix/LICENSE)
and ships with the package. Later versions of Remix Icon are under a different
licence, with terms about distributing the icons as a collection, so this package
stays on 4.8.0.
