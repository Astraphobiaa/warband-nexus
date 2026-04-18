local links = {
    "|cffa335ee|Hitem:225574:0:0:0:0:0:0:0:80:71:0:0:1:11910|h[Example]|h|r",
    "|cffa335ee|Hitem:225574:1234:0:0:0:0:0:0:80:71:0:0:1:11910|h[Example]|h|r",
    "|cffa335ee|Hitem:225574::::::::80:71:0:0:1:11910|h[Example]|h|r"
}
for i, itemLink in ipairs(links) do
    local hasEnchant = false
    local enchantStr = string.match(itemLink, "item:%%d+:(%%d*)")
    if enchantStr and enchantStr ~= "" and enchantStr ~= "0" then
        hasEnchant = true
    end
    print(tostring(i) .. " -> str:" .. tostring(enchantStr) .. " has:" .. tostring(hasEnchant))
end
