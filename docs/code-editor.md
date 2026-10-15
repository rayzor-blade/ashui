# Code view and editor

Import `CodeEditor` and `CodeView` from `ashui.components`. Both use the same
syntax colors, line-number gutter, folding and scrolling. `CodeView` allows
selection and copying; `CodeEditor` also edits the shared value.

```tsx
import ashui.components.CodeEditor;
import ashui.components.CodeView;
import ashui.reactive.Reactive;

var source = signal("class Hello {\n    static function main() {}\n}\n");

return <div class="flex-col gap-4">
    <code-editor value={source} language="haxe" height={360}
        label="Application source" indentGuides={true}
        onInput={text -> saveDraft(text)} />
    <code-view value={source} language="haxe" height={200}
        label="Source preview" />
</div>;
```

Use the standard [components setup](https://github.com/rayzor-blade/ashui/blob/main/components/README.md#setup),
including `--macro ashui.ui.Markup.enable()` in `build.hxml`.
The [CodeWorkbench demo](https://github.com/rayzor-blade/ashui/blob/main/tools/demo/CodeWorkbench.hx)
is a complete windowed example.

## Display options

| Prop | Default | Purpose |
| --- | --- | --- |
| `value` | `""` | A shared signal, initial string, or derived source. Use LF line endings. |
| `language` | `"plain"` | Reactive language name; unknown names use plain text. |
| `highlighter` | Built in | A custom `CodeHighlighter`, overriding `language`. |
| `lineNumbers` | `true` | Original source line numbers, including after folding. |
| `folding` | `true` | Gutter buttons for multiline `{…}` and `[…]` blocks. |
| `indentGuides` | `false` | Guides at each indentation level. |
| `highlightBrackets` | `true` | Highlight the matching `{}`, `[]` or `()` pair beside the caret. |
| `tabSize` | `4` | Spaces per tab stop, from 1 to 16. |
| `insertSpaces` | `true` | Insert spaces when indenting; `false` inserts tabs. |
| `readOnly` | `false` | Reactive edit lock; selection and copying remain available. |
| `disabled` | `false` | Reactive input and focus lock. |
| `label` | `"Code"` | Accessible name of the text surface. |

Use layout attributes or CSS for width and height. Height defaults to 320px.
Code stays unwrapped and scrolls in both directions; the gutter stays visible
when scrolling horizontally. Closing a fold keeps its opening line visible.
Nested folds keep their state. Folding does not alter the source.

Built-in lexical highlighters cover Haxe (`hxx`), JavaScript (`js`, `jsx`), TypeScript (`ts`, `tsx`),
Rust (`rs`), JSON, CSS, Python (`py`) and Lua. Multiline comments and strings
carry state between lines. Brackets inside those tokens do not create folds.
These highlighters provide lexical colors rather than semantic language analysis.
HXX/JSX markup keeps child text separate from host code. Tags, attributes,
quoted values and embedded expressions get distinct tokens, including across
lines; literal text such as `Add one` is not treated as a type name.

## Editing

The editor reuses Ashui's text editing engine: native grapheme positions,
pointer selection, double-click word selection, keyboard navigation,
clipboard and input-method composition. The caret follows the selection
into view. A focused read-only view has no blinking caret.
Click a brace or move the caret next to it to highlight its matching pair.
Braces in strings, comments and literal markup text are excluded.

- **Enter:** insert a newline with the current indentation; add one level
  after an opening brace, bracket or colon.
- **Tab / Shift+Tab:** indent or outdent the selected lines. Without a
  selection, Tab advances to the next tab stop.
- **Command+Z / Control+Z:** undo. Add Shift to redo; Control+Y also redoes.
- **Command+Enter / Control+Enter:** call `onSubmit` with the source.
- **Escape:** leave the editing surface. In a read-only view, Tab moves focus.

`onInput` fires for user edits, undo and redo. External signal updates replace
the source and clear undo history. History stores replacement patches,
bounded to 100 edits and 1 MiB, rather than copying the file for each edit.

A `Ref<CodeEditor>` exposes `focus()`, `select(anchor, caret)`, `undo()`,
`redo()`, `toggleFold(line)` and `expandAll()`. Selection offsets are Haxe
string indices; fold line numbers are **zero based**. `select` reveals folded
ancestors. `value`, `editing`, `document`, `metrics` and `scroll` are available
for custom toolbars and status displays.

Only viewport rows and a small overscan are mounted. Highlighting reuses
unchanged lines until their incoming lexical state changes. Native caret
measurements retain at most 96 lines; disposal releases the view's watches,
layout callbacks and caret timer.

For editor tabs, keep panes mounted and bind their `display` to the selected
tab, as CodeWorkbench does. Inactive panes retain undo history, selection,
folds and shaped rows. An `<if>` intentionally disposes its inactive branch
and builds a fresh editor when it returns.

## Styling

The components follow the active theme's surfaces, typography, selection,
borders and shape tokens. Customize `.ui-code`, `.ui-code-gutter`,
`.ui-code-line-number`, `.ui-code-token[data-token="keyword"]`,
`.ui-code-selection`, `.ui-code-caret`, `.ui-code-guide` and `.ui-code-fold`.
`.ui-code-bracket` styles the matching-pair outline and background.
The fold control is the existing icon Button component.

```css
.source-editor {
    --ui-code-bg: var(--background);
    --ui-code-gutter-bg: var(--background);
    --ui-code-font-size: 14px;
    --ui-code-keyword: var(--primary);
}
```

Other custom properties are `--ui-code-font`, `--ui-code-border`,
`--ui-code-active-line`, `--ui-code-line-number`, `--ui-code-string`,
`--ui-code-comment`, `--ui-code-number`, `--ui-code-type`,
`--ui-code-function`, `--ui-code-operator`, `--ui-code-tag`,
`--ui-code-attribute`, `--ui-code-bracket-bg` and `--ui-code-bracket-border`. Syntax defaults have separate
light and dark palettes.

## Custom syntax

Implement `ashui.components.code.CodeHighlighter`. Return non-overlapping,
ordered spans using **Haxe string offsets** within the line, plus the lexical
state to pass to the next line. Return `""` when no multiline construct is open.
Cover the whole line, including plain text between colored tokens.

```haxe
import ashui.components.code.CodeHighlighter;

class NotesSyntax implements CodeHighlighter {
    public function new() {}

    public function highlight(line:String, state:String):CodeHighlight {
        return {
            tokens: [{from: 0, to: line.length,
                kind: StringTools.startsWith(line, "#") ? Comment : Plain}],
            state: ""
        };
    }
}
```

Pass `highlighter={new NotesSyntax()}` to either component. The token kinds
are `Plain`, `Keyword`, `StringLiteral`, `Comment`, `Number`, `Type`,
`Function`, `Operator`, `Tag`, `Attribute` and `MarkupText`; colors remain in CSS.
Use `MarkupText` for literal markup so bracket matching and folding skip it.
