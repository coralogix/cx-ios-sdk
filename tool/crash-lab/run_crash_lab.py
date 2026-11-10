#!/usr/bin/env python3
"""Runs the crash lab's cases on an iOS simulator and records what each one needs to be verified.

Reads Example/Shared/Resources/crash-lab/cases.json, the same file the demo app's lab lists. For each
case it reinstalls the app (fresh state), writes the case's launch settings into the app's container,
launches it with the case (`-crashLabCase <id>`), waits for the crash or ends a hang, relaunches so
the SDK sends what it stored, backgrounds the app, and writes, under the run directory:

  manifest.json      simulator, build, and per case: status, steps with timestamps, sessions seen
  logs/<id>.log      the lab's and the SDK's log lines (`log stream`, compact style)
  screens/<id>.png   the screen before the app was backgrounded

It judges nothing: verification reads the manifest afterwards and writes verdicts/<id>.json next to
it; report.py turns the lot into report.html.

Build the demo app for the simulator first (see README.md); the driver installs the newest build it
finds in DerivedData, or --app-path.
"""
import argparse
import datetime
import json
import os
import platform
import plistlib
import re
import socket
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

REPO = Path(__file__).resolve().parents[2]
CASES = REPO / "Example/Shared/Resources/crash-lab/cases.json"
SDK_VERSION_FILE = REPO / "CoralogixInternal/Sources/Utils.swift"
APPS = {  # --app: bundle id and Xcode scheme (workspace Example/DemoApp.xcworkspace)
    "swift": {"bundle": "com.coralogix.DemoAppSwift", "scheme": "DemoAppSwift"},
    "swiftui": {"bundle": "com.coralogix.DemoAppSwiftUI", "scheme": "DemoAppSwiftUI"},
}
DERIVED_DATA = Path("~/Library/Developer/Xcode/DerivedData").expanduser()
SETTINGS_RELATIVE = Path("Library/Application Support/crash_lab.json")
BACKGROUND_APP = "com.apple.Preferences"
INGRESS_HOST = "ingress.eu1.rum-ingress-coralogix.com"
LOG_PREDICATE = 'eventMessage CONTAINS "[CrashLab]" OR subsystem == "com.coralogix.rum"'

# Every case starts from these, so a hang case and a crash case run under the same configuration.
# Runs report to the crash lab's EU1 environment (its key is in Example/envs.swift, never committed).
# SDK debug logging puts each upload and the server's answer in the case's log.
BASE_SETTINGS = {"coralogixEnv": "eu1-crash-lab", "sdkDebug": True, "anrInstrumentation": True}
PUBLIC_KEY_ENV = "CX_CRASH_LAB_PUBLIC_KEY"
# Hangs the process must end during: the driver terminates the app after --hang-wait seconds.
HANG_CASES = {"A1", "A2", "A5", "A6", "A7", "A8", "A9"}
# Statuses and requirements the simulator cannot run; recorded in the manifest as not run.
SKIP_STATUSES = {"out_of_scope", "covered_elsewhere", "manual"}
MANUAL_REQUIREMENTS = {
    "device": "needs a physical device",
    "xcode": "needs the Xcode debugger attached",
    "network_link_conditioner": "needs the Network Link Conditioner",
}
SET_LINE = re.compile(r"^\s*Set\s+(\w+)\s*=\s*(.+?)\s*$")
RELAUNCH_LINE = re.compile(r"\brelaunch", re.IGNORECASE)
SESSION_LINE = re.compile(r"\[CrashLab\] (launch|case=\S+) session=(\S+)")
LOG_TIMESTAMP = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d+)")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="milliseconds")


def run(*cmd, check=True, timeout=120, env=None):
    result = subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout, env=env)
    if check and result.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}: {(result.stderr or result.stdout).strip()}")
    return result.stdout.strip()


