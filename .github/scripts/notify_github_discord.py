#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Post GitHub issue/PR opened events to Discord (GitHub Actions)."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from discord_common import post_or_skip, truncate

REPO_URL = "https://github.com/Astraphobiaa/warband-nexus"


def main() -> int:
    event_path = os.environ.get("GITHUB_EVENT_PATH", "").strip()
    if not event_path or not Path(event_path).is_file():
        print("GITHUB_EVENT_PATH missing — skip.", file=sys.stderr)
        return 0

    event = json.loads(Path(event_path).read_text(encoding="utf-8"))
    action = event.get("action", "")
    if action not in ("opened", "reopened"):
        print(f"Skip action={action!r}")
        return 0

    if "pull_request" in event:
        pr = event["pull_request"]
        number = pr.get("number")
        title = pr.get("title") or "(no title)"
        user = (pr.get("user") or {}).get("login") or "unknown"
        body = truncate((pr.get("body") or "").strip() or "(no description)", 3000)
        url = pr.get("html_url") or f"{REPO_URL}/pull/{number}"
        embed_title = f"Pull request #{number} {action}"
        color = 0x2EA043
        kind = "PR"
    elif "issue" in event:
        issue = event["issue"]
        if issue.get("pull_request"):
            print("Skip issue event that is a pull request.")
            return 0
        number = issue.get("number")
        title = issue.get("title") or "(no title)"
        user = (issue.get("user") or {}).get("login") or "unknown"
        body = truncate((issue.get("body") or "").strip() or "(no description)", 3000)
        url = issue.get("html_url") or f"{REPO_URL}/issues/{number}"
        embed_title = f"Issue #{number} {action}"
        color = 0xD29922
        kind = "Issue"
    else:
        print("Unknown event shape — skip.")
        return 0

    description = f"**{title}**\nby `{user}`\n\n{body}"
    posted = post_or_skip(
        "DISCORD_GITHUB_CHANNEL_ID",
        title=embed_title,
        description=description,
        color=color,
        footer=f"GitHub {kind}",
        url=url,
    )
    if not posted:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
