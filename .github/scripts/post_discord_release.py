#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Post latest CHANGELOG.md to Discord after a successful GitHub release.

Preferred: Warband Nexus Discord **bot** (REST API, no 24/7 process required).
  DISCORD_BOT_TOKEN          — Bot token from Discord Developer Portal
  DISCORD_RELEASE_CHANNEL_ID — Target text channel snowflake ID

Legacy fallback (optional):
  DISCORD_RELEASE_WEBHOOK    — Incoming webhook URL

Skips with exit 0 when neither bot nor webhook is configured.
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

DISCORD_API = "https://discord.com/api/v10"
DISCORD_EMBED_DESC_LIMIT = 4096
DISCORD_EMBED_TITLE_LIMIT = 256

CF_PROJECT_URL = "https://www.curseforge.com/wow/addons/warband-nexus"
WAGO_PROJECT_URL = "https://addons.wago.io/addons/warband-nexus"
GITHUB_RELEASES_URL = "https://github.com/Astraphobiaa/warband-nexus/releases"


def read_toc_version() -> str:
    text = TOC.read_text(encoding="utf-8")
    m = re.search(r"(?m)^## Version:\s*(.+)\s*$", text)
    if not m:
        raise SystemExit("Could not parse ## Version from WarbandNexus.toc")
    return m.group(1).strip()


def extract_latest_changelog_section() -> tuple[str, str]:
    text = CHANGELOG.read_text(encoding="utf-8")
    matches = list(re.finditer(r"(?m)^## (v[^\n]+)\n", text))
    if not matches:
        raise SystemExit("No ## vX.Y.Z section found in CHANGELOG.md")
    start = matches[0].start()
    end = matches[1].start() if len(matches) > 1 else len(text)
    header = matches[0].group(1).strip()
    body = text[start:end].strip()
    body = re.sub(r"^### ", "**", body, flags=re.MULTILINE)
    body = re.sub(r"(?m)^\*\*(Fixed|Updated|Added)\*\*$", r"**\1:**", body)
    return header, body


def build_payload(version: str, header: str, body: str) -> dict:
    title = f"Warband Nexus {version} released"
    if len(title) > DISCORD_EMBED_TITLE_LIMIT:
        title = title[: DISCORD_EMBED_TITLE_LIMIT - 3] + "..."

    description = body
    if len(description) > DISCORD_EMBED_DESC_LIMIT:
        description = description[: DISCORD_EMBED_DESC_LIMIT - 20] + "\n\n...(truncated)"

    return {
        "embeds": [
            {
                "title": title,
                "description": description,
                "color": 0x58A6FF,
                "footer": {"text": header},
                "fields": [
                    {
                        "name": "Download",
                        "value": f"[CurseForge]({CF_PROJECT_URL}) · [Wago]({WAGO_PROJECT_URL}) · [GitHub Releases]({GITHUB_RELEASES_URL})",
                        "inline": False,
                    }
                ],
            }
        ],
    }


def post_json(url: str, payload: dict, headers: dict) -> None:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={**headers, "Content-Type": "application/json", "User-Agent": "warband-nexus-release/2.0"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(f"Discord notify OK (HTTP {resp.status})")


def send_via_bot(token: str, channel_id: str, payload: dict) -> None:
    url = f"{DISCORD_API}/channels/{channel_id}/messages"
    post_json(url, payload, {"Authorization": f"Bot {token}"})


def send_via_webhook(webhook_url: str, payload: dict) -> None:
    webhook_payload = {"username": "Warband Nexus Releases", **payload}
    post_json(webhook_url, webhook_payload, {})


def main() -> int:
    token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    channel_id = os.environ.get("DISCORD_RELEASE_CHANNEL_ID", "").strip()
    webhook = os.environ.get("DISCORD_RELEASE_WEBHOOK", "").strip()

    if token and not channel_id:
        print("DISCORD_BOT_TOKEN set but DISCORD_RELEASE_CHANNEL_ID missing.", file=sys.stderr)
        return 1
    if channel_id and not token:
        print("DISCORD_RELEASE_CHANNEL_ID set but DISCORD_BOT_TOKEN missing.", file=sys.stderr)
        return 1
    if not token and not webhook:
        print("Discord bot/webhook not configured — skipping Discord notify.")
        return 0

    version = read_toc_version()
    header, body = extract_latest_changelog_section()
    payload = build_payload(version, header, body)

    try:
        if token and channel_id:
            print(f"Posting release {version} via Discord bot to channel {channel_id}.")
            send_via_bot(token, channel_id, payload)
        else:
            print(f"Posting release {version} via Discord webhook (legacy).")
            send_via_webhook(webhook, payload)
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"Discord API failed: HTTP {e.code} {err_body}", file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"Discord API error: {e}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
