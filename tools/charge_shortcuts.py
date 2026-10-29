#!/usr/bin/env python3
"""Generate and validate two unsigned macOS Shortcuts workflows.

No third-party dependencies. Apple signs the generated plist on macOS.
"""
from __future__ import annotations

import argparse
import pathlib
import plistlib
import uuid

ACTION = "com.apple.ShortcutsActions.SetBatteryChargeLimitAction"
BUNDLE = "com.apple.ShortcutsActions"
PROFILES = (
    ("白天充电上限80", 80, 0xE0B64AFF),
    ("晚间充电上限100", 100, 0x4A62B4FF),
)


def workflow(name: str, limit: int) -> dict:
    if name not in {row[0] for row in PROFILES}:
        raise ValueError("Unknown shortcut name")
    if limit not in (80, 100):
        raise ValueError("Only 80 and 100 are supported")
    color = next(row[2] for row in PROFILES if row[0] == name)
    return {
        "WFWorkflowClientVersion": "2600.0.1",
        "WFWorkflowMinimumClientVersion": 2600,
        "WFWorkflowMinimumClientVersionString": "2600",
        "WFWorkflowIcon": {
            "WFWorkflowIconGlyphNumber": 61440,
            "WFWorkflowIconStartColor": color,
        },
        "WFWorkflowName": name,
        "WFWorkflowImportQuestions": [],
        "WFWorkflowInputContentItemClasses": [],
        "WFWorkflowOutputContentItemClasses": [],
        "WFWorkflowTypes": [],
        "WFWorkflowHasOutputFallback": False,
        "WFWorkflowActions": [
            {
                "WFWorkflowActionIdentifier": ACTION,
                "WFWorkflowActionParameters": {
                    "AppIntentDescriptor": {
                        "AppIntentIdentifier": "SetBatteryChargeLimitAction",
                        "BundleIdentifier": BUNDLE,
                        "Name": "ShortcutsActions",
                        "TeamIdentifier": "0000000000",
                    },
                    "UUID": str(uuid.uuid5(uuid.NAMESPACE_DNS, f"macbatterycharge/{name}")),
                    "limit": limit,
                    "setUntilTomorrow": False,
                },
            }
        ],
    }


def validate(data: bytes, name: str, limit: int) -> None:
    obj = plistlib.loads(data)
    if obj.get("WFWorkflowName") != name:
        raise ValueError(f"Unexpected shortcut name: {name}")
    if obj.get("WFWorkflowMinimumClientVersion", 0) < 2600:
        raise ValueError("Unsupported minimum Shortcuts version")
    actions = obj.get("WFWorkflowActions")
    if not isinstance(actions, list) or len(actions) != 1:
        raise ValueError("Expected exactly one action")
    action = actions[0]
    if action.get("WFWorkflowActionIdentifier") != ACTION:
        raise ValueError("Unexpected action identifier")
    params = action["WFWorkflowActionParameters"]
    desc = params.get("AppIntentDescriptor")
    if not isinstance(desc, dict) or desc.get("BundleIdentifier") != BUNDLE or desc.get("AppIntentIdentifier") != "SetBatteryChargeLimitAction":
        raise ValueError("Invalid AppIntentDescriptor")
    if params.get("limit") != limit or type(params.get("limit")) is not int:
        raise ValueError("Incorrect limit")
    if params.get("setUntilTomorrow") is not False:
        raise ValueError("A persistent charge limit is required")
    if set(params) != {"AppIntentDescriptor", "UUID", "limit", "setUntilTomorrow"}:
        raise ValueError("Unexpected action parameters")


def generate(directory: pathlib.Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    for name, limit, _ in PROFILES:
        data = plistlib.dumps(workflow(name, limit), fmt=plistlib.FMT_XML, sort_keys=True)
        validate(data, name, limit)
        dest = directory / f"{name}.unsigned.shortcut"
        dest.write_bytes(data)
        print(f"Generated {dest} ({len(data)} bytes)")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate macOS charge-limit shortcuts")
    parser.add_argument("--output", type=pathlib.Path, default=pathlib.Path("build/unsigned"))
    args = parser.parse_args()
    generate(args.output)


if __name__ == "__main__":
    main()
