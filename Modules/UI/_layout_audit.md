# Main window layout audit matrix

Hierarchical checklist per main tab (viewport -> scrollChild -> resultsContainer).
Used for resize/reposition QA across 1080p / 1440p / 4K and WoW + addon UI scale.

## Shell (all tabs)

| Region | Check |
|--------|--------|
| content -> viewportBorder | MAIN_SCROLL insets symmetric; scroll not under v-scrollbar |
| scroll vs scrollBarColumn | Content width = viewport - SCROLLBAR_COLUMN_WIDTH - SCROLL_GAP |
| fixedHeader / columnHeaderClip | columnHeaderInner width matches scrollChild after UpdateScrollLayout |
| scrollChild height | max(content, viewport) after PopulateContent; bottom fill / annex no double band |

## Per tab

| Tab | Module | resultsContainer | Live resize | Commit resize | Notes |
|-----|--------|------------------|-------------|---------------|-------|
| chars | CharactersUI.lua | no | row width via min scroll | PopulateContent | UI_GetCharRowTotalWidth |
| currency | CurrencyUI.lua | yes | toolbar anchors | PopulateContent | expandable sections height |
| items | ItemsUI.lua | yes (inventory + warband) | warband debounced redraw | RedrawStorageResultsOnly / PopulateContent | SyncStorageResultsLayoutFromTail |
| gear | GearUI.lua | no | dropdown scroll width | PopulateContent | paper doll fill viewport |
| reputations | ReputationUI.lua | yes | split chrome | PopulateContent | MeasureChildrenHeight |
| collections | CollectionsUI.lua | embedded in contentFrame | RelayoutActiveSubTabChrome debounced | same + PopulateContent fallback | split list/viewer |
| plans | PlansUI.lua | browse results | CardLayoutManager RefreshLayout | PopulateContent | _plansCardLayoutManager on scrollChild |
| pve | PvEUI.lua | no | min scroll width | PopulateContent | |
| professions | ProfessionsUI.lua | no | grid width | PopulateContent | |
| stats | StatisticsUI.lua | storageCard annex | card widths | PopulateContent | three-card min width |

## QA matrix (manual)

- Resolutions: 1920x1080, 2560x1440, 3840x2160 (ultrawide optional)
- WoW UI scale: 100%, 125%, 150%
- Addon uiScale (Settings): 80%, 100%, 120%
- Per tab: corner resize drag, header drag, bottom-edge clamp, /reload geometry restore

Profiler slices: Lay_resizeLive, Lay_resizeCommit, Lay_displayChanged (LayoutCoordinator.lua).
