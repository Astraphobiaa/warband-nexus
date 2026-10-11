#!/usr/bin/env luajit
-- Regression test: Profession & Concentration persistence across logout, login, and reload.
-- Ensures that transient API empty states (e.g. during PLAYER_LOGOUT teardown)
-- never wipe saved professions, concentration, or expansions in db.global.characters.

local failures = 0
local function assertTrue(cond, msg)
    if not cond then
        failures = failures + 1
        io.stderr:write("FAIL: " .. msg .. "\n")
    else
        io.write("  ok   " .. msg .. "\n")
    end
end

io.write("Phase 1: DataService.UpdateProfessionData Guard Against Empty / Nil Tables\n")
do
    -- Mock DataService
    local DataService = {}
    local db = {
        global = {
            characters = {
                ["Player-1234"] = {
                    name = "Puryshiva",
                    realm = "Kazzak",
                    professions = {
                        [1] = { name = "Tailoring", skillLine = 197, rank = 100, maxRank = 100 },
                        [2] = { name = "Jewelcrafting", skillLine = 755, rank = 100, maxRank = 100 },
                    }
                }
            }
        }
    }

    function DataService:UpdateProfessionData(newData)
        if not newData or not next(newData) then return end
        local char = db.global.characters["Player-1234"]
        if not char then return end

        local hasPrimary = false
        for _, prof in pairs(newData) do
            if prof and prof.name and prof.skillLine then
                local sl = prof.skillLine
                if sl ~= 185 and sl ~= 356 and sl ~= 129 then
                    hasPrimary = true
                    break
                end
            end
        end

        local existingHasPrimary = false
        if char.professions then
            for _, prof in pairs(char.professions) do
                if prof and prof.name and prof.skillLine then
                    local sl = prof.skillLine
                    if sl ~= 185 and sl ~= 356 and sl ~= 129 then
                        existingHasPrimary = true
                        break
                    end
                end
            end
        end

        if not hasPrimary and existingHasPrimary then
            return
        end

        char.professions = newData
    end

    -- 1. Calling with nil or empty table
    DataService:UpdateProfessionData(nil)
    assertTrue(#db.global.characters["Player-1234"].professions == 2, "nil newData does not wipe professions")

    DataService:UpdateProfessionData({})
    assertTrue(#db.global.characters["Player-1234"].professions == 2, "empty table newData does not wipe professions")

    -- 2. Calling with only cooking (secondary) when primary exists
    DataService:UpdateProfessionData({
        [1] = { name = "Cooking", skillLine = 185, rank = 50, maxRank = 100 }
    })
    assertTrue(#db.global.characters["Player-1234"].professions == 2, "secondary-only scan does not wipe primary professions")
    assertTrue(db.global.characters["Player-1234"].professions[1].name == "Tailoring", "primary profession Tailoring preserved")
end

io.write("Phase 2: ProfessionService OnProfessionChanged Stale Wipe Protection\n")
do
    local charData = {
        name = "Puryshiva",
        professionExpansions = {
            [2918] = { currentSkill = 100, maxSkill = 100, skillLineID = 2918 },
            [2910] = { currentSkill = 100, maxSkill = 100, skillLineID = 2910 },
        },
        discoveredSkillLines = { [2918] = true, [2910] = true },
        concentration = {
            [2918] = { current = 244, max = 1000, lastUpdated = 100000 },
            [2910] = { current = 219, max = 1000, lastUpdated = 100000 },
        }
    }

    local function SimulateProfessionChanged(currentProfs)
        -- New rule in ProfessionService:
        -- Stale cleanup ONLY runs if next(currentProfs) ~= nil (at least one active profession detected)
        local canClearStale = next(currentProfs) ~= nil
        if canClearStale and charData.professionExpansions then
            for slID in pairs(charData.professionExpansions) do
                if not currentProfs[slID] then
                    charData.professionExpansions[slID] = nil
                    if charData.discoveredSkillLines then charData.discoveredSkillLines[slID] = nil end
                    if charData.concentration then charData.concentration[slID] = nil end
                end
            end
        end
    end

    -- Call with empty detected professions (e.g. transient API blank)
    SimulateProfessionChanged({})

    assertTrue(charData.professionExpansions[2918] ~= nil, "expansions preserved when currentProfs is empty")
    assertTrue(charData.discoveredSkillLines[2918] == true, "discoveredSkillLines preserved when currentProfs is empty")
    assertTrue(charData.concentration[2918].current == 244, "concentration preserved when currentProfs is empty")
end

io.write("Phase 3: UI Concentration Resolution Across Key Formats\n")
do
    local PUI = {}
    function PUI.GetCharacterConcentration(char, profName, slID, prof)
        if not char or not char.concentration then return nil end

        if slID then
            local byId = char.concentration[slID]
            if byId then return byId end
            local numId = tonumber(slID)
            if numId and char.concentration[numId] then return char.concentration[numId] end
            local strId = tostring(slID)
            if strId and char.concentration[strId] then return char.concentration[strId] end
        end

        if prof and prof.skillLine then
            local byProfSl = char.concentration[prof.skillLine]
            if byProfSl then return byProfSl end
            local numProfSl = tonumber(prof.skillLine)
            if numProfSl and char.concentration[numProfSl] then return char.concentration[numProfSl] end
            local strProfSl = tostring(prof.skillLine)
            if strProfSl and char.concentration[strProfSl] then return char.concentration[strProfSl] end
        end

        if profName and char.concentration[profName] then
            return char.concentration[profName]
        end

        for key, entry in pairs(char.concentration) do
            if type(entry) == "table" and (entry.current or entry.max) then
                if slID and (key == slID or tostring(key) == tostring(slID) or entry.skillLineID == slID or entry.skillLineID == tonumber(slID)) then
                    return entry
                end
                if profName and (entry.name == profName or entry.profession == profName) then
                    return entry
                end
            end
        end

        return nil
    end

    local testChar = {
        name = "Puryshiva",
        concentration = {
            [2918] = { current = 244, max = 1000, lastUpdated = 12345 },
            ["Jewelcrafting"] = { current = 219, max = 1000, lastUpdated = 12345 },
            ["3000"] = { current = 500, max = 1000, lastUpdated = 12345 },
        }
    }

    local conc1 = PUI.GetCharacterConcentration(testChar, "Tailoring", 2918, nil)
    assertTrue(conc1 and conc1.current == 244, "resolves concentration by numeric skillLineID")

    local conc2 = PUI.GetCharacterConcentration(testChar, "Jewelcrafting", 755, { skillLine = 755 })
    assertTrue(conc2 and conc2.current == 219, "resolves concentration by profName fallback")

    local conc3 = PUI.GetCharacterConcentration(testChar, "Engineering", "3000", nil)
    assertTrue(conc3 and conc3.current == 500, "resolves concentration by string slID")

    local conc4 = PUI.GetCharacterConcentration(testChar, "Blacksmithing", 9999, nil)
    assertTrue(conc4 == nil, "returns nil safely when no concentration exists")
end

if failures > 0 then
    io.stderr:write(string.format("\nFAILED: %d failure(s)\n", failures))
    os.exit(1)
end
io.write("\nOK: All profession persistence and concentration tests passed!\n")
