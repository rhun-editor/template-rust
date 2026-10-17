# Testing

## The conformance checker
`go run github.com/rhun-editor/extension-protocol/conformance/ext@latest DIR` (or build it from a
clone: `go build -o rhun-ext-check ./conformance/ext`), where `DIR` is the extension laid out as
installed: `DIR/extension.ini`, `DIR/bin/NAME-TARGET`, the icon. It plays rhun: the handshake and
features, every command on four documents, the edits stream, hover, completion and signature
requests on a document your `[provides]` patterns match (answers checked against the grammar
and the document), your views' events and every picture, an unknown event, an error reply,
fragmented and coalesced input, a burst of 2000 events, `bye` and the end of input. It prints
`ok` or `FAIL name: why` per check and exits 1 on a failure. `-v` prints the whole exchange.

## Headless rhun
```sh
HOME=$W XDG_CONFIG_HOME=$W/config XDG_STATE_HOME=$W/state \
  rhun $W/proj --headless 1000x600 --scale 1 --extensions $W/exts --script test.txt
```
`$W/exts/OWNER/NAME/` holds the extension as installed. Put a config in
`$W/config/rhun/config` that turns off session restore, update checks and git:
`[files] restore_session = false`, `restore_project = false`, `[updates] check = false`,
`[git] enabled = false`, `[ui] sidebar = false`, `agents_panel = false`.

The script, one command per line (section 10 of the spec has them all):
- `open PATH`, `cmd NAME.command`, `wait-ext NAME running`, `wait 300` (twice after a step
  before reading its effect), `type TEXT`, `key Return`, `key ctrl+space`, `move X Y`,
  `click X Y`;
- `print-doc` (the text, then `<eod>`), `print-state`, `print-toast`, `print-marks`,
  `print-hover`, `print-extensions`, `print-views` (`view=ID title=T shapes=N size=WxH
  at=X,Y`), `print-complete` (the list and the signature help), `shot PATH` (a PPM picture).

Compare the output with an expected file (`tests/basic.expected`); strip pids
(`sed 's/pid=[1-9][0-9]*/pid=PID/'`).

## What to look at
After drawing anything (a view, a chart), take a `shot`, convert it to PNG and look at it:
wrong colors, clipped text and misplaced hover bands do not show in text output.
