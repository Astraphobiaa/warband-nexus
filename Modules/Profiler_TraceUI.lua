--[[
    Warband Nexus - Profiler trace table UI (dev-only).
    Loaded after Profiler.lua. Columns: Operation | Where | Detail | ms
]]

local _, ns = ...

local Profiler = ns.Profiler
if not Profiler then return end

local tinsert = table.insert
local tremove = table.remove
local wipe = wipe
local time = time
local format = string.format

Profiler.TRACE_TABLE_MIN_MS = Profiler.TRACE_TABLE_MIN_MS or 8
Profiler.TRACE_COALESCE_SEC = Profiler.TRACE_COALESCE_SEC or 4
Profiler.TRACE_DISPLAY_MAX = Profiler.TRACE_DISPLAY_MAX or 600

local ROW_HEIGHT = 20
local COL_OP_W = 72
local COL_WHERE_W = 88
local COL_MS_W = 48
local PAD = 4

local C_GOOD = "|cff00ff00"
local C_WARN = "|cffff8800"
local C_BAD = "|cffff4444"
local C_DIM = "|cff808080"
local C_INFO = "|cffc8c8c8"
local C_ACCENT = "|cff9370DB"
local C_R = "|r"
local PREFIX = C_ACCENT .. "[WN Profiler]" .. C_R .. " "

local function IsProfilerDebugAllowed()
    return ns.IsDebugModeEnabled and ns.IsDebugModeEnabled() or false
end

local function GetPersistRoot()
    local db = ns.db or (_G.WarbandNexus and _G.WarbandNexus.db)
    if not db or not db.profile then return nil end
    db.profile.profilerPersist = db.profile.profilerPersist or {}
    return db.profile.profilerPersist
end

local function StripColorCodes(s)
    if not s or s == "" then return "" end
    return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

local function Trim(s)
    if not s then return "" end
    return (s:match("^%s*(.-)%s*$") or "")
end

local function MsText(ms)
    if ms == nil then return "-" end
    return format("%.1f", ms)
end

local function MsColor(ms)
    if ms == nil then return C_DIM end
    if ms >= 33 then return C_BAD end
    if ms >= (Profiler.TRACE_ANOMALY_MS or 16.67) then return C_WARN end
    return C_GOOD
end

local function OpColor(kind)
    if kind == "error" then return C_BAD end
    if kind == "anomaly" then return C_WARN end
    if kind == "event" then return C_ACCENT end
    if kind == "bag" then return "|cff88ccff" end
    return C_INFO
end

local function SplitSliceLabel(label)
    label = tostring(label or "")
    local cat, name = label:match("^([^/]+)/(.+)$")
    if cat and name then return cat, name end
    return "Svc", label
end

--- Drop noisy plain lines before structuring.
local function ShouldParsePlainLine(clean)
    if clean == "" then return false end
    if clean:find("^START ", 1, false) then return false end
    if clean:find("^ASYNC START ", 1, false) then return false end
    if clean:find("session_dirty", 1, true) then return false end
    return true
end

