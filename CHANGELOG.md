## v3.3.8 (2026-07-29)

### Updated

- Marking a character as a favorite no longer pulls it out of your custom section. The star now highlights the character where it already sits and sorts it to the top of that section, so the Favorites block only holds favorites that are not in a section of their own.
- The roster picker for a custom section now lists favorited characters as well, so a favorite can be added to or removed from a section like any other character.

### Fixed

- Fixed the favorites star refusing to release a character. Characters starred before the account moved to its current storage format were saved under an older name, so the star kept adding and removing a second entry while the original one stayed behind and pinned the character to Favorites forever. Existing lists are cleaned up automatically on login.
- Fixed a character being listed as a member of a custom section in the add window while still showing under Favorites on the Characters tab, and appearing as tracked but neither favorite nor section member on the PvE, PvP and Professions tabs.
- Fixed a Lua error when clicking the gold star on a custom section header, or confirming Add selected in the roster picker.
- Fixed key combinations being unreadable in Settings when the bound key is a dash. Combinations are now shown with a spaced separator, so Ctrl plus dash reads as CTRL - -.
- Fixed long key combinations spilling out of the keybinding button and disappearing behind the clear button. The full combination is now also shown in the button tooltip.
