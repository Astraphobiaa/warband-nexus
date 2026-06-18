## v3.1.11 (2026-06-18)

### Fixed

- Great Vault: unclaimed chest status no longer clears on login before Blizzard sends weekly rewards data.
- Great Vault: Easy Access badge and vault tracker refresh immediately after you claim a reward or close the vault UI.
- Great Vault: vault-ready toast only when rewards become newly claimable, not after you already claimed the chest.
- Achievements: Plans and Collections lists now include achievements in deep subcategories (e.g. Glory and meta chains); scan retries until the journal API is ready.
- Notifications: stacked toasts keep correct spacing and order when several alerts fire in quick succession.
- Notifications: criteria progress toasts are deduplicated when Blizzard fires both achievement and criteria alert paths.
- Notifications: toast cards use corrected size and stack position so mixed alert types no longer overlap or jump.
- Professions: fixed errors when profession spell names return nil or secret values from the API.
- Midnight taint: additional secret-value guards across tooltips, collections, reminders, and vault UI.
