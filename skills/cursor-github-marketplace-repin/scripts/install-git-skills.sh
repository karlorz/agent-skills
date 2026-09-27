#!/usr/bin/env bash
# Install allowlisted gitSkills from keep.local.json into namespaced dirs.
# Fail closed: only https://github.com/karlorz/* URLs present in the allowlist.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_SKILL_DIR="${HOME}/.cursor/skills/cursor-github-marketplace-repin"
KEEP_LOCAL="${CURSOR_REPIN_KEEP_FILE:-$HOME_SKILL_DIR/keep.local.json}"
ALLOWLIST="${CURSOR_REPIN_GIT_SKILLS_ALLOWLIST:-$SCRIPT_DIR/git-skills.allowlist.json}"
if [[ ! -f "$ALLOWLIST" && -f "$SCRIPT_DIR/git-skills.allowlist.json.example" ]]; then
  ALLOWLIST="$SCRIPT_DIR/git-skills.allowlist.json.example"
fi

clean_env() {
  # Drop portfolio-lab LD_LIBRARY_PATH that SIGSEGVs git-remote-https on the box.
  env -u LD_LIBRARY_PATH \
    -u DYLD_LIBRARY_PATH \
    GIT_EXEC_PATH="${GIT_EXEC_PATH:-/usr/lib/git-core}" \
    PATH="${PATH}" \
    HOME="${HOME}" \
    GH_TOKEN="${GH_TOKEN-}" \
    GITHUB_TOKEN="${GITHUB_TOKEN-}" \
    "$@"
}

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "$ALLOWLIST" ]] || fail "allowlist missing ($ALLOWLIST)"
[[ -f "$KEEP_LOCAL" ]] || fail "keep.local.json missing ($KEEP_LOCAL)"

python3 - "$ALLOWLIST" "$KEEP_LOCAL" <<'PY'
import hashlib, json, os, re, subprocess, sys, tempfile, urllib.request
from datetime import datetime, timezone
from pathlib import Path

allowlist_path, keep_path = Path(sys.argv[1]), Path(sys.argv[2])
allow = json.loads(allowlist_path.read_text(encoding="utf-8"))
keep = json.loads(keep_path.read_text(encoding="utf-8"))
sources = {s["name"]: s for s in allow.get("sources", []) if isinstance(s, dict) and s.get("name")}
wanted = keep.get("gitSkills") or []
if not isinstance(wanted, list):
    print("FAIL: keep.local.json gitSkills must be an array", file=sys.stderr)
    sys.exit(1)
if not wanted:
    print("gitSkills: none requested in keep.local.json")
    sys.exit(0)

URL_RE = re.compile(r"^https://github\.com/karlorz/[A-Za-z0-9_.-]+(?:\.git)?$")
PATH_RE = re.compile(r"^skills/[a-z0-9-]+/SKILL\.md$")


def clean_env():
    env = dict(os.environ)
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("DYLD_LIBRARY_PATH", None)
    for key in list(env):
        val = env.get(key) or ""
        if "portfolio-lab/toolchain" in val and "LIBRARY" in key.upper():
            env.pop(key, None)
    env["GIT_EXEC_PATH"] = "/usr/lib/git-core"
    return env


def run(cmd):
    return subprocess.check_output(cmd, text=True, env=clean_env()).strip()


def gh_api(path):
    return json.loads(run(["gh", "api", path]))


def resolve_sha(git_url: str, ref: str) -> str:
    # Prefer gh for karlorz/owner-repo
    m = re.match(r"https://github\.com/([^/]+)/([^/.]+)(?:\.git)?$", git_url)
    if not m:
        raise SystemExit(f"FAIL: cannot parse gitUrl {git_url}")
    owner, repo = m.group(1), m.group(2)
    # try branch then tag then commit
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
        except subprocess.CalledProcessError:
            continue
    # commit sha?
    if re.fullmatch(r"[0-9a-f]{40}", ref):
        return ref
    # git ls-remote fallback
    out = run(["/usr/bin/git", "ls-remote", git_url, ref, f"refs/heads/{ref}", f"refs/tags/{ref}"])
    for line in out.splitlines():
        sha, name = line.split("\t", 1)
        if name.endswith(f"refs/heads/{ref}") or name.endswith(f"refs/tags/{ref}") or name == ref:
            return sha
    raise SystemExit(f"FAIL: could not resolve ref {ref} for {git_url}")


def fetch_skill_md(owner: str, repo: str, skill_path: str, sha: str) -> bytes:
    # Contents API returns base64 for files
    import base64
    path = skill_path.lstrip("/")
    data = gh_api(f"repos/{owner}/{repo}/contents/{path}?ref={sha}")
    if data.get("type") != "file":
        raise SystemExit(f"FAIL: {skill_path} is not a file at {sha}")
    return base64.b64decode(data["content"])


def expand_install_dir(raw: str) -> Path:
    return Path(os.path.expanduser(raw)).resolve()


for entry in wanted:
    if not isinstance(entry, dict):
        raise SystemExit("FAIL: gitSkills entries must be objects")
    name = entry.get("name") or ""
    ref = entry.get("ref") or ""
    if not name or not ref:
        raise SystemExit("FAIL: gitSkills entry needs name and ref")
    src = sources.get(name)
    if not src:
        raise SystemExit(f"FAIL: {name!r} not in allowlist")
    git_url = src.get("gitUrl") or ""
    skill_path = src.get("skillPath") or ""
    install_dir = src.get("installDir") or ""
    allowed_refs = src.get("allowedRefs") or []
    if not URL_RE.match(git_url):
        raise SystemExit(f"FAIL: gitUrl not allowlisted host/owner shape: {git_url}")
    if ref not in allowed_refs:
        raise SystemExit(f"FAIL: ref {ref!r} not in allowedRefs for {name}")
    if not PATH_RE.match(skill_path):
        raise SystemExit(f"FAIL: skillPath rejected: {skill_path}")
    if "_git-sources/" not in install_dir.replace("\\", "/"):
        raise SystemExit(f"FAIL: installDir must be under ~/.cursor/skills/_git-sources/: {install_dir}")

    m = re.match(r"https://github\.com/([^/]+)/([^/.]+)(?:\.git)?$", git_url)
    owner, repo = m.group(1), m.group(2)
    sha = resolve_sha(git_url, ref)
    body = fetch_skill_md(owner, repo, skill_path, sha)
    digest = hashlib.sha256(body).hexdigest()
    dest = expand_install_dir(install_dir)
    dest.mkdir(parents=True, exist_ok=True)
    skill_out = dest / "SKILL.md"
    meta_out = dest / ".repin-git-skill.json"
    tmp = dest / f".SKILL.md.tmp.{os.getpid()}"
    tmp.write_bytes(body)
    tmp.replace(skill_out)
    meta = {
        "name": name,
        "gitUrl": git_url,
        "ref": ref,
        "resolvedSha": sha,
        "skillPath": skill_path,
        "sha256": digest,
        "installDir": str(dest),
        "installedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    meta_out.write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    print(f"installed {name} ref={ref} sha={sha} sha256={digest} -> {skill_out}")
PY
