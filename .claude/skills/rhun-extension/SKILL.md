---
name: rhun-extension
description: Build, test and release extensions for the rhun editor in Rust (preferred), Go, C or C++ - commands, edits, diagnostics, hover, settings, views that draw charts and pictures, completion, signature help, go to definition, references, symbols, code actions, rename and format. Use when asked to write, change, debug or publish a rhun extension, or when a repository has an extension.ini with protocol = 1.
---

# Writing a rhun extension

A rhun extension is a program rhun starts and talks to over its standard input and output, one
text line per message. There is no plugin API inside the editor, no JavaScript, no web view: the
extension is a native binary (or a script with a runtime), the editor sends it events, it sends
requests and rhun answers each one. Everything is in the spec, written for agents:
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1/v1.md - read sections 1-3
before writing code, and the section of every feature you use.

## Choose the language

- **Rust** (default): start from https://github.com/rhun-editor/template-rust, SDK `rhun-ext`
  (`reference/rust.md`). Small static binaries, the richest SDK (charts included).
- **Go**: https://github.com/rhun-editor/template-go, SDK `rhunext` (`reference/go.md`).
- **C or C++**: one header, `rhunext.h` (`reference/c.md`); the examples `rhun-editor/wordfreq`
  (C, views) and `rhun-editor/words` (C++, completion).
- Not TypeScript or Python for anything you ship: users would need a runtime installed.

## The workflow

1. Copy the template (or `git clone` it), then rename: `name` and `owner` in `extension.ini` must
   equal the GitHub repository's owner and name; the binary is `bin/NAME-TARGET`.
2. Write the manifest first (`reference/manifest.md`): commands, `[subscribe]` for the events
   you need, `[needs]` for what you touch, `[provides]` for the language features you answer,
   `[settings]` for options the user sets. Ask only for what you use: the install dialog shows
   it.
3. Write the handler with the SDK. Never write to standard output yourself: that is the
   protocol's pipe. Log to standard error (rhun keeps it, 1 MB).
4. Test, in this order, and fix until all pass:
   - the unit tests (`cargo test` / `go test ./...`);
   - the conformance checker: `rhun-ext-check DIR` on the installed layout
     (`DIR/OWNER/NAME/extension.ini` + `bin/`), which plays rhun and reports every protocol
     mistake (`reference/testing.md`);
   - the headless test: `tests/run.sh` drives the real rhun with a script and compares its
     output (`rhun --headless`, section 10 of the spec). Every run gets its own `HOME`,
     `XDG_CONFIG_HOME` and `XDG_STATE_HOME`: never the user's own.
   - for a view or a list, a `shot PATH` and a look at the picture.
5. Release: set `version`, commit, tag `vX.Y.Z` (the same). The template's release workflow
   builds Linux x86-64, macOS arm64 and Windows x64 and publishes `NAME-TARGET.tar.gz` and
   `sha256sums.txt`; users install with **Install from GitHub** and `OWNER/NAME`.

## Rules that bite

- Positions are **1-based lines and 1-based byte columns** of UTF-8 text, never characters or
  UTF-16 units. Ranges are half-open. Converting from LSP (UTF-16) is your job.
- Every request carries an id; rhun answers `ok ID …` or `error ID CODE TEXT`. The SDKs do this:
  use their calls, which block until the answer. An edit names the document's `VERSION`; a
  stale version is refused (`error ID stale`): fetch the text again and retry once.
- Bodies are byte-counted (`LEN` last on the line, then exactly `LEN` bytes). Let the SDK frame.
- Events you did not subscribe to never come. `opened` gates everything about a document.
- rhun stops an extension that floods it (hundreds of messages per 16 ms), sends lines over
  64 KB, or misses `hello` for 5 s. Batch work; do not answer every keystroke with a request.
- Features of section 12 are asked for in `hello` (the SDK's run call takes them) and only the
  ones rhun says back in `0 features` exist. A provider must also list them in `[provides]`.
- Views: draw in logical pixels with theme colors (`fg`, `muted`, `accent`, `c1`-`c8`, …) so the
  picture follows the theme; redraw on `size` and `metrics`. Keep pictures small (1 MB, 20000
  shapes) and redraw only when something changed.
- Completion answers are filtered and ranked by rhun as the user types: return every candidate
  for the word (up to 4096), not a pre-filtered top few; mark the list incomplete when you cut it.
- Rename, format and code actions answer with a **workspace edit**: every group names the
  version it was made for (`-` for a file that is not open), and rhun refuses the whole edit if
  one document moved on, a range is outside its text or two edits overlap. Build the edits from
  the text at the request's version, never from a later read.
- Paths in locations and edits are absolute (or `#DOC` for an untitled document). Do not send
  relative paths or `file://` URIs.

## Reference

- `reference/manifest.md`: every manifest key, with the values rhun accepts.
- `reference/protocol.md`: the messages in one page.
- `reference/rust.md`, `reference/go.md`, `reference/c.md`: the SDKs, with recipes.
- `reference/testing.md`: the checker, headless scripts, what each `print-` command shows.
