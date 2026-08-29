#!/usr/bin/env bash
# Read-only: compare Cursor user marketplace pins to GitHub for the two plugin groups.
set -euo pipefail

# shellcheck source=resolve-cursor-agent.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-cursor-agent.sh"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not on PATH" >&2
  exit 1
fi

LIST_JSON="$("$AGENT" plugin marketplace list --format json)"

python3 - "$LIST_JSON" <<'PY'
import json, subprocess, sys

raw = sys.argv[1]
try:
    rows = json.loads(raw)
except json.JSONDecodeError as exc:
    print(f"FAIL: marketplace list is not JSON: {exc}", file=sys.stderr)
    sys.exit(1)

by_name = {row.get("name"): row for row in rows if isinstance(row, dict)}

groups = [
    {
        "name": "llm-wiki",
        "url": "https://github.com/karlorz/llm-wiki.git",
        "mode": "tag",
    },
    {
        "name": "karlorz-agent-skills",
        "url": "https://github.com/karlorz/agent-skills.git",
        "mode": "head",
    },
]


def ls_remote(url, *args):
    cmd = ["git", "ls-remote", url, *args]
    out = subprocess.check_output(cmd, text=True)
    lines = []
    for line in out.splitlines():
        if not line.strip():
            continue
        sha, ref = line.split("\t", 1)
        lines.append((sha, ref))
    return lines


def pin_matches(pin, shas):
    return bool(pin) and pin in {sha for sha in shas if sha}


print("Cursor user GitHub marketplace pins (read-only)")
print()

for group in groups:
    name = group["name"]
    row = by_name.get(name)
    print(f"== {name} ==")
    if not row:
        print("  status: MISSING — skip remove; only add --git-ref")
        print()
        continue
    pin = row.get("gitRef") or ""
    scope = row.get("scope") or ""
    git_url = row.get("gitUrl") or ""
    print(f"  scope:  {scope}")
    print(f"  gitUrl: {git_url}")
    print(f"  gitRef: {pin}")
    if scope != "user":
        print("  note: scope is not user — this skill does not apply; do not remove+add")
        print()
        continue
    try:
        if group["mode"] == "tag":
            tags = ls_remote(group["url"], "refs/tags/v*")
            info = {}
            for sha, ref in tags:
                if ref.endswith("^{}"):
                    tag = ref[len("refs/tags/") : -3]
                    info.setdefault(tag, {})["peeled"] = sha
                else:
                    tag = ref[len("refs/tags/") :]
                    info.setdefault(tag, {})["object"] = sha

            def tag_key(tag):
                body = tag[1:] if tag.startswith("v") else tag
                parts = []
                for piece in body.split("."):
                    try:
                        parts.append(int(piece))
                    except ValueError:
                        return None
                return tuple(parts)

            version_tags = [t for t in info if tag_key(t) is not None]
            latest = max(version_tags, key=tag_key, default="")
            if not latest:
                print("  remote: no v* version tags")
            else:
                object_sha = info[latest].get("object", "")
                peeled_sha = info[latest].get("peeled", "")
                print(f"  remote: {latest} tag={object_sha} commit={peeled_sha or object_sha}")
                if pin_matches(pin, [object_sha, peeled_sha]):
                    print(f"  status: PIN MATCHES latest {latest} tag")
                else:
                    print(f"  status: STALE — remove then add --git-ref {latest}")
                    print(f"  add:    plugin marketplace add {group['url'].removesuffix('.git')} --git-ref {latest}")
        else:
            head = ls_remote(group["url"], "HEAD")[0][0]
            print(f"  remote: HEAD {head}")
            if pin_matches(pin, [head]):
                print("  status: PIN MATCHES default-branch HEAD")
            else:
                print(f"  status: STALE — remove then add --git-ref {head}")
                print(f"  add:    plugin marketplace add {group['url'].removesuffix('.git')} --git-ref {head}")
    except subprocess.CalledProcessError as exc:
        print(f"  remote: git ls-remote failed ({exc.returncode})")
    print()
PY
