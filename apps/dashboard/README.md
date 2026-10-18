# Ash Drive

A car's dashboard as an ashui app, and the demo for the website's landing page. It is the README banner made into a program a
visitor can use: every key of the dock opens a page that works, the music plays, and the window is light or dark as the system is.

| Page     | What works                                                                                                         |
| -------- | ------------------------------------------------------------------------------------------------------------------ |
| Navigate | A street map with a route to a charger, zoom keys, a search that narrows the chargers, start and end of guidance.  |
| Media    | Three original tracks played by hlavi: play and pause, seek, volume, next and previous, shuffle, repeat, a visualiser. |
| Vehicle  | The 3D car with its callouts, the speed and gear, the climate dial, the paint, the doors, the energy chart.        |
| Charging | The battery ring, the charge limit, the charging curve, and the chargers nearby, each a press from guidance.       |
| Camera   | Front, rear, side and top views of the car, drag to look round, scroll to move closer, the parking sensors.        |
| Phone    | A keypad, contacts, a call that rings and runs with its clock, and the recent calls. No real call is placed.       |
| Profile  | Who is driving, which sets the climate and the paint, the appearance (Auto, Light, Dark) and the units.            |
| More     | Brightness, sounds, notifications and quiet hours, and what the app is made of.                                    |

The island across the top plays the same track as the Media page, and its play key and scrubber work from any page.

## Running it

On the desktop, from the repository root:

```sh
apps/dashboard/run.sh
```

It builds the native libraries it needs (blinc_abi, hlwgpu, hlwindow and hlavi), compiles the program and opens it on Ash. It needs
the sibling checkouts that `tools/demo/run.sh` does, and `../hlavi` as well, for the music.

In a browser, the program is built for a page as `docs/web.md` describes, with hlavi's web build beside it for the music.
`tests/wasm/run.sh Dashboard` builds it, serves it and opens it; it needs a browser with WebGPU. The browser starts the music only
after a press, so the first press of the play key is the one that starts it.

`apps/dashboard/check.sh` type-checks the program without building it, and `apps/dashboard/preview.sh` draws a page to a PNG:

```sh
TAB=Charging SCHEME=light apps/dashboard/preview.sh      # .ashui/snapshots/dashboard-Charging-light.png
```

`WIDTH` and `HEIGHT` set the size, and `CALL=1` shows the phone on a call.

## How it is made

Everything a page shows is a signal in `Model` (the car, the climate, the charge, the guidance, who is driving) or in `Music` and
`Phone`, and a page only reads them. `Model.step` is the simulation: the car cruises, the charge rises, the guidance moves on.
Pages are made when they are opened, in `Dashboard.page`, so a page nobody is on costs nothing. The 3D scene behind them is drawn
on the Vehicle and Camera pages only.

`dashboard.css` is the stylesheet, and the classes the markup names must be in it. The page is a gray gradient and the cards are
frosted, tinted glass, whose colours the stylesheet sets for each scheme through `prefers-color-scheme`. Canvases take their
colours from `Ink`, which reads the theme as they draw.

The window's scheme is `WindowTheme`'s: it follows the system until the Profile page chooses Light or Dark, and chooses nothing again
for Auto.

Two rules of markup the pages follow. An interpolation is read again when a signal changes only if it reads that signal itself with
`.get()`, so text that calls a function reading signals is wrapped in `Widgets.live`. And what an `<if>` shows is made inside it, so
it is a call (`{stopKey()}`) and not a variable that was made before.

## The music

The three tracks in `audio/` are original, made by `tools/compose.py` (numpy for the synthesis, ffmpeg for the encoding), so there
is nothing to license. Running it again rewrites `audio/` and `levels/`, which holds the loudness of 16 bands for the visualiser.
