# Default fonts

Web builds bundle `Arimo.woff2` and `Arimo-Italic.woff2` because browsers do
not expose system fonts to the runtime. See `ashui.text.Fonts`.
The files are Arimo variable fonts from
[google/fonts](https://github.com/google/fonts/tree/main/ofl/arimo), covering
weights 400–700. They were converted from TTF to WOFF2 without other changes.

Arimo uses Helvetica/Arial-compatible glyph widths to preserve layout.
`OFL.txt` contains its license, the SIL Open Font License 1.1.

To override Arimo, embed a font with `Fonts.embed` whose family name is
Helvetica, Helvetica Neue or Arial.
