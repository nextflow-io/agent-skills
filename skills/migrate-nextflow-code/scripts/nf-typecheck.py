#!/usr/bin/env python3
"""
nf-typecheck.py — run the Nextflow language server headlessly and report diagnostics.

`nextflow lint` only does syntax/parse checks; static type checking lives in the
Nextflow VS Code extension's language server. This script drives that same language
server over LSP (stdio JSON-RPC) without an editor, so type errors can be collected
from the command line during the static-typing migration.

What it does:
  1. Ensures the language server jar is available at
     ~/.nextflow/lsp/v26.04/language-server-all.jar (downloads the latest v26.04.x
     release from GitHub if missing).
  2. Launches it, initializes the given workspace, and pushes config so errors and
     warnings are reported.
  3. Opens one .nf (and one .config) file to trigger a full-workspace scan, then
     collects every published diagnostic.
  4. Prints diagnostics grouped by file. Exit code is 1 if any errors were found.

Type checking runs automatically on any .nf file that contains
`nextflow.enable.types = true`; this script does not enable it for you.

Usage:
    python3 nf-typecheck.py [WORKSPACE_DIR] [--json] [--paranoid]

Requires Java 17+ and network access on first run (to download the jar).
"""

import argparse
import json
import os
import subprocess
import sys
import threading
import time
import urllib.request
from pathlib import Path
from queue import Empty, Queue

LSP_DIR = Path.home() / ".nextflow" / "lsp" / "v26.04"
JAR_PATH = LSP_DIR / "language-server-all.jar"
RELEASES_API = "https://api.github.com/repos/nextflow-io/language-server/releases"

# Directories never worth scanning (large / generated).
EXCLUDE = [".git", ".nextflow", "work", ".nf-test", "node_modules", ".venv"]

# Idle window: the server debounces scans by ~1s, so treat the workspace as fully
# scanned once no new diagnostics arrive for this long. Bump for very large projects.
IDLE_SECONDS = 3.0
FIRST_DIAG_TIMEOUT = 90.0   # how long to wait for the first diagnostic
OVERALL_TIMEOUT = 300.0     # hard cap on the whole run


def _java_available() -> bool:
    try:
        subprocess.run(["java", "-version"], capture_output=True, check=False)
        return True
    except FileNotFoundError:
        return False


def ensure_jar() -> Path:
    """Return the path to the language server jar, downloading it if absent."""
    if JAR_PATH.exists():
        return JAR_PATH
    LSP_DIR.mkdir(parents=True, exist_ok=True)
    url = _latest_2604_jar_url()
    sys.stderr.write(f"Downloading language server: {url}\n")
    urllib.request.urlretrieve(url, JAR_PATH)
    sys.stderr.write(f"Saved to {JAR_PATH}\n")
    return JAR_PATH


def _latest_2604_jar_url() -> str:
    """Find the download URL for the newest v26.04.x language-server-all.jar."""
    try:
        with urllib.request.urlopen(RELEASES_API, timeout=30) as resp:
            releases = json.load(resp)
        candidates = []
        for rel in releases:
            tag = rel.get("tag_name", "")
            if not tag.startswith("v26.04."):
                continue
            for asset in rel.get("assets", []):
                if asset.get("name") == "language-server-all.jar":
                    patch = int(tag.rsplit(".", 1)[-1])
                    candidates.append((patch, asset["browser_download_url"]))
        if candidates:
            return max(candidates)[1]
    except Exception as e:  # noqa: BLE001 — fall back to a known-good release
        sys.stderr.write(f"Could not query GitHub releases ({e}); using fallback.\n")
    return ("https://github.com/nextflow-io/language-server/releases/download/"
            "v26.04.1/language-server-all.jar")


