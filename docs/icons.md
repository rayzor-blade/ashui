# Icons

A toolbar needs a play button, a pause button and a save button. Those symbols
should be there wherever a panel is built, without a file to load or SVG to
parse each time the panel opens. ashui makes each icon a typed constant,
compiled into the program.

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

Build the template where its owner is, as for any template, and enable inline
markup with `--macro ashui.ui.Markup.enable()`. A constant also fits a component
property typed `ashui.svg.Icon`, such as a tree item's `icon`.

## A set of your own

`ashui.svg.IconSet.build` makes a class of constants from directories of SVG
files, and from several at once:

```haxe
@:build(ashui.svg.IconSet.build(["ashui/icons/remix", "assets/icons"]))
class Icons {}
```

The directories are looked up on Haxe's class paths, so a library's own
directory is named as it is inside the library, `"ashui/icons/remix"`, and an
app's `assets/icons` is found when its parent is a `-cp`, even when the
compiler is run from another directory.

A file name becomes an upper-case name with every character that is not a letter
or a digit an underscore: `play-line.svg` is `PLAY_LINE`, and `save-3-line.svg` is
`SAVE_3_LINE`. A name that would start with a digit takes an underscore first, so
`4k-line.svg` is `_4K_LINE`. Folders only organize the files, so they are not in
the name, and two files that make one name are a compile error even in different
folders or different directories. So are a missing directory, XML that does not
parse and an SVG path that is not valid, each reported at the file.

## What the program holds

ashui checks each SVG while Haxe compiles it. The program carries its canonical
markup, its natural size and whether it can be tinted, but not the file, so it
needs no asset at run time. Reading a constant makes its document the first
time and keeps it, and the renderer rasterizes the markup at the size it is drawn
and caches the image. Parsing the optional `document.nodes` shape tree happens
only if code asks for it.

The class is marked `@:dce`, so an icon the program never names is removed with its
markup. Building the class still checks every file, but using one icon does not
make the rest at start-up. The files and the directories are dependencies of the
class, so a compilation server rebuilds it when a file changes, appears or goes.

## Let the text colour tint it

An icon drawn only in `currentColor` is a mask, and the colour of the element it
is in tints it: `text-primary` on the icon or on anything around it, and a
transition on that colour. The theme's text colour, its scheme changes and its
token overrides all reach it without a rebuild. Set the size with a class or an
attribute, `size-5` or `width={20}`; the authored viewBox stays whole. An SVG with
fixed paints keeps its own colours and is not a mask.

## The Remix catalogue

`ashui-icons` holds Remix Icon 4.8.0, 3188 icons in 20 category folders, and the
licence it was released under, the Apache License 2.0. Later releases of Remix
Icon, from 4.9.0, are under a different licence whose terms restrict
distributing the icons as a collection, so the package stays on 4.8.0. Moving to
a newer release is a decision about that licence first, and then a copy of
`package/icons` from the release's npm package into
`icons/haxe/ashui/icons/remix`. `tests/fixtures/icons` checks the catalogue and
that it combines with an app's own icons.
