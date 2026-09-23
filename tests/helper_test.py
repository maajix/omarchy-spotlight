import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import select
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
HELPER_PATH = ROOT / "bin" / "spotlight-helper"
SPEC = importlib.util.spec_from_file_location("spotlight_helper", HELPER_PATH)
if SPEC is None:
    from importlib.machinery import SourceFileLoader

    SPEC = importlib.util.spec_from_loader(
        "spotlight_helper", SourceFileLoader("spotlight_helper", str(HELPER_PATH))
    )
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)


class HelperTests(unittest.TestCase):
    def test_wifi_lists_unique_networks_and_rejects_newlines_in_ssids(self):
        raw = (b':436166653a4775657374:65:WPA2\n:486f6d65:95:WPA2\n'
               b'*:486f6d65:72:WPA2\n:536166650a203a4576696c:99:WPA2\n'
               b':badhex:40:WPA2\n')
        for char in "\x7f\u0085\u009b\u202e\u200b":
            raw += b":" + ("Safe" + char + "Evil").encode().hex().encode() + b":99:WPA2\n"
        safe_name = "Café 中😀\ue000"
        raw += b":" + safe_name.encode().hex().encode() + b":60:WPA2\n"
        with mock.patch.object(HELPER, "run_bounded", return_value=(raw, False, 0)) as run_bounded:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_wifi()
        self.assertIn("IN-USE,SSID-HEX,SIGNAL,SECURITY", run_bounded.call_args.args[0])
        self.assertEqual(json.loads(buf.getvalue())["networks"], [
            {"ssid": "Home", "connected": True, "signal": 72, "security": "WPA2"},
            {"ssid": "Cafe:Guest", "connected": False, "signal": 65, "security": "WPA2"},
            {"ssid": safe_name, "connected": False, "signal": 60, "security": "WPA2"},
        ])
        self.assertEqual(HELPER._nmcli_fields(r":Cafe\\Guest:50:--"),
                         ["", r"Cafe\Guest", "50", "--"])

    def test_wifi_keeps_complete_lines_and_bluetooth_rejects_truncated_json(self):
        with mock.patch.object(HELPER, "run_bounded",
                               return_value=(b":486f6d65:95:WPA2\n:Caf", True, -9)):
            reply = run(HELPER.cmd_wifi)
        self.assertEqual([n["ssid"] for n in reply["networks"]], ["Home"])
        self.assertTrue(reply["partial"])
        with mock.patch.object(HELPER, "run_bounded", return_value=(b'{"data":', True, -9)):
            with self.assertRaises(HELPER.Denied):
                HELPER.cmd_bluetooth()

    def test_bluetooth_lists_paired_devices_and_connection_state(self):
        def device(address, name, paired=True, connected=False):
            return {"org.bluez.Device1": {
                "Address": {"type": "s", "data": address},
                "Alias": {"type": "s", "data": name},
                "Paired": {"type": "b", "data": paired},
                "Connected": {"type": "b", "data": connected}}}

        objects = {
            "/org/bluez/hci0/dev_38_18_4C_24_30_3E": device(
                "38:18:4C:24:30:3E", "Headphones", connected=True),
            "/org/bluez/hci0/dev_00_11_22_33_44_55": device(
                "00:11:22:33:44:55", "Keyboard"),
            "/org/bluez/hci0/dev_AA_BB_CC_DD_EE_FF": device(
                "AA:BB:CC:DD:EE:FF", "Safe\nDevice 66:77:88:99:AA:BB Evil"),
            "/org/bluez/hci0/dev_66_77_88_99_AA_BB": device(
                "66:77:88:99:AA:BB", "Not paired", paired=False),
            "/org/bluez/hci0/dev_11_22_33_44_55_66": device(
                "11:22:33:44:55:66", "Zébra 中😀\ue000"),
        }
        for index, char in enumerate("\x7f\u0085\u009b\u202e\u200b"):
            address = "AA:BB:CC:DD:EE:%02X" % index
            objects["/org/bluez/hci0/dev_" + address.replace(":", "_")] = device(
                address, "Safe" + char + "Evil")
        raw = json.dumps({"type": "a{oa{sa{sv}}}", "data": [objects]}).encode()
        with mock.patch.object(HELPER, "run_bounded", return_value=(raw, False, 0)) as run_bounded:
            reply = run(HELPER.cmd_bluetooth)
        self.assertEqual(run_bounded.call_args.args[0][:3],
                         ["busctl", "--json=short", "call"])
        self.assertEqual(reply["devices"], [
            {"address": "38:18:4C:24:30:3E", "name": "Headphones", "connected": True},
            {"address": "00:11:22:33:44:55", "name": "Keyboard", "connected": False},
            {"address": "11:22:33:44:55:66", "name": "Zébra 中😀\ue000", "connected": False},
        ])

    def test_terminal_log_wrapper_keeps_output_after_interrupt(self):
        literal = "device name; $(echo unchanged)"
        child = 'printf "%s\\n" "$1"; exec sleep 30'
        proc = subprocess.Popen(
            ["bash", str(ROOT / "bin" / "spotlight-hold.bash"),
             "bash", "-c", child, "child", literal],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            bufsize=0, start_new_session=True,
            # A terminal starts the wrapper with SIGINT at its default; a
            # background test runner may have it ignored, which bash keeps.
            preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
        try:
            # The wrapper sets its trap before starting the child, so once the
            # child has printed, the interrupt can only reach the child.
            read_until(proc, literal.encode())
            os.killpg(proc.pid, signal.SIGINT)
            read_until(proc, b"Process exited (130). Press Enter to close.")
            # The prompt is followed by a blocking read on stdin.
            self.assertIsNone(proc.poll())
            proc.stdin.write(b"\n")
            _, errors = proc.communicate(timeout=3)
            self.assertEqual(proc.returncode, 130)
            self.assertEqual(errors, b"")
        finally:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait(timeout=3)

    def test_terminal_wrapper_hold_if_holds_only_on_that_status(self):
        wrapper = str(ROOT / "bin" / "spotlight-hold.bash")

        def wrap(status, stdin=b""):
            return subprocess.run(
                ["bash", wrapper, "--hold-if", "255", "bash", "-c", "exit %d" % status],
                input=stdin, capture_output=True, timeout=5)

        # No input is available, so a wrongly held prompt would show in stdout.
        for status in (0, 3):
            done = wrap(status)
            self.assertEqual((done.returncode, done.stdout), (status, b""))
        held = wrap(255, b"\n")
        self.assertEqual(held.returncode, 255)
        self.assertIn(b"Process exited (255). Press Enter to close.", held.stdout)
        # A missing ssh (127) must not flash the terminal shut either.
        missing = subprocess.run(
            ["bash", wrapper, "--hold-if", "255", "spotlight-no-such-command"],
            input=b"\n", capture_output=True, timeout=5)
        self.assertEqual(missing.returncode, 127)
        self.assertIn(b"Process exited (127). Press Enter to close.", missing.stdout)

    def test_audio_lists_defaults_and_excludes_monitor_sources(self):
        info = {"default_sink_name": "speaker", "default_source_name": "mic"}
        sinks = [{"name": "speaker", "description": "USB Headphones", "mute": False,
                  "volume": {"left": {"value_percent": "40%"}},
                  "properties": {"object.id": "59"}}]
        sources = [
            {"name": "speaker.monitor", "description": "Monitor of USB Headphones"},
            {"name": "mic", "description": "USB Microphone", "mute": True,
             "volume": {"mono": {"value_percent": "75%"}},
             "properties": {"object.id": "5 --x"}},
        ]
        replies = [(json.dumps(item).encode(), False, 0) for item in (info, sinks, sources)]
        with mock.patch.object(HELPER, "run_bounded", side_effect=replies) as run:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_audio()
        self.assertEqual(run.call_count, 3)
        devices = json.loads(buf.getvalue())["devices"]
        self.assertEqual([(d["kind"], d["name"], d["default"]) for d in devices],
                         [("output", "speaker", True), ("input", "mic", True)])
        self.assertEqual(devices[0]["volume"], "40%")
        self.assertTrue(devices[1]["muted"])
        self.assertEqual([d["id"] for d in devices], ["59", ""])
        with mock.patch.object(HELPER, "run_bounded", return_value=(b"", False, 1)):
            with self.assertRaises(HELPER.Denied):
                HELPER.cmd_audio()

    def test_audio_caps_after_sorting_so_the_default_survives(self):
        info = {"default_sink_name": "default-sink", "default_source_name": ""}
        sinks = [{"name": "sink-%03d" % i, "description": "Sink %03d" % i}
                 for i in range(HELPER.AUDIO_COUNT)]
        sinks.append({"name": "default-sink", "description": "Zulu speakers"})
        replies = [(json.dumps(item).encode(), False, 0) for item in (info, sinks, [])]
        with mock.patch.object(HELPER, "run_bounded", side_effect=replies):
            reply = run(HELPER.cmd_audio)
        self.assertEqual(len(reply["devices"]), HELPER.AUDIO_COUNT)
        self.assertEqual(reply["devices"][0]["name"], "default-sink")
        self.assertTrue(reply["partial"])

    def test_mounts_keep_the_visible_mount_per_target_and_flag_the_cap(self):
        stacked = json.dumps({"filesystems": [
            {"target": "/mnt/x", "source": "/dev/sda1", "fstype": "ext4"},
            {"target": "/mnt/x", "source": "/dev/sdb1", "fstype": "xfs"},
        ]}).encode()
        with mock.patch.object(HELPER, "run_bounded", return_value=(stacked, False, 0)):
            reply = run(HELPER.cmd_mounts)
        self.assertEqual(reply["mounts"],
                         [{"target": "/mnt/x", "source": "/dev/sdb1", "fstype": "xfs"}])
        self.assertFalse(reply["partial"])
        many = json.dumps({"filesystems": [
            {"target": "/mnt/%d" % i, "source": "/dev/x", "fstype": "ext4"}
            for i in range(HELPER.MOUNTS_COUNT + 1)]}).encode()
        with mock.patch.object(HELPER, "run_bounded", return_value=(many, False, 0)):
            reply = run(HELPER.cmd_mounts)
        self.assertEqual(len(reply["mounts"]), HELPER.MOUNTS_COUNT)
        self.assertTrue(reply["partial"])

    def test_mounts_project_real_filesystems_and_handle_failure(self):
        raw = json.dumps({"filesystems": [
            {"target": "/mnt/games", "source": "/dev/sdb1", "fstype": "ext4", "use%": "7%"},
            {"target": "relative", "source": "/dev/sdc1", "fstype": "xfs"},
        ]}).encode()
        with mock.patch.object(HELPER, "run_bounded", return_value=(raw, False, 0)) as run:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_mounts()
        run.assert_called_once_with(
            ["findmnt", "--json", "--list", "--real", "--nocanonicalize",
             "--output", "TARGET,SOURCE,FSTYPE"],
            HELPER.MOUNTS_BYTES, HELPER.MOUNTS_DEADLINE, want_status=True)
        self.assertEqual(json.loads(buf.getvalue())["mounts"], [
            {"target": "/mnt/games", "source": "/dev/sdb1", "fstype": "ext4"}])
        with mock.patch.object(HELPER, "run_bounded", return_value=(b"", False, 1)):
            with self.assertRaises(HELPER.Denied):
                HELPER.cmd_mounts()

    def test_services_project_user_and_system_units(self):
        user = b'app.service loaded active running User app service\n'
        system = ('\u00d7 failed.service loaded failed failed A failed service\n'
                  'sshd.service loaded active running OpenSSH server\n').encode()
        with mock.patch.object(HELPER, "run_bounded", side_effect=[
                (user, False, 0), (system, False, 0)]) as run:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_services()
        self.assertEqual(run.call_count, 2)
        rows = json.loads(buf.getvalue())["services"]
        self.assertEqual([(r["scope"], r["name"], r["active"]) for r in rows], [
            ("system", "failed.service", "failed"),
            ("user", "app.service", "active"),
            ("system", "sshd.service", "active"),
        ])
        self.assertEqual(rows[0]["description"], "A failed service")
        self.assertFalse(json.loads(buf.getvalue())["partial"])
        with mock.patch.object(HELPER, "run_bounded", return_value=(b"", False, 1)):
            with self.assertRaises(HELPER.Denied):
                HELPER.cmd_services()

    def test_services_sort_before_cap_and_show_partial_output(self):
        user = (b'app.service loaded active running App\n' * 220)
        system = b'failed.service loaded failed failed Broken\ncut-off.service loaded'
        with mock.patch.object(HELPER, "run_bounded", side_effect=[
                (user, False, 0), (system, True, -15)]):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_services()
        reply = json.loads(buf.getvalue())
        self.assertEqual(len(reply["services"]), HELPER.SERVICES_COUNT)
        self.assertEqual(reply["services"][0]["name"], "failed.service")
        self.assertTrue(reply["partial"])
        # Complete output with more units than the cap is partial too.
        with mock.patch.object(HELPER, "run_bounded", side_effect=[
                (user, False, 0), (b"", False, 0)]):
            reply = run(HELPER.cmd_services)
        self.assertEqual(len(reply["services"]), HELPER.SERVICES_COUNT)
        self.assertTrue(reply["partial"])

    def test_docker_projects_containers_and_handles_daemon_failure(self):
        running = {"ID": "a" * 64, "Names": "api", "Image": "node:22",
                   "State": "running", "Status": "Up 2 hours", "Ports": "127.0.0.1:3000->3000/tcp"}
        stopped = {"ID": "b" * 64, "Names": "db", "Image": "postgres:17",
                   "State": "exited", "Status": "Exited (0) 1 hour ago", "Ports": ""}
        raw = (json.dumps(stopped) + "\n" + json.dumps(running) + "\n").encode()
        with mock.patch.object(HELPER, "run_bounded", return_value=(raw, False, 0)) as run:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_docker()
        run.assert_called_once_with(
            ["docker", "container", "ls", "--all", "--last", str(HELPER.DOCKER_COUNT + 1),
             "--no-trunc", "--size=false", "--format", "{{json .}}"],
            HELPER.DOCKER_BYTES, HELPER.DOCKER_DEADLINE, want_status=True)
        containers = json.loads(buf.getvalue())["containers"]
        self.assertEqual([c["name"] for c in containers], ["api", "db"])
        self.assertEqual(containers[0]["ports"], "127.0.0.1:3000->3000/tcp")
        with mock.patch.object(HELPER, "run_bounded", return_value=(b"", False, 1)):
            with self.assertRaises(HELPER.Denied):
                HELPER.cmd_docker()

    def test_docker_keeps_complete_rows_at_byte_cap_and_reads_podman_fields(self):
        podman = {"Id": "c" * 64, "Names": ["worker"], "Image": "busybox",
                  "State": "running", "Status": "Up", "Ports": []}
        raw = (json.dumps(podman) + "\n{" + '"Id":"partial"').encode()
        with mock.patch.object(HELPER, "run_bounded", return_value=(raw, True, -15)):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_docker()
        reply = json.loads(buf.getvalue())
        self.assertEqual(reply["containers"][0]["name"], "worker")
        self.assertTrue(reply["partial"])

    def test_docker_caps_after_sorting_and_flags_the_extra_container(self):
        stopped = [{"ID": "%064x" % i, "Names": "c%03d" % i, "Image": "img",
                    "State": "exited", "Status": "Exited", "Ports": ""}
                   for i in range(HELPER.DOCKER_COUNT)]
        running = {"ID": "f" * 64, "Names": "zz-running", "Image": "img",
                   "State": "running", "Status": "Up", "Ports": ""}
        raw = "".join(json.dumps(row) + "\n" for row in stopped + [running]).encode()
        with mock.patch.object(HELPER, "run_bounded", return_value=(raw, False, 0)):
            reply = run(HELPER.cmd_docker)
        self.assertEqual(len(reply["containers"]), HELPER.DOCKER_COUNT)
        self.assertEqual(reply["containers"][0]["name"], "zz-running")
        self.assertTrue(reply["partial"])

    def test_ssh_hosts_from_config_and_includes(self):
        with tempfile.TemporaryDirectory() as home:
            ssh = Path(home) / ".ssh"
            (ssh / "config.d").mkdir(parents=True)
            (ssh / "extra").mkdir()
            (ssh / "config").write_text(
                'Include config.d/*.conf\nHost work prod *.internal !blocked\n'
                'Host=work\nMatch all\nInclude ignored.conf\nHost after-match\n'
                'Host *\nInclude extra/always.conf\n'
            )
            (ssh / "config.d" / "hosts.conf").write_text('Host "lab" staging # comment\n')
            (ssh / "extra" / "always.conf").write_text('Host universal\n')
            (ssh / "ignored.conf").write_text('Host ignored\n')
            (ssh / "known_hosts").write_text(
                'work,legacy ssh-ed25519 AAAA\n'
                '|1|hashed|host ssh-ed25519 AAAA\n'
                '@cert-authority *.example.com ssh-ed25519 AAAA\n'
            )
            with mock.patch.dict(os.environ, {"HOME": home}):
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    HELPER.cmd_ssh_hosts()
        self.assertEqual(json.loads(buf.getvalue())["hosts"], [
            {"name": host, "source": "config"}
            for host in ("lab", "staging", "work", "prod", "after-match", "universal")
        ] + [{"name": "legacy", "source": "known_hosts"}])
        self.assertFalse(json.loads(buf.getvalue())["partial"])

    def test_ssh_flags_a_refused_known_hosts_and_the_host_cap(self):
        with tempfile.TemporaryDirectory() as home:
            ssh = Path(home) / ".ssh"
            ssh.mkdir()
            (ssh / "config").write_text("Host saved\n")
            (ssh / "known_hosts").write_bytes(b"x" * (HELPER.SSH_KNOWN_BYTES + 1))
            with mock.patch.dict(os.environ, {"HOME": home}):
                reply = run(HELPER.cmd_ssh_hosts)
            self.assertEqual(reply["hosts"], [{"name": "saved", "source": "config"}])
            self.assertTrue(reply["partial"])
            (ssh / "known_hosts").write_text("".join(
                "h%03d ssh-ed25519 AAAA\n" % i for i in range(HELPER.SSH_HOSTS)))
            with mock.patch.dict(os.environ, {"HOME": home}):
                reply = run(HELPER.cmd_ssh_hosts)
        self.assertEqual(len(reply["hosts"]), HELPER.SSH_HOSTS)
        self.assertEqual(reply["hosts"][0]["name"], "saved")
        self.assertTrue(reply["partial"])

    def test_ssh_include_globs_scan_a_sorted_bounded_set(self):
        with tempfile.TemporaryDirectory() as home:
            ssh = Path(home) / ".ssh"
            (ssh / "config.d").mkdir(parents=True)
            (ssh / "config").write_text("Include config.d/*.conf\n")
            # Created in reverse so directory order is unlikely to be sorted.
            for i in reversed(range(40)):
                (ssh / "config.d" / ("h%02d.conf" % i)).write_text("Host h%02d\n" % i)
            with mock.patch.dict(os.environ, {"HOME": home}):
                reply = run(HELPER.cmd_ssh_hosts)
        # The main config counts toward SSH_FILES, leaving room for 31 includes.
        self.assertEqual([h["name"] for h in reply["hosts"]],
                         ["h%02d" % i for i in range(HELPER.SSH_FILES - 1)])
        self.assertTrue(reply["partial"])

    def test_ssh_known_hosts_without_config_or_agent(self):
        with tempfile.TemporaryDirectory() as home:
            ssh = Path(home) / ".ssh"
            ssh.mkdir()
            (ssh / "known_hosts").write_text('example.org ssh-ed25519 AAAA\n')
            with mock.patch.dict(os.environ, {"HOME": home}, clear=True):
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    HELPER.cmd_ssh_hosts()
        self.assertEqual(json.loads(buf.getvalue()),
                         {"ok": True, "partial": False,
                          "hosts": [{"name": "example.org", "source": "known_hosts"}]})

    def test_ssh_without_an_ssh_directory_is_empty_not_partial(self):
        with tempfile.TemporaryDirectory() as home:
            with mock.patch.dict(os.environ, {"HOME": home}):
                reply = run(HELPER.cmd_ssh_hosts)
        self.assertEqual(reply, {"ok": True, "partial": False, "hosts": []})

    def test_ports_parse_listeners_and_bound_output(self):
        lines = (b'tcp LISTEN 0 4096 127.0.0.1:5173 0.0.0.0:* users:(("node",pid=18472,fd=22))\n'
                 b'tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=842,fd=3))\n'
                 b'tcp LISTEN 0 128 [::1]:631 [::]:* users:(("cupsd",pid=1104,fd=4))\n'
                 b'tcp LISTEN 0 128 127.0.0.53%lo:53 0.0.0.0:*\n'
                 b'udp UNCONN 0 0 [fe80::1c2]%wlan0:546 [::]:*\n'
                 b'tcp LISTEN 0 128 [fe80::5]%eno1:8080 [::]:*\n'
                 b'udp UNCONN 0 0 [::]:5353 [::]:*\n'
                 b'udp UNCONN 0 0 [::]:5353 [::]:*\n'
                 b'broken line\n')
        with mock.patch.object(HELPER, "run_bounded", return_value=(lines, False, 0)) as run:
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_ports()
        run.assert_called_once_with(["ss", "-H", "-lntup"], HELPER.PORTS_BYTES,
                                    HELPER.PORTS_DEADLINE, want_status=True)
        ports = json.loads(buf.getvalue())["ports"]
        self.assertEqual([p["port"] for p in ports], [22, 53, 546, 631, 5173, 5353, 8080])
        self.assertEqual(ports[0]["url"], "http://localhost:22")
        self.assertEqual(ports[1]["endpoint"], "127.0.0.53%lo:53")
        self.assertEqual(ports[1]["url"], "http://127.0.0.53:53")
        self.assertEqual((ports[2]["endpoint"], ports[2]["url"]), ("[fe80::1c2%wlan0]:546", ""))
        self.assertEqual(ports[3]["url"], "http://[::1]:631")
        self.assertEqual(ports[4]["process"], "node")
        self.assertEqual(ports[5]["endpoint"], "[::]:5353")
        self.assertEqual(ports[5]["url"], "")
        self.assertIsNone(ports[5]["pid"])
        self.assertEqual(ports[6]["url"], "http://[fe80::5%25eno1]:8080")

    def test_ports_limit_and_probe_failure(self):
        lines = b"".join(
            f'tcp LISTEN 0 128 127.0.0.1:{port} 0.0.0.0:*\n'.encode()
            for port in range(3000, 3300))
        lines += b'tcp LISTEN 0 128 0.0.0.0:22 0.0.0.0:*\n'
        with mock.patch.object(HELPER, "run_bounded",
                               return_value=(lines, False, 0)):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_ports()
            result = json.loads(buf.getvalue())
            self.assertEqual(len(result["ports"]), HELPER.PORTS_COUNT)
            self.assertEqual(result["ports"][0]["port"], 22)
            self.assertTrue(result["partial"])
        with mock.patch.object(HELPER, "run_bounded",
                               return_value=(b'tcp LISTEN 0 128 127.0.0.1:53 0.0.0.0:*\npartial', True, -15)):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_ports()
            result = json.loads(buf.getvalue())
            self.assertEqual(result["ports"][0]["port"], 53)
            self.assertTrue(result["partial"])
        with mock.patch.object(HELPER, "run_bounded", return_value=(b"", False, 1)):
            with self.assertRaises(HELPER.Denied):
                HELPER.cmd_ports()

    def test_settings_are_private_by_default_and_bounded(self):
        defaults = HELPER.normalize_settings({})
        self.assertFalse(defaults["webSuggestions"])
        self.assertTrue(defaults["currencyRates"])
        self.assertTrue(defaults["fileSearchAlways"])
        self.assertTrue(defaults["clipboardSearch"])
        self.assertTrue(defaults["clipboardSearchAlways"])
        self.assertTrue(defaults["learningEnabled"])
        self.assertEqual(defaults["maxResults"], 20)

        settings = HELPER.normalize_settings({
            "webSuggestions": "yes",
            "currencyRates": False,
            "maxApps": 999,
            "maxSuggestions": -5,
            "maxResults": 999,
            "learningEnabled": False,
            "searchEngine": "invalid-value",
        })
        self.assertFalse(settings["webSuggestions"])
        self.assertFalse(settings["currencyRates"])
        self.assertEqual(settings["maxApps"], 24)
        self.assertEqual(settings["maxSuggestions"], 0)
        self.assertEqual(settings["maxResults"], 50)
        self.assertFalse(settings["learningEnabled"])
        self.assertEqual(settings["searchEngine"], "g")

    def test_file_reader_rejects_symlinks_and_oversized_files(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / "target").write_bytes(b"secret")
            (base / "link").symlink_to("target")
            (base / "large").write_bytes(b"x" * 9)
            fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                with self.assertRaises(HELPER.Denied):
                    HELPER.read_file(fd, "link", 64)
                with self.assertRaises(HELPER.Denied):
                    HELPER.read_file(fd, "large", 8)
            finally:
                os.close(fd)

    def _run_cmd_files(self, lines_bytes):
        original = HELPER.run_bounded
        HELPER.run_bounded = lambda argv, cap, deadline: (lines_bytes, False)
        try:
            with tempfile.TemporaryDirectory() as directory:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    HELPER.cmd_files([directory, "Downloads"])
        finally:
            HELPER.run_bounded = original
        return buf.getvalue()

    def _assert_payload_fits_qml(self, payload):
        # Spotlight.qml checks `text.length` - JS counts UTF-16 code units,
        # not code points, so a character outside the BMP counts twice
        # there and once under Python's len(). This is the metric that
        # actually has to stay under maxHelperPayloadChars (524288); a
        # Python-len() check alone would pass on exactly the inputs that
        # break it.
        utf16_units = len(payload.encode("utf-16-le")) // 2
        self.assertLess(utf16_units, 524288)
        parsed = json.loads(payload)
        self.assertTrue(parsed["ok"])
        self.assertGreater(len(parsed["files"]), 0)
        return parsed

    def test_files_json_stays_under_the_qml_payload_ceiling_on_long_paths(self):
        # Each row repeats its path across path/name/dir, so a pool of long
        # real-world paths can clear that ceiling well before FILES_COUNT
        # does - this is what used to make loadFiles silently fall back to
        # an empty list.
        long_lines = "\n".join(
            "/home/user/" + "x" * 580 + "-Downloads-%04d" % i for i in range(400)
        ).encode("utf-8") + b"\n"
        parsed = self._assert_payload_fits_qml(self._run_cmd_files(long_lines))
        self.assertLess(len(parsed["files"]), 400)

    def test_files_json_stays_under_the_qml_payload_ceiling_with_json_escapes(self):
        # Control characters are legal in a Linux filename and cmd_files
        # does not reject them, but each one expands to a 6-char \\uXXXX
        # escape in JSON regardless of ensure_ascii - a budget estimated
        # from raw string length, rather than the real serialized size,
        # undercounts this by up to 6x and can still overflow the ceiling.
        control_component = ("a\x01" * 100)
        line = (
            "/home/user/" + "/".join([control_component] * 3) + "/Downloads%04d"
        )
        long_lines = "\n".join(line % i for i in range(400)).encode("utf-8") + b"\n"
        self._assert_payload_fits_qml(self._run_cmd_files(long_lines))

    def test_files_json_stays_under_the_qml_payload_ceiling_with_non_bmp_paths(self):
        # Non-BMP characters (outside U+0000-U+FFFF, e.g. most emoji) are
        # exactly the case where Python len() and JS String.length diverge -
        # this is what the 2x margin in FILES_JSON_BUDGET_CHARS is for. The
        # component is sized close to FILES_PATH_CHARS so the *budget* is
        # what stops row-building here, not FILES_COUNT - a short component
        # would let all 400 rows through under either cutoff and never
        # actually exercise the margin this test exists to protect.
        emoji_component = "\U0001F600" * 450  # U+1F600, outside the BMP
        line = "/home/user/" + emoji_component + "/Downloads%04d"
        long_lines = "\n".join(line % i for i in range(400)).encode("utf-8") + b"\n"
        parsed = self._assert_payload_fits_qml(self._run_cmd_files(long_lines))
        self.assertLess(len(parsed["files"]), 400)

    def test_files_truncated_output_drops_the_last_line(self):
        original = HELPER.run_bounded
        # A path that would otherwise parse as a perfectly normal hit - the
        # point is that `truncated=True` alone is enough to drop it, since a
        # cut mid-path is indistinguishable from a clean one from here.
        HELPER.run_bounded = lambda argv, cap, deadline: (
            b"/home/user/real-hit\n/home/user/maybe-cut-off",
            True,
        )
        try:
            with tempfile.TemporaryDirectory() as directory:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    HELPER.cmd_files([directory, "hit"])
        finally:
            HELPER.run_bounded = original

        parsed = json.loads(buf.getvalue())
        paths = [f["path"] for f in parsed["files"]]
        self.assertIn("/home/user/real-hit", paths)
        self.assertNotIn("/home/user/maybe-cut-off", paths)

    def test_file_results_carry_sha256_path_fingerprints(self):
        parsed = json.loads(self._run_cmd_files(b"/home/user/report.txt\n"))
        self.assertEqual(
            parsed["files"][0]["id"],
            hashlib.sha256(b"/home/user/report.txt").hexdigest(),
        )

    def test_deadline_reaps_the_process_group(self):
        with tempfile.TemporaryDirectory() as directory:
            pid_file = Path(directory) / "child.pid"
            code = (
                "import os,subprocess,sys,time; "
                "child=subprocess.Popen(['sleep','60']); "
                "open(sys.argv[1],'w').write(str(child.pid)); "
                "print('ready',flush=True); time.sleep(60)"
            )
            output, truncated = HELPER.run_bounded(
                [sys.executable, "-c", code, str(pid_file)], 1024, 0.2
            )
            self.assertTrue(truncated)
            self.assertIn(b"ready", output)
            child_pid = int(pid_file.read_text())
            for _ in range(50):
                if not Path("/proc") .joinpath(str(child_pid)).exists():
                    break
                time.sleep(0.02)
            self.assertFalse(Path("/proc").joinpath(str(child_pid)).exists())

    def test_clean_home_reads_stock_defaults_and_empty_clipboard(self):
        with tempfile.TemporaryDirectory() as directory:
            old_home = os.environ.get("HOME")
            os.environ["HOME"] = directory
            try:
                for command, key in ((HELPER.cmd_read_settings, "settings"),
                                     (HELPER.cmd_read_clipboard, "items")):
                    buf = io.StringIO()
                    with contextlib.redirect_stdout(buf):
                        command()
                    reply = json.loads(buf.getvalue())
                    self.assertTrue(reply["ok"])
                    self.assertTrue(reply[key] == [] if key == "items" else reply[key]["fileSearchAlways"])
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home

    def test_unavailable_web_suggestions_return_an_empty_result(self):
        buf = io.StringIO()
        with mock.patch("urllib.request.build_opener", side_effect=OSError("offline")):
            with contextlib.redirect_stdout(buf):
                HELPER.cmd_suggest(["firefox"])
        self.assertEqual(json.loads(buf.getvalue())["suggestions"], [])

    def test_suggestions_route_to_a_fixed_provider(self):
        for args, endpoint in (
            (["c++ & café", "kagi"], "https://kagi.com/api/autosuggest?q="),
            (["c++ & café"], "https://suggestqueries.google.com/complete/search?client=firefox&hl=en&q="),
        ):
            with self.subTest(args=args):
                opener = mock.MagicMock()
                opener.open.return_value.__enter__.return_value.read.return_value = json.dumps([args[0], ["first"]]).encode()
                buf = io.StringIO()
                with mock.patch("urllib.request.build_opener", return_value=opener):
                    with contextlib.redirect_stdout(buf):
                        HELPER.cmd_suggest(args)
                self.assertEqual(opener.open.call_args.args[0].full_url, endpoint + "c%2B%2B%20%26%20caf%C3%A9")
                self.assertEqual(json.loads(buf.getvalue())["suggestions"], ["first"])
        for args in ([], ["q", "kagi", "extra"], ["q", "Kagi"], ["q", "https://example.com"],
                     ["q", ""], ["q", "abcdefghi"], ["q", "kagi\n"]):
            with self.subTest(args=args):
                with self.assertRaises(HELPER.Denied):
                    HELPER.cmd_suggest(args)

    def test_suggestion_failures_do_not_fall_back_to_another_provider(self):
        from urllib.error import URLError
        for raw, error in ((b"not json", None), (None, URLError("boom"))):
            with self.subTest(raw=raw, error=error):
                opener = mock.MagicMock()
                opener.open.side_effect = error
                opener.open.return_value.__enter__.return_value.read.return_value = raw
                buf = io.StringIO()
                with mock.patch("urllib.request.build_opener", return_value=opener):
                    with contextlib.redirect_stdout(buf):
                        HELPER.cmd_suggest(["query", "kagi"])
                self.assertEqual(json.loads(buf.getvalue())["suggestions"], [])
                opener.open.assert_called_once()

    def test_suggestions_decode_declared_charset_and_handle_truncated_http(self):
        from email.message import Message
        from http.client import IncompleteRead

        headers = Message()
        headers["Content-Type"] = "text/javascript; charset=ISO-8859-1"
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.headers = headers
        response.read.return_value = '["café", ["café au lait"]]'.encode("iso-8859-1")
        opener = mock.Mock()
        opener.open.return_value = response
        with mock.patch("urllib.request.build_opener", return_value=opener):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                HELPER.cmd_suggest(["café"])
        self.assertEqual(json.loads(out.getvalue())["suggestions"], ["café au lait"])

        response.read.side_effect = IncompleteRead(b"partial")
        with mock.patch("urllib.request.build_opener", return_value=opener):
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                HELPER.cmd_suggest(["café"])
        self.assertEqual(json.loads(out.getvalue())["suggestions"], [])

    def test_settings_creation_is_private_and_never_overwrites(self):
        with tempfile.TemporaryDirectory() as directory:
            old_home = os.environ.get("HOME")
            os.environ["HOME"] = directory
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    HELPER.cmd_ensure_settings()
                settings = Path(directory) / ".config" / "omarchy" / "spotlight.json"
                self.assertEqual(stat.S_IMODE(settings.stat().st_mode), 0o600)
                parsed = json.loads(settings.read_text())
                self.assertEqual(parsed["maxResults"], 20)
                settings.write_text('{"custom":true}\n')
                with contextlib.redirect_stdout(io.StringIO()):
                    HELPER.cmd_ensure_settings()
                self.assertEqual(settings.read_text(), '{"custom":true}\n')
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home

    def test_reset_deletes_only_spotlight_usage(self):
        with tempfile.TemporaryDirectory() as directory:
            old_home = os.environ.get("HOME")
            os.environ["HOME"] = directory
            try:
                state = Path(directory) / ".local" / "state" / "omarchy"
                state.mkdir(parents=True)
                usage = state / "spotlight-usage.json"
                other = state / "clipboard-history.json"
                usage.write_text("{}")
                other.write_text("[]")
                with contextlib.redirect_stdout(io.StringIO()):
                    HELPER.cmd_reset_usage()
                self.assertFalse(usage.exists())
                self.assertTrue(other.exists())
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home

    def test_v1_usage_migrates_to_versioned_v2_ids(self):
        usage = HELPER.normalize_usage({
            "app:firefox": {"count": 2, "last": 10},
            "cmd:theme.pick": {"count": 3, "last": 20},
            "bang.gh": {"count": 4, "last": 30},
        })
        self.assertEqual(usage["version"], 2)
        self.assertEqual(usage["items"]["app:firefox"]["count"], 2)
        self.assertEqual(usage["items"]["action:theme.pick"]["count"], 3)
        self.assertNotIn("bang.gh", usage["items"])
        self.assertEqual(usage["contexts"], {})

    def test_path_fingerprints_are_stable_and_file_metadata_is_verified(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "report.txt"
            path.write_text("report")
            fingerprint = HELPER.path_fingerprint(str(path))
            self.assertEqual(fingerprint, HELPER.path_fingerprint(str(path)))
            self.assertEqual(fingerprint, hashlib.sha256(str(path).encode()).hexdigest())
            self.assertEqual(len(fingerprint), 64)

            usage = HELPER.normalize_usage({
                "version": 2,
                "items": {
                    "file:" + fingerprint: {
                        "count": 1, "last": 1, "meta": {"path": str(path)}
                    },
                    "file:" + "0" * 64: {
                        "count": 1, "last": 1, "meta": {"path": str(path)}
                    },
                },
                "contexts": {},
            })
            self.assertIn("file:" + fingerprint, usage["items"])
            self.assertNotIn("file:" + "0" * 64, usage["items"])

    def test_v2_usage_enforces_all_count_and_byte_limits(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            items = {
                "app:%d" % i: {"count": 1, "last": i}
                for i in range(320)
            }
            file_ids = []
            for i in range(105):
                path = base / ("file-%03d" % i)
                path.touch()
                item_id = "file:" + HELPER.path_fingerprint(str(path))
                file_ids.append(item_id)
                items[item_id] = {
                    "count": 1, "last": i, "meta": {"path": str(path)}
                }
            contexts = {}
            for i in range(140):
                contexts["query:q%d" % i] = {
                    "app:%d" % hit: {"count": 1, "last": i}
                    for hit in range(10)
                }

            usage = HELPER.normalize_usage({
                "version": 2, "items": items, "contexts": contexts
            })
            self.assertLessEqual(len(usage["items"]), 400)
            self.assertLessEqual(
                sum(item_id.startswith("file:") for item_id in usage["items"]), 100
            )
            self.assertLessEqual(len(usage["contexts"]), 128)
            self.assertTrue(all(len(hits) <= 8 for hits in usage["contexts"].values()))
            payload = json.dumps(usage, ensure_ascii=False, separators=(",", ":")).encode()
            self.assertLessEqual(len(payload), HELPER.USAGE_JSON_BUDGET_BYTES)

    def test_missing_usage_file_returns_an_empty_v2_store(self):
        with tempfile.TemporaryDirectory() as directory:
            old_home = os.environ.get("HOME")
            os.environ["HOME"] = directory
            try:
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    HELPER.cmd_read_usage()
                usage = json.loads(buf.getvalue())["usage"]
                self.assertEqual(usage, {"version": 2, "items": {}, "contexts": {}})
                self.assertFalse(
                    (Path(directory) / ".local" / "state" / "omarchy" / "spotlight-usage.json").exists()
                )
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home

    def test_read_usage_persists_v1_migration(self):
        with tempfile.TemporaryDirectory() as directory:
            old_home = os.environ.get("HOME")
            os.environ["HOME"] = directory
            try:
                state = Path(directory) / ".local" / "state" / "omarchy"
                state.mkdir(parents=True)
                path = state / "spotlight-usage.json"
                path.write_text(json.dumps({"app:firefox": {"count": 2, "last": 10}}))
                with contextlib.redirect_stdout(io.StringIO()):
                    HELPER.cmd_read_usage()
                persisted = json.loads(path.read_text())
                self.assertEqual(persisted["version"], 2)
                self.assertEqual(persisted["items"]["app:firefox"]["count"], 2)
            finally:
                if old_home is None:
                    os.environ.pop("HOME", None)
                else:
                    os.environ["HOME"] = old_home


@contextlib.contextmanager
def fake_home():
    """A throwaway $HOME; restores the real one even when the test fails."""
    old = os.environ.get("HOME")
    home = tempfile.mkdtemp()
    os.environ["HOME"] = home
    try:
        yield Path(home)
    finally:
        os.environ["HOME"] = old
        shutil.rmtree(home, ignore_errors=True)


def run(handler, argv=None, stdin=b""):
    """Run a helper command, feed it `stdin`, return its parsed JSON reply."""
    buf = io.StringIO()
    with mock.patch("sys.stdin", io.TextIOWrapper(io.BytesIO(stdin))):
        with contextlib.redirect_stdout(buf):
            handler(argv) if argv is not None else handler()
    return json.loads(buf.getvalue())


def read_until(proc, marker, timeout=5):
    """Read an unbuffered stdout pipe until `marker` arrives; no fixed sleeps."""
    data = b""
    fd = proc.stdout.fileno()
    end = time.monotonic() + timeout
    while marker not in data:
        remaining = end - time.monotonic()
        if remaining <= 0:
            raise AssertionError("timed out waiting for %r; got %r" % (marker, data))
        if select.select([fd], [], [], remaining)[0]:
            chunk = os.read(fd, 4096)
            if not chunk:
                raise AssertionError("output ended before %r; got %r" % (marker, data))
            data += chunk
    return data


PRINT_FIXTURE = (
    "SUPER + SPACE                       \u2192 Omarchy menu\n"
    "SUPER SHIFT CTRL + SPACE            \u2192 Theme menu\n"
    "CTRL + SPACE                        \u2192 Spotlight\n"
    "PRINT                               \u2192 Screenshot\n"
).encode("utf-8")
# What the compositor answers. It names three of PRINT_FIXTURE's four chords;
# PRINT is left to --print alone, standing in for the keycode-named binds
# Hyprland reports with an empty `key`.
BINDS_FIXTURE = json.dumps([
    {"modmask": 64, "key": "SPACE", "submap": "", "description": "Omarchy menu"},
    {"modmask": 69, "key": "SPACE", "submap": "", "description": "Theme menu"},
    {"modmask": 4, "key": "SPACE", "submap": "", "description": "Spotlight"},
    {"modmask": 64, "key": "", "submap": "", "description": "Switch to workspace 1"},
]).encode("utf-8")
TOGGLE = "omarchy-shell shell toggle io.github.maajix.spotlight '{}'"
LUA_FIXTURE = "\n".join([
    "-- my bindings",
    'o.bind("SUPER + B", "Browser", "omarchy-launch-browser")',
    "",
    "-- Spotlight",
    'o.bind("CTRL + SPACE", "Spotlight", "%s")' % TOGGLE,
    '-- o.bind("ALT + SPACE", "Spotlight", "%s")' % TOGGLE,
    'o.bind("SUPER + R", "Spotlight reminder", "omarchy-shell shell toggle io.github.maajix.spotlight \'{\\"query\\":\\"remind me \\"}\'")',
    "",
])
MANAGED = "\n".join([
    HELPER.MARK_START,
    'hl.unbind("SUPER + SPACE")',
    'o.bind("SUPER + SPACE", "Spotlight", "%s")' % TOGGLE,
    HELPER.MARK_END,
    "",
])
EXPECTED_AFTER_WRITE = LUA_FIXTURE.replace(
    'o.bind("CTRL + SPACE"', HELPER.DISABLED_PREFIX + 'o.bind("CTRL + SPACE"') + "\n" + MANAGED


class SettingsWriteTests(unittest.TestCase):
    def test_default_currency_is_optional_and_normalizes_code_spelling(self):
        self.assertEqual(HELPER.normalize_settings({})["defaultCurrency"], "")
        self.assertEqual(HELPER.normalize_settings({"defaultCurrency": " eur "})["defaultCurrency"], "EUR")
        for value in [None, True, 123, [], "€", "eu", "euros", "EUR/JPY"]:
            self.assertEqual(HELPER.normalize_settings({"defaultCurrency": value})["defaultCurrency"], "")

    def test_default_currency_survives_other_settings_updates_and_can_be_cleared(self):
        with fake_home():
            reply = run(HELPER.cmd_write_settings, stdin=b'{"defaultCurrency":"eur","currencyRates":false}')
            self.assertEqual(reply["settings"]["defaultCurrency"], "EUR")
            self.assertFalse(reply["settings"]["currencyRates"])
            run(HELPER.cmd_write_settings, stdin=b'{"webSuggestions":true}')
            reply = run(HELPER.cmd_read_settings)
            self.assertEqual(reply["settings"]["defaultCurrency"], "EUR")
            self.assertFalse(reply["settings"]["currencyRates"])
            reply = run(HELPER.cmd_write_settings, stdin=b'{"defaultCurrency":""}')
            self.assertEqual(reply["settings"]["defaultCurrency"], "")

    def test_setup_completed_defaults_false_and_clamps(self):
        self.assertFalse(HELPER.normalize_settings({})["setupCompleted"])
        self.assertFalse(HELPER.normalize_settings({"setupCompleted": "yes"})["setupCompleted"])
        self.assertTrue(HELPER.normalize_settings({"setupCompleted": True})["setupCompleted"])

    def test_write_settings_merges_and_keeps_unknown_keys(self):
        with fake_home() as home:
            cfg = home / ".config" / "omarchy"
            cfg.mkdir(parents=True)
            (cfg / "spotlight.json").write_text(
                '{"maxResults": 12, "customThing": [1, 2], "bogus": true}\n')
            reply = run(HELPER.cmd_write_settings,
                        stdin=b'{"setupCompleted": true, "maxResults": 999, "evil": 1}')
            self.assertTrue(reply["ok"])
            self.assertTrue(reply["settings"]["setupCompleted"])
            self.assertEqual(reply["settings"]["maxResults"], 50)
            on_disk = json.loads((cfg / "spotlight.json").read_text())
            self.assertEqual(on_disk["customThing"], [1, 2])
            self.assertNotIn("evil", on_disk)
            self.assertTrue(on_disk["setupCompleted"])
            self.assertEqual(stat.S_IMODE((cfg / "spotlight.json").stat().st_mode), 0o600)

    def test_write_settings_clamps_every_numeric_limit(self):
        with fake_home():
            reply = run(HELPER.cmd_write_settings,
                        stdin=b'{"maxResults": 1, "maxApps": 99, "maxSuggestions": -4}')
            self.assertEqual(reply["settings"]["maxResults"], 8)
            self.assertEqual(reply["settings"]["maxApps"], 24)
            self.assertEqual(reply["settings"]["maxSuggestions"], 0)

    def test_write_settings_creates_file(self):
        with fake_home() as home:
            reply = run(HELPER.cmd_write_settings, stdin=b'{"webSuggestions": true}')
            self.assertTrue(reply["settings"]["webSuggestions"])
            self.assertTrue((home / ".config" / "omarchy" / "spotlight.json").exists())

    def test_write_settings_only_persists_patched_keys(self):
        with fake_home() as home:
            run(HELPER.cmd_write_settings, stdin=b'{"setupCompleted": true}')
            path = home / ".config" / "omarchy" / "spotlight.json"
            self.assertEqual(json.loads(path.read_text()), {"setupCompleted": True})

    def test_write_settings_stays_readable_with_large_utf8_values(self):
        with fake_home() as home:
            cfg = home / ".config" / "omarchy"
            cfg.mkdir(parents=True)
            path = cfg / "spotlight.json"
            custom = "\u4e16" * 13000
            path.write_text(json.dumps({"custom": custom}, ensure_ascii=False))
            run(HELPER.cmd_write_settings, stdin=b'{"setupCompleted": true}')
            self.assertLessEqual(path.stat().st_size, HELPER.SETTINGS_BYTES)
            self.assertEqual(json.loads(path.read_text())["custom"], custom)
            self.assertTrue(run(HELPER.cmd_read_settings)["ok"])

    def test_write_settings_refuses_an_oversized_serialization(self):
        with fake_home() as home:
            cfg = home / ".config" / "omarchy"
            cfg.mkdir(parents=True)
            path = cfg / "spotlight.json"
            original = json.dumps({"custom": [0] * 15000}, separators=(",", ":"))
            path.write_text(original)
            with self.assertRaises(HELPER.Denied):
                run(HELPER.cmd_write_settings, stdin=b'{"setupCompleted": true}')
            self.assertEqual(path.read_text(), original)

    def test_write_settings_refuses_bad_input_and_corrupt_file(self):
        with fake_home() as home:
            cfg = home / ".config" / "omarchy"
            cfg.mkdir(parents=True)
            for raw in (b"[1]", b"nope", b""):
                with self.assertRaises(HELPER.Denied):
                    run(HELPER.cmd_write_settings, stdin=raw)
            (cfg / "spotlight.json").write_bytes(b"{broken")
            with self.assertRaises(HELPER.Denied):
                run(HELPER.cmd_write_settings, stdin=b'{"setupCompleted": true}')
            self.assertEqual((cfg / "spotlight.json").read_bytes(), b"{broken")

    def test_write_settings_reports_symlink_without_touching_target(self):
        with fake_home() as home:
            cfg = home / ".config" / "omarchy"
            cfg.mkdir(parents=True)
            target = cfg / "target.json"
            target.write_text('{"maxResults": 12}')
            (cfg / "spotlight.json").symlink_to(target)
            reply = run(HELPER.main, ["write-settings"], b'{"maxResults": 30}')
            self.assertEqual(reply, {"ok": False, "error": "spotlight.json is a symlink"})
            self.assertEqual(target.read_text(), '{"maxResults": 12}')

    def test_read_settings_treats_a_corrupt_file_as_set_up(self):
        with fake_home() as home:
            cfg = home / ".config" / "omarchy"
            cfg.mkdir(parents=True)
            (cfg / "spotlight.json").write_bytes(b"{broken")
            self.assertTrue(run(HELPER.cmd_read_settings)["settings"]["setupCompleted"])
            (cfg / "spotlight.json").unlink()
            self.assertFalse(run(HELPER.cmd_read_settings)["settings"]["setupCompleted"])


class BindingTests(unittest.TestCase):
    def setUp(self):
        self.print_output = PRINT_FIXTURE
        self.print_truncated = False
        self.print_status = 0
        self.binds_output = BINDS_FIXTURE
        self.print_calls = []
        self.socket_calls = []
        real = HELPER.run_bounded
        real_request = HELPER._hypr_request

        def fake_request(payload):
            self.socket_calls.append(payload)
            return self.binds_output

        HELPER._hypr_request = fake_request
        self.addCleanup(setattr, HELPER, "_hypr_request", real_request)

        def fake_run(argv, cap, deadline, *rest, **kw):
            self.print_calls.append(argv)
            if argv[0] == "omarchy-menu-keybindings":
                if self.print_output is None:
                    raise HELPER.Denied("cannot run")
                if kw.get("want_status"):
                    return self.print_output, self.print_truncated, self.print_status
                return self.print_output, self.print_truncated
            return real(argv, cap, deadline, *rest, **kw)

        HELPER.run_bounded = fake_run
        self.addCleanup(setattr, HELPER, "run_bounded", real)

    @staticmethod
    def _hypr(home, text=LUA_FIXTURE):
        hypr = home / ".config" / "hypr"
        hypr.mkdir(parents=True, exist_ok=True)
        if text is not None:
            path = hypr / "bindings.lua"
            path.write_text(text)
            path.chmod(0o644)
        return hypr / "bindings.lua"

    def test_canon_chord(self):
        cases = {
            "SUPER SHIFT CTRL + SPACE": "SUPER + CTRL + SHIFT + SPACE",
            "ctrl+space": "CTRL + SPACE",
            "SHIFT + SUPER + K": "SUPER + SHIFT + K",
            "win + control + space": "SUPER + CTRL + SPACE",
            "mod4 mod1 + k": "SUPER + ALT + K",
            "PRINT": "PRINT",
            "SUPER + A + B": None,
            "SUPER": None,
            "": None,
        }
        for text, want in cases.items():
            self.assertEqual(HELPER._canon_chord(text), want, text)

    def test_read_binding_reports_current_and_bound(self):
        with fake_home() as home:
            self._hypr(home)
            reply = run(HELPER.cmd_read_binding)
            self.assertEqual(reply["current"], "CTRL + SPACE")
            self.assertIsNone(reply["previous"])
            self.assertFalse(reply["managed"])
            self.assertEqual(reply["bound"], {
                "SUPER + SPACE": "Omarchy menu",
                "SUPER + CTRL + SHIFT + SPACE": "Theme menu",
                "CTRL + SPACE": "Spotlight",
                "PRINT": "Screenshot",
            })

    def test_bound_chords_is_unknown_when_the_compositor_does_not_answer(self):
        # The regression this guards: omarchy-menu-keybindings --print exits 0
        # and prints its static entries when the dynamic query fails, so the
        # chord the tour wants reads as free and gets taken from whatever
        # already holds it. Asking the compositor makes that state unknown.
        self.binds_output = None
        self.print_output = PRINT_FIXTURE
        self.assertEqual(HELPER._bound_chords(), (None, []))

    def test_bound_chords_marks_the_modifiers_it_cannot_speak_for(self):
        # BINDS_FIXTURE holds one key-less record under SUPER, standing in
        # for the `SUPER + code:10` binds Hyprland 0.56 will not name. Its
        # chord is missing from the table and occupied all the same, so
        # SUPER stops being evidence of anything.
        bound, unknown = HELPER._bound_chords()
        self.assertEqual(unknown, ["SUPER"])
        self.assertEqual(bound, {
            "SUPER + SPACE": "Omarchy menu",
            "SUPER + CTRL + SHIFT + SPACE": "Theme menu",
            "CTRL + SPACE": "Spotlight",
            "PRINT": "Screenshot",
        })
        self.assertEqual(self.socket_calls, [b"j/binds"])
        self.assertFalse(HELPER._chord_is_known("SUPER + K", bound, unknown))
        self.assertFalse(HELPER._chord_is_known("SUPER + SPACE", bound, unknown))
        self.assertTrue(HELPER._chord_is_known("ALT + SPACE", bound, unknown))
        self.assertTrue(HELPER._chord_is_known("SUPER + ALT + K", bound, unknown))
        self.assertFalse(HELPER._chord_is_known("ALT + SPACE", None, []))

    def test_print_never_clears_a_modifier_the_socket_could_not_name(self):
        # --print naming one chord under SUPER is no evidence it named every
        # SUPER bind the socket could not, so the modifier stays unreliable
        # however rich --print looks. This is where counting entries would
        # turn into a guess.
        self.print_output = (
            "SUPER + 1 \u2192 Switch to workspace 1\n"
            "SUPER + 2 \u2192 Switch to workspace 2\n").encode("utf-8")
        bound, unknown = HELPER._bound_chords()
        self.assertIn("SUPER + 1", bound)
        self.assertEqual(unknown, ["SUPER"])
        # The one case that matters downstream: --print running and failing
        # cannot make a modifier look reliable either.
        for self.print_output in (None, b""):
            self.assertEqual(HELPER._bound_chords()[1], ["SUPER"])

    def test_bound_chords_keeps_modifiers_the_socket_named_in_full(self):
        self.binds_output = json.dumps([
            {"modmask": 64, "key": "B", "submap": "", "description": "Browser"},
        ]).encode("utf-8")
        self.print_output = None
        self.assertEqual(HELPER._bound_chords(), ({"SUPER + B": "Browser"}, []))

    def test_print_that_ran_and_failed_is_not_an_empty_table(self):
        # run_bounded reports stdout, not exit status, so a --print that
        # runs and dies writes nothing - the same bytes as one that ran and
        # found nothing. want_status is what tells them apart.
        self.print_status = 1
        self.print_output = b""
        self.assertIsNone(HELPER._print_chords())
        self.print_status = 0
        self.assertEqual(HELPER._print_chords(), {})

    def test_print_fills_empty_descriptions_without_replacing_compositor_labels(self):
        self.print_output = "ALT + SPACE \u2192 Menu label\n".encode("utf-8")
        for description, expected in (("", "Menu label"), (None, "Menu label"),
                                      ("Compositor label", "Compositor label")):
            self.binds_output = json.dumps([
                {"modmask": 8, "key": "SPACE", "submap": "", "description": description},
            ]).encode("utf-8")
            self.assertEqual(HELPER._bound_chords(), ({"ALT + SPACE": expected}, []))
        self.print_output = None
        self.binds_output = b'[{"modmask": 8, "key": "SPACE", "description": ""}]'
        self.assertEqual(HELPER._bound_chords(), ({"ALT + SPACE": ""}, []))

    def test_bound_chords_rejects_a_bind_table_it_cannot_trust(self):
        for raw in (b"", b"not json", b"[]", b"{}", b'["bind"]', b"[[]]",
                    b'[{"modmask": 4, "key": "SPACE"}, 7]', b"\xff\xfe"):
            self.binds_output = raw
            self.print_output = PRINT_FIXTURE
            self.assertEqual(HELPER._bound_chords(), (None, []), raw)

    def test_bound_chords_reads_modmask_and_skips_submaps(self):
        self.print_output = b""
        self.binds_output = json.dumps([
            {"modmask": 1 | 4 | 8 | 64, "key": "K", "submap": "", "description": "All mods"},
            {"modmask": 8, "key": "SPACE", "submap": "resize", "description": "In a submap",
             "submap_universal": "false"},
            {"modmask": 0, "key": "mouse:272", "submap": "", "description": "Mouse"},
            {"modmask": 4, "key": "SPACE", "submap": "", "description": None},
            # An unmapped bit (CapsLock) still names the chord: reporting a
            # free chord as taken costs a manual choice, dropping the record
            # would let an automatic write land on a live binding.
            {"modmask": 2 | 8, "key": "TAB", "submap": "", "description": "Caps"},
            {"modmask": 8, "key": "", "submap": "", "description": "no key"},
        ]).encode("utf-8")
        self.assertEqual(HELPER._bound_chords(), ({
            "SUPER + CTRL + ALT + SHIFT + K": "All mods",
            "MOUSE:272": "Mouse",
            "CTRL + SPACE": "",
            "ALT + TAB": "Caps",
        }, ["ALT"]))
        # A record whose modifiers are unreadable scopes to nothing, so it
        # takes the whole table down rather than one modifier set.
        for bad in ({"modmask": True}, {"modmask": "8"}, {"modmask": 8.0}, {}):
            self.binds_output = json.dumps([
                {"modmask": 4, "key": "SPACE", "submap": "", "description": "ok"},
                dict({"key": "", "submap": "", "description": "bad"}, **bad),
            ]).encode("utf-8")
            self.assertEqual(HELPER._bound_chords(), (None, []), bad)

    def test_a_universal_submap_bind_still_holds_the_chord(self):
        # A bind under a submap normally waits for that submap to be
        # entered, but the universal flag is what makes it fire everywhere,
        # so it occupies the chord in the default map like any other.
        # Hyprland writes the flag as the string "true", which means Python
        # truthiness would read "false" as yes.
        self.print_output = b""
        for flag, occupied in (("true", True), (True, True), ("TRUE", True),
                               ("false", False), (False, False), ("", False),
                               (None, False), ("yes", False)):
            record = {"modmask": 8, "key": "SPACE", "submap": "resize",
                      "description": "Universal"}
            if flag is not None:
                record["submap_universal"] = flag
            self.binds_output = json.dumps([
                {"modmask": 64, "key": "B", "submap": "", "description": "Browser"},
                record,
            ]).encode("utf-8")
            bound, unknown = HELPER._bound_chords()
            self.assertEqual("ALT + SPACE" in bound, occupied, flag)
            self.assertEqual(unknown, [], flag)

    def test_a_universal_submap_bind_it_cannot_name_marks_its_modifiers(self):
        self.print_output = b""
        self.binds_output = json.dumps([
            {"modmask": 64, "key": "B", "submap": "", "description": "Browser"},
            {"modmask": 8, "key": "", "submap": "resize", "submap_universal": "true",
             "description": "Universal, unnameable"},
        ]).encode("utf-8")
        bound, unknown = HELPER._bound_chords()
        self.assertEqual(unknown, ["ALT"])
        self.assertFalse(HELPER._chord_is_known("ALT + SPACE", bound, unknown))

    def test_hypr_socket_path_refuses_a_signature_it_cannot_trust(self):
        env = {"XDG_RUNTIME_DIR": "/run/user/1000",
               "HYPRLAND_INSTANCE_SIGNATURE": "sig"}
        with mock.patch.dict(os.environ, env):
            self.assertEqual(HELPER._hypr_socket_path(),
                             "/run/user/1000/hypr/sig/.socket.sock")
        for bad in ({"HYPRLAND_INSTANCE_SIGNATURE": ""},
                    {"HYPRLAND_INSTANCE_SIGNATURE": ".."},
                    {"HYPRLAND_INSTANCE_SIGNATURE": "../../etc"},
                    {"HYPRLAND_INSTANCE_SIGNATURE": "a/b"},
                    {"XDG_RUNTIME_DIR": ""},
                    {"XDG_RUNTIME_DIR": "run/user/1000"}):
            with mock.patch.dict(os.environ, dict(env, **bad)):
                self.assertIsNone(HELPER._hypr_socket_path(), bad)

    def test_read_binding_tolerates_missing_dir_and_tool(self):
        self.print_output = None
        self.binds_output = None
        with fake_home():
            reply = run(HELPER.cmd_read_binding)
            self.assertEqual(reply, {"current": None, "previous": None,
                                     "managed": False, "bound": None,
                                     "unknownMods": [], "ok": True})

    def test_write_binding_validates_chord(self):
        with fake_home() as home:
            self._hypr(home)
            for argv in (["SPACE"], ["ALT+SPACE"], ["alt + space"], ["SHIFT + SUPER + A"],
                         ["SUPER + F13"], ["SUPER + SPACE; rm -rf"], [""],
                         ["ALT + SPACE", "x"], []):
                with self.assertRaises(HELPER.Denied, msg=repr(argv)):
                    run(HELPER.cmd_write_binding, argv)
            for chord in ("ALT + SPACE", "SUPER + SHIFT + K", "CTRL + ALT + F6",
                          "SUPER + 1", "SHIFT + PRINT"):
                self.assertEqual(run(HELPER.cmd_write_binding, [chord])["chord"], chord)

    def test_write_binding_exact_bytes_and_idempotent(self):
        with fake_home() as home:
            path = self._hypr(home)
            reply = run(HELPER.cmd_write_binding, ["SUPER + SPACE"])
            self.assertTrue(reply["unbound"])
            self.assertEqual(reply["path"], str(path))
            self.assertEqual(path.read_text(), EXPECTED_AFTER_WRITE)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)
            # Second run, even after hyprctl reload made the chord look free.
            self.print_output = PRINT_FIXTURE.replace(b"SUPER + SPACE   ", b"ALT + SPACE     ")
            run(HELPER.cmd_write_binding, ["SUPER + SPACE"])
            self.assertEqual(path.read_text(), EXPECTED_AFTER_WRITE)
            reply = run(HELPER.cmd_read_binding)
            self.assertEqual((reply["current"], reply["previous"], reply["managed"]),
                             ("SUPER + SPACE", "CTRL + SPACE", True))

    def test_write_binding_disables_a_whole_multiline_call_and_reverts_exactly(self):
        original = "\n".join([
            "-- no trailing newline",
            'o.bind("CTRL + SPACE", "Spotlight", "%s",' % TOGGLE,
            "  {})",
        ])
        with fake_home() as home:
            path = self._hypr(home, original)
            run(HELPER.cmd_write_binding, ["ALT + SPACE"])
            written = path.read_text()
            self.assertIn(HELPER.DISABLED_PREFIX + 'o.bind("CTRL + SPACE"', written)
            self.assertIn(HELPER.DISABLED_PREFIX + "  {})", written)
            self.assertEqual(run(HELPER.cmd_revert_binding)["restored"], "CTRL + SPACE")
            self.assertEqual(path.read_text(), original)

    def test_single_quoted_toggle_is_recognized(self):
        original = (
            "hl.unbind('CTRL + SPACE')\n"
            "o.bind('CTRL + SPACE', 'Spotlight', "
            "'omarchy-shell shell toggle io.github.maajix.spotlight')"
        )
        with fake_home() as home:
            path = self._hypr(home, original)
            run(HELPER.cmd_write_binding, ["ALT + SPACE"])
            self.assertIn(HELPER.DISABLED_PREFIX + "hl.unbind('CTRL + SPACE')",
                          path.read_text())
            self.assertEqual(run(HELPER.cmd_read_binding)["previous"], "CTRL + SPACE")
            run(HELPER.cmd_revert_binding)
            self.assertEqual(path.read_text(), original)

    def test_managed_markers_tolerate_whitespace_and_crlf(self):
        variants = {
            "spaces": lambda text: text.replace(HELPER.MARK_START, "  " + HELPER.MARK_START + " ")
                                         .replace(HELPER.MARK_END, "\t" + HELPER.MARK_END + "  "),
            "crlf": lambda text: text.replace("\n", "\r\n"),
        }
        for name, transform in variants.items():
            with self.subTest(name=name), fake_home() as home:
                path = self._hypr(home)
                run(HELPER.cmd_write_binding, ["SUPER + SPACE"])
                path.write_bytes(transform(path.read_text()).encode())
                run(HELPER.cmd_write_binding, ["ALT + SPACE"])
                written = path.read_text()
                self.assertNotIn('hl.unbind("SUPER + SPACE")', written)
                self.assertNotIn('o.bind("SUPER + SPACE", "Spotlight"', written)

    def test_write_binding_handles_an_empty_managed_block(self):
        with fake_home() as home:
            path = self._hypr(home, HELPER.MARK_START + "\n" + HELPER.MARK_END)
            run(HELPER.cmd_write_binding, ["ALT + SPACE"])
            self.assertIn('o.bind("ALT + SPACE", "Spotlight"', path.read_text())

    def test_unbind_only_when_someone_else_holds_the_chord(self):
        with fake_home() as home:
            self._hypr(home)
            self.assertFalse(run(HELPER.cmd_write_binding, ["CTRL + SPACE"])["unbound"])
        with fake_home() as home:
            self._hypr(home)
            self.assertFalse(run(HELPER.cmd_write_binding, ["ALT + SPACE"])["unbound"])
        with fake_home() as home:
            # After our own write + reload the chord shows up as Spotlight; still ours.
            self._hypr(home)
            run(HELPER.cmd_write_binding, ["ALT + SPACE"])
            self.print_output = PRINT_FIXTURE.replace(b"\nCTRL + SPACE", b"\nALT + SPACE ")
            self.assertFalse(run(HELPER.cmd_write_binding, ["ALT + SPACE"])["unbound"])

    def test_write_binding_unbinds_when_the_keybinding_list_is_unavailable(self):
        # Unavailable now means the compositor did not answer; --print going
        # missing only narrows a table the socket already returned.
        self.binds_output = None
        self.print_output = None
        with fake_home() as home:
            path = self._hypr(home)
            self.assertTrue(run(HELPER.cmd_write_binding, ["ALT + SPACE"])["unbound"])
            self.assertIn('hl.unbind("ALT + SPACE")', path.read_text())

    def test_write_binding_refuses_missing_dir_and_unclosed_block(self):
        with fake_home():
            with self.assertRaises(HELPER.Denied):
                run(HELPER.cmd_write_binding, ["ALT + SPACE"])
        with fake_home() as home:
            path = self._hypr(home, LUA_FIXTURE + HELPER.MARK_START + "\n")
            before = path.read_bytes()
            with self.assertRaises(HELPER.Denied):
                run(HELPER.cmd_write_binding, ["ALT + SPACE"])
            self.assertEqual(path.read_bytes(), before)

    def test_write_binding_creates_missing_file(self):
        with fake_home() as home:
            path = self._hypr(home, None)
            run(HELPER.cmd_write_binding, ["SUPER + SPACE"])
            self.assertEqual(path.read_text(), MANAGED)
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)

    def test_revert_round_trips(self):
        with fake_home() as home:
            path = self._hypr(home)
            run(HELPER.cmd_write_binding, ["SUPER + SPACE"])
            reply = run(HELPER.cmd_revert_binding)
            self.assertEqual(reply["restored"], "CTRL + SPACE")
            self.assertEqual(path.read_text(), LUA_FIXTURE)
            reply = run(HELPER.cmd_read_binding)
            self.assertEqual((reply["current"], reply["previous"], reply["managed"]),
                             ("CTRL + SPACE", None, False))

    def test_revert_without_block_is_a_noop(self):
        with fake_home() as home:
            path = self._hypr(home)
            os.utime(path, (1000000, 1000000))
            self.assertIsNone(run(HELPER.cmd_revert_binding)["restored"])
            self.assertEqual(path.stat().st_mtime, 1000000)
        with fake_home() as home:
            self._hypr(home, None)
            self.assertIsNone(run(HELPER.cmd_revert_binding)["restored"])
        with fake_home():
            with self.assertRaises(HELPER.Denied):
                run(HELPER.cmd_revert_binding)


class MenuCommandsTests(unittest.TestCase):
    MENU_FIXTURE = {
        "root": {"label": "Go"},
        "learn": {"label": "Learn", "parent": "root"},
        "learn.safe": {
            "label": "Safe command",
            "parent": "learn",
            "aliases": ["safe", "fixture"],
            "action": "omarchy-safe --flag",
        },
        "learn.keybindings": {"label": "Keybindings", "action": "omarchy-menu-keybindings"},
        "trigger.toggle.screensaver": {"label": "Screensaver", "action": "omarchy-toggle-screensaver"},
        "setup.keybindings": {"label": "Keybindings", "action": "omarchy-edit-keybindings"},
        "install.example": {"label": "Install", "action": "omarchy-install-example"},
        "remove.example": {"label": "Remove", "action": "omarchy-remove-example"},
        "system.example": {"label": "System", "action": "omarchy-system-example"},
        "external": {"label": "External", "action": "systemctl reboot"},
    }

    def _fixture_menu_commands(self, user_raw=b"{}", default_raw=None):
        original_default = HELPER._menu_read_default
        original_user = HELPER._menu_read_user
        if default_raw is None:
            default_raw = json.dumps({"items": self.MENU_FIXTURE}).encode()
        HELPER._menu_read_default = lambda: default_raw
        HELPER._menu_read_user = lambda: user_raw
        try:
            return HELPER._menu_commands()
        finally:
            HELPER._menu_read_default = original_default
            HELPER._menu_read_user = original_user

    def test_action_resolves_to_argv_for_plain_commands(self):
        self.assertEqual(
            HELPER._menu_resolve_argv("omarchy-launch-webapp 'https://example.com/'"),
            ["omarchy-launch-webapp", "https://example.com/"],
        )

    def test_action_expands_home_and_tilde_without_a_shell(self):
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = "/home/test-user"
        try:
            self.assertEqual(
                HELPER._menu_resolve_argv('omarchy-launch-config-editor "$HOME/.config/hypr/hyprland.lua"'),
                ["omarchy-launch-config-editor", "/home/test-user/.config/hypr/hyprland.lua"],
            )
            self.assertEqual(
                HELPER._menu_resolve_argv("omarchy-launch-config-editor ~/.XCompose"),
                ["omarchy-launch-config-editor", "/home/test-user/.XCompose"],
            )
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home

    def test_action_needing_a_real_shell_is_rejected_not_reinterpreted(self):
        # Real entries from the shipped menu tree - each needs actual shell
        # semantics (||, &&, command substitution, if/then) that shlex does
        # not provide, so none of them may become an argv vector.
        for action in (
            "pkill hyprpicker || hyprpicker -a",
            'theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set "$theme"',
            "omarchy-launch-config-editor ~/.config/hypr/hyprsunset.conf && omarchy-restart-hyprsunset",
            "if omarchy-cmd-present nvidia-smi; then ollama_pkg=ollama-cuda; fi",
        ):
            self.assertIsNone(HELPER._menu_resolve_argv(action), action)

    def test_action_with_an_unresolved_variable_is_rejected(self):
        # $HOME/~ are the only substitutions this ever performs; anything
        # else left in a token after that is a sign of an expansion this
        # does not understand, not something to pass through literally.
        self.assertIsNone(HELPER._menu_resolve_argv("omarchy-dns $CUSTOM_DNS"))

    def test_action_does_not_expand_a_variable_that_merely_starts_with_home(self):
        # $HOMEDIR is a different variable that happens to start with the
        # same four letters - a substring replace turned it into a
        # fabricated path instead of leaving it as the unresolved variable
        # it is, which the token-with-a-$-left-in-it check rejects.
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = "/home/test-user"
        try:
            self.assertIsNone(HELPER._menu_resolve_argv("omarchy-launch-config-editor $HOMEDIR/a"))
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home

    def test_action_with_a_single_quoted_home_stays_literal_not_expanded(self):
        # Single quotes in real Bash mean literal - $HOME under them is
        # never a variable reference, so the correct argv value is the
        # literal string "$HOME/a", not an expanded path and not a
        # rejection (this is now resolvable exactly, not just detectable
        # as wrong - see the quote-aware tokeniser).
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = "/home/test-user"
        try:
            self.assertEqual(
                HELPER._menu_resolve_argv("omarchy-launch-config-editor '$HOME/a'"),
                ["omarchy-launch-config-editor", "$HOME/a"],
            )
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home

    def test_action_with_a_quote_concatenation_trick_stays_literal(self):
        # Bash joins an adjacent quoted and unquoted span into one token
        # with no whitespace between them, so `'$'HOME/a` - a single-quoted
        # literal `$` immediately followed by unquoted `HOME/a` - is the
        # literal string "$HOME/a", never an expansion of $HOME: only the
        # `$` itself was ever quoted, and unquoted `HOME/a` has no `$` in
        # it to expand. Found by review: a check that only asks "is the
        # whole $HOME substring inside quotes" cannot see this, since no
        # quote in the source spans all of "$HOME".
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = "/home/test-user"
        try:
            for action in (
                "omarchy-launch-config-editor '$'HOME/a",
                'omarchy-launch-config-editor "$"HOME/a',
            ):
                self.assertEqual(
                    HELPER._menu_resolve_argv(action),
                    ["omarchy-launch-config-editor", "$HOME/a"],
                    action,
                )
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home

    def test_action_keeps_shell_metacharacters_literal_inside_quotes(self):
        # ?, &, *, {}, [] only mean anything to a real shell when they are
        # not quoted - found by review, rejecting them unconditionally (a
        # regex over the raw string before tokenising) made a harmless,
        # already-quoted URL query string vanish from the catalogue, the
        # same false-negative failure this module otherwise avoids on
        # purpose. omarchy-launch-webapp with a quoted URL is a real,
        # common shape in the shipped tree.
        self.assertEqual(
            HELPER._menu_resolve_argv("omarchy-launch-webapp 'https://x.com/?a=1&b=2'"),
            ["omarchy-launch-webapp", "https://x.com/?a=1&b=2"],
        )
        self.assertEqual(
            HELPER._menu_resolve_argv("omarchy-foo 'file * name'"),
            ["omarchy-foo", "file * name"],
        )

    def test_action_tilde_expansion_respects_real_token_boundaries(self):
        # Found by review: a regex checking "is there a ~ somewhere between
        # a pair of quotes" could match across two separate quoted tokens
        # rather than within one, falsely treating an unquoted ~ in between
        # as though it were quoted. A real per-character tokeniser cannot
        # make that mistake.
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = "/home/test-user"
        try:
            self.assertEqual(
                HELPER._menu_resolve_argv("omarchy-foo 'a' ~/x 'b'"),
                ["omarchy-foo", "a", "/home/test-user/x", "b"],
            )
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home

    def test_action_rejects_redirection_background_and_glob_operators(self):
        # Real evidence from the review: shlex tokenises these into
        # syntactically valid-looking argv (">"/"&" as literal tokens)
        # instead of raising, so the operator blacklist - not shlex itself -
        # is what has to catch them.
        for action in (
            "omarchy-dns DHCP > /tmp/dns.log",
            "omarchy-dns DHCP 2> /tmp/dns.log",
            "omarchy-dns DHCP < /tmp/in",
            "omarchy-dns DHCP &",
            "omarchy-launch-webapp *.desktop",
            "omarchy-launch-webapp {a,b}",
            "omarchy-probe (a)",
            "omarchy-probe a)",
        ):
            self.assertIsNone(HELPER._menu_resolve_argv(action), action)

    def test_action_rejects_nonleading_unquoted_tilde(self):
        # Bash expands ~ after the `=`/`:` in assignment-shaped words, but
        # this lexer deliberately does not implement the complete assignment
        # grammar. Passing it through literally would execute a different
        # argv, so ambiguous non-leading unquoted forms fail closed. A quoted
        # tilde is unambiguously literal and remains supported.
        for action in (
            "omarchy-probe x=~/foo",
            "omarchy-probe x=a:~/foo",
            "omarchy-probe foo~bar",
        ):
            self.assertIsNone(HELPER._menu_resolve_argv(action), action)
        self.assertEqual(
            HELPER._menu_resolve_argv("omarchy-probe 'x=~/foo'"),
            ["omarchy-probe", "x=~/foo"],
        )

    def test_action_rejects_an_unquoted_newline_as_a_command_separator(self):
        # Found by review: \n is whitespace to Python's isspace() but a
        # command separator to real Bash, not a word separator - two lines
        # are two commands, never one command with an extra argument. This
        # is the exact failure that reproved the very first review round;
        # a lexer rewrite reintroduced it by checking isspace() before the
        # reject-char set that already listed \n.
        self.assertIsNone(HELPER._menu_resolve_argv("omarchy-a\nomarchy-b"))

    def test_action_rejects_named_and_special_tilde_forms(self):
        # Only `~` alone and `~/...` are ever expanded - found by review,
        # expanding any leading ~ unconditionally fabricated a path for
        # `~user` (another user's home directory), `~+` ($PWD) and `~-`
        # ($OLDPWD), none of which this module can resolve correctly
        # without guessing.
        for action in ("omarchy-probe ~foo", "omarchy-probe ~foo/bar", "omarchy-probe ~+", "omarchy-probe ~-"):
            self.assertIsNone(HELPER._menu_resolve_argv(action), action)
        old_home = os.environ.get("HOME")
        os.environ["HOME"] = "/home/test-user"
        try:
            self.assertEqual(HELPER._menu_resolve_argv("omarchy-probe ~"), ["omarchy-probe", "/home/test-user"])
            self.assertEqual(HELPER._menu_resolve_argv("omarchy-probe ~/x"), ["omarchy-probe", "/home/test-user/x"])
        finally:
            if old_home is None:
                os.environ.pop("HOME", None)
            else:
                os.environ["HOME"] = old_home

    def test_action_keeps_an_explicit_empty_quoted_argument(self):
        # Found by review: '' and "" are legitimate empty arguments in real
        # Bash, not nothing - dropping them shifts every positional
        # argument after it, silently calling the command with the wrong
        # arity.
        self.assertEqual(HELPER._menu_resolve_argv("omarchy-probe '' tail"), ["omarchy-probe", "", "tail"])
        self.assertEqual(HELPER._menu_resolve_argv('omarchy-probe ""'), ["omarchy-probe", ""])

    def test_action_rejects_ansi_c_and_locale_quoting(self):
        # Found by review: $'...' (ANSI-C quoting) and $"..." (locale
        # quoting) are real Bash constructs this module does not
        # implement. Treating the $ as a literal dollar sign here (as it
        # correctly is inside already-open double quotes, where a lone '
        # has no special meaning) accepted the action with the wrong
        # argument - $'abc' means the single argument "abc" in Bash, not a
        # literal "$" followed by a separately-quoted "abc".
        self.assertIsNone(HELPER._menu_resolve_argv("omarchy-probe $'abc'"))
        self.assertIsNone(HELPER._menu_resolve_argv('omarchy-probe $"abc"'))

    def test_action_keeps_carriage_return_vtab_formfeed_literal_in_a_word(self):
        # Found by review: Python's str.isspace() is true for \r/\v/\f too,
        # but Bash's default IFS is only space/tab/newline - those three
        # are ordinary characters *inside* a Bash word, not separators.
        # Splitting a word on them shifted positional arguments, the same
        # class of bug as newline being consumed by isspace() before the
        # reject check could see it, just narrower in practice.
        self.assertEqual(HELPER._menu_resolve_argv("omarchy-probe a\rb"), ["omarchy-probe", "a\rb"])
        self.assertEqual(HELPER._menu_resolve_argv("omarchy-probe a\vb"), ["omarchy-probe", "a\vb"])
        self.assertEqual(HELPER._menu_resolve_argv("omarchy-probe a\fb"), ["omarchy-probe", "a\fb"])

    def test_systemctl_action_is_rejected_regardless_of_shape(self):
        # The exact case Commands.js already refuses by hand (its own
        # comment: a bare systemctl call costs the marketplace listing its
        # automatic Verified status) - argv-clean, two tokens, no shell
        # operator at all, and still must not pass the argv[0] gate.
        self.assertIsNone(HELPER._menu_resolve_argv("systemctl suspend"))
        self.assertIsNone(HELPER._menu_resolve_argv("systemctl hibernate"))

    def test_action_is_capped_on_token_count_and_token_length(self):
        many_tokens = "omarchy-launch-webapp " + " ".join("a" for _ in range(HELPER.MENU_ARGV_TOKENS + 1))
        self.assertIsNone(HELPER._menu_resolve_argv(many_tokens))
        long_token = "omarchy-launch-webapp " + ("x" * (HELPER.MENU_ARGV_CHARS + 1))
        self.assertIsNone(HELPER._menu_resolve_argv(long_token))

    def test_when_with_no_condition_allows(self):
        self.assertTrue(HELPER._menu_when_allows(""))
        self.assertTrue(HELPER._menu_when_allows(None))

    def test_when_pkg_present_reads_the_cached_package_list(self):
        original = HELPER._INSTALLED_PACKAGES
        HELPER._INSTALLED_PACKAGES = frozenset({"git", "python"})
        try:
            self.assertTrue(HELPER._menu_when_allows("omarchy-pkg-present git"))
            self.assertFalse(HELPER._menu_when_allows("omarchy-pkg-present nonexistent-pkg"))
            self.assertFalse(HELPER._menu_when_allows("! omarchy-pkg-present git"))
            self.assertTrue(HELPER._menu_when_allows("! omarchy-pkg-present nonexistent-pkg"))
        finally:
            HELPER._INSTALLED_PACKAGES = original

    def test_when_pkg_present_shows_rather_than_hides_on_a_truncated_listing(self):
        # None now distinctly means "truncated/unknown", not "not yet read"
        # (that is the "unread" sentinel) - a truncated pacman -Qq listing
        # must not read as "package absent" for a plain check, nor as
        # "package present" for a negated one; both must default to shown.
        original = HELPER._INSTALLED_PACKAGES
        HELPER._INSTALLED_PACKAGES = None
        try:
            self.assertTrue(HELPER._menu_when_allows("omarchy-pkg-present git"))
            self.assertTrue(HELPER._menu_when_allows("! omarchy-pkg-present git"))
        finally:
            HELPER._INSTALLED_PACKAGES = original

    def test_when_cmd_present_checks_path(self):
        self.assertTrue(HELPER._menu_when_allows("omarchy-cmd-present sh"))
        self.assertFalse(HELPER._menu_when_allows("omarchy-cmd-present definitely-not-a-real-command-xyz"))
        self.assertTrue(HELPER._menu_when_allows("! omarchy-cmd-present definitely-not-a-real-command-xyz"))

    def test_when_path_exists_checks_dir_and_file(self):
        with tempfile.TemporaryDirectory() as directory:
            file_path = Path(directory) / "marker"
            file_path.write_text("x")
            self.assertTrue(HELPER._menu_when_allows("[[ -d %s ]]" % directory))
            self.assertFalse(HELPER._menu_when_allows("[[ ! -d %s ]]" % directory))
            self.assertTrue(HELPER._menu_when_allows("[[ -f %s ]]" % file_path))
            self.assertFalse(HELPER._menu_when_allows("[[ -f %s/missing ]]" % directory))

    def test_when_path_respects_quote_type_for_home_and_tilde_expansion(self):
        # Found by review: $HOME expands inside double quotes and unquoted
        # text (real Bash's rule) but never inside single quotes; ~ never
        # expands under any quoting. A literal directory named "$HOME" or
        # "~" almost certainly does not exist, so the un-negated condition
        # is False and the negated one True - if either got expanded, the
        # real home directory (which does exist) would flip both results.
        self.assertFalse(HELPER._menu_when_allows("[[ -d '$HOME' ]]"))
        self.assertTrue(HELPER._menu_when_allows("[[ ! -d '$HOME' ]]"))
        self.assertFalse(HELPER._menu_when_allows('[[ -d "~" ]]'))
        self.assertTrue(HELPER._menu_when_allows('[[ ! -d "~" ]]'))
        # Unquoted and double-quoted $HOME still expand correctly.
        home = os.environ.get("HOME", "")
        if home:
            self.assertTrue(HELPER._menu_when_allows("[[ -d %s ]]" % home))
            self.assertTrue(HELPER._menu_when_allows('[[ -d "$HOME" ]]'))

    def test_when_path_exists_handles_quoted_paths_with_spaces(self):
        # A quoted path is the normal, equivalent Bash form - the previous
        # regex captured the quotes themselves as part of the filename, so
        # `[[ -d "/" ]]` came back False even though `/` plainly exists.
        self.assertTrue(HELPER._menu_when_allows('[[ -d "/" ]]'))
        self.assertTrue(HELPER._menu_when_allows("[[ -d '/' ]]"))
        with tempfile.TemporaryDirectory() as directory:
            spaced = Path(directory) / "Xbox Cloud Gaming"
            spaced.mkdir()
            self.assertTrue(HELPER._menu_when_allows('[[ -d "%s" ]]' % spaced))
            self.assertFalse(HELPER._menu_when_allows('[[ -d "%s missing" ]]' % spaced))

    def test_when_unrecognised_condition_shows_rather_than_hides(self):
        # A false negative (a row silently disappears) is worse in a
        # launcher than a false positive (one dead row for hardware the
        # user does not have), so anything this cannot answer defaults to
        # visible.
        self.assertTrue(HELPER._menu_when_allows("omarchy-hw-dell-xps-haptic-touchpad"))
        self.assertTrue(HELPER._menu_when_allows("[[ $(findmnt -no FSTYPE /) == btrfs ]]"))

    def test_merge_overrides_fields_not_whole_entries(self):
        default_items = {"personal": {"label": "Personal", "icon": "A", "action": "omarchy-x"}}
        user_items = {"personal": {"label": "Mine"}}
        merged, order = HELPER._menu_merge(default_items, user_items)
        self.assertEqual(order, ["personal"])
        self.assertEqual(merged["personal"]["label"], "Mine")
        self.assertEqual(merged["personal"]["icon"], "A")
        self.assertEqual(merged["personal"]["action"], "omarchy-x")

    def test_merge_does_not_leave_a_stale_action_when_an_extension_turns_it_into_a_link(self):
        # The review's main finding: merging raw dicts (rather than
        # normalizing each source first, as the real MenuModel.js does)
        # let a default action survive under an extension's replacement
        # label even though the extension itself no longer sets `action`
        # at all - the exact case where the real menu runs nothing and
        # Spotlight would otherwise have kept running the old command.
        default_items = HELPER._menu_parse_items(
            json.dumps({"custom": {"label": "Original", "action": "omarchy-x"}}).encode()
        )
        user_items = HELPER._menu_parse_items(
            json.dumps({"custom": {"label": "Submenu", "target": "style"}}).encode()
        )
        merged, order = HELPER._menu_merge(default_items, user_items)
        self.assertEqual(merged["custom"]["kind"], "link")
        self.assertEqual(merged["custom"]["action"], "")
        self.assertEqual(merged["custom"]["target"], "style")

    def test_breadcrumb_walks_labelled_ancestors_and_tolerates_cycles(self):
        merged = {
            "a": {"label": "Top", "parent": "root"},
            "a.b": {"label": "Mid", "parent": "a"},
            "a.b.c": {"label": "Leaf", "parent": "a.b"},
        }
        self.assertEqual(HELPER._menu_breadcrumb("a.b.c", merged), "Top › Mid")

        cyclic = {
            "x": {"label": "X", "parent": "y"},
            "y": {"label": "Y", "parent": "x"},
        }
        # Must terminate rather than loop forever; the exact crumb does not
        # matter as much as returning at all.
        HELPER._menu_breadcrumb("x", cyclic)

    def test_breadcrumb_clamps_each_ancestor_label(self):
        merged = {
            "a": {"label": "x" * (HELPER.MENU_BREADCRUMB_LABEL_CHARS + 50), "parent": "root"},
            "a.b": {"label": "Leaf", "parent": "a"},
        }
        crumb = HELPER._menu_breadcrumb("a.b", merged)
        self.assertLessEqual(len(crumb), HELPER.MENU_BREADCRUMB_LABEL_CHARS + 3)

    def test_menu_commands_never_emit_a_non_omarchy_prefixed_command(self):
        for row in self._fixture_menu_commands():
            self.assertTrue(row["argv"][0].startswith("omarchy-"), row)

    def test_menu_commands_exclude_install_remove_and_system_subtrees(self):
        for row in self._fixture_menu_commands():
            item_id = row["key"].split(":", 1)[1]
            self.assertFalse(item_id.startswith(("install.", "remove.", "system.")), item_id)
            self.assertNotIn(item_id, ("install", "remove", "system"))

    def test_menu_commands_exclude_ids_that_collide_with_commands_js(self):
        # Keybindings and Screensaver already exist by hand in Commands.js
        # with different (Screensaver: opposite) behaviour - a second,
        # differently-behaving row under the same title is a worse outcome
        # than the menu tree's copy being absent from this catalogue.
        #
        # Found by review: asserting id-not-in-emitted-set against
        # MENU_SKIP_IDS itself is a tautology for a typo'd id (it can never
        # appear, whether the skip worked or the id was simply never real),
        # so this checks the actual property that matters - no title this
        # module emits collides with one of Commands.js's curated titles -
        # rather than trusting the skip list to grade its own homework.
        commands_js_titles = {"Keybindings", "Screensaver"}
        for row in self._fixture_menu_commands():
            self.assertNotIn(row["title"], commands_js_titles, row)

    def test_menu_commands_stops_before_exceeding_the_json_budget(self):
        # Row count and per-label clamps alone do not bound the real
        # serialized payload; MENU_JSON_BUDGET_CHARS is the defense-in-depth
        # that actually has to trip. Shrink the budget rather than trying to
        # organically produce >200000 chars, so the assertion is exact and
        # not dependent on today's field-length constants.
        original_default = HELPER._menu_read_default
        original_user = HELPER._menu_read_user
        original_budget = HELPER.MENU_JSON_BUDGET_CHARS
        tree = {}
        for i in range(60):
            tree["c%d" % i] = {"label": "Leaf number %d" % i, "action": "omarchy-x"}
        HELPER._menu_read_default = lambda: json.dumps(tree).encode()
        HELPER._menu_read_user = lambda: b"{}"
        HELPER.MENU_JSON_BUDGET_CHARS = 1000
        try:
            rows = HELPER._menu_commands()
            self.assertGreater(len(rows), 0)
            self.assertLess(len(rows), 60)
            total = len(json.dumps(rows, ensure_ascii=False, separators=(",", ":")))
            self.assertLessEqual(total, HELPER.MENU_JSON_BUDGET_CHARS + 200)
        finally:
            HELPER._menu_read_default = original_default
            HELPER._menu_read_user = original_user
            HELPER.MENU_JSON_BUDGET_CHARS = original_budget

    def test_menu_commands_always_emits_at_least_one_row_even_over_budget(self):
        # A single row larger than the whole budget must still go out - the
        # budget check only applies once at least one row has been emitted,
        # so one oversized entry cannot silently empty the entire catalogue.
        original_default = HELPER._menu_read_default
        original_user = HELPER._menu_read_user
        original_budget = HELPER.MENU_JSON_BUDGET_CHARS
        HELPER._menu_read_default = lambda: json.dumps(
            {"only": {"label": "Only Item", "action": "omarchy-x"}}
        ).encode()
        HELPER._menu_read_user = lambda: b"{}"
        HELPER.MENU_JSON_BUDGET_CHARS = 1
        try:
            rows = HELPER._menu_commands()
            self.assertEqual(len(rows), 1)
        finally:
            HELPER._menu_read_default = original_default
            HELPER._menu_read_user = original_user
            HELPER.MENU_JSON_BUDGET_CHARS = original_budget

    def test_menu_commands_row_shape_matches_commands_js(self):
        rows = self._fixture_menu_commands()
        self.assertGreater(len(rows), 0)
        for row in rows[:5]:
            self.assertEqual(
                set(row.keys()), {"key", "title", "subtitle", "icon", "argv", "keywords"}
            )
            self.assertIsInstance(row["argv"], list)
            self.assertTrue(row["key"].startswith("menu:"))

    def test_menu_commands_survives_a_missing_or_malformed_user_extension(self):
        rows = self._fixture_menu_commands(b"{ not json at all")
        self.assertGreater(len(rows), 0)

    @unittest.skipUnless(
        Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), *HELPER.MENU_PARTS, HELPER.MENU_NAME).is_file(),
        "installed Omarchy menu is unavailable",
    )
    def test_installed_menu_matches_projection_safety_invariants(self):
        # Optional integration coverage for Omarchy hosts. Read the fixture
        # directly here so filesystem sandbox UID remapping does not turn a
        # parser/projection test into an ownership-policy test; read_file's
        # ownership checks have their own focused coverage above.
        menu_path = Path(
            os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"),
            *HELPER.MENU_PARTS,
            HELPER.MENU_NAME,
        )
        rows = self._fixture_menu_commands(default_raw=menu_path.read_bytes())
        self.assertGreater(len(rows), 0)
        for row in rows:
            self.assertTrue(row["argv"][0].startswith("omarchy-"), row)
            item_id = row["key"].split(":", 1)[1]
            self.assertFalse(item_id.startswith(HELPER.MENU_SKIP_PREFIXES), item_id)


