#!/usr/bin/env python3
import argparse
import json
import re
import sys


DEFAULT_INTERVAL = "10m"
JOB_ID_RE = r"(loop-[A-Za-z0-9-]+)"
UNIT_RE = r"(seconds?|secs?|sec|s|minutes?|mins?|min|m|hours?|hrs?|hr|h|days?|day|d)"
DRY_RUN_PATTERNS = [
    r"\bdry[- ]run\b",
    r"\buse\s+dry[- ]run\b",
    r"\bin\s+dry[- ]run\s+mode\b",
]
NO_RUN_NOW_PATTERNS = [
    r"\bdo\s+not\s+run\s+now\b",
    r"\bdon['’]t\s+run\s+now\b",
    r"\bwithout\s+running\s+now\b",
    r"\bskip\s+initial\s+run\b",
    r"\bdo\s+not\s+execute\s+now\b",
    r"\bdon['’]t\s+execute\s+now\b",
    r"\bno\s+run\s+now\b",
]
FILLER_TOKENS = {"a", "an", "and", "in", "mode", "now", "please", "the", "use", "with"}


def normalize_interval(count: str, unit: str) -> str:
    unit = unit.lower()
    mapping = {
        "s": "s",
        "sec": "s",
        "secs": "s",
        "second": "s",
        "seconds": "s",
        "m": "m",
        "min": "m",
        "mins": "m",
        "minute": "m",
        "minutes": "m",
        "h": "h",
        "hr": "h",
        "hrs": "h",
        "hour": "h",
        "hours": "h",
        "d": "d",
        "day": "d",
        "days": "d",
    }
    suffix = mapping.get(unit)
    if suffix is None:
        raise ValueError(f"unsupported unit: {unit}")
    return f"{count}{suffix}"


def strip_leading_skill_token(text: str) -> str:
    return re.sub(r"^\s*\$loop\b[:\s-]*", "", text, flags=re.IGNORECASE).strip()


