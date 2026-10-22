# Contributions (protocol 1.1)

Commands with arguments, key bindings and chords, menus, status bar items, when clauses, context
keys, language configuration and file icon themes. Most are manifest sections and data files and
need no code; the run-time parts are features for `hello 1 ...`: `command-args` (every run says
where it came from and carries a body; `run-command`, `call`), `commands` (`unregister`),
`context-keys` (`set-context`), `status-items` (`status-item`, `status-remove`). Manifest:
`[command-options]`, `[keys]`, `[menu.LOCATION]`, `[submenu.NAME]`, `[status]`, `[context]`,
`[icons]`, `[language.NAME]`; files `syntax/*.syn`, `icon-themes/*.icons`. Spec: v1.1.md, "Command
identity", "Feature: `commands`", "Feature: `command-args`", "Keys", "When clauses", "Feature:
`context-keys`", "Menus", "Feature: `status-items`", "Language configuration", "File icon
themes", https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md.
`rhun-ext-check DIR` compiles every when clause as rhun does and fails each entry rhun would drop
(rhun itself drops the entry, lists it on the extension's page and loads the rest). Examples:
the templates (a chord with an argument, an editor menu item, a status item, `[language.Shell]`),
`rhun-editor/snippets` (`[keys]`, `[menu.editor]`, `[command-options]` when), `rhun-editor/blame`
(`[menu.editor]` groups), `rhun-editor/hg` and `rhun-editor/format` (`palette = no`),
`rhun-editor/wordfreq` (`[status]` and a runtime status item, C).

## Commands

- **Identity.** A command is `OWNER/NAME.command`; `NAME.command` works while only one installed
  extension is named NAME (a disabled one counts). `0 run NAME.command DOC` keeps the short form.
- **`commands`**: `ID unregister NAME` → `ok ID` removes a command added with `register` (and its
  default keys); a manifest command is `refused`. Rust `ext.unregister`, Go `Unregister`, C
  `rx_unregister`.
- **`command-args`**: every run of the extension's commands becomes `0 run EXT.NAME DOC FROM LEN`
  + LEN body bytes (LEN 0 without a body; without the feature v1's `0 run EXT.NAME DOC`):

| FROM | Invoked by | Body |
| --- | --- | --- |
| `palette` | the palette, headless `cmd`, a menu listing all commands | empty |
| `key` | a `[keys]` binding | the binding's ARGS (4096 bytes) |
| `menu` | a menu item, a tab-strip or view button | `TARGET` LF, then the item's `args` |
| `ref` | a command reference: a code lens, tree item, status item, notification button, inlay hint part, scm button, code action, decoration | the reference's ARGS, verbatim |

TARGET by location: `editor VERSION L1 C1 L2 C2` (the selection after the right click) ·
explorer `file PATH`, `folder PATH`, `root PATH` (the empty area) · `tab doc DOC PATH` (PATH `-`
untitled), `tab image PATH`, `tab view VIEW`, `tab settings`, `tab git`, `tab extensions` ·
`terminal N` · `extension` · `editor_title` as `tab` for the active tab · `view_title` `view VIEW`
· `view_item`, `view_item_inline` `item VIEW ID` · `history_commit` `commit SHA` · `history_file`
`commit SHA PATH` · `scm_resource` `resource GROUP PATH` · `scm_group` `group GROUP` · `scm_title`
`scm OWNER/NAME ROOT` (or `scm git ROOT`). A command invoked while the extension starts is held
(one, 64 KB) and delivered after `ready` and the catch-up.

- **Command references**: inside any body, the record `command NAME ARGS_LEN` LF + ARGS (NAME a
  local command, manifest or registered; ARGS opaque, 8192 bytes) runs `0 run EXT.NAME DOC ref
  LEN` + ARGS when the user activates what carries it. A command gone by then shows "This command
  is no longer available".
- **`run-command`**: `ID run-command NAME LEN` + ARGS → `ok ID LEN` + RESULT. NAME is a built-in
  (`goto_line`, `rhun.find`; ARGS one line for `goto_line` `LINE [COL]`, `find`, `replace`,
  `find_in_files`, `quick_open`, `command_palette`; result always empty) or another extension's
  `OWNER/EXT.NAME` declared `callable = yes` whose owner agreed `command-args` (else `refused not
  callable`). Your own commands are
  `refused its own command`. The callee gets `ID call EXT.NAME DOC CALLER LEN` + ARGS and answers
  `ok ID LEN` + RESULT (1 MiB) or an error, within 10 s including its start (then the caller gets
  `cancelled timeout`, the callee `0 cancel ID`); 8 calls outstanding per caller. A callable
  command runs with its owner's `[needs]`, without asking the user.

```ini
[command-options]
# NAME.FIELD: icon (a built-in name or ext:NAME, for menu items and buttons), when (enablement:
# false hides it from the palette and menus and its keys fall through), palette = no, callable = yes
copy_relative.icon = copy
copy_relative.when = projectOpen
fmt.callable = yes
```

## Keys

```ini
[keys]
# KEYS = COMMAND [ARGS] [when CLAUSE]; one stroke or two (a chord); linux: mac: windows: limits it
ctrl+k ctrl+g = greet when editorFocus && !editorReadonly
ctrl+alt+l = insert_log console.log when resourceLang == JavaScript
mac:ctrl+shift+r = reveal
```

A stroke is `ctrl`, `shift`, `alt`, `super` (`cmd`, `meta`) joined by `+` to a character or a
key name (`Enter Tab Escape Backspace Delete Up Down Left Right Home End PageUp PageDown Insert
Space F1`-`F12`, an X keysym such as `KP_Add`); on macOS Command arrives as `ctrl`. A key with `=`
is written by name (`ctrl+equal`). COMMAND is a local `NAME`, a built-in `rhun.NAME` or another
extension's `EXT.NAME`/`OWNER/EXT.NAME`; ARGS run to ` when ` and are the body of FROM `key`.
Precedence: the user's `[keys]` > extensions' `[keys]` > built-ins > `[commands]` default keys
(v1: single strokes that never take a built-in's key); the earlier binding of a rank wins. A
chord's first stroke needs ctrl, alt or super; rhun waits 5 s for the second (Escape ends it).
**A typing key** (a character, Enter, Tab, Backspace, Delete, Escape, arrows, Home, End, PageUp,
PageDown, Insert) without ctrl, alt or super is refused unless its clause has `!textInputFocus`,
`viewFocus` or `view == …` as a top-level `&&` term. A binding to a command that does not exist is
refused until a runtime command of that name is registered.

## When clauses

`&&`, `||`, `!`, parentheses; tests `key`, `key == v`, `!=`, `<`, `<=`, `>`, `>=` (signed
integers), `=~ 'glob*'` (whole value, `*` and `?`, case-sensitive, no regex), `key in 'a b'`,
`not in`; values are literals ('…' or "…" quotes, no escapes; never a key). At most 512 bytes, 64
operations, 8 levels. A bare key is true when non-empty and not `false` or `0`. Keys:

- built-in: `editorFocus textInputFocus paletteFocus findFocus explorerFocus agentsFocus
  terminalFocus scmInputFocus settingsFocus findVisible completionVisible signatureVisible
  snippetActive viewFocus view viewItem activeTab activeTabPinned tabCount resourceLang
  resourceExt resourceFilename resourceDirname resourcePath resourceScheme resourceInProject
  editorReadonly editorDirty editorHasSelection editorHasMultipleSelections editorProviders
  vimMode sidebarVisible agentsVisible terminalVisible projectOpen projectPath gitRepo gitBranch
  gitChanges gitTrusted isLinux isMac isWindows isWayland remoteName remoteHost targetKind
  explorerResourceIsFolder explorerResourceIsRoot tabKind debugState inDebugMode debugType
  scmProvider scmResourceGroup scmResourceStatus`, and in notebooks `notebookFocus
  notebookCellEditing notebookCellType notebookKernelState`. Inside a menu `resource*` and
  `editor*` describe its target. `resourceLang` has `_` for spaces (`Visual_Basic`), `resourceExt`
  is `.rs`.
- an extension's own: `NAME.KEY` (`OWNER/NAME.KEY` when two extensions share NAME; in its own
  manifest `NAME.KEY` is always its own); its settings `NAME.setting.KEY` (read-only).
- rhun's settings: `config.SECTION.KEY` as written in its config (`config.editor.word_wrap == true`).

A typo in a built-in key fails the clause (`unknown key resourceExtt at byte 0`); an unknown key
of another extension is empty. Rust `rhun_ext::when::check(clause)` → `Err((offset, text))`, Go
`rhunext.WhenCheck(clause)` → `*WhenError{Offset, Text}`, C `rx_when_check(clause, len, &off,
&msg)`; shared vectors in `v1.1/when-vectors.txt`.

## Context keys

`[context]` gives defaults (`mode = normal`), valid while the program is stopped too. With
`context-keys`, `ID set-context KEY VALUE` → `ok ID` sets one at run time (KEY a lowercase letter,
then letters, digits, `_`, 40 bytes; VALUE one line, 256 bytes; `-` removes the run-time value so
the default applies). 64 keys per extension; run-time values go when the program stops. Rust
`ext.set_context(k, v)`, `remove_context(k)`; Go `SetContext`, `RemoveContext`; C
`rx_set_context`, `rx_remove_context`.

## Menus

```ini
[menu.explorer]
# ITEM.FIELD: command (default: ITEM), group, order, when, args, submenu
run_make.command = make_targets
run_make.group = 2_build
run_make.when = resourceFilename == Makefile
more.submenu = tools
[submenu.tools]
title = Tools
lint.command = lint_file
lint.when = resourceExt in '.js .ts'
```

Locations: `editor explorer tab terminal extension editor_title view_title view_item
view_item_inline history_commit history_file scm_resource scm_group scm_title`. ITEM is 1-40 of
`[a-z0-9_]`; labels are the commands' titles. An item shows when its command exists, its
`[command-options]` `when` and its own `when` hold. rhun's items come first, then groups sorted by
name (default group: the extension's), a line between groups; within a group by `order`. 16 items
per extension per location, 32 extensions per menu, no submenu in a submenu. `editor_title`,
`view_title`, `view_item_inline` and `scm_title` items are icon buttons (the command's
`[command-options] icon`; 3 shown, then `…`); `view_item` is a tree row's context menu, with
`viewItem` its `ctx` value. `extension` items replace the list of its commands in its title-bar
button. Without `command-args` a click sends v1's `0 run EXT.NAME DOC`.

## Status items

`[status]` items show while the extension is installed and enabled (a click starts it); with
`status-items`, `ID status-item ITEM LEN` + body → `ok ID` adds or replaces one at run time and
`ID status-remove ITEM` removes one (a manifest item is hidden until the program stops). 8 per
extension in all (`toobig 8 items`); v1's `status` text is the item `_v1` and does not count.

```
body: ALIGN PRIORITY TEXT_LEN TOOLTIP_LEN EXTRA_LEN LF <TEXT><TOOLTIP><EXTRA>
ALIGN left|right; PRIORITY -1000..1000 (higher further left); TEXT one line, 120 bytes;
TOOLTIP 500 bytes; EXTRA: command NAME ARGS_LEN + ARGS, color NAME 0, background error|warning 0,
when LEN + clause; colors fg muted (default) accent error warning success
```

```ini
[status]
# ITEM.FIELD: text tooltip command args align priority color background when
tasks.text = $(play) Tasks
tasks.command = run_task
tasks.align = left
tasks.when = projectOpen
[icons]
# NAME (1-40 of [a-z0-9_-], 32 at most) = PNG, 64 KB, 256 px; ext:NAME in status text and icons
logo = icons/logo.png
```

`$(NAME)` in TEXT is an icon (4 drawn): `ext:NAME` or a built-in: `chevron-right chevron-down
chevron-up folder file close search spark dot plus minus check terminal back user arrow-up
arrow-down refresh sync branch discard file-plus folder-plus sliders play stop debug bug warning
error info bell gear edit trash eye pin lock copy filter list beaker cloud more extensions`. An
all-grey PNG is drawn as a mask in the text's color. A manifest item's command must be one of the
extension's own. Rust `ext.set_status_item(&StatusItem{name, align, priority, text, tooltip,
command, args, color, background, when})`, `remove_status_item`; Go `SetStatusItem(StatusItem{…})`,
`RemoveStatusItem`; C `rx_set_status_item(ext, &item)` (`rx_status_item`), `rx_remove_status_item`.

## SDK for runs (Rust, Go, C)

- Feature: `Feature::CommandArgs` / `rhunext.FeatureCommandArgs` / `"command-args"`; likewise
  `Commands`, `ContextKeys`, `StatusItems`.
- Runs: Rust `Handler::invoke(&Invocation{command, name, doc, from, body})` (the default calls
  `command`), `inv.target()` → `Option<(MenuTarget{kind, fields, line}, args)>`,
  `MenuTarget::path()`. Go: a handler implementing `Invoker` (`Invoke(ext, Invocation)`) gets it
  instead of `Run`; `inv.Name()`, `inv.Target()` → `(MenuTarget, args, ok)`, `FromPalette FromKey
  FromMenu FromRef`, `ParseMenuTarget`, `t.Path()`. C: `rx_handlers.invoke` (`rx_invocation`),
  `rx_menu_target(inv, &t, &tlen, &args, &alen)`.
- References: Rust `command_ref(name, args)` / `push_command_ref`; Go `EncodeCommandRef`,
  `AppendCommandRef`; C `rx_command_ref(&buf, name, args, len)`.
- Running others: Rust `ext.run_command(name, args)`; Go `RunCommand`, `RunCommandContext`; C
  `rx_run_command(ext, name, args, len, &result)`. Being called: Rust `Handler::call(&CallRequest
  {name, caller, args, ..})` → `Result<Vec<u8>, Error>`; Go `Callee` (`Call(ext, CallRequest)`,
  `c.Context` ends on cancel); C `rx_handlers.call`.

The status item's command must be one of the extension's own (`[commands] toggle = Toggle Mode`).

```rust
use rhun_ext::{run, Ext, Feature, Handler, Invocation, StatusItem};

struct Demo;
impl Handler for Demo {
    fn ready(&mut self, ext: &Ext, _project: Option<&str>) {
        let item = StatusItem { name: "mode".into(), align: "left".into(), text: "$(edit) normal".into(),
            command: "toggle".into(), ..Default::default() };
        let _ = ext.set_status_item(&item);
    }
    fn invoke(&mut self, ext: &Ext, inv: &Invocation) {
        if let Some((target, args)) = inv.target() {
            if let Some(path) = target.path() { let _ = ext.toast(&format!("{} on {path}", inv.name)); }
            let _ = args;
        } else if inv.name == "toggle" {
            let _ = ext.set_context("mode", "insert"); // when clauses: demo.mode == insert
        }
    }
}
fn main() { let _ = run(&[Feature::CommandArgs, Feature::ContextKeys, Feature::StatusItems], Demo); }
```

## Language configuration and file icon themes

Keys in a grammar (`syntax/NAME.syn`) or in `[language.NAME]` for a grammar that exists (NAME
with `_` for a space: `[language.Plain_Text]`): `brackets` (pairs, 16), `autoclose` (OPEN CLOSE
pairs, 16), `autoclose_code` (OPENs that close only outside strings and comments), `surround`,
`indent_open`, `indent_close` (`^T` only first on a line, `T$` only last), `indent_middle` (`else
elif`), `indent_dedent_after` (`return pass`), `continue` (line markers Enter continues: `/// -
>`), `doc_block` (`/** * */`), `fold` (`brackets` or `indent`), `fold_markers` (`#region
#endregion`); also `comment`, `toggle_comment`, `block`, `ident`, `colon_indent`. Tokens at most
14 bytes, 32 per list. Per key, a user grammar wins, then the first extension that sets it, then
the grammar, then the default; a bad value keeps the default and is listed on the page.

`icon-themes/NAME.icons` (INI, 256 KB): `title`, `fallback = default|rhun`, `[icons]` NAME = `PNG
[COLOR]` or `rhun:ICON [COLOR]` (COLOR `red orange yellow green blue purple pink cyan grey white
accent muted` draws the PNG's alpha as a mask), then `[files]` (whole name, any case),
`[extensions]` (longest suffix: `d.ts`), `[languages]`, `[folders]`, `[folders_open]`; keys
`file`, `folder`, `folder_open` are the defaults. PNG 64 KB, 256 px (32 or 64 best); 512 icons,
4096 lines; no SVG, no VS Code JSON. The id is `OWNER/NAME/THEME`; users pick it with **Select File
Icon Theme** (`[ui] file_icons = OWNER/NAME/THEME`). `icon-themes/`, `icons/` and `syntax/` ship
in the release archive by themselves: the templates' `tests/layout.sh` copies every top-level
folder except source, tests and build files.

## Headless

`print-keys [EXT]` (`STROKES COMMAND source=… rank=R [args=A] [when=W]
state=active|shadowed:SOURCE|refused:command|when|typing|prefix|strokes`), `print-chord`,
`key-latin LATIN COMBO`, `print-menu` (an open menu's rows; `LABEL [OWNER/NAME]`, submenus end
` >`), `menu-pick LABEL`, `click X Y right` (then `print-menu`), `print-title-buttons`,
`view-item-menu VIEW ID [CONTEXT]`, `print-status` (`side= prio= owner= item= text= tooltip=
command= shown=0|1 at=X,Y,W,H`; click its middle), `when CLAUSE` (`when=1|0|error at N: TEXT`),
`print-context [KEY]`, `cmd-args NAME ARGS...` (runs as a reference would), `cmd-ref EXT NAME
[ARGS]`, `print-langconf` (`KEY=VALUE source=default|grammar|user|ext:OWNER/NAME`), `print-icon
NAME [folder|folder-open]`, `print-contrib-problems OWNER/NAME` (`problem=[SECTION] KEY: TEXT`),
`print-ext-page-contributions OWNER/NAME`.

## Pitfalls

- Never put a comment after a value: `ctrl+k = greet # hi` makes `# hi` part of ARGS.
- A bare letter or Enter binding without `!textInputFocus`/`viewFocus`/`view == …` is refused.
- Status text is one line of 120 bytes; more than 8 items (manifest included) is `toobig`.
- `[keys]` and `[menu.*]` name an own command by its local name (`greet`, not `hello.greet`) and
  may name `rhun.NAME` or another extension's `EXT.NAME`; `[status]` and command references name
  only the extension's own commands.
- The spec's own examples put `# …` after values in `[command-options]`, `[menu.*]` and `where`;
  the manifest rule (v1 section 2) has no comments after a value: keep comments on their own line.
- Read `inv.from`: the same command runs from the palette (no body), a key (ARGS) and a menu
  (TARGET + args); handle an empty body.
- Without `command-args` agreed (an older rhun) every run still reaches `invoke`/`Invoke` when
  the handler has it, with an empty `from` and no body; Go handlers without `Invoker` get `Run`,
  Rust's default `invoke` calls `command`.
