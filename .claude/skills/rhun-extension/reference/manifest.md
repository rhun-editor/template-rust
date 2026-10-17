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
# one line, under 200 bytes
description = Completion from the words in your open files.
# a square PNG in the folder, 128 px, at most 64 KB, and the badge's background
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

# key = Title | default keys; in the palette as words.stats
[commands]
stats = Count Distinct Words | ctrl+alt+w

# string | bool | int | choice; values arrive as `setting` events
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