def strip_soft_wrappers(text: str) -> str:
    text = re.sub(
        r"^\s*(?:please\s+)?(?:create|add|schedule)\s+(?:a\s+)?(?:recurring\s+)?(?:loop\s+)?(?:job|task)?\b",
        "",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(r"^\s*(?:in|for)\s+the\s+current\s+workspace\b", "", text, flags=re.IGNORECASE)
    text = re.sub(r"^\s*(?:with|to)\b", "", text, flags=re.IGNORECASE)
    return text.strip(" ,")


def extract_flag(text: str, patterns: list[str]) -> tuple[str, bool]:
    matched = False
    for pattern in patterns:
        text, replacements = re.subn(pattern, " ", text, flags=re.IGNORECASE)
        if replacements:
            matched = True
    return re.sub(r"\s+", " ", text).strip(), matched


def strip_modifier_clauses(text: str) -> str:
    clauses = re.split(r"[.;]\s*", text)
    kept: list[str] = []

    for clause in clauses:
        candidate = clause.strip()
        if not candidate:
            continue

        candidate, _ = extract_flag(candidate, DRY_RUN_PATTERNS)
        candidate, _ = extract_flag(candidate, NO_RUN_NOW_PATTERNS)
        tokens = re.findall(r"[A-Za-z']+", candidate.lower())
        if tokens and all(token in FILLER_TOKENS for token in tokens):
            continue

        candidate = re.sub(r"\s+", " ", candidate).strip(" ,")
        if candidate:
            kept.append(candidate)

    return ". ".join(kept).strip()


def parse_management(text: str) -> dict | None:
    normalized = text.strip()
    command_patterns = [
        ("list", rf"^(?:list|ls|show(?:\s+jobs)?|list\s+jobs)\s*[.!?]?$"),
        ("status", rf"^(?:status|health|scheduler\s+status)\s*[.!?]?$"),
        ("logs", rf"^(?:logs?|show\s+logs?)(?:\s+for)?\s+{JOB_ID_RE}\s*[.!?]?$"),
        ("remove", rf"^(?:remove|delete|cancel)(?:\s+job)?\s+{JOB_ID_RE}\s*[.!?]?$"),
        ("run", rf"^(?:run|trigger|execute)(?:\s+job)?\s+{JOB_ID_RE}\s*[.!?]?$"),
    ]

    for action, pattern in command_patterns:
        match = re.match(pattern, normalized, flags=re.IGNORECASE)
        if not match:
            continue
        payload = {
            "action": action,
            "parse_mode": "management_command",
            "request": normalized,
        }
        if action in {"logs", "remove", "run"}:
            payload["job_id"] = match.group(1)
        return payload
    return None


def parse_explicit_fields(text: str) -> dict | None:
    interval_match = re.search(
        rf"\binterval\s+(?P<count>\d+)\s*(?P<unit>{UNIT_RE})\b", text, flags=re.IGNORECASE
    )
    prompt_match = re.search(r"\bprompt\s+([\"'])(?P<prompt>.+?)\1", text, flags=re.IGNORECASE)

    if not interval_match and not prompt_match:
        return None

    interval = DEFAULT_INTERVAL
    if interval_match:
        interval = normalize_interval(interval_match.group("count"), interval_match.group("unit"))

    prompt = None
    if prompt_match:
        prompt = prompt_match.group("prompt").strip()

    if not prompt:
        remainder = text
        if interval_match:
            remainder = remainder.replace(interval_match.group(0), " ")
        remainder = re.sub(r"\bprompt\b", " ", remainder, flags=re.IGNORECASE)
        remainder = strip_soft_wrappers(remainder)
        prompt = re.sub(r"\s+", " ", remainder).strip(" .,!?:;")

    if not prompt:
        return None

    return {
        "action": "add",
        "parse_mode": "explicit_fields",
        "interval": interval,
        "prompt": prompt,
    }


def parse_add(text: str) -> dict:
    cleaned = text.strip()

    explicit = parse_explicit_fields(cleaned)
    if explicit is not None:
        return explicit

    leading = re.match(rf"^(?P<interval>\d+[smhd])\s+(?P<prompt>.+?)\s*$", cleaned, flags=re.IGNORECASE)
    if leading:
        return {
            "action": "add",
            "parse_mode": "leading_interval",
            "interval": leading.group("interval").lower(),
            "prompt": leading.group("prompt").strip(),
        }

    trailing = re.match(
        rf"^(?P<prompt>.+?)\s+every\s+(?P<count>\d+)\s*(?P<unit>{UNIT_RE})\s*[.!?]?\s*$",
        cleaned,
        flags=re.IGNORECASE,
    )
    if trailing:
        return {
            "action": "add",
            "parse_mode": "trailing_every",
            "interval": normalize_interval(trailing.group("count"), trailing.group("unit")),
            "prompt": trailing.group("prompt").strip(),
        }

    prompt = strip_soft_wrappers(cleaned)
    return {
        "action": "add",
        "parse_mode": "default_interval",
        "interval": DEFAULT_INTERVAL,
        "prompt": prompt,
    }


def parse_request(text: str) -> dict:
    original = strip_leading_skill_token(text)

    _, dry_run = extract_flag(original, DRY_RUN_PATTERNS)
    _, suppress_run_now = extract_flag(original, NO_RUN_NOW_PATTERNS)
    without_no_run_now = strip_modifier_clauses(original)

    management = parse_management(without_no_run_now)
    if management is not None:
        management["dry_run"] = dry_run
        management["run_now"] = False if suppress_run_now else None
        management["raw_request"] = original
        management["normalized_request"] = without_no_run_now
        return management

    add = parse_add(without_no_run_now)
    add["dry_run"] = dry_run
    add["run_now"] = not suppress_run_now
    add["raw_request"] = original
    add["normalized_request"] = without_no_run_now
    add["prompt"] = add["prompt"].strip()
    if not add["prompt"]:
        raise ValueError("parsed prompt is empty")
    return add


def main() -> int:
    parser = argparse.ArgumentParser(description="Parse a $loop skill request into structured JSON.")
    parser.add_argument("--request", required=True, help="Raw request text after $loop")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print the JSON result")
    args = parser.parse_args()

    try:
        result = parse_request(args.request)
    except Exception as exc:
        print(json.dumps({"error": str(exc), "request": args.request}))
        return 1

    if args.pretty:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
