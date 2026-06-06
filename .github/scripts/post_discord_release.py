#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Post latest CHANGELOG.md section to Discord via webhook (GitHub Actions release step).

Env: DISCORD_RELEASE_WEBHOOK (required to send; skips with exit 0 if unset).
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHANGELOG = ROOT / "CHANGELOG.md"
TOC = ROOT / "WarbandNexus.toc"

DISCORD_EMBED_DESC_LIMIT = 4096
DISCORD_EMBED_TITLE_LIMIT = 256


def read_toc_version() -> str:
    text = TOC.read_text(encoding="utf-8")
    m = re.search(r"(?m)^## Version:\s*(.+)\s*$", text)
    if not m:
        raise SystemExit("Could not parse ## Version from WarbandNexus.toc")
    return m.group(1).strip()


def extract_latest_changelog_section() -> tuple[str, str]:
    text = CHANGELOG.read_text(encoding="utf-8")
    # First ## vX.Y.Z block after intro (skip top-level # title)
    matches = list(re.finditer(r"(?m)^## (v[^\n]+)\n", text))
    if not matches:
        raise SystemExit("No ## vX.Y.Z section found in CHANGELOG.md")
    start = matches[0].start()
    end = matches[1].start() if len(matches) > 1 else len(text)
    header = matches[0].group(1).strip()
    body = text[start:end].strip()
    # Discord embed: markdown-ish; strip ### for readability
    body = re.sub(r"^### ", "**", body, flags=re.MULTILINE)
    body = re.sub(r"(?m)^\*\*(Fixed|Updated|Added)\*\*$", r"**\1:**", body)
    return header, body


def main() -> int:
    webhook = os.environ.get("DISCORD_RELEASE_WEBHOOK", "").strip()
    if not webhook:
        print("DISCORD_RELEASE_WEBHOOK not set — skipping Discord notify.")
        return 0

    version = read_toc_version()
    header, body = extract_latest_changelog_section()
    title = f"Warband Nexus {version} released"
    if len(title) > DISCORD_EMBED_TITLE_LIMIT:
        title = title[: DISCORD_EMBED_TITLE_LIMIT - 3] + "..."

    description = body
    if len(description) > DISCORD_EMBED_DESC_LIMIT:
        description = description[: DISCORD_EMBED_DESC_LIMIT - 20] + "\n\n...(truncated)"

    payload = {
        "username": "Warband Nexus Releases",
        "embeds": [
            {
                "title": title,
                "description": description,
                "color": 0x58a6ff,
                "footer": {"text": header},
            }
        ],
    }

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        webhook,
        data=data,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "warband-nexus-release/1.0",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            print(f"Discord notify OK (HTTP {resp.status})")
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"Discord webhook failed: HTTP {e.code} {err_body}", file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"Discord webhook error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
