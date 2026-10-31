#!/usr/bin/env bash
# LT-36: process-level checks of scripts/test.sh against a fake Godot (a bash script that
# records its argv and exits, or hangs with a child, both ignoring SIGTERM). Not a gdUnit
# suite: test.sh is the process that runs gdUnit, so its watchdog, exit codes and argument
# handling are checked from outside, without starting Godot. Run from anywhere:
#
#   tests/shell/test_sh_test.sh        # ~15 s; exit 0 when every check passes
#
# scripts/test.sh does not run it (it runs only gdUnit suites under res://tests).
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/test_sh_test.XXXXXX")"
FAKE="$T/godot"
passes=0
fails=0

kill_leftovers() {
  local f
  for f in "$T"/*.pid; do
    [ -f "$f" ] && kill -9 "$(cat "$f")" 2>/dev/null
    rm -f "$f"
  done
  return 0
}
trap 'kill_leftovers; rm -rf "$T"' EXIT

cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --import "*) echo import >>"$FAKE_DIR/imports"; exit 0 ;; esac
printf '%s\n' "$@" >"$FAKE_DIR/args"
case "$FAKE_MODE" in
  exit)
    [ -n "$FAKE_OUT" ] && printf '%s\n' "$FAKE_OUT"
    exit "$FAKE_CODE" ;;
  hang)
    trap '' TERM
    bash -c 'trap "" TERM; echo $$ >"$FAKE_DIR/child.pid"; while :; do sleep 1; done' &
    echo $$ >"$FAKE_DIR/leader.pid"
    while :; do sleep 1; done ;;
esac
EOF
chmod +x "$FAKE"

ok() { passes=$((passes + 1)); echo "ok - $1"; }
bad() { fails=$((fails + 1)); echo "not ok - $1"; [ $# -gt 1 ] && printf '    %s\n' "$2"; return 0; }

# Fake behaviour for the next run(); reset after each run.
MODE=exit CODE=0 OUT="" TIMEOUT=60 GODOT_BIN="$FAKE" PROJ="$REPO"

# Runs $PROJ/scripts/test.sh "$@" (default: the repo's) with the fake; sets rc, out, argv ("" when
# the fake was never run), imports (how many times the fake was asked to --import). A 40 s alarm bounds a broken watchdog (rc 142 then).
run() {
  kill_leftovers
  rm -f "$T/args" "$T/out" "$T/imports"
  (cd "$PROJ" && exec env GODOT="$GODOT_BIN" TEST_TIMEOUT="$TIMEOUT" FAKE_DIR="$T" \
    FAKE_MODE="$MODE" FAKE_CODE="$CODE" FAKE_OUT="$OUT" \
    perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' 40 "$PROJ/scripts/test.sh" "$@") \
    >"$T/out" 2>&1
  rc=$?
  out="$(cat "$T/out")"
  argv="$(cat "$T/args" 2>/dev/null || true)"
  imports="$(grep -c import "$T/imports" 2>/dev/null || true)"
  imports="${imports:-0}"
  MODE=exit CODE=0 OUT="" TIMEOUT=60 GODOT_BIN="$FAKE" PROJ="$REPO"
}

# The gdUnit command line test.sh must build: expected_argv <res paths...> -- <extra...>
expected_argv() {
  local lines="--headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd" a
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do lines="$lines -a $1"; shift; done
  [ $# -gt 0 ] && shift
  lines="$lines --ignoreHeadlessMode -c"
  for a in "$@"; do lines="$lines $a"; done
  printf '%s\n' $lines
}

# check_argv <name> <expected rc> <res paths...> -- <extra...>  (after a run)
check_argv() {
  local name="$1" want_rc="$2"; shift 2
  local want; want="$(expected_argv "$@")"
  if [ "$rc" -eq "$want_rc" ] && [ "$argv" = "$want" ]; then ok "$name"
  else bad "$name" "rc=$rc (want $want_rc), argv: $(echo $argv) | want: $(echo $want)"; fi
}

# check_refused <name> <message part>: exit 2, the fake never ran, the message shown.
check_refused() {
  if [ "$rc" -eq 2 ] && [ -z "$argv" ] && [[ "$out" == *"$2"* ]]; then ok "$1"
  else bad "$1" "rc=$rc argv=[$(echo $argv)] out: $out"; fi
}

# A pid is gone once kill -0 fails or it is a zombie; waits up to 2 s for the reaper.
gone() {
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    kill -0 "$1" 2>/dev/null || return 0
    case "$(ps -o stat= -p "$1" 2>/dev/null)" in Z*) return 0 ;; esac
    sleep 0.1
  done
  return 1
}

S=tests/sim_boundary_test.gd
A=tests/sim_boundary_api_test.gd

# --- arguments: paths become -a res://..., -c is always there -----------------------------
run; check_argv "no args runs res://tests with -c" 0 res://tests --
run "$S"; check_argv "relative path" 0 "res://$S" --
run "./$S"; check_argv "./ path" 0 "res://$S" --
run "$REPO/$S"; check_argv "absolute path inside the repo" 0 "res://$S" --
run tests; check_argv "directory" 0 res://tests --
run "$S" "$A"; check_argv "two paths keep their order" 0 "res://$S" "res://$A" --
run -a "$S"; check_argv "-a X is one suite, no stray -a" 0 "res://$S" --
run --add "$S" "$A"; check_argv "--add X then a path" 0 "res://$S" "res://$A" --
run res://tests/not_checked.gd; check_argv "res:// passes unchecked" 0 res://tests/not_checked.gd --
run -i sim_boundary_test:test_x
check_argv "-i suite:test passes through, default suite kept" 0 res://tests -- -i sim_boundary_test:test_x
run "$S" -i sim_boundary_test:test_x
check_argv "path then -i suite:test" 0 "res://$S" -- -i sim_boundary_test:test_x

run tests/no_such_test.gd; check_refused "missing relative path -> 2" "no such test file or directory"
run -a tests/no_such_test.gd; check_refused "missing path after -a -> 2" "no such test file or directory"
run "$T"; check_refused "existing path outside the repo -> 2" "path outside the project"
run -a; check_refused "-a without a path -> 2" "needs a path"
TIMEOUT=abc; run; check_refused "non-integer TEST_TIMEOUT -> 2" "TEST_TIMEOUT must be"
GODOT_BIN="$T/no_godot"; run; check_refused "missing Godot -> 2" "Godot binary not found"

# --- exit codes ------------------------------------------------------------------------
CODE=100 OUT="1 failure"; run "$S"
if [ "$rc" -eq 100 ]; then ok "gdUnit exit 100 is kept"; else bad "gdUnit exit 100 is kept" "rc=$rc"; fi
CODE=0 OUT="No test cases found"; run "$S"
if [ "$rc" -eq 1 ]; then ok "no test cases with exit 0 -> 1"; else bad "no test cases -> 1" "rc=$rc"; fi
CODE=0 OUT="SCRIPT ERROR: boom"; run "$S"
if [ "$rc" -eq 3 ] && [[ "$out" == *"1 SCRIPT ERROR line(s)"* ]]; then ok "SCRIPT ERROR listed, exit 0 -> 3"
else bad "SCRIPT ERROR listed, exit 0 -> 3" "rc=$rc out: $out"; fi
# LT-42: only a passing run becomes 3; a non-zero gdUnit code (101: warnings) is kept.
CODE=101 OUT="SCRIPT ERROR: boom"; run "$S"
if [ "$rc" -eq 101 ] && [[ "$out" == *"1 SCRIPT ERROR line(s)"* ]]; then ok "SCRIPT ERROR listed, exit 101 kept"
else bad "SCRIPT ERROR listed, exit 101 kept" "rc=$rc out: $out"; fi
CODE=0 OUT="all passed"; run "$S"
if [ "$rc" -eq 0 ]; then ok "no SCRIPT ERROR, exit 0 kept"; else bad "no SCRIPT ERROR, exit 0 kept" "rc=$rc out: $out"; fi

# --- LT-42: re-import when the class cache is missing or older than a .gd or a directory ---
# A throwaway project (a copy of test.sh, one script) with every mtime set, so the repo's own
# .godot is never touched.
P="$T/proj"
mkdir -p "$P/scripts" "$P/sub" "$P/.godot"
cp "$REPO/scripts/test.sh" "$P/scripts/test.sh"
echo "extends Node" >"$P/sub/a.gd"
# old_tree: every file and directory 2020-01-01, the class cache 2021-01-01 (fresh).
old_tree() {
  find "$P" -exec touch -t 202001010000 {} +
  touch -t 202101010000 "$P/.godot/global_script_class_cache.cfg"
}
# check_import <name> <want imports> <want message part, "" for none>
check_import() {
  if [ "$rc" -eq 0 ] && [ "$imports" -eq "$2" ] && [[ "$out" == *"$3"* ]]; then ok "$1"
  else bad "$1" "rc=$rc imports=$imports (want $2) out: $out"; fi
}
R=res://tests/not_checked.gd
rm -f "$P/.godot/global_script_class_cache.cfg"
PROJ="$P"; run "$R"; check_import "no class cache -> import" 1 "no class cache yet"
old_tree; PROJ="$P"; run "$R"; check_import "fresh class cache -> no import" 0 ""
if [[ "$out" != *"Importing project"* ]]; then ok "fresh class cache -> no import message"
else bad "fresh class cache -> no import message" "$out"; fi
old_tree; touch "$P/sub/a.gd"; PROJ="$P"; run "$R"
check_import "a .gd newer than the class cache -> import" 1 "a.gd is newer than the class cache"
old_tree; mkdir "$P/new_dir"; PROJ="$P"; run "$R"
check_import "a directory newer than the class cache -> import" 1 "is newer than the class cache"
rmdir "$P/new_dir"
old_tree; touch "$P/sub/notes.txt"; touch -t 202001010000 "$P/sub"
PROJ="$P"; run "$R"; check_import "a newer non-.gd file -> no import" 0 ""
old_tree; touch "$P/.godot/x.gd"; touch -t 202001010000 "$P/.godot"; PROJ="$P"; run "$R"
check_import "a newer .gd under .godot (pruned) -> no import" 0 ""

# --- watchdog: a hung run that ignores SIGTERM and has a child ---------------------------
MODE=hang TIMEOUT=2; run "$S"
if [ "$rc" -eq 124 ]; then ok "hung run exits 124"; else bad "hung run exits 124" "rc=$rc out: $out"; fi
if [[ "$out" == *"TIMEOUT after 2s"* ]]; then ok "timeout message"; else bad "timeout message" "$out"; fi
if [ -f "$T/leader.pid" ] && [ -f "$T/child.pid" ]; then
  leader="$(cat "$T/leader.pid")" child="$(cat "$T/child.pid")"
  if gone "$leader"; then ok "hung leader killed"; else bad "hung leader killed" "pid $leader alive"; fi
  if gone "$child"; then ok "its child (same group) killed"; else bad "child killed" "pid $child alive"; fi
else
  bad "fake started its leader and child" "no pid files"
fi

echo "$passes passed, $fails failed"
[ "$fails" -eq 0 ]
