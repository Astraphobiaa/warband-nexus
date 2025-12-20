# Changelog

All notable changes to Warband Nexus will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2024-12-16

### Fixed
- **Critical**: Fixed folder structure in release ZIP that prevented the addon from loading when manually installed
  - Release ZIP now contains addon files directly at root level (correct: `WarbandNexus.toc`, not `WarbandNexus-1.0.0/WarbandNexus.toc`)
  - Manual installation from GitHub Releases now works correctly
  - Users who installed v1.0.0 manually should delete the old folder and reinstall v1.0.1

### Added
- **Addon Compatibility**: Automatic detection and compatibility with third-party bank/inventory addons
  - Bank frame suppression is automatically disabled when conflicting addons are detected
  - "Replace Default Bank" setting adjusts automatically to prevent conflicts
  - Seamless coexistence with popular inventory management solutions
- **Enhanced Debug Logging**: Comprehensive debug logging for loot notification system
  - Added detailed event firing logs for `BAG_UPDATE_DELAYED`
  - Item detection logs show classID, subclassID, and collection status
  - Mount/Pet/Toy detection logs for troubleshooting
  - Enable via `/wn config` → General → Debug Mode

### Notes
- CurseForge/WoWUp/Wago users are not affected by the v1.0.0 installation issue (packager handles folder structure correctly)
- If you manually installed v1.0.0 and the addon wasn't loading, delete `Interface\AddOns\WarbandNexus-1.0.0` and install v1.0.1

## [1.0.0] - 2024-12-16

### 🎉 Initial Release

The first production-ready release of Warband Nexus!

### ✨ Added

#### **Core Features**
- **Warband Bank Management** - Full integration with account-wide Warband bank (5 tabs)
- **Personal Bank Tracking** - Track personal bank items across all characters
- **Cross-Character Gold Tracking** - View total gold across all characters and Warband
- **3,800+ Item Cache** - Comprehensive item tracking across characters and banks
- **Character Overview** - Sortable character list with class colors and statistics
- **PvE Progress Tracking** - Mythic+ history, raid lockouts, and Great Vault progress
- **Collection Statistics** - Track mounts, pets, toys, and achievement points

#### **UI/UX**
- **Modern Interface** - Clean, beautiful design with smooth animations
- **Tab Navigation** - 5 dedicated tabs (Characters, Items, Storage, PvE, Statistics)
- **Minimap Button** - Quick access via LibDBIcon with detailed tooltip
- **Live Search** - Real-time item search with 0.4s debounce
- **Sortable Headers** - Click column headers to sort (Characters tab)
- **Enhanced Tooltips** - Hover over items to see all locations
- **Shift+Click Search** - Shift+Click any item to search for it
- **Resizable Window** - Drag to resize (500x400 minimum)
- **Footer Statistics** - Real-time item count and last scan time
- **Right-Click Menu** - Quick actions via minimap button right-click

#### **Performance**
- **Smart Caching System** - TTL-based cache (30s) for frequently accessed data
- **Event Throttling** - Debounced `BAG_UPDATE` (0.5s) and search input (0.4s)
- **Frame Pooling** - Reused UI frames for better performance
- **Lazy Loading** - Modules initialize on-demand with staggered timers
- **Priority Queue** - Critical events (bank open) processed first
- **Database Optimizer** - Automatic cleanup of stale data (90+ days)

#### **Reliability**
- **API Wrapper Layer** (650 lines) - 37 wrapped API functions for future-proofing
- **Error Handler** (430 lines) - Comprehensive error logging with stack traces
- **Safe Execution** - All critical functions wrapped in `pcall`
- **Emergency Recovery** - `/wn recover` command for critical failures
- **Fallback Support** - Automatic legacy API usage when modern APIs unavailable
- **Data Validation** - Character and item data validation on load

