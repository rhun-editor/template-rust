---
name: rhun-extension
description: Build, test and release extensions for the rhun editor (protocol 1, with the 1.1 features of rhun 0.18) in Rust (preferred), Go, C or C++ - commands with arguments, keys, chords, menus, status items, when clauses, workspace edits, snippets, views (pictures, charts, trees, logs, forms, tables, Markdown), notifications, progress, quick input, completion, hover, navigation, hierarchies, code actions, rename, format, diagnostics, semantic tokens, inlay hints, code lens, decorations, tasks and problem matchers, debug adapters, test controllers, source control panels, notebooks, custom editors, agents and tools, secrets, sign-in, virtual documents, remote windows, WebAssembly and packs. Use when asked to write, change, debug or publish a rhun extension, or when a repository has an extension.ini with protocol = 1.
---

# Writing a rhun extension

A rhun extension is a program rhun starts and talks to over its standard input and output, one
text line per message. There is no plugin API inside the editor, no JavaScript, no web view: the
extension is a native binary (or a WebAssembly module, or a script with a runtime), the editor
sends it events and requests, it sends requests and rhun answers each one. The specs are written
for agents: v1 (frozen)
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1/v1.md (read sections 1-3
before writing code) and protocol 1.1 (rhun 0.18), every addition negotiated by name in `hello`:
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md (read the
section of every feature you use; the reference pages here name them).

## Choose the language and the template

- **Rust** (default): https://github.com/rhun-editor/template-rust, SDK `rhun-ext`
  (`reference/rust.md`): `rhun-ext = { git = "https://github.com/rhun-editor/extension-protocol",
  tag = "rust-v1.4.2" }`. The richest SDK (charts included), small static binaries.
- **Go**: https://github.com/rhun-editor/template-go, SDK `rhunext` (`reference/go.md`):
  `go get github.com/rhun-editor/extension-protocol@v1.4.2`. Go alone parses snippet templates and
  compiles regex transforms from source (`snippets.md`).
- **C or C++**: one header, `c/rhunext.h` of the same repository (`reference/c.md`); examples
  `rhun-editor/wordfreq` (C, views) and `rhun-editor/words` (C++, completion).
- Not TypeScript or Python for anything you ship: users would need a runtime installed. For one
  file that runs everywhere, build any of the three as WebAssembly (`distribution.md`).

SDK v1.4 speaks protocol 1.1: Rust `rhun-ext` from the tag `rust-v1.4.2`, Go
`github.com/rhun-editor/extension-protocol@v1.4.2` (the templates pin them).

## The workflow

1. **Pick the features.** Map what the user wants onto features with `reference/features.md`:
   each row names the `hello` feature, the manifest keys and the reference page. Ask only for
   what you use: `[needs]` is shown in the install dialog, and every extra feature is more to
   test. Prefer a manifest-only contribution (`[keys]`, `[menu.*]`, `[status]`,
   `[language.NAME]`, icon themes) when it does the job.
2. **Start from the template.** With rhun 0.18.1 or later, `rhun new-extension DIR --name NAME
   --owner OWNER --lang rust|go --skills --yes` downloads the template, renames it to
   OWNER/NAME and copies this skill in for Claude Code (`.claude/skills`) and Codex
   (`.agents/skills`); without flags in a terminal it asks, and the palette has **Extensions: New
   Extension…**. With rhun 0.18.0, copy (or `git clone`) template-rust or template-go, then
   rename: `name` and `owner` in `extension.ini` equal the GitHub repository's owner and name; the
   binary is `bin/NAME-TARGET` (also `Cargo.toml`'s `name`, or `main.go`'s comments). Keep its
   tests. Only themes, grammars, icon themes or language keys, and no commands? From 0.18.1 that is
   a data extension: no `run`, `runtime`, `[commands]` or `[provides]`, and no program to build.
3. **Declare every feature twice.** In `hello`: the SDK's run call takes them (Rust
   `run(&[Feature::CommandArgs, Feature::ViewTree], h)`, Go `rhunext.RunWith([]string{…}, h)`, C
   `rx_run("command-args view-tree", &h, NULL)`). In the manifest: the feature's `[provides]`
   key with file patterns, its `[needs]`, its sections (`[views]`, `[tools]`, `[debugger.TYPE]`,
   …). rhun asks a provider only when both are there, and agrees only what it knows: check
   `has(feature)` before a request that needs one, and keep working without it.
