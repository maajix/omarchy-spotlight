import io
from types import SimpleNamespace
import unittest
from unittest import mock

from helper_test import HELPER
import system_metrics as metrics


class SystemMetricsTests(unittest.TestCase):
    def test_snapshot_uses_local_counters_and_marks_partial_scans(self):
        stats = SimpleNamespace(f_fsid=7, f_blocks=100, f_bfree=40, f_bavail=35, f_frsize=1024)
        services = {"services": [{"scope": "user", "active": "failed", "name": "example.service"}],
                    "partial": True, "scopes": ["user"]}
        run = mock.Mock(side_effect=lambda argv, *_args, **_kwargs:
                        (b"abcd-1234\n", False, 0) if argv[0] == "findmnt"
                        else (b"1024\t/home/example/Downloads\n4096\t/home/example/.cache\n999\t/incomplete", True, None))
        with mock.patch.object(metrics, "cpu_ticks", side_effect=[(100, 50), (200, 125)]), \
                mock.patch.object(metrics.time, "sleep"), \
                mock.patch.object(metrics, "memory", return_value={"total": 100, "used": 60, "available": 40}), \
                mock.patch.object(metrics.os, "statvfs", side_effect=[stats, SimpleNamespace(**{**vars(stats), "f_fsid": 8})]):
            result = metrics.snapshot("all", run, "/home/example", services)
        self.assertEqual(result["cpu"]["percent"], 25)
        self.assertEqual(result["memory"]["used"], 60)
        self.assertEqual(len(result["disks"]), 1, "Same filesystem must not be duplicated")
        self.assertEqual(result["folders"], [{"name": ".cache", "bytes": 4096}, {"name": "Downloads", "bytes": 1024}])
        self.assertTrue(result["foldersPartial"])
        self.assertEqual(result["services"][0]["failed"], 1)
        self.assertIn("System service status unavailable", result["errors"])
        self.assertEqual(run.call_args.args[1:3], (65536, 3))
        self.assertIn("--no-dereference", run.call_args.args[0])

    def test_unavailable_measurements_are_not_zero(self):
        with mock.patch.object(metrics, "cpu_ticks", side_effect=OSError):
            result = metrics.snapshot("cpu", mock.Mock(), None)
        self.assertIsNone(result["cpu"])
        self.assertIsNone(result["memory"])
        self.assertEqual(result["errors"], ["CPU usage unavailable"])
        with mock.patch("builtins.open", return_value=io.BytesIO(b"MemTotal: 100 kB\nMemAvailable: 120 kB\n")):
            with self.assertRaises(ValueError):
                metrics.memory()
        self.assertEqual(metrics.folder_sizes(b"1\t/etc\n2\t/home/example\n3\t/home/example/bad\x01name\n", "/home/example"), [])

    def test_provider_cannot_supply_local_measurements(self):
        card = HELPER.ARTIFACT_VALIDATORS["dashboard"]({"type": "dashboard", "title": "Local overview", "focus": "cpu", "cpu": {"percent": 99}})
        self.assertNotIn("cpu", card)
        with mock.patch.object(HELPER, "system_snapshot", return_value={"cpu": {"percent": 25}}):
            self.assertEqual(HELPER.local_dashboard(card)["cpu"]["percent"], 25)
        with self.assertRaises(ValueError):
            HELPER.ARTIFACT_VALIDATORS["dashboard"]({"title": "Invalid", "focus": "shell"})
