#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Post latest CHANGELOG.md to Discord after a successful GitHub release."""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from discord_common import post_message, post_or_skip, send_embed, truncate

ROOT = Path(__file__).resolve().parents[2]
CHANGELOG = ROOT / "CHANGELOG.md"
TOC = ROOT / "WarbandNexus.toc"

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
    # Drop the "## vX.Y.Z" line: it is already the embed title, and leaving it in made
    # Discord render the version and the first section header as one run-on line.
    body = re.sub(r"(?m)\A## v[^\n]*\n+", "", body)
    # "### Added" -> "**Added:**" in ONE step. Turning the "### " prefix into "**" and then
    # looking for "**Added**" never matched, because nothing had closed the bold. Discord got
    # an unterminated "**Added", which bolds everything up to the next "**" and swallows the
    # bullet list into the heading.
    body = re.sub(r"(?m)^#{2,3} +(.+?)\s*$", r"**\1:**", body)
    return header, body


# Discord caps message content at 2000 characters (embed descriptions at 4096).
CONTENT_LIMIT = 2000
ANNOUNCE_FOOTER = (
    f"{CF_PROJECT_URL}\n\n"
    f"{WAGO_PROJECT_URL}\n\n"
    "⚠️ New version will be available in a couple minutes. ⚠️ @everyone"
)


def build_announcement(version: str, body: str) -> dict:
    """Announcements-channel post: the release's changelog, then the store links and the
    @everyone heads-up (CurseForge / Wago still process the upload for a few minutes).

    Plain message text when it fits Discord's 2000-character limit; otherwise the changelog
    moves into an embed and the text keeps the links + mention (an embed cannot ping).
    """
    title = f"**Warband Nexus v{version.lstrip('v')}**"
    text = f"{title}\n\n{body}\n\n{ANNOUNCE_FOOTER}"
    # Only @everyone may ping: changelog text never mentions roles or users by accident.
    mentions = {"parse": ["everyone"]}
    if len(text) <= CONTENT_LIMIT:
        return {"content": text, "allowed_mentions": mentions}
    return {
        "content": f"{title}\n\n{ANNOUNCE_FOOTER}",
        "allowed_mentions": mentions,
        "embeds": [{
            "title": truncate(f"Warband Nexus v{version.lstrip('v')}", 256),
            "description": truncate(body, 4096),
            "color": 0x58A6FF,
        }],
    }


def post_webhook(url: str, payload: dict) -> None:
    import json
    import urllib.request

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "User-Agent": "warband-nexus-release/2.0"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(f"Discord announcement OK HTTP {resp.status}")


def post_announcement(version: str, body: str) -> None:
    """Second post, to the announcements channel. Preferred route: that channel's webhook
    (DISCORD_ANNOUNCEMENTS_WEBHOOK; a webhook may ping @everyone, no bot needed). Fallback:
    the release bot + DISCORD_ANNOUNCEMENTS_CHANNEL_ID. Skipped when neither is set, so the
    release-channel post works on its own.

    DISCORD_ANNOUNCE_NO_EVERYONE=1 drops the @everyone ping (manual test runs)."""
    payload = build_announcement(version, body)
    if os.environ.get("DISCORD_ANNOUNCE_NO_EVERYONE", "").strip() in ("1", "true"):
        payload["content"] = payload["content"].replace(" @everyone", "")
        payload["allowed_mentions"] = {"parse": []}
    webhook = os.environ.get("DISCORD_ANNOUNCEMENTS_WEBHOOK", "").strip()
    if webhook:
        print(f"Posting release {version} announcement via webhook.")
        payload["username"] = "Warband Nexus"
        post_webhook(webhook, payload)
        return
    token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    channel = os.environ.get("DISCORD_ANNOUNCEMENTS_CHANNEL_ID", "").strip()
    if not (token and channel):
        print("Discord announcements channel not configured - skip.")
        return
    print(f"Posting release {version} announcement to channel {channel}.")
    post_message(token, channel, payload)


def main() -> int:
    if "--announce-only" in sys.argv[1:]:
        # Manual run (Discord announcement workflow): the announcement alone, errors fail the run.
        _, only_body = extract_latest_changelog_section()
        post_announcement(read_toc_version(), only_body)
        return 0

    if "--preview-announcement" in sys.argv[1:]:
        # Local check of the exact announcement text; sends nothing.
        _, preview_body = extract_latest_changelog_section()
        payload = build_announcement(read_toc_version(), preview_body)
        print(payload.get("content", ""))
        if payload.get("embeds"):
            print("\n[embed]\n" + payload["embeds"][0]["description"])
        return 0

    try:
        _, announce_body = extract_latest_changelog_section()
        post_announcement(read_toc_version(), announce_body)
    except Exception as exc:  # never fail the release over the announcement
        print(f"Discord announcement failed: {exc}")

    webhook = os.environ.get("DISCORD_RELEASE_WEBHOOK", "").strip()
    token = os.environ.get("DISCORD_BOT_TOKEN", "").strip()
    channel_id = os.environ.get("DISCORD_RELEASE_CHANNEL_ID", "").strip()

    if not (token and channel_id) and not webhook:
        print("Discord release notify not configured — skip.")
        return 0

    version = read_toc_version()
    header, body = extract_latest_changelog_section()
    title = f"Warband Nexus {version} released"
    fields = [
        {
            "name": "Download",
            "value": f"[CurseForge]({CF_PROJECT_URL}) · [Wago]({WAGO_PROJECT_URL}) · [GitHub Releases]({GITHUB_RELEASES_URL})",
            "inline": False,
        }
    ]

    if token and channel_id:
        print(f"Posting release {version} via bot to channel {channel_id}.")
        send_embed(
            token,
            channel_id,
            title=title,
            description=body,
            footer=header,
            fields=fields,
        )
        return 0

    # Legacy webhook fallback
    import json
    import urllib.request

    payload = {
        "username": "Warband Nexus Releases",
        "embeds": [
            {
                "title": truncate(title, 256),
                "description": truncate(body, 4096),
                "color": 0x58A6FF,
                "footer": {"text": header},
                "fields": fields,
            }
        ],
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        webhook,
        data=data,
        headers={"Content-Type": "application/json", "User-Agent": "warband-nexus-release/2.0"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(f"Discord webhook OK HTTP {resp.status}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
