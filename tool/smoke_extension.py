import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
EXTENSION_DIR = ROOT_DIR / "build" / "chrome-extension"
REQUIRED_ORIGINS = [
    "https://connect.bracu.ac.bd/*",
    "https://sso.bracu.ac.bd/*",
    "https://api.preconnect.app/*",
    "https://pb.preconnect.app/*",
]
RENDER_TIMEOUT_SECONDS = 90


def chrome_path():
    configured = os.environ.get("CHROME_PATH")
    if configured:
        return configured
    mac = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    if Path(mac).exists():
        return mac
    for name in ("google-chrome", "google-chrome-stable", "chromium"):
        found = shutil.which(name)
        if found:
            return found
    raise SystemExit("Chrome was not found; set CHROME_PATH")


class DevToolsPipe:
    def __init__(self, process, writer, reader):
        self.process = process
        self.writer = writer
        self.reader = reader
        self.buffer = b""
        self.next_id = 0
        self.events = []

    def _read_message(self, deadline):
        while b"\0" not in self.buffer:
            if time.time() > deadline:
                raise SystemExit("Chrome stopped answering DevTools commands")
            chunk = os.read(self.reader, 1 << 20)
            if not chunk:
                raise SystemExit("Chrome closed the DevTools pipe")
            self.buffer += chunk
        raw, self.buffer = self.buffer.split(b"\0", 1)
        return json.loads(raw)

    def call(self, method, session=None, **params):
        self.next_id += 1
        message = {"id": self.next_id, "method": method, "params": params}
        if session:
            message["sessionId"] = session
        os.write(self.writer, json.dumps(message).encode() + b"\0")
        deadline = time.time() + 60
        while True:
            reply = self._read_message(deadline)
            if reply.get("id") == self.next_id:
                if "error" in reply:
                    raise SystemExit(f"{method} failed: {reply['error']}")
                return reply.get("result", {})
            self.events.append(reply)

    def evaluate(self, session, expression):
        result = self.call(
            "Runtime.evaluate",
            session,
            expression=expression,
            awaitPromise=True,
            returnByValue=True,
        )
        if "exceptionDetails" in result:
            raise SystemExit(f"Evaluation failed: {result['exceptionDetails']}")
        return result.get("result", {}).get("value")


def launch(profile):
    to_chrome_read, to_chrome_write = os.pipe()
    from_chrome_read, from_chrome_write = os.pipe()

    def attach_pipe():
        os.dup2(to_chrome_read, 3)
        os.dup2(from_chrome_write, 4)

    arguments = [
        chrome_path(),
        "--headless=new",
        f"--user-data-dir={profile}",
        "--remote-debugging-pipe",
        "--enable-unsafe-extension-debugging",
        "--no-first-run",
        "--no-default-browser-check",
        "--window-size=420,860",
        "about:blank",
    ]
    if sys.platform.startswith("linux") and os.geteuid() == 0:
        arguments.insert(1, "--no-sandbox")
    process = subprocess.Popen(
        arguments,
        pass_fds=(3, 4),
        preexec_fn=attach_pipe,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    os.close(to_chrome_read)
    os.close(from_chrome_write)
    return DevToolsPipe(process, to_chrome_write, from_chrome_read)


def wait_for(check, timeout, failure):
    deadline = time.time() + timeout
    while time.time() < deadline:
        value = check()
        if value:
            return value
        time.sleep(1)
    raise SystemExit(failure)


def page_errors(events, session):
    errors = []
    for event in events:
        if event.get("sessionId") != session:
            continue
        if event.get("method") == "Runtime.exceptionThrown":
            details = event["params"]["exceptionDetails"]
            errors.append(details.get("exception", {}).get("description") or details.get("text"))
    return errors


def main():
    if not (EXTENSION_DIR / "manifest.json").exists():
        raise SystemExit(f"Build the extension first: {EXTENSION_DIR} is missing")
    profile = tempfile.mkdtemp(prefix="preconnect_smoke_")
    devtools = launch(profile)
    try:
        extension_id = devtools.call("Extensions.loadUnpacked", path=str(EXTENSION_DIR))["id"]
        print(f"Loaded extension {extension_id}")

        def background_running():
            targets = devtools.call("Target.getTargets")["targetInfos"]
            return any(
                target["type"] == "service_worker"
                and target["url"] == f"chrome-extension://{extension_id}/background.dart.js"
                for target in targets
            )

        wait_for(background_running, 30, "The background worker did not start")
        print("Background worker is running")

        target = devtools.call(
            "Target.createTarget", url=f"chrome-extension://{extension_id}/index.html"
        )["targetId"]
        session = devtools.call("Target.attachToTarget", targetId=target, flatten=True)["sessionId"]
        devtools.call("Runtime.enable", session)

        wait_for(
            lambda: devtools.evaluate(
                session,
                "!!document.querySelector('flt-glass-pane')?.shadowRoot"
                "?.querySelector('canvas')"
                " && !document.getElementById('loading-container')",
            ),
            RENDER_TIMEOUT_SECONDS,
            "The extension page did not finish rendering",
        )
        print("Extension page rendered with the Chromium CanvasKit")

        granted = devtools.evaluate(
            session,
            "chrome.permissions.contains({origins: %s})" % json.dumps(REQUIRED_ORIGINS),
        )
        if granted is not True:
            raise SystemExit("Required site access is not granted")
        print("Site access is granted")


        time.sleep(3)
        devtools.evaluate(session, "1")
        errors = page_errors(devtools.events, session)
        if errors:
            raise SystemExit("Uncaught errors on the extension page:\n" + "\n".join(errors))
        print("Extension smoke test passed")
    finally:
        devtools.process.terminate()
        try:
            devtools.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            devtools.process.kill()
        shutil.rmtree(profile, ignore_errors=True)


if __name__ == "__main__":
    main()