class Simulator:
    def __init__(self, udid, bundle, mock_port=None):
        self.udid = udid
        self.bundle = bundle
        self.mock_port = mock_port
        self.pid = None
        self.log_stream = None

    def simctl(self, *args, check=True, timeout=120, env=None):
        return run("xcrun", "simctl", *args, check=check, timeout=timeout, env=env)

    def install(self, app_path):
        self.simctl("terminate", self.udid, self.bundle, check=False)
        self.simctl("uninstall", self.udid, self.bundle, check=False)
        self.simctl("install", self.udid, str(app_path), timeout=300)

    def container(self, kind):
        return Path(self.simctl("get_app_container", self.udid, self.bundle, kind))

    def settings_path(self):
        return self.container("data") / SETTINGS_RELATIVE

    def settings(self):
        try:
            return json.loads(self.settings_path().read_text())
        except (OSError, ValueError):
            return {}

    def write_settings(self, values, merge):
        # Merged on a relaunch, so a one-shot the app already consumed stays consumed.
        merged = {**(self.settings() if merge else {}), **values}
        path = self.settings_path()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(merged))
        return merged

    def launch(self, case_id=None):
        env = dict(os.environ)
        if self.mock_port:
            env["SIMCTL_CHILD_CX_MOCK_PORT"] = str(self.mock_port)
        args = ["launch", "--terminate-running-process", self.udid, self.bundle]
        if case_id:
            args += ["-crashLabCase", case_id]
        output = self.simctl(*args, env=env)
        match = re.search(r":\s*(\d+)\s*$", output)
        self.pid = int(match.group(1)) if match else None
        return self.pid

    def alive(self):
        # Simulator apps are host processes, so the pid `simctl launch` printed can be probed directly.
        if self.pid:
            try:
                os.kill(self.pid, 0)
                return True
            except ProcessLookupError:
                return False
            except PermissionError:
                return True
        listing = self.simctl("spawn", self.udid, "launchctl", "list", check=False)
        return any(f"UIKitApplication:{self.bundle}[" in line and not line.startswith("-")
                   for line in listing.splitlines())

    def wait_until_dead(self, timeout):
        deadline = time.time() + timeout
        while time.time() < deadline:
            if not self.alive():
                return True
            time.sleep(0.5)
        return False

    def terminate(self):
        self.simctl("terminate", self.udid, self.bundle, check=False)
        return self.wait_until_dead(10)

    def background(self):
        self.simctl("launch", self.udid, BACKGROUND_APP, check=False)

    def screenshot(self, path):
        self.simctl("io", self.udid, "screenshot", str(path), check=False, timeout=60)

    def start_log(self, path):
        self.log_file = path.open("w")
        self.log_stream = subprocess.Popen(
            ["xcrun", "simctl", "spawn", self.udid, "log", "stream", "--style", "compact", "--level", "debug",
             "--predicate", LOG_PREDICATE],
            stdout=self.log_file, stderr=subprocess.STDOUT)
        time.sleep(2)  # `log stream` attaches a moment after it starts; a crash in that gap goes unlogged.

    def stop_log(self):
        if not self.log_stream:
            return
        self.log_stream.terminate()
        try:
            self.log_stream.wait(10)
        except subprocess.TimeoutExpired:
            self.log_stream.kill()
        self.log_file.close()
        self.log_stream = None


def booted_udid():
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "booted", "-j"))["devices"]
    booted = [d["udid"] for runtime in devices.values() for d in runtime if d.get("state") == "Booted"]
    if len(booted) != 1:
        sys.exit(f"{len(booted)} simulators booted; boot one or pass --udid")
    return booted[0]


def simulator_info(udid):
    devices = json.loads(run("xcrun", "simctl", "list", "devices", "-j"))["devices"]
    for runtime, entries in devices.items():
        for device in entries:
            if device["udid"] == udid:
                if device.get("state") != "Booted":
                    sys.exit(f"simulator {udid} is {device.get('state')}; boot it first")
                # com.apple.CoreSimulator.SimRuntime.iOS-18-5 -> 18.5
                version = re.search(r"(\d+(?:-\d+)*)$", runtime)
                return {"udid": udid, "name": device["name"], "runtime": version.group(1).replace("-", ".") if version else runtime,
                        "model": device.get("deviceTypeIdentifier", "").rsplit(".", 1)[-1]}
    sys.exit(f"no simulator {udid}")


def find_app(bundle):
    """The newest simulator build under DerivedData whose Info.plist names [bundle]."""
    builds = []
    for app in DERIVED_DATA.glob("*/Build/Products/*-iphonesimulator/*.app"):
        if read_plist(app).get("CFBundleIdentifier") == bundle:
            builds.append(app)
    if not builds:
        sys.exit(f"no simulator build of {bundle} under {DERIVED_DATA}; build it first or pass --app-path")
    return max(builds, key=lambda app: app.stat().st_mtime)


def read_plist(app):
    try:
        with (app / "Info.plist").open("rb") as file:
            return plistlib.load(file)
    except (OSError, plistlib.InvalidFileException):
        return {}


def parse_value(text):
    try:
        return json.loads(text)
    except ValueError:
        return text.strip("'\"")


def case_settings(case):
    """[crash launch settings, relaunch settings] from the case's `Set <key> = <value>` steps.

    A Set after a step that mentions relaunching, or one setting a key a second time, applies to the
    relaunch: `Set appVersion = crashlab-old`, crash, relaunch, `Set appVersion = crashlab-new`.
    """
    phases = [{}, {}]
    phase = 0
    for line in case.get("steps") or []:
        if not isinstance(line, str):
            continue
        match = SET_LINE.match(line)
        if not match:
            if RELAUNCH_LINE.search(line):
                phase = 1
            continue
        key, value = match.group(1), parse_value(match.group(2))
        target = 1 if phase or key in phases[0] else 0
        phases[target][key] = value
    return phases