4. **Write the manifest first** (`reference/manifest.md`), then the handler with the SDK. Never
   write to standard output yourself: it is the protocol's pipe. Log to standard error (rhun keeps
   it, 1 MB).
5. **Test, in this order, and fix until all pass** (`reference/testing.md`):
   - the unit tests (`cargo test` / `go test ./...`);
   - the conformance checker, `tests/check.sh` (`rhun-ext-check DIR`, `DIR` the extension's own
     folder as installed: `DIR/extension.ini`, `DIR/bin/NAME-TARGET`, the icon, the data folders;
     the folder's name is the manifest's `name`): it plays rhun, asks every feature it
     agrees, checks every answer and the manifest (keys, menus, when clauses, views, debuggers);
     it does not agree `workspace_watch`, `view-form`, `view-table`, `view-doc`, `quick-input`,
     `markdown`, `decorations`, `diagnostic-tags` or the presentation providers, so those are
     tested headlessly only;
   - the headless test, `tests/run.sh`: the real rhun runs `tests/basic.txt` (`rhun PROJECT
     --headless 1000x600 --scale 1 --extensions DIR --script FILE`) and its output must equal
     `tests/basic.expected`. Every run gets its own `HOME`, `XDG_CONFIG_HOME`,
     `XDG_STATE_HOME` and `TMPDIR`, never the user's; never a rhun window; never kill processes
     by name. Each feature has its print commands: `print-keys`, `print-menu`, `print-status`,
     `when` for contributions; `print-view`, `print-log`, `print-form`, `print-docview` for
     views; `print-notes`, `print-quick` for cards and pickers; `print-complete`,
     `print-hover-card`, `print-results`, `print-problems` for language features;
     `print-present` for presentation; `print-tasks`, `print-terminals` for tasks;
     `print-debug` for debuggers; `print-tests` for test controllers; `print-scm-ext` for
     source control; `print-notebook`, `print-custom` for notebooks and editors; `print-agents`,
     `print-review`, `print-tools` for AI; the full table is in `testing.md` and on each page;
   - for anything drawn (a picture view, a chart, a custom editor), a `shot PATH` and a look at
     the picture.
