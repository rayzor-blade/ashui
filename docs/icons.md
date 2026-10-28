# Icons

ashui compiles SVG icons into typed constants. Panels can reuse them without
loading or parsing icon files each time they open.

## Use a catalogue

`ashui-icons` carries the Remix icon set as `ashui.icons.Remix`. Each icon is an
`ashui.svg.SvgDocument`, and the `<icon>` element of `ashui-components` draws one:

```haxe
import ashui.components.Icon;
import ashui.icons.Remix;

var toolbar = <div class="flex flex-row items-center gap-3 p-2 text-primary">
	<icon document={Remix.PLAY_LINE} class="size-5"/>
	<icon document={Remix.PAUSE_LINE} class="size-5"/>
	<icon document={Remix.SAVE_3_LINE} class="size-5"/>
</div>;
```

Build the template inside an owner scope and enable HXX with
`--macro ashui.ui.Markup.enable()`. Icon constants also work in component
props typed `ashui.svg.Icon`, such as a tree item's `icon`.

## A set of your own

`ashui.svg.IconSet.build` makes a class of constants from directories of SVG
files, and from several at once:

```haxe
@:build(ashui.svg.IconSet.build(["ashui/icons/remix", "assets/icons"]))
class Icons {}
```

Directories resolve through Haxe class paths. Reference library directories
relative to their class path, such as `"ashui/icons/remix"`. For application
assets, add the parent of `assets/icons` with `-cp`. This also works when the
compiler runs from another directory.

Filenames become uppercase constants, with non-alphanumeric characters
replaced by underscores. For example, `play-line.svg` becomes `PLAY_LINE`
and `save-3-line.svg` becomes `SAVE_3_LINE`. A leading digit adds an initial
underscore: `4k-line.svg` becomes `_4K_LINE`.

Folder names do not affect constants. Duplicate names are compile errors,
even across different directories. Missing directories, malformed XML and
invalid SVG paths are also reported at their source files.

## What the program holds

The build validates each SVG and embeds canonical markup, intrinsic size
and tint information. Runtime icon files are unnecessary.
Each constant lazily creates and caches its document. The renderer caches
rasterized images by size. The optional `document.nodes` shape tree is
parsed only when accessed.

The generated class uses `@:dce`, so unused icons and their markup can be
removed. The build validates every file, but startup creates only the icons
the program uses. File and directory dependencies let the compilation server
detect changes, additions and removals.

## Let the text colour tint it

An icon painted only with `currentColor` becomes a tintable mask.
It inherits the displaying element's text color, including `text-primary`,
color transitions and theme overrides. These changes reuse the rasterized mask.
Set dimensions with utilities such as `size-5` or attributes such as
`width={20}`. The full viewBox is preserved. SVGs with fixed paints keep
their authored colors and do not use masks.

## The Remix catalogue

`ashui-icons` holds Remix Icon 4.8.0, 3188 icons in 20 category folders, and the
licence it was released under, the Apache License 2.0. Later releases of Remix
Icon, from 4.9.0, are under a different licence whose terms restrict
distributing the icons as a collection, so the package stays on 4.8.0. Moving to
a newer release is a decision about that licence first, and then a copy of
`package/icons` from the release's npm package into
`icons/haxe/ashui/icons/remix`. `tests/fixtures/icons` checks the catalogue and
that it combines with an app's own icons.
