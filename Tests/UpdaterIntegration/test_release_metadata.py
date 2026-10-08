import base64
import importlib.util
import json
import plistlib
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("release_metadata", ROOT / "scripts/release_metadata.py")
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class ReleaseMetadataTests(unittest.TestCase):
    def test_invalid_versions_feeds_keys_and_builds_are_rejected(self):
        original = metadata.read_config()
        for key, value in [("version", "1.1.1-beta"), ("build", 1), ("build", True),
                           ("publicKey", "invalid"), ("feedURL", "https://example.com/feed.xml"),
                           ("repository", "bad repo"), ("signingAccount", "bad account")]:
            with self.subTest(key=key, value=value), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / "release.json"
                path.write_text(json.dumps({**original, key: value}))
                with self.assertRaises(ValueError):
                    metadata.read_config(path)

    def test_packaged_app_disallows_silent_installs_and_requires_signatures(self):
        config = metadata.read_config()
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "SeeUsage.app"
            contents = app / "Contents"
            framework = contents / "Frameworks/Sparkle.framework"
            framework.mkdir(parents=True)
            (framework / "Sparkle").write_bytes(b"mock framework")
            plist = contents / "Info.plist"
            plist.write_bytes(plistlib.dumps({"CFBundleIdentifier": "app.seeusage.SeeUsage"}))
            metadata.configure_app(app, config)
            metadata.validate_app(app, config)
            info = plistlib.loads(plist.read_bytes())
            self.assertTrue(info["SUEnableAutomaticChecks"])
            for key in ["SURequireSignedFeed", "SUVerifyUpdateBeforeExtraction", "SUAllowsAutomaticUpdates"]:
                modified = {**info, key: not info[key]}
                plist.write_bytes(plistlib.dumps(modified))
                with self.assertRaises(ValueError):
                    metadata.validate_app(app, config)

    def test_appcast_uses_matching_immutable_release_asset_and_build(self):
        config = metadata.read_config()
        namespace = {"s": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
        signature = base64.b64encode(bytes(64)).decode()
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / f'SeeUsage-{config["version"]}-universal.dmg'
            archive.write_bytes(b"mock archive")
            feed = Path(directory) / "appcast.xml"
            metadata.create_appcast(archive, signature, feed, config)
            item = ET.parse(feed).find("./channel/item")
            self.assertEqual(item.find("s:version", namespace).text, str(config["build"]))
            self.assertEqual(item.find("s:minimumSystemVersion", namespace).text, "14.0")
            enclosure = item.find("enclosure")
            self.assertEqual(enclosure.get("url"), f'https://github.com/{config["repository"]}/releases/download/v{config["version"]}/{archive.name}')
            self.assertEqual(enclosure.get("length"), str(archive.stat().st_size))
            self.assertEqual(enclosure.get("{" + namespace["s"] + "}edSignature"), signature)
            with self.assertRaises(ValueError):
                metadata.create_appcast(archive, "invalid", feed, config)


if __name__ == "__main__":
    unittest.main()
