"""LT-56 balance lab: unit tests for tools/balance/balance.py (stdlib unittest, no Godot).

  python3 -m unittest discover -s tools/balance/tests -v

Godot is never started: main()'s Godot work goes through run_job and godot_bin, which these
tests replace; run_job itself is tested with subprocess.Popen replaced.
"""
import contextlib
import copy
import io
import json
import os
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import balance  # noqa: E402
from balance import PatchError  # noqa: E402


def patched(target, patch):
    t = copy.deepcopy(target)
    balance.apply_patch(t, patch)
    return t


# --- 1-3: merge, replacement, array addressing -------------------------------------------

class ApplyPatchTest(unittest.TestCase):
    def test_object_patch_deep_merges_and_keeps_siblings(self):
        doc = {"a": {"x": 1, "y": {"p": 2, "q": 3}}, "b": "keep"}
        self.assertEqual(patched(doc, {"a": {"y": {"q": 30}}}),
                         {"a": {"x": 1, "y": {"p": 2, "q": 30}}, "b": "keep"})

    def test_non_object_values_replace(self):
        doc = {"n": 1, "s": "a", "f": True, "arr": [1, 2, 3]}
        self.assertEqual(patched(doc, {"n": 5, "s": "b", "f": False, "arr": [9]}),
                         {"n": 5, "s": "b", "f": False, "arr": [9]})

    def test_array_index_negative_star_and_field_value(self):
        doc = {"t": [{"id": "a", "c": 1}, {"id": "b", "c": 2}, {"id": "a", "c": 3}]}
        self.assertEqual([i["c"] for i in patched(doc, {"t": {"0": {"c": 10}}})["t"]], [10, 2, 3])
        self.assertEqual([i["c"] for i in patched(doc, {"t": {"-1": {"c": 30}}})["t"]], [1, 2, 30])
        self.assertEqual([i["c"] for i in patched(doc, {"t": {"*": {"c": 0}}})["t"]], [0, 0, 0])
        self.assertEqual([i["c"] for i in patched(doc, {"t": {"id=a": {"c": 7}}})["t"]], [7, 2, 7])
        # a numeric field value is matched too
        self.assertEqual([i["c"] for i in patched(doc, {"t": {"c=2": {"c": 20}}})["t"]], [1, 20, 3])

    def test_array_of_scalars_by_index(self):
        self.assertEqual(patched({"l": [1, 2, 3]}, {"l": {"1": 5, "-1": 6}}), {"l": [1, 5, 6]})


# --- 4-6: errors --------------------------------------------------------------------------

class PatchErrorTest(unittest.TestCase):
    def err(self, doc, patch):
        with self.assertRaises(PatchError) as cm:
            balance.apply_patch(copy.deepcopy(doc), patch)
        return str(cm.exception)

    def test_missing_key_names_dotted_path_and_existing_keys(self):
        doc = {"lighthouse": {"oil": {"price": 1, "start": 2, "cap": 3}}}
        msg = self.err(doc, {"lighthouse": {"oil": {"prise": 2}}})
        self.assertIn("lighthouse.oil.prise", msg)
        self.assertIn("no such key", msg)
        for k in ("price", "start", "cap"):
            self.assertIn(k, msg)

    def test_select_errors_name_the_path(self):
        doc = {"t": [{"id": "a", "c": 1}], "e": []}
        cases = {
            "out of range": ({"t": {"5": {"c": 2}}}, "t"),
            "negative out of range": ({"t": {"-2": {"c": 2}}}, "t"),
            "star on empty": ({"e": {"*": 1}}, "e"),
            "unmatched field=value": ({"t": {"id=zzz": {"c": 2}}}, "t"),
            "non-index key on array": ({"t": {"c": 2}}, "t"),
        }
        for name, (patch, path) in cases.items():
            with self.subTest(name):
                self.assertIn(path, self.err(doc, patch))

    def test_type_change_is_rejected(self):
        doc = {"i": 1, "f": 1.5, "s": "x", "b": True, "l": [1], "o": {"k": 1}}
        for name, patch in {"int->str": {"i": "1"}, "str->int": {"s": 1},
                            "bool->int": {"b": 1}, "int->bool": {"i": True},
                            "float->bool": {"f": False}, "list->str": {"l": "x"},
                            "object->number": {"o": 1}, "int->null": {"i": None}}.items():
            with self.subTest(name):
                self.assertIn(list(patch)[0], self.err(doc, patch))

    def test_int_and_float_are_interchangeable(self):
        self.assertEqual(patched({"i": 1, "f": 1.5}, {"i": 2.5, "f": 3}), {"i": 2.5, "f": 3})

    def test_failed_patch_names_nested_array_path(self):
        doc = {"t": [{"id": "a", "c": 1}]}
        msg = self.err(doc, {"t": {"id=a": {"c": "x"}}})
        self.assertIn("t.0.c", msg)


