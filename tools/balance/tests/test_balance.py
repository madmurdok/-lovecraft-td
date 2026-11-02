"""LT-56 balance lab: unit tests for tools/balance/balance.py (stdlib unittest, no Godot).

  python3 -m unittest discover -s tools/balance/tests -v

Godot is never started: main()'s Godot work goes through run_job and godot_bin, which these
tests replace; run_job itself is tested with subprocess.run replaced.
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
    def test_reads_the_strategies_const_of_the_bot_file(self):
        with tempfile.TemporaryDirectory() as d:
            f = os.path.join(d, "bot.gd")
            with open(f, "w") as out:
                out.write('extends SceneTree\nconst OTHER := ["x"]\n'
                          'const STRATEGIES := ["alpha", "beta", "gamma"]\n')
            with mock.patch.object(balance, "BOT_FILE", f):
                self.assertEqual(balance.bot_strategies(), ["alpha", "beta", "gamma"])

    def test_real_bot_file(self):
        s = balance.bot_strategies()
        self.assertIn("mundane", s)
        self.assertEqual(len(s), len(set(s)))


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


# --- 13: run_job ---------------------------------------------------------------------------

def fake_proc(stdout_lines, rc=0, real=4.0, user=2.0, calls=None):
    def run(cmd, stdout=None, stderr=None, **kw):
        if calls is not None:
            calls.append(cmd)
        stdout.write("".join(l + "\n" for l in stdout_lines))
        stderr.write(f"some godot noise\nreal {real:.2f}\nuser {user:.2f}\nsys 0.10\n")
        return mock.Mock(returncode=rc)
    return run


class RunJobTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.job = {"variant": "v", "strategy": "occult", "data": "/x/data_v", "flags": ["--flare=0"]}

    def run_job(self, lines, rc=0, seeds=2, calls=None):
        with mock.patch.object(balance.subprocess, "run", fake_proc(lines, rc, calls=calls)):
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