class LspClient:
    """Minimal LSP client: framed JSON-RPC over a subprocess's stdio."""

    def __init__(self, proc: subprocess.Popen):
        self.proc = proc
        self.queue: "Queue[dict]" = Queue()
        self._next_id = 0
        self._reader = threading.Thread(target=self._read_loop, daemon=True)
        self._reader.start()

    def _read_loop(self):
        stream = self.proc.stdout
        while True:
            headers = {}
            while True:
                line = stream.readline()
                if not line:
                    return  # server closed stdout
                line = line.decode("utf-8", "replace").strip()
                if line == "":
                    break
                if ":" in line:
                    k, v = line.split(":", 1)
                    headers[k.strip().lower()] = v.strip()
            length = int(headers.get("content-length", 0))
            if not length:
                continue
            body = stream.read(length)
            try:
                self.queue.put(json.loads(body.decode("utf-8", "replace")))
            except json.JSONDecodeError:
                pass

    def _send(self, msg: dict):
        data = json.dumps(msg).encode("utf-8")
        header = f"Content-Length: {len(data)}\r\n\r\n".encode("ascii")
        self.proc.stdin.write(header + data)
        self.proc.stdin.flush()

    def notify(self, method: str, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def request(self, method: str, params) -> int:
        self._next_id += 1
        self._send({"jsonrpc": "2.0", "id": self._next_id,
                    "method": method, "params": params})
        return self._next_id

    def respond(self, req_id, result):
        self._send({"jsonrpc": "2.0", "id": req_id, "result": result})

    def handle_server_request(self, msg: dict):
        """Answer requests the server makes of us so it does not block."""
        method = msg.get("method", "")
        params = msg.get("params") or {}
        if method == "workspace/configuration":
            items = params.get("items", [])
            self.respond(msg["id"], [None] * len(items))
        else:
            # window/workDoneProgress/create, client/registerCapability, etc.
            self.respond(msg["id"], None)


def uri_of(path: Path) -> str:
    return path.resolve().as_uri()


def find_open_targets(root: Path):
    """One .nf and one .config file to open (each triggers its service's scan)."""
    nf = root / "main.nf"
    if not nf.exists():
        nf = next(_walk(root, ".nf"), None)
    cfg = root / "nextflow.config"
    if not cfg.exists():
        cfg = next(_walk(root, ".config"), None)
    return [p for p in (nf, cfg) if p]


def _walk(root: Path, suffix: str):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE]
        for f in sorted(filenames):
            if f.endswith(suffix):
                yield Path(dirpath) / f


