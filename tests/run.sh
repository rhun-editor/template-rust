#!/bin/sh
# Builds the extension for this machine, lays it out as rhun installs it, and runs tests/basic.txt
# headlessly against a rhun binary. usage: tests/run.sh [RHUN]; UPDATE=1 writes tests/basic.expected
set -e
cd "$(dirname "$0")/.."
RHUN=${1:-$(command -v rhun || echo "$HOME/.local/bin/rhun")}
name=$(sed -n 's/^name *= *//p' extension.ini | head -1)
owner=$(sed -n 's/^owner *= *//p' extension.ini | head -1)
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) target=linux-x86_64 ;;
    Darwin-arm64) target=macos-arm64 ;;
    *) echo "no target for $(uname -s)-$(uname -m)"; exit 77 ;;
esac
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dir=$work/exts/$owner/$name
mkdir -p "$dir/bin" "$work/proj" "$work/config/rhun" "$work/state"
sh tests/layout.sh "$dir"  # what the release ships: the manifest, the icon, themes/, icon-themes/, ...
if ! grep -q "^run\.$target *=" extension.ini && grep -q '^run\.wasm32-wasip1 *=' extension.ini; then
    # no program for this system: the WebAssembly module, which rhun runs itself
    module=$(sed -n 's/^run\.wasm32-wasip1 *= *//p' extension.ini | head -1)
    cargo build --release --quiet --target wasm32-wasip1
    mkdir -p "$dir/$(dirname "$module")"
    cp "target/wasm32-wasip1/release/$name.wasm" "$dir/$module"
else
    cargo build --release --quiet
    cp "target/release/$name" "$dir/bin/$name-$target"
fi
printf 'hello world\nsecond line\n' > "$work/proj/sample.txt"
printf '# a note\n' > "$work/proj/notes.sh"
printf '[files]\nrestore_session = false\nrestore_project = false\n[updates]\ncheck = false\n[git]\nenabled = false\n[ui]\nsidebar = false\nagents_panel = false\n[editor]\ncursor_blink = false\n' > "$work/config/rhun/config"
run() { # SCRIPT: runs it in a fresh editor, the output on stdout
    HOME=$work XDG_CONFIG_HOME=$work/config XDG_STATE_HOME=$work/state \
        "$RHUN" "$work/proj" --headless 1000x600 --scale 1 --extensions "$work/exts" --script "$1" 2>&1
}
# where the status item is drawn depends on the platform's font: ask first (with the document of
# the click open), then click its middle
printf 'wait 100\nopen %s\nprint-status\n' "$work/proj/sample.txt" > "$work/status.txt"
status=$(run "$work/status.txt" | sed -n 's/^.*owner=rhun-editor\/hello .* at=\([0-9]*\),\([0-9]*\),\([0-9]*\),\([0-9]*\).*$/\1 \2 \3 \4/p' | head -1)
set -- $status
[ $# -eq 4 ] || { echo "FAIL basic: no status item"; exit 1; }
sed -e "s|proj/|$work/proj/|" -e "s|^click STATUS|click $(($1 + $3 / 2)) $(($2 + $4 / 2))|" tests/basic.txt > "$work/basic.txt"
# confined=2 is a Linux without unprivileged user namespaces (GitHub's Ubuntu runners): Landlock
# holds the files and TCP rules cut the network, so the extension is held all the same
run "$work/basic.txt" | sed -e 's/pid=[1-9][0-9]*/pid=PID/' -e 's/ at=[0-9,]*/ at=X,Y,W,H/' -e 's/ confined=2/ confined=1/' > "$work/out.txt"
[ -z "$UPDATE" ] || cp "$work/out.txt" tests/basic.expected  # UPDATE=1 writes the expected output
if cmp -s "$work/out.txt" tests/basic.expected; then
    echo "ok   basic"
else
    echo "FAIL basic"; diff tests/basic.expected "$work/out.txt" || true; exit 1
fi
