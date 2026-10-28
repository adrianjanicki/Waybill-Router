"""Tworzy apps.json – źródło aplikacji dla SideStore/AltStore (format AltStore source)."""
import json
import os
import sys
from datetime import datetime, timezone

ipa, version, build, out = sys.argv[1:5]
repo = os.environ["GITHUB_REPOSITORY"]
tag = f"v{version}"
source = {
    "name": "Karta drogowa",
    "identifier": "pl.adrian.WaybillRouter.source",
    "sourceURL": f"https://github.com/{repo}/releases/latest/download/apps.json",
    "apps": [{
        "name": "Karta drogowa",
        "bundleIdentifier": "pl.adrian.WaybillRouter",
        "developerName": "Adrian Janicki",
        "subtitle": "Karta drogowa z listów przewozowych",
        "localizedDescription": "Skan listu przewozowego, trasa TomTom, karty drogowe PDF/CSV.",
        "iconURL": f"https://raw.githubusercontent.com/{repo}/main/Resources/AppIcon.png",
        "tintColor": "F28C28",
        "versions": [{
            "version": version,
            "buildVersion": build,
            "date": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "localizedDescription": os.environ.get("CHANGES", "").strip().split("\n")[0],
            "downloadURL": f"https://github.com/{repo}/releases/download/{tag}/WaybillRouter.ipa",
            "size": os.path.getsize(ipa),
            "minOSVersion": "17.0",
        }],
        "appPermissions": {
            "entitlements": [],
            "privacy": {"NSCameraUsageDescription": "Skanowanie listów przewozowych."},
        },
    }],
    "news": [],
}
with open(out, "w", encoding="utf-8") as f:
    json.dump(source, f, ensure_ascii=False, indent=2)
