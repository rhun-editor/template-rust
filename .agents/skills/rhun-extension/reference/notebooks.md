# Notebooks (protocol 1.1)

Feature `notebooks` in `hello 1 ...`; manifest `[provides] notebook = PATTERNS`,
`notebook.title`, `notebook.kernel = yes|no`, and `[needs] kernels = NAMES` for kernels started
as the user (`nb-exec`). rhun never parses a notebook file: the extension turns the file's bytes
into cells and back, and runs cells. Spec section "Feature: `notebooks`" (Bodies, Messages,
Kernels that run as the user: `nb-exec`, The notebook tab, Cells for language providers) of
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md. Example:
`rhun-editor/jupyter` (Rust, `.ipynb`, ipykernel over ZeroMQ).

```ini
on = open:*.ipynb
[provides]
notebook = *.ipynb
notebook.title = Jupyter Notebook
# it runs cells; "no" for a viewer or converter
notebook.kernel = yes
[needs]
# programs rhun may start as the user as kernels (nb-exec)
kernels = python3 python
```

Opening a matching file shows a notebook tab and starts the extension. Ids rhun hands out, never
reused in a session: `NB` (a notebook), `CELL` (stable while the cell exists), `RUN` (a run).

## Bodies

```
notebook:  N META_LEN LF <META>
           N × KIND LANG COUNT SOURCE_LEN META_LEN NOUT LF <SOURCE><META>, then NOUT output bodies
output:    KIND OUTID KEEP_LEN NITEM LF <KEEP>
           NITEM × TYPE W H LEN LF <LEN bytes>
```

- Cell KIND `code` or `markup` (Markdown, LANG `-`); LANG a grammar name with `_` for spaces
  (case ignored) or `-`; COUNT the execution count or `-`; SOURCE with LF line ends. The
  notebook's and each cell's META are opaque: rhun returns them unchanged.
- Output KIND `stdout stderr result display error`; OUTID Jupyter's display id or `-`; KEEP opaque
  bytes returned on save (jupyter keeps the output's original JSON there so every MIME bundle
  round-trips). Items in order of preference; rhun shows the first it can draw.
- TYPE `text`, `ansi` (SGR colors), `png`, `jpeg`, `gif`, `rich` (a `doc LEN` Markdown record and
  an optional `base LEN` folder), `picture` (a 12a picture body), or any other token rhun keeps.
  `W H` the logical size, `0 0` natural.

## Messages

| Direction | Message | Reply or meaning |
| --- | --- | --- |
| rhun → ext | `ID nb-open NB LEN` + `PATH_LEN DATA_LEN LF <PATH><DATA>` | `ok ID LEN` + notebook body; DATA empty for a new file; an error's TEXT shows in the tab with Open as Text |
| rhun → ext | `ID nb-save NB LEN` + `PATH_LEN LF <PATH>` + notebook body | `ok ID LEN` + the file's bytes, which rhun writes |
| rhun → ext | `0 nb-run NB CELL RUN LANG LEN` + source | an event: runs queue in the extension in arrival order |
| rhun → ext | `0 nb-interrupt NB`, `0 nb-restart NB`, `0 nb-kernel NB`, `0 nb-closed NB` | interrupt; restart (confirmed); the kernel button (offer kernels, e.g. with `choose`); the tab closed |
| ext → rhun | `ID nb-state NB CELL RUN STATE COUNT` | STATE `queued running done failed cancelled`; COUNT or `-` |
| ext → rhun | `ID nb-output NB CELL RUN OP TARGET LEN` + output body | OP `append` (TARGET `-`), `replace` (an output index or an OUTID), `clear`, `clear-wait` (LEN 0) |
| ext → rhun | `ID nb-stream NB CELL RUN NAME LEN` + bytes | NAME `stdout`/`stderr`: appends to the last output of that stream (type `ansi`); a lone CR goes back to the line's start |
| ext → rhun | `ID nb-kernel-label NB STATE LEN` + label | the kernel button; STATE `idle busy starting dead none` |
| ext → rhun | `ID nb-exec NB LEN` + command body | `ok ID EXEC`: a kernel started as the user |
| ext → rhun | `ID nb-exec-signal EXEC SIGNAL` | `interrupt` (SIGINT; `refused` on Windows), `terminate`, `kill` |
| rhun → ext | `0 nb-exec-exit EXEC CODE` | CODE its status (128 + N after signal N), or `killed` |

Every `nb-state`, `nb-output` and `nb-stream` names its RUN: one for a run that is not the
cell's latest, a deleted cell or a closed notebook is `error ID stale` and changes nothing.
Outputs and counts make the notebook modified. When the extension stops, queued and running
cells show cancelled.

