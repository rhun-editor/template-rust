# Notifications, progress, quick input, Markdown (protocol 1.1)

Cards at the window's bottom right, progress in the status bar, a card or a view, and multi-step
pickers and validated inputs drawn like the palette. Features for `hello 1 ...`: `notify`,
`progress`, `quick-input`, `markdown`. No manifest keys; a button or item that runs a command
uses a command reference (`command-args`, see `contributions.md`). Spec: v1.1.md, "Notifications
and progress" ("Feature: `notify`", "Feature: `progress`"), "Quick input" ("Feature:
`quick-input`"), "Feature: `markdown`",
https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1.1/v1.1.md. v1's `toast`,
`choose` and `ask` stay as they are; use these when you need buttons, progress or several steps.

## notify

| Request | Reply |
| --- | --- |
| `ID notify SEVERITY LEN` + body | `ok ID NOTE`; SEVERITY `info`, `warning`, `error` |
| `ID notify-set NOTE LEN` + body | `ok ID`: replaces the content (`noview` when it is gone) |
| `ID unnotify NOTE` | `ok ID`: closes it without an event |

Body: `MSG_LEN EXTRA_LEN` LF + message (2000 bytes, LF breaks a line, 6 lines shown) + records
`detail LEN` (a muted line), `sticky 0`, `button LEN` + title (3 at most, 60 bytes), and right
after a button `command NAME ARGS_LEN` + ARGS (that button runs the command reference).
Events: `0 notify NOTE pressed N` (button N from 1, only for buttons without a command) and `0
notify NOTE closed` (its close button, a timeout, Clear All). Any button closes the card. Info
closes after 8 s, warnings after 12 s; errors, cards with buttons and sticky ones stay. 16 cards
per extension (`toobig 16 notifications`).

## progress

| Request | Reply |
| --- | --- |
| `ID progress WHERE CANCEL LEN` + title | `ok ID P`; WHERE `status`, `note` or `view:VIEW` (one of its own views); CANCEL `cancel` or `-` |
| `ID progress-set P PERCENT LEN` + message | `ok ID`; PERCENT 0-100 or `-` (indeterminate); message 200 bytes |
| `ID progress-end P` | `ok ID` |

Event `0 progress P cancel`: the user pressed Cancel; rhun shows "Cancelling…" and removes it 10 s
later unless `progress-end` comes first. Nothing shows for progress that ends within 500 ms. 8 per
extension. The title is one non-empty line (200 bytes), else `syntax`.

## quick-input

| Request | Reply |
| --- | --- |
| `ID quick LEN` + step body | `ok ID Q`; `busy` while a quick input, the palette or a prompt shows |
| `ID quick-set Q LEN` + step body | `ok ID`: changes only the records it names, atomically |
| `ID quick-close Q` | `ok ID`: closes it (no `hide` event) |

Step body records (all optional, `NAME ARGS... LEN` LF + bytes): `title`, `step N M 0` (`0 0`
hides "N/M"), `placeholder`, `prompt` (the line under the field), `value SEQ LEN`, `mode
pick|input 0`, `flags F… 0` (`multi back busy nofilter match-desc match-detail password`; `-`
clears), `msg SEQ SEVERITY LEN` (shown while SEQ is the field's sequence; `error` refuses Enter),
`buttons N LEN` + N `KEY ICON TIP_LEN` LF + tip (title buttons, 8), `items N LEN` + N `ID_LEN
LABEL_LEN EXTRA_LEN KIND` LF + id + label + extras (KIND `item` or `sep`; extras `desc`, `detail`,
`icon SPEC COLOR 0`, `picked 0`, `always 0`, `hl FROM TO 0`, `button KEY ICON LEN` + tip, 4),
`active LEN` + item id. Limits: 10000 items, 2 MB.

Events (`0 quick Q …`): `value SEQ LEN` + text (the field changed; SEQ counts edits from 1),
`active SEQ LEN` + id, `accept SEQ N LEN` + N ids each ending in LF, then the field's text (Enter
or a click: the checked items in `multi`, else the active one; none in input mode), `back SEQ`
(Alt+Left, the Back button), `button SEQ KEY LEN` + item id (empty: a title button), `hide`
(Escape, a click outside: Q is gone).

