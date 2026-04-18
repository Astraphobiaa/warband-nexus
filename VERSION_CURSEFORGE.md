# CurseForge / Wago — **Warband Nexus v2.6.1** (2026-04-18)

## Summary for project description / changelog field

**v2.6.1** — Try Counter: fishing try counts no longer stall when target/mouseover remains on a nearby mob corpse; routing trusts `IsFishingLoot()` / the LOOT_READY snapshot. Includes 2.6.0 content: Gear UI enchant/gem warnings, mail icon on characters, `/wn keys` grouping, fishing bobber/spell fixes, Midnight instanced-combat guards.

## Full notes

### Bug fixes (2.6.1)

- **Try Counter (`TryCounterService`)**: Fixed misclassification of fishing loot as NPC loot when unit frames still pointed at a corpse; increments resume reliably.

### 2.6.0 highlights

- **Gear UI**: Enchant/gem warnings vs upgrade arrows; offline characters; translations.
- **Characters**: Pending mail icon.
- **Commands**: `/wn keys` line grouping and throttle safety.
- **Try Counter**: Toy bobbers, unknown fishing spells, Midnight combat.

---

Package: `WarbandNexus-2.6.1.zip` from `python build_addon.py` or `py build_addon.py` at repo root. **`/reload`** after installing.
