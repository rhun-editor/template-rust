# rhun extension template (Rust)

A rhun extension is a program that [rhun](https://rhun.app) starts and talks to over its standard
input and output, one text line per message. This repository is the smallest useful one, in
Rust on [rhun-ext](https://github.com/rhun-editor/extension-protocol/tree/main/rust/rhun-ext):
two commands, a toast and an edit, with the workflows that test it and release it for Linux,
macOS and Windows.

Written for people and for coding agents: [AGENTS.md](AGENTS.md) is the working guide, and
`.claude/skills/rhun-extension` is a skill Claude Code picks up in this folder (Codex: install
the `rhun` plugin from [rhun-editor/skills](https://github.com/rhun-editor/skills)).

## Make your own

1. **Use this template** on GitHub (or clone it) as `OWNER/NAME`.
2. In `extension.ini` set `name = NAME`, `owner = OWNER`, `title`, your commands and what the
   extension needs (`[needs]`); in `Cargo.toml` set `name = "NAME"`. rhun installs into
   `~/.config/rhun/extensions/OWNER/NAME/`.
3. Change what `command` does in `src/main.rs`. Views (charts and pictures in a tab), completion
   lists and signature help are features: `run(&[Feature::Views], …)` and the matching
   `Handler` methods (section 12 of the [protocol](https://rhun.app/extensions/v1/)).
4. Test: `cargo test`, `sh tests/run.sh` (drives rhun headlessly with `tests/basic.txt` and
   compares with `tests/basic.expected`) and `sh tests/check.sh` (the conformance checker).
5. Tag `vX.Y.Z` (the manifest's `version`). The release workflow builds the three targets on
   their own runners and publishes what **Install from GitHub** takes.

## Versions, development installs and the index

- Each tag installs on its own: `OWNER/NAME@0.1.0` in **Install from GitHub** (or the link
  `rhun://extension/OWNER/NAME@0.1.0`) installs that release; the name alone installs the latest
  release's exact tag. rhun keeps the version an update replaces, so users can **Roll back**, and
  a new version that fails its first start (no `hello` within 5 seconds) rolls back by itself.
- While you work, the Extensions page's **Install** menu has **Link a Folder (development)**: rhun
  runs the extension from your folder (build `bin/` first), so rebuild and **Restart** is the loop.
  **From a Folder** and **From an Archive** install a copy or a release `.tar.gz` you built.
- To be listed under **Browse**, and updated by itself on users' machines, open a pull request to
  [rhun-editor/extensions](https://github.com/rhun-editor/extensions) adding `OWNER/NAME.ini` that
  pins a release's tag and digests; its checks verify the digests and this workflow's attestation.
  An update that asks for more access (`[needs]`) always asks users first.
- A pack installs several extensions together: an extension without a program whose
  `extension.ini` says `pack = OWNER/NAME …` (at most 16). Release it like any other, with
  `NAME-TARGET.tar.gz` (its `extension.ini`, `README.md` and `LICENSE`) for each target and
  `sha256sums.txt`.

## One module for every system (WebAssembly)

Instead of three binaries, an extension can ship one WebAssembly module that rhun runs itself on
Linux, macOS and Windows, held to its `[needs]` on every system. In `extension.ini` replace the
three `run.TARGET` lines with

```ini
run.wasm32-wasip1 = bin/hello.wasm
```

`rustup target add wasm32-wasip1`, then `cargo build --release --target wasm32-wasip1` builds it
(`rhun-ext` needs no threads there), `sh tests/run.sh` tests it when the manifest names no
program for your machine, and the release workflow packs it into every archive. Keeping the
`run.TARGET` lines as well gives those systems the native binary (faster at heavy work) and the
module to any other. What the module may use (WASI preview 1, no sockets, no processes): section
"WebAssembly extensions" of [protocol 1.1](https://rhun.app/extensions/v1.1/).

## State and environment

Your extension's folder is read-only once installed. Write to `$RHUN_STATE`, which is also its
`HOME`. `$RHUN_PROJECT` is the project folder when there is one. Standard error goes to a log
file rhun keeps under 1 MB; standard output is the protocol's.