**Multi-step pattern.** rhun never closes a session on accept: after `accept`, send `quick-set`
with the next step (`step 2 3`, new `items`, a new `value`, `flags back`) or `quick-close`. Keep
the answers yourself; on `back` resend the previous step. Validate as the user types: on `value
SEQ`, answer `quick-set` with `msg SEQ error …` (it shows only while the text is still that one).
Set `flags busy` while you compute, `nofilter` with `hl` when you rank items yourself.

## markdown

With `markdown` agreed, rhun renders as Markdown (the `view-doc` subset): node tooltips (`tip`),
notification messages, and the language-features texts that say so (hover-query text,
completion documentation, signature-list documentation). Links in messages work when rhun can
follow them; links in tooltips show but are not followed. Without it the same text is plain.

## SDK

| | Rust | Go | C |
| --- | --- | --- | --- |
| notify | `ext.notify(notify::Severity::Warning, &Note::new(msg).detail(d).sticky().button("OK").button_command("Open", "open_log", args))` → NOTE; `notify_set`, `unnotify`; `Handler::note_event(note, NoteEvent::Pressed(n) / Closed)` | `ext.Notify(rhunext.SeverityWarning, rhunext.NewNote(msg).Detail(d).Sticky().Button("OK").ButtonCommand("Open", "open_log", args))`; `NotifySet`, `Unnotify`; `NoteListener` (`NoteEvent{Note, Pressed, Closed}`) | `rx_note n; rx_note_init(&n, msg); rx_note_detail; rx_note_sticky; rx_note_button(&n, title, command or NULL, args, len)`; `rx_notify(ext, "warning", &n)`; `rx_notify_set`, `rx_unnotify`, `rx_note_free`; `note_event` handler (`pressed` 0: closed) |
| progress | `ext.progress(ProgressWhere::Status / Note / View(v), cancel, title)` → P; `progress_set(p, Some(40) or None, msg)`; `progress_end`; `Handler::progress_cancel` | `Progress(rhunext.ProgressStatus / ProgressNote / ProgressView(v), cancel, title)`; `ProgressSet(p, percent or -1, msg)`; `ProgressEnd`; `ProgressCanceller` | `rx_progress(ext, "status", cancel, title)`; `rx_progress_set(ext, p, percent or -1, msg)`; `rx_progress_end`; `progress_cancel` handler |
| quick | `quick::Step::pick(title)` / `input(title)` `.step .placeholder .prompt .value(Some(seq) or None, t) .flags(&[Flag::Multi, Flag::Back]) .msg(seq, "error", t) .buttons(&[(key, icon, tip)]) .items(&[Item::new(id, label).desc(..).picked(), Item::separator(l)]) .active(id)`; `ext.quick`, `quick_set`, `quick_close`; `Handler::quick_event(q, QuickEvent::Accept{ids, text,..} / Value / Back / Button / Active / Hide)` | `rhunext.QuickPick(title)` / `QuickInput(title)` / `NewQuickStep()` `.Step .Placeholder .Prompt .Value(seq or -1, t) .Flags("multi", "back") .Msg .Buttons(QuickButton{…}) .Items(NewQuickItem(id, label).Desc(..), QuickSeparator(l)) .Active`; `Quick`, `QuickSet`, `QuickClose`; `QuickListener` (`QuickEvent{Q, Kind, Seq, Text, IDs, Key}`) | `rx_buf` built with `rx_qs_title _mode _step _placeholder _prompt _value _flags _msg _active`, items with `rx_qi_rec` + `rx_qs_items` (item extras and title buttons: `rx_rec`); `rx_quick`, `rx_quick_set`, `rx_quick_close`; `quick_event` handler (`what`, `argv`, body) |

