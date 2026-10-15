#!/usr/bin/env bash
# Tests for my-extras/my-extras and my-extras/pr-check (branch miles only; never sent upstream).
# Sandboxed: a fake "his kit" repo and a fake kit folder; no network, no gh.
# Also checks the REAL kit folder: miles may hold no change that belongs to no extra.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; X="$ROOT/my-extras/my-extras"; PC="$ROOT/my-extras/pr-check"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
has() { case "$3" in *"$2"*) pass=$((pass+1)) ;; *) fail=$((fail+1)); echo "FAIL $1: want '$2' in: $3" ;; esac; }
hasnt() { case "$3" in *"$2"*) fail=$((fail+1)); echo "FAIL $1: did not want '$2' in: $3" ;; *) pass=$((pass+1)) ;; esac; }
rc_is() { [ "$2" = "$3" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL $1: want exit $2, got $3"; }; }
q() { git -C "$K" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
H="$TMP/his"; K="$TMP/kit"
export MY_EXTRAS_REPO="$K" MY_EXTRAS_NO_NET=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export MY_EXTRAS_WORDS="$TMP/words"; printf '# test list\nzebrafinch\n' >"$MY_EXTRAS_WORDS"
ver() { mkdir -p "$1/.claude-plugin"; printf '{ "name": "k", "version": "%s" }\n' "$2" > "$1/.claude-plugin/plugin.json"; }

# his kit: 1.0 with a launcher and a hud file
mkdir -p "$H/scripts"; git -C "$H" init -q -b main; ver "$H" 1.0
echo launcher > "$H/scripts/launch.sh"; echo hud > "$H/hud.ts"; printf '# Changelog\n\n## 1.0\n' > "$H/CHANGELOG.md"
git -C "$H" add -A; git -C "$H" commit -qm "1.0"
git clone -q "$H" "$K"; q remote rename origin upstream
# two extras from his kit, merged into miles; the tool's own folder committed on miles
q checkout -b extra/tabs upstream/main; echo "tab colors" >> "$K/scripts/launch.sh"; q commit -am "tabs"
q checkout -b extra/dots upstream/main; echo "dots" >> "$K/hud.ts"; q commit -am "dots"
q checkout -b miles upstream/main; q merge --no-ff extra/tabs -m "merge tabs"; q merge --no-ff extra/dots -m "merge dots"
mkdir -p "$K/my-extras"; echo tool > "$K/my-extras/x"; q add my-extras/x; q commit -m "tracking"
cat > "$K/MY-EXTRAS.md" <<'EOF'
## Details
### tabs
- name: Tabs
- status: Only mine
- pr:
- what: tab colors
### dots
- name: Dots
- status: Sent
- pr: 7
- what: project dots
## Given to his kit
EOF

# --- header, check, files
out="$("$X" header)"; has "header: version and extras" "Orca-kit 1.0 + 2 extras" "$out"; hasnt "header: nothing new" "▲" "$out"; has "header: current shown green" "$(printf '\033[32mcurrent 1.0 ✓')" "$out"; hasnt "header: nothing unlisted" "⚠" "$out"
out="$("$X" check)"; rc_is "check: clean miles passes" 0 $?
has "files: from the branch" "scripts/launch.sh" "$("$X" files tabs)"
out="$("$X" refresh)"; has "page: table row" "| Tabs | tab colors | Only mine | — |" "$(cat "$K/MY-EXTRAS.md")"
has "page: PR number shown" "| Dots | project dots | Sent | #7 |" "$(cat "$K/MY-EXTRAS.md")"
has "page: details kept" "### dots" "$(cat "$K/MY-EXTRAS.md")"; has "page: files from git" "files (from git): hud.ts" "$(cat "$K/MY-EXTRAS.md")"
out="$("$X" header)"; has "header: refresh keeps the extras" "+ 2 extras" "$out"
sed -i 's/^- status: Only mine$/- status: Building/' "$K/MY-EXTRAS.md"
out="$("$X" header)"; has "header: an extra still being built is not counted" "+ 1 extra" "$out"
sed -i 's/^- status: Building$/- status: Only mine/' "$K/MY-EXTRAS.md"

# --- a stray edit straight on miles is caught; a tracking-only commit is not
echo "stray" >> "$K/hud.ts"; q commit -am "quick fix on miles"
out="$("$X" header)"; has "header: unlisted change flagged" "⚠ 1 unlisted change" "$out"
out="$("$X" check)"; rc=$?; rc_is "check: stray commit fails" 1 $rc; has "check: names it" "quick fix on miles" "$out"
q reset --hard HEAD~1
echo more > "$K/my-extras/x"; q commit -am "tracking 2"
out="$("$X" check)"; rc_is "check: tracking-only commit is fine" 0 $?

# --- his new release: marker, news, refit only for the extra whose files he changed
ver "$H" 1.1; echo "his launcher change" >> "$H/scripts/launch.sh"; printf '# Changelog\n\n## 1.1\n- **New: faster launch.**\n\n## 1.0\n' > "$H/CHANGELOG.md"
git -C "$H" commit -qam "1.1"; q fetch -q upstream
out="$("$X" header)"; has "header: newer version marked" "▲ current 1.1 (news)" "$out"; hasnt "header: not green when behind" "✓" "$out"; has "header: still on 1.0" "Orca-kit 1.0" "$out"
has "header: update in yellow" "$(printf '\033[1;33m▲')" "$out"; hasnt "header: NO_COLOR is plain" "$(printf '\033[')" "$(NO_COLOR=1 "$X" header)"
out="$("$X" news)"; has "news: versions" "His latest: 1.1" "$out"; has "news: changelog heading" "New: faster launch." "$out"
has "news: overlapping extra needs refit" "Tabs needs a refit (he changed scripts/launch.sh)" "$out"; has "news: other extra fine" "Dots: not affected" "$out"
out="$("$X" status)"; has "status: refit flag" "Only mine, needs refit" "$out"
"$X" refresh >/dev/null; has "page: refit in the table" "Only mine, needs refit" "$(cat "$K/MY-EXTRAS.md")"

# --- pr-check
out="$("$PC" dots)"; rc=$?; rc_is "pr-check: old base refused" 1 $rc; has "pr-check: says refit first" "refit it first" "$out"
q checkout -q extra/dots; q rebase -q upstream/main; q checkout -q miles
out="$("$PC" dots)"; rc_is "pr-check: refitted extra passes" 0 $?; has "pr-check: size line" "dots: 1 file, +1 -0 lines" "$out"
q checkout -q -b extra/leak upstream/main; echo "see the Zebrafinch seat" >> "$K/hud.ts"; q commit -am leak; q checkout -q miles
out="$("$PC" leak)"; rc_is "pr-check: personal name refused" 1 $?; has "pr-check: shows the line" "Zebrafinch" "$out"
q checkout -q -b extra/priv upstream/main; echo x > "$K/MY-EXTRAS.md.x"; mkdir -p "$K/my-extras"; echo y > "$K/my-extras/y"; q add my-extras/y; q commit -m priv; q checkout -q miles
out="$("$PC" priv)"; rc_is "pr-check: private file refused" 1 $?; has "pr-check: names it" "my-extras/y" "$out"
q checkout -q -b extra/both upstream/main; q merge --no-ff extra/dots -m "both"; q checkout -q miles
out="$("$PC" both)"; rc_is "pr-check: merge refused" 1 $?; has "pr-check: one extra at a time" "merge commit" "$out"
out="$("$PC" nope)"; rc_is "pr-check: unknown branch" 1 $?
out="$("$PC" 2>&1)"; rc_is "pr-check: usage" 64 $?
out="$(MY_EXTRAS_WORDS="$TMP/none" "$PC" dots)"; rc_is "pr-check: no word list refused" 1 $?; has "pr-check: says why" "no private word list" "$out"

# --- the real kit folder: miles holds nothing that belongs to no extra
if [ -f "$ROOT/MY-EXTRAS.md" ] && [ "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" = miles ]; then
  out="$(env -u MY_EXTRAS_REPO MY_EXTRAS_NO_NET=1 "$X" check)"; rc=$?
  rc_is "real kit: no unlisted change on miles ($out)" 0 $rc
fi

echo "my-extras: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
