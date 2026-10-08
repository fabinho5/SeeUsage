#!/usr/bin/env python3
"""Exercise Sparkle with temporary fixture apps and a localhost feed.

Requires cached Sparkle tools. Uses a disposable test key, never the publisher's
Keychain key. Never launches SeeUsage or accesses real provider accounts.
"""
import functools
import http.server
import os
import plistlib
import re
import shutil
import signal
import subprocess
import tempfile
import threading
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOLS = Path.home() / "Library/Caches/SeeUsage/Sparkle-2.10.0"


def run(*arguments, capture=False):
    result = subprocess.run([str(arg) for arg in arguments], check=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=90)
    return result.stdout.strip() if capture else None


class QuietHTTP(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


def main():
    with tempfile.TemporaryDirectory(prefix="seeusage-update-fixtures-") as directory:
        work = Path(directory)
        # CryptoKit creates a random test seed in the private temporary directory.
        # Only the public key is printed; the fixture seed is erased on completion.
        test_key = work / "fixture-key"
        public_key = run("swift", "-e", '''
import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
let path = CommandLine.arguments[1]
try key.rawRepresentation.base64EncodedData().write(to: URL(fileURLWithPath: path))
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
print(key.publicKey.rawRepresentation.base64EncodedString())
''', test_key, capture=True)
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHTTP, directory=directory))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base_url = f"http://127.0.0.1:{server.server_port}"
        executable = work / "UpdateFixture"
        run("xcrun", "clang", "-fobjc-arc", "-mmacosx-version-min=14.0", "-framework", "AppKit",
            "-F", TOOLS, "-framework", "Sparkle", "-Wl,-rpath,@executable_path/../Frameworks",
            ROOT / "Tests/UpdaterIntegration/UpdateFixture.m", "-o", executable)
        identifiers = []
        try:
            for case in ["dismiss", "skip", "no-update", "tampered-feed", "tampered-archive", "install"]:
                case_root = work / case
                case_root.mkdir()
                identifier = f"app.seeusage.integration.{uuid.uuid4().hex}"
                identifiers.append(identifier)
                log = case_root / "events.log"
                app_name = "UpdateFixture.app"
                host = case_root / app_name
                payload_root = case_root / "payload"
                target = payload_root / app_name

                def make_app(path, build, updated):
                    (path / "Contents/MacOS").mkdir(parents=True)
                    (path / "Contents/Frameworks").mkdir()
                    shutil.copy2(executable, path / "Contents/MacOS/UpdateFixture")
                    run("ditto", TOOLS / "Sparkle.framework", path / "Contents/Frameworks/Sparkle.framework")
                    info = {
                        "CFBundleIdentifier": identifier, "CFBundleName": "UpdateFixture",
                        "CFBundleExecutable": "UpdateFixture", "CFBundlePackageType": "APPL",
                        "CFBundleVersion": str(build), "CFBundleShortVersionString": f"0.0.{build}",
                        "LSMinimumSystemVersion": "14.0", "LSUIElement": True,
                        "SUFeedURL": f"{base_url}/{case}/appcast.xml", "SUPublicEDKey": public_key,
                        "SUEnableAutomaticChecks": False, "SUAllowsAutomaticUpdates": False,
                        "SUVerifyUpdateBeforeExtraction": True, "SURequireSignedFeed": True,
                        "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
                        "TestChoice": case if case in ["dismiss", "skip"] else "install",
                        "TestLogPath": str(log), "TestUpdatedPayload": updated,
                    }
                    with (path / "Contents/Info.plist").open("wb") as file:
                        plistlib.dump(info, file)
                    run("codesign", "--force", "--sign", "-", path)

                make_app(host, 2 if case == "no-update" else 1, False)
                make_app(target, 2, True)
                archive = case_root / "update.dmg"
                run("hdiutil", "create", "-quiet", "-volname", "UpdateFixture", "-srcfolder", payload_root,
                    "-fs", "HFS+", "-format", "UDZO", archive)
                signature = run(TOOLS / "bin/sign_update", "--ed-key-file", test_key, "-p", archive, capture=True)
                assert re.fullmatch(r"[A-Za-z0-9+/=]+", signature)
                feed = case_root / "appcast.xml"
                feed.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><title>Disposable updater test</title><item><title>Test update</title>
<sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString>
<sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
<enclosure url="{base_url}/{case}/update.dmg" length="{archive.stat().st_size}" type="application/octet-stream" sparkle:edSignature="{signature}"/>
</item></channel></rss>''')
                run(TOOLS / "bin/sign_update", "--ed-key-file", test_key, feed)
                run(TOOLS / "bin/sign_update", "--ed-key-file", test_key, "--verify", feed)
                if case == "tampered-feed":
                    feed.write_text(feed.read_text().replace("Test update", "Changed update"))
                if case == "tampered-archive":
                    with archive.open("ab") as file:
                        file.write(b"tampered-after-signing")
                run("open", "-n", host)
                deadline = time.monotonic() + 50
                events = ""
                while time.monotonic() < deadline:
                    events = log.read_text() if log.exists() else ""
                    terminal = ("relaunched:2" if case == "install" else
                                "error:" if case.startswith("tampered") else
                                "no-update" if case == "no-update" else "dismissed-driver")
                    if terminal in events or "timeout" in events or "startup-error" in events:
                        break
                    time.sleep(0.1)
                print(f"{case}: {events.strip().replace(chr(10), ' → ')}", flush=True)
                assert "timeout" not in events and "startup-error" not in events, events
                if case == "install":
                    assert "relaunched:2" in events and "preference:preserved" in events, events
                    with (host / "Contents/Info.plist").open("rb") as file:
                        assert plistlib.load(file)["CFBundleVersion"] == "2"
                elif case.startswith("tampered"):
                    # Sparkle announces the extraction *stage* before validating;
                    # invalid archives must never actually extract or install.
                    assert "error:" in events and "extraction-progress" not in events and "installing" not in events and "relaunched" not in events, events
                    if case == "tampered-feed":
                        assert "found:" not in events, "Unsigned feed must be rejected before offering an update"
                elif case == "no-update":
                    assert "no-update" in events and "consented" not in events, events
                else:
                    assert "found:2" in events and "consented" not in events and "downloading" not in events, events
                if case != "install":
                    with (host / "Contents/Info.plist").open("rb") as file:
                        assert plistlib.load(file)["CFBundleVersion"] == ("2" if case == "no-update" else "1")
                # Let the fixture exit before removing its bundle/preferences.
                time.sleep(0.4)
        finally:
            server.shutdown()
            for line in subprocess.check_output(["/bin/ps", "-ww", "-axo", "pid=,command="], text=True).splitlines():
                fields = line.strip().split(None, 1)
                if len(fields) == 2 and fields[1].startswith(str(work) + "/") and fields[1].endswith("/Contents/MacOS/UpdateFixture"):
                    try:
                        os.kill(int(fields[0]), signal.SIGTERM)
                    except ProcessLookupError:
                        pass
            registrar = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            for host in work.glob("*/UpdateFixture.app"):
                subprocess.run([registrar, "-u", str(host)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            # Only these newly generated fixture domains are removed.
            for identifier in identifiers:
                subprocess.run(["defaults", "delete", identifier], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                shutil.rmtree(Path.home() / "Library/Caches" / identifier, ignore_errors=True)
    print("All six isolated update scenarios passed. No provider account was accessed.")


if __name__ == "__main__":
    main()
