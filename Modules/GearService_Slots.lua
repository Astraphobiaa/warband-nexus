--[[
    Warband Nexus - Paper doll slot tables (Gear tab + storage matching).
    Split from GearService.lua (Lua 5.1 local limit).
    Loaded before Modules/GearService.lua.
]]

local _, ns = ...

-- Left column, right column, bottom row — mirrors Blizzard paper doll order.
local GEAR_SLOTS = {
    { id = 1,  key = "head",      label = INVTYPE_HEAD,      col = "left"   },
    { id = 2,  key = "neck",      label = INVTYPE_NECK,      col = "left"   },
    { id = 3,  key = "shoulder",  label = INVTYPE_SHOULDER,  col = "left"   },
    { id = 15, key = "back",      label = INVTYPE_CLOAK,      col = "left"   },
    { id = 5,  key = "chest",     label = INVTYPE_CHEST,     col = "left"   },
    { id = 9,  key = "wrist",     label = INVTYPE_WRIST,     col = "left"   },
    { id = 10, key = "hands",     label = INVTYPE_HAND,     col = "right"  },
    { id = 6,  key = "waist",     label = INVTYPE_WAIST,     col = "right"  },
    { id = 7,  key = "legs",      label = INVTYPE_LEGS,      col = "right"  },
    { id = 8,  key = "feet",      label = INVTYPE_FEET,      col = "right"  },
    { id = 11, key = "ring1",     label = "Ring",      col = "right"  },
    { id = 12, key = "ring2",     label = "Ring",      col = "right"  },
    { id = 13, key = "trinket1",  label = "Trinket",   col = "bottom" },
    { id = 14, key = "trinket2",  label = "Trinket",   col = "bottom" },
    { id = 16, key = "mainhand",  label = INVTYPE_WEAPONMAINHAND, col = "bottom" },
    { id = 17, key = "offhand",   label = INVTYPE_WEAPONOFFHAND,  col = "bottom" },
    -- Vanilla ranged slot: bows, guns, wands, thrown, and paladin/shaman/druid relics. Retail
    -- dropped it in Legion, WoW Forever brings it back -- C_PaperDollInfo.IsRangedSlotShown()
    -- answers true there and GetInventorySlotInfo("RangedSlot") returns 18. `rangedOnly` keeps
    -- it out of the paperdoll on clients that do not show it.
    { id = 18, key = "ranged",    label = INVTYPE_RANGED or "Ranged", col = "bottom", rangedOnly = true },
}

--- The ranged slot only exists where the client shows it; everything that walks the paperdoll
--- uses this instead of the raw table so the slot appears on Forever and nowhere else.
local rangedShown
local function IsRangedSlotAvailable()
    if rangedShown == nil then
        local ok, shown = pcall(function()
            return C_PaperDollInfo and C_PaperDollInfo.IsRangedSlotShown
                and C_PaperDollInfo.IsRangedSlotShown()
        end)
        rangedShown = (ok and shown) and true or false
    end
    return rangedShown
end
ns.GearSlots_IsRangedSlotAvailable = IsRangedSlotAvailable

-- Reverse map: slotID -> slot def (O(1) lookup)
local SLOT_BY_ID = {}
for i = 1, #GEAR_SLOTS do
    local s = GEAR_SLOTS[i]
    SLOT_BY_ID[s.id] = s
end

-- WoW uses shared "item redundancy" for rings, trinkets, and weapons: one watermark per group.
-- Ring 1/2, Trinket 1/2, and Main Hand/Off Hand all share their respective high watermark slot.
-- For paired slots, gold-only affordability must be capped by THIS item's ilvl — otherwise the
-- pair's higher ilvl makes upgrades look free when the upgrade NPC actually charges crests
-- (e.g. Off Hand at 285 falsely marks Main Hand 282→285 as gold-only).
local SLOT_PAIRS = { [11] = 12, [12] = 11, [13] = 14, [14] = 13, [16] = 17, [17] = 16 }

-- Maps INVTYPE_ equip location -> which slot IDs that item can fill
-- C_Item.GetItemInfoInstant returns 4th value = itemEquipLoc (string, e.g. "INVTYPE_SHOULDER")
local EQUIP_LOC_TO_SLOTS = {
    INVTYPE_HEAD           = { 1  },
    INVTYPE_NECK           = { 2  },
    INVTYPE_SHOULDER       = { 3  },
    INVTYPE_BACK           = { 15 },
    INVTYPE_CLOAK          = { 15 },
    INVTYPE_CHEST          = { 5  },
    INVTYPE_ROBE           = { 5  },
    INVTYPE_WRIST          = { 9  },
    INVTYPE_HAND           = { 10 },
    INVTYPE_WAIST          = { 6  },
    INVTYPE_LEGS           = { 7  },
    INVTYPE_FEET           = { 8  },
    INVTYPE_FINGER         = { 11, 12 },
    INVTYPE_TRINKET        = { 13, 14 },
    INVTYPE_WEAPON         = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 },
    INVTYPE_2HWEAPON       = { 16 },
    INVTYPE_WEAPONOFFHAND  = { 17 },
    INVTYPE_SHIELD         = { 17 },
    INVTYPE_HOLDABLE       = { 17 },
    -- Ranged weapons route to slot 18 where the client shows that slot (WoW Forever brings the
    -- vanilla ranged slot back). Mapping them to 16 there would have the storage finder offer a
    -- hunter's bow as a main-hand upgrade and compare its ilvl against the equipped melee weapon.
    -- On retail the slot is gone, so legacy ranged items stay mapped to the main hand.
}

--- Ranged equip locations resolve on FIRST LOOKUP, not at load: IsRangedSlotShown() is not
--- reliable before the player is in the world. Mapping a bow to slot 16 on a client that has
--- slot 18 would make the storage finder offer it as a main-hand upgrade and compare its ilvl
--- against the equipped melee weapon, so this has to be right rather than early.
local RANGED_EQUIP_LOCS = {
    INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true, INVTYPE_RELIC = true,
}
setmetatable(EQUIP_LOC_TO_SLOTS, {
    __index = function(tbl, key)
        if not RANGED_EQUIP_LOCS[key] then return nil end
        local slots = IsRangedSlotAvailable() and { 18 } or { 16 }
        rawset(tbl, key, slots)
        return slots
    end,
})

local ARMOR_SLOT_IDS = {
    [1] = true, [3] = true, [5] = true, [6] = true, [7] = true, [8] = true, [9] = true, [10] = true, [15] = true,
}

ns.GearServiceSlots = {
    GEAR_SLOTS = GEAR_SLOTS,
    SLOT_BY_ID = SLOT_BY_ID,
    EQUIP_LOC_TO_SLOTS = EQUIP_LOC_TO_SLOTS,
    SLOT_PAIRS = SLOT_PAIRS,
    ARMOR_SLOT_IDS = ARMOR_SLOT_IDS,
}
ns.GEAR_SLOTS = GEAR_SLOTS
ns.SLOT_BY_ID = SLOT_BY_ID
ns.EQUIP_LOC_TO_SLOTS = EQUIP_LOC_TO_SLOTS