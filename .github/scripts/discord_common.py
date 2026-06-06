#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Shared Discord bot REST helpers for Warband Nexus GitHub Actions."""
from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

DISCORD_API = "https://discord.com/api/v10"
EMBED_DESC_LIMIT = 4096
EMBED_TITLE_LIMIT = 256


def bot_token() -> str:
    return os.environ.get("DISCORD_BOT_TOKEN", "").strip()


def channel_id(env_name: str) -> str:
    return os.environ.get(env_name, "").strip()


def require_bot_channel(channel_env: str) -> tuple[str, str] | None:
    token = bot_token()
    cid = channel_id(channel_env)
    if not token or not cid:
        return None
    return token, cid


def truncate(text: str, limit: int, suffix: str = "...") -> str:
    if len(text) <= limit:
        return text
    return text[: limit - len(suffix)] + suffix


def post_message(token: str, channel_id_value: str, payload: dict) -> None:
    url = f"{DISCORD_API}/channels/{channel_id_value}/messages"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Authorization": f"Bot {token}",
            "Content-Type": "application/json",
            "User-Agent": "warband-nexus-discord/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        print(f"Discord OK channel={channel_id_value} HTTP {resp.status}")


def send_embed(
    token: str,
    channel_id_value: str,
    *,
    title: str,
    description: str,
    color: int = 0x58A6FF,
    footer: str | None = None,
    url: str | None = None,
    fields: list[dict] | None = None,
) -> None:
    embed: dict = {
        "title": truncate(title, EMBED_TITLE_LIMIT),
        "description": truncate(description, EMBED_DESC_LIMIT),
        "color": color,
    }
    if footer:
        embed["footer"] = {"text": truncate(footer, 2048)}
    if url:
        embed["url"] = url
    if fields:
        embed["fields"] = fields[:25]
    post_message(token, channel_id_value, {"embeds": [embed]})


def post_or_skip(channel_env: str, **embed_kwargs) -> bool:
    cfg = require_bot_channel(channel_env)
    if not cfg:
        print(f"Skip Discord ({channel_env}): bot token or channel id not configured.")
        return False
    token, cid = cfg
    send_embed(token, cid, **embed_kwargs)
    return True
