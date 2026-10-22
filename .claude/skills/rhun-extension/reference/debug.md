# Debuggers (protocol 1.1)

rhun is a Debug Adapter Protocol client: an extension declares debuggers in `[debugger.TYPE]`
sections, rhun starts their adapters after the user's approval and speaks DAP to them itself. No
DAP crosses the extension wire. Declaring debuggers needs no feature and no program; `hello 1
debug` is only for starting and stopping sessions (`debug-start`, `debug-stop`) and for preparing
launches (`debug-resolve`). Manifest: `[needs] debug = yes`, `[debugger.TYPE]`. Spec: v1.1.md
"Debuggers: `[debugger.TYPE]` and feature `debug`" ("Manifest", "Configuration bodies", "Feature
`debug`", "Host request `debug-resolve`"),
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md; users' side:
docs/guide.md "Debugging". Examples: `rhun-editor/debug` (Go, main: Delve, debugpy, lldb-dap,
with a resolver), `rhun-editor/tests` (Go, rhun-0.18: debuggers without `languages`, started by
its test runs' debug profile).

## Manifest

```ini
[needs]
# the adapters run as the user, outside any sandbox, after one approval per extension and project
debug = yes

[debugger.go]
title = Go (Delve)
languages = Go
program = dlv
program.windows-x64 = dlv.exe
paths = ~/go/bin
args = dap --listen=127.0.0.1:${port}
transport = tcp
resolve = yes
templates = debug/go.ini
install = go install github.com/go-delve/delve/cmd/dlv@latest
attr.mode = choice debug test exec
attr.program = path
attr.args = list
attr.env = map
attr.stopOnEntry = bool
```

| Key | Value |
| --- | --- |
| `title` | the picker's and console's name |
| `languages` | grammar names, space separated (none: never offered for F5, only for `debug-start`) |
| `program` | names tried in order on the login PATH and in `paths`, or a path inside the extension's folder (with a `/`); `program.TARGET` per system |
| `paths` | extra folders to search; `~` is the home |
| `args` | words (`"a b"` keeps its space); `args.TARGET` per system; at most 4 KB |
| `transport` | `stdio` (default) or `tcp`: rhun picks a loopback port for `${port}` and connects every 100 ms for 10 s |
| `requests` | `launch attach` (default) |
| `install` | a command shown when `program` is not found |
| `resolve` | `yes`: rhun sends `debug-resolve` before every launch the user starts |
| `templates` | launch.ini fragments in the extension's folder (64 KB each) offered by Debug: Add Configuration |
| `attr.NAME` | `string` (default), `path`, `int`, `bool`, `list`, `map`, `choice A B ...` |

TYPE is `[a-z0-9-]{1,32}`. Variables in `program` and `args`: `${port}`, `${extension}`,
`${state}`, `${project}`, `${config:KEY}`, `${config:KEY|DEFAULT}` (`program =
${config:python|python3}`). At most 8 debuggers per extension, 128 `attr.*` each. An extension
that only declares debuggers needs no `run.TARGET`: rhun never starts it.

Users write `PROJECT/.rhun/launch.ini`, a section per configuration: `type`, `request`, the
attributes, and rhun's own keys (`before = TASK`, `after = TASK`, `compound = A | B`, `server =
HOST:PORT`, and variables such as `${file}`, `${fileDir}`, `${ask:Port}`, `${pick:A|B}`; guide
"Debugging"). The configuration's keys become the launch arguments with the declared types, plus
`type`, `request` and `name`.

## Configuration bodies

```
N LF
KIND PATH_LEN VALUE_LEN LF <PATH><VALUE>      (N times)
<extra records>: context DOC LINE COL LEN + the active document's path (DOC 0: none)
```

KIND `s` string, `n` integer (|v| < 2^53, no leading zeros), `b` `true`/`false`, `z` null. PATH
is dotted: `args.0`, `env.LOG_LEVEL`. Limits: 4096 leaves, 1 MB, PATH 256 bytes and 16 segments,
VALUE 64 KB.

## Feature `debug`

| Direction | Message | Reply |
| --- | --- | --- |
| ext → rhun | `ID debug-start NAME_LEN LEN` + NAME + configuration | `ok ID SESSION` once the adapter started |
| ext → rhun | `ID debug-stop SESSION` | `ok ID` once Stop was asked (`ok` too for a session already over) |
| rhun → ext | `0 debug-ended SESSION CODE` | a session it started is over; CODE `-` when unknown |
| rhun → ext | `ID debug-resolve TYPE REQUEST NODEBUG LEN` + configuration | `ok ID 0` (unchanged), `ok ID LEN` + the complete configuration, `error ID cancelled TEXT` (quietly), `error ID refused TEXT` (shown) |

`debug-start`'s body names one of its own debuggers in the `type` leaf; `request` and `noDebug`
are optional; the other leaves go to the adapter as they are (rhun resolves no variables and
applies no `attr.*` types). Errors: `unknown` (not agreed), `needs` (no `debug = yes`), `syntax`,
`refused not within 10 s of one of your commands` (one session per command; a test run with the
`debug` profile counts), `refused the configuration's type is not one of your debuggers`,
`cancelled` (approval declined), `busy`, `toobig 8 sessions`, `refused TEXT` (the adapter did not
start). `debug-resolve` comes before every launch the user starts (not the extension's own
`debug-start`), with variables replaced, types applied, `type`/`request`/`name` and a `context`
record; it may `choose`/`ask`; rhun waits 60 s and Stop sends `0 cancel ID`.

## SDK

| | Rust | Go | C |
| --- | --- | --- | --- |
| feature | `Feature::Debug` | `FeatureDebug` | `"debug"` |
| configuration | `DebugConfig` (`new`, `set`, `get`, `get_str`, `list`, `set_list`, `remove`, `encode`, `parse`) of `DebugValue::{Str, Int, Bool, Null}` | `DebugConfig` (`Set`, `Get`, `String`, `List`, `SetList`, `Remove`, `Encode`), `ParseDebugConfig`, values `DebugStr`, `DebugInt`, `DebugBoolean`, `DebugNil` | `rx_debug_config` with `rx_debug_config_set(c, 's', path, value)`, `_get`, `_remove`, `_encode`, `_parse`, `_free` |
| start, stop | `ext.debug_start(name, &cfg)` → session, `ext.debug_stop(session)` | `ext.DebugStart(ctx, name, cfg)`, `ext.DebugStop(ctx, session)` | `rx_debug_start`, `rx_debug_stop` |
| ended | `DebugEnded::parse(&ev)` (`session`, `code: Option<i32>`) | `ParseDebugEnded(ev)` (`Session`, `Code`, `HasCode`) | `rx_parse_debug_ended` |
| resolve | `Handler::resolve_debug(&DebugResolve) -> Resolved` (`Unchanged`, `Config`, `Cancel`, `Refuse(text)`); `req.config`, `req.doc` | `DebugResolver.ResolveDebug(ext, DebugResolveRequest)`: nil config launches unchanged, `ErrDebugCancelled`, any other error refuses; `req.Context` ends on cancel | `debug_resolve` handler: 0 unchanged, 1 with `*out`, -1 with `why`, -2 cancel |

Manifest for it: `[commands] debug_main = Debug the Server`, `[needs] debug = yes` and a
`[debugger.go]` section as above.

```rust
use rhun_ext::{run, DebugConfig, DebugEnded, DebugResolve, DebugValue, Doc, Event, Ext, Feature, Handler, Resolved};

struct Dbg;
impl Handler for Dbg {
    fn command(&mut self, ext: &Ext, name: &str, _doc: Doc) {
        if name == "debug_main" { // debug-start must follow one of its commands within 10 s
            let mut cfg = DebugConfig::new();
            cfg.set("type", DebugValue::Str("go".into())); // one of its [debugger.TYPE]
            cfg.set("mode", DebugValue::Str("debug".into()));
            cfg.set("program", DebugValue::Str("/abs/project/cmd/server".into()));
            cfg.set_list("args", &["--port", "8080"]); // args.0, args.1
            if let Err(e) = ext.debug_start("Debug server", &cfg) { eprintln!("debug: {e}"); }
        }
    }
    fn event(&mut self, _ext: &Ext, ev: &Event) {
        if let Some(DebugEnded { session, code }) = DebugEnded::parse(ev) {
            eprintln!("session {session} ended: {code:?}");
        }
    }
    fn resolve_debug(&mut self, _ext: &Ext, req: &DebugResolve) -> Resolved {
        if req.config.get_str("program").is_some() { return Resolved::Unchanged; }
        let Some((_, _, path)) = &req.doc else { return Resolved::Refuse("no file to debug".into()) };
        let mut cfg = req.config.clone();
        cfg.set("program", DebugValue::Str(path.clone()));
        Resolved::Config(cfg)
    }
}
fn main() { let _ = run(&[Feature::Debug], Dbg); }
```

## Testing

`rhun-ext-check` checks the `[debugger.*]` sections (types, keys, values, caps, files inside the
folder, `[needs] debug = yes`) and asks every `resolve = yes` debugger once per template section.
Headless rhun (from `rhun-editor/debug`'s tests): `debug-start NAME` (a launch.ini section),
`print-dialog` / `dialog yes` (the approval), `wait-debug paused|ended [MS]`, `print-debug`,
`print-stack`, `print-vars`, `print-console`, `print-configs`, `print-dap-log`, `bp PATH LINE`,
`bp-clear`, `debug-continue`, `debug-step over|into|out`, `debug-stop`. A real adapter needs a
native machine on Linux (no ptrace in Docker under Rosetta).

## Pitfalls

- `resolve = yes` on an extension that did not agree `debug` fails every launch; without `[needs]
  debug = yes` its debuggers are not offered at all.
- `debug-start` outside 10 s of one of the extension's commands (or a debug test run) is
  refused: start sessions from command handlers, one per command.
- A resolve answer is the **complete** configuration and its `type` must be one of the
  extension's debuggers; `Resolved::Unchanged` / nil is cheaper when nothing changes.
- The approval comes after the resolve answer, showing the adapter command built from it
  (`${config:KEY}`): keep `program` free of user-controlled shell text.
- `templates` files and adapters shipped in the extension's folder must be in the release
  archive: the templates' release workflow packs `bin/`, the manifest, icon, README and LICENSE,
  and of other folders only `themes/` and `syntax/`; add yours (`debug/`) to its `for d in` loop.
- In a remote window the adapter runs on the host; a `tcp` adapter listens on the host's loopback.
