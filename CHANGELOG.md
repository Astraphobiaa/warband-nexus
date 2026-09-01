## v3.5.6 (2026-08-31)

Season 2 item levels corrected against the game's own data, a try counter fix reported from the field, and three Delves corrections.

### Fixed

- Season 2 item levels are right now. Every upgrade track was six item levels too low, so a Season 2 piece could be shown on the wrong rank with the wrong next upgrade step, and crafted gear caps were off with them. The new numbers are read from the game's own crest descriptions rather than from patch previews.
- Crest tooltips now list where each crest actually comes from, again from the game's own descriptions. The Mythic Keystone ranges were wrong for Hero and Myth crests, and the Season 2 spark currency was missing from the highlighted currencies entirely.
- The try counter no longer keeps counting attempts for a drop you already have when the collectible it turns into has not appeared yet. The Nether-Warped Egg is the case that exposed it: the drake takes seven days to hatch, so every later cast kept adding an attempt. The addon now recognises the item in your bags, bank, reagent bank or warband bank and stops counting - including when you looted it on another character or before installing the addon. Thanks to @claytonkimber for the detailed report.
- Delves now show the right number of weekly Gilded Stashes. A character could show a maximum of 3 instead of 4 whenever the Delves panel had not been opened that session.
- Reputation gains from your Delve companion are announced again on non-English game clients. The addon recognised the companion by its English name only, which silently switched the companion experience notifications off everywhere else.
- The Delve companion's level and name are recorded again. The companion is a friendship rather than a renown faction in Midnight, so the addon was asking for renown data that never existed for it.
