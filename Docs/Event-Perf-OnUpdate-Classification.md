# OnUpdate / Polling Classification (Plan Phase 4)

Classification of `SetScript("OnUpdate", ...)` usages: keep vs consider moving to event/timer.

## Keep (interaction or short-lived animation)

| Location | Purpose | Reason |
|----------|---------|--------|
| **CollectionsUI.lua** (model) | 3D model rotation while left-drag held | Per-frame input; no WoW event for "mouse moved while button down". |
| **MinimapButton.lua** | Shift key state change to show/hide tooltip | Input polling; could use KEY_MODIFIER_CHANGED if available in 12.0. |
| **WindowFactory.lua** | Popup mouse capture (down/up outside to close) | Input-driven; no event for "mouse up outside frame". |
| **InitializationService.lua** | Wait for non–combat then register events | Documented: OnUpdate works in lockdown; C_Timer does not. |
| **NotificationManager.lua** | Fade-in / fade-out / slide animations | Short-lived; clears OnUpdate when progress >= 1. Acceptable. |
| **PvEUI.lua** / **SharedWidgets.lua** | Loading spinner rotation | Visual only; cleared when loading done. Acceptable. |
| **Profiler.lua** | Frame spike detection | Diagnostic; low priority to change. |

## Consider event/timer replacement

| Location | Current behavior | Suggested change |
|----------|------------------|------------------|
| **EventManager.lua** | Queue processor: OnUpdate while frame shown, process up to N events per frame, hide when queue empty | Use `C_Timer.NewTicker(0, processor)` when `#eventQueue > 0`, cancel when empty; or keep current pattern (frame is hidden when idle so no per-frame cost when empty). |
| **SharedWidgets.lua** (container) | 60s refresh: `timeSinceUpdate += elapsed`, refresh at 60s | Replace with `C_Timer.NewTicker(60, refreshFn)` and store ticker on container; cancel on release. |
| **PlanCardFactory.lua** | Layout update after 2 frames (updateCount >= 2) | Replace with `C_Timer.After(0.05, layoutFn)` for a one-shot deferred layout. |

## Summary

- **No change required** for drag, input, combat-wait, or short-lived animation OnUpdates.
- **Optional** refactors: EventManager queue (ticker when non-empty), SharedWidgets 60s refresh (NewTicker), PlanCardFactory 2-frame defer (C_Timer.After).
