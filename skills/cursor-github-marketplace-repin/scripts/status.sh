#!/usr/bin/env bash
# Read-only: compare Cursor user marketplace pins + gitSkills status.
set -euo pipefail

# shellcheck source=resolve-cursor-agent.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-cursor-agent.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not on PATH" >&2
  exit 1
fi

LIST_JSON="$("$AGENT" plugin marketplace list --format json)"

python3 - "$LIST_JSON" "$SCRIPT_DIR" <<'PY'
import json, os, re, subprocess, sys
from pathlib import Path

raw = sys.argv[1]
script_dir = Path(sys.argv[2])
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
        "repo": "karlorz/llm-wiki",
        "mode": "tag",
    },
    {
        "name": "karlorz-agent-skills",
        "url": "https://github.com/karlorz/agent-skills.git",
        "repo": "karlorz/agent-skills",
        "mode": "head",
    },
]


def clean_git_env():
    env = dict(os.environ)
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("DYLD_LIBRARY_PATH", None)
    for key in list(env):
        val = env.get(key) or ""
        if "portfolio-lab/toolchain" in val and "LIBRARY" in key.upper():
            env.pop(key, None)
    env["GIT_EXEC_PATH"] = "/usr/lib/git-core"
    return env


def ls_remote(url, *args):
    cmd = [os.environ.get("CURSOR_REPIN_GIT_BIN", "/usr/bin/git"), "ls-remote", url, *args]
    out = subprocess.check_output(cmd, text=True, env=clean_git_env())
    lines = []
    for line in out.splitlines():
        if not line.strip():
            continue
        sha, ref = line.split("\t", 1)
        lines.append((sha, ref))
    return lines


def gh_api(path):
    out = subprocess.check_output(["gh", "api", path], text=True, env=clean_git_env())
    return json.loads(out)


def tag_key(tag):
    body = tag[1:] if tag.startswith("v") else tag
    parts = []
    for piece in body.split("."):
        try:
            parts.append(int(piece))
        except ValueError:
            return None
    return tuple(parts)


def latest_tag_via_gh(repo):
    refs = gh_api(f"repos/{repo}/git/matching-refs/tags/v")
    info = {}
    for row in refs:
        ref = row.get("ref") or ""
        if not ref.startswith("refs/tags/"):
            continue
        tag = ref[len("refs/tags/") :]
        obj = row.get("object") or {}
        sha = obj.get("sha") or ""
        typ = obj.get("type") or ""
        if not sha:
            continue
        slot = info.setdefault(tag, {})
        if typ == "tag":
            slot["object"] = sha
            try:
                tag_obj = gh_api(f"repos/{repo}/git/tags/{sha}")
                peeled = (tag_obj.get("object") or {}).get("sha") or ""
                if peeled:
                    slot["peeled"] = peeled
            except (subprocess.CalledProcessError, json.JSONDecodeError, TypeError):
                pass
        elif typ == "commit":
            slot.setdefault("object", sha)
            slot["peeled"] = sha
    version_tags = [t for t in info if tag_key(t) is not None]
    latest = max(version_tags, key=tag_key, default="")
    if not latest:
        return "", "", ""
    return latest, info[latest].get("object", ""), info[latest].get("peeled", "")


def head_via_gh(repo):
    meta = gh_api(f"repos/{repo}")
    branch = meta.get("default_branch") or "main"
    commit = gh_api(f"repos/{repo}/commits/{branch}")
    return commit.get("sha") or ""


def pin_matches(pin, shas):
    return bool(pin) and pin in {sha for sha in shas if sha}


