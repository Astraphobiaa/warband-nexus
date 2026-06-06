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
| LayoutCoordinator viewport | `computeScrollContentWidth` = live `scroll:GetWidth()` (`GetScrollViewportWidth`); tab mins via `ComputeScrollChildWidth` on commit only |

## Per tab

| Tab | Module | resultsContainer | Live resize (corner-drag) | Commit resize | Notes |
|-----|--------|------------------|---------------------------|---------------|-------|
| chars | CharactersUI.lua | no | **frozen** (shell only) | PopulateContent | UI_GetCharRowTotalWidth; virtual list on commit |
| currency | CurrencyUI.lua | yes | **frozen** (`freezeWhileResizing`) | RESULTS_CONTAINER relayout / PopulateContent fallback | expandable sections height |
| items | ItemsUI.lua | yes (inventory + warband) | **frozen** | RedrawItemsResultsOnly | SyncStorageResultsLayoutFromTail |
| gear | GearUI_Layout.lua | no | chromeOnly relayout (`GearUI_RelayoutGearTabViewportFill`) | relayout + RedrawGearStorageRecommendationsOnly | paper doll + recommended panel |
| reputations | ReputationUI.lua | yes | **frozen** (`freezeWhileResizing`) | RESULTS_CONTAINER relayout | MeasureChildrenHeight |
| collections | CollectionsUI.lua | embedded in contentFrame | **frozen** (commit relayout only) | RelayoutActiveSubTabChrome | split list/viewer; debounced live outside drag |
| plans | PlansUI.lua | browse results | none (stale until commit) | CardLayoutManager RefreshLayout | _plansCardLayoutManager on scrollChild |
| pve | PvEUI.lua | no | **frozen** | PopulateContent(true) | min scroll width |
| professions | ProfessionsUI.lua | no | STRETCH_ROWS live | custom relayout (no PopulateContent) | onCommit returns true |
| stats | StatisticsUI.lua | storageCard annex | none | PopulateContent | three-card min width |

## QA matrix (manual)

- Resolutions: 1920x1080, 2560x1440, 3840x2160 (ultrawide optional)
- WoW UI scale: 100%, 125%, 150%
- Addon uiScale (Settings): 80%, 100%, 120%
- Per tab: corner resize drag, header drag, bottom-edge clamp, /reload geometry restore

Profiler slices: Lay_resizeLive, Lay_resizeCommit, Lay_displayChanged (LayoutCoordinator.lua).