#### **Modules**
- `APIWrapper.lua` - WoW API abstraction layer (37 functions)
- `ErrorHandler.lua` - Error logging and recovery system
- `DataService.lua` - Data collection, validation, and export
- `CacheManager.lua` - Smart caching with TTL and invalidation
- `EventManager.lua` - Throttled/debounced event handling
- `DatabaseOptimizer.lua` - SavedVariables cleanup and size reporting
- `MinimapButton.lua` - LibDBIcon integration
- `TooltipEnhancer.lua` - Item location tooltips
- `Scanner.lua` - Bank and inventory scanning
- `Banker.lua` - Gold transfer and bank operations
- `PvE.lua` - Mythic+, raid, and vault tracking
- `UI.lua` - Main window and tab system (1,100+ lines)
- `SharedWidgets.lua` - Reusable UI components
- `CharactersUI.lua` - Character list tab
- `ItemsUI.lua` - Item search tab
- `StorageUI.lua` - Storage breakdown tab
- `PvEUI.lua` - PvE progress tab
- `StatisticsUI.lua` - Statistics and charts tab

#### **Configuration**
- **General Settings** - Debug mode, auto-open at bank
- **Minimap Button** - Toggle icon visibility
- **Tooltip Enhancements** - Toggle enhanced tooltips and hints
- **Automation** - Auto database optimization (weekly)
- **Profiles** - AceDB profile support (per-character, realm, account)

#### **Slash Commands**
- `/wn` - Toggle main window
- `/wn show` / `/wn hide` - Show/hide window
- `/wn config` - Open configuration
- `/wn scan` - Manual bank scan
- `/wn cache` - Show cache statistics
- `/wn clearcache` - Clear all caches
- `/wn dbstats` - Database size and statistics
- `/wn optimize` - Run database optimization
- `/wn apireport` - WoW API compatibility report
- `/wn errors` - Show error statistics
- `/wn recover` - Emergency recovery

#### **Localization**
- Full English (enUS) translation
- Localization framework ready for community translations
- Support files for: deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW

### 🛠️ Technical Details

#### **Architecture**
- **Modular Design** - 17 separate modules for maintainability
- **Namespace Isolation** - Uses `ns` table for cross-module communication
- **AceAddon-3.0** - Built on industry-standard Ace3 framework
- **SavedVariables** - Persistent data storage via `WarbandNexusDB`
- **Event-Driven** - Efficient event handling with AceEvent-3.0

#### **Code Quality**
- **~5,000 lines of code** across all modules
- **Comprehensive documentation** - LuaLS annotations for all functions
- **Error handling** - Every critical path protected with `pcall`
- **Performance optimized** - Throttling, caching, frame pooling
- **Best practices** - Follows WoW addon development standards
- **Future-proof** - API wrapper layer protects against Blizzard changes

#### **Compatibility**
- **WoW Version:** 11.0.2+ (The War Within)
- **Dependencies:** Ace3 (embedded), LibDataBroker-1.1, LibDBIcon-1.0
- **Tested On:** Retail (11.0.2)
- **API Coverage:** 37 wrapped functions with legacy fallbacks

### 🐛 Known Issues

- None at release! 🎉

### 📝 Notes

This is the first public release of Warband Nexus. The addon has been extensively tested and is production-ready. All core features are fully functional.

Special thanks to the WoW addon development community for the excellent libraries and tools that made this project possible!

---

## [Unreleased]

### 🔮 Planned Features (v1.1.0)

- **Performance Profiler** - CPU/memory usage tracking (`/wn profile`)
- **Backup & Restore** - Export/import SavedVariables (`/wn backup`)
- **Advanced Search** - Regex support, multi-filter, search history
- **Data Export** - Export to CSV/JSON format

### 🔮 Future Features (v1.2.0+)

- **Shopping List** - Track items you need across characters
- **Auction House Integration** - Item price tracking
- **Guild Bank Support** - Track guild bank contents
- **Mail Tracking** - Track incoming/outgoing mail
- **Profession Integration** - Track reagents and recipes

---

## Version History

- **1.0.0** - Initial release (2024-12-16)

---

**Legend:**
- `Added` - New features
- `Changed` - Changes in existing functionality
- `Deprecated` - Soon-to-be removed features
- `Removed` - Removed features
- `Fixed` - Bug fixes
- `Security` - Security patches
