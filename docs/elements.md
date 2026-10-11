# Dialogs and forms

Built-in elements carry their behavior into HXX. A modal dialog manages focus
and plays its existing opening and closing transitions; a form validates its
controls before submitting.

```tsx
import ashui.ui.Dialog;
import ashui.ui.Ref;

var dialog = new Ref<Dialog>();

<dialog ref={dialog} open={showDialog} closedby="closerequest"
    onCancel={event -> { if (hasUnsavedChanges) event.preventDefault(); }}>
    <form method="dialog" class="flex-col items-stretch gap-4 w-full">
        <input name="displayName" required value={displayName} />
        <button name="action" value="saved">Save</button>
    </form>
</dialog>
```

Pass a signal to `open` to share the dialog's state. `closedby="any"` allows
Escape and a backdrop press to request dismissal; `closerequest` allows only
Escape; `none` allows only explicit controls and API calls. An `onCancel`
handler can call `preventDefault()` to keep the dialog open. A child that
consumes Escape also keeps it open. Omitting `closedby` preserves the existing
`dismissible` behavior: Escape and backdrop by default, neither when false.

`dialog.get().requestClose(value)` sends `onCancel` before closing.
`dialog.get().close(value)` closes directly. The value is stored in
`returnValue`; omitting it preserves the previous value. `onClose` runs once
when an open dialog closes. `modal={false}` displays it in place.

A form with `method="dialog"` closes the dialog containing it after successful
submission, setting `returnValue` from its submit button's `value`. It still
validates and calls `onSubmit`; `novalidate` skips validation. Enter in a text
input uses the first submit button. `type="button"` never submits, and
`type="reset"` restores the controls. Only the chosen submit button's `name`
and `value` join the named controls in `FormData`, in document order.

The component library's `Button` supports the same `type`, `name` and `value`.
Its `DialogContent` accepts `closedby`, `onCancel` and `onClose`; it uses the
built-in dialog underneath. See the existing
[DialogMotion example](../tools/snapshot/scenes/DialogMotion.hx) for a dialog
form with the default component theme and transitions.