def resolve_ref_sha(git_url, ref):
    m = re.match(r"https://github\.com/([^/]+)/([^/.]+)(?:\.git)?$", git_url)
    if not m:
        return ""
    owner, repo = m.group(1), m.group(2)
    for kind in ("heads", "tags"):
        try:
            data = gh_api(f"repos/{owner}/{repo}/git/ref/{kind}/{ref}")
            obj = data.get("object") or {}
            sha = obj.get("sha") or ""
            if obj.get("type") == "tag":
                tag = gh_api(f"repos/{owner}/{repo}/git/tags/{sha}")
                sha = (tag.get("object") or {}).get("sha") or sha
            if sha:
                return sha
        except (subprocess.CalledProcessError, json.JSONDecodeError, TypeError):
            continue
    if re.fullmatch(r"[0-9a-f]{40}", ref):
        return ref
    try:
        lines = ls_remote(git_url, ref, f"refs/heads/{ref}", f"refs/tags/{ref}")
        for sha, name in lines:
            if name.endswith(f"refs/heads/{ref}") or name.endswith(f"refs/tags/{ref}") or name == ref:
                return sha
    except subprocess.CalledProcessError:
        return ""
    return ""


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
            try:
                tags = ls_remote(group["url"], "refs/tags/v*")
            except subprocess.CalledProcessError:
                latest, object_sha, peeled_sha = latest_tag_via_gh(group["repo"])
                if not latest:
                    print("  remote: gh api — no v* version tags")
                    print()
                    continue
                print(f"  remote: {latest} tag={object_sha} commit={peeled_sha or object_sha} (via gh api)")
                if pin_matches(pin, [object_sha, peeled_sha]):
                    print(f"  status: PIN MATCHES latest {latest} tag")
                else:
                    print(f"  status: STALE — remove then add --git-ref {latest}")
                    print(f"  add:    plugin marketplace add {group['url'].removesuffix('.git')} --git-ref {latest}")
                print()
                continue

            info = {}
            for sha, ref in tags:
                if ref.endswith("^{}"):
                    tag = ref[len("refs/tags/") : -3]
                    info.setdefault(tag, {})["peeled"] = sha
                else:
                    tag = ref[len("refs/tags/") :]
                    info.setdefault(tag, {})["object"] = sha

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
            try:
                head = ls_remote(group["url"], "HEAD")[0][0]
            except subprocess.CalledProcessError:
                head = head_via_gh(group["repo"])
                if not head:
                    print("  remote: gh api — could not resolve default-branch HEAD")
                    print()
                    continue
                print(f"  remote: HEAD {head} (via gh api)")
                if pin_matches(pin, [head]):
                    print("  status: PIN MATCHES default-branch HEAD")
                else:
                    print(f"  status: STALE — remove then add --git-ref {head}")
                    print(f"  add:    plugin marketplace add {group['url'].removesuffix('.git')} --git-ref {head}")
                print()
                continue

            print(f"  remote: HEAD {head}")
            if pin_matches(pin, [head]):
                print("  status: PIN MATCHES default-branch HEAD")
            else:
                print(f"  status: STALE — remove then add --git-ref {head}")
                print(f"  add:    plugin marketplace add {group['url'].removesuffix('.git')} --git-ref {head}")
    except (subprocess.CalledProcessError, json.JSONDecodeError, IndexError, TypeError, KeyError) as exc:
        detail = getattr(exc, "returncode", exc)
        print(f"  remote: compare failed ({detail})")
    print()

# --- gitSkills channel ---
print("gitSkills (allowlisted git sources, read-only)")
print()
home_skill = Path.home() / ".cursor/skills/cursor-github-marketplace-repin"
keep_path = Path(os.environ["CURSOR_REPIN_KEEP_FILE"]) if os.environ.get("CURSOR_REPIN_KEEP_FILE", "").strip() else home_skill / "keep.local.json"
allow_path = Path(os.environ["CURSOR_REPIN_GIT_SKILLS_ALLOWLIST"]) if os.environ.get("CURSOR_REPIN_GIT_SKILLS_ALLOWLIST", "").strip() else script_dir / "git-skills.allowlist.json"
if not allow_path.is_file():
    allow_path = script_dir / "git-skills.allowlist.json.example"

if not allow_path.is_file():
    print("  note: no allowlist file found")
    print()
    sys.exit(0)

allow = json.loads(allow_path.read_text(encoding="utf-8"))
sources = {s["name"]: s for s in allow.get("sources", []) if isinstance(s, dict) and s.get("name")}
wanted = []
if keep_path.is_file():
    keep = json.loads(keep_path.read_text(encoding="utf-8"))
    wanted = keep.get("gitSkills") or []
else:
    print(f"  note: keep.local.json missing ({keep_path}) — no gitSkills requested")
    print()
    sys.exit(0)

if not wanted:
    print("  note: gitSkills array empty or absent in keep.local.json")
    print()
    sys.exit(0)

for entry in wanted:
    if not isinstance(entry, dict):
        print("  status: bad gitSkills entry (not an object)")
        continue
    name = entry.get("name") or ""
    ref = entry.get("ref") or ""
    print(f"== gitSkill {name or '?'} ==")
    src = sources.get(name)
    if not src:
        print("  status: NOT ALLOWLISTED")
        print()
        continue
    git_url = src.get("gitUrl") or ""
    skill_path = src.get("skillPath") or ""
    install_dir = os.path.expanduser(src.get("installDir") or "")
    print(f"  gitUrl: {git_url}")
    print(f"  wantRef: {ref}")
    print(f"  skillPath: {skill_path}")
    print(f"  installDir: {install_dir}")
    if ref not in (src.get("allowedRefs") or []):
        print(f"  status: REF NOT ALLOWED (allowedRefs={src.get('allowedRefs')})")
        print()
        continue
    remote_sha = resolve_ref_sha(git_url, ref)
    print(f"  remoteSha: {remote_sha or '(unresolved)'}")
    meta_path = Path(install_dir) / ".repin-git-skill.json" if install_dir else None
    skill_file = Path(install_dir) / "SKILL.md" if install_dir else None
    if not meta_path or not meta_path.is_file() or not skill_file or not skill_file.is_file():
        print("  status: MISSING — run scripts/install-git-skills.sh")
        print()
        continue
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        print("  status: BROKEN meta (.repin-git-skill.json)")
        print()
        continue
    installed_sha = meta.get("resolvedSha") or ""
    installed_hash = meta.get("sha256") or ""
    print(f"  installedSha: {installed_sha}")
    print(f"  installedSha256: {installed_hash}")
    if remote_sha and installed_sha == remote_sha:
        print("  status: PIN MATCHES allowlisted ref")
    elif remote_sha:
        print("  status: STALE — run scripts/install-git-skills.sh")
    else:
        print("  status: INSTALLED (remote sha unresolved)")
    print()
PY
