## v3.5.16 (2026-10-08)

Reagent deposit accuracy, profession tracking on alts, and container try counter improvements.

### Updated

- Improved container try counting when a container is consumed instantly or opened from a stack.

### Fixed

- Fixed the Reagent Deposit Manager moving weapon oils, whetstones and other usable items to the bank. Food, flasks, phials and potions always stay in your bags.
- Fixed bind-on-equip two-handed swords and warglaives being deposited as Warbound Gear, while real Warbound-until-equipped gear was skipped.
- Fixed keystones being picked up by reagent deposits.
- Fixed profession skill levels not updating for characters that are not logged in, including skill-ups gained with the profession window closed or right before logging out.
- Fixed Midnight profession skill not being tracked on characters that never opened their profession window.
- Fixed saved profession data being wiped when the game reported professions late during login.
