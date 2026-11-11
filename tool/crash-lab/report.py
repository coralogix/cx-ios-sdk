#!/usr/bin/env python3
"""Builds report.html for a crash lab run: every case with its verdict and evidence.

  python3 report.py <run-dir>

Reads the case list (cases.json), the driver's manifest.json, and verdicts/<id>.json, which
verification writes per case:

  {
    "verdict": "PASS" | "FAIL" | "INCONCLUSIVE",
    "summary": "one sentence",
    "checks": [{"expect": "...", "ui": "what the Coralogix UI showed", "held": true}],
    "evidence": [{"label": "Error details", "file": "evidence/N1-error.png"} | {"label": "...", "url": "https://..."}],
  }

File paths are relative to the run dir. Evidence is embedded (screenshots as data URIs, text as
<pre>), so report.html can be shared on its own; the simulator runs' logs and final screen are not.
An optional findings.json in the run dir, [{"title", "detail", "cases": [ids]}], is listed first.
"""
import base64
import html
import json
import mimetypes
import sys
from pathlib import Path

CASES = Path(__file__).resolve().parents[2] / "Example/Shared/Resources/crash-lab/cases.json"
# Titles for the sections cases.json uses; a section missing here is listed under its own name,
# so a new one never drops out of the report.
SECTIONS = {"native": "Signals and Mach exceptions", "exception": "Objective-C and Swift exceptions",
            "cxx": "C++ exceptions", "pre_init": "Crashes before SDK init", "anr": "Hangs (ANR)",
            "delivery": "Delivery", "options": "Options and sampling", "attribution": "Attribution",
            "negative": "Negative controls", "symbolication": "Symbolicated stacks (dSYM)",
            "hybrid": "Hybrid (React Native, Flutter)"}
# Verdicts verification gives, then statuses the driver records for cases it did not run.
ORDER = ["FAIL", "INCONCLUSIVE", "UNVERIFIED", "PASS", "NOT_RUN", "COVERED_ELSEWHERE", "MANUAL", "OUT_OF_SCOPE"]
LABELS = {"UNVERIFIED": "Ran, not verified", "NOT_RUN": "Not run on this simulator", "COVERED_ELSEWHERE": "PASS on CI",
          "MANUAL": "Manual", "OUT_OF_SCOPE": "Out of scope"}
# Statuses meaning "the simulator runs this case": a case absent from the manifest with one of these never ran.
RUNNABLE = (None, "device", "simulator")


def esc(value):
    return html.escape(str(value)) if value is not None else ""


def verdict_of(case, run, verdict):
    if verdict:
        return verdict["verdict"]
    if run and run.get("same_run_as"):
        return "UNVERIFIED"
    status = (run or {}).get("status") or case.get("status")
    if status in ("ran", "driver_error"):
        return "UNVERIFIED"
    if status in RUNNABLE:
        return "NOT_RUN"
    return status.upper()


def evidence_html(items, run_dir):
    out = []
    for item in items:
        label = esc(item.get("label", ""))
        if item.get("file"):
            path = run_dir / item["file"]
            kind = mimetypes.guess_type(path.name)[0] or ""
            if kind.startswith("image/"):
                src = f"data:{kind};base64,{base64.b64encode(path.read_bytes()).decode()}"
                out.append(f'<figure class="wide"><img src="{src}" alt="{label}" loading="lazy"><figcaption>{label}</figcaption></figure>')
            else:
                out.append(f'<figure class="wide"><pre>{esc(path.read_text(errors="replace"))}</pre><figcaption>{label}</figcaption></figure>')
        elif item.get("url"):
            out.append(f'<p class="link"><a href="{esc(item["url"])}">{label or esc(item["url"])}</a></p>')
    return "".join(out)


def check_row(check, with_data):
    data = f"<td>{esc(check.get('data'))}</td>" if with_data else ""
    held = "✅" if check.get("held") else "❌" if check.get("held") is False else "—"
    return f'<tr><td>{esc(check.get("expect"))}</td>{data}<td>{esc(check.get("ui"))}</td><td class="held">{held}</td></tr>'


