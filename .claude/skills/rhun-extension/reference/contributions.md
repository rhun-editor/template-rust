# Contributions (protocol 1.1, rhun 0.18)

Menus, keys, status items, context keys, language keys and file icon themes are declared in the
manifest and data files; most need no code. The spec's sections: "Feature: command-args", "Keys",
"When clauses", "Feature: context-keys", "Menus", "Feature: status-items", "Language
configuration", "File icon themes" in https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md.
Check everything with `rhun-ext-check DIR`: it compiles every when clause as rhun does and lists
each entry rhun would drop.

```ini
[command-options]
# per command: icon (a built-in name or ext:NAME), when (enablement), palette = no, callable = yes
tour.icon = spark
fmt.callable = yes

[keys]
# KEYS = COMMAND [ARGS] [when CLAUSE]; two strokes make a chord; a typing key (a letter, Enter,
# arrows... without ctrl, alt or super) needs !textInputFocus, viewFocus or view == ID in its clause
ctrl+k ctrl+g = greet when editorFocus && !editorReadonly
ctrl+alt+l = insert_log console.log when resourceLang == JavaScript

[menu.explorer]
# locations: editor explorer tab terminal extension editor_title view_title view_item
# view_item_inline (and scm/history ones); ITEM.command group order when args submenu
run_make.command = make_targets
run_make.when = resourceFilename == Makefile
more.submenu = tools
[submenu.tools]
title = Tools
lint.command = lint_file

[status]
# ITEM.FIELD: text tooltip command args align (left|right) priority color background when
tasks.text = $(play) Tasks
tasks.command = run_task
tasks.align = left

[context]
# defaults of the extension's own keys (when clauses read them as NAME.KEY)
mode = normal

[icons]
# PNGs for ext:NAME in status items, menus and buttons (at most 64 KB, 256 px)
logo = icons/logo.png

[language.Lua]
# language keys for an existing grammar (also valid in a .syn file)
continue = ---
indent_middle = else elseif
```

When clauses: `editorFocus && resourceExt in '.rs .go'`, `!findVisible`, `tabCount > 1`,
`resourceFilename =~ 'test_*'`, `demo.mode == insert`, `config.editor.word_wrap == true`. A typo in
a built-in key is an error (rhun drops the entry); an unknown key of another extension is empty.

## What arrives

With `command-args` in `hello`, every run is `0 run EXT.NAME DOC FROM LEN` and a body: FROM
`palette` (empty), `key` (the binding's ARGS), `menu` (the target line, LF, the item's args:
`file PATH`, `folder PATH`, `root PATH`, `tab doc DOC PATH`, `editor VERSION L1 C1 L2 C2`,
`terminal N`, `view VIEW`, `item VIEW ID`), `ref` (a command reference's ARGS, from a status
item, a code lens, a tree item). Rust: `Handler::invoke(&Invocation)`, `inv.target()`; Go: the
`Invoker` interface, `inv.Target()`; C: `rx_handlers.invoke`, `rx_menu_target`. A command
reference in a body is `command NAME LEN` + ARGS (`command_ref` / `EncodeCommandRef` /
`rx_command_ref`).

- `run-command NAME ARGS` runs a built-in (`goto_line 12 5`, `find TEXT`) or another extension's
  `callable` command and returns its result (`run_command` / `RunCommand` / `rx_run_command`);
  the callee answers `call` (`Handler::call` / `Callee` / `rx_handlers.call`) within 10 s.
- `set-context KEY VALUE` (feature `context-keys`) changes a key at run time; `-` removes it.
- `status-item ITEM` with a body adds or replaces an item (feature `status-items`), at most 8.

## Data files

- `syntax/NAME.syn`: a grammar; language keys `brackets autoclose autoclose_code surround
  indent_open indent_close indent_middle indent_dedent_after continue doc_block fold
  fold_markers` say how it types (`^T` only first on a line, `T$` only last).
- `icon-themes/NAME.icons`: a file icon theme (`title`, `fallback`, `[icons]` PNG or
  `rhun:ICON` with an optional color, `[files]`, `[extensions]` longest suffix first,
  `[languages]`, `[folders]`, `[folders_open]`). Users pick it with Select File Icon Theme;
  the setting is `[ui] file_icons = OWNER/NAME/THEME`.

## Testing headless

`print-menu`, `menu-pick LABEL`, `print-keys [EXT]`, `print-chord`, `print-status`,
`print-title-buttons`, `when CLAUSE`, `print-context [KEY]`, `print-langconf`,
`print-icon NAME [folder|folder-open]`, `print-contrib-problems OWNER/NAME`, `cmd-args NAME ARGS`.
