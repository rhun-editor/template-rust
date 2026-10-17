# Working on this rhun extension

This repository is an extension for the rhun editor, written in Rust on the `rhun-ext` crate.
rhun starts the program and talks to it over standard input and output with a line protocol;
there is no in-process API. These are the instructions for a coding agent working here.

## Read first
- The protocol, written for agents:
  https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1/v1.md: sections 1-3
  always, then the section of each thing you touch (2 manifest, 5 permissions, 6 documents and
  edits, 7 limits, 8 messages, 10 testing, 11 releases, 12 views, completion, signature help).
- The SDK reference and recipes: `.claude/skills/rhun-extension/reference/rust.md` (the same
  skill ships for Codex in the `rhun` plugin of rhun-editor/skills).

## Layout
| Path | What |
| --- | --- |
| `extension.ini` | the manifest: `name` and `owner` equal this repository's; commands, `[subscribe]`, `[provides]`, `[needs]`, `[settings]` |
| `src/main.rs` | the `Handler`: `ready`, `event`, `command`, `setting`, `view`, `complete`, `signature`, `bye` |
| `tests/run.sh`, `tests/basic.txt`, `tests/basic.expected` | the headless test: rhun runs `basic.txt`, its output must equal `basic.expected` |
| `tests/check.sh` | the conformance checker against the built extension |
| `.github/workflows/ci.yml`, `release.yml` | tests on push; a `vX.Y.Z` tag publishes the release |

## Loop
1. `cargo clippy --all-targets -- -D warnings && cargo test`
2. `sh tests/run.sh [RHUN]` (rhun on `PATH` or `~/.local/bin/rhun`; install it from
   https://rhun.app). Update `tests/basic.txt` and `tests/basic.expected` with every behavior
   you add: a command's effect shows in `print-doc`, `print-toast`, `print-marks`,
   `print-views`, `print-complete` (section 10 lists them).
3. `sh tests/check.sh`: every line must be `ok`.
4. For anything drawn (a view, a chart): add `shot PATH` to a script and look at the picture.

## Rules
- Never write to standard output (`println!`): it is the protocol's pipe. Use `eprintln!` for
  logs; rhun keeps them in the extension's state folder.
- Positions are 1-based lines and 1-based **byte** columns. Ranges are half-open.
- An edit names the version it was made for; `stale` means the user typed meanwhile: fetch the
  text again and retry once, never loop.
- Commands in `extension.ini` and in `command()` must match (the palette shows the manifest's).
- Ask only for the permissions you use (`[needs]`): the install dialog lists them in plain words.
- Keep messages few: do not answer every keystroke with a request; redraw a view only when what
  it shows changed.
- Tests never touch the user's rhun: every run gets its own `HOME`, `XDG_CONFIG_HOME` and
  `XDG_STATE_HOME` (tests/run.sh does this). Never kill processes by name.
- Releasing: the same version in `extension.ini` and `Cargo.toml`, commit, tag `vVERSION`.