def case_html(case, run, verdict, state, run_dir):
    run = run or {}
    verdict = verdict or {}
    # Runs verify in the UI only; a data column shows up only when a verdict carries query results.
    with_data = any(c.get("data") for c in verdict.get("checks", []))
    checks = "".join(check_row(c, with_data) for c in verdict.get("checks", []))
    expect = "".join(f"<li>{esc(e)}</li>" for e in case["expect"])
    sessions = "".join(f'<li><code>{esc(s["session_id"])}</code> · {esc(s["event"])}</li>' for s in run.get("sessions", []))
    steps = "".join(
        f'<li><code>{esc(json.dumps(s["step"]))}</code> <span class="muted">{esc(s["at"])}'
        f'{" · died" if s.get("died") else ""}{" · alive" if s.get("alive") else ""}'
        f'{" · terminated" if s.get("terminated") else ""}</span></li>'
        for s in run.get("steps", []))
    note = run.get("reason") or case.get("note") or case.get("covered_by") or ""
    if run.get("same_run_as"):
        note = f"Checked on {run['same_run_as']}'s run."
    if run.get("error"):
        note = f"Driver error: {run['error']}"
    parts = [
        f'<details class="case" data-state="{state}" id="{esc(case["id"])}"{" open" if state in ("FAIL", "INCONCLUSIVE") else ""}>',
        f'<summary><span class="badge {state}">{esc(LABELS.get(state, state))}</span>'
        f'<span class="cid">{esc(case["id"])}</span><span class="title">{esc(case["title"])}</span></summary>',
        '<div class="body">',
        f'<p class="summary">{esc(verdict.get("summary"))}</p>' if verdict.get("summary") else "",
        f'<p class="note">{esc(note)}</p>' if note else "",
        f"<h4>Expected</h4><ul>{expect}</ul>",
        # What this case needed beyond the default driver run (Appendix B), so someone else can repeat it.
        f'<h4>How to reproduce</h4><ol>{"".join(f"<li>{esc(r)}</li>" for r in verdict["reproduce"])}</ol>' if verdict.get("reproduce") else "",
        f'<h4>Checks</h4><table><thead><tr><th>Expectation</th>{"<th>Data</th>" if with_data else ""}<th>Seen in Coralogix</th><th></th></tr></thead><tbody>{checks}</tbody></table>' if checks else "",
        f'<h4>Evidence</h4><div class="evidence">{evidence_html(verdict.get("evidence", []), run_dir)}</div>' if verdict.get("evidence") else "",
        f'<h4>Query</h4><pre>{esc(verdict["query"])}</pre>' if verdict.get("query") else "",
        f"<h4>Sessions</h4><ul>{sessions}</ul>" if sessions else "",
        # No links to the run folder's raw files: the page is sent on its own, so it carries only what it embeds.
        f'<details class="run"><summary>Simulator run</summary><ol>{steps}</ol></details>' if steps else "",
        "</div></details>",
    ]
    return "".join(parts)


def main():
    run_dir = Path(sys.argv[1]).expanduser()
    manifest = json.loads((run_dir / "manifest.json").read_text())
    cases = json.loads(CASES.read_text())
    verdicts = {p.stem: json.loads(p.read_text()) for p in (run_dir / "verdicts").glob("*.json")}

    states = {c["id"]: verdict_of(c, manifest["cases"].get(c["id"]), verdicts.get(c["id"])) for c in cases}
    counts = {s: sum(1 for v in states.values() if v == s) for s in ORDER}
    device = manifest["device"]
    # The driver records every case it settles, skipped for its device included; one it never got to is
    # missing from the manifest, and keeps the run from PASS.
    never_run = [i for i, s in states.items() if s == "NOT_RUN" and i not in manifest["cases"]]
    overall = "FAIL" if counts["FAIL"] else "INCONCLUSIVE" if counts["INCONCLUSIVE"] or counts["UNVERIFIED"] or never_run else "PASS"

    findings_file = run_dir / "findings.json"
    findings = json.loads(findings_file.read_text()) if findings_file.exists() else []
    findings_html = (
        '<section class="findings"><h2>Findings</h2><ol>' + "".join(
            f'<li><b>{esc(f["title"])}</b> {esc(f["detail"])} '
            + " ".join(f'<a href="#{esc(i)}">{esc(i)}</a>' for i in f.get("cases", [])) + "</li>"
            for f in findings) + "</ol></section>") if findings else ""
    # Optional appendix.json: [{id, title, detail, excerpts: [{file, lines, code}]}], e.g. code another repo's behaviour rests on.
    appendix_file = run_dir / "appendix.json"
    appendix = json.loads(appendix_file.read_text()) if appendix_file.exists() else []
    appendix_html = "".join(
        f'<section class="appendix" id="{esc(a["id"])}"><h2>{esc(a["title"])}</h2><p>{esc(a["detail"])}</p>' + "".join(
            f'<h4>{esc(x["file"])}{":" + esc(x["lines"]) if x.get("lines") else ""}</h4><pre>{esc(x["code"])}</pre>'
            + (f'<p class="note">{esc(x["note"])}</p>' if x.get("note") else "")
            for x in a.get("excerpts", [])) + "</section>"
        for a in appendix)
    tiles = "".join(f'<button class="tile {s}" data-filter="{s}"><b>{counts[s]}</b>{esc(LABELS.get(s, s.title()))}</button>'
                    for s in ORDER if counts[s])
    sections = list(dict.fromkeys([key for key in SECTIONS if any(c["section"] == key for c in cases)]
                                  + [c["section"] for c in cases]))
    body = "".join(
        f'<section><h2>{esc(SECTIONS.get(key, key.replace("_", " ").capitalize()))}</h2>' + "".join(
            case_html(c, manifest["cases"].get(c["id"]), verdicts.get(c["id"]), states[c["id"]], run_dir) for c in cases if c["section"] == key
        ) + "</section>"
        for key in sections)

    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>iOS Crash Lab</title>
