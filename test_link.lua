local link = "|cffa335ee|Hitem:225574:0:0:0:0:0:0:0:80:71:0:0:1:11910|h[Example Item]|h|r"
local e, g1, g2, g3, g4 = string.match(link, "item:%d+:(%d*):(%d*):(%d*):(%d*):(%d*)")
print("Enchant: " .. tostring(e) .. " G1: " .. tostring(g1))
