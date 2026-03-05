#!/usr/bin/env python3
import argparse
import datetime
import json
import os
import shlex
import subprocess
import sys


def _expand_path(path: str) -> str:
    return os.path.abspath(os.path.expanduser(os.path.expandvars(path)))


def _default_vault_dir() -> str:
    config_path = _expand_path("~/.config/obsidian-gh-knowledge/config.json")
    if os.path.exists(config_path):
        try:
            with open(config_path, "r", encoding="utf-8") as f:
                config = json.load(f)
            local_vault_path = config.get("local_vault_path")
            if isinstance(local_vault_path, str) and local_vault_path.strip():
                return _expand_path(local_vault_path)
        except (OSError, json.JSONDecodeError):
            pass
    return _expand_path("~/Documents/obsidian_vault")


def _run(cmd: list[str], *, cwd: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, check=check)


def _format_cmd(cmd: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in cmd)


def _die(message: str, *, exit_code: int = 2) -> None:
    print(message, file=sys.stderr)
    sys.exit(exit_code)


def _git_stdout(args: list[str], *, cwd: str) -> str:
    try:
        result = _run(["git", *args], cwd=cwd, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        stderr = (e.stderr or "").strip()
        stdout = (e.stdout or "").strip()
        details = "\n".join([part for part in [stdout, stderr] if part])
        if details:
            _die(f"Git command failed: {_format_cmd(['git', *args])}\n{details}", exit_code=e.returncode)
        _die(f"Git command failed: {_format_cmd(['git', *args])}", exit_code=e.returncode)


def _git_ok(args: list[str], *, cwd: str) -> bool:
    return _run(["git", *args], cwd=cwd, check=False).returncode == 0


def _now_message() -> str:
    return "Vault sync (agent): " + datetime.datetime.now().strftime("%Y-%m-%d %H:%M")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sync a local Obsidian vault git repo: pull (rebase), commit, and push."
    )
    parser.add_argument(
        "--vault-dir",
        default=None,
        help="Local vault directory. Default: local_vault_path from config.json, else ~/Documents/obsidian_vault",
    )
    parser.add_argument("--message", default=None, help="Commit message (default: timestamped sync message)")
    parser.add_argument(
        "--paths",
        nargs="*",
        default=None,
        help='Optional paths to stage (default: "git add -A")',
    )
    parser.add_argument("--no-pull", action="store_true", help="Skip git pull --rebase --autostash")
    parser.add_argument("--no-push", action="store_true", help="Skip git push")
    parser.add_argument("--dry-run", action="store_true", help="Print planned commands without changing anything")

    args = parser.parse_args()

    vault_dir = _expand_path(args.vault_dir) if args.vault_dir else _default_vault_dir()
    if not os.path.isdir(vault_dir):
        _die(f"Vault directory does not exist: {vault_dir}")

    if not _git_ok(["rev-parse", "--is-inside-work-tree"], cwd=vault_dir):
        _die(f"Not a git repo: {vault_dir}")

    branch = _git_stdout(["branch", "--show-current"], cwd=vault_dir).strip()
    if not branch:
        _die("Detached HEAD: checkout a branch before syncing.")

    if not args.no_push and not _git_ok(["remote", "get-url", "origin"], cwd=vault_dir):
        _die('Missing git remote "origin": set a remote or run with --no-push.')

    planned: list[list[str]] = []

    if not args.no_pull:
        planned.append(["git", "pull", "--rebase", "--autostash"])

    status_before = _git_stdout(["status", "--porcelain=v1"], cwd=vault_dir)
    has_changes = bool(status_before.strip())
    if has_changes:
        if args.paths:
            planned.append(["git", "add", "--", *args.paths])
        else:
            planned.append(["git", "add", "-A"])

        message = (args.message or "").strip() or _now_message()
        planned.append(["git", "commit", "-m", message])

        if not args.no_pull:
            planned.append(["git", "pull", "--rebase"])

    if not args.no_push:
        planned.append(["git", "push", "-u", "origin", "HEAD"])

    if args.dry_run:
        print(f"Vault: {vault_dir}")
        print(f"Branch: {branch}")
        print("Planned:")
        for cmd in planned:
            print(f"  - {_format_cmd(cmd)}")
        return

    for cmd in planned:
        print(f"+ {_format_cmd(cmd)}")
        if cmd[0] != "git":
            _die(f"Unexpected command (internal error): {cmd[0]}", exit_code=1)
        _git_stdout(cmd[1:], cwd=vault_dir)

    print("Done.")


if __name__ == "__main__":
    main()
