# Testing

Three layers, in this order: the unit tests (`cargo test`, `go test ./...`), the conformance
checker, then a headless rhun driven by a script whose output is compared with an expected file.
The templates have all three: `tests/check.sh` and `tests/run.sh` with `tests/basic.txt` and
`tests/basic.expected`.

## The conformance checker
`go run github.com/rhun-editor/extension-protocol/conformance/ext@latest DIR` (or build it from a
clone: `go build -o rhun-ext-check ./conformance/ext`), where `DIR` is the extension laid out as
installed: `DIR/extension.ini`, `DIR/bin/NAME-TARGET`, the icon and every data folder the manifest
names. It plays rhun without a display: the handshake and features, every command on four documents
(as the palette runs it: `palette 0` with `command-args`), the edits stream, hover, every language
feature you agreed on a document your `[provides]` patterns match (answers checked against the
grammar and the document, workspace edits applied as rhun would, `apply` served), your views'
events and every picture and patch, the 1.1 requests of each agreed feature, an unknown event, an
error reply, fragmented and coalesced input, a burst of 2000 events, `bye` and the end of input. It
also checks the manifest: `[keys]`, `[menu.*]`, `[status]`, `[context]`, `[icons]` and every when
clause (compiled as rhun compiles them), `[language.*]`, `syntax/*.syn`, `icon-themes/*.icons`,
`[views]`, `[debugger.*]` (and `debug-resolve` once per template section of a `resolve = yes`
debugger), `[tools]`, `where`, `pack`. It prints `ok` or `FAIL name: why` per check and exits 1 on
a failure.