<style>
:root {{ --bg:#f7f7f5; --card:#fff; --ink:#1d1d1b; --muted:#6b6b66; --line:#e2e2dd;
  --pass:#1f7a4d; --fail:#b42318; --warn:#a15c07; --info:#3b5bdb; --quiet:#6b6b66; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#141413; --card:#1e1e1c; --ink:#ecece8;
  --muted:#9a9a93; --line:#33332f; --pass:#4cc38a; --fail:#f97066; --warn:#f5b041; --info:#8fa8ff; --quiet:#9a9a93; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:15px/1.5 system-ui,-apple-system,sans-serif; }}
main {{ max-width:1100px; margin:0 auto; padding:24px 16px 64px; }}
h1 {{ font-size:26px; margin:0 0 4px; }} h2 {{ font-size:18px; margin:32px 0 8px; }} h4 {{ margin:14px 0 4px; font-size:13px; text-transform:uppercase; letter-spacing:.04em; color:var(--muted); }}
.meta {{ color:var(--muted); margin:0 0 16px; }}
.overall {{ font-weight:700; }} .overall.PASS {{ color:var(--pass); }} .overall.FAIL {{ color:var(--fail); }} .overall.INCONCLUSIVE {{ color:var(--warn); }}
.tiles {{ display:flex; flex-wrap:wrap; gap:8px; margin:16px 0; }}
.tile {{ background:var(--card); border:1px solid var(--line); border-radius:10px; padding:8px 12px; color:var(--ink); font:inherit; cursor:pointer; text-align:left; }}
.tile b {{ display:block; font-size:22px; }} .tile.active {{ outline:2px solid var(--info); }}
.case {{ background:var(--card); border:1px solid var(--line); border-radius:10px; margin:6px 0; }}
.case > summary {{ display:flex; gap:10px; align-items:center; padding:10px 12px; cursor:pointer; list-style:none; }}
.cid {{ font-weight:700; min-width:3.2em; }} .title {{ flex:1; }}
.body {{ padding:0 14px 14px; border-top:1px solid var(--line); }}
.badge {{ font-size:12px; font-weight:700; border-radius:999px; padding:2px 8px; white-space:nowrap; border:1px solid currentColor; }}
.PASS {{ color:var(--pass); }} .FAIL {{ color:var(--fail); }} .INCONCLUSIVE, .UNVERIFIED {{ color:var(--warn); }}
.NOT_RUN, .COVERED_ELSEWHERE, .MANUAL, .OUT_OF_SCOPE {{ color:var(--quiet); }}
table {{ width:100%; border-collapse:collapse; font-size:14px; }} th, td {{ text-align:left; vertical-align:top; padding:6px; border-bottom:1px solid var(--line); }}
td.held {{ width:2em; text-align:center; }}
.evidence {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(220px,1fr)); gap:10px; }}
figure {{ margin:0; }} figure.wide {{ grid-column:1/-1; }} .findings li {{ margin:6px 0; }} img {{ width:100%; border:1px solid var(--line); border-radius:6px; }} figcaption {{ font-size:13px; color:var(--muted); }}
pre {{ white-space:pre-wrap; background:var(--bg); padding:8px; border-radius:6px; font-size:13px; overflow-x:auto; }}
code {{ font-size:13px; word-break:break-all; }} .muted, .note {{ color:var(--muted); }} .summary {{ font-weight:600; }}
a {{ color:var(--info); }}
</style></head><body><main>
<h1>iOS Crash Lab</h1>
<p class="meta">Verdict: <span class="overall {overall}">{overall}</span> · {esc(device["name"])} simulator, iOS {esc(device["runtime"])} ({esc(device["arch"])})
 · app {esc(manifest["app"])} {esc(device["app_version"])}{" (" + esc(device["configuration"]) + ")" if device.get("configuration") else ""}
 · SDK {esc(device.get("sdk_version"))} · {esc(manifest["region"])}{" + mock endpoint" if manifest.get("mock_endpoint") else ""}
 · commit <code>{esc(device["git_commit"][:10])}</code>{" + local changes" if device.get("git_dirty") else ""}</p>
<div class="tiles">{tiles}</div>
{findings_html}
{body}
{appendix_html}
</main>
<script>
document.querySelectorAll('.tile').forEach(tile => tile.addEventListener('click', () => {{
  const on = !tile.classList.contains('active');
  document.querySelectorAll('.tile').forEach(t => t.classList.remove('active'));
  if (on) tile.classList.add('active');
  document.querySelectorAll('.case').forEach(c => c.style.display = !on || c.dataset.state === tile.dataset.filter ? '' : 'none');
}}));
</script>
</body></html>"""
    (run_dir / "report.html").write_text(page)
    print(run_dir / "report.html")


if __name__ == "__main__":
    main()
