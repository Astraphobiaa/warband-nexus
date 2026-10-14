## v3.6.0 (2026-10-14)

Full support for patch 12.1.5, a sharper and more consistent interface, a reworked Bank tab and a broad performance pass.

### Added

- Added animated entrance effects to notifications (glow, icon flash and shine) that scale with how important the alert is.
- Added a close button to the Try Count window.

### Updated

- Updated the addon for patch 12.1.5.
- Borders, dividers and lines now stay crisp and the same thickness at any UI scale, and no longer flicker while you resize or scroll a window.
- Every border in the addon now has the same weight: cards, buttons, dropdowns, search bars, input fields and sliders.
- Headers, tabs, search bars and content now use the same spacing and alignment on every tab, so pages no longer shift when you switch between them.
- Tables across the addon share one look: matching row heights, column spacing, sort arrows and status icons.
- Turning a module off now fully stops its background work, unless another enabled module needs that data.
- Bank tab reorganized: Bags and Bank show your current character, Warband shows your other characters' items (Personal) and your Warband Bank (Warband), and Guild Bank lists each character's guild with its stored items.
- All pop-up windows now share the same title bar, close button, Escape-to-close, dragging and UI scale, including Money Logs, Gold Target, Reagent Deposit, Mail Details, Reminders, plan windows and character dialogs.
- The Custom Plan and Weekly Vault windows have a cleaner, more compact layout with evenly spaced fields.
- Windows that hold a table now size it to fit, so no column is cut off (Money Logs, Reagent Deposit).
- Removed the "Recent Obtains" title and tightened the spacing on the Collections Recent view.
- Removed the icon from the Filter button.
- Faster tab switching and scrolling, with less memory churn in Storage, tooltips, lists and the Weekly Vault button.

### Fixed

- Fixed errors caused by item and coin functions that patch 12.1.5 removed (including Collections scanning errors).
- Fixed the "Weekly Vault Ready" reminder not appearing at login.
- Fixed currencies, guild, specialization and item level sometimes showing blank after a temporary data hiccup; the last known value is now kept.
- Fixed Mythic+ weekly best not showing correctly.
- Fixed Bank rows overlapping after switching tabs, and the Personal section expanding or collapsing everything at once.
- Fixed the Guild Bank losing items from tabs you had not opened during that visit, and characters' guilds not being listed.
- Fixed the To-Do empty-state card being wider than the header and search bar.
- Fixed the Money Logs table not filling the window and the Amount column being cut off.
- Fixed the Gold Target input field having no border.
- Fixed the Gear tab character selector looking thinner than the buttons next to it.
- Fixed an invisible layer that blocked your next click after confirming character tracking.
- Fixed the Mail Details window leaving an invisible layer behind when reopened.
- Fixed search box hint text not hiding when you click into the box.