---@param plainLine string
---@return table|nil
local function ParsePlainTraceLine(plainLine)
    local clean = StripColorCodes(plainLine)
    if not ShouldParsePlainLine(clean) then return nil end

    local label, stopMs = clean:match("^STOP (.+) ([%d%.]+)ms$")
    if label then
        local cat, name = SplitSliceLabel(label)
        local ms = tonumber(stopMs)
        return {
            op = "Slice",
            where = cat,
            detail = name,
            ms = ms,
            kind = (ms or 0) >= (Profiler.TRACE_ANOMALY_MS or 16.67) and "anomaly" or "perf",
        }
    end

    local asyncLabel, asyncMs = clean:match("^ASYNC STOP (.+) CPU=([%d%.]+)ms")
    if asyncLabel then
        local cat, name = SplitSliceLabel(asyncLabel)
        local ms = tonumber(asyncMs)
        return {
            op = "Async",
            where = cat,
            detail = name,
            ms = ms,
            kind = (ms or 0) >= (Profiler.TRACE_ANOMALY_MS or 16.67) and "anomaly" or "perf",
        }
    end

    local evt, ms, rest = clean:match("^WN_TRACE_EVT ([^%s]+) ([%d%.]+)ms(.*)$")
    if evt then
        return {
            op = "Event",
            where = evt,
            detail = Trim(rest),
            ms = tonumber(ms),
            kind = "event",
        }
    end

    local cat, pms, hint = clean:match("^%[([^%]]+)%] ([%d%.]+)ms%s+(.*)$")
    if cat and pms then
        local ms = tonumber(pms)
        return {
            op = cat,
            where = "Perf",
            detail = Trim(hint),
            ms = ms,
            kind = (ms or 0) >= (Profiler.TRACE_ANOMALY_MS or 16.67) and "anomaly" or "perf",
        }
    end

    local bag, dtype, slots, total, phases = clean:match(
        "%[WN BagPerf%] bag=(%S+)%s+(%S+)%s+slots=(%d+)%s+total=([%d%.]+)ms%s*|%s*(.*)"
    )
    if bag then
        local msNum = tonumber(total)
        return {
            op = "Bag",
            where = "bag " .. bag,
            detail = Trim(phases ~= "" and phases or ("type=" .. dtype .. " slots=" .. slots)),
            ms = msNum,
            kind = msNum and msNum >= (Profiler.TRACE_ANOMALY_MS or 16.67) and "anomaly" or "bag",
        }
    end

    if clean:find("SPIKE", 1, true) or clean:find("SLOW", 1, true) then
        local spikeMs = clean:match("([%d%.]+)ms")
        return {
            op = "Frame",
            where = "Client",
            detail = clean,
            ms = spikeMs and tonumber(spikeMs) or nil,
            kind = "anomaly",
        }
    end

    if clean:find("Error", 1, true) or clean:find("error", 1, true) then
        return {
            op = "Error",
            where = "-",
            detail = clean,
            ms = nil,
            kind = "error",
        }
    end

    return {
        op = "Log",
        where = "Debug",
        detail = clean,
        ms = nil,
        kind = "info",
    }
end

--- Keep trace table focused: bag/zone/events/errors/spikes + slow slices only.
---@param entry table
---@return boolean
local function ShouldRetainTraceRow(entry)
    if not entry then return false end
    if entry.kind == "error" then return true end
    if entry.kind == "anomaly" then return true end
    if entry.op == "Frame" then
        local detail = tostring(entry.detail or "")
        if detail:find("outside WN", 1, true) and (entry.ms or 0) < 50 then
            local root = GetPersistRoot()
            if not (root and root.traceOutsideWnFrames == true) then
                return false
            end
        end
        return true
    end
    if entry.op == "Error" then return true end
    if entry.op == "Bag" or entry.op == "Zone" or entry.op == "Event" or entry.op == "Handler" then
        return (entry.ms or 0) >= Profiler.TRACE_TABLE_MIN_MS
    end
    if entry.op == "Slice" or entry.op == "Async" or entry.op == "Perf" then
        return (entry.ms or 0) >= Profiler.TRACE_TABLE_MIN_MS
    end
    if entry.op == "Log" then
        local root = GetPersistRoot()
        if not (root and root.traceCacheLogs == true) then return false end
        return true
    end
    return false
end

local function NormalizeFrameCoalesceDetail(detail)
    detail = tostring(detail or "")
    if detail:find("outside WN", 1, true) or detail:find("no WN work", 1, true) then
        return "outside WN"
    end
    if detail:find("^near ", 1, false) or detail:find("^last Frame", 1, false) then
        return detail:sub(1, 48)
    end
    return detail
end

local function TraceRowsCoalesce(entry, prev)
    if not entry or not prev then return false end
    local entryDetail = entry.detail
    local prevDetail = prev.detail
    if entry.op == "Frame" and prev.op == "Frame" then
        entryDetail = NormalizeFrameCoalesceDetail(entry.detail)
        prevDetail = NormalizeFrameCoalesceDetail(prev.detail)
    end
    if entry.op ~= prev.op or entry.where ~= prev.where or entryDetail ~= prevDetail then
        return false end
    if (entry.t or 0) - (prev.t or 0) > Profiler.TRACE_COALESCE_SEC then return false end
    prev.count = (prev.count or 1) + 1
    if entry.op == "Frame" and entryDetail == "outside WN" then
        prev.detail = "outside WN (client / GC / other addon)"
    end
    if entry.ms and (not prev.ms or entry.ms > prev.ms) then
        prev.ms = entry.ms
    end
    prev.t = entry.t
    if entry.kind == "anomaly" or entry.kind == "error" then
        prev.kind = entry.kind
    end
    return true
end

