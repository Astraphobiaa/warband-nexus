--[[
    Warband Nexus - Try Counter self-test results window.

    /wn tc test used to print a hundred-odd lines into chat. This renders them as a scrollable,
    grouped list instead: a summary bar, section bands, and one row per probe with a status icon.

    Status markers are TEXTURES via ns.UI_GetIconMarkup (status_ok / status_fail / status_warn),
    never unicode glyphs -- the WoW font has no check or cross codepoint and renders them as empty
    boxes. The registry resolves an atlas only when C_Texture.GetAtlasInfo confirms it exists and
    falls back to a shipped file otherwise, so nothing here can render blank.

    The command is already debug-gated (the /wn tc family sits behind IsDebugOn in CommandService),
    so this window only ever appears in debug mode.

    Layout: shell from ns.UI_CreateExternalWindow, scroll from ns.UI.Factory, colours from the theme
    helpers, one padding constant per axis. Rows are anchored to the previous row and carry an
    explicit height, so a wrapped line can never overlap the next one.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

local CreateExternalWindow = ns.UI_CreateExternalWindow
local Factory = ns.UI and ns.UI.Factory
local FontManager = ns.FontManager

local PAD = 14
local ROW_GAP = 3
local SECTION_TOP_GAP = 10
local ICON_COL = 18
local ICON_GAP = 6
local MIN_ROW_H = 16
local SCROLLBAR_W = 20
local CONTENT_W = 560
local TEXT_W = CONTENT_W - ICON_COL - ICON_GAP
local WINDOW_W = CONTENT_W + (PAD * 2) + SCROLLBAR_W
local WINDOW_H = 500

-- Icon key + text role per status. Keys are the ones IconRegistry already ships.
local STATUS = {
    pass = { icon = "status_ok",      role = "Normal" },
    fail = { icon = "status_fail",    role = "Bright" },
    skip = { icon = "status_pending", role = "Dim" },
    warn = { icon = "status_warn",    role = "Normal" },
    info = { icon = "status_pending", role = "Dim" },
}

local function TextHex(role)
    if ns.UI_GetTextRoleHex then
        local hex = ns.UI_GetTextRoleHex(role)
        if hex then return hex end
    end
    return "|cffeeeeee"
end

local function Marker(status)
    local meta = STATUS[status] or STATUS.info
    if ns.UI_GetIconMarkup then
        local m = ns.UI_GetIconMarkup(meta.icon, 14, 14)
        if m and m ~= "" then return m end
    end
    -- Last resort stays inside printable ASCII; a unicode glyph would render as a box.
    return (status == "fail") and "|cffff4444x|r" or "|cff888888-|r"
end

local function NewLine(parent, role)
    local fs = FontManager and FontManager:CreateFontString(parent, "body", "OVERLAY")
    if not fs then fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall") end
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    fs:SetWordWrap(true)
    return fs
end

---@param rows table[] { status, label, err }
---@param totals table { pass, fail, skip, warn }
---@return boolean rendered
function ns.UI_ShowTryCounterTestResults(rows, totals)
    if not CreateExternalWindow or not Factory then
        -- UI layer unavailable: the caller keeps its chat output, nothing is lost.
        return false
    end
    rows = rows or {}
    totals = totals or {}

    local dialog, contentFrame = CreateExternalWindow({
        name = "TryCounterTestResults",
        title = (ns.L and ns.L["TRYCOUNTER_TEST_RESULTS_TITLE"]) or "Try Counter self-test",
        icon = ns.UI_GetIconFile("book"),
        width = WINDOW_W,
        height = WINDOW_H,
        preventDuplicates = true,
    })
    if not dialog or not contentFrame then return false end

    -- ── summary bar ──────────────────────────────────────────────────────────
    local failed = (totals.fail or 0) > 0
    local summary = NewLine(contentFrame, "Bright")
    summary:SetPoint("TOPLEFT", PAD, -PAD)
    summary:SetWidth(CONTENT_W)
    summary:SetText(table.concat({
        Marker("pass"), " ", TextHex("Bright"), tostring(totals.pass or 0), " passed|r    ",
        Marker(failed and "fail" or "skip"), " ",
        failed and "|cffff6666" or TextHex("Dim"), tostring(totals.fail or 0), " failed|r    ",
        Marker("skip"), " ", TextHex("Dim"), tostring(totals.skip or 0), " skipped|r    ",
        Marker("warn"), " ", TextHex("Normal"), tostring(totals.warn or 0), " warnings|r",
    }))
    local summaryH = math.max(18, summary:GetStringHeight() or 18)

    -- Theme divider, not a hand-rolled SetColorTexture: the chrome gate rejects the latter and the
    -- helper already follows the light/dark border ladder and the classic-chrome thickness rules.
    local rule = Factory:CreateThemeDivider(contentFrame, { orientation = "horizontal" })
    if rule then
        rule:SetPoint("TOPLEFT", PAD, -(PAD + summaryH + 6))
        rule:SetPoint("TOPRIGHT", -PAD, -(PAD + summaryH + 6))
    end

    -- ── scrolling list ───────────────────────────────────────────────────────
    local scroll = Factory:CreateScrollFrame(contentFrame, "UIPanelScrollFrameTemplate", true)
    if not scroll then return false end
    scroll:SetPoint("TOPLEFT", PAD, -(PAD + summaryH + 12))
    scroll:SetPoint("BOTTOMRIGHT", -(PAD + SCROLLBAR_W), PAD)

    local child = scroll:GetScrollChild()
    if not child then
        child = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(child)
    end
    -- Content width, never the outer dialog width: the scrollbar owns its own column.
    child:SetWidth(CONTENT_W)

    local y = 0
    for i = 1, #rows do
        local row = rows[i]
        local isSection = (row.status == "section")

        if isSection and i > 1 then y = y + SECTION_TOP_GAP end

        if isSection then
            local band = NewLine(child, "Bright")
            -- Width BEFORE text: GetStringHeight only reports the wrapped height once the font
            -- string knows how wide it may run.
            band:SetWidth(CONTENT_W)
            band:SetText(TextHex("Bright") .. tostring(row.label) .. "|r")
            local h = math.max(MIN_ROW_H, band:GetStringHeight() or MIN_ROW_H)
            band:SetHeight(h)
            band:SetPoint("TOPLEFT", 0, -y)
            y = y + h + ROW_GAP
        else
            local meta = STATUS[row.status] or STATUS.info

            local icon = NewLine(child, meta.role)
            icon:SetWidth(ICON_COL)
            icon:SetText(Marker(row.status))

            local text = NewLine(child, meta.role)
            text:SetWidth(TEXT_W)
            local body = TextHex(meta.role) .. tostring(row.label) .. "|r"
            if row.status == "fail" and row.err then
                body = body .. "\n|cffff8888" .. tostring(row.err) .. "|r"
            end
            text:SetText(body)

            local h = math.max(MIN_ROW_H, text:GetStringHeight() or MIN_ROW_H)
            text:SetHeight(h)
            icon:SetHeight(MIN_ROW_H)

            icon:SetPoint("TOPLEFT", 0, -y)
            text:SetPoint("TOPLEFT", ICON_COL + ICON_GAP, -y)
            y = y + h + ROW_GAP
        end
    end

    child:SetHeight(math.max(1, y))
    dialog:Show()
    return true
end
