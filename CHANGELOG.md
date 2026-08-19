## v3.5.5 (2026-08-19)

Everything from the 3.5.4 beta builds, consolidated: a large try counter data expansion and a full pass over try counter chat and counting, plus the Season 2 groundwork for the Coiled Isle.

### Added

- The Coiled Isle is now a zone the addon knows about. Its world quests and dailies feed Weekly Progress, and reminders can be set for the isle - the Vaults of Atal'Utek, The Underbelly and the Tomb of the Lost Priest below it all count as being on the isle.
- The Coiled Isle rare mounts (Topaz Skyfang, Ruby Writhe) now count tries across all twelve daily rares and the five Cursed Surge bosses, including inside the Vaults of Atal'Utek.
- New Season 2 collectibles are tracked: the Soulcoil Remnant pet from Nek'zali in The Venomous Abyss, Lil' Mon from Big Mon, and the Vibrant Venomfang from the Wriggling Venom-Soaked Satchel.
- The Mythic raid mounts Ascendant Skyrazor, Keys to the Big G and Unbound Star-Eater are now tracked with kill statistics.
- Hundreds of drop-based mounts, pets and toys from Classic through The War Within have been added to try counting.

### Fixed

- Mythic+ ratings from the previous season no longer linger once a new season opens. Scores and best runs are cleared for every character as soon as the game reports the new season, instead of showing last season's numbers until you ran that dungeon again.
- Season 2 gear now reports the right upgrade ranks. The item level table for the new tracks was ten levels low, so a Season 2 piece could be shown on the wrong track with the wrong next upgrade step, and crafted gear caps were off by the same amount.
- Attempt messages could go missing from chat completely even though the try was counted. Mount drops whose journal entry had not finished loading were affected most, as were several loot windows following each other quickly.
- The attempt message after fishing arrived seconds late, sometimes only turning up on your next catch. It now follows the loot right away.
- The counter could look stuck, registering attempts without the number moving, for fishing, container and object drops.
- Daily and weekly lockout rares, including every Undermine rare, printed "Skipped: daily/weekly lockout" instead of your attempt count on the kill that actually counted, and containers kept in your reagent bag were never counted at all.
- Try counts no longer skip kills while you farm the same rare back-to-back. Killing a rare again within about ten seconds of the last one could silently drop the attempt, losing roughly half the kills in a back-to-back farm.
- Fishing attempts now count on Isle of Quel'Danas and in Arcantina, the addon learns your bobber the first time it sees a confirmed catch, and casts made with newer or unusual fishing abilities are recognised.
- The "after N attempts" total shown when you finally obtain a drop could be wrong.
- Two try counter notices ignored your Try Counter chat tab setting and showed up in a different tab from every other try counter line; they now follow the hide-chat option as well. Try counter lines could also be lost without a trace when another chat addon's message handler failed.