# --- LT-111: optional keys a patch may add -------------------------------------------------

class OptionalKeysTest(unittest.TestCase):
    WAVES = {"build_phase_seconds": 40,
             "waves": [{"groups": [{"type": "cultist", "count": 8}]},
                       {"groups": [{"type": "hybrid", "count": 2}]}]}

    def apply(self, patch):
        doc = copy.deepcopy(self.WAVES)
        balance.apply_patch(doc, patch, optional=balance.OPTIONAL_KEYS["waves.json"])
        return doc

    def err(self, patch):
        with self.assertRaises(PatchError) as cm:
            self.apply(patch)
        return str(cm.exception)

    def test_wave_multipliers_may_be_added_to_the_addressed_waves_only(self):
        doc = self.apply({"waves": {"1": {"hp_mult": 2, "speed_mult": 0.5}}})
        self.assertEqual(doc["waves"][1], {"groups": [{"type": "hybrid", "count": 2}],
                                           "hp_mult": 2, "speed_mult": 0.5})
        self.assertEqual(doc["waves"][0], self.WAVES["waves"][0])
        doc = self.apply({"waves": {"*": {"speed_mult": 1.25}}})
        self.assertEqual([w["speed_mult"] for w in doc["waves"]], [1.25, 1.25])

    def test_an_added_multiplier_can_be_patched_again(self):
        doc = self.apply({"waves": {"0": {"hp_mult": 2}}})
        balance.apply_patch(doc, {"waves": {"0": {"hp_mult": 3}}},
                            optional=balance.OPTIONAL_KEYS["waves.json"])
        self.assertEqual(doc["waves"][0]["hp_mult"], 3)

    def test_other_unknown_keys_and_misplaced_multipliers_are_still_errors(self):
        cases = {
            "typo in a wave": ({"waves": {"0": {"hp_mul": 2}}}, "waves.0.hp_mul"),
            "multiplier on a group": ({"waves": {"0": {"groups": {"0": {"hp_mult": 2}}}}},
                                      "waves.0.groups.0.hp_mult"),
            "multiplier at the root": ({"hp_mult": 2}, "hp_mult"),
        }
        for name, (patch, path) in cases.items():
            with self.subTest(name):
                msg = self.err(patch)
                self.assertIn(path, msg)
                self.assertIn("no such key", msg)

    def test_an_added_multiplier_must_be_a_number(self):
        for name, value in {"string": "2", "bool": True, "null": None, "list": [2]}.items():
            with self.subTest(name):
                self.assertIn("waves.0.hp_mult", self.err({"waves": {"0": {"hp_mult": value}}}))

    def test_without_optional_keys_adding_one_is_an_error(self):
        with self.assertRaises(PatchError) as cm:
            balance.apply_patch(copy.deepcopy(self.WAVES), {"waves": {"0": {"hp_mult": 2}}})
        self.assertIn("no such key", str(cm.exception))


# --- 7-8: materialize, load_variant --------------------------------------------------------