6. **Windows.** Standard output must be binary: a text stream turns LF into CR LF and every body
   length breaks. The SDKs do it (`rx_run` sets `_O_BINARY`; Rust and Go write bytes as they
   are); a hand-written program or a script must (Python: `sys.stdout.buffer`). Absolute paths
   are drive paths there (`C:/…`; the `0 folders` event uses native `\` separators): never test
   for a leading `/`.
7. **Release** (`reference/distribution.md`): set `version` (and `Cargo.toml`'s), commit, tag
   `vX.Y.Z`. The template's release workflow builds Linux x86-64, macOS arm64, Windows x64 (and
   the WebAssembly module when the manifest names one) and publishes `NAME-TARGET.tar.gz` and
   `sha256sums.txt`. The archive is laid out by `tests/layout.sh`, which `tests/run.sh` and
   `tests/check.sh` use too: it ships every file and folder of the repository except source,
   tests and build files (and refuses links), so data folders ship by themselves; add your own
   source folders to its exclusion list. Users install with
   **Install from GitHub** and `OWNER/NAME`; while developing, **Link a Folder (development)**
   runs it from the working folder. To list it under Browse, run `rhun submit-extension` in the
   repository after the release (rhun 0.18.1; palette **Extensions: Submit to Index…**): it writes
   the index entry from the release's digests and opens the pull request to
   `rhun-editor/extensions` (through `gh` when it is logged in, else GitHub's page in the browser).
   The index checks that the release is attested by the repository's own `release.yml`, as the
   templates' is.

## Rules that bite

- Positions are **1-based lines and 1-based byte columns** of UTF-8 text, never characters or
  UTF-16 units. Ranges are half-open. Converting from LSP (UTF-16) is your job.
- Every request carries an id; rhun answers `ok ID …` or `error ID CODE TEXT`. The SDKs do this:
  use their calls, which block until the answer. An edit names the document's `VERSION`; a
  stale version is refused (`error ID stale`): fetch the text again and retry once, never loop.
- Bodies are byte-counted (`LEN` last on the line, then exactly `LEN` bytes). Let the SDK frame.
- Events you did not subscribe to never come. `opened` gates everything about a document.
- rhun stops an extension that floods it (hundreds of messages per 16 ms), sends lines over
  64 KB, or misses `hello` for 5 s. Batch work; do not answer every keystroke with a request.
- A feature exists only when rhun says it back in `0 features`; a provider also needs its
  `[provides]` key. Names are exact (`workspace_watch` has an underscore; `code-actions`
  replaces v1's `actions` requests but the manifest key stays `actions`).
- Commands: with `command-args` every run carries where it came from and a body; menu items,
  keys and status items name commands by their local name; a command reference
  (`command NAME LEN` + ARGS) is how a tree row, a lens, a button or a status item runs one.
- Typing keys (a letter, Enter, arrows… without ctrl, alt or super) bind only with
  `!textInputFocus`, `viewFocus` or `view == …` in the `when` clause; a chord's first stroke needs
  ctrl, alt or super.
- Views: draw pictures in logical pixels with theme colors (`fg`, `muted`, `accent`, `c1`-`c8`,
  …) and redraw on `size` and `metrics`; for lists and trees use retained views (rhun draws and
  keeps them), patched, never resent whole on every change.
- Completion answers are filtered and ranked by rhun as the user types: return every candidate
  for the word (up to 4096), not a pre-filtered top few; mark the list incomplete when you cut it.
- Workspace edits: every text group names the version (or `-`, or with `workspace-edits` a
  `fnv1a64:` hash of the bytes on disk) it was made for; rhun refuses the whole edit if one
  document moved on, a range is outside its text or two edits overlap. Build edits from the text
  at the request's version, never from a later read.
- Paths in locations and edits are absolute (or `#DOC` for an untitled document, or a URI of a
  scheme your extension provides with `uris`). Do not send relative paths or `file://` URIs.
- Programs run as the user (terminals, tasks, `test-exec`, debug adapters, kernels) need their
  `[needs]` and the user's one-time approval per project; a headless test answers the dialog with
  `print-dialog` and `dialog yes`.
- Never put a comment after a manifest value: `#` there is part of the value.

## Reference

- `reference/features.md`: every feature, its manifest keys and its page; what the checker agrees.
- `reference/manifest.md`: every manifest key, with the values rhun accepts.
- `reference/protocol.md`: the messages in one page.
- `reference/rust.md`, `reference/go.md`, `reference/c.md`: the SDKs, with recipes.
- `reference/testing.md`: the checker, headless scripts, what to print for each feature.
- `reference/contributions.md`: commands with arguments, keys and chords, menus, status items,
  when clauses, context keys, language configuration, file icon themes.
- `reference/editing.md`: workspace edits as transactions, file operations, selections, reveal,
  diff tabs, linked editing, save actions. `reference/snippets.md`: snippet fields.
- `reference/views.md`: trees, logs, forms, tables, Markdown documents, picture views.
  `reference/ui.md`: notifications, progress, quick input, Markdown.
- `reference/language.md`: the 1.1 language features. `reference/presentation.md`: decorations,
  folding, semantic tokens, inlay hints, code lens, highlights, colors, inline completion.
- `reference/tasks.md`, `reference/debug.md`, `reference/test-controllers.md`: tasks and problem
  matchers, debug adapters, test controllers.
- `reference/scm.md`: Git data, commit messages, quick diff, source control panels.
- `reference/notebooks.md`, `reference/custom-editors.md`, `reference/ai.md`: notebooks, custom
  editors, agents, reviews and tools.
- `reference/resources.md`: workspace watch, files, folders, scoped settings, secrets, URIs,
  URLs and sign-in, idle stop. `reference/distribution.md`: remote windows, WebAssembly, packs,
  releases, the index, updates, development installs.
- Porting a VS Code extension: the vscode-to-rhun skill of the same plugin
  (`../vscode-to-rhun/SKILL.md`).