`nb-exec`'s command body is test-exec's: `PROGRAM_LEN CWD_LEN ARGC ENVC LF PROGRAM CWD`, then
ARGC arguments and ENVC `NAME=VALUE` lines, each `LEN LF` + bytes (256 KiB, 256 arguments, 64
variables). rhun checks, in order: the feature, the notebook is the extension's (`stale`), at
most 4 kernels (`busy`), the body, the program's last path component is a word of `[needs]
kernels` (`needs kernels=NAME`), found on the PATH (`nofile`), the folder exists (empty: the
notebook's), the user allows it (asked once per extension and project). The kernel runs outside
the sandbox with the user's login environment; its output goes to `kernel-EXEC.log` in
`$RHUN_STATE`. It ends with the extension and 3 s after its notebook closes. In a remote window
`nb-exec` is `refused`. The extension talks to the kernel itself (Jupyter's loopback sockets need
`[needs] network = yes`).

## SDK

| | Rust (`rhun_ext::notebook`, `Feature::Notebooks`) | Go (`FeatureNotebooks`) | C (`"notebooks"`) |
| --- | --- | --- | --- |
| open, save, run | `Handler::nb_open(&NbOpen) -> Result<Notebook, String>`, `nb_save(&NbSave) -> Result<Vec<u8>, String>`, `nb_run(&NbRun)` | `NotebookProvider`: `NbOpen`, `NbSave`, `NbRun` | `rx_handlers.nb_open`, `nb_save`, `nb_run` |
| events | `nb_interrupt`, `nb_restart`, `nb_kernel`, `nb_closed`, `nb_exec_exit` | `NotebookEvents` (`NbInterrupt`, `NbRestart`, `NbKernel`, `NbClosed`), `NotebookExecs.NbExecExit` | `nb_event` ("interrupt", "restart", "kernel", "closed"), `nb_exec_exit` |
| bodies | `Notebook { meta, cells }`, `Cell::code(lang, src)`, `Cell::markup`, `Output::new(OutputKind, items)`, `Item::text/ansi/png/jpeg/gif/new`, `.size(w, h)` | `Notebook`, `Cell`, `Output`, `Item`, `ParseNotebook`, `ParseOutput`, `.Encode()` | write: `rx_nb_begin`, `rx_nb_cell`, `rx_nb_output`, `rx_nb_item`; read: `rx_nb_read_begin`, `rx_nb_read_cell`, `rx_nb_read_output`, `rx_nb_read_item` |
| results | `ext.nb_state(nb, cell, run, RunState, Option<count>)`, `nb_output(…, OutputOp::Append \| Replace(i) \| ReplaceId(id) \| Clear \| ClearWait, Some(&out))`, `nb_stream(…, stderr, bytes)`, `nb_kernel_label(nb, KernelState, label)` | `NbState(nb, cell, run, state, count or -1)`, `NbOutput(nb, cell, run, op, target, *Output)`, `NbStream`, `NbKernelLabel` | `rx_nb_state`, `rx_nb_output_send`, `rx_nb_stream`, `rx_nb_kernel_label` |
| kernels | `ext.nb_exec(nb, &Command { program, dir, args, env })`, `nb_exec_signal(exec, ExecSignal::Interrupt)` | `NbExec(nb, *Command)`, `NbExecSignal(exec, "interrupt")` | `rx_nb_exec`, `rx_nb_exec_signal`, `rx_command_body` |
| cells as documents | `nb_cell(doc, nb, cell, index)`, `nb_cells(nb, &[Doc])` | `NotebookCells` (`NbCell`, `NbCells`) | `nb_cell`, `nb_cells` |

`nb_stream` cuts long data into 64 KB messages at character boundaries.

```rust
use rhun_ext::notebook::{Cell, Item, KernelState, NbOpen, NbRun, NbSave, Notebook, Output, OutputKind, OutputOp, RunState};
use rhun_ext::{run, Ext, Feature, Handler};

struct Nb;

