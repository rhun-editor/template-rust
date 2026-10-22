# Where it runs and how it ships (protocol 1.1)

Remote windows, WebAssembly modules, packs, releases, the extensions index, updates and
development installs. None of these is a `hello` feature: they are manifest keys and release
assets. Spec: "Remote windows: `where` and the host", "WebAssembly extensions:
`run.wasm32-wasip1`", "Packs and the install record" of
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md, v1 section 11
("Releases and installing"), and the user's side in rhun's user guide (`docs/guide.md`, "Install
and manage").

## Remote windows: `where`

A remote window (`rhun --remote ssh:HOST PATH`, Connect to Host, Attach to Container, Connect to
WSL) has its files, terminals, git and extensions on a Linux x86-64 host. The protocol does not
change: paths are the host's absolute paths and the pipe is relayed byte for byte.

```ini
# workspace (the default): runs on the host | local: runs on this computer
where = local
```

- `where = workspace` runs on the host: ship `run.linux-x86_64` in every release (rhun fetches
  `NAME-linux-x86_64.tar.gz` when the installed folder holds another system's build), or be a
  script (`runtime` + `run`, the runtime on the host's login PATH) or a WebAssembly module. The
  environment has the host's `HOME`, `RHUN_STATE`, `RHUN_PROJECT`, `RHUN_TARGET=linux-x86_64`
  and `RHUN_REMOTE` (`ssh:HOST`, `docker:NAME`, `podman:NAME`, `wsl:DISTRO`).
- `where = local` runs on the user's computer even in a remote window; it may not ask for
  `project` or `home` in `[needs]` (the manifest is refused there, and the checker says so) and
  reads documents through the protocol only. For a spell checker, or a bridge to a service with
  this computer's sign-in.
- When clauses read `remoteName` and `remoteHost`. A page served on the host's loopback goes
  through `external-uri` (feature `urls`) before `open-url`, which forwards the port.
- Headless: `print-remote`, `remote-connect SPEC [PATH]`, `wait-remote`, `print-forward-url URL`.

## WebAssembly: `run.wasm32-wasip1`

```ini
run.wasm32-wasip1 = bin/NAME.wasm
```

One `wasm32-wasip1` (WASI preview 1) module runs on Linux, macOS and Windows; rhun runs it
itself (`rhun --wasm-host`), so nothing needs installing. A `run.TARGET` for this system wins, so
a manifest may name native builds and the module for every other system.

| Language | Build |
| --- | --- |
| Rust | `rustup target add wasm32-wasip1`, `cargo build --release --target wasm32-wasip1` (rhun-ext reads without threads there) |
| Go | `GOOS=wasip1 GOARCH=wasm go build -o bin/NAME.wasm .` |
| C, C++ | `clang --target=wasm32-wasip1 --sysroot=$WASI_SYSROOT -O2 main.c -o bin/NAME.wasm` |

- Files: the state folder (read and write), the extension's own folder (read only), the project
  with `project = read|write`, home with `home = read`, as preopened directories named by their
  absolute paths (`/C:/Users/me/proj` on Windows). Everything else is `ENOTCAPABLE`.
- No sockets and no processes (WASI preview 1 has none): `network` and `run` grant nothing, so a
  module cannot run `gofmt` or reach a server. It is always `confined=1`.
- WebAssembly 2.0 without SIMD; 256 MB of memory; a trap exits with 134 and the message in the
  log. Computation is 15 to 40 times slower than native: keep heavy work native.
- Test: `rhun-ext-check -target wasm32-wasip1 -rhun RHUN DIR` (the checker runs it through
  `rhun --wasm-host`); the templates' `tests/run.sh` builds the module when the manifest names
  no program for the machine. Headless `print-wasm` lists `OWNER/NAME module=PATH` per module.

## Releases

A tag `vVERSION` equal to the manifest's `version`. Assets, for each target the manifest names:
`NAME-TARGET.tar.gz` (the folder's contents at its top level: `extension.ini`, `bin/…`, the
icon, `themes/`, `syntax/`, `icon-themes/`, `icons/`, debugger templates, anything the manifest
names; plain files only, no links) and `sha256sums.txt`. The templates' `release.yml` builds
Linux x86-64 (Rust: musl, static), macOS arm64, Windows x64 (Rust: `+crt-static`) and the module
when the manifest names one, attests the archives and publishes them. The folder each archive
holds is made by `tests/layout.sh DEST` (also used by `tests/run.sh` and `tests/check.sh`): every
file and folder at the repository's top except source, tests and build files. It leaves out names
starting with a dot, `tests`, `AGENTS.md`, `CLAUDE.md`, `bin` and `dist`, plus Go's `*.go`,
`go.mod`, `go.sum`, `go.work*`, `internal`, `cmd`, `pkg`, or Rust's `target`, `out`, `src`,
`build.rs`, `Cargo.*`, `rust-toolchain*`, `rustfmt.toml`, `clippy.toml`, `deny.toml`; the program
is built into `DEST/bin`. It fails on a link. Add your own source folders to its exclusion list.

Users install with **Install from GitHub** and `OWNER/NAME` (or `OWNER/NAME@0.1.0` for one tag;
`rhun://extension/OWNER/NAME[@VERSION]` links do the same). rhun refuses archives over 64 MB,
with links, devices or paths outside themselves, or whose manifest names another owner or name.

## Packs

```ini
# no run entries: a pack never starts; at most 16 members
pack = rhun-editor/lsp rhun-editor/format rhun-editor/editorconfig rhun-editor/snippets
```

Installing the pack installs every missing member in one dialog; removing it keeps them. There
are no dependencies between extensions: a pack is how to say "install these too". Release it like
any extension (the same archive per target). Example: `rhun-editor/essentials`.

## Versions, updates and the index

- rhun keeps the version an install or update replaced (**Roll back**); a version that fails its
  first start (no `hello` within 5 s, or it exits first) rolls back by itself. Never ship a
  `.rhun-install` file: rhun writes it.
- Updates: an extension listed in the index (https://github.com/rhun-editor/extensions) is
  offered only the reviewed version and installs by itself; any other is offered its latest
  GitHub release and asks. An update that asks for more `[needs]` always asks first.
- To be listed under **Browse**: a pull request to `rhun-editor/extensions` adding
  `OWNER/NAME.ini` with `category`, `keywords`, `tag`, `commit` and `sha256.TARGET` per archive
  (optionally `rhun = 0.19.0`, the oldest rhun it works with). Its checks verify the digests,
  run `rhun-ext-check` on the Linux build and verify the release workflow's attestation.

## Development installs

The Extensions page's **Install** menu: **Link a Folder (development)** runs the extension from
your working folder (build `bin/` first; rebuild, then **Restart**); **From a Folder** copies a
folder laid out like an archive; **From an Archive** takes a `.tar.gz` you built (with
`sha256sums.txt` beside it when there is one). These are never offered updates. Headless:
`ext-install-folder PATH [copy|link]`, `ext-install-archive PATH`, `ext-rollback NAME`,
`print-ext-versions NAME`, `ext-check-updates`, `wait-ext-updates`, `print-ext-updates`,
`print-ext-page-more`; `RHUN_EXT_BASE` serves releases from disk (`BASE/OWNER/NAME/releases/
latest/download/ASSET`) for install and update tests.

## Pitfalls

- An extension meant for remote windows without a `run.linux-x86_64` build (or a script or
  module) fails there.
- On Windows standard output must be binary: a text stream turns LF into CR LF and breaks every
  body length. The SDKs handle it (`rhunext.h` sets `_O_BINARY` in `rx_run`; Rust and Go write
  bytes as they are); a hand-rolled C program or a script must do it itself (Python:
  `sys.stdout.buffer`).
- A module that needs `run` or `network` cannot work as WebAssembly; ship native builds.
- A source or scratch folder at the repository's top that `tests/layout.sh` does not exclude
  ships to every user; add it to the script's exclusion list. Links make the layout fail.
