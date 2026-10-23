"""Prepend a new version to source.json (AltStore / SideStore source format)."""
import argparse
import datetime
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
parser.add_argument("--size", required=True, type=int)
parser.add_argument("--url", required=True)
args = parser.parse_args()

path = Path(__file__).resolve().parent.parent / "source.json"
source = json.loads(path.read_text(encoding="utf-8"))
app = source["apps"][0]

entry = {
    "version": args.version,
    "buildVersion": args.build,
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": f"Version {args.version}",
    "downloadURL": args.url,
    "size": args.size,
    "minOSVersion": "26.0",
}

versions = [v for v in app.get("versions", []) if v.get("version") != args.version]
app["versions"] = [entry] + versions

path.write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"source.json -> {args.version} ({args.size} bytes)")
