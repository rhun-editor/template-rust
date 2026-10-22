# extension.ini

INI, UTF-8, `key = value`. Comments are whole lines starting with `#` or `;`: **never put a
comment after a value** (`name = words  # x` makes the name `words  # x`). Schema:
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1/v1.json

```ini
# required: [a-z0-9][a-z0-9-]*, the repository's name
name = words
# required: the GitHub owner
owner = rhun-editor
# required: shown in the palette after command titles
title = Words
# one line, at most 200 bytes
description = Completion from the words in your open files.
# a square PNG in the folder (128 px recommended; at most 256 px a side and 64 KB), and the
# badge's background
icon = icon.png
color = #3f9f6f
# required; the release tag is vVERSION
version = 0.1.0
protocol = 1
run.linux-x86_64 = bin/words-linux-x86_64
run.macos-arm64 = bin/words-macos-arm64
run.windows-x64 = bin/words-windows-x64.exe
# when to start: startup (the default) | command | lang:LANG | open:GLOB | project
on = command

# a script instead of run.TARGET lines: runtime = python3, run = main.py, requires = python3 >=
# 3.10 (shown when the runtime is missing); args = extra arguments, space separated
# key = Title | default keys; in the palette as words.stats
[commands]
stats = Count Distinct Words | ctrl+alt+w

# string | bool | int (0 to 2147483647) | choice (with KEY.options = a b c, space separated);
# values arrive as `setting` events
[settings]
limit.type = int
limit.default = 500
limit.min = 1
limit.max = 4096
limit.title = Items at most
limit.description = How many words a list offers.

# events and the file names they are sent for: *, *.rs, Makefile; "no" (the default) for none
[subscribe]
opened = *
saved = *.rs
changed = no
cursor = no
selection = no
# every change as byte deltas (section 6a)
edits = *.rs
# the pointer rests on a position
hover = *.rs

# section 12: rhun asks the extension; a provider gets opened and edits for these files as if
# subscribed, and the first such file to open starts it
[provides]
complete = *.rs *.go
complete.triggers = . :
signature = *.rs
signature.triggers = ( ,
definition = *.rs
references = *.rs
symbols = *.rs
actions = *.rs
rename = *.rs
format = *.rs

# section 5: what it may touch; the install dialog shows it
[needs]
# none | read | write (write: replace, insert)
documents = read
# none | read | write: the project folder on disk
project = read
home = none
network = no
# suggest commands in rhun's terminal
terminal = no
# programs it may start
run = gofmt rustfmt
```

## Protocol 1.1 keys (rhun 0.18)

Schema: https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.json. A
key or section rhun 0.18 does not know is ignored. A bad line in `[command-options]`, `[keys]`,
`[menu.*]`, `[status]`, `[context]`, `[icons]`, `[language.*]` or `[views]` drops that entry
(listed on the extension's page and by the checker); a bad `pack` list fails the manifest. Each
line below names the reference page with the details.

```ini
# workspace (default) | local: where it runs in a remote window (distribution.md)
where = workspace
# a WebAssembly module, for systems without a run.TARGET (distribution.md)
run.wasm32-wasip1 = bin/words.wasm
# a pack: other extensions installed with this one; no program needed (distribution.md)
# pack = rhun-editor/lsp rhun-editor/format
# stop after idle.after seconds without work; it starts again when needed (resources.md)
idle = stop
idle.after = 300
# on also takes contains:NAME, started when a workspace folder has such a file (resources.md)
on = contains:Cargo.toml

[settings]
# user (default) | workspace | folder; yes: values per language (resources.md)
limit.scope = workspace
limit.languages = yes

[provides]
# language features (language.md); presentation (presentation.md)
hover = *.rs
declaration = *.rs
type_definition = *.rs
implementation = *.rs
selection_ranges = *.rs
call_hierarchy = *.rs
type_hierarchy = *.rs
workspace_symbols = *.rs
range_format = *.rs
type_format = *.rs
type_format.triggers = ; } newline
document_links = *.rs
folding = *.rs
semantic_tokens = *.rs
inlay_hints = *.rs
code_lens = *.rs
highlights = *.rs
colors = *.css
inline_complete = *.rs
# editing.md
linked = *.html
save_actions = *.go
# test-controllers.md, scm.md, notebooks.md, custom-editors.md, ai.md, resources.md
tests = *_test.go
tests.profiles = run debug coverage
quickdiff = *
commit_message = yes
notebook = *.ipynb
editor = *.bin
agents = yes
schemes = words

[needs]
# terminal: no | suggest (v1's yes) | run | input | output (tasks.md)
terminal = run
# git = read: Git data through rhun (scm.md); secrets = yes: the keychain (resources.md)
git = read
secrets = yes
# debug = yes: debug adapters as the user (debug.md); tests, kernels: programs run as the user
debug = yes
tests = go cargo
kernels = python3
```

Sections, each on its page: `[command-options]`, `[keys]`, `[menu.LOCATION]`, `[submenu.NAME]`,
`[status]`, `[context]`, `[icons]`, `[language.NAME]` (`contributions.md`); `[views]`
(`views.md`); `[tools]` (`ai.md`); `[debugger.TYPE]` (`debug.md`). Data folders: `syntax/`,
`themes/`, `icon-themes/` (`contributions.md`). Comments stay whole lines here too: some of the
1.1 spec's examples put a `#` comment after a value, which rhun reads as part of the value.
