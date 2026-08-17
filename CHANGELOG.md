## v3.5.4-beta1 (2026-08-17)

Beta build. These are try counter fixes that have been verified against automated tests but not yet
across a broad range of live play, so please report anything that looks miscounted.

### Fixed

- Try counts no longer skip kills while you farm the same rare over and over. Killing a rare again within about ten seconds of the last one could silently drop the attempt, losing roughly half the kills in a back-to-back farm.
- Fishing attempts now count on Isle of Quel'Danas and in Arcantina. Both zones were producing no try counts and no chat lines at all.
- Fishing is now recognised much more reliably. The addon learns your bobber the first time it sees a confirmed catch and remembers it from then on, instead of relying on a short built-in list that no longer matched current fishing.
- Fishing casts made with newer or unusual fishing abilities are now recognised, so their attempts are counted instead of being ignored for the rest of the session.
- Attempt messages can no longer go missing from chat when several loot windows follow each other quickly.
