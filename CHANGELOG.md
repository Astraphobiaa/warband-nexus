## v3.3.3 (2026-07-15)

### Added

- Turkish language support, with a language selector in Settings so you can pick any interface language regardless of your game client.

### Updated

- Settings reorganized: Language now sits at the top of General, and every minimap option moved into the renamed "Shortcuts" panel alongside Easy Access.
- General settings are now grouped into Interface, Controls & Scaling, Item tooltips, and Startup.

### Fixed

- Gear upgrade ranks no longer show two steps too low; a Champion 1/6 item read as Veteran 5/6 because both share item level 246.
- Crafted gear now reads "Crafted 285" instead of an invented "Myth 5/5" rank; crafted items have no upgrade track, and the 5/5 scale clashed with real 6/6 tracks.
- Gear lifted past its track cap with a Nebulous Voidcore now reads "Myth+" instead of showing no rank at all; "Myth 6/6" would have hidden it, since that rank means item level 289 while the item is 298.
- Upgrade ranks now read from the tooltip on every locale, so non-English clients no longer fall back to guessing from item level.
- Editing an attempt count by hand now sticks; a mount's try count could previously snap back to the old value.
- The welcome message now reads correctly in Korean.
