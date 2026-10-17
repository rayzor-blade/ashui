package ashui.icons;

/**
	The Remix icon set, version 4.8.0, 3188 icons: `Remix.PLAY_LINE`,
	`Remix.SAVE_3_FILL`, `Remix._4K_LINE`. Each is an `ashui.svg.SvgDocument`,
	checked and compiled into the program when it is built, and made the first
	time it is read; a program carries only the icons it names. They draw in
	`currentColor`, so the text colour of the element they are in tints them:

	```haxe
	import ashui.components.Icon;
	import ashui.icons.Remix;

	<icon document={Remix.PLAY_LINE} class="size-5 text-primary"/>
	```

	The names are the file names in upper case, folders left out (see
	`ashui.svg.IconSet`); the icons are in `ashui/icons/remix`, one folder to a
	category, which a set of your own can name to take them with its own:

	```haxe
	@:build(ashui.svg.IconSet.build(["ashui/icons/remix", "assets/icons"]))
	class Icons {}
	```

	Remix Icon is by Remix Design (https://remixicon.com) and, in this version,
	under the Apache License 2.0, whose text is in `ashui/icons/remix/LICENSE`.
**/
@:build(ashui.svg.IconSet.build("ashui/icons/remix"))
class Remix {}