Features: Rust `Feature::Notify Progress QuickInput Markdown` (types in `rhun_ext::notify` and
`rhun_ext::quick`); Go `FeatureNotify FeatureProgress FeatureQuickInput FeatureMarkdown`; C the
words `notify progress quick-input markdown` in `rx_run`.

## Minimal example (Rust): a two-step input with validation and a card

```rust
use rhun_ext::notify::{Note, Severity};
use rhun_ext::quick::{Flag, QuickEvent, Step};
use rhun_ext::{run, Ext, Feature, Handler, Invocation};

#[derive(Default)]
struct New { name: Option<String>, typed: String }
impl Handler for New {
    fn invoke(&mut self, ext: &Ext, _inv: &Invocation) {
        self.name = None;
        let _ = ext.quick(&Step::input("New Module").step(1, 2).placeholder("name"));
    }
    fn quick_event(&mut self, ext: &Ext, q: u64, ev: QuickEvent) {
        match ev {
            QuickEvent::Value { seq, text } if text.contains(' ') => {
                let _ = ext.quick_set(q, &Step::new().msg(seq, "error", "no spaces"));
            }
            QuickEvent::Value { text, .. } if self.name.is_none() => self.typed = text,
            QuickEvent::Accept { text, .. } if self.name.is_none() => {
                self.name = Some(text);
                let _ = ext.quick_set(q, &Step::new().step(2, 2).value(None, "").flags(&[Flag::Back])
                    .placeholder("folder"));
            }
            QuickEvent::Accept { text, .. } => {
                let _ = ext.quick_close(q);
                let msg = format!("Created {} in {text}", self.name.take().unwrap_or_default());
                let _ = ext.notify(Severity::Info, &Note::new(&msg).button_command("Open", "open_it", text.as_bytes()));
            }
            QuickEvent::Back { .. } => {
                self.name = None;
                let back = Step::new().step(1, 2).value(None, &self.typed).flags(&[]).placeholder("name");
                let _ = ext.quick_set(q, &back);
            }
            _ => {}
        }
    }
}
fn main() { let _ = run(&[Feature::CommandArgs, Feature::QuickInput, Feature::Notify], New::default()); }
```

## Headless

`print-notes` (a line per card: `note=NOTE sev=S buttons=A|B msg=M [detail=D] [stays]
[at=X,Y size=WxH]`, then `progress=P where=W percent=N|- cancel=0|1|2 shown=0|1 title=T [msg=M]`;
a Markdown card is marked `markdown`), `note-press N B|close|cancel` (card N among those drawn, 0
the oldest), `print-quick` (`quick Q title=T step=N/M mode=pick|input flags=F seq=S waiting=0|1
… field=TEXT`, then `row I id=ID label=L [sep] [checked] [active]` per item, `button KEY at=X,Y`,
`back at=X,Y`; `quick none`), then `type`, `key Return`, `key Down`, `key space`, `key alt+Left`,
`key Escape` drive it. `cmd focus_notifications`, `cmd clear_notifications`. `print-tip` shows a
tooltip's Markdown source.

## Pitfalls

- A `pressed` event comes only for buttons without a command; a button with a command reference
  runs `0 run EXT.NAME DOC ref LEN` instead (needs `command-args` for the ARGS).
- NOTE, P and Q go away with the user: `noview` on `notify-set`/`progress-set`/`quick-set` is
  normal after a close, timeout or `hide`; drop your handle then.
- Progress stays until `progress-end`: end it on every path, errors included (8 at most per
  extension). `view:VIEW` must be one of the extension's own views (`syntax` otherwise).
- `quick` is `busy` while the palette, a prompt or another quick input is open: do not loop.
- After `accept` nothing happens until you `quick-set` or `quick-close`: always answer it.
- `msg SEQ` must name the sequence of the text it judges (the SEQ of the `value` event), or the
  message never shows; `value SEQ` likewise applies only if the user has not typed since.
- Markdown text sent without `markdown` agreed shows as raw source.
