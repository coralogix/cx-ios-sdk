# Crash lab

A manual verification kit for crash capture. It crashes the demo app in every way we know of on an iOS simulator. The crashes go to a **real Coralogix environment** (the crash lab's EU1 environment), and each case is judged by what Coralogix stores and what its UI shows.

The unit and UI tests check that the SDK catches a crash and builds the right payload. The lab answers the other half: does the backend accept it, attribute it and show it right? Run it by hand before a release or after a backend change. When it finds an SDK bug, also add a test for it, so CI keeps it fixed.

The lab mirrors the Android SDK's: same case schema, run-directory layout, manifest and verdict shapes, and report, so runs on the two platforms compare.

## What's here

| Path | What it is |
|---|---|
| `Example/Shared/Resources/crash-lab/cases.json` | Every case: `id`, `section`, `title`, `expect` (what must hold), `steps`, and optionally `trigger`, `requires`, `status`, `covered_by`, `note`, `source` |
| `tool/crash-lab/run_crash_lab.py` | Driver: runs cases on a simulator through `xcrun simctl` and records what happened |
| `tool/crash-lab/report.py` | Builds `report.html` from a run directory |

A case with `status: covered_elsewhere` is checked by automated tests and isn't run; `out_of_scope` gives its reason; `manual` is run by hand (see [Manual cases](#manual-cases)).

## Setup

1. **Key.** Export the crash lab environment's public key as `CX_CRASH_LAB_PUBLIC_KEY` before running the driver; it writes it into the app's `crash_lab.json` (`publicKey`) for every case that reports to `eu1-crash-lab`. Never commit it. Without it the app keeps the key from the git-ignored `Example/envs.swift`, which belongs to the demo app's own environment.
2. **Simulator.** Boot one (`xcrun simctl boot "iPhone 16"` or from Xcode). The driver uses the booted simulator, or `--udid`.
3. **Build the demo app for the simulator:**
   ```bash
   xcodebuild build -workspace Example/DemoApp.xcworkspace -scheme DemoAppSwift \
     -destination "platform=iOS Simulator,name=iPhone 16"
   ```
   Use `-scheme DemoAppSwiftUI` for the SwiftUI app. The driver installs the newest simulator build of that app under `~/Library/Developer/Xcode/DerivedData`, or the one `--app-path` names. Don't run the app from Xcode during a run: an attached debugger catches the crash before the SDK does.
4. **Network.** The simulator shares the host's network. The driver checks that the host reaches the EU1 ingress before it starts.

### Launch settings

The lab's settings are a JSON file the app reads at launch: `Library/Application Support/crash_lab.json` in its data container (`xcrun simctl get_app_container <udid> <bundle> data`). A missing key means its default, the demo app's normal behaviour.

| Key | Values |
|---|---|
| `coralogixEnv` | `null` (the demo app's own environment), `"eu1-crash-lab"` |
| `sdkDebug` | on puts every upload and the server's answer in the log |
| `crashBeforeInit` | `"exception"`, `"signal"` (next launch only) |
| `launchAction`, `launchActionCount` | right after init: `"exception"`, `"signal"`, `"cxx"` or `"hang"`, repeated for 1, 3 or 12 launches |
| `sessionSampleRate`, `errorInstrumentation`, `anrInstrumentation` | 100/0, on/off, on/off |
| `ignoreErrors` | `"SIGSEGV.*"`, `"NSInvalidArgumentException:.*"`, `"ANR"` |
| `crashBeforeSend` | `"keep"`, `"drop"`, `"edit"` |
| `tracesExporter`, `sessionReplay`, `globalSpan`, `hybridBeforeSend` | on/off |
| `appVersion` | `null` (the build's), `"crashlab-old"`, `"crashlab-new"` |
| `endpoint` | `null`, `"mock"` (see [Mock endpoint](#mock-endpoint)) |

Every case the driver runs starts from `coralogixEnv = eu1-crash-lab`, `sdkDebug = true` and `anrInstrumentation = true`, and adds the case's own `Set <key> = <value>` steps. A `Set` after a step that mentions relaunching, or one that sets a key a second time, applies to the relaunch instead (for example `appVersion` old for the crash, new for the relaunch).

For a manual run, set `coralogixEnv` first, otherwise events go to the demo app's own environment.

## Running

```bash
python3 tool/crash-lab/run_crash_lab.py
```

| Flag | Does |
|---|---|
| `--only N1,J1` | runs these cases |
| `--section native` | runs one section (names as in `cases.json`) |
| `--udid <udid>` | picks the simulator. Default: the booted one |
| `--app swift\|swiftui` | the UIKit (`com.coralogix.DemoAppSwift`) or SwiftUI (`com.coralogix.DemoAppSwiftUI`) demo app. Default `swift` |
| `--app-path <path.app>` | the build to install. Default: the newest in DerivedData |
| `--no-reinstall` | keeps the installed app and its stored data between cases |
| `--out <dir>` | the run directory. Re-running into the same directory adds to its manifest |
| `--mock-endpoint <url>` | runs the cases that need a mock upload server against it |
| `--settle <s>` | how long the relaunch runs before the app is backgrounded. Default 20 |
| `--crash-timeout <s>`, `--hang-wait <s>`, `--background-wait <s>` | how long to wait for a crash, how long a hang lasts before the app is terminated, how long to keep logging after backgrounding. Defaults 30, 8, 10 |

For each case the driver:

1. Uninstalls and reinstalls the app, so the case starts from fresh state and gets sessions of its own.
2. Starts a `log stream` of the lab's and the SDK's lines.
3. Writes the case's settings.
4. Launches the app, with `-crashLabCase <id>` when the case has a `trigger`; the app runs that case right after SDK init. A case without a trigger is driven by its settings alone. A repeated launch action launches once per repetition.
5. Waits for the process to exit. A hang case is terminated after `--hang-wait` seconds instead.
6. Relaunches without a case, so the SDK sends what it stored, and waits `--settle` seconds.
7. Takes a screenshot, backgrounds the app by opening Settings, waits `--background-wait` seconds and stops the log.

It doesn't judge anything.

The run directory, by default `~/.claude/verify-runs/<date>-crash-lab-ios<runtime>/`, holds:

| File | Has |
|---|---|
| `manifest.json` | simulator, build, SDK version, git commit, and per case: status, settings, each step with its timestamp, sessions seen |
| `logs/<id>.log` | the lab's and the SDK's log lines |
| `screens/<id>.png` | the screen before the app was backgrounded |
| `verdicts/<id>.json` | written by whoever verifies the case |

The app logs `[CrashLab] launch session=<id>` after each init. Those session ids and the step timestamps in `manifest.json` are what you look up in Coralogix.

### Mock endpoint

Cases with `requires: mock_endpoint` check server answers Coralogix never gives on demand. Start a mock upload server on the host, then:

```bash
python3 tool/crash-lab/run_crash_lab.py --mock-endpoint http://127.0.0.1:8080
```

For those cases the driver sets `endpoint = mock` and launches the app with `CX_MOCK_PORT` set, and the app sends to `http://127.0.0.1:<port>`. Without the flag they are recorded as not run.

### Manual cases

The driver records these as not run, with the reason. Run them by hand and write their verdicts the same way.

| `requires` | Why the simulator can't run it |
|---|---|
| `device` | the behaviour differs on hardware: memory limits, the system watchdog, real signal delivery, or symbolication of a release build |
| `xcode` | the case is about a debugger being attached, which takes over the crash before the SDK |
| `network_link_conditioner` | it needs a degraded network, which the Network Link Conditioner gives a device or the host |

## Verifying in Coralogix

Check each case against its `expect` list in `cases.json`. Every line must hold. Write down what you saw, not what you expected.

Open the crash lab's EU1 team, RUM, and filter the session list to the session id from the manifest. In the session's **Errors** tab, open the error: **Stack Trace** shows the frames, and **Event** shows the raw JSON (`error_context`, `threads`, `is_crash`). For many events at once, use Explore with the `rum.events` dataset, filtered to the case's time window from `manifest.json`.

Traps:

- **Time.** The UI shows your browser's local time; the manifest is UTC. Always set the time window.
- **Ingestion lag.** Events can take a few minutes to show up. Re-run the query before calling an event missing.
- **Count the sends.** Before calling a duplicate an SDK bug, count the uploads in the case's log (SDK debug logging is on).

### Recording a verdict

For each case, write `verdicts/<id>.json` in the run directory:

```json
{
  "verdict": "PASS",
  "summary": "one sentence",
  "checks": [{"expect": "<a line from the case's expect list>", "ui": "what Coralogix showed", "held": true}],
  "evidence": [{"label": "Stack trace", "file": "evidence/N1-stack.png"}, {"label": "Session", "url": "<link to the session>"}]
}
```

| Verdict | When |
|---|---|
| `PASS` | every `expect` line held |
| `FAIL` | at least one was contradicted by what you saw |
| `INCONCLUSIVE` | something couldn't be checked: the data didn't arrive, a page wouldn't load. Never round it up to PASS. |

Keep screenshots under `evidence/`, because Coralogix links expire with data retention. Optional extras:
- `findings.json`: `[{"title", "detail", "cases": [ids]}]`, listed first in the report.
- `appendix.json`: `[{"id", "title", "detail", "excerpts": [{"file", "lines", "code"}]}]`.
- A verdict can also carry `reproduce` (steps) and `query` (the DataPrime used).

## Report

```bash
python3 tool/crash-lab/report.py <run-dir>
```

`report.html` lands in the run directory. It counts verdicts and lists every case by section, with its checks and evidence. Cases the driver ran but nobody judged read **Ran, not verified**; cases it didn't get to read **Not run on this simulator**. Screenshots and text evidence are embedded, so the file can be shared on its own.
