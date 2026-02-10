# Warband Nexus

> Modern Warband bank management and cross-character inventory tracking for World of Warcraft

[![WoW Version](https://img.shields.io/badge/WoW-11.0.2-blue.svg)](https://worldofwarcraft.com)
[![License](https://img.shields.io/badge/license-All%20Rights%20Reserved-red.svg)](LICENSE)

## 📖 Overview

**Warband Nexus** is a comprehensive World of Warcraft addon designed for The War Within (11.0+) that provides powerful Warband bank management and cross-character inventory tracking. Track all your characters' gold, items, collections, and PvE progress in one elegant interface.

## ✨ Features

### 🏦 **Bank Management**
- **Warband Bank Integration** - Full support for account-wide Warband bank (5 tabs)
- **Personal Bank Tracking** - Track personal bank items across all characters
- **Smart Synchronization** - Automatically syncs when you open the bank
- **Real-time Updates** - UI updates instantly when items move

### 💰 **Gold Tracking**
- **Cross-Character Gold** - View total gold across all characters
- **Warband Gold** - Track Warband bank gold separately
- **Quick Transfer** - Transfer gold to Warband bank with one click
- **Gold Statistics** - See richest character, total wealth, and more

### 📦 **Inventory Management**
- **3,800+ Item Cache** - Tracks all items across characters and banks
- **Live Search** - Type to search items as you type (0.4s debounce)
- **Quality Filtering** - Filter by item rarity (Common, Rare, Epic, etc.)
- **Location Tracking** - See which character/bank has specific items
- **Enhanced Tooltips** - Hover over items to see all locations (with Shift+Click to search)

### 📊 **Character Overview**
- **Smart Sorting** - 3-state sorting (ascending → descending → default)
  - Current character always appears at the top
  - Click column headers to cycle through sort states
  - Sorting preferences saved across sessions
- **Favorite Characters** ⭐ - Star your favorite characters (visual indicator)
- **Class Colors** - Characters displayed in class colors
- **Realm Support** - Works across multiple realms
- **Last Seen Tracking** - Know when each character was last played

### 🎮 **PvE Progress Tracking**
- **Mythic+ History** - Track completed keystones across characters
- **Raid Lockouts** - See all saved raid instances
- **Great Vault Progress** - Monitor weekly vault rewards
- **Unified View** - All characters' progress in one place

### 📈 **Collection Statistics**
- **Mounts** - Total mount collection count
- **Pets** - Battle pet collection tracking
- **Toys** - Toy collection progress
- **Achievements** - Total achievement points
- **Warband-wide Stats** - See account-wide collection progress

### 🎨 **Modern UI**
- **Clean Interface** - Beautiful, modern design with smooth animations
- **Tab Navigation** - Characters, Items, Storage, PvE, Statistics
- **Minimap Button** - Quick access via LibDBIcon
- **Resizable Window** - Drag to resize (500x400 minimum)
- **Footer Statistics** - Real-time item count and scan status

### ⚡ **Performance & Optimization**
- **Smart Caching** - TTL-based cache for frequently accessed data
- **Event Throttling** - Debounced events prevent UI spam
- **Frame Pooling** - Reuses UI elements for better performance
- **Error Handling** - Comprehensive error logging with stack traces
- **Database Optimizer** - Automatic cleanup of stale data

### 🛡️ **Reliability**
- **API Wrapper Layer** - Protected against WoW API changes across patches
- **Fallback Support** - Automatically uses legacy APIs when modern ones unavailable
- **Emergency Recovery** - `/wn recover` command for critical failures
- **Safe Execution** - All critical functions wrapped in `pcall`

### 🔔 **Notifications**
- **Unified Toast System** - All notifications use consistent, beautiful 450x130 toast design
  - **100% Opaque** - Fully opaque background (no transparency)
  - **Smart Stacking** - Max 3 toasts visible, auto-queue excess
  - **Dynamic Positioning** - Toasts stack vertically, slide up when closed
  - **Queue Management** - 4th+ toasts wait in queue, appear when slot opens
- **Update Notifications** - Full-screen changelog pop-up when addon updates
- **Weekly Vault Reminder** - Toast notification when you have unclaimed vault rewards
- **Loot Alerts** 🎉 - Instant notification when a mount/pet/toy **enters your bag**
  - **Rarity-Style Bag Detection** - Uses BAG_UPDATE_DELAYED (same as Rarity addon)
  - **Lightning Fast** - 0.2s detection (instant feel, no lag)
  - **Loot-Time Trigger** - Shows notification when item drops/purchased, NOT when learned
  - **Smart Detection** - Only shows for collectibles you don't already have
  - **Collection Types** - Mounts, Battle Pets (caged), and Toys
  - **TWW-Compatible** - Triple-layer pet detection:
    - Primary: speciesID-based collection check
    - Secondary: API-returned pet name (TWW behavior)
    - Tertiary: Tooltip parsing (line 3 = pet name, locale-independent)
  - **Caged Pet Handling** - Shows **real pet name** (not "Pet Cage") in ALL UI:
    - Items tab, Storage tab, and notifications
    - Tooltip parsing: Line 3 = pet name (consistent across locales)
    - 100% locale-independent (no hardcoded strings)
  - **Universal Coverage** - Works for ALL sources: boss loot, chests, vendor purchases, AH, mail, quest rewards
  - **Optimized Performance** - 0.2s throttle + item cache pre-loading
  - **Consistent Design** - Same toast style as Vault Reminder (purple border, centered layout)
  - **Sound Effect** - Epic loot toast sound on acquisition
- **Centralized System** - Generic `ShowToastNotification()` function (SharedWidgets pattern)
- **Configurable** - Enable/disable each notification type in settings
- **Test Commands** - `/wn testloot [mount|pet|toy|spam]` - Test notifications (spam = 5 toasts)

## 📥 Installation

### **Method 1: Manual Installation**
1. Download the latest release from [GitHub Releases](https://github.com/warbandnexus/warband-nexus/releases)
2. Extract the `WarbandNexus` folder to `World of Warcraft\_retail_\Interface\AddOns\`
3. Restart WoW or type `/reload` in-game

### **Method 2: CurseForge Client**
1. Search for "Warband Nexus" in the CurseForge app
2. Click Install
3. Launch WoW

### **Method 3: Wago Addons**
1. Search for "Warband Nexus" in Wago Addons app
2. Click Install
3. Launch WoW

## 🎮 Usage

### **Opening the Interface**
- **Slash Command:** `/wn` or `/warband` or `/warbandnexus`
- **Minimap Button:** Left-click the minimap icon
- **At Banker:** Opens automatically when you access the bank

### **Scanning Data**
1. Visit a banker (any bank NPC)
2. Open the Warband or Personal bank
3. Click the **"Scan"** button in Warband Nexus UI
4. Data is cached and available on all characters

### **Searching Items**
1. Go to **Items** or **Storage** tab
2. Type in the search box
3. Results filter live as you type
4. Use **Shift+Click** on any item tooltip to search

### **Sorting Characters**
1. Go to **Characters** tab
2. Click any column header (Character, Level, Gold, Last Seen)
3. Click once: Sort ascending (^)
4. Click twice: Sort descending (v)
5. Click third time: Reset to default sort (level → name)
6. Your current character always stays at the top
7. Sorting preferences are saved automatically

### **Favorite Characters**
1. Go to **Characters** or **PvE** tab
2. Click the ⭐ star icon next to any character to mark as favorite
3. Favorites are a visual indicator (gold star)
4. Click again to remove the star
5. Favorites are synced across all characters

## 🔧 Slash Commands

### **Basic Commands**
- `/wn` - Toggle main window
- `/wn show` - Show main window
- `/wn hide` - Hide main window
- `/wn config` - Open configuration panel

### **Advanced Commands**
- `/wn scan` - Manually trigger a bank scan
- `/wn cache` - Show cache statistics
- `/wn clearcache` - Clear all cached data

### **Database Management**
- `/wn dbstats` - Show database size and statistics
- `/wn optimize` - Run database optimization (cleanup stale data)

### **API & Debugging** (Hidden)
- `/wn apireport` - Show WoW API compatibility report
- `/wn errors` - Show error statistics
- `/wn recover` - Emergency recovery (reload UI with data backup)

## ⚙️ Configuration

Access settings via `/wn config` or ESC → Interface → AddOns → Warband Nexus

### **General Settings**
- **Debug Mode** - Enable verbose logging
- **Auto-Open at Bank** - Automatically show UI when bank opens

### **Minimap Button**
- **Show Minimap Icon** - Toggle minimap button visibility

### **Tooltip Enhancements**
- **Enhanced Tooltips** - Show item locations in tooltips
- **Show Shift+Click Hint** - Display search hint in tooltips

### **Notifications**
- **Update Notes** - Pop-up changelog when addon is updated
- **Weekly Vault Reminder** - Notification when you have unclaimed vault rewards
- **Loot Notifications** - Track valuable looted items (coming soon)

### **Automation**
- **Auto Database Optimization** - Automatically cleanup on login (weekly)

## 🏗️ Architecture

Warband Nexus uses a modular architecture for maintainability and performance:

### **Core Modules**
- `Constants.lua` - Centralized version and configuration management
- `APIWrapper.lua` - Abstraction layer for WoW API (future-proof)
- `ErrorHandler.lua` - Comprehensive error logging and recovery
- `ReputationCacheService.lua` - Reputation data persistence
- `CurrencyCacheService.lua` - Currency data persistence
- `CollectionService.lua` - Collection tracking (mounts, pets, toys)
- `PvECacheService.lua` - PvE data (Mythic+, Great Vault, Lockouts)
- `ItemsCacheService.lua` - Smart bag/bank scanning with hash-based filtering
- `DataService.lua` - Character orchestration and aggregation
- `EventManager.lua` - Throttled/debounced event handling
- `DatabaseOptimizer.lua` - SavedVariables cleanup and optimization

### **Feature Modules**
- `MinimapButton.lua` - LibDBIcon integration
- `TooltipEnhancer.lua` - Item location tooltips
- `Scanner.lua` - Bank and inventory scanning
- `Banker.lua` - Gold transfer and bank operations
- `PvE.lua` - Mythic+, raids, and vault tracking

### **UI Modules**
- `UI.lua` - Main window and tab system
- `SharedWidgets.lua` - Reusable UI components
- `CharactersUI.lua` - Character list tab
- `ItemsUI.lua` - Item search tab
- `StorageUI.lua` - Storage breakdown tab
- `PvEUI.lua` - PvE progress tab
- `StatisticsUI.lua` - Statistics and charts tab

## 🔄 Performance

### **Cache System**
- **TTL-based caching** - Expires after 30 seconds
- **Smart invalidation** - Auto-refreshes on data changes
- **Memory efficient** - Only caches frequently accessed data

### **Event Optimization**
- **Throttling** - `BAG_UPDATE` throttled to 0.5s
- **Debouncing** - Search input debounced to 0.4s
- **Priority Queue** - Critical events processed first

### **Database Size**
- **Average:** ~50KB per character
- **Auto-cleanup** - Removes stale data (90+ days)
- **Manual optimization** - `/wn optimize` command

## 🐛 Troubleshooting

### **UI Not Opening**
1. Make sure you're at a banker
2. Try `/wn show` manually
3. Check `/wn config` → "Auto-Open at Bank" is enabled

### **Items Not Showing**
1. Visit the bank and click **"Scan"**
2. Check footer status (should show scan time)
3. Try `/wn clearcache` then scan again

### **Errors in Chat**
1. Run `/wn errors` to see error log
2. Try `/wn recover` for emergency recovery
3. Report the error with `/wn errors` output

### **Minimap Button Missing**
1. Open `/wn config`
2. Enable "Show Minimap Icon"
3. `/reload` UI

### **Performance Issues**
1. Run `/wn dbstats` to check database size
2. Run `/wn optimize` to cleanup
3. Consider enabling "Auto Database Optimization"

## 📝 Known Limitations

- **Scan Required** - You must visit the bank at least once per character
- **Bank Access** - Cannot scan banks remotely (WoW API limitation)
- **Real-time Sync** - Data syncs when bank is opened, not automatically
- **Addon Communication** - Does not use addon channels (privacy-focused)

## 🤝 Contributing

**This is a proprietary project. Contributions are not accepted at this time.**

All rights to this software are reserved by the copyright holder. 
If you wish to contribute or collaborate, please contact the author directly.

## 📄 License

**Copyright © 2025-2026 Mert Gedikli. All Rights Reserved.**

This software is proprietary and confidential. Unauthorized copying, distribution, 
modification, or use of this software is strictly prohibited. See the [LICENSE](LICENSE) 
file for full details.

## 🙏 Credits

### **Libraries Used**
- [Ace3](https://www.wowace.com/projects/ace3) - Framework (AceAddon, AceEvent, AceDB, AceConfig, AceGUI)
- [LibDataBroker-1.1](https://github.com/tekkub/libdatabroker-1-1) - Data broker interface
- [LibDBIcon-1.0](https://www.wowace.com/projects/libdbicon-1-0) - Minimap button

### **Inspired By**
- Multi-character inventory tracking solutions
- Unified bag management interfaces
- Modular addon architecture patterns

## 📧 Support

- **Issues:** [GitHub Issues](https://github.com/warbandnexus/warband-nexus/issues)
- **Discord:** [Join our server](#) (Coming soon)
- **CurseForge:** [Project Page](#) (Coming soon)

## 🗺️ Roadmap

### **v1.1.0** (Planned)
- [ ] Performance profiler (`/wn profile`)
- [ ] Backup & restore system (`/wn backup`)
- [ ] Advanced search with regex
- [ ] Export data to CSV/JSON

### **v1.2.0** (Future)
- [ ] Shopping list feature
- [ ] Item price tracking (AH integration)
- [ ] Guild bank support
- [ ] Mail tracking

---

**Made with ❤️ for the World of Warcraft community**

*Warband Nexus is not affiliated with or endorsed by Blizzard Entertainment.*
