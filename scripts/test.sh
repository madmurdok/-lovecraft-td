#!/usr/bin/env bash
# Runs the gdUnit4 suite headless. Exits non-zero if any test fails, errors or the run hangs.
#
#   scripts/test.sh                                   # every suite under res://tests
#   scripts/test.sh tests/foo_test.gd tests/bar_test.gd   # only these suites (or directories)
#   scripts/test.sh tests/foo_test.gd -i foo_test:test_x  # args starting with '-' go to gdUnit
#
# A path argument (res://, relative to the repo root, or absolute inside the repo; also after
# -a/--add) becomes a suite to run; a missing path or one outside the repo exits 2. Arguments
# starting with '-', and a non-path value right after one, go to GdUnitCmdTool unchanged.
# gdUnit always runs with -c (continue), so every failing test is reported, not only the
# first one per suite.
#
# Env:
#   GODOT         Godot binary, default /Applications/Godot.app/Contents/MacOS/Godot.
#   TEST_TIMEOUT  wall-clock limit in seconds for the whole Godot run, default 1800; 0 = none.
#                 On expiry the whole Godot process group gets SIGTERM, then SIGKILL after 5 s,
#                 and the script exits 124. The default is ~7x a full run (~260 s of test time
#                 at LT-34), so a loaded machine still passes but a hung run (LT-34 S3 control
#                 5b: 56 min) is stopped in at most 30 min.
#
# Before the run the project is (re-)imported when .godot/global_script_class_cache.cfg is
# missing or older than any .gd file or directory of the project (a script added, edited,
# renamed or deleted): a stale class cache gives parse errors (LT-36 S1, LT-42). An up-to-date
# cache costs one `find`, no Godot start.
#
# Exit codes: gdUnit's own (0 ok, 100 failures/errors, 101 warnings...), 1 when no test case
# was found, 2 when Godot is missing, 3 when the run passed but the log has a SCRIPT ERROR
# (raised outside any test, so gdUnit did not count it; LT-42), 124 on timeout.
set -uo pipefail
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TEST_TIMEOUT="${TEST_TIMEOUT:-1800}"
cd "$(dirname "$0")/.."

if [ ! -x "$GODOT" ]; then
  echo "Godot binary not found: $GODOT (set \$GODOT)" >&2
  exit 2
fi
case "$TEST_TIMEOUT" in
  ''|*[!0-9]*) echo "TEST_TIMEOUT must be a whole number of seconds, got '$TEST_TIMEOUT'" >&2; exit 2 ;;
esac

# Runs "$@" as the leader of its own process group, killing the whole group after
# $TEST_TIMEOUT seconds (macOS has no coreutils `timeout`; perl is always there).
# Exits with the command's code, 128+signal if it died of a signal, 124 on timeout.
guarded() {
  perl -e '
    my $t = shift;
    my $pid = fork() // die "test.sh: fork failed: $!\n";
    if ($pid == 0) { setpgrp(0, 0); exec @ARGV or die "test.sh: exec $ARGV[0] failed: $!\n"; }
    setpgrp($pid, $pid);  # also from the parent: no window where the group does not exist
    my $kill = sub {
      kill "TERM", -$pid;
      for (1 .. 50) { last if waitpid($pid, 1) > 0; select(undef, undef, undef, 0.1); }
      kill "KILL", -$pid;
      waitpid($pid, 0);
    };
    $SIG{ALRM} = sub {
      print STDERR "\ntest.sh: TIMEOUT after ${t}s (TEST_TIMEOUT), killing process group $pid\n";
      $kill->(); exit 124;
    };
    $SIG{INT} = $SIG{TERM} = $SIG{HUP} = sub { $kill->(); exit 130; };
    alarm $t if $t > 0;
    waitpid($pid, 0);
    my $s = $?;
    exit(($s & 127) ? 128 + ($s & 127) : $s >> 8);
  ' "$TEST_TIMEOUT" "$@"
}

class_cache=.godot/global_script_class_cache.cfg
stale=""
if [ ! -f "$class_cache" ]; then
  stale="no class cache yet"
else
  newer="$(find . \( -path ./.godot -o -path ./.git -o -path ./reports -o -path ./build \) -prune \
    -o \( -name '*.gd' -o -type d \) -newer "$class_cache" -print -quit)"
  [ -n "$newer" ] && stale="$newer is newer than the class cache"
fi
if [ -n "$stale" ]; then
  echo "Importing project ($stale)..."
  guarded "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi

root="$PWD"
# Turns a path argument into a res:// path; exits 2 on one outside the repo or not existing.
to_res() {
  local p="$1"
  if [[ "$p" == res://* ]]; then echo "$p"; return; fi
  if [ ! -e "$p" ]; then echo "test.sh: no such test file or directory: $p" >&2; exit 2; fi
  if [[ "$p" == /* ]]; then
    if [[ "$p" != "$root"/* ]]; then echo "test.sh: path outside the project: $p" >&2; exit 2; fi
    p="${p#"$root"/}"
  fi
  echo "res://${p#./}"
}

adds=()
extra=()
prev_opt=0  # the previous argument was a gdUnit option, so this one may be its value
while [ $# -gt 0 ]; do
  a="$1"; shift
  if [[ "$a" == -a || "$a" == --add ]]; then
    # gdUnit's own form: the next argument is the path.
    if [ $# -eq 0 ]; then echo "test.sh: $a needs a path" >&2; exit 2; fi
    r="$(to_res "$1")" || exit 2; shift
    adds+=(-a "$r"); prev_opt=0
  elif [[ "$a" == -* ]]; then
    extra+=("$a"); prev_opt=1
  elif [[ "$a" == res://* || -e "$a" || $prev_opt -eq 0 ]]; then
    r="$(to_res "$a")" || exit 2
    adds+=(-a "$r"); prev_opt=0
  else
    extra+=("$a"); prev_opt=0  # value of the preceding option, e.g. -i suite:test
  fi
done
[ ${#adds[@]} -eq 0 ] && adds=(-a res://tests)

# No -d: under the debugger a script parse error still exits 0.
log="$(mktemp)"
guarded "$GODOT" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
  "${adds[@]}" --ignoreHeadlessMode -c ${extra[@]+"${extra[@]}"} 2>&1 | tee "$log"
code=${PIPESTATUS[0]}
# gdUnit4 exits 0 when it finds no tests (e.g. every test script failed to parse).
if [ "$code" -eq 0 ] && grep -q "No test cases found" "$log"; then
  echo "No test cases found: treating as failure" >&2
  code=1
fi
# gdUnit reports a runtime error inside a test as a test error (exit 100). One raised outside
# any test (a deferred call, a node's _process after its test ended) is only logged: list it
# and fail an otherwise passing run with 3 (LT-42: a full run had none, so no false alarms).
n_script_errors=$(grep -c "SCRIPT ERROR:" "$log")
if [ "$n_script_errors" -gt 0 ]; then
  echo "test.sh: $n_script_errors SCRIPT ERROR line(s) in the log:" >&2
  grep -A1 "SCRIPT ERROR:" "$log" | grep -v "^--$" >&2
  if [ "$code" -eq 0 ]; then
    echo "test.sh: failing the run (exit 3): SCRIPT ERROR outside any test" >&2
    code=3
  fi
fi
rm -f "$log"
echo "gdUnit4 exit code: $code"
exit $code
