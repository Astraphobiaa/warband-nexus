## v3.1.10 (2026-06-16)

### Fixed

- Notifications: achievement toasts no longer vanish when Replace Achievement Popup is on (ACHIEVEMENT_EARNED no longer pre-marks before AddAlert).
- Notifications: achievement subtitle no longer shows a stray "A:" from a broken UTF-8 separator; uses ASCII " - " between completion text and points.
- Currency chat: scenario/challenge scoring and profession capacity rows (Challenge -, Sites, Total, public order capacity) are filtered; no spurious [WN-Currency] lines.
- Currency cache: fixed nil call in ShouldIgnoreCurrencyEvent (Lua 5.1 forward-reference for visibleCurrencyIDs helpers).
- Tooltips: bag item WN Search lines stay inside the tooltip frame (sync inject before Show; widget tooltips still defer).
- Midnight taint: secret/nil guards across services, data catalogs, and UI (issecretvalue before string ops on API returns).
- Notifications: achievement toast fallback when Replace mode is on but Blizzard AddAlert never fires after ACHIEVEMENT_EARNED.
- Notifications: permanent dedup and achievement session ack only after toast is queued (not at emit time).
- Notifications: central CanShowToast gate for plan/vault/quest/reminder; showAchievementNotifications wired for replace-mode achievements.

### Updated

- Performance: flight paths and taxi rides no longer cause large FPS drops from addon quest-log work (updates are batched).
- Reminders: zone reminder checks pause while you are flying or on a flight path, then catch up when you land or regain control.
- Character zone tracking skips redundant saves when your zone and subzone did not change.
- Daily quests: background weekly-reset polling runs every 5 minutes instead of every minute.
