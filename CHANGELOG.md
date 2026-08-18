## v3.5.4-beta3 (2026-08-18)

Beta build. Try counter chat and counting fixes throughout; please report anything that still looks miscounted or stays silent.

### Fixed

- Attempt messages could go missing from chat completely even though the try was counted. Mount drops whose journal entry had not finished loading were affected most.
- The attempt message after fishing arrived seconds late, sometimes only turning up on your next catch. It now follows the loot right away.
- Daily and weekly lockout rares, including every Undermine rare, printed "Skipped: daily/weekly lockout" instead of your attempt count on the kill that actually counted.
- Containers kept in your reagent bag were never counted at all.
- The "after N attempts" total shown when you finally obtain a drop could be wrong.
- Two try counter notices ignored your Try Counter chat tab setting and showed up in a different tab from every other try counter line. They now follow the hide-chat option as well.
- Try counter lines could be lost without a trace when another chat addon's message handler failed.