impl Handler for Nb {
    // the file's bytes to cells: here, one code cell per blank-line-separated block
    fn nb_open(&mut self, _ext: &Ext, req: &NbOpen) -> Result<Notebook, String> {
        let text = String::from_utf8(req.data.clone()).map_err(|_| "not UTF-8".to_string())?;
        let cells = text.split("\n\n").filter(|s| !s.is_empty()).map(|s| Cell::code("Shell", s.as_bytes())).collect();
        Ok(Notebook { meta: Vec::new(), cells })
    }
    // the cells back to the file's bytes (rhun writes them)
    fn nb_save(&mut self, _ext: &Ext, req: &NbSave) -> Result<Vec<u8>, String> {
        let parts: Vec<&[u8]> = req.notebook.cells.iter().map(|c| c.source.as_slice()).collect();
        Ok(parts.join(&b"\n\n"[..]))
    }
    // handlers run one at a time: a real kernel answers from a thread of its own (Ext is Clone + Send)
    fn nb_run(&mut self, ext: &Ext, r: &NbRun) {
        let (ext, r) = (ext.clone(), r.clone());
        std::thread::spawn(move || {
            let _ = ext.nb_state(r.nb, r.cell, r.run, RunState::Running, None);
            let _ = ext.nb_stream(r.nb, r.cell, r.run, false, b"running\n");
            let out = Output::new(OutputKind::Result, vec![Item::text(&format!("{} bytes", r.source.len()))]);
            let _ = ext.nb_output(r.nb, r.cell, r.run, OutputOp::Append, Some(&out));
            let _ = ext.nb_state(r.nb, r.cell, r.run, RunState::Done, Some(1));
            let _ = ext.nb_kernel_label(r.nb, KernelState::Idle, "echo");
        });
    }
}

fn main() {
    if let Err(e) = run(&[Feature::Notebooks], Nb) { eprintln!("nb: {e}"); }
}
```

## Cells for language providers

An extension that agreed `notebooks` hears cells as documents: `0 opened DOC VERSION LANG -` (no
path), `changed`, `edits`, `closed` (never `saved`); `text`, `replace`, `diagnostics` and the
language features take the cell's DOC. Patterns match a cell through its language's usual file
name (a Python cell is `cell.py`: `complete = *.py` gets Python cells). It hears `0 cell DOC NB
CELL INDEX` per cell and `0 cells NB DOC...` in order, after `opened` and after cells move. While
a notebook tab is active its `active` document is the selected cell; extensions without the
feature never see cells (their active document is `0` there). `rhun-editor/jupyter` also
declares `complete = *.py` to complete in its cells.

## The tab and when clauses

Jupyter's keys: Shift+Enter run and next, Ctrl+Enter run, Alt+Enter run and insert, Esc command
mode (a/b insert, d d delete, m/y markup/code, i i interrupt, 0 0 restart, z undo). Commands are
`notebook.*` (`notebook.run_cell`, `notebook.insert_below`). When-clause keys: `notebookFocus`,
`notebookCellEditing`, `notebookCellType` (`code`|`markup`), `notebookKernelState`; `activeTab`
is `notebook`.

## Limits

`nb-open`'s answer and `nb-save`'s body 64 MB each (every other answer 4 MB); 5,000 cells; a
source 4 MB; 1,000 outputs a cell; 32 items an output; an item 16 MB; an `nb-output` body 17 MB
and an `nb-stream` body 64 KB (more stops the extension); 64 MB of outputs per notebook (`toobig`).
A request rhun waits on fails after 30 s. Outputs count against the 16 ms message window.

## Testing headless

`print-notebook` (a line per cell: `cell=I id=CELL kind=… lang=… lines=N count=C state=… outputs=K
sel=… editing=… hidden=0|1 at=X,Y`, then `dirty= mode= undo= kstate= kernel=`; `notebook=opening|failed|none`),
`print-nb-output I J` (kind, items, the text or layout, then `<eoo>`), `print-nb-md I`,
`print-nb-xy I LINE COL`, `print-nb-exec` (`exec=N nb=N pid=P state=asking|running`),
`nb-mode edit|command`, `nb-select I`, `nb-run I`, `nb-output-tab I J`. Open the file with
`open PATH`, then `nb-run 0`, `wait 300` twice, `print-notebook`. The conformance checker starts
no kernels: it answers `nb-exec` refused, and fails `nb-exec` without `[needs] kernels`.

## Pitfalls

- Keep KEEP and META bytes exactly; rhun hands them back on save and nowhere else.
- Answer `nb-run` with the RUN it carried; a new run of the cell makes old ones `stale`.
- Do not block the handler for a whole run: queue runs and report from a worker thread.
- `notebook.kernel = no` for a viewer or converter; a missing `[needs] kernels` makes every
  `nb-exec` fail. `rhun-editor/jupyter` lists the kernels in both `run` (programs it starts in its
  sandbox, as a fallback when `nb-exec` is unknown or declined) and `kernels`.
- Handle a user who declines the approval (`refused the user did not allow it`).
