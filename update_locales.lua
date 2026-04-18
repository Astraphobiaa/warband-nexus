local lfs = require "lfs"
local path = "c:\\Users\\Mert\\Documents\\GitHub\\warband-nexus\\Locales\\"

for file in lfs.dir(path) do
    if file:match("%.lua$") then
        local f = io.open(path .. file, "r")
        if f then
            local content = f:read("*a")
            f:close()
            
            if not content:find("GEAR_MISSING_ENCHANT") then
                local translation1 = "Missing Enchant"
                local translation2 = "Missing Gem"
                
                if file == "trTR.lua" then
                    translation1 = "Eksik Efsun"
                    translation2 = "Eksik Mücevher"
                elseif file == "deDE.lua" then
                    translation1 = "Fehlende Verzauberung"
                    translation2 = "Fehlender Edelstein"
                elseif file == "esES.lua" or file == "esMX.lua" then
                    translation1 = "Encantamiento faltante"
                    translation2 = "Gema faltante"
                elseif file == "frFR.lua" then
                    translation1 = "Enchantement manquant"
                    translation2 = "Gemme manquante"
                elseif file == "itIT.lua" then
                    translation1 = "Incantamento mancante"
                    translation2 = "Gemma mancante"
                elseif file == "koKR.lua" then
                    translation1 = "???? ??"
                    translation2 = "?? ??"
                elseif file == "ptBR.lua" then
                    translation1 = "Encantamento Ausente"
                    translation2 = "Gema Ausente"
                elseif file == "ruRU.lua" then
                    translation1 = "??? ???"
                    translation2 = "??? ?????????"
                elseif file == "zhCN.lua" then
                    translation1 = "????"
                    translation2 = "????"
                elseif file == "zhTW.lua" then
                    translation1 = "????"
                    translation2 = "????"
                end
                
                -- find the end of the L table
                local newContent = content:gsub("(L%[%"GEAR_SLOT_TRINKET2%"%]%s*=%s*.-)%s*(%)"), "%1\n    L[\"GEAR_MISSING_ENCHANT\"] = \"" .. translation1 .. "\"\n    L[\"GEAR_MISSING_GEM\"] = \"" .. translation2 .. "\"\n%2")
                
                local fw = io.open(path .. file, "w")
                if fw then
                    fw:write(newContent)
                    fw:close()
                    print("Updated " .. file)
                end
            end
        end
    end
end
