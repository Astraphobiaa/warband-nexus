#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Poll CurseForge (+ Wago when API available) for new comments; notify Discord.

Env:
  DISCORD_BOT_TOKEN
  DISCORD_COMMENTS_CHANNEL_ID   — target channel for CF/Wago comments
  CF_MOD_ID                     — default 1406501 (WarbandNexus.toc X-Curse-Project-ID)
  WAGO_PROJECT_ID               — default mKODQYGx (WarbandNexus.toc X-Wago-ID)
  WAGO_API_TOKEN                — optional; used for Wago API attempts
  HOST_COMMENTS_STATE_FILE      — default .github/state/host-comments.json

First run bootstraps seen IDs without posting (avoids flooding history).
"""
from __future__ import annotations

import html
import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from discord_common import post_or_skip, truncate

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_STATE = ROOT / ".github" / "state" / "host-comments.json"

CF_MOD_ID = os.environ.get("CF_MOD_ID", "1406501").strip()
WAGO_PROJECT_ID = os.environ.get("WAGO_PROJECT_ID", "mKODQYGx").strip()
WAGO_API_TOKEN = os.environ.get("WAGO_API_TOKEN", "").strip()

CF_PAGE = "https://www.curseforge.com/wow/addons/warband-nexus"
WAGO_PAGE = "https://addons.wago.io/addons/warband-nexus"


def http_get_json(url: str, headers: dict | None = None) -> dict | list | None:
    hdrs = {"Accept": "application/json", "User-Agent": "warband-nexus-comments/1.0"}
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, headers=hdrs, method="GET")
    try:
        with urllib.request.urlopen(req, timeout=45) as resp:
            return json.loads(resp.read().decode("utf-8", errors="replace"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:300]
        print(f"HTTP {e.code} for {url}: {body}", file=sys.stderr)
        return None
    except urllib.error.URLError as e:
        print(f"URL error for {url}: {e}", file=sys.stderr)
        return None


def strip_html(text: str) -> str:
    if not text:
        return ""
    text = re.sub(r"<br\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text)
    text = re.sub(r"\r\n?", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def flatten_cf_comments(nodes: list, out: list[dict]) -> None:
    for node in nodes or []:
        if not isinstance(node, dict):
            continue
        cid = node.get("id")
        if cid is not None:
            author = node.get("author") or {}
            out.append(
                {
                    "source": "curseforge",
                    "id": str(cid),
                    "author": author.get("displayName") or author.get("username") or "Unknown",
                    "text": strip_html(node.get("text") or node.get("body") or ""),
                    "datePosted": node.get("datePosted"),
                    "parentId": node.get("parentId"),
                    "url": CF_PAGE,
                }
            )
        replies = node.get("replies")
        if replies:
            flatten_cf_comments(replies, out)


def fetch_curseforge_comments() -> list[dict]:
    url = f"https://www.curseforge.com/api/v1/mods/{CF_MOD_ID}/comments?index=0&pageSize=50"
    payload = http_get_json(url)
    if not payload or not isinstance(payload, dict):
        return []
    data = payload.get("data") or []
    items: list[dict] = []
    flatten_cf_comments(data, items)
    return items


def parse_wago_comments_payload(payload) -> list[dict]:
    items: list[dict] = []
    if isinstance(payload, list):
        rows = payload
    elif isinstance(payload, dict):
        rows = payload.get("data") or payload.get("comments") or payload.get("feedbacks") or []
    else:
        return items
    for row in rows:
        if not isinstance(row, dict):
            continue
        cid = row.get("id") or row.get("_id")
        if cid is None:
            continue
        author = row.get("author") or row.get("user") or {}
        if isinstance(author, dict):
            name = author.get("name") or author.get("username") or author.get("displayName") or "Unknown"
        else:
            name = str(author)
        text = row.get("text") or row.get("body") or row.get("message") or row.get("content") or ""
        if isinstance(text, dict):
            text = text.get("text") or text.get("body") or ""
        items.append(
            {
                "source": "wago",
                "id": str(cid),
                "author": name,
                "text": strip_html(str(text)),
                "datePosted": row.get("created_at") or row.get("datePosted") or row.get("created"),
                "parentId": row.get("parent_id") or row.get("parentId"),
                "url": WAGO_PAGE,
            }
        )
    return items


def fetch_wago_comments() -> list[dict]:
    if not WAGO_API_TOKEN:
        print("WAGO_API_TOKEN not set — skipping Wago comment poll.")
        return []
    headers = {"Authorization": f"Bearer {WAGO_API_TOKEN}"}
    endpoints = [
        f"https://addons.wago.io/api/projects/{WAGO_PROJECT_ID}/comments",
        f"https://addons.wago.io/api/projects/{WAGO_PROJECT_ID}/feedbacks",
        f"https://addons.wago.io/api/v1/projects/{WAGO_PROJECT_ID}/comments",
    ]
    for url in endpoints:
        payload = http_get_json(url, headers=headers)
        if payload is None:
            continue
        items = parse_wago_comments_payload(payload)
        if items:
            print(f"Wago comments from {url}: {len(items)}")
            return items
    print("Wago comment API: no supported endpoint returned data (may need Wago to expose API).")
    return []


def load_state(path: Path) -> dict:
    if path.is_file():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError) as e:
            print(f"State read warning: {e}", file=sys.stderr)
    return {"cf": [], "wago": [], "bootstrapped": False}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, sort_keys=True), encoding="utf-8")


def state_key(item: dict) -> str:
    return f"{item['source']}:{item['id']}"


def main() -> int:
    state_path = Path(os.environ.get("HOST_COMMENTS_STATE_FILE", str(DEFAULT_STATE)))
    state = load_state(state_path)

    cf_items = fetch_curseforge_comments()
    wago_items = fetch_wago_comments()
    all_items = cf_items + wago_items
    print(f"Fetched {len(cf_items)} CurseForge + {len(wago_items)} Wago comment rows.")

    seen_cf = set(str(x) for x in state.get("cf", []))
    seen_wago = set(str(x) for x in state.get("wago", []))

    for item in all_items:
        if item["source"] == "curseforge":
            seen_cf.add(item["id"])
        else:
            seen_wago.add(item["id"])

    if not state.get("bootstrapped"):
        state["cf"] = sorted(seen_cf, key=lambda x: int(x) if x.isdigit() else x)
        state["wago"] = sorted(seen_wago)
        state["bootstrapped"] = True
        save_state(state_path, state)
        print(
            f"Bootstrap complete — recorded {len(seen_cf)} CF + {len(seen_wago)} Wago IDs; "
            "no Discord posts on first run."
        )
        return 0

    prev_cf = set(str(x) for x in state.get("cf", []))
    prev_wago = set(str(x) for x in state.get("wago", []))
    new_items: list[dict] = []
    for item in all_items:
        bucket = prev_cf if item["source"] == "curseforge" else prev_wago
        if item["id"] not in bucket:
            new_items.append(item)

    if not new_items:
        print("No new comments.")
        state["cf"] = sorted(seen_cf, key=lambda x: int(x) if x.isdigit() else x)
        state["wago"] = sorted(seen_wago)
        save_state(state_path, state)
        return 0

    new_items.sort(key=lambda x: (x.get("datePosted") or 0, x["id"]))
    posted = 0
    for item in new_items:
        if post_or_skip(
            "DISCORD_COMMENTS_CHANNEL_ID",
            title=f"New {'CurseForge' if item['source'] == 'curseforge' else 'Wago'} "
            + ("reply" if item.get("parentId") else "comment"),
            description=f"**{item.get('author', 'Unknown')}**\n\n{truncate(item.get('text') or '(empty)', 3500)}",
            color=0xF16436 if item["source"] == "curseforge" else 0x9B59B6,
            footer=f"{'CurseForge' if item['source'] == 'curseforge' else 'Wago'} #{item['id']}",
            url=item.get("url"),
        ):
            posted += 1

    state["cf"] = sorted(seen_cf, key=lambda x: int(x) if x.isdigit() else x)
    state["wago"] = sorted(seen_wago)
    save_state(state_path, state)
    print(f"Notified Discord for {posted} new comment(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