local function TrimTraceRows(rows)
    local maxRows = Profiler.TRACE_DISPLAY_MAX or 600
    while #rows > maxRows do
        local removed = false
        for i = 1, #rows do
            local e = rows[i]
            if e.kind ~= "error" and e.kind ~= "anomaly" and e.op ~= "Error" and e.op ~= "Frame" then
                tremove(rows, i)
                removed = true
                break
            end
        end
        if not removed then
            tremove(rows, 1)
        end
    end
end

function Profiler:AppendTraceRow(op, where, detail, ms, kind)
    if not IsProfilerDebugAllowed() then return end
    if not self._traceRows then
        self._traceRows = {}
    end
    local entry = {
        op = tostring(op or "-"),
        where = tostring(where or "-"),
        detail = tostring(detail or ""),
        ms = tonumber(ms),
        kind = kind or "info",
        t = time(),
        count = 1,
    }
    if not ShouldRetainTraceRow(entry) then return end

    if self.NoteActivityHint and entry.op ~= "Frame" then
        self:NoteActivityHint(entry.op, entry.where, entry.detail, entry.ms)
    end

    local rows = self._traceRows
    local prev = rows[#rows]
    if prev and TraceRowsCoalesce(entry, prev) then
        if self._traceWindow and self._traceWindow:IsShown() then
            self:_ScheduleTraceTableSync(true)
        end
        return
    end

    tinsert(rows, entry)
    TrimTraceRows(rows)
    self._traceUINeedsFullRebuild = true
    if self._traceWindow and self._traceWindow:IsShown() then
        self:_ScheduleTraceTableSync(false)
    end
end

function Profiler:AppendTraceRowFromPlain(plainLine, dedupe)
    if not plainLine then return end
    local entry = ParsePlainTraceLine(plainLine)
    if not entry then return end
    if dedupe then
        local prev = self._traceRows and self._traceRows[#self._traceRows]
        if prev and prev.op == entry.op and prev.where == entry.where
            and prev.detail == entry.detail and prev.ms == entry.ms then
            return
        end
    end
    entry.t = time()
    entry.count = 1
    if not ShouldRetainTraceRow(entry) then return end
    if not self._traceRows then self._traceRows = {} end

    local rows = self._traceRows
    local prev = rows[#rows]
    if prev and TraceRowsCoalesce(entry, prev) then
        if self._traceWindow and self._traceWindow:IsShown() then
            self:_ScheduleTraceTableSync(true)
        end
        return
    end

    tinsert(rows, entry)
    TrimTraceRows(rows)
    self._traceUINeedsFullRebuild = true
    if self._traceWindow and self._traceWindow:IsShown() then
        self:_ScheduleTraceTableSync(false)
    end
end

function Profiler:ClearTraceRows()
    if self._traceRows then wipe(self._traceRows) end
    self._traceUINeedsFullRebuild = true
    if self._traceWindow and self._traceWindow:IsShown() then
        self:_RebuildTraceTableUI()
    end
    if self._traceCopyFrame then self._traceCopyFrame:Hide() end
    if self._traceCopyEdit then self._traceCopyEdit:SetText("") end
end

local function FormatDetail(entry)
    local detail = entry.detail or ""
    if entry.count and entry.count > 1 then
        detail = detail .. " (x" .. tostring(entry.count) .. ")"
    end
    if #detail > 96 then
        detail = detail:sub(1, 93) .. "..."
    end
    return detail
end

local function ApplyEntryToRowFrame(row, entry)
    row.fsOp:SetText(OpColor(entry.kind) .. (entry.op or "-") .. C_R)
    row.fsWhere:SetText(C_DIM .. (entry.where or "-") .. C_R)
    row.fsDetail:SetText(C_INFO .. FormatDetail(entry) .. C_R)
    local ms = entry.ms
    row.fsMs:SetText(MsColor(ms) .. MsText(ms) .. C_R)
    if entry.kind == "error" or entry.op == "Error" then
        row.bg:SetColorTexture(0.35, 0.08, 0.08, 0.45)
    elseif entry.kind == "anomaly" or entry.op == "Frame" then
        row.bg:SetColorTexture(0.28, 0.18, 0.04, 0.35)
    elseif (ms or 0) >= (Profiler.TRACE_ANOMALY_MS or 16.67) then
        row.bg:SetColorTexture(0.22, 0.16, 0.04, 0.25)
    else
        row.bg:SetColorTexture(0, 0, 0, 0)
    end
end

function Profiler:_CreateTraceRowFrame(index, entry)
    local parent = self._traceContent
    if not parent then return nil end
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_HEIGHT)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
    row:SetPoint("RIGHT", parent, "RIGHT", 0, 0)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    row.bg = bg

    local fsOp = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fsOp:SetPoint("TOPLEFT", row, "TOPLEFT", PAD, -3)
    fsOp:SetWidth(COL_OP_W)
    fsOp:SetJustifyH("LEFT")
    fsOp:SetWordWrap(false)

    local fsWhere = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fsWhere:SetPoint("TOPLEFT", fsOp, "TOPRIGHT", PAD, 0)
    fsWhere:SetWidth(COL_WHERE_W)
    fsWhere:SetJustifyH("LEFT")
    fsWhere:SetWordWrap(false)

    local fsMs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fsMs:SetPoint("TOPRIGHT", row, "TOPRIGHT", -PAD, -3)
    fsMs:SetWidth(COL_MS_W)
    fsMs:SetJustifyH("RIGHT")
    fsMs:SetWordWrap(false)

    local fsDetail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fsDetail:SetPoint("TOPLEFT", fsWhere, "TOPRIGHT", PAD, 0)
    fsDetail:SetPoint("TOPRIGHT", fsMs, "TOPLEFT", -PAD, 0)
    fsDetail:SetJustifyH("LEFT")
    fsDetail:SetWordWrap(false)

    row.fsOp = fsOp
    row.fsWhere = fsWhere
    row.fsDetail = fsDetail
    row.fsMs = fsMs

    ApplyEntryToRowFrame(row, entry)
    return row
end

function Profiler:_ReleaseTraceRowFrames()
    if not self._traceRowFrames then return end
    for i = 1, #self._traceRowFrames do
        local row = self._traceRowFrames[i]
        if row then row:Hide(); row:SetParent(nil) end
    end
    wipe(self._traceRowFrames)
end

function Profiler:_RebuildTraceTableUI()
    local scroll = self._traceScroll
    local content = self._traceContent
    local emptyFs = self._traceEmptyLabel
    if not scroll or not content then return end

    local wasAtBottom = true
    if scroll.GetVerticalScrollRange and scroll.GetVerticalScroll then
        local range = scroll:GetVerticalScrollRange() or 0
        local pos = scroll:GetVerticalScroll() or 0
        wasAtBottom = range <= 4 or pos >= range - 8
    end

    self:_ReleaseTraceRowFrames()
    if not self._traceRowFrames then self._traceRowFrames = {} end

    local rows = self._traceRows or {}
    local n = #rows
    if emptyFs then
        if n == 0 then emptyFs:Show() else emptyFs:Hide() end
    end

    content:SetHeight(math.max(ROW_HEIGHT, n * ROW_HEIGHT))
    local sw = scroll:GetWidth()
    if sw and sw > 80 then content:SetWidth(sw - 8) end
    for i = 1, n do
        local row = self:_CreateTraceRowFrame(i, rows[i])
        self._traceRowFrames[i] = row
    end

    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
    if scroll.GetVerticalScrollRange and scroll.SetVerticalScroll then
        if self._traceFollowTail ~= false and wasAtBottom then
            local maxRange = scroll:GetVerticalScrollRange()
            if maxRange and maxRange > 0 then
                scroll:SetVerticalScroll(maxRange)
            end
        end
    end
    self._traceUINeedsFullRebuild = false
    self._traceUILastBuiltCount = n
end

function Profiler:_ScheduleTraceTableSync(coalesceOnly)
    if self._traceSyncPending then return end
    self._traceSyncPending = true
    C_Timer.After(0.05, function()
        self._traceSyncPending = false
        if not (self._traceWindow and self._traceWindow:IsShown()) then return end
        if coalesceOnly and not self._traceUINeedsFullRebuild then
            local rows = self._traceRows or {}
            local n = #rows
            local lastRow = self._traceRowFrames and self._traceRowFrames[n]
            if lastRow and rows[n] then
                ApplyEntryToRowFrame(lastRow, rows[n])
                if self._traceFollowTail ~= false and self._traceScroll then
                    local scroll = self._traceScroll
                    if scroll.GetVerticalScrollRange and scroll.SetVerticalScroll then
                        local maxRange = scroll:GetVerticalScrollRange()
                        if maxRange and maxRange > 0 then scroll:SetVerticalScroll(maxRange) end
                    end
                end
                return
            end
        end
        self:_RebuildTraceTableUI()
    end)
end

function Profiler:_SyncTraceEditBoxText()
    self:_RebuildTraceTableUI()
end

function Profiler:_BuildTraceCopyText()
    local rows = self._traceRows or {}
    if #rows == 0 then return "" end
    local lines = { "Operation\tWhere\tDetail\tms" }
    for i = 1, #rows do
        local e = rows[i]
        local detail = FormatDetail(e)
        lines[#lines + 1] = format(
            "%s\t%s\t%s\t%s",
            e.op or "",
            e.where or "",
            detail:gsub("\t", " "),
            e.ms and format("%.2f", e.ms) or ""
        )
    end
    return table.concat(lines, "\n")
end

function Profiler:EnsureTraceWindow()
    if self._traceWindow then return end

    local f = CreateFrame("Frame", "WarbandNexusProfilerTraceFrame", UIParent, "BackdropTemplate")
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(8100)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, tileSize = 0, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.08, 0.93)
    f:SetBackdropBorderColor(0.45, 0.2, 0.65, 1)
    f:SetSize(720, 440)
    f:SetPoint("CENTER", UIParent, "CENTER", 280, -40)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cff9370DBWN Profiler trace|r")

    local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOP", 0, -28)
    hint:SetText("|cff808080Slow ops (>=8ms), bag, zone, errors. Frame rows show likely cause in Detail.|r")

    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local followCheck = CreateFrame("CheckButton", nil, f, "ChatConfigCheckButtonTemplate")
    followCheck:SetPoint("TOPLEFT", 14, -46)
    followCheck.Text:SetText("Follow tail")
    followCheck:SetChecked(true)
    Profiler._traceFollowTail = true
    followCheck:SetScript("OnClick", function(self)
        Profiler._traceFollowTail = self:GetChecked() == true
        local root = GetPersistRoot()
        if root then root.traceFollowTail = Profiler._traceFollowTail end
    end)

    local copyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    copyBtn:SetSize(88, 22)
    copyBtn:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -88, -2)
    copyBtn:SetText("Copy TSV")
    local copyFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    copyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    copyFrame:SetFrameLevel(8200)
    copyFrame:SetSize(680, 220)
    copyFrame:SetPoint("CENTER", f, "CENTER")
    copyFrame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = false, tileSize = 0, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    copyFrame:SetBackdropColor(0.06, 0.06, 0.09, 0.97)
    copyFrame:SetBackdropBorderColor(0.45, 0.2, 0.65, 1)
    copyFrame:Hide()

    local copyTitle = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    copyTitle:SetPoint("TOP", 0, -10)
    copyTitle:SetText("|cff9370DBCopy trace (TSV)|r")

    local copyHint = copyFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    copyHint:SetPoint("TOP", 0, -26)
    copyHint:SetText("|cff808080Text is selected — press Ctrl+C, then Esc to close.|r")

    local copyClose = CreateFrame("Button", nil, copyFrame, "UIPanelCloseButton")
    copyClose:SetPoint("TOPRIGHT", -4, -4)
    copyClose:SetScript("OnClick", function() copyFrame:Hide() end)

    local copyScroll = CreateFrame("ScrollFrame", nil, copyFrame, "UIPanelScrollFrameTemplate")
    copyScroll:SetPoint("TOPLEFT", 12, -42)
    copyScroll:SetPoint("BOTTOMRIGHT", -28, 12)

    local copyEdit = CreateFrame("EditBox", nil, copyScroll)
    copyEdit:SetMultiLine(true)
    copyEdit:SetAutoFocus(false)
    copyEdit:SetMaxLetters(0)
    copyEdit:SetWidth(620)
    copyEdit:SetFontObject(ChatFontNormal)
    if ns.FontManager and ns.FontManager.RegisterManagedEditBox then
        ns.FontManager:RegisterManagedEditBox(copyEdit)
        if ns.FontManager.ApplyFontToEditBox then
            ns.FontManager:ApplyFontToEditBox(copyEdit)
        end
    end
    copyScroll:SetScrollChild(copyEdit)
    copyEdit:SetScript("OnEscapePressed", function() copyFrame:Hide() end)
    copyEdit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    copyEdit:SetScript("OnKeyDown", function(self, key)
        if key == "C" and IsControlKeyDown() then
            C_Timer.After(0.05, function() copyFrame:Hide() end)
        end
    end)

    copyBtn:SetScript("OnClick", function()
        local text = Profiler:_BuildTraceCopyText()
        if not text or text == "" then
            print(PREFIX .. C_WARN .. "Trace table is empty." .. C_R)
            return
        end
        copyEdit:SetText(text)
        local lineCount = 1
        for _ in text:gmatch("\n") do lineCount = lineCount + 1 end
        copyEdit:SetHeight(math.max(160, math.min(400, lineCount * 14 + 8)))
        if copyScroll.UpdateScrollChildRect then copyScroll:UpdateScrollChildRect() end
        copyFrame:Show()
        copyEdit:SetFocus()
        copyEdit:HighlightText()
        print(PREFIX .. C_DIM .. "Trace ready — press Ctrl+C to copy." .. C_R)
    end)

    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(70, 22)
    clearBtn:SetPoint("TOPRIGHT", copyBtn, "TOPLEFT", -6, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function() Profiler:ClearTraceRows() end)

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", followCheck, "BOTTOMLEFT", 0, -6)
    header:SetPoint("TOPRIGHT", -12, -68)
    header:SetHeight(20)
    local hBg = header:CreateTexture(nil, "BACKGROUND")
    hBg:SetAllPoints()
    hBg:SetColorTexture(0.15, 0.12, 0.22, 0.9)

    local hOp = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hOp:SetPoint("LEFT", header, "LEFT", PAD, 0)
    hOp:SetWidth(COL_OP_W)
    hOp:SetJustifyH("LEFT")
    hOp:SetText("|cffffd700Operation|r")

    local hWhere = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hWhere:SetPoint("LEFT", hOp, "RIGHT", PAD, 0)
    hWhere:SetWidth(COL_WHERE_W)
    hWhere:SetJustifyH("LEFT")
    hWhere:SetText("|cffffd700Where|r")

    local hMs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hMs:SetPoint("RIGHT", header, "RIGHT", -PAD, 0)
    hMs:SetWidth(COL_MS_W)
    hMs:SetJustifyH("RIGHT")
    hMs:SetText("|cffffd700ms|r")

    local hDetail = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hDetail:SetPoint("LEFT", hWhere, "RIGHT", PAD, 0)
    hDetail:SetPoint("RIGHT", hMs, "LEFT", -PAD, 0)
    hDetail:SetJustifyH("LEFT")
    hDetail:SetText("|cffffd700Detail|r")

    local scrollLaneReserve = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve())
        or ((ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26) + 2
    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", -scrollLaneReserve, 12)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(660)
    content:SetHeight(ROW_HEIGHT)
    scroll:SetScrollChild(content)

    local emptyFs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyFs:SetPoint("TOP", content, "TOP", 0, -28)
    emptyFs:SetWidth(620)
    emptyFs:SetJustifyH("CENTER")
    emptyFs:SetText("|cff808080No rows yet.|r\n|cff00ccff/wn profiler|r then loot, fly, or vendor.\nRows >=8ms, bag/zone events, and errors are kept.")
    self._traceEmptyLabel = emptyFs

    self._traceWindow = f
    self._traceScroll = scroll
    self._traceContent = content
    self._traceCopyFrame = copyFrame
    self._traceCopyEdit = copyEdit
    self._traceRowFrames = {}
    self._traceRows = self._traceRows or {}
    self._traceUINeedsFullRebuild = true
    self._traceFollowTail = true

    local root = GetPersistRoot()
    if root and root.traceFollowTail == false then
        self._traceFollowTail = false
        followCheck:SetChecked(false)
    end

    f:SetScript("OnShow", function()
        Profiler._traceUINeedsFullRebuild = true
        Profiler:_RebuildTraceTableUI()
    end)
    f:Hide()
end

function Profiler:ToggleTraceWindow()
    self:EnsureTraceWindow()
    local w = self._traceWindow
    if not w then return end
    if w:IsShown() then
        self:HideTraceWindow()
        print(PREFIX .. "Trace window hidden." .. C_R)
    else
        self:ShowTraceWindow()
        if not self.enabled then
            print(PREFIX .. C_WARN .. "Profiling OFF — run |cff00ccff/wn profiler|r to enable measuring." .. C_R)
        end
        print(PREFIX .. C_GOOD .. "Trace table shown." .. C_R)
    end
end