@unittest.skipUnless(shutil.which("bash"), "bash not available")
class TokenizeVsBashTests(unittest.TestCase):
    """A compact differential harness against real Bash - not exhaustive,
    but the shape of check that actually caught every defect found across
    review rounds 6-8 (a newline regression, ~user/~+/~- fabrication, a
    dropped empty quoted argument, ANSI-C/locale quoting), none of which an
    inline unit test asserting one input/output pair at a time had managed
    to catch before the bug was already reported by a human reviewer.

    Each action runs for real under `bash -c`, with PATH restricted to a
    directory of shim executables that record their own argv instead of
    doing anything - so nothing real ever executes, and the check is
    self-validating rather than needing a hand-maintained expected-output
    table: if Bash runs the shim exactly once, _menu_resolve_argv must
    return that exact argv; if Bash runs it zero times (a syntax error) or
    more than once (e.g. a newline splitting one action into two
    commands), _menu_resolve_argv must return None, since this module only
    ever accepts an action that is unambiguously one single simple command.
    """

    SHIM_NAMES = ("omarchy-probe", "omarchy-a", "omarchy-b")

    @classmethod
    def setUpClass(cls):
        cls.bash_path = shutil.which("bash")
        cls.shimdir = tempfile.mkdtemp(prefix="menu-tokenize-shim-")
        shim_src = (
            "#!" + sys.executable + "\n"
            "import json, os, sys\n"
            "with open(os.environ['MENU_TOKENIZE_LOG'], 'a') as f:\n"
            "    f.write(json.dumps([os.path.basename(sys.argv[0])] + sys.argv[1:]) + '\\n')\n"
        )
        for name in cls.SHIM_NAMES:
            path = Path(cls.shimdir) / name
            path.write_text(shim_src)
            path.chmod(0o755)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.shimdir, ignore_errors=True)

    def _bash_invocations(self, action):
        with tempfile.NamedTemporaryFile(prefix="menu-tokenize-log-", suffix=".jsonl", delete=False) as f:
            logfile = f.name
        try:
            # cwd is a scratch directory, not the repo: a case like "a > b"
            # is meant to be *rejected*, precisely because Bash really
            # would create a file named "b" here - which is exactly what
            # happens when this harness runs the action for real to find
            # out, and it must not land in the repo's own working tree.
            with tempfile.TemporaryDirectory(prefix="menu-tokenize-cwd-") as cwd:
                env = {
                    "PATH": self.shimdir,
                    "HOME": os.environ.get("HOME", "/root"),
                    "MENU_TOKENIZE_LOG": logfile,
                }
                subprocess.run(
                    [self.bash_path, "-c", action],
                    env=env, cwd=cwd, timeout=5,
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
            lines = Path(logfile).read_text().splitlines()
            return [json.loads(line) for line in lines]
        finally:
            os.unlink(logfile)

    def _assert_agrees_with_bash(self, action):
        # Over-rejecting is always safe here by this module's own explicit
        # policy (unrecognised syntax is excluded, never guessed at), so
        # only one direction is actually a bug: this module accepting an
        # action and resolving it to something other than what Bash itself
        # would run it as. A None result is never asserted against Bash -
        # it is deliberately conservative for several real constructs
        # (~user, for instance) that Bash would run unambiguously.
        invocations = self._bash_invocations(action)
        got = HELPER._menu_resolve_argv(action)
        if got is None:
            return
        self.assertEqual(len(invocations), 1, (action, got, invocations))
        self.assertEqual(got, invocations[0], action)

    def test_agrees_with_bash_across_the_corpus(self):
        cases = [
            "omarchy-probe a b c",
            "omarchy-probe 'a b' c",
            'omarchy-probe "a b" c',
            "omarchy-probe a'b'c",
            "omarchy-probe ~/x",
            "omarchy-probe ~",
            "omarchy-probe ~/",
            "omarchy-probe ~foo",
            "omarchy-probe ~foo/bar",
            "omarchy-probe ~+",
            "omarchy-probe ~-",
            "omarchy-probe '' tail",
            'omarchy-probe ""',
            "omarchy-probe '$'HOME/a",
            'omarchy-probe "$"HOME/a',
            'omarchy-probe "$HOME"x',
            "omarchy-probe 'https://x.com/?a=1&b=2'",
            "omarchy-probe 'file * name'",
            "omarchy-probe a\tb",
            "omarchy-probe a\rb",
            "omarchy-probe a\vb",
            "omarchy-probe a\fb",
            "omarchy-probe $'abc'",
            'omarchy-probe $"abc"',
            "omarchy-probe a$'b'",
            "omarchy-probe $CUSTOM_DNS",
            "omarchy-probe $HOMEDIR/a",
            "omarchy-probe a > b",
            "omarchy-probe a < b",
            # Not "a & b": backgrounding races bash's own exit against the
            # shim's file write, since bash -c does not wait on background
            # jobs before exiting - unreliable to assert here, and the
            # rejection is already pinned deterministically by the plain
            # unit tests above.
            "omarchy-probe a && b",
            "omarchy-probe a || b",
            "omarchy-probe a; b",
            "omarchy-probe *.desktop",
            "omarchy-probe {a,b}",
            "omarchy-probe (a)",
            "omarchy-probe a)",
            "omarchy-probe x=~/foo",
            "omarchy-probe x=a:~/foo",
            "omarchy-a\nomarchy-b",
            "if omarchy-probe x; then omarchy-a; fi",
            "omarchy-probe $(omarchy-a)",
            "omarchy-probe `omarchy-a`",
        ]
        for action in cases:
            self._assert_agrees_with_bash(action)


class ToggleStatesTests(unittest.TestCase):
    """The switch in the result list is only ever as honest as this probe."""

    def _states(self):
        """Flag files only: the command probes get their own tests."""
        with mock.patch.dict(HELPER.TOGGLE_PROBES, {}, clear=True):
            reply = run(HELPER.cmd_toggle_states)
        self.assertTrue(reply["ok"])
        return reply["states"]

    def test_flag_files_report_their_documented_sense(self):
        with fake_home() as home:
            for name, (rel, present_is_on) in HELPER.TOGGLE_FLAGS.items():
                flag = home / rel
                flag.parent.mkdir(parents=True, exist_ok=True)
                flag.write_text("")
                self.assertEqual(self._states()[name], present_is_on, name)
                flag.unlink()
                self.assertEqual(self._states()[name], not present_is_on, name)

    def test_a_probe_that_cannot_run_is_omitted_rather_than_reported_off(self):
        with fake_home():
            with mock.patch.dict(HELPER.TOGGLE_PROBES, {
                "missing": HELPER._cmd_probe(["spotlight-no-such-binary"], lambda t: True),
                "unreadable": HELPER._cmd_probe(["printf", "something else entirely"],
                                                lambda t: HELPER._tri(t, "yes", "no")),
            }, clear=True):
                reply = run(HELPER.cmd_toggle_states)
        self.assertTrue(reply["ok"])
        self.assertNotIn("missing", reply["states"])
        self.assertNotIn("unreadable", reply["states"])

    def test_probe_output_maps_to_three_answers_never_to_a_guess(self):
        self.assertTrue(HELPER._probe_bluetooth("bluetooth unblocked\nwlan blocked\n"))
        self.assertFalse(HELPER._probe_bluetooth("bluetooth blocked\nwlan unblocked\n"))
        self.assertIsNone(HELPER._probe_bluetooth("wlan unblocked\n"))

        self.assertTrue(HELPER._probe_mic("Volume: 0.40"))
        self.assertFalse(HELPER._probe_mic("Volume: 0.40 [MUTED]"))
        self.assertIsNone(HELPER._probe_mic(""))

        # Opaque forced on is transparency off, and getprop answers a miss in
        # prose rather than JSON.
        self.assertFalse(HELPER._probe_opaque('{"opaque": true}'))
        self.assertTrue(HELPER._probe_opaque('{"opaque": false}'))
        self.assertIsNone(HELPER._probe_opaque("window not found"))

        self.assertTrue(HELPER._probe_nightlight('{"enabled":true,"temperature":4000}'))
        self.assertFalse(HELPER._probe_nightlight('{"enabled":false}'))
        self.assertIsNone(HELPER._probe_nightlight("not json"))
        self.assertIsNone(HELPER._probe_nightlight('{"enabled":"yes"}'))

        self.assertTrue(HELPER._tri("Mute: no", "mute: no", "mute: yes"))
        self.assertFalse(HELPER._tri("Mute: yes", "mute: no", "mute: yes"))
        self.assertIsNone(HELPER._tri("", "mute: no", "mute: yes"))
        # "enabled" is a substring of "disabled": the off answer has to win.
        self.assertFalse(HELPER._tri("disabled", "enabled", "disabled"))
        self.assertTrue(HELPER._tri("enabled\n", "enabled", "disabled"))

    def test_the_hyprland_probes_read_the_focused_window_and_workspace(self):
        self.assertTrue(HELPER._probe_fullscreen('{"fullscreenClient":2}'))
        self.assertFalse(HELPER._probe_fullscreen('{"fullscreenClient":0}'))
        # A window that reports no such field, and a hyprctl that printed
        # nothing usable, are both unknown rather than "not fullscreen".
        self.assertIsNone(HELPER._probe_fullscreen('{"address":"0x1"}'))
        self.assertIsNone(HELPER._probe_fullscreen("Invalid"))
        # With no focused window there is no target to toggle.
        self.assertIsNone(HELPER._probe_fullscreen("{}"))

        self.assertTrue(HELPER._probe_scrolling('{"tiledLayout":"scrolling"}'))
        self.assertFalse(HELPER._probe_scrolling('{"tiledLayout":"dwindle"}'))
        # A third layout is neither end of this switch.
        self.assertIsNone(HELPER._probe_scrolling('{"tiledLayout":"master"}'))
        self.assertIsNone(HELPER._probe_scrolling("[]"))

    def test_battery_percentage_reads_the_bar_entry_rather_than_a_flag(self):
        def config(home):
            path = home / ".config" / "omarchy"
            path.mkdir(parents=True, exist_ok=True)
            return path

        def write(home, *entries):
            (config(home) / "shell.json").write_text(json.dumps(
                {"bar": {"layout": {"left": [{"id": "omarchy.menu"}], "right": list(entries)}}}))

        with fake_home() as home:
            config(home)
            self.assertIsNone(HELPER._probe_battery_percent())
            write(home, {"id": "omarchy.power", "showPercentage": True})
            self.assertTrue(HELPER._probe_battery_percent())
            write(home, {"id": "omarchy.power", "showPercentage": False})
            self.assertFalse(HELPER._probe_battery_percent())
            # The bar's own default is off, so an entry that never toggled it
            # reads off rather than unknown.
            write(home, {"id": "omarchy.power"})
            self.assertFalse(HELPER._probe_battery_percent())
            # No power module in the bar: nothing for the percentage to sit on.
            write(home, {"id": "omarchy.audio", "showPercentage": True})
            self.assertIsNone(HELPER._probe_battery_percent())

    def test_a_menu_row_borrows_the_verb_its_own_command_names(self):
        # "Bluetooth" under Update > Hardware restarts the service; the
        # curated "Toggle Bluetooth" row flips the radio. Same noun, opposite
        # expectations, so the title has to carry the verb.
        self.assertEqual(
            HELPER._menu_title("Bluetooth", ["omarchy-launch-floating-terminal-with-presentation",
                                             "omarchy-restart-bluetooth"]),
            "Restart Bluetooth")
        self.assertEqual(HELPER._menu_title("Restart Audio", ["omarchy-restart-audio"]),
                         "Restart Audio")
        self.assertEqual(HELPER._menu_title("Nightlight", ["omarchy-toggle-nightlight"]),
                         "Nightlight")
        self.assertEqual(HELPER._menu_title("Anything", []), "Anything")

    def test_the_handler_survives_a_home_it_cannot_use(self):
        with mock.patch.dict(os.environ, {"HOME": "not-absolute"}):
            reply = self._states()
        self.assertEqual(reply, {})


class TldrTests(unittest.TestCase):
    PAGE = (
        "# scp\n\n> Secure copy.\n> Copy files between hosts.\n"
        "> More information: <https://man.archlinux.org/man/scp.1>.\n\n"
        "- Copy a local file to a remote host:\n\n"
        "`scp {{path/to/local_file}} {{remote_host}}:{{path/to/remote_file}}`\n\n"
        "- [r]ecursively copy a directory to `remote_host`:\n\n"
        "`scp {{[-r|--recursive]}} {{path/to/dir}} {{remote_host}}:{{path/to/dir}}`\n"
    )

    def _tldr(self, output, argv):
        calls = []
        real = HELPER.run_bounded
        HELPER.run_bounded = lambda a, cap, deadline: calls.append(a) or (output, False)
        self.addCleanup(setattr, HELPER, "run_bounded", real)
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            HELPER.cmd_tldr(argv)
        return json.loads(buf.getvalue()), calls

    def test_page_is_parsed_into_ordered_examples(self):
        reply, _ = self._tldr(self.PAGE.encode(), ["scp"])
        self.assertEqual(reply["title"], "scp")
        self.assertEqual(reply["description"], "Secure copy. Copy files between hosts.")
        self.assertEqual(reply["url"], "https://man.archlinux.org/man/scp.1")
        self.assertEqual(reply["examples"], [
            {"description": "Copy a local file to a remote host",
             "command": "scp path/to/local_file remote_host:path/to/remote_file"},
            {"description": "Recursively copy a directory to remote_host",
             "command": "scp --recursive path/to/dir remote_host:path/to/dir"},
        ])

    def test_multi_word_page_joins_and_unknown_page_is_not_found(self):
        reply, calls = self._tldr(b"`git-commit` documentation is not available.\n", ["Git Commit"])
        self.assertEqual(calls, [["tldr", "-m", "--", "git-commit"]])
        self.assertEqual((reply["page"], reply["found"]), ("git-commit", False))

    def test_bad_page_names_are_denied(self):
        for name in ["../x", "-v", "", "a b/c"]:
            with self.assertRaises(HELPER.Denied):
                HELPER.cmd_tldr([name])


class CurrencyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.home = Path(self.directory.name)
        self.cache = self.home / ".cache" / "omarchy" / HELPER.CURRENCY_CACHE_NAME
        self.now = time.time()
        self.record = {"base": "USD", "quote": "EUR", "rate": 0.9234,
                       "date": HELPER.datetime.fromtimestamp(self.now, HELPER.timezone.utc).date().isoformat(),
                       "fetchedAt": self.now}
        patch = mock.patch.dict(os.environ, {"HOME": str(self.home)})
        patch.start()
        self.addCleanup(patch.stop)
        patch = mock.patch.object(HELPER.time, "time", return_value=self.now)
        patch.start()
        self.addCleanup(patch.stop)

    def run_rate(self, args=None):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            status = HELPER.main(["currency-rate"] + (args or ["USD", "EUR"]))
        self.assertEqual(status, 0)
        return json.loads(out.getvalue())

    def test_cold_fetch_then_warm_cache_and_private_permissions(self):
        with mock.patch.object(HELPER, "currency_fetch", return_value=self.record) as fetch:
            first = self.run_rate()
            second = self.run_rate()
        fetch.assert_called_once_with("USD", "EUR")
        self.assertEqual(first, second)
        self.assertTrue(first["ok"])
        self.assertFalse(first["stale"])
        self.assertEqual(first["rate"], 0.9234)
        self.assertEqual(stat.S_IMODE(self.cache.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(self.cache.parent.stat().st_mode), 0o700)

    def test_cached_only_never_fetches_and_keeps_identity_conversions(self):
        with mock.patch.object(HELPER, "currency_fetch") as fetch:
            self.assertFalse(self.run_rate(["--cached-only", "USD", "EUR"])["ok"])
            identity = self.run_rate(["--cached-only", "EUR", "EUR"])
            self.assertEqual(identity["rate"], 1)
            HELPER.currency_store(self.record)
            cached = self.run_rate(["--cached-only", "USD", "EUR"])
            self.assertEqual(cached["rate"], self.record["rate"])
            fetch.assert_not_called()

    def test_cached_only_returns_expired_rate_without_network(self):
        expired = dict(self.record, fetchedAt=self.now - HELPER.CURRENCY_TTL)
        HELPER.currency_store(expired)
        with mock.patch.object(HELPER, "currency_fetch") as fetch:
            cached = self.run_rate(["--cached-only", "USD", "EUR"])
            fetch.assert_not_called()
        self.assertTrue(cached["stale"])
        self.assertEqual(cached["rate"], expired["rate"])

    def test_rate_date_uses_utc_even_when_local_date_is_yesterday(self):
        now = HELPER.datetime(2026, 9, 22, 0, 30, tzinfo=HELPER.timezone.utc).timestamp()
        record = dict(self.record, date="2026-09-22", fetchedAt=now)
        try:
            with mock.patch.dict(os.environ, {"TZ": "Etc/GMT+7"}):
                time.tzset()
                self.assertEqual(HELPER.currency_record(record, now), record)
        finally:
            time.tzset()

    def test_invalid_cached_timestamps_are_not_trusted(self):
        for stamp in [True, -1, 0, "1", self.now + 1, float("nan"), float("inf")]:
            self.assertIsNone(HELPER.currency_record(dict(self.record, fetchedAt=stamp), self.now))

    def test_expired_rate_refreshes_and_failure_keeps_original_date_and_timestamp(self):
        expired = dict(self.record, fetchedAt=self.now - HELPER.CURRENCY_TTL)
        HELPER.currency_store(expired)
        original = self.cache.read_bytes()
        with mock.patch.object(HELPER, "currency_fetch", side_effect=TimeoutError):
            response = self.run_rate()
        self.assertTrue(response["ok"])
        self.assertTrue(response["stale"])
        self.assertEqual(response["date"], expired["date"])
        self.assertEqual(response["fetchedAt"], expired["fetchedAt"])
        self.assertEqual(self.cache.read_bytes(), original)
        with mock.patch.object(HELPER, "currency_fetch", return_value=self.record) as fetch:
            self.assertFalse(self.run_rate()["stale"])
        fetch.assert_called_once()
        self.assertEqual(HELPER.currency_cached("USD", "EUR", self.now), self.record)

    def test_cold_offline_failure_is_one_normalized_error(self):
        with mock.patch.object(HELPER, "currency_fetch", side_effect=OSError("offline")):
            self.assertEqual(self.run_rate(), {"ok": False, "error": "currency rate unavailable"})

    def test_same_currency_never_fetches(self):
        with mock.patch.object(HELPER, "currency_fetch") as fetch:
            response = self.run_rate(["USD", "USD"])
        fetch.assert_not_called()
        self.assertEqual(response["rate"], 1)
        self.assertFalse(self.cache.exists())

    def test_invalid_arguments_never_reach_network(self):
        with mock.patch.object(HELPER, "currency_fetch") as fetch:
            for args in [["usd", "EUR"], ["USD/../../", "EUR"], ["USD"],
                         ["USD", "EUR", "100"], ["USD", "EUR\n"], ["€", "USD"]]:
                self.assertFalse(self.run_rate(args)["ok"])
        fetch.assert_not_called()

    def test_bad_cache_is_ignored_and_write_failure_preserves_fetched_answer(self):
        self.cache.parent.mkdir(parents=True)
        for data in [b"{", b"[]", b'{"version":2,"rates":[]}', b"x" * (HELPER.CURRENCY_CACHE_BYTES + 1)]:
            self.cache.write_bytes(data)
            with mock.patch.object(HELPER, "currency_fetch", return_value=self.record):
                response = self.run_rate()
            self.assertTrue(response["ok"])
            self.assertEqual(response["rate"], self.record["rate"])
        self.cache.unlink()
        with mock.patch.object(HELPER, "currency_fetch", return_value=self.record), \
                mock.patch.object(HELPER, "write_atomic", side_effect=OSError("disk full")):
            self.assertTrue(self.run_rate()["ok"])

    def test_unsafe_cache_file_and_directory_are_never_written(self):
        self.cache.parent.mkdir(parents=True)
        victim = self.home / "victim"
        victim.write_text("untouched")
        self.cache.symlink_to(victim)
        with mock.patch.object(HELPER, "currency_fetch", return_value=self.record):
            self.assertTrue(self.run_rate()["ok"])
        self.assertTrue(self.cache.is_symlink())
        self.assertEqual(victim.read_text(), "untouched")
        self.cache.unlink()
        self.cache.parent.chmod(0o777)
        with mock.patch.object(HELPER, "currency_fetch", return_value=self.record):
            self.assertTrue(self.run_rate()["ok"])
        self.assertFalse(self.cache.exists())

    def test_cache_merges_pairs_and_evicts_oldest_fetches(self):
        for i in range(HELPER.CURRENCY_CACHE_KEEP + 2):
            code = "A" + chr(65 + i // 26) + chr(65 + i % 26)
            HELPER.currency_store(dict(self.record, quote=code, fetchedAt=self.now - 200 + i))
        cached = json.loads(self.cache.read_text())
        self.assertEqual(len(cached["rates"]), HELPER.CURRENCY_CACHE_KEEP)
        self.assertLess(self.cache.stat().st_size, HELPER.CURRENCY_CACHE_BYTES)
        self.assertIsNone(HELPER.currency_cached("USD", "AAA", self.now))
        self.assertIsNotNone(HELPER.currency_cached("USD", "AEZ", self.now))

    def test_busy_cache_lock_does_not_block_success(self):
        self.cache.parent.mkdir(parents=True)
        fd = os.open(self.cache.parent, os.O_RDONLY | os.O_DIRECTORY)
        lock = HELPER.lock_at(fd, "spotlight-currency.lock")
        try:
            with mock.patch.object(HELPER, "currency_fetch", return_value=self.record):
                self.assertTrue(self.run_rate()["ok"])
            self.assertFalse(self.cache.exists())
        finally:
            os.close(lock)
            os.close(fd)

    def test_network_contract_is_fixed_bounded_and_rejects_redirects(self):
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.read.return_value = json.dumps(self.record).encode()
        opener = mock.Mock()
        opener.open.return_value = response
        with mock.patch("urllib.request.build_opener", return_value=opener) as build:
            record = HELPER.currency_fetch("USD", "EUR")
        self.assertEqual(record, self.record)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.frankfurter.dev/v2/rate/usd/eur")
        self.assertEqual(opener.open.call_args.kwargs["timeout"], HELPER.CURRENCY_DEADLINE)
        response.read.assert_called_once_with(HELPER.CURRENCY_BYTES + 1)
        handler = build.call_args.args[0]()
        self.assertIsNone(handler.redirect_request(None, None, 302, "", {}, "http://localhost/"))

    def test_bad_network_responses_cannot_replace_an_expired_rate(self):
        expired = dict(self.record, fetchedAt=self.now - HELPER.CURRENCY_TTL)
        HELPER.currency_store(expired)
        original = self.cache.read_bytes()
        invalid = [dict(self.record, rate=v) for v in [0, -1, "1", True, float("nan"), float("inf")]]
        invalid += [dict(self.record, base="GBP"), dict(self.record, quote="JPY"),
                    dict(self.record, date="2026-02-30"), dict(self.record, date="9999-12-31"), [], {}]
        bodies = [json.dumps(value).encode() for value in invalid]
        bodies += [b"not json", b"\xff", b" " * (HELPER.CURRENCY_BYTES + 1)]
        for body in bodies:
            with self.subTest(body=body[:100]):
                response = mock.MagicMock()
                response.__enter__.return_value = response
                response.read.return_value = body
                opener = mock.Mock()
                opener.open.return_value = response
                with mock.patch("urllib.request.build_opener", return_value=opener):
                    result = self.run_rate()
                self.assertTrue(result["stale"])
                self.assertEqual(result["rate"], expired["rate"])
                self.assertEqual(self.cache.read_bytes(), original)

    def test_http_errors_preserve_cached_fallback(self):
        from urllib.error import HTTPError
        from http.client import IncompleteRead
        HELPER.currency_store(dict(self.record, fetchedAt=self.now - HELPER.CURRENCY_TTL))
        for error in [HTTPError("", 404, "missing pair", {}, None),
                      HTTPError("", 429, "rate limited", {}, None), IncompleteRead(b"")]:
            with mock.patch("urllib.request.build_opener", side_effect=error):
                self.assertTrue(self.run_rate()["stale"])
            if isinstance(error, HTTPError):
                error.close()

    def test_total_deadline_interrupts_a_stalled_reader_and_restores_alarm(self):
        import signal
        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.read.side_effect = lambda *_: time.sleep(2)
        opener = mock.Mock()
        opener.open.return_value = response
        previous = signal.getsignal(signal.SIGALRM)
        start = time.monotonic()
        with mock.patch.object(HELPER, "CURRENCY_DEADLINE", 0.03), \
                mock.patch("urllib.request.build_opener", return_value=opener):
            self.assertFalse(self.run_rate()["ok"])
        self.assertLess(time.monotonic() - start, 1)
        self.assertEqual(signal.getsignal(signal.SIGALRM), previous)
        self.assertEqual(signal.getitimer(signal.ITIMER_REAL), (0.0, 0.0))


if __name__ == "__main__":
    unittest.main()
