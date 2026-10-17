# The protocol in one page

Lines end with LF. Fields are separated by one space. A message whose last field is `LEN` is
followed by exactly `LEN` bytes. The full grammar: https://raw.githubusercontent.com/rhun-editor/extension-protocol/main/v1/v1.abnf

## Start
1. The extension writes `hello 1` (plus features: `hello 1 views complete signature`).
2. rhun answers `0 features …` (only those it agrees to), then `0 ready PROJECT` (`-` without
   one), the extension's settings (`0 setting KEY VALUE`), then catch-up: `opened` for every
   open document the subscription matches, `active`, `cursor`.
3. `0 bye`: leave within a second.

## Events (rhun to the extension): `0 NAME …`
`ready PROJECT` · `opened DOC VERSION LANG PATH` · `active DOC` · `saved DOC VERSION` ·
`changed DOC VERSION` · `cursor DOC LINE COL` · `selection DOC L1 C1 L2 C2` · `closed DOC` ·
`project PATH` · `run NAME.command DOC` · `edits DOC VERSION LEN` + records `START DEL INS` LF +
INS bytes · `resync DOC VERSION` · `hover DOC LINE COL` · `setting KEY VALUE` ·
`features NAME…` · `cancel ID` · `view VIEW size W H | metrics … | hover X Y | down | drag | up |
click X Y | leave | wheel X Y DY | closed` · `action LEN` + the chosen code action's DATA · `bye`

## Requests (the extension to rhun): `ID VERB …`, answered `ok ID …` or `error ID CODE TEXT`
`text DOC` → `ok ID VERSION LEN` + text · `range DOC L1 C1 L2 C2` → `ok ID VERSION LEN` + bytes ·
`replace DOC VERSION L1 C1 L2 C2 LEN` + text → `ok ID NEWVERSION` · `insert DOC VERSION LEN` +
text · `select DOC L1 C1 L2 C2` · `open LINE COL PATH` → `ok ID DOC` · `toast LEN` · `status LEN`
· `diagnostics DOC VERSION N LEN` + `L1 C1 L2 C2 SEVERITY MESSAGE` lines · `hover DOC LINE COL
LEN` + text · `register NAME KEYS TITLE` · `option DOC KEY VALUE` · `choose LEN` + prompt and
items → `ok ID N` (1-based) · `ask LEN` + prompt → `ok ID LEN` + answer · `term LEN` + command ·
`cmd NAME` · `cancel ID` · `view TITLE` → `ok ID VIEW` · `draw VIEW LEN` + picture · `unview
VIEW` · `apply LEN` + a workspace edit (below) → `ok ID` (documents write; nothing changes on an
error)

Error codes: `syntax unknown needs nodoc nofile readonly stale badpos toobig busy cancelled
refused noview`.

## Requests rhun sends (section 12)
`complete` and `signature`: `ID VERB DOC VERSION LINE COL KIND CHAR` (KIND `typed trigger
invoked incomplete` for completion, `trigger invoked update` for signature help) ·
`definition`, `references`, `symbols`: `ID VERB DOC VERSION LINE COL invoked -` · `actions`: `ID
actions DOC VERSION L1 C1 L2 C2` · `rename`: `ID rename DOC VERSION LINE COL invoked NAME` ·
`format`: `ID format DOC VERSION TAB_WIDTH yes|no`.
Answer `ok ID LEN` + body, or `error ID CODE TEXT` (`unknown` for a verb you do not know,
`refused TEXT` for a rename that cannot be done: rhun shows TEXT).
- Completion body: `N MORE` LF, then per item `L1 C1 L2 C2 KIND LABEL_LEN INSERT_LEN DETAIL_LEN
  EXTRA_LEN` LF and the LABEL INSERT DETAIL EXTRA bytes back to back. EXTRA records: `edit L1 C1
  L2 C2 LEN` LF + text (an import), `doc LEN` LF + documentation.
- Signature body: `FROM TO` LF (the active parameter's bytes, `-1 -1` for none), the signature
  LF, documentation. An empty body hides the help.
- Locations (definition, references): `N` LF, then per record `L1 C1 L2 C2 PATH_LEN TEXT_LEN` LF
  and the PATH (absolute, or `#DOC`) and TEXT (a one-line preview) bytes. `0` LF: none.
- Symbols: `N` LF, then per record `L1 C1 L2 C2 KIND DEPTH NAME_LEN DETAIL_LEN` LF + NAME DETAIL,
  in document order; DEPTH 0 at the top level. KIND: `file module namespace package class method
  property field constructor enum interface function variable constant string number boolean
  array object key null enum_member struct event operator type_parameter`.
- Code actions: `N` LF, then per action `KIND TITLE_LEN EDIT_LEN DATA_LEN` LF + TITLE EDIT DATA;
  KIND `quickfix` (listed first), `refactor`, `source`; EDIT a workspace edit or empty; DATA
  comes back as `0 action LEN` when the user chooses it.
- Workspace edit (rename, format, an action's EDIT): `N` LF, then per file `PATH_LEN VERSION M`
  LF + PATH, then M edits `L1 C1 L2 C2 LEN` LF + new text. VERSION is the open document's
  version the edits were made for, `-` for a file that is not open. Edits of a file all refer to
  that one text and must not overlap. rhun checks everything first, changes nothing on any
  failure, applies each file as one undo step and saves nothing.

## Pictures (`draw`): one shape per line, logical pixels
`rect X Y W H C` · `rrect X Y W H R C` · `line X1 Y1 X2 Y2 W C` · `poly W C X Y X Y …` · `fill C X
Y X Y X Y …` · `circle X Y R C` · `ring X Y R W C` · `pie X Y R FROM TO C` (degrees, 0 at the
top, clockwise) · `text X Y SIZE ALIGN C TEXT` (SIZE small normal large mono; ALIGN left center
right; Y is the line's top) · `clip X Y W H` · `unclip`. Numbers: at most 7 digits before the
point. Colors: `fg muted bg panel border accent error warning success`, `c1`-`c8`, `#rrggbb[aa]`.