def requirements(case):
    requires = case.get("requires") or []
    if isinstance(requires, str):
        return {requires}
    if isinstance(requires, dict):
        return {key for key, value in requires.items() if value}
    return set(requires)


def skip_reason(case, mock_url):
    needs = requirements(case)
    for need, reason in MANUAL_REQUIREMENTS.items():
        if need in needs:
            return "manual", reason
    if "mock_endpoint" in needs and not mock_url:
        return "not_run", "needs a mock endpoint (--mock-endpoint)"
    status = case.get("status")
    if status in SKIP_STATUSES:
        return status, case.get("note") or case.get("covered_by")
    if case.get("same_run_as"):
        return status or "simulator", case.get("note")
    return None


def crash_launches(settings):
    # A launch action repeats for launchActionCount launches; anything else crashes one launch.
    return int(settings.get("launchActionCount", 1)) if settings.get("launchAction") else 1


def is_hang(case, settings):
    return case["id"] in HANG_CASES or settings.get("launchAction") == "hang"


def sessions(lines):
    seen = []
    for line in lines:
        match = SESSION_LINE.search(line)
        if match:
            stamp = LOG_TIMESTAMP.match(line)
            seen.append({"at": stamp.group(1) if stamp else None, "event": match.group(1), "session_id": match.group(2)})
    return seen


def step(entry, description, **fields):
    record = {"step": description, "at": now(), **fields}
    entry["steps"].append(record)
    print(f"  {entry['id']}: {json.dumps(description)}", flush=True)
    return record


def run_case(sim, case, args, app_path, out):
    entry = {"id": case["id"], "started": now(), "steps": []}
    log_path = out / "logs" / f"{case['id']}.log"
    screen_path = out / "screens" / f"{case['id']}.png"
    first, relaunch = case_settings(case)
    mock = "mock_endpoint" in requirements(case)
    sim.mock_port = args.mock_port if mock else None
    first = {**BASE_SETTINGS, **({"endpoint": "mock"} if mock else {}), **first}
    # The crash lab environment's key: from the environment, never from the repo.
    if first.get("coralogixEnv") == "eu1-crash-lab" and os.environ.get(PUBLIC_KEY_ENV):
        first["publicKey"] = os.environ[PUBLIC_KEY_ENV]
    hang = is_hang(case, first)
    trigger = case.get("trigger")
    trigger_id = trigger if isinstance(trigger, str) else case["id"] if trigger else None
    try:
        if args.no_reinstall:
            sim.terminate()
        else:
            step(entry, {"install": str(app_path)})
            sim.install(app_path)
        sim.start_log(log_path)
        entry["settings"] = sim.write_settings(first, merge=False)
        step(entry, {"settings": first})
        for _ in range(crash_launches(first)):
            record = step(entry, {"launch": True, "case": trigger_id} if trigger_id else {"launch": True})
            record["pid"] = sim.launch(trigger_id)
            trigger_id = None  # Later launches of a repeated launch action run without the case.
            if hang:
                time.sleep(args.hang_wait)
                record["alive"] = sim.alive()
                record["terminated"] = sim.terminate()
            else:
                record["died"] = sim.wait_until_dead(args.crash_timeout)
        if relaunch:
            entry["relaunch_settings"] = sim.write_settings(relaunch, merge=True)
            step(entry, {"settings": relaunch})
        record = step(entry, {"launch": True})
        record["pid"] = sim.launch()
        step(entry, {"wait": args.settle})
        time.sleep(args.settle)
        record["alive"] = sim.alive()
        sim.screenshot(screen_path)
        step(entry, {"background": BACKGROUND_APP})
        sim.background()
        step(entry, {"wait": args.background_wait})
        time.sleep(args.background_wait)
        entry["status"] = "ran"
    except Exception as error:  # A broken step is that case's result, not the run's end.
        entry["status"] = "driver_error"
        entry["error"] = str(error)
    finally:
        sim.stop_log()
        sim.terminate()
    entry["ended"] = now()
    entry["log"] = str(log_path.relative_to(out))
    entry["screen"] = str(screen_path.relative_to(out)) if screen_path.exists() else None
    entry["sessions"] = sessions(log_path.read_text(errors="replace").splitlines()) if log_path.exists() else []
    return entry


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args], capture_output=True, text=True).stdout.strip()


def sdk_version():
    match = re.search(r'case sdk = "([^"]+)"', SDK_VERSION_FILE.read_text()) if SDK_VERSION_FILE.exists() else None
    return match.group(1) if match else None


