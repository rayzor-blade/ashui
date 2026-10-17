# Default fonts

A page has no system fonts, so a web build brings `Arimo.woff2` and
`Arimo-Italic.woff2` (see `ashui.text.Fonts`): the Arimo variable fonts from
[google/fonts](https://github.com/google/fonts/tree/main/ofl/arimo), weights
400 to 700, converted from TTF to WOFF2 without other change. Arimo has the
glyph widths of Helvetica and Arial, so layouts match. `OFL.txt` is its
licence, SIL Open Font License 1.1.

A program that wants another face brings its own file, `Fonts.embed`ed, and
names it `Helvetica`, `Helvetica Neue` or `Arial` to take the place of Arimo.
