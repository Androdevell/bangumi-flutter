"""Generate a limited CycloneDX inventory and query OSV for resolved public versions.

No source, credentials or environment are uploaded. This is advisory matching,
not proof of reachability or a complete Flutter/native binary vulnerability scan.
"""
import argparse
import datetime
import json
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen


def components(dart, maven):
    result = []
    for item in dart["packages"]:
        if item.get("source") != "hosted":
            continue  # SDK/path/git packages need separate provenance review.
        name, version = item["name"], item["version"]
        result.append(("Pub", name, version, f"pkg:pub/{quote(name)}@{quote(version)}"))
    for item in maven:
        group, name, version = item["group"], item["name"], item["version"]
        result.append(("Maven", f"{group}:{name}", version,
                       f"pkg:maven/{quote(group)}/{quote(name)}@{quote(version)}"))
    return sorted(set(result))


def scan(items, query):
    findings = []
    for offset in range(0, len(items), 100):
        batch = items[offset:offset + 100]
        response = query({"queries": [{"package": {"ecosystem": eco, "name": name},
                                        "version": version} for eco, name, version, _ in batch]})
        results = response["results"]
        if len(results) != len(batch):
            raise ValueError("Incomplete OSV response")
        for item, result in zip(batch, results):
            if result.get("error") or result.get("next_page_token") or result.get("nextPageToken"):
                raise ValueError("OSV query incomplete; review service response")
            if result.get("vulns"):
                findings.append({"ecosystem": item[0], "name": item[1], "version": item[2],
                                 "advisories": result["vulns"], "status": "needs-review"})
    return findings


def osv_query(payload):
    request = Request("https://api.osv.dev/v1/querybatch", json.dumps(payload).encode(),
                      {"Content-Type": "application/json", "User-Agent": "bangumi-dependency-audit"})
    with urlopen(request, timeout=60) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--directory", default="build/dependency-audit")
    parser.add_argument("--inventory-only", action="store_true")
    args = parser.parse_args()
    directory = Path(args.directory)
    items = components(json.loads((directory / "dart.json").read_text(encoding="utf-8-sig")),
                       json.loads((directory / "maven.json").read_text(encoding="utf-8-sig")))
    bom = {"bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1,
           "metadata": {"timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()},
           "components": [{"type": "library", "name": name, "version": version,
                           "purl": purl, "bom-ref": purl} for _, name, version, purl in items]}
    (directory / "sbom.cdx.json").write_text(json.dumps(bom, indent=2), encoding="utf-8")
    if args.inventory_only:
        return 0
    findings = scan(items, osv_query)  # Errors fail the job; never report an incomplete scan as clean.
    report = {"coverage": "hosted Dart packages and Android debugRuntimeClasspath Maven artifacts",
              "excludes": "Flutter SDK, OS libraries, bundled native binary internals and exploitability",
              "findings": findings}
    (directory / "osv-review.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Scanned {len(items)} public component versions; {len(findings)} require advisory review.")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