def ingress_reachable():
    try:
        socket.create_connection((INGRESS_HOST, 443), timeout=5).close()
        return True
    except OSError:
        return False


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--udid", help="simulator UDID (default: the booted simulator)")
    parser.add_argument("--app", choices=sorted(APPS), default="swift", help="demo app: swift (UIKit) or swiftui. Default swift")
    parser.add_argument("--app-path", help="built .app to install (default: the newest simulator build of --app in DerivedData)")
    parser.add_argument("--no-reinstall", action="store_true", help="keep the installed app and its data between cases")
    parser.add_argument("--only", help="comma-separated case ids")
    parser.add_argument("--section", help="run one section (as in cases.json), e.g. native")
    parser.add_argument("--out", help="run directory (default: ~/.claude/verify-runs/<date>-crash-lab-ios<runtime>)")
    parser.add_argument("--mock-endpoint", metavar="URL", help="mock upload server, e.g. http://127.0.0.1:8080; runs the mock_endpoint cases against it")
    parser.add_argument("--settle", type=int, default=20, help="seconds the relaunch runs before the app is backgrounded. Default 20")
    parser.add_argument("--crash-timeout", type=int, default=30, help="seconds to wait for a triggered launch to exit. Default 30")
    parser.add_argument("--hang-wait", type=int, default=8, help="seconds a hang case hangs before the app is terminated. Default 8")
    parser.add_argument("--background-wait", type=int, default=10, help="seconds to keep logging after backgrounding. Default 10")
    args = parser.parse_args()

    args.mock_port = None
    if args.mock_endpoint:
        url = urlparse(args.mock_endpoint)
        if not url.port:
            sys.exit("--mock-endpoint needs a port, e.g. http://127.0.0.1:8080")
        args.mock_port = url.port

    app = APPS[args.app]
    udid = args.udid or booted_udid()
    info = simulator_info(udid)
    app_path = Path(args.app_path).expanduser().resolve() if args.app_path else None
    if not args.no_reinstall:
        app_path = app_path or find_app(app["bundle"])
        if read_plist(app_path).get("CFBundleIdentifier") != app["bundle"]:
            sys.exit(f"{app_path} is not {app['bundle']}")
    sim = Simulator(udid, app["bundle"])
    if args.no_reinstall:
        try:
            installed = sim.container("app")
        except RuntimeError:
            sys.exit(f"{app['bundle']} is not installed on {udid}; drop --no-reinstall")
        plist = read_plist(installed)
    else:
        plist = read_plist(app_path)
    info.update({
        "arch": platform.machine(),
        "bundle": app["bundle"],
        "scheme": app["scheme"],
        "app_path": str(app_path) if app_path else None,
        "app_version": f"{plist.get('CFBundleShortVersionString', '?')} ({plist.get('CFBundleVersion', '?')})",
        # Debug or Release, from the DerivedData products folder the build came from.
        "configuration": app_path.parent.name.split("-")[0] if app_path else None,
        "sdk_version": sdk_version(),
        "git_commit": git("rev-parse", "HEAD"),
        "git_dirty": bool(git("status", "--porcelain", "--untracked-files=no")),
    })

    out = Path(args.out or f"~/.claude/verify-runs/{datetime.date.today()}-crash-lab-ios{info['runtime']}").expanduser()
    for sub in ("logs", "screens", "verdicts"):
        (out / sub).mkdir(parents=True, exist_ok=True)
    manifest_path = out / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"cases": {}}
    manifest.update({"device": info, "platform": "ios", "app": app["scheme"], "region": "EU1",
                     "mock_endpoint": args.mock_endpoint, "base_settings": BASE_SETTINGS})

    # A simulator shares the host's network: with the ingress unreachable every upload times out
    # unseen, and every verdict would read as "not arrived".
    if not ingress_reachable():
        sys.exit(f"cannot reach {INGRESS_HOST}:443; fix the host's network first")

    cases = json.loads(CASES.read_text())
    only = set(args.only.split(",")) if args.only else None
    try:
        for case in cases:
            if (only and case["id"] not in only) or (args.section and case["section"] != args.section):
                continue
            skipped = skip_reason(case, args.mock_endpoint)
            if skipped:
                status, reason = skipped
                manifest["cases"][case["id"]] = {"id": case["id"], "status": status, "reason": reason,
                                                 "same_run_as": case.get("same_run_as")}
                continue
            print(f"{case['id']} · {case['title']}", flush=True)
            manifest["cases"][case["id"]] = run_case(sim, case, args, app_path, out)
            # Written after every case, so an interrupted run keeps what it did.
            manifest_path.write_text(json.dumps(manifest, indent=1))
    finally:
        sim.stop_log()
        manifest_path.write_text(json.dumps(manifest, indent=1))
    print(f"\nRun directory: {out}")


if __name__ == "__main__":
    sys.exit(main())
