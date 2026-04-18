local link = "|cffa335ee|Hitem:225574::::::::80:71:0:0:1:11910|h[Example]|h|r"
local enchantStr = string.match(link, "item:%%d+:(%%d*)")
print(enchantStr == "" and "EMPTY" or enchantStr)