def collect_diagnostics(root: Path, jar: Path, paranoid: bool) -> dict:
    proc = subprocess.Popen(
        ["java", "-jar", str(jar)],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
    )
    client = LspClient(proc)
    root_uri = uri_of(root)

    init_id = client.request("initialize", {
        "processId": os.getpid(),
        "rootUri": root_uri,
        "capabilities": {"workspace": {"configuration": False,
                                       "didChangeConfiguration": {}}},
        "workspaceFolders": [{"uri": root_uri, "name": root.name}],
    })

    diagnostics: dict[str, list] = {}
    deadline = time.time() + OVERALL_TIMEOUT
    initialized = False

    def pump(until_id=None):
        """Process incoming messages; return when the given response id arrives."""
        while time.time() < deadline:
            try:
                msg = client.queue.get(timeout=1.0)
            except Empty:
                continue
            if "id" in msg and "method" in msg:
                client.handle_server_request(msg)
            elif msg.get("method") == "textDocument/publishDiagnostics":
                p = msg["params"]
                diagnostics[p["uri"]] = p.get("diagnostics", [])
            elif until_id is not None and msg.get("id") == until_id:
                return
        return

    pump(until_id=init_id)
    client.notify("initialized", {})
    # Settings must be NESTED objects — the server navigates dotted keys
    # (nextflow.errorReportingMode → settings["nextflow"]["errorReportingMode"]).
    # A non-default value here is also what makes the server (re)scan the
    # workspace: shouldInitialize() only fires when errorReportingMode or the
    # exclude list changes, and the default exclude list is empty.
    client.notify("workspace/didChangeConfiguration", {"settings": {
        "nextflow": {
            "errorReportingMode": "PARANOID" if paranoid else "WARNINGS",
            "files": {"exclude": EXCLUDE},
        }
    }})

    for target in find_open_targets(root):
        text = target.read_text(encoding="utf-8", errors="replace")
        lang = "nextflow-config" if target.suffix == ".config" else "nextflow"
        client.notify("textDocument/didOpen", {"textDocument": {
            "uri": uri_of(target), "languageId": lang,
            "version": 1, "text": text,
        }})
        initialized = True

    if not initialized:
        sys.stderr.write("No .nf or .config files found to scan.\n")

    # Wait for diagnostics to go idle.
    first_deadline = time.time() + FIRST_DIAG_TIMEOUT
    last_activity = time.time()
    got_any = False
    while time.time() < deadline:
        try:
            msg = client.queue.get(timeout=IDLE_SECONDS)
        except Empty:
            if got_any:
                break                       # idle after receiving diagnostics → done
            if time.time() > first_deadline:
                break                       # nothing ever arrived
            continue
        last_activity = time.time()
        if "id" in msg and "method" in msg:
            client.handle_server_request(msg)
        elif msg.get("method") == "textDocument/publishDiagnostics":
            p = msg["params"]
            diagnostics[p["uri"]] = p.get("diagnostics", [])
            got_any = True

    try:
        client.request("shutdown", None)
        client.notify("exit", None)
        proc.wait(timeout=5)
    except Exception:  # noqa: BLE001
        proc.kill()

    return diagnostics


SEV = {1: "error", 2: "warning", 3: "info", 4: "hint"}


def main():
    ap = argparse.ArgumentParser(description="Report Nextflow language server diagnostics.")
    ap.add_argument("workspace", nargs="?", default=".", help="project directory (default: .)")
    ap.add_argument("--json", action="store_true", help="emit raw diagnostics as JSON")
    ap.add_argument("--paranoid", action="store_true",
                    help="report all warnings (errorReportingMode=PARANOID)")
    args = ap.parse_args()

    root = Path(args.workspace).resolve()
    if not root.is_dir():
        sys.exit(f"Not a directory: {root}")

    if not _java_available():
        sys.exit("Java 17+ is required to run the language server but `java` was not "
                 "found on PATH. Install it (e.g. via SDKMAN) and retry.")

    jar = ensure_jar()
    diags = collect_diagnostics(root, jar, args.paranoid)

    if args.json:
        print(json.dumps(diags, indent=2))
        # still set exit code below

    n_err = n_warn = 0
    lines = []
    for uri in sorted(diags):
        items = diags[uri]
        if not items:
            continue
        try:
            rel = os.path.relpath(Path(urllib.request.url2pathname(uri[7:])), root)
        except Exception:  # noqa: BLE001
            rel = uri
        for d in sorted(items, key=lambda d: (d["range"]["start"]["line"],
                                              d["range"]["start"]["character"])):
            sev = SEV.get(d.get("severity", 1), "error")
            if sev == "error":
                n_err += 1
            elif sev == "warning":
                n_warn += 1
            ln = d["range"]["start"]["line"] + 1
            col = d["range"]["start"]["character"] + 1
            msg = d.get("message", "").replace("\n", " ")
            lines.append(f"{rel}:{ln}:{col}: {sev}: {msg}")

    if not args.json:
        if lines:
            print("\n".join(lines))
            print()
        files_with_issues = len({l.split(':', 1)[0] for l in lines})
        if n_err or n_warn:
            print(f"{n_err} error(s), {n_warn} warning(s) across "
                  f"{files_with_issues} file(s).")
        else:
            print("No diagnostics. ✓")

    sys.exit(1 if n_err else 0)


if __name__ == "__main__":
    main()
