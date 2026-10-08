#!/usr/bin/env python3
"""Validate public release settings and configure the copied DMG app only."""
import base64
import json
import plistlib
import re
import sys
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
from xml.etree import ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent


def require(condition, message):
    if not condition:
        raise ValueError(message)


def read_config(path=ROOT / "release.json"):
    config = json.loads(path.read_text())
    require(re.fullmatch(r"\d+\.\d+\.\d+", config["version"]), "Use a stable x.y.z version")
    require(type(config["build"]) is int and config["build"] > 1, "Use an increasing build number > 1")
    require(re.fullmatch(r"[\w.-]+/[\w.-]+", config["repository"]), "Invalid repository")
    expected = f'https://github.com/{config["repository"]}/releases/latest/download/appcast.xml'
    require(config["feedURL"] == expected, "Feed must point to this repository's latest release")
    require(len(base64.b64decode(config["publicKey"], validate=True)) == 32, "Invalid Ed25519 public key")
    require(re.fullmatch(r"[\w.-]+", config["signingAccount"]), "Invalid Keychain account")
    return config


def configure_app(app, config):
    path = Path(app) / "Contents/Info.plist"
    with path.open("rb") as file:
        info = plistlib.load(file)
    require(info["CFBundleIdentifier"] == "app.seeusage.SeeUsage", "Unexpected app identifier")
    info.update({
        "CFBundleShortVersionString": config["version"],
        "CFBundleVersion": str(config["build"]),
        "SUFeedURL": config["feedURL"],
        "SUPublicEDKey": config["publicKey"],
        "SUEnableAutomaticChecks": True,
        "SUScheduledCheckInterval": 3600,
        "SUAutomaticallyUpdate": False,
        "SUAllowsAutomaticUpdates": False,
        "SUEnableSystemProfiling": False,
        "SUVerifyUpdateBeforeExtraction": True,
        "SURequireSignedFeed": True,
    })
    with path.open("wb") as file:
        plistlib.dump(info, file, sort_keys=False)


def validate_app(app, config):
    with (Path(app) / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    expected = {
        "CFBundleIdentifier": "app.seeusage.SeeUsage",
        "CFBundleShortVersionString": config["version"],
        "CFBundleVersion": str(config["build"]),
        "SUFeedURL": config["feedURL"],
        "SUPublicEDKey": config["publicKey"],
        "SUVerifyUpdateBeforeExtraction": True,
        "SURequireSignedFeed": True,
        "SUAllowsAutomaticUpdates": False,
        "SUAutomaticallyUpdate": False,
        "SUEnableSystemProfiling": False,
        "SUScheduledCheckInterval": 3600,
    }
    for key, value in expected.items():
        require(info.get(key) == value, f"Incorrect release setting: {key}")
    require((Path(app) / "Contents/Frameworks/Sparkle.framework/Sparkle").is_file(), "Missing updater framework")


def create_appcast(archive, signature, output, config):
    require(len(base64.b64decode(signature, validate=True)) == 64, "Invalid archive signature")
    namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", namespace)
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "SeeUsage updates"
    ET.SubElement(channel, "link").text = f'https://github.com/{config["repository"]}/releases'
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f'SeeUsage {config["version"]}'
    ET.SubElement(item, "link").text = f'https://github.com/{config["repository"]}/releases/tag/v{config["version"]}'
    ET.SubElement(item, "pubDate").text = format_datetime(datetime.now(timezone.utc))
    for key, value in [("version", str(config["build"])), ("shortVersionString", config["version"]),
                       ("minimumSystemVersion", "14.0")]:
        ET.SubElement(item, f"{{{namespace}}}{key}").text = value
    ET.SubElement(item, "enclosure", {
        "url": f'https://github.com/{config["repository"]}/releases/download/v{config["version"]}/{Path(archive).name}',
        "length": str(Path(archive).stat().st_size), "type": "application/octet-stream",
        f"{{{namespace}}}edSignature": signature,
    })
    tree = ET.ElementTree(rss)
    ET.indent(tree)
    tree.write(output, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    try:
        settings = read_config()
        action = sys.argv[1]
        if action == "configure":
            configure_app(sys.argv[2], settings)
        elif action == "validate-app":
            validate_app(sys.argv[2], settings)
        elif action == "appcast":
            create_appcast(sys.argv[2], sys.argv[3], sys.argv[4], settings)
        else:
            print(settings[action])
    except (AssertionError, KeyError, ValueError, OSError, IndexError) as error:
        sys.exit(f"Release metadata error: {error}")
