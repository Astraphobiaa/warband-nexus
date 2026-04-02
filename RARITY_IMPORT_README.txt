Warband Nexus — Rarity mount try-count import (for Rarity maintainers / QA)
================================================================================
Addon version this document refers to: 2.5.5

WHAT WE DO (Mounts category only)
---------------------------------
We read Rarity’s in-memory table once (per account, lifetime):

  Rarity.db.profile.groups.mounts

For each enabled entry with attempts > 0:
  • itemId (or itemID) — WoW mount item ID
  • attempts — Rarity’s counter for that mount

We resolve itemId → mount journal ID with C_MountJournal.GetMountFromItem(itemId),
same as our try counter. We compute:

  newTotal = WN_base + Rarity_attempts

where WN_base is max( GetTryCount("mount", mountKey), GetTryCount("mount", itemId) )
when mountKey and itemId differ (avoids double-counting duplicate keys); otherwise
one GetTryCount. We then SetTryCount on mountKey and mirror to itemId if needed.

ONE-TIME ONLY
-------------
SavedVariables: tryCounts.rarityMountsOneTimeSeedComplete

After the first successful import where at least one Rarity mount row had
attempts > 0, we set this flag and never read Rarity for try counts again.
Later kills are tracked only by Warband Nexus (so running both addons does not
re-add Rarity’s numbers every /reload).

If Rarity is installed but every mount has 0 attempts, we do NOT set the flag yet
(so a later session can still seed when the user has data).

Debug (requires /wn debug):
  /wn raritymountpreview   — mapping + whether seed is done
  /wn rarityseedreset      — clear the flag to test import again

WHEN IT RUNS
------------
Automatically ~2s and ~12s after try counter init (load-order safety). Silent if
Rarity absent or seed already complete.

We do not ship Rarity code; runtime interop only.

Contact: Warband Nexus (CurseForge / GitHub).
