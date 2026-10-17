# C and C++: rhunext.h

One header, C99, the C library only; C++ includes it the same way. Copy
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/c/rhunext.h into the
repository.

```c
#define RHUNEXT_IMPLEMENTATION          /* in exactly one file */
#include "rhunext.h"

static void on_command(rx_ext *ext, const char *name, rx_doc doc, void *user) {
    if (strcmp(name, "say") == 0) rx_toast(ext, "Hello from C");
}
int main(void) {
    rx_handlers h = {0};
    h.command = on_command;
    return rx_run("", &h, NULL);        /* features: "views complete signature" */
}
```

Handlers: `ready`, `command` (name without `NAME.`), `event` (every event, first), `view`,
`complete`, `signature`, `bye`, `definition`, `references`, `symbols`, `actions`, `action`,
`rename`, `format`; each gets the `user` pointer passed to `rx_run`.

Requests block until answered and return -1 on an error reply (`rx_error(ext)` is its `CODE
TEXT`): `rx_text` (malloc'd, NUL-terminated: `free()` it), `rx_insert`, `rx_replace`,
`rx_select`, `rx_open`, `rx_toast`, `rx_status`, `rx_register`, `rx_cmd`, `rx_view`, `rx_draw`,
`rx_unview`, `rx_request` (any).

Pictures go into an `rx_buf` (`rx_buf p = {NULL, 0, 0};`): `rx_rect`, `rx_rrect`, `rx_line`,
`rx_poly`, `rx_fill`, `rx_circle`, `rx_ring`, `rx_pie`, `rx_label` (text), `rx_clip`,
`rx_unclip`; then `rx_draw(ext, view, &p)` and `rx_buf_free(&p)`.

Completion: in the `complete` handler, `rx_list l = {0};` (C++: `rx_list l{};`) then
`rx_list_item(&l, range, "function", label, insert, detail, doc)` per item, `rx_list_finish(&l,
out)`, return 1 (no items is the empty list; returning 0 answers `unknown`). Give every candidate
for the word: rhun filters and orders as the user types; set `l.more = 1` only when you cut the
list. The range is usually `rx_word_start(text, len, req->at)` to `req->at`; `req->id` is what a
`cancel` event names. `rx_list_item_cursor(&l, range, kind, label, insert, detail, doc, NULL,
NULL, 0, cursor)` puts the cursor `cursor` bytes into `insert` (-1: after it). Signature: `rx_signature_answer(out, sig, from, to, doc)`, return 1 (an
empty `out` hides the help).

Definition, references, symbols, code actions, rename, format: the handler adds to the builder
it gets and returns 1 (0 answers `unknown`). `rx_location(out, abs_path, 0, range, preview)`;
`rx_symbol(out, range, "function", depth, name, detail)` in document order; a workspace edit is
`rx_wedit_file(e, path, 0, version)` (or `RX_ON_DISK` for a file that is not open; path NULL and
a doc id for an open untitled document) then `rx_wedit_edit(e, range, text, len)` per edit;
`rx_action(out, "quickfix", title, &edit_or_NULL, data, len)` (the `action` handler gets the data
when the user chooses it). A rename that cannot be done: `return rx_refuse(out, "why");`.
`rx_apply(ext, &edit)` applies an edit on your own (needs `documents = write`).

Events: `ev->argv` splits on spaces, so a path (the last field of `opened` and `project`) comes
from `rx_event_tail(ev, 3)` and `ev->rest`. `rx_error(ext)` is `CODE TEXT` for your log, not a
message to show the user.

Builds: Linux `cc -std=c99 -O2 -static`, macOS `cc -std=c99 -O2`, Windows `clang -std=c99 -O2`
(C++: `c++ -std=c++17`, `clang++`).