| Flag | Does |
| --- | --- |
| `-v` | prints the whole exchange |
| `-target T` | the `run.T` program to start (default: this machine's; `wasm32-wasip1` for the module) |
| `-rhun PATH` | the rhun that runs a module (`rhun --wasm-host`) |
| `-test-exec-script FILE` | how it answers `test-exec` (lines `out TEXT`, `err TEXT`, `sleep MS`, `exit CODE`); without it `test-exec` is refused |
| `-test-timeout D` | how long a test run may take (default 60s) |

It does not agree `workspace_watch`, `view-form`, `view-table`, `view-doc`, `quick-input`,
`markdown`, `decorations`, `diagnostic-tags` or the presentation providers (`features.md`): test
those headlessly. While the SDK you build against is a local checkout (an unreleased addition),
run that checkout's checker: the templates' `tests/check.sh` takes `RHUN_EXT_CHECK=PATH` (and
template-go `RHUN_EXT_SDK=DIR`, which also writes a `go.work`).

## Headless rhun
```sh
W=$(mktemp -d)
mkdir -p $W/proj $W/exts/OWNER/NAME/bin $W/config/rhun $W/state $W/tmp
HOME=$W XDG_CONFIG_HOME=$W/config XDG_STATE_HOME=$W/state TMPDIR=$W/tmp \
  rhun $W/proj --headless 1000x600 --scale 1 --extensions $W/exts --script test.txt 2>&1
```
`$W/exts/OWNER/NAME/` holds the extension as installed. Every run gets its own `HOME`,
`XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `TMPDIR`: never the user's, since rhun writes its config
and session on exit. Put a config in `$W/config/rhun/config` that turns off session restore,
update checks, git and blinking: `[files] restore_session = false`, `restore_project = false`,
`[updates] check = false`, `[git] enabled = false` (leave git on for source control tests),
`[ui] sidebar = false`, `agents_panel = false`, `[editor] cursor_blink = false`. The extension's
state folder is `$XDG_STATE_HOME/rhun/extensions/OWNER--NAME`: a test seeds files there. Logs go
to standard error, so capture `2>&1` when the expected file holds them. Never run rhun with a
window for a test, and never stop processes by name (`pkill rhun` kills the user's editor): stop
your own by pid.

The script is one command per line (v1 section 10 lists the basics):
- `open PATH`, `cmd NAME.command` (or any palette command by its snake case name), `wait-ext NAME
  running`, `wait 300` (twice after a step before reading its effect), `type TEXT`, `key Return`,
  `key ctrl+k` (each stroke of a chord on its own line), `move X Y`, `click X Y [right]`,
  `menu-pick LABEL`, `cmd-args NAME ARGS` (a command reference's run), `when CLAUSE`;
- `print-doc` (the text, then `<eod>`), `print-state`, `print-toast`, `print-marks`,
  `print-hover`, `print-extensions`, `print-views`, `print-complete`, `print-palette`,
  `print-tabs`, `print-tip`, `shot PATH` (a PPM picture);
- the language keys: `key F12`, `key shift+F12`, `key ctrl+r`, `key ctrl+.`, `key F2` (then
  `type NAME`, `key Return`), `key shift+alt+f`.

Compare the output with an expected file using `cmp` (and print a `diff` on a mismatch); strip
what moves: `sed -e 's/pid=[1-9][0-9]*/pid=PID/' -e 's/ at=[0-9,]*/ at=X,Y,W,H/'`. Pixel
positions depend on the platform's font: ask for them in a first run (`print-status`,
`print-views`, `print-text-cell LINE COL`, `print-title-buttons`) and click their middle, as the
templates' `tests/run.sh` does for the status item. Run a new print command once and read its
output before writing the expected file: several 1.1 controls have formats only rhun's source
documents.

## What to print, per feature

| Area | Controls | Reference |
| --- | --- | --- |
| commands, keys, menus | `print-keys [EXT]`, `print-chord`, `key-latin`, `print-menu`, `menu-pick`, `print-title-buttons`, `cmd-args`, `cmd-ref`, `print-contrib-problems OWNER/NAME`, `print-ext-page-contributions EXT` | `contributions.md` |
| when clauses, context keys, status items | `when CLAUSE`, `print-context [KEY]`, `print-status` | `contributions.md` |
| language keys, icon themes | `print-langconf`, `print-icon NAME [folder\|folder-open]` | `contributions.md` |
| workspace edits, selections, linked editing | `print-doc`, `print-tabs`, `print-tx`, `print-journal`, `ext-edits NAME yes\|no`, `print-selections`, `print-linked` | `editing.md` |
| snippets | `print-doc`, `print-state` (`sel=`), `print-complete`, `when snippetActive` | `snippets.md` |
| retained views | `print-views`, `print-view NAME\|VIEW`, `print-log`, `print-form`, `print-docview`, `print-sidebar`, `print-panel-tabs`, `print-side-tabs`, `view-show`, `view-focus`, `view-item-menu` | `views.md` |
| notifications, progress, quick input | `print-notes`, `note-press N B\|close\|cancel`, `print-quick`, `print-tip` | `ui.md` |
| language features | `print-complete`, `hover-at LINE COL`, `print-hover-card`, `print-results`, `print-peek`, `print-outline`, `print-lightbulb`, `print-problems`, `print-file-diagnostics`, `print-doc-links`, `provider-set`, `print-providers`, `print-provides`, `print-langstats`, `print-query` | `language.md` |
| presentation | `print-present KIND`, `print-classes LINE`, `print-hit`, `print-xy` | `presentation.md` |
| terminals, tasks | `term-run`, `wait-terminal`, `print-terminals`, `print-tasks`, `print-task-status`, `print-problems`, `run-approve`, `print-approve`, `print-allowed`, `print-pattern` | `tasks.md` |
| debuggers | `debug-start NAME`, `wait-debug`, `print-debug`, `print-stack`, `print-vars`, `print-console`, `print-configs`, `print-dap-log`, `bp`, `bp-clear` | `debug.md` |
| test controllers | `wait-test-items`, `wait-tests`, `print-tests`, `print-testing`, `print-test-result`, `print-test-runs`, `print-coverage`, `print-gutter`, `test-select`, `test-action` | `test-controllers.md` |
| source control | `wait-git`, `print-git-data`, `print-scm-ext`, `scm-click`, `scm-action`, `scm-menu`, `wait-scm`, `wait-quickdiff`, `print-vcs PATH` | `scm.md` |
| notebooks, custom editors | `print-notebook`, `print-nb-output I J`, `nb-run I`, `nb-mode`, `print-nb-exec`; `print-custom`, `reopen-with`, `custom-backup` | `notebooks.md`, `custom-editors.md` |
| agents, tools | `print-agents`, `agent-new`, `agent-prompt`, `agent-card N`, `print-review`, `review accept\|reject`, `print-tools`, `tool-confirm` | `ai.md` |
| resources | `secret-backend memory`, `print-secrets`, `print-vdocs`, `link-deliver URL`, `print-folders`, `folder-add`, `print-ext-setting`, `print-file-runs`; `RHUN_IDLE_SCALE` | `resources.md` |
| installs, remote, WebAssembly | `ext-install-folder PATH link`, `print-ext-versions`, `print-ext-page-more`, `print-remote`, `print-wasm` | `distribution.md` |

## What to look at
After drawing anything (a picture view, a chart, a custom editor), take a `shot`, convert it to
PNG and look at it: wrong colors, clipped text and misplaced hover bands do not show in text
output. Retained views, notifications and quick input print their rows and positions instead.
