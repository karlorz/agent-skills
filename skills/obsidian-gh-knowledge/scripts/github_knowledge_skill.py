#!/usr/bin/env python3
import argparse
import base64
import json
import subprocess
import sys
from urllib.parse import quote


def _quote_path(path: str) -> str:
    return quote(path, safe="/")


class GitHubKnowledgeManager:
    def __init__(self, repo: str):
        self.repo = repo

    def run_gh_command(self, command):
        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True)
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            print(f"Error executing command: {' '.join(command)}", file=sys.stderr)
            if e.stderr:
                print(e.stderr, file=sys.stderr)
            sys.exit(1)

    def _contents_endpoint(self, path: str) -> str:
        if not path:
            return f"repos/{self.repo}/contents"
        return f"repos/{self.repo}/contents/{_quote_path(path)}"

    def list_files(self, path: str = ""):
        cmd = ["gh", "api", self._contents_endpoint(path)]
        output = self.run_gh_command(cmd)
        try:
            return json.loads(output)
        except json.JSONDecodeError:
            return output

    def read_file(self, file_path: str) -> str:
        cmd = [
            "gh",
            "api",
            self._contents_endpoint(file_path),
            "-H",
            "Accept: application/vnd.github.v3.raw",
        ]
        return self.run_gh_command(cmd)

    def search_code(self, query: str) -> str:
        cmd = [
            "gh",
            "search",
            "code",
            query,
            "--repo",
            self.repo,
            "--json",
            "path,repository",
        ]
        return self.run_gh_command(cmd)

    def get_default_branch(self) -> str:
        cmd = [
            "gh",
            "repo",
            "view",
            self.repo,
            "--json",
            "defaultBranchRef",
            "-q",
            ".defaultBranchRef.name",
        ]
        return self.run_gh_command(cmd)

    def create_branch(self, branch_name: str, base_branch: str) -> str:
        base_ref_cmd = [
            "gh",
            "api",
            f"repos/{self.repo}/git/refs/heads/{quote(base_branch, safe='')}",
        ]
        base_ref = json.loads(self.run_gh_command(base_ref_cmd))
        sha = base_ref["object"]["sha"]

        create_ref_cmd = [
            "gh",
            "api",
            f"repos/{self.repo}/git/refs",
            "-f",
            f"ref=refs/heads/{branch_name}",
            "-f",
            f"sha={sha}",
        ]
        return self.run_gh_command(create_ref_cmd)

    def commit_file(self, file_path: str, content: str, message: str, branch: str) -> str:
        content_b64 = base64.b64encode(content.encode()).decode()

        sha = None
        try:
            check_cmd = [
                "gh",
                "api",
                self._contents_endpoint(file_path),
                "-f",
                f"ref={branch}",
            ]
            file_data = json.loads(self.run_gh_command(check_cmd))
            if "sha" in file_data:
                sha = file_data["sha"]
        except SystemExit:
            pass

        cmd = [
            "gh",
            "api",
            self._contents_endpoint(file_path),
            "-X",
            "PUT",
            "-f",
            f"message={message}",
            "-f",
            f"content={content_b64}",
            "-f",
            f"branch={branch}",
        ]
        if sha:
            cmd.extend(["-f", f"sha={sha}"])

        return self.run_gh_command(cmd)

    def delete_file(self, file_path: str, message: str, branch: str) -> str:
        get_sha_cmd = [
            "gh",
            "api",
            self._contents_endpoint(file_path),
            "-f",
            f"ref={branch}",
        ]
        file_data = json.loads(self.run_gh_command(get_sha_cmd))
        sha = file_data["sha"]

        cmd = [
            "gh",
            "api",
            self._contents_endpoint(file_path),
            "-X",
            "DELETE",
            "-f",
            f"message={message}",
            "-f",
            f"sha={sha}",
            "-f",
            f"branch={branch}",
        ]
        return self.run_gh_command(cmd)


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage GitHub repo knowledge via CLI")
    parser.add_argument("--repo", required=True, help="Repository name (owner/repo)")

    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="List files in path")
    list_parser.add_argument("--path", default="", help="Path to list")

    read_parser = subparsers.add_parser("read", help="Read file content")
    read_parser.add_argument("file_path", help="Path to file")

    search_parser = subparsers.add_parser("search", help="Search code")
    search_parser.add_argument("query", help="Search query")

    move_parser = subparsers.add_parser("move", help="Move file (creates branch/commit)")
    move_parser.add_argument("src", help="Source path")
    move_parser.add_argument("dest", help="Destination path")
    move_parser.add_argument("--branch", default="organize-notes", help="Branch name")
    move_parser.add_argument("--message", default="Organize notes via agent", help="Commit message")

    args = parser.parse_args()
    manager = GitHubKnowledgeManager(args.repo)

    if args.command == "list":
        print(json.dumps(manager.list_files(args.path), indent=2))
        return

    if args.command == "read":
        print(manager.read_file(args.file_path))
        return

    if args.command == "search":
        print(manager.search_code(args.query))
        return

    if args.command == "move":
        branch_encoded = quote(args.branch, safe="")
        try:
            manager.run_gh_command(["gh", "api", f"repos/{args.repo}/branches/{branch_encoded}"])
        except SystemExit:
            default_branch = manager.get_default_branch()
            print(f"Creating branch {args.branch} from {default_branch}...")
            manager.create_branch(args.branch, default_branch)

        print(f"Reading {args.src}...")
        content = manager.read_file(args.src)

        print(f"Creating {args.dest}...")
        manager.commit_file(args.dest, content, args.message, args.branch)

        print(f"Deleting {args.src}...")
        manager.delete_file(args.src, args.message, args.branch)

        print(f"Moved {args.src} to {args.dest} on branch {args.branch}")
        return


if __name__ == "__main__":
    main()
