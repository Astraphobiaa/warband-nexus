## v3.5.12 (2026-09-25)

Display scaling improvements for MacBook and laptop screens, UI scale slider stabilization, and external window viewport clamping.

### Added

- Added an Auto-Fit Scale option in Settings to automatically adapt UI scale to MacBook and laptop resolutions.
- Added a Reset to 100% quick action for UI Scale in Settings.

### Fixed

- Resolved violent flickering, thumb jumping, and constant UI refreshes when adjusting the UI Scale slider.
- Corrected screen category classification on high-DPI Retina laptop screens (such as 14" and 16" MacBooks).
- Reduced default window footprint and minimum resize dimensions on smaller and laptop displays.
- Clamped external popup windows so they never exceed available viewport height.