class TempDirs(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.tmp = self._tmp.name
        self.data = os.path.join(self.tmp, "data")
        self.variants = os.path.join(self.tmp, "variants")
        os.makedirs(self.data)
        os.makedirs(self.variants)
        for p in (mock.patch.object(balance, "DATA", self.data),
                  mock.patch.object(balance, "VARIANTS", self.variants)):
            p.start()
            self.addCleanup(p.stop)
        self.addCleanup(self._tmp.cleanup)

    def write(self, d, name, obj_or_text):
        text = obj_or_text if isinstance(obj_or_text, str) else json.dumps(obj_or_text)
        with open(os.path.join(d, name), "w", encoding="utf-8") as f:
            f.write(text)

    def read(self, path):
        with open(path, "rb") as f:
            return f.read()


class MaterializeTest(TempDirs):
    def test_unpatched_files_are_byte_identical_and_patch_applies(self):
        self.write(self.data, "a.json", '{ "x" : 1,\n  "y": [1,2] }\n')  # odd formatting
        self.write(self.data, "b.json", {"k": {"v": 1, "w": 2}})
        self.write(self.data, "notes.txt", "not json data")
        dest = os.path.join(self.tmp, "out")
        balance.materialize({"name": "v", "patch": {"b.json": {"k": {"v": 5}}}, "flags": []}, dest)
        self.assertEqual(self.read(os.path.join(dest, "a.json")),
                         self.read(os.path.join(self.data, "a.json")))
        self.assertEqual(json.loads(self.read(os.path.join(dest, "b.json"))),
                         {"k": {"v": 5, "w": 2}})
        # data/ itself untouched
        self.assertEqual(json.loads(self.read(os.path.join(self.data, "b.json"))),
                         {"k": {"v": 1, "w": 2}})

    def test_missing_data_file(self):
        self.write(self.data, "a.json", {"x": 1})
        with self.assertRaises(PatchError) as cm:
            balance.materialize({"name": "myvar", "patch": {"nope.json": {"x": 2}}, "flags": []},
                                os.path.join(self.tmp, "out"))
        self.assertIn("no data file data/nope.json", str(cm.exception))
        self.assertIn("myvar", str(cm.exception))

    def test_patch_error_is_prefixed_with_variant_name(self):
        self.write(self.data, "a.json", {"x": 1})
        with self.assertRaises(PatchError) as cm:
            balance.materialize({"name": "myvar", "patch": {"a.json": {"z": 2}}, "flags": []},
                                os.path.join(self.tmp, "out"))
        msg = str(cm.exception)
        self.assertTrue(msg.startswith("variant myvar"), msg)
        self.assertIn("a.json", msg)
        self.assertIn("z", msg)


    def test_waves_json_may_add_multipliers_and_other_files_may_not(self):
        waves = OptionalKeysTest.WAVES
        self.write(self.data, "waves.json", waves)
        self.write(self.data, "other.json", waves)
        dest = os.path.join(self.tmp, "out")
        balance.materialize({"name": "v", "patch": {"waves.json": {"waves": {"1": {"hp_mult": 2}}}},
                             "flags": []}, dest)
        out = json.loads(self.read(os.path.join(dest, "waves.json")))
        self.assertEqual(out["waves"][1]["hp_mult"], 2)
        self.assertNotIn("hp_mult", out["waves"][0])
        with self.assertRaises(PatchError) as cm:
            balance.materialize({"name": "v", "patch": {"other.json": {"waves": {"1": {"hp_mult": 2}}}},
                                 "flags": []}, os.path.join(self.tmp, "out2"))
        self.assertIn("no such key", str(cm.exception))


class LoadVariantTest(TempDirs):
    def test_good_variant(self):
        self.write(self.variants, "ok", "")  # not a .json: ignored
        self.write(self.variants, "ok.json", {"description": "d", "patch": {"a.json": {"x": 1}},
                                              "flags": ["--flare=0"]})
        v = balance.load_variant("ok")
        self.assertEqual((v["name"], v["description"], v["patch"], v["flags"]),
                         ("ok", "d", {"a.json": {"x": 1}}, ["--flare=0"]))

    def test_bad_variants(self):
        cases = {
            "unknown_key": {"patch": {}, "seeds": 3},
            "patch_entry_not_object": {"patch": {"a.json": 5}},
            "patch_not_object": {"patch": ["a.json"]},
            "flag_not_string": {"flags": [1]},
            "flags_not_list": {"flags": "--flare=0"},
            "top_not_object": [1, 2],
            "bad_json": "{not json",
        }
        for flag in balance.RESERVED_FLAGS:
            cases["reserved" + flag.strip("-=")] = {"flags": [flag + "x"]}
        self.assertEqual(len([c for c in cases if c.startswith("reserved")]), 4)
        for name, body in cases.items():
            self.write(self.variants, name + ".json", body)
            with self.subTest(name), self.assertRaises(PatchError):
                balance.load_variant(name)

    def test_missing_variant_file(self):
        with self.assertRaises(PatchError) as cm:
            balance.load_variant("ghost")
        self.assertIn("ghost", str(cm.exception))


# --- 11: strategies from the bot ----------------------------------------------------------

class BotStrategiesTest(unittest.TestCase):
    def test_reads_the_names_of_the_strategies_file_in_order(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "strategies.json")
            with open(f, "w") as out:
                json.dump({"tunables": {"build_first": 5, "flare_min_live": 4},
                           "strategies": [{"name": "gamma", "cycle": ["x"]},
                                          {"name": "alpha", "cycle": ["x"]},
                                          {"name": "beta", "cycle": ["x"]}]}, out)
            with mock.patch.object(balance, "STRATEGIES_FILE", f):
                self.assertEqual(balance.bot_strategies(), ["gamma", "alpha", "beta"])

    def test_real_bot_file(self):
        s = balance.bot_strategies()
        self.assertIn("mundane", s)
        self.assertEqual(len(s), len(set(s)))

    def test_real_bot_file_is_the_shipped_order(self):
        self.assertEqual(balance.STRATEGIES_FILE,
                         os.path.join(balance.REPO, "tools", "bot", "strategies.json"))
        self.assertEqual(balance.bot_strategies(),
                         ["mundane", "occult", "mixed", "madness", "demolition", "battery",
                          "resonator", "gate", "circle", "light"])

    def test_missing_or_bad_file_exits_naming_the_file(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "strategies.json")
            cases = {"missing": None, "bad json": "{", "no strategies": '{"tunables": {}}',
                     "row without name": '{"strategies": [{"cycle": ["x"]}]}',
                     "not an object": "[1]"}
            for what, text in cases.items():
                with self.subTest(what):
                    if text is None:
                        if os.path.exists(f):
                            os.remove(f)
                    else:
                        with open(f, "w") as out:
                            out.write(text)
                    with mock.patch.object(balance, "STRATEGIES_FILE", f):
                        with self.assertRaises(SystemExit) as cm:
                            balance.bot_strategies()
                    self.assertIn(f, str(cm.exception.code))


# --- 12: cell / report --------------------------------------------------------------------

def runs(won, lost, timeout=0):
    return ([{"outcome": "won"}] * won + [{"outcome": "lost"}] * lost
            + [{"outcome": "timeout"}] * timeout)


META = {"started": "2026-11-01 12:00:00", "commit": "abc1234", "jobs": 3,
        "uptime_start": "UP-START load 1.0", "uptime_end": "UP-END load 2.0", "wall": 12.0,
        "work": "/tmp/w"}


def table_rows(md):
    return [l for l in md.splitlines() if l.startswith("| ") and not l.startswith("| variant")]


class ReportTest(unittest.TestCase):
    def make(self, cells, seeds=20, target=0.5, times=None):
        """cells: {variant: {strategy: runs}}"""
        variants = [{"name": v, "description": "", "flags": []} for v in cells]
        strategies = list(next(iter(cells.values())))
        results = {(v, s): {"runs": r, "times": (times or {}).get((v, s), {})}
                   for v, row in cells.items() for s, r in row.items()}
        return balance.report(variants, strategies, results, seeds, target, META)

    def test_target_mark_at_the_threshold(self):
        md = self.make({"v": {"a": runs(10, 10), "b": runs(11, 9)}})
        row = table_rows(md)[0]
        self.assertIn("| 10/10 **yes** |", row)
        self.assertIn("| 11/9 no |", row)
        self.assertIn("| 1/2 |", row)  # met column

    def test_target_fraction_is_configurable_and_rounded_up(self):
        # 0.55 * 20 = 11 -> 10 losses is not enough
        row = table_rows(self.make({"v": {"a": runs(10, 10), "b": runs(9, 11)}}, target=0.55))[0]
        self.assertIn("| 10/10 no |", row)
        self.assertIn("| 9/11 **yes** |", row)
        # 0.5 * 5 = 2.5 -> 3
        row = table_rows(self.make({"v": {"a": runs(3, 2), "b": runs(2, 3)}}, seeds=5))[0]
        self.assertIn("| 3/2 no |", row)
        self.assertIn("| 2/3 **yes** |", row)
        # 0.7 * 10 is 7.000000000000001 in floating point: still 7
        row = table_rows(self.make({"v": {"a": runs(3, 7)}}, seeds=10, target=0.7))[0]
        self.assertIn("| 3/7 **yes** |", row)

    def test_timeouts_shown_and_counted_as_neither(self):
        # 9 losses + 2 timeouts: 11 non-wins, but only losses count toward >= 10
        row = table_rows(self.make({"v": {"a": runs(9, 9, 2), "b": runs(0, 10, 10)}}))[0]
        self.assertIn("| 9/9 (2 t/o) no |", row)
        self.assertIn("| 0/10 (10 t/o) **yes** |", row)
        self.assertIn("| 1/2 |", row)

    def test_header_and_seconds_per_run(self):
        times = {("v", "a"): {"real": 30.0, "user": 15.0}, ("v", "b"): {"real": 10.0, "user": 5.0}}
        md = self.make({"v": {"a": runs(5, 5), "b": runs(5, 5)}}, seeds=10, target=0.5,
                       times=times)
        for s in ("abc1234", "UP-START load 1.0", "UP-END load 2.0"):
            self.assertIn(s, md)
        head = md.split("| variant")[0]
        self.assertIn("10 seeds", head)
        self.assertIn("loses >= 5 of 10", head)
        row = table_rows(md)[0]
        self.assertIn("| 2.0 |", row)   # (30 + 10) s / 20 runs
        self.assertIn("| 0.50 |", row)  # user/real
        self.assertTrue(row.startswith("| v |"))

    def test_one_row_per_variant_in_order(self):
        md = self.make({"v1": {"a": runs(1, 1)}, "v2": {"a": runs(0, 2)}}, seeds=2)
        self.assertEqual([r.split("|")[1].strip() for r in table_rows(md)], ["v1", "v2"])

    def test_no_wave_table_without_waves_survived(self):
        self.assertNotIn("Where runs end", self.make({"v": {"a": runs(1, 1)}}, seeds=2))

    def test_wave_table_counts_losses_by_wave_and_early_share(self):
        # 5 waves: a won run survived 5; lost runs end in waves 1, 3, 3 and 4.
        def r(outcome, ws):
            return {"outcome": outcome, "waves_survived": ws}
        md = self.make({"v": {"a": [r("won", 5), r("lost", 0), r("lost", 2)],
                              "b": [r("lost", 2), r("lost", 3)]}}, seeds=3)
        wave_rows = [l for l in md.split("Where runs end")[1].splitlines()
                     if l.startswith("| v |")]
        self.assertEqual(len(wave_rows), 1)
        row = wave_rows[0]
        self.assertIn("| 1.0.1.0.0 (2.3) |", row)  # a: (5 + 0 + 2) / 3 survived
        self.assertIn("| 0.0.1.1.0 (2.5) |", row)
        self.assertIn("| 1.0.2.1.0 |", row)  # all strategies
        self.assertIn("| 2/5 (40%) |", row)  # survived waves 1..3: ws 5 and 3

    def test_target_needs_both_parts_with_flare_on_only(self):
        # 5 waves, early = 3, seeds 4 -> loses >= 2 and survives waves 1..3 in >= 3.
        def r(outcome, ws):
            return {"outcome": outcome, "waves_survived": ws}
        good = [r("lost", 3), r("lost", 4), r("won", 5), r("won", 5)]  # 4 survive early, 2 losses
        weak = [r("lost", 0), r("lost", 2), r("won", 5), r("won", 5)]  # 2 survive early
        md = self.make({"v": {"a": good, "b": weak}}, seeds=4)
        row = [l for l in md.splitlines() if l.startswith("| v |")][0]
        self.assertIn("2/2 e4 **yes**", row)
        self.assertIn("2/2 e2 no", row)
        self.assertIn("| 1/2 |", row)


# --- 13: run_job ---------------------------------------------------------------------------

def fake_proc(stdout_lines, rc=0, real=4.0, user=2.0, calls=None):
    """Stands in for subprocess.Popen: writes the output at once, wait() returns `rc`."""
    def popen(cmd, stdout=None, stderr=None, **kw):
        if calls is not None:
            calls.append(cmd)
        stdout.write("".join(l + "\n" for l in stdout_lines))
        stderr.write(f"some godot noise\nreal {real:.2f}\nuser {user:.2f}\nsys 0.10\n")
        return mock.Mock(returncode=rc, pid=0, wait=mock.Mock(return_value=rc))
    return popen


class RunJobTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.job = {"variant": "v", "strategy": "occult", "data": "/x/data_v", "flags": ["--flare=0"]}

    def run_job(self, lines, rc=0, seeds=2, calls=None):
        with mock.patch.object(balance.subprocess, "Popen", fake_proc(lines, rc, calls=calls)):
            return balance.run_job("/g/godot", self.job, seeds, self._tmp.name)

    def test_ok_job_parses_runs_and_times_and_plays_one_strategy(self):
        calls = []
        r = self.run_job(['noise', 'RUN {"outcome": "won"}', 'RUN {"outcome": "lost"}',
                          'SUMMARY []'], calls=calls)
        self.assertIsNone(r["problem"])
        self.assertEqual([x["outcome"] for x in r["runs"]], ["won", "lost"])
        self.assertEqual((r["times"]["real"], r["times"]["user"]), (4.0, 2.0))
        cmd = calls[0]
        for a in ("--seeds=2", "--data=/x/data_v", "--strategies=occult", "--flare=0"):
            self.assertIn(a, cmd)
        self.assertIn("/g/godot", cmd)

    def test_nonzero_exit_fails_the_job(self):
        r = self.run_job(['RUN {"outcome": "won"}', 'RUN {"outcome": "lost"}'], rc=1)
        self.assertIsNotNone(r["problem"])
        self.assertTrue(r["err"].endswith(".err"))

    def test_wrong_run_count_fails_the_job(self):
        for lines in (['RUN {"outcome": "won"}'],
                      ['RUN {"outcome": "won"}'] * 3):
            with self.subTest(len(lines)):
                self.assertIsNotNone(self.run_job(lines)["problem"])


# --- 13b: run_job timeout (LT-101), a real process ---------------------------------------

class RunJobTimeoutTest(unittest.TestCase):
    """A job still running at the limit is killed with its whole process group and fails.
    "godot" is a shell script that starts a grandchild `sleep`, records its pid and waits, so
    the job never ends by itself; the limit is patched to 1 s."""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.pidfile = os.path.join(self._tmp.name, "child.pid")
        self.godot = os.path.join(self._tmp.name, "godot")
        with open(self.godot, "w") as f:
            f.write("#!/bin/sh\nsleep 60 &\necho $! > '%s'\nwait\n" % self.pidfile)
        os.chmod(self.godot, 0o755)
        self.job = {"variant": "v", "strategy": "mundane", "data": "/x/data_v", "flags": []}

    def _alive(self, pid):
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return False
        return True

    def test_hung_job_is_killed_with_its_children_and_reported(self):
        with mock.patch.object(balance, "JOB_TIMEOUT_BASE", 1), \
                mock.patch.object(balance, "JOB_TIMEOUT_PER_SEED", 0):
            t0 = time.monotonic()
            r = balance.run_job(self.godot, self.job, 2, self._tmp.name)
            elapsed = time.monotonic() - t0
        self.assertEqual(r["problem"], "timeout after 1 s")
        self.assertEqual(r["runs"], [])
        self.assertLess(elapsed, 30)  # the grandchild sleeps 60 s: run_job did not wait for it
        with open(self.pidfile) as f:
            child = int(f.read())
        # The grandchild (Godot's stand-in under /usr/bin/time) is gone too; an orphan is
        # reaped by launchd/init shortly after the kill, so allow a moment.
        deadline = time.monotonic() + 5
        while self._alive(child) and time.monotonic() < deadline:
            time.sleep(0.05)
        alive = self._alive(child)
        if alive:
            os.kill(child, 9)
        self.assertFalse(alive, "the grandchild of the timed-out job is still running")

    def test_limit_scales_with_seeds(self):
        self.assertEqual(balance.JOB_TIMEOUT_BASE + balance.JOB_TIMEOUT_PER_SEED * 20, 1320)
        # A quick job under the limit is not a timeout.
        with open(self.godot, "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        with mock.patch.object(balance, "JOB_TIMEOUT_BASE", 5), \
                mock.patch.object(balance, "JOB_TIMEOUT_PER_SEED", 0):
            r = balance.run_job(self.godot, self.job, 0, self._tmp.name)
        self.assertIsNone(r["problem"])


# --- 9, 10, 13, 14: main -------------------------------------------------------------------

class MainTest(TempDirs):
    def setUp(self):
        super().setUp()
        self.write(self.data, "a.json", {"x": 1, "y": {"z": 2}})
        self.write(self.variants, "good.json", {"patch": {"a.json": {"x": 3}}})
        self.write(self.variants, "good2.json", {"patch": {}})
        self.work = os.path.join(self.tmp, "work")
        self.started = []
        self.lock = threading.Lock()
        p = mock.patch.object(balance, "bot_strategies", return_value=["s1", "s2", "s3"])
        p.start()
        self.addCleanup(p.stop)
        p = mock.patch.object(balance, "godot_bin", return_value="/fake/godot")
        p.start()
        self.addCleanup(p.stop)

    def fake_run_job(self, outcome="lost", problem=None, hold=None):
        def run(godot, job, seeds, logdir):
            with self.lock:
                self.started.append(job)
            if hold:
                hold(job)
            return dict(job, runs=[{"outcome": outcome}] * seeds, times={"real": 1.0, "user": 1.0},
                        problem=problem, log=os.path.join(logdir, "x.log"),
                        err=os.path.join(logdir, job["variant"] + "." + job["strategy"] + ".err"))
        return run

    def main(self, *args, run_job=None):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(balance, "run_job", run_job or self.fake_run_job()), \
                contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            rc = balance.main(list(args))
        return rc, out.getvalue(), err.getvalue()

    def test_bad_variants_exit_2_list_every_error_and_start_nothing(self):
        self.write(self.variants, "bad1.json", {"patch": {"a.json": {"nokey": 1}}})
        self.write(self.variants, "bad2.json", {"patch": {"a.json": {"x": "str"}}})
        with mock.patch.object(balance.subprocess, "run") as sp, \
                mock.patch.object(balance, "godot_bin") as gb:
            rc, out, err = self.main("good", "bad1", "bad2", "ghost", "--work=" + self.work)
            sp.assert_not_called()
            gb.assert_not_called()
        self.assertEqual(rc, 2)
        self.assertEqual(self.started, [])
        for s in ("bad1", "nokey", "bad2", "ghost"):
            self.assertIn(s, err)

    def test_check_validates_and_runs_nothing(self):
        rc, out, err = self.main("good", "--check", "--work=" + self.work)
        self.assertEqual(rc, 0, err)
        self.assertEqual(self.started, [])
        with open(os.path.join(self.work, "data_good", "a.json")) as f:
            self.assertEqual(json.load(f)["x"], 3)
        self.write(self.variants, "bad.json", {"patch": {"a.json": {"q": 1}}})
        rc, out, err = self.main("good", "bad", "--check", "--work=" + self.work)
        self.assertEqual(rc, 2)

    def test_work_inside_the_repo_exits_2(self):
        rc, out, err = self.main("good", "--work=" + os.path.join(balance.REPO, "tmp_balance_x"))
        self.assertEqual(rc, 2)
        self.assertEqual(self.started, [])
        self.assertFalse(os.path.exists(os.path.join(balance.REPO, "tmp_balance_x")))

    def test_unknown_strategy_exits_2(self):
        rc, out, err = self.main("good", "--strategies=s1,nope", "--work=" + self.work)
        self.assertEqual(rc, 2)
        self.assertIn("nope", err)
        self.assertEqual(self.started, [])

    def test_bad_option_values_exit_2(self):
        for a in ("--seeds=x", "--jobs=0", "--target=1.5", "--seeds=0", "--bogus=1", "-x"):
            with self.subTest(a):
                rc, out, err = self.main("good", a, "--work=" + self.work)
                self.assertEqual(rc, 2)
                self.assertEqual(self.started, [])

    def test_one_job_per_variant_and_strategy_and_report(self):
        outp = os.path.join(self.tmp, "r.md")
        rc, out, err = self.main("good", "good2", "--strategies=s3,s1", "--seeds=4",
                                 "--work=" + self.work, "--out=" + outp)
        self.assertEqual(rc, 0, err)
        self.assertEqual(sorted((j["variant"], j["strategy"]) for j in self.started),
                         sorted((v, s) for v in ("good", "good2") for s in ("s3", "s1")))
        for j in self.started:
            self.assertEqual(j["data"], os.path.join(self.work, "data_" + j["variant"]))
        with open(outp) as f:
            md = f.read()
        self.assertEqual(len(table_rows(md)), 2)
        self.assertIn("0/4 **yes**", md)

    def test_default_runs_every_strategy_of_the_bot(self):
        rc, out, err = self.main("good", "--work=" + self.work)
        self.assertEqual(rc, 0, err)
        self.assertEqual(sorted(j["strategy"] for j in self.started), ["s1", "s2", "s3"])

    def test_failed_job_exits_1_names_the_err_log_and_still_writes_the_report(self):
        outp = os.path.join(self.tmp, "r.md")
        rc, out, err = self.main("good", "--strategies=s2", "--work=" + self.work,
                                 "--out=" + outp, run_job=self.fake_run_job(problem="exit 1"))
        self.assertEqual(rc, 1)
        self.assertIn("good.s2.err", out + err)
        self.assertTrue(os.path.isfile(outp))

    def test_at_most_jobs_godot_processes_at_once(self):
        active = [0]
        peak = [0]
        reached = threading.Event()

        def hold(job):
            with self.lock:
                active[0] += 1
                peak[0] = max(peak[0], active[0])
                if active[0] >= 2:
                    reached.set()
            reached.wait(2.0)  # let a second worker start, if there is one
            time.sleep(0.02)
            with self.lock:
                active[0] -= 1

        rc, out, err = self.main("good", "good2", "--jobs=2", "--work=" + self.work,
                                 run_job=self.fake_run_job(hold=hold))
        self.assertEqual(rc, 0, err)
        self.assertEqual(len(self.started), 6)
        self.assertEqual(peak[0], 2)

    def test_jobs_one_runs_serially(self):
        active, peak = [0], [0]

        def hold(job):
            with self.lock:
                active[0] += 1
                peak[0] = max(peak[0], active[0])
            time.sleep(0.02)
            with self.lock:
                active[0] -= 1

        rc, out, err = self.main("good", "--jobs=1", "--work=" + self.work,
                                 run_job=self.fake_run_job(hold=hold))
        self.assertEqual(rc, 0, err)
        self.assertEqual(peak[0], 1)


if __name__ == "__main__":
    unittest.main()
