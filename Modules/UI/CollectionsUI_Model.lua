--[[
    Warband Nexus - Collections tab (Model)
    Loaded via WarbandNexus.toc after CollectionsUI_Shared.lua.
]]

local _, ns = ...
local M = ns.CollectionsUI
assert(M and M.state, "CollectionsUI_Shared.lua must load before this file")

local WarbandNexus = M.WarbandNexus
local FontManager = M.FontManager
local Constants = M.Constants
local Utilities = M.Utilities
local issecretvalue = M.issecretvalue
local SafeLower = M.SafeLower
local CreateCard = M.CreateCard
local CreateEmptyStateCard = M.CreateEmptyStateCard
local HideEmptyStateCard = M.HideEmptyStateCard
local CreateThemedCheckbox = M.CreateThemedCheckbox
local PlanCardFactory = M.PlanCardFactory
local COLORS = M.COLORS
local ApplyVisuals = M.ApplyVisuals
local UpdateBorderColor = M.UpdateBorderColor
local CreateCollapsibleHeader = M.CreateCollapsibleHeader
local ChainSectionFrameBelow = M.ChainSectionFrameBelow
local CreateIcon = M.CreateIcon
local LAYOUT = M.LAYOUT
local SIDE_MARGIN = M.SIDE_MARGIN
local TOP_MARGIN = M.TOP_MARGIN
local CARD_GAP = M.CARD_GAP
local AFTER_ELEMENT = M.AFTER_ELEMENT
local ROW_ICON_SIZE = M.ROW_ICON_SIZE
local DETAIL_ICON_SIZE = M.DETAIL_ICON_SIZE
local STATUS_ICON_SIZE = M.STATUS_ICON_SIZE
local SCROLL_CONTENT_TOP_PADDING = M.SCROLL_CONTENT_TOP_PADDING
local CONTENT_INSET = M.CONTENT_INSET
local CONTAINER_INSET = M.CONTAINER_INSET
local TEXT_GAP = M.TEXT_GAP
local SEARCH_ROW_HEIGHT = M.SEARCH_ROW_HEIGHT
local COLLECTIONS_TITLE_CARD_HEIGHT = M.COLLECTIONS_TITLE_CARD_HEIGHT
local RECENT_SECTION_ORDER = M.RECENT_SECTION_ORDER
local RECENT_CARD_ICON = M.RECENT_CARD_ICON
local RECENT_CARD_HEADER_PAD = M.RECENT_CARD_HEADER_PAD
local RECENT_ROW_ICON_BORDER_ALPHA = M.RECENT_ROW_ICON_BORDER_ALPHA
local RECENT_CARD_MIN_WIDTH = M.RECENT_CARD_MIN_WIDTH
local SUBTAB_BAR_HEIGHT = M.SUBTAB_BAR_HEIGHT
local PROGRESS_ROW_HEIGHT = M.PROGRESS_ROW_HEIGHT
local BAR_INSET = M.BAR_INSET
local SD = M.SD
local Factory = M.Factory
local PADDING = M.PADDING
local SCROLLBAR_GAP = M.SCROLLBAR_GAP
local SCROLLBAR_SIDE_GAP = M.SCROLLBAR_SIDE_GAP
local COLLECTION_HEAVY_DELAY = M.COLLECTION_HEAVY_DELAY
local RUN_CHUNK_SIZE = M.RUN_CHUNK_SIZE
local ROW_HEIGHT = M.ROW_HEIGHT
local ROW_GAP = M.ROW_GAP
local ROW_STRIDE = M.ROW_STRIDE
local COLLAPSE_HEADER_HEIGHT_COLL = M.COLLAPSE_HEADER_HEIGHT_COLL
local COLLECTION_LIST_DETAIL_SPLIT = M.COLLECTION_LIST_DETAIL_SPLIT
local DETAIL_SCROLLBAR_VERTICAL_INSET = M.DETAIL_SCROLLBAR_VERTICAL_INSET
local BORDER_INSET = M.BORDER_INSET
local VALID_COLLECTIONS_SUBTABS = M.VALID_COLLECTIONS_SUBTABS
local collectionsState = M.state
local format = string.format
local time = time
local date = date
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local tremove = table.remove
local wipe = table.wipe

-- Model viewer layout / camera (were file-level locals before CollectionsUI split).
local FIXED_CAM_SCALE = 1.8
local CAM_SCALE_MIN = 0.6
local CAM_SCALE_MAX = 6
local ZOOM_STEP = 0.1
local ROTATE_SENSITIVITY = 0.02
local REFERENCE_RADIUS = 0.86
local FIXED_CAM_DISTANCE = 3.55
local MODEL_VIEWER_CAMERA_FIT_PADDING = 1.60
local MODEL_VIEWPORT_TOP_GAP = 6
local MOUNT_VIEWPORT_NUDGE_UP = 6
local MODEL_VIEWPORT_INSET = 2
local MODEL_PREVIEW_MAX_HEIGHT_PER_WIDTH = 0.62
local MOUNT_JOURNAL_SCENE_BASE_DISTANCE_MULT = 1.04
local MOUNT_JOURNAL_SCENE_VIEW_TRANSLATE_Y = 14
local MODEL_SCALE_MIN = 0.15
local MODEL_SCALE_MAX = 6.0
local ZOOM_MULTIPLIER_MIN = 0.5
local ZOOM_MULTIPLIER_MAX = 2.0
local PET_MODEL_VERTICAL_OFFSET = 0.12
local MOUNT_PLAYERMODEL_FALLBACK_Y_OFFSET = 0.16

function M.Collections_LoadBlizzardCollections()
    if Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Blizzard_Collections")
    end
end

function M.Collections_SanitizeMountExtra(v, default)
    if v == nil then return default end
    if issecretvalue and issecretvalue(v) then return default end
    return v
end

function M.ApplyJournalModelSceneZoom(scene, zoomMultiplier)
    if not scene then return end
    local mul = MOUNT_JOURNAL_SCENE_BASE_DISTANCE_MULT * (zoomMultiplier or 1.0)
    if scene.SetCameraDistanceScale then
        pcall(scene.SetCameraDistanceScale, scene, mul)
    end
    if scene.SetCamDistanceScale then
        pcall(scene.SetCamDistanceScale, scene, mul)
    end
    -- Mount Journal: önizleme biraz yukarıda; aksi halde binek+binici frame altında kalıyor
    if scene.SetViewTranslation then
        pcall(scene.SetViewTranslation, scene, 0, MOUNT_JOURNAL_SCENE_VIEW_TRANSLATE_Y)
    end
end

--- Same pipeline as MountJournal_UpdateMountDisplay (ModelScene path). Returns true if scene was updated.
function M.ApplyMountJournalModelSceneDisplay(scene, mountID, creatureDisplayIDFromCache, forceSceneChange)
    if not scene or not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoExtraByID then
        return false
    end
    local creatureDisplayID, _desc, _src, isSelfMount, _, modelSceneID, animID, spellVisualKitID, disablePlayerMountPreview =
        C_MountJournal.GetMountInfoExtraByID(mountID)
    creatureDisplayID = M.Collections_SanitizeMountExtra(creatureDisplayID, nil)
    isSelfMount = M.Collections_SanitizeMountExtra(isSelfMount, false) == true
    modelSceneID = M.Collections_SanitizeMountExtra(modelSceneID, nil)
    animID = M.Collections_SanitizeMountExtra(animID, nil)
    spellVisualKitID = M.Collections_SanitizeMountExtra(spellVisualKitID, nil)
    disablePlayerMountPreview = M.Collections_SanitizeMountExtra(disablePlayerMountPreview, true) == true

    if not creatureDisplayID or creatureDisplayID <= 0 then
        creatureDisplayID = creatureDisplayIDFromCache
    end
    if (not creatureDisplayID or creatureDisplayID <= 0) and C_MountJournal.GetMountAllCreatureDisplayInfoByID then
        local all = C_MountJournal.GetMountAllCreatureDisplayInfoByID(mountID)
        if all and #all > 0 and all[1] and type(all[1].creatureDisplayID) == "number" then
            creatureDisplayID = all[1].creatureDisplayID
        end
    end
    if not creatureDisplayID or creatureDisplayID <= 0 then
        return false
    end

    local needsFanfare = false
    if C_MountJournal.NeedsFanfare then
        local nf = C_MountJournal.NeedsFanfare(mountID)
        if not (issecretvalue and nf and issecretvalue(nf)) then
            needsFanfare = nf == true
        end
    end

    local trans = _G.CAMERA_TRANSITION_TYPE_IMMEDIATE
    local disc = _G.CAMERA_MODIFICATION_TYPE_DISCARD
    if forceSceneChange and type(modelSceneID) == "number" and modelSceneID > 0 and trans and disc and scene.TransitionToModelSceneID then
        pcall(scene.TransitionToModelSceneID, scene, modelSceneID, trans, disc, true)
    end

    if scene.PrepareForFanfare then
        pcall(scene.PrepareForFanfare, scene, needsFanfare)
    end

    local mountActor = scene.GetActorByTag and scene:GetActorByTag("unwrapped")
    if not mountActor then
        return false
    end

    mountActor:Hide()
    if mountActor.SetOnModelLoadedCallback then
        mountActor:SetOnModelLoadedCallback(function()
            mountActor:Show()
        end)
    else
        mountActor:Show()
    end
    if mountActor.SetModelByCreatureDisplayID then
        local okSet = pcall(mountActor.SetModelByCreatureDisplayID, mountActor, creatureDisplayID, true)
        if not okSet then
            return false
        end
    else
        return false
    end

    local blend = Enum and Enum.ModelBlendOperation
    if isSelfMount and blend then
        if mountActor.SetAnimationBlendOperation then
            pcall(mountActor.SetAnimationBlendOperation, mountActor, blend.None)
        end
        if mountActor.SetAnimation then
            pcall(mountActor.SetAnimation, mountActor, 618)
        end
    else
        if mountActor.SetAnimationBlendOperation and blend then
            pcall(mountActor.SetAnimationBlendOperation, mountActor, blend.Anim)
        end
        if mountActor.SetAnimation then
            pcall(mountActor.SetAnimation, mountActor, 0)
        end
    end

    local showPlayer = false
    if GetCVarBool then
        local okCv, cv = pcall(GetCVarBool, "mountJournalShowPlayer")
        if okCv then showPlayer = cv end
    end
    local disablePreview = disablePlayerMountPreview
    if not disablePreview and not showPlayer then
        disablePreview = true
    end

    local useNativeForm = false
    if PlayerUtil and PlayerUtil.ShouldUseNativeFormInModelScene then
        local okN, n = pcall(PlayerUtil.ShouldUseNativeFormInModelScene)
        if okN then useNativeForm = n end
    end

    if scene.AttachPlayerToMount then
        pcall(scene.AttachPlayerToMount, scene, mountActor, animID, isSelfMount, disablePreview, spellVisualKitID, useNativeForm)
    end

    scene:Show()
    return true
end

-- Fallback when Journal ModelScene is unavailable: PlayerModel + cinematic scene ID (approximate).
function M.TryApplyMountJournalModelScene(pm, panel_)
    if not pm or not panel_ or not panel_._lastMountID then return false end
    local sid = panel_._mountUiModelSceneID
    if type(sid) ~= "number" or sid <= 0 then return false end
    if pm.ApplyUICinematicCamera then
        local ok = pcall(pm.ApplyUICinematicCamera, pm, sid)
        if ok then return true end
    end
    if pm.TransitionToModelSceneID then
        local ok = pcall(pm.TransitionToModelSceneID, pm, sid)
        if ok then return true end
    end
    return false
end

-- Largest sensible bounding radius for framing. GetModelRadius alone under-reports some flying mounts
-- (wings above the sphere); GetBoundingRadius (when present) often closer to visible extent — use max().
function M.GetEffectiveModelBoundingRadius(m)
    if not m then return nil end
    local best = nil
    if m.GetModelRadius then
        local ok, r = pcall(m.GetModelRadius, m)
        if ok and type(r) == "number" and r > 0 then best = r end
    end
    if m.GetBoundingRadius then
        local ok, r = pcall(m.GetBoundingRadius, m)
        if ok and type(r) == "number" and r > 0 then
            best = best and math.max(best, r) or r
        end
    end
    return best
end

-- Mount API helpers — CreateModelViewer closure'ları bunlara ihtiyaç duyduğu için burada tanımlı.
function M.SafeGetMountCollected(mountID)
    if not C_MountJournal or not C_MountJournal.GetMountInfoByID then return false end
    local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
    if issecretvalue and collected and issecretvalue(collected) then
        return false
    end
    return collected == true
end

function M.SafeGetMountInfoExtra(mountID)
    if not mountID or not C_MountJournal or not C_MountJournal.GetMountInfoExtraByID then
        return nil, "", "", nil
    end
    local displayID, description, source, _, _, uiModelSceneID = C_MountJournal.GetMountInfoExtraByID(mountID)
    if issecretvalue and displayID and issecretvalue(displayID) then displayID = nil end
    if issecretvalue and description and issecretvalue(description) then description = "" end
    if issecretvalue and source and issecretvalue(source) then source = "" end
    if issecretvalue and uiModelSceneID and issecretvalue(uiModelSceneID) then uiModelSceneID = nil end
    return displayID, description or "", source or "", uiModelSceneID
end

-- Pet API helpers — same pattern as mounts.
function M.SafeGetPetCollected(speciesID)
    if not C_PetJournal or not C_PetJournal.GetNumCollectedInfo then return false end
    local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
    if issecretvalue and numCollected and issecretvalue(numCollected) then
        return false
    end
    return numCollected and numCollected > 0
end

function M.SafeGetPetInfoExtra(speciesID)
    if not speciesID or not C_PetJournal then return nil, "", "" end
    local creatureDisplayID = nil
    if C_PetJournal.GetNumDisplays and C_PetJournal.GetDisplayIDByIndex then
        local numDisplays = C_PetJournal.GetNumDisplays(speciesID) or 0
        if numDisplays > 0 then
            creatureDisplayID = C_PetJournal.GetDisplayIDByIndex(speciesID, 1)
        end
    end
    if issecretvalue and creatureDisplayID and issecretvalue(creatureDisplayID) then creatureDisplayID = nil end
    local name, icon, _, _, source, description = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
    if issecretvalue and source and issecretvalue(source) then source = "" end
    if issecretvalue and description and issecretvalue(description) then description = "" end
    return creatureDisplayID, description or "", source or ""
end

--- Collections detail header: Plan (todo) icon — yellow when on To-Do, white when idle, grey when collected (list row parity).
function M.RefreshCollectionsDetailPlanButton(addBtn, collected, planned, onClick)
    if not addBtn then return end
    local Factory = ns.UI and ns.UI.Factory
    if Factory and Factory.ApplyIconOnlyButtonChrome then
        Factory:ApplyIconOnlyButtonChrome(addBtn)
    end
    local onTodo = planned == true
    local disabled = collected == true
    if addBtn._wnAddPlusText then
        addBtn._wnAddPlusText:SetShown(not onTodo and not disabled)
    end
    local iconTex = addBtn._wnIconTex
    if iconTex then
        if ns.UI_ApplyWnActionIcon then
            ns.UI_ApplyWnActionIcon(iconTex, "todo", onTodo, disabled)
        elseif ns.UI_SetWnIconTexture then
            ns.UI_SetWnIconTexture(iconTex, "todo", {
                desaturate = disabled,
                vertexColor = ns.UI_WnIconVertexForKey and ns.UI_WnIconVertexForKey("todo", onTodo, disabled)
                    or (ns.WN_ICON_VERTEX_WHITE or { 1, 1, 1, 1 }),
            })
        end
        iconTex:Show()
    end
    addBtn:Show()
    addBtn:SetAlpha(1)
    local L = ns.L
    local todoTitle = (L and L["COLLECTIONS_TT_TODO_TITLE"]) or "To-Do list"
    if onTodo then
        addBtn:EnableMouse(true)
        addBtn:RegisterForClicks()
        local body = (L and L["COLLECTIONS_DETAIL_TT_ON_TODO"]) or "Left-click to remove from your To-Do list."
        addBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:SetText(todoTitle, 1, 1, 1)
            GameTooltip:AddLine(body, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        addBtn:SetScript("OnClick", nil)
    elseif disabled then
        addBtn:EnableMouse(false)
        addBtn:RegisterForClicks()
        addBtn:SetScript("OnEnter", nil)
        addBtn:SetScript("OnLeave", nil)
        addBtn:SetScript("OnClick", nil)
    else
        local body = (L and L["COLLECTIONS_DETAIL_TT_ADD_TODO"]) or "Left-click to add to your To-Do list."
        addBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:ClearLines()
            GameTooltip:SetText(todoTitle, 1, 1, 1)
            GameTooltip:AddLine(body, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        addBtn:EnableMouse(true)
        addBtn:RegisterForClicks("LeftButtonUp")
        if onClick then
            addBtn:SetScript("OnClick", function(_, button)
                if button == "LeftButton" then onClick() end
            end)
        else
            addBtn:SetScript("OnClick", nil)
        end
    end
end

--- Plan (To-Do) control for mount/pet/toy detail headers — bordered shell + inner icon button.
function M.CreateCollectionsDetailPlanButton(actionSlot)
    if not actionSlot or not PlanCardFactory then return nil end
    local CDH = ns.CollectionsDetailHeaderLayout or {}
    local sz = CDH.DETAIL_ACTION_SIZE or 28
    local inner = math.max(12, sz - 4)
    local shell = Factory.CreateCollectionsDetailIconShell and Factory:CreateCollectionsDetailIconShell(actionSlot, sz)
    if not shell then
        return PlanCardFactory.CreateAddButton(actionSlot, {
            buttonType = "row",
            iconOnly = true,
            width = sz,
            height = sz,
            anchorPoint = "TOPRIGHT",
            x = 0,
            y = 0,
        })
    end
    shell:SetPoint("TOPRIGHT", actionSlot, "TOPRIGHT", 0, 0)
    local addBtn = PlanCardFactory.CreateAddButton(shell, {
        buttonType = "row",
        iconOnly = true,
        width = inner,
        height = inner,
        anchorPoint = "CENTER",
        x = 0,
        y = 0,
    })
    if addBtn and Factory.CenterCollectionsDetailActionButton then
        Factory:CenterCollectionsDetailActionButton(shell, addBtn)
    end
    return addBtn
end

function M.CreateModelViewer(parent, width, height)
    local panel = Factory:CreateContainer(parent, width, height, false)
    if not panel then return nil end
    panel:SetSize(width, height)
    M.ApplyDetailAccentVisuals(panel)

    -- Slot: full width from desc bottom to panel bottom; viewport inside is height-capped and vertically centered.
    local modelViewportSlot = Factory:CreateContainer(panel, math.max(1, width), math.max(1, height), false)
    if not modelViewportSlot then
        modelViewportSlot = CreateFrame("Frame", nil, panel)
    end
    modelViewportSlot:SetFrameLevel(panel:GetFrameLevel() + 1)
    panel.modelViewportSlot = modelViewportSlot

    -- Model stage: plain Frame with SetClipsChildren (ScriptRegion child tree); PlayerModel draws past bounds — clip here.
    local modelViewport = Factory:CreateContainer(modelViewportSlot, math.max(1, width), math.max(1, height), false)
    if not modelViewport then
        modelViewport = CreateFrame("Frame", nil, modelViewportSlot)
    end
    modelViewport:SetFrameLevel(modelViewportSlot:GetFrameLevel() + 1)
    if modelViewport.SetClipsChildren then
        modelViewport:SetClipsChildren(true)
    end
    panel.modelViewport = modelViewport

    -- Widget type Model / PlayerModel — see Widget API; mouse off on model, hits on interactionLayer (ScriptRegion).
    local model = CreateFrame("PlayerModel", nil, modelViewport)
    model:SetModelDrawLayer("ARTWORK")
    model:SetFrameLevel(modelViewport:GetFrameLevel())
    model:EnableMouse(false)
    model:EnableMouseWheel(false)

    local function ApplyModelToViewportInsets()
        local inset = MODEL_VIEWPORT_INSET
        model:ClearAllPoints()
        model:SetPoint("TOPLEFT", modelViewport, "TOPLEFT", inset, -inset)
        model:SetPoint("BOTTOMRIGHT", modelViewport, "BOTTOMRIGHT", -inset, inset)
        local js = panel._journalMountScene
        if js then
            js:ClearAllPoints()
            js:SetPoint("TOPLEFT", modelViewport, "TOPLEFT", inset, -inset)
            js:SetPoint("BOTTOMRIGHT", modelViewport, "BOTTOMRIGHT", -inset, inset)
        end
    end

    -- Journal-quality mount preview: same ModelScene template as Mount Journal (Blizzard_Collections).
    local function TryInitJournalMountModelScene()
        if panel._journalMountScene then return panel._journalMountScene end
        if panel._journalMountSceneFailed then return nil end
        M.Collections_LoadBlizzardCollections()
        local ok, scene = pcall(CreateFrame, "ModelScene", nil, modelViewport, "WrappedAndUnwrappedModelScene")
        if not ok or not scene then
            panel._journalMountSceneFailed = true
            return nil
        end
        panel._journalMountScene = scene
        scene:SetFrameLevel(model:GetFrameLevel() + 2)
        if scene.SetResetCallback then
            scene:SetResetCallback(function()
                if panel._lastMountID and panel._mountDisplayUsesJournalScene and panel._journalMountScene then
                    M.ApplyMountJournalModelSceneDisplay(panel._journalMountScene, panel._lastMountID, panel._lastCreatureDisplayID, true)
                    M.ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
                end
            end)
        end
        if scene.ControlFrame and scene.ControlFrame.SetModelScene then
            pcall(scene.ControlFrame.SetModelScene, scene.ControlFrame, scene)
        end
        scene:Hide()
        ApplyModelToViewportInsets()
        return scene
    end

    -- Defined before interactionLayer exists; use panel._interactionLayer at call time (not local interactionLayer — scope).
    local function ShowPlayerModelPath(show)
        local il = panel._interactionLayer
        if show then
            model:Show()
            if il then il:Show() end
        else
            model:Hide()
            if il then il:Hide() end
        end
    end

    -- Layout: slot from descText bottom (or fallback) to panel bottom; viewport height capped vs width and centered in slot.
    local MODEL_FALLBACK_TOP_RATIO = 0.36
    local function UpdateModelFrameSize()
        local w = panel:GetWidth()
        local h = panel:GetHeight()
        if not w or not h or w < 1 or h < 1 then return end
        local slot = panel.modelViewportSlot
        if not slot then return end
        slot:ClearAllPoints()
        if panel.descText and panel.descText:IsShown() then
            slot:SetPoint("TOPLEFT", panel.descText, "BOTTOMLEFT", 0, -MODEL_VIEWPORT_TOP_GAP)
            slot:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
        else
            slot:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_INSET, -h * MODEL_FALLBACK_TOP_RATIO)
            slot:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
        end
        local sw = slot:GetWidth()
        local sh = slot:GetHeight()
        if not sw or sw < 1 then sw = math.max(1, w - 2 * CONTENT_INSET) end
        if not sh or sh < 2 then sh = math.max(2, h * (1 - MODEL_FALLBACK_TOP_RATIO)) end
        -- Mount: tüm slot yüksekliğini model için kullan (Blizzard Mount Journal; 0.62 tavan büyük üst/alt siyah bant yaratıyordu).
        local isMountView = panel._lastMountID and (not panel._lastPetID)
        local maxH = sw * MODEL_PREVIEW_MAX_HEIGHT_PER_WIDTH
        local vh = isMountView and sh or math.min(sh, maxH)
        local totalVPad = math.max(0, sh - vh)
        local vCenter = totalVPad * 0.5
        local nudgeUp = isMountView and MOUNT_VIEWPORT_NUDGE_UP or 0
        nudgeUp = math.min(nudgeUp, vCenter)
        local vPadTop = math.max(0, vCenter - nudgeUp)
        local vPadBottom = totalVPad - vPadTop
        modelViewport:ClearAllPoints()
        modelViewport:SetPoint("LEFT", slot, "LEFT", 0, 0)
        modelViewport:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
        modelViewport:SetPoint("TOP", slot, "TOP", 0, -vPadTop)
        modelViewport:SetPoint("BOTTOM", slot, "BOTTOM", 0, vPadBottom)
        ApplyModelToViewportInsets()
    end
    panel.UpdateModelFrameSize = UpdateModelFrameSize
    panel:SetScript("OnSizeChanged", function()
        UpdateModelFrameSize()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() UpdateModelFrameSize() end)
        end
    end)

    panel.modelRotation = 0
    panel.camScale = FIXED_CAM_SCALE
    panel.normalizedRadius = false
    panel.modelScale = 1.0
    panel.zoomMultiplier = 1.0
    panel._dragButton = nil

    -- Transparent layer above PlayerModel: reliable hit-testing for wheel + drag (journal-style: right-drag rotate; left-drag also supported).
    local interactionLayer = Factory:CreateContainer(modelViewport, math.max(1, width), math.max(1, height), false)
    if not interactionLayer then
        interactionLayer = CreateFrame("Frame", nil, modelViewport)
    end
    interactionLayer:SetAllPoints()
    interactionLayer:SetFrameLevel(model:GetFrameLevel() + 20)
    interactionLayer:EnableMouse(true)
    interactionLayer:EnableMouseWheel(true)
    panel._interactionLayer = interactionLayer

    -- Centered preview: UseModelCenterToTransform + optional pet vertical nudge; idle pose + zero pitch for consistency.
    local function ApplyTransform()
        if panel._mountDisplayUsesJournalScene and panel._journalMountScene then
            M.ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
            return
        end
        if panel._usesJournalCamera and panel._lastMountID then
            model:SetPosition(0, 0, 0)
            if model.UseModelCenterToTransform then model:UseModelCenterToTransform(true) end
            if model.SetPitch then pcall(model.SetPitch, model, 0) end
            model:SetFacing(panel.modelRotation)
            if model.SetPortraitZoom then model:SetPortraitZoom(0) end
            if model.SetCamDistanceScale then
                model:SetCamDistanceScale(FIXED_CAM_SCALE * panel.zoomMultiplier)
            end
            if model.SetViewTranslation then model:SetViewTranslation(0, 0) end
            return
        end
        local yOff = 0
        if panel._lastPetID and not panel._lastMountID then
            yOff = PET_MODEL_VERTICAL_OFFSET
        elseif panel._lastMountID and (not panel._lastPetID) and (not panel._mountDisplayUsesJournalScene) then
            yOff = MOUNT_PLAYERMODEL_FALLBACK_Y_OFFSET
        end
        model:SetPosition(0, yOff, 0)
        if model.UseModelCenterToTransform then model:UseModelCenterToTransform(true) end
        if model.SetPitch then pcall(model.SetPitch, model, 0) end
        model:SetFacing(panel.modelRotation)
        if model.SetPortraitZoom then model:SetPortraitZoom(0) end
        if panel.normalizedRadius then
            if model.SetModelScale then model:SetModelScale(panel.modelScale) end
            if model.SetCameraDistance then
                local vw, vh = modelViewport:GetWidth(), modelViewport:GetHeight()
                local aspectPad = 1.0
                if vw and vh and vw > 1 and vh > 1 then
                    local ratio = vw / vh
                    if ratio > 1.12 then
                        -- Wide preview: tall mounts (banners, wings) clip vertically — pull camera back
                        -- proportionally to the aspect ratio so they fit.
                        aspectPad = math.min(1.45, 1.0 + (ratio - 1.0) * 0.35)
                    elseif ratio < 0.85 then
                        -- Tall preview: wide mounts clip horizontally — same logic, mirrored.
                        aspectPad = math.min(1.45, 1.0 + (1.0 / ratio - 1.0) * 0.35)
                    end
                end
                local camDist = FIXED_CAM_DISTANCE
                    * MODEL_VIEWER_CAMERA_FIT_PADDING
                    * aspectPad
                    * panel.zoomMultiplier
                    * panel.modelScale
                local ok = pcall(model.SetCameraDistance, model, math.max(0.1, camDist))
                if not ok and model.SetCamDistanceScale then
                    model:SetCamDistanceScale(panel.camScale)
                end
            end
        else
            if model.SetCamDistanceScale then model:SetCamDistanceScale(panel.camScale) end
        end
        if model.SetViewTranslation then model:SetViewTranslation(0, 0) end
    end

    local function ScheduleJournalSceneAfterMount(midLock)
        if not midLock then return end
        local function tryOnce()
            if panel._lastMountID ~= midLock then return end
            if M.TryApplyMountJournalModelScene(model, panel) then
                panel._usesJournalCamera = true
                panel.zoomMultiplier = 1.0
                ApplyTransform()
            end
        end
        C_Timer.After(0, tryOnce)
        C_Timer.After(0.1, tryOnce)
    end

    -- Model script OnModelLoaded (Widget script handlers): radius APIs often valid here; complements deferred retries.
    local function TryApplyBoundingRadiusNormalize(lockMountID, lockCreatureID)
        if panel._usesJournalCamera then return false end
        if lockMountID and panel._lastMountID ~= lockMountID then return false end
        if lockCreatureID and lockCreatureID > 0 and panel._lastCreatureDisplayID ~= lockCreatureID then return false end
        local r = M.GetEffectiveModelBoundingRadius(model)
        if not r or r <= 0 or not model.SetModelScale or not model.SetCameraDistance then return false end
        local scale = (REFERENCE_RADIUS / r) * 0.94
        if scale < MODEL_SCALE_MIN then scale = MODEL_SCALE_MIN elseif scale > MODEL_SCALE_MAX then scale = MODEL_SCALE_MAX end
        panel.normalizedRadius = true
        panel.modelScale = scale
        ApplyTransform()
        return true
    end

    local FRAMING_RETRY_DELAYS = { 0, 0.06, 0.14, 0.30, 0.60 }
    local function ScheduleBoundingRadiusRetries(lockMountID, lockCreatureID)
        for i = 1, #FRAMING_RETRY_DELAYS do
            local delay = FRAMING_RETRY_DELAYS[i]
            C_Timer.After(delay, function()
                TryApplyBoundingRadiusNormalize(lockMountID, lockCreatureID)
            end)
        end
    end

    model:SetScript("OnModelLoaded", function()
        TryApplyBoundingRadiusNormalize(panel._lastMountID, panel._lastCreatureDisplayID)
        ApplyTransform()
    end)

    local function InteractionEffectiveScale()
        local s = interactionLayer:GetEffectiveScale()
        if s and s > 0 then return s end
        return model:GetEffectiveScale() or 1
    end

    local function interactionDragOnUpdate()
        if panel._dragCursorX == nil or not panel._dragButton then
            interactionLayer:SetScript("OnUpdate", nil)
            return
        end
        if not IsMouseButtonDown(panel._dragButton) then
            panel._dragCursorX = nil
            panel._dragButton = nil
            interactionLayer:SetScript("OnUpdate", nil)
            return
        end
        local x = GetCursorPosition()
        local s = InteractionEffectiveScale()
        if s > 0 then x = x / s end
        local dx = x - panel._dragCursorX
        panel._dragCursorX = x
        panel.modelRotation = (panel._dragRotation or 0) - dx * ROTATE_SENSITIVITY
        panel._dragRotation = panel.modelRotation
        model:SetFacing(panel.modelRotation)
        ApplyTransform()
    end

    interactionLayer:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" and button ~= "RightButton" then return end
        local x = GetCursorPosition()
        local s = InteractionEffectiveScale()
        if s > 0 then x = x / s end
        panel._dragCursorX = x
        panel._dragRotation = panel.modelRotation
        panel._dragButton = button
        interactionLayer:SetScript("OnUpdate", interactionDragOnUpdate)
    end)
    interactionLayer:SetScript("OnMouseUp", function(_, button)
        if button == panel._dragButton then
            panel._dragCursorX = nil
            panel._dragButton = nil
        end
        interactionLayer:SetScript("OnUpdate", nil)
    end)
    interactionLayer:SetScript("OnHide", function()
        panel._dragCursorX = nil
        panel._dragButton = nil
        interactionLayer:SetScript("OnUpdate", nil)
    end)
    interactionLayer:SetScript("OnMouseWheel", function(_, delta)
        if panel._mountDisplayUsesJournalScene and panel._journalMountScene then
            local m = panel.zoomMultiplier * (delta > 0 and 0.9 or 1.1)
            if m < ZOOM_MULTIPLIER_MIN then m = ZOOM_MULTIPLIER_MIN elseif m > ZOOM_MULTIPLIER_MAX then m = ZOOM_MULTIPLIER_MAX end
            panel.zoomMultiplier = m
            M.ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
            return
        end
        if panel._usesJournalCamera then
            local m = panel.zoomMultiplier * (delta > 0 and 0.9 or 1.1)
            if m < ZOOM_MULTIPLIER_MIN then m = ZOOM_MULTIPLIER_MIN elseif m > ZOOM_MULTIPLIER_MAX then m = ZOOM_MULTIPLIER_MAX end
            panel.zoomMultiplier = m
            ApplyTransform()
            return
        end
        if panel.normalizedRadius then
            local m = panel.zoomMultiplier * (delta > 0 and 0.9 or 1.1)
            if m < ZOOM_MULTIPLIER_MIN then m = ZOOM_MULTIPLIER_MIN elseif m > ZOOM_MULTIPLIER_MAX then m = ZOOM_MULTIPLIER_MAX end
            panel.zoomMultiplier = m
        else
            local v = panel.camScale + (delta > 0 and -ZOOM_STEP or ZOOM_STEP)
            if v < CAM_SCALE_MIN then v = CAM_SCALE_MIN elseif v > CAM_SCALE_MAX then v = CAM_SCALE_MAX end
            panel.camScale = v
        end
        ApplyTransform()
    end)

    -- Text on top of model: overlay frame with higher frame level so text is always in front.
    local textOverlay = Factory:CreateContainer(panel, math.max(1, width), math.max(1, height), false)
    if not textOverlay then
        textOverlay = CreateFrame("Frame", nil, panel)
    end
    textOverlay:SetFrameLevel(panel:GetFrameLevel() + 10)
    textOverlay:SetAllPoints(panel)
    textOverlay:EnableMouse(false)
    panel.textOverlay = textOverlay

    local DETAIL_HEADER_GAP = 10
    local collectionsDetailIcon = math.floor((DETAIL_ICON_SIZE or 64) * 1.14)
    -- Detail icon with border (Factory CreateContainer + accent override)
    local iconBorder = Factory:CreateContainer(textOverlay, collectionsDetailIcon, collectionsDetailIcon, true)
    iconBorder:SetPoint("TOPLEFT", textOverlay, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
    if ApplyVisuals then
        ApplyVisuals(iconBorder, {0.12, 0.12, 0.14, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.7})
    end
    if iconBorder.EnableMouse then iconBorder:EnableMouse(false) end
    panel.detailIconBorder = iconBorder
    local iconTex = iconBorder:CreateTexture(nil, "OVERLAY")
    iconTex:SetAllPoints()
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel.detailIconTexture = iconTex

    local goldR = (COLORS.gold and COLORS.gold[1]) or 1
    local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
    local goldB = (COLORS.gold and COLORS.gold[3]) or 0
    local whiteR, whiteG, whiteB = 1, 1, 1

    -- Sağ üst: Factory sütunu — Wowhead + Add/Added; try satırı yalnızca Add sütunu genişliğinde (hizalı).
    local addCol = Factory.CreateCollectionsDetailRightColumn and Factory:CreateCollectionsDetailRightColumn(textOverlay, { withTryRow = true })
    local addContainer = addCol and addCol.root
    local actionSlot = addCol and addCol.actionSlot
    if addContainer then
        addContainer:SetPoint("TOPRIGHT", textOverlay, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        addContainer:Hide()
    end
    panel._addContainer = addContainer
    panel._detailActionSlot = actionSlot

    if actionSlot then
        panel._addBtn = M.CreateCollectionsDetailPlanButton(actionSlot)
    end

    panel._wowheadBtn = addCol and addCol.wowheadBtn
    panel._tryCountRow = addCol and addCol.tryCountRow

    local nameText = FontManager:CreateFontString(textOverlay, "header", "OVERLAY")
    do
        local fp, fsz, flg = nameText:GetFont()
        if type(fsz) == "number" and fp and flg then
            pcall(nameText.SetFont, nameText, fp, fsz + 2, flg)
        end
    end
    nameText:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
    if addContainer then
        nameText:SetPoint("TOPRIGHT", addContainer, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
    else
        nameText:SetPoint("TOPRIGHT", textOverlay, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
    end
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(true)
    nameText:SetTextColor(whiteR, whiteG, whiteB)
    panel.nameText = nameText

    local headerRowBottom = Factory:CreateContainer(textOverlay, math.max(1, width), 1, false)
    if not headerRowBottom then
        headerRowBottom = CreateFrame("Frame", nil, textOverlay)
        headerRowBottom:SetHeight(1)
    end
    headerRowBottom:SetPoint("TOPLEFT", iconBorder, "BOTTOMLEFT", 0, 0)
    headerRowBottom:SetPoint("TOPRIGHT", nameText, "BOTTOMRIGHT", 0, 0)
    if headerRowBottom.EnableMouse then headerRowBottom:EnableMouse(false) end
    panel.headerRowBottom = headerRowBottom

    local sourceContainer = Factory:CreateContainer(textOverlay, math.max(1, width), 2, false)
    if not sourceContainer then
        sourceContainer = CreateFrame("Frame", nil, textOverlay)
        sourceContainer:SetHeight(1)
    end
    sourceContainer:SetPoint("TOPLEFT", headerRowBottom, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceContainer:SetPoint("TOPRIGHT", headerRowBottom, "BOTTOMRIGHT", 0, -TEXT_GAP)
    if sourceContainer.EnableMouse then sourceContainer:EnableMouse(false) end
    panel.sourceContainer = sourceContainer

    panel.sourceLines = {}

    -- Source label: gold color (consistent with Toy and all collection detail panels)
    local sourceLabel = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    sourceLabel:SetPoint("TOPLEFT", headerRowBottom, "BOTTOMLEFT", 0, -TEXT_GAP)
    sourceLabel:SetPoint("TOPRIGHT", headerRowBottom, "BOTTOMRIGHT", 0, -TEXT_GAP)
    sourceLabel:SetJustifyH("LEFT")
    sourceLabel:SetWordWrap(true)
    sourceLabel:SetNonSpaceWrap(false)
    sourceLabel:SetTextColor(goldR, goldG, goldB)
    panel.sourceLabel = sourceLabel

    local descText = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
    descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(false)
    descText:SetNonSpaceWrap(false)
    if descText.SetMaxLines then descText:SetMaxLines(1) end
    descText:SetTextColor(whiteR, whiteG, whiteB)
    panel.descText = descText

    local obtainedAtLine = FontManager:CreateFontString(textOverlay, "small", "OVERLAY")
    obtainedAtLine:SetJustifyH("LEFT")
    obtainedAtLine:SetWordWrap(true)
    obtainedAtLine:SetTextColor(1, 1, 1, 1)
    obtainedAtLine:Hide()
    panel.obtainedAtLine = obtainedAtLine

    local collectedBadge = FontManager:CreateFontString(textOverlay, "body", "OVERLAY")
    collectedBadge:SetPoint("BOTTOMLEFT", textOverlay, "BOTTOMLEFT", CONTENT_INSET, CONTENT_INSET)
    collectedBadge:SetPoint("RIGHT", textOverlay, "RIGHT", -CONTENT_INSET, 0)
    collectedBadge:SetJustifyH("LEFT")
    collectedBadge:Hide()
    panel.collectedBadge = collectedBadge

    -- descText exists: anchor model viewport below it (first layout; was previously deferred until SetMountInfo).
    UpdateModelFrameSize()

    panel.model = model

    panel:SetScript("OnShow", function()
        if panel._mountDisplayUsesJournalScene and panel._lastMountID and panel._journalMountScene then
            M.ApplyMountJournalModelSceneDisplay(panel._journalMountScene, panel._lastMountID, panel._lastCreatureDisplayID, true)
            M.ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
            return
        end
        local mid = panel._lastMountID
        if panel._useSetMountForRestore and mid and type(model.SetMount) == "function" then
            model:ClearModel()
            local ok = pcall(model.SetMount, model, mid)
            if ok then
                ApplyTransform()
                ScheduleJournalSceneAfterMount(mid)
                return
            end
        end
        local cid = panel._lastCreatureDisplayID
        if cid and cid > 0 and model.SetDisplayInfo then
            model:ClearModel()
            model:SetDisplayInfo(cid)
            ApplyTransform()
        end
    end)

    local function scheduleModelViewerLayout()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function() UpdateModelFrameSize() end)
        else
            UpdateModelFrameSize()
        end
    end

    function panel:SetMount(mountID, creatureDisplayIDFromCache)
        if not mountID then
            if panel._journalMountScene then
                panel._journalMountScene:Hide()
            end
            panel._mountDisplayUsesJournalScene = false
            ShowPlayerModelPath(true)
            model:ClearModel()
            panel._lastMountID = nil
            panel._lastCreatureDisplayID = nil
            panel._useSetMountForRestore = false
            panel._mountUiModelSceneID = nil
            panel._usesJournalCamera = false
            scheduleModelViewerLayout()
            return
        end
        local extraDisplayID, _, _, uiScene = M.SafeGetMountInfoExtra(mountID)
        panel._mountUiModelSceneID = uiScene
        panel._usesJournalCamera = false

        local creatureDisplayID = creatureDisplayIDFromCache
        if not creatureDisplayID or creatureDisplayID <= 0 then
            creatureDisplayID = extraDisplayID
        end

        local journalScene = TryInitJournalMountModelScene()
        if journalScene then
            panel._lastPetID = nil
            panel._lastMountID = mountID
            panel._lastCreatureDisplayID = (creatureDisplayID and creatureDisplayID > 0) and creatureDisplayID or nil
            panel._useSetMountForRestore = false
            local okJournal = M.ApplyMountJournalModelSceneDisplay(journalScene, mountID, creatureDisplayIDFromCache, true)
            if okJournal then
                panel._mountDisplayUsesJournalScene = true
                panel.zoomMultiplier = 1.0
                M.ApplyJournalModelSceneZoom(journalScene, panel.zoomMultiplier)
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if panel._lastMountID ~= mountID or not panel._mountDisplayUsesJournalScene or not panel._journalMountScene then return end
                        M.ApplyJournalModelSceneZoom(panel._journalMountScene, panel.zoomMultiplier)
                    end)
                end
                model:ClearModel()
                ShowPlayerModelPath(false)
                panel.normalizedRadius = false
                scheduleModelViewerLayout()
                return
            end
        end

        panel._mountDisplayUsesJournalScene = false
        if panel._journalMountScene then
            panel._journalMountScene:Hide()
        end
        ShowPlayerModelPath(true)

        local usedSetMount = false
        if type(model.SetMount) == "function" then
            model:ClearModel()
            usedSetMount = pcall(model.SetMount, model, mountID) == true
        end
        if usedSetMount then
            panel._useSetMountForRestore = true
            panel._lastMountID = mountID
            panel._lastCreatureDisplayID = (creatureDisplayID and creatureDisplayID > 0) and creatureDisplayID or nil
            panel.modelRotation = 0
            panel.camScale = FIXED_CAM_SCALE
            panel.normalizedRadius = true
            panel.modelScale = 1.0
            panel.zoomMultiplier = 1.0
            ApplyTransform()
            if model.SetAnimation then pcall(model.SetAnimation, model, 0) end
            ScheduleJournalSceneAfterMount(mountID)
            ScheduleBoundingRadiusRetries(mountID, 0)
            scheduleModelViewerLayout()
            return
        end
        if creatureDisplayID and creatureDisplayID > 0 then
            panel._useSetMountForRestore = false
            model:ClearModel()
            model:SetDisplayInfo(creatureDisplayID)
            panel._lastMountID = mountID
            panel._lastCreatureDisplayID = creatureDisplayID
            panel.modelRotation = 0
            panel.camScale = FIXED_CAM_SCALE
            -- İlk frame zoom-in olmasın: başta normalizedRadius=true, modelScale=1 ile sabit kamera kullan; radius gelince güncelle.
            panel.normalizedRadius = true
            panel.modelScale = 1.0
            panel.zoomMultiplier = 1.0
            ApplyTransform()
            if model.SetAnimation then pcall(model.SetAnimation, model, 0) end
            ScheduleJournalSceneAfterMount(mountID)
            ScheduleBoundingRadiusRetries(mountID, creatureDisplayID)
        else
            model:ClearModel()
            panel._lastMountID = nil
            panel._lastCreatureDisplayID = nil
            panel._useSetMountForRestore = false
            panel._mountUiModelSceneID = nil
            panel._usesJournalCamera = false
            panel.normalizedRadius = false
        end
        scheduleModelViewerLayout()
    end

    function panel:SetPet(speciesID, creatureDisplayIDFromCache)
        if not speciesID then
            if panel._journalMountScene then
                panel._journalMountScene:Hide()
            end
            panel._mountDisplayUsesJournalScene = false
            ShowPlayerModelPath(true)
            model:ClearModel()
            panel._lastPetID = nil
            panel._lastCreatureDisplayID = nil
            panel._useSetMountForRestore = false
            panel._mountUiModelSceneID = nil
            panel._usesJournalCamera = false
            scheduleModelViewerLayout()
            return
        end
        if panel._journalMountScene then
            panel._journalMountScene:Hide()
        end
        panel._mountDisplayUsesJournalScene = false
        ShowPlayerModelPath(true)
        local creatureDisplayID = creatureDisplayIDFromCache
        if not creatureDisplayID or creatureDisplayID <= 0 then
            creatureDisplayID = select(1, M.SafeGetPetInfoExtra(speciesID))
        end
        if creatureDisplayID and creatureDisplayID > 0 then
            panel._useSetMountForRestore = false
            panel._mountUiModelSceneID = nil
            panel._usesJournalCamera = false
            panel._lastMountID = nil
            model:ClearModel()
            model:SetDisplayInfo(creatureDisplayID)
            panel._lastPetID = speciesID
            panel._lastCreatureDisplayID = creatureDisplayID
            panel.modelRotation = 0
            panel.camScale = FIXED_CAM_SCALE
            panel.normalizedRadius = true
            panel.modelScale = 1.0
            panel.zoomMultiplier = 1.0
            ApplyTransform()
            if model.SetAnimation then pcall(model.SetAnimation, model, 0) end
            ScheduleBoundingRadiusRetries(nil, creatureDisplayID)
        else
            model:ClearModel()
            panel._lastPetID = nil
            panel._lastCreatureDisplayID = nil
            panel.normalizedRadius = false
        end
        scheduleModelViewerLayout()
    end

    local DEFAULT_ICON_MOUNT = "Interface\\Icons\\Ability_Mount_RidingHorse"
    local DEFAULT_ICON_PET = "Interface\\Icons\\INV_Box_PetCarrier_01"

    function panel:SetMountInfo(mountID, name, icon, sourceTextRaw, descriptionFromCache, isCollectedFromCache)
        if not mountID then
            local placeholder = (ns.L and ns.L["SELECT_MOUNT_FROM_LIST"]) or "Select a mount from the list"
            if placeholder == "" or placeholder == "SELECT_MOUNT_FROM_LIST" then placeholder = "Select a mount from the list" end
            nameText:SetText("|cffffffff" .. placeholder .. "|r")
            if panel.detailIconTexture then
                panel.detailIconTexture:SetTexture(DEFAULT_ICON_MOUNT)
                panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            sourceLabel:SetText("")
            local mountSrcLines = panel.sourceLines
            for li = 1, #mountSrcLines do
                local line = mountSrcLines[li]
                line:SetText("")
                line:Hide()
            end
            descText:SetText("")
            collectedBadge:SetText("")
            collectedBadge:Hide()
            descText:ClearAllPoints()
            descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            if panel._addContainer then panel._addContainer:Hide() end
            if panel._wowheadBtn then panel._wowheadBtn:Hide() end
            if panel._tryCountRow then panel._tryCountRow:Hide() end
            if panel.obtainedAtLine then panel.obtainedAtLine:Hide() end
            return
        end
        if panel._addContainer and panel._addBtn then
            panel._addContainer:Show()
            local planned = WarbandNexus and WarbandNexus.IsMountPlanned and WarbandNexus:IsMountPlanned(mountID)
            local collected = isCollectedFromCache
            M.RefreshCollectionsDetailPlanButton(panel._addBtn, collected, planned, function()
                if WarbandNexus and WarbandNexus.AddPlan then
                    WarbandNexus:AddPlan({
                        type = "mount",
                        mountID = mountID,
                        name = name,
                        icon = icon,
                        source = sourceTextRaw or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                    })
                end
            end)
        end
        if panel.detailIconTexture then
            panel.detailIconTexture:SetTexture(icon or DEFAULT_ICON_MOUNT)
            panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        collectedBadge:Hide()
        local gR = (COLORS.gold and COLORS.gold[1]) or 1
        local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local gB = (COLORS.gold and COLORS.gold[3]) or 0
        local goldHex = format("|cff%02x%02x%02x", gR * 255, gG * 255, gB * 255)
        nameText:SetText(goldHex .. (name or "") .. "|r" .. (SD.FormatMountPetToyListTrySuffix and SD.FormatMountPetToyListTrySuffix("mount", mountID) or ""))
        local description, source = descriptionFromCache, sourceTextRaw
        if (not source or source == "") or (not description or description == "") then
            local _, extraDesc, extraSrc = M.SafeGetMountInfoExtra(mountID)
            if not source or source == "" then source = extraSrc or "" end
            if not description or description == "" then description = extraDesc or "" end
        end
        source = source or ""
        description = description or ""
        if WarbandNexus.CleanSourceText then
            source = WarbandNexus:CleanSourceText(source)
            description = WarbandNexus:CleanSourceText(description)
        else
            source = SD.StripWoWFormatCodes(source)
            description = SD.StripWoWFormatCodes(description)
        end
        local rawSource = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if rawSource == "" or rawSource == "Unknown" then
            rawSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        end
        local whiteHex = "|cffffffff"
        -- Cost/Amount satırlarına para birimi ikonu (satın alma)
        local L = ns.L
        local costKey = (L and L["PARSE_COST"]) or "Cost"
        local amountKey = (L and L["PARSE_AMOUNT"]) or "Amount"
        local function isCostOrAmountLine(text)
            if not text or text == "" then return false end
            if issecretvalue and issecretvalue(text) then return false end
            local t = text:gsub("^%s+", "")
            return t:sub(1, #costKey):lower() == costKey:lower() or t:sub(1, #amountKey):lower() == amountKey:lower()
        end
        -- API satırları: "Label: Value" ise etiket (Drop, Zone, Location vb.) sarı, değer beyaz
        local lines = {}
        for line in (rawSource .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local colonPos = line:find(":", 1, true)
                if colonPos and colonPos > 1 then
                    local label = line:sub(1, colonPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local value = line:sub(colonPos + 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local suffix = isCostOrAmountLine(line) and (" " .. SD.GetCurrencyIconForCostLine(value)) or ""
                    lines[#lines + 1] = goldHex .. label .. ": |r" .. whiteHex .. value .. "|r" .. suffix
                else
                    local suffix = isCostOrAmountLine(line) and (" " .. SD.GetCurrencyIconForCostLine(line)) or ""
                    lines[#lines + 1] = whiteHex .. line .. "|r" .. suffix
                end
            end
        end
        if #lines == 0 then
            lines[1] = whiteHex .. rawSource .. "|r"
        end
        sourceLabel:SetText("")
        local TEXT_GAP_LINE = TEXT_GAP
        local lastAnchor = sourceContainer
        local lastPoint = "TOPLEFT"
        local lastY = 0
        for i = 1, #lines do
            local lineFs = panel.sourceLines[i]
            if not lineFs then
                lineFs = FontManager:CreateFontString(sourceContainer, "body", "OVERLAY")
                lineFs:SetPoint("TOPLEFT", sourceContainer, "TOPLEFT", 0, 0)
                lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, 0)
                lineFs:SetJustifyH("LEFT")
                lineFs:SetWordWrap(true)
                lineFs:SetNonSpaceWrap(false)
                lineFs:SetTextColor(whiteR, whiteG, whiteB)
                panel.sourceLines[i] = lineFs
            end
            lineFs:ClearAllPoints()
            lineFs:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
            lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
            lineFs:SetText(lines[i])
            lineFs:Show()
            lastAnchor = lineFs
            lastPoint = "BOTTOMLEFT"
            lastY = -TEXT_GAP_LINE
        end
        for i = #lines + 1, #panel.sourceLines do
            panel.sourceLines[i]:SetText("")
            panel.sourceLines[i]:Hide()
        end
        local isCollected = isCollectedFromCache
        if isCollected == nil and C_MountJournal and C_MountJournal.GetMountInfoByID then
            local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
            if issecretvalue and collected and issecretvalue(collected) then
                isCollected = false
            else
                isCollected = collected == true
            end
        end

        local anchorBeforeDesc, pointBeforeDesc, yBeforeDesc = lastAnchor, lastPoint, lastY
        if panel.obtainedAtLine then
            panel.obtainedAtLine:ClearAllPoints()
            local obtText = (isCollected and WarbandNexus.GetCollectionsAcquiredAt)
                and M.FormatCollectionsAcquiredDetail(WarbandNexus:GetCollectionsAcquiredAt("mount", mountID))
                or nil
            if obtText then
                panel.obtainedAtLine:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
                panel.obtainedAtLine:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
                panel.obtainedAtLine:SetText(obtText)
                panel.obtainedAtLine:Show()
                anchorBeforeDesc = panel.obtainedAtLine
                pointBeforeDesc = "BOTTOMLEFT"
                yBeforeDesc = -TEXT_GAP_LINE
            else
                panel.obtainedAtLine:Hide()
            end
        end

        M.PinCollectionsDetailDescriptionLine(descText, textOverlay, anchorBeforeDesc, pointBeforeDesc, 0, yBeforeDesc)

        description = (description or ""):gsub("^%s+", ""):gsub("%s+$", "")
        description = description:gsub("[%c\r\n]+", " ")
        -- API'den gelen description: tek satir, beyaz
        descText:SetText(description ~= "" and (whiteHex .. description .. "|r") or "")

        if panel._wowheadBtn then
            local spellID = nil
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, sid = C_MountJournal.GetMountInfoByID(mountID)
                if sid and sid > 0 then spellID = sid end
            end
            if spellID then
                panel._wowheadBtn:SetScript("OnClick", function(self)
                    if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                        ns.UI.Factory:ShowWowheadCopyURL("mount", spellID, self)
                    end
                end)
                panel._wowheadBtn:Show()
            else
                panel._wowheadBtn:Hide()
            end
        end

        if panel._tryCountRow and panel._tryCountRow.WnUpdateTryCount then
            panel._tryCountRow:WnUpdateTryCount("mount", mountID, name)
        end

        if C_Timer and C_Timer.After and panel.UpdateModelFrameSize then
            C_Timer.After(0, function() panel.UpdateModelFrameSize() end)
        end
    end

    function panel:SetPetInfo(speciesID, name, icon, sourceTextRaw, descriptionFromCache, isCollectedFromCache)
        if not speciesID then
            local placeholder = (ns.L and ns.L["SELECT_PET_FROM_LIST"]) or "Select a pet from the list"
            if placeholder == "" or placeholder == "SELECT_PET_FROM_LIST" then placeholder = "Select a pet from the list" end
            nameText:SetText("|cffffffff" .. placeholder .. "|r")
            if panel.detailIconTexture then
                panel.detailIconTexture:SetTexture(DEFAULT_ICON_PET)
                panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            sourceLabel:SetText("")
            local petSrcLines = panel.sourceLines
            for li = 1, #petSrcLines do
                local line = petSrcLines[li]
                line:SetText("")
                line:Hide()
            end
            descText:SetText("")
            collectedBadge:SetText("")
            collectedBadge:Hide()
            descText:ClearAllPoints()
            descText:SetPoint("TOPLEFT", sourceContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            descText:SetPoint("TOPRIGHT", sourceContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            if panel._addContainer then panel._addContainer:Hide() end
            if panel._wowheadBtn then panel._wowheadBtn:Hide() end
            if panel._tryCountRow then panel._tryCountRow:Hide() end
            if panel.obtainedAtLine then panel.obtainedAtLine:Hide() end
            return
        end
        if panel._addContainer and panel._addBtn then
            panel._addContainer:Show()
            local planned = WarbandNexus and WarbandNexus.IsPetPlanned and WarbandNexus:IsPetPlanned(speciesID)
            local collected = isCollectedFromCache
            M.RefreshCollectionsDetailPlanButton(panel._addBtn, collected, planned, function()
                if WarbandNexus and WarbandNexus.AddPlan then
                    WarbandNexus:AddPlan({
                        type = "pet",
                        speciesID = speciesID,
                        name = name,
                        icon = icon,
                        source = sourceTextRaw or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                    })
                end
            end)
        end
        if panel.detailIconTexture then
            panel.detailIconTexture:SetTexture(icon or DEFAULT_ICON_PET)
            panel.detailIconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        collectedBadge:Hide()
        local gR = (COLORS.gold and COLORS.gold[1]) or 1
        local gG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local gB = (COLORS.gold and COLORS.gold[3]) or 0
        local goldHex = format("|cff%02x%02x%02x", gR * 255, gG * 255, gB * 255)
        nameText:SetText(goldHex .. (name or "") .. "|r" .. (SD.FormatMountPetToyListTrySuffix and SD.FormatMountPetToyListTrySuffix("pet", speciesID) or ""))
        local description, source = descriptionFromCache, sourceTextRaw
        if (not source or source == "") or (not description or description == "") then
            local _, extraDesc, extraSrc = M.SafeGetPetInfoExtra(speciesID)
            if not source or source == "" then source = extraSrc or "" end
            if not description or description == "" then description = extraDesc or "" end
        end
        source = source or ""
        description = description or ""
        if WarbandNexus.CleanSourceText then
            source = WarbandNexus:CleanSourceText(source)
            description = WarbandNexus:CleanSourceText(description)
        else
            source = SD.StripWoWFormatCodes(source)
            description = SD.StripWoWFormatCodes(description)
        end
        local rawSource = (source or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if rawSource == "" or rawSource == "Unknown" then
            rawSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        end
        local whiteHex = "|cffffffff"
        local L = ns.L
        local costKey = (L and L["PARSE_COST"]) or "Cost"
        local amountKey = (L and L["PARSE_AMOUNT"]) or "Amount"
        local function isCostOrAmountLine(text)
            if not text or text == "" then return false end
            if issecretvalue and issecretvalue(text) then return false end
            local t = text:gsub("^%s+", "")
            return t:sub(1, #costKey):lower() == costKey:lower() or t:sub(1, #amountKey):lower() == amountKey:lower()
        end
        local lines = {}
        for line in (rawSource .. "\n"):gmatch("([^\n]*)\n") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line ~= "" then
                local colonPos = line:find(":", 1, true)
                if colonPos and colonPos > 1 then
                    local label = line:sub(1, colonPos - 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local value = line:sub(colonPos + 1):gsub("^%s+", ""):gsub("%s+$", "")
                    local suffix = isCostOrAmountLine(line) and (" " .. SD.GetCurrencyIconForCostLine(value)) or ""
                    lines[#lines + 1] = goldHex .. label .. ": |r" .. whiteHex .. value .. "|r" .. suffix
                else
                    local suffix = isCostOrAmountLine(line) and (" " .. SD.GetCurrencyIconForCostLine(line)) or ""
                    lines[#lines + 1] = whiteHex .. line .. "|r" .. suffix
                end
            end
        end
        if #lines == 0 then
            lines[1] = whiteHex .. rawSource .. "|r"
        end
        sourceLabel:SetText("")
        local TEXT_GAP_LINE = TEXT_GAP
        local lastAnchor = sourceContainer
        local lastPoint = "TOPLEFT"
        local lastY = 0
        for i = 1, #lines do
            local lineFs = panel.sourceLines[i]
            if not lineFs then
                lineFs = FontManager:CreateFontString(sourceContainer, "body", "OVERLAY")
                lineFs:SetPoint("TOPLEFT", sourceContainer, "TOPLEFT", 0, 0)
                lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, 0)
                lineFs:SetJustifyH("LEFT")
                lineFs:SetWordWrap(true)
                lineFs:SetNonSpaceWrap(false)
                lineFs:SetTextColor(whiteR, whiteG, whiteB)
                panel.sourceLines[i] = lineFs
            end
            lineFs:ClearAllPoints()
            lineFs:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
            lineFs:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
            lineFs:SetText(lines[i])
            lineFs:Show()
            lastAnchor = lineFs
            lastPoint = "BOTTOMLEFT"
            lastY = -TEXT_GAP_LINE
        end
        for i = #lines + 1, #panel.sourceLines do
            panel.sourceLines[i]:SetText("")
            panel.sourceLines[i]:Hide()
        end
        local petCollected = isCollectedFromCache
        if petCollected == nil then
            petCollected = M.SafeGetPetCollected(speciesID)
        end

        local anchorBeforeDescP, pointBeforeDescP, yBeforeDescP = lastAnchor, lastPoint, lastY
        if panel.obtainedAtLine then
            panel.obtainedAtLine:ClearAllPoints()
            local obtText = (petCollected and WarbandNexus.GetCollectionsAcquiredAt)
                and M.FormatCollectionsAcquiredDetail(WarbandNexus:GetCollectionsAcquiredAt("pet", speciesID))
                or nil
            if obtText then
                panel.obtainedAtLine:SetPoint("TOPLEFT", lastAnchor, lastPoint, 0, lastY)
                panel.obtainedAtLine:SetPoint("TOPRIGHT", sourceContainer, "TOPRIGHT", 0, lastY)
                panel.obtainedAtLine:SetText(obtText)
                panel.obtainedAtLine:Show()
                anchorBeforeDescP = panel.obtainedAtLine
                pointBeforeDescP = "BOTTOMLEFT"
                yBeforeDescP = -TEXT_GAP_LINE
            else
                panel.obtainedAtLine:Hide()
            end
        end

        M.PinCollectionsDetailDescriptionLine(descText, textOverlay, anchorBeforeDescP, pointBeforeDescP, 0, yBeforeDescP)
        description = (description or ""):gsub("^%s+", ""):gsub("%s+$", "")
        description = description:gsub("[%c\r\n]+", " ")
        descText:SetText(description ~= "" and (whiteHex .. description .. "|r") or "")

        if panel._wowheadBtn and speciesID then
            panel._wowheadBtn:SetScript("OnClick", function(self)
                if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                    ns.UI.Factory:ShowWowheadCopyURL("pet", speciesID, self)
                end
            end)
            panel._wowheadBtn:Show()
        elseif panel._wowheadBtn then
            panel._wowheadBtn:Hide()
        end

        if panel._tryCountRow and panel._tryCountRow.WnUpdateTryCount then
            panel._tryCountRow:WnUpdateTryCount("pet", speciesID, name)
        end

        if C_Timer and C_Timer.After and panel.UpdateModelFrameSize then
            C_Timer.After(0, function() panel.UpdateModelFrameSize() end)
        end
    end

    return panel
end

-- ============================================================================
-- DESCRIPTION PANEL (standalone; used only if we need separate panel elsewhere)
-- ============================================================================

function M.CreateDescriptionPanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetSize(width, height)
    ApplyVisuals(panel, {0.08, 0.08, 0.10, 0.95}, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    function panel:SetMountInfo() end
    return panel
end

-- ============================================================================
-- LOADING STATE PANEL
-- ============================================================================

function M.GetOrCreateLoadingPanel(parent)
    local UI_CreateLoadingStatePanel = ns.UI_CreateLoadingStatePanel
    if UI_CreateLoadingStatePanel then
        return UI_CreateLoadingStatePanel(parent)
    end
    local fallback = Factory:CreateContainer(parent, math.max(1, parent:GetWidth() or 200), math.max(1, parent:GetHeight() or 200), false)
    if not fallback then
        fallback = CreateFrame("Frame", nil, parent)
    end
    fallback:SetAllPoints(parent)
    function fallback:ShowLoading() self:Show() end
    function fallback:HideLoading() self:Hide() end
    return fallback
end

-- ============================================================================
-- ACHIEVEMENT DETAIL PANEL — Parent/Children, Description, Criteria (replaces model viewer)
-- ============================================================================
-- Achievement detail header: icon-only To-Do + Track (same WN vertex icons as list rows).
local ACH_ACTION_ICON_SZ = (ns.CollectionsDetailHeaderLayout and ns.CollectionsDetailHeaderLayout.DETAIL_ACTION_SIZE) or 32
local ACH_ROW_ADD_WIDTH = ACH_ACTION_ICON_SZ
local ACH_ROW_ADD_HEIGHT = ACH_ACTION_ICON_SZ
local ACH_TRACK_WIDTH = ACH_ACTION_ICON_SZ
local ACH_TRACK_HEIGHT = ACH_ACTION_ICON_SZ
local ACH_ACTION_GAP = 6

-- Build full achievement series (e.g. Level 10, 20, 30... 80): walk to root via GetPreviousAchievement, then collect all via GetSupercedingAchievements.
-- Returns ordered array of achievement IDs from first tier to last; length >= 1 when achievement is part of a chain.
function M.BuildAchievementSeries(achievementID)
    if not achievementID or achievementID <= 0 then return {} end
    if issecretvalue and issecretvalue(achievementID) then return {} end
    local GetPrev = GetPreviousAchievement
    local GetSuperceding = (C_AchievementInfo and C_AchievementInfo.GetSupercedingAchievements) or function() return {} end
    if not GetPrev then return { achievementID } end
    local id = achievementID
    local guard = 0
    local MAX_CHAIN = 250
    while true do
        guard = guard + 1
        if guard > MAX_CHAIN then break end
        local okp, prev = pcall(GetPrev, id)
        if not okp or prev == nil then break end
        if issecretvalue and issecretvalue(prev) then break end
        if type(prev) ~= "number" or prev <= 0 then break end
        id = prev
    end
    local series = { id }
    local idx = 1
    guard = 0
    while true do
        guard = guard + 1
        if guard > MAX_CHAIN then break end
        local cur = series[idx]
        if cur == nil then break end
        if issecretvalue and issecretvalue(cur) then break end
        local okn, nextIds = pcall(GetSuperceding, cur)
        if not okn or not nextIds or type(nextIds) ~= "table" or #nextIds == 0 then break end
        local nxt = nextIds[1]
        if nxt == nil then break end
        if issecretvalue and issecretvalue(nxt) then break end
        if type(nxt) ~= "number" or nxt <= 0 then break end
        series[idx + 1] = nxt
        idx = idx + 1
    end
    return series
end

function M.IsAchievementTracked(achievementID)
    if not achievementID then return false end
    if WarbandNexus and WarbandNexus.IsAchievementTracked then
        return WarbandNexus:IsAchievementTracked(achievementID)
    end
    return false
end

function M.ToggleAchievementTracking(achievementID)
    if not achievementID then return false end
    if WarbandNexus and WarbandNexus.ToggleAchievementTracking then
        return WarbandNexus:ToggleAchievementTracking(achievementID)
    end
    return false
end

function M.CreateAchievementDetailPanel(parent, width, height, onSelectAchievement)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(width, height)

    panel._scrollBarContainer = M.EnsureDetailScrollBarContainer(panel._scrollBarContainer, panel, SCROLLBAR_GAP, CONTAINER_INSET)
    local scroll = Factory:CreateScrollFrame(panel, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
    scroll:SetPoint("BOTTOMRIGHT", panel._scrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
    M.EnableStandardScrollWheel(scroll)
    panel.scrollFrame = scroll

    local child = M.CreateStandardScrollChild(scroll, width - (CONTAINER_INSET * 2) - SCROLLBAR_GAP, 1)
    if scroll.ScrollBar then
        Factory:PositionScrollBarInContainer(scroll.ScrollBar, panel._scrollBarContainer, CONTAINER_INSET)
    end

    local content = child
    local lastAnchor = content
    local lastPoint = "TOPLEFT"
    local lastY = 0
    local TEXT_GAP_LINE = TEXT_GAP

    panel._detailElements = {}

    local function clearDetailElements()
        local bin = ns.UI_RecycleBin
        local dels = panel._detailElements
        for ei = 1, #dels do
            local el = dels[ei]
            el:Hide()
            if bin then el:SetParent(bin) else el:SetParent(nil) end
        end
        panel._detailElements = {}
    end

    local function addDetailElement(el)
        if el then
            panel._detailElements[#panel._detailElements + 1] = el
        end
    end

    -- Achievement details: flat sections (no nested cards); single accent border on outer container only.
    local SECTION_GAP = 4
    local SECTION_HEADER_GAP = 10
    local CONTENT_COLUMN_LEFT = CONTENT_INSET
    local SERIES_ICON_GAP = 6
    local SERIES_ROW_GAP = 2

    local goldR = (COLORS.gold and COLORS.gold[1]) or 1
    local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
    local goldB = (COLORS.gold and COLORS.gold[3]) or 0
    local bodyR, bodyG, bodyB = 1, 1, 1
    local mutedR, mutedG, mutedB = 1, 1, 1
    local completeR, completeG, completeB = 0.35, 0.88, 0.45

    local function addSection(title, fn)
        local titleFs = FontManager:CreateFontString(content, "body", "OVERLAY")
        titleFs:SetPoint("TOP", lastAnchor, "BOTTOM", 0, lastY)
        titleFs:SetPoint("LEFT", content, "LEFT", CONTENT_COLUMN_LEFT, 0)
        titleFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(true)
        titleFs:SetTextColor(goldR, goldG, goldB)
        titleFs:SetText(title or "")
        addDetailElement(titleFs)
        lastAnchor = titleFs
        lastPoint = "BOTTOMLEFT"
        lastY = -SECTION_GAP
        fn(titleFs)
    end

    local SERIES_ICON_SIZE = ROW_ICON_SIZE
    local SERIES_ROW_PAD = 4
    local seriesBorderColor = Factory.GetCollectionsDetailIconBorderColor and Factory:GetCollectionsDetailIconBorderColor()

    local function addAchievementRow(ach, label, currentAchievementID)
        if not ach or not ach.id then return end
        if issecretvalue and issecretvalue(ach.id) then return end
        if ach.name and issecretvalue and issecretvalue(ach.name) then return end
        local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
        row:SetPoint("TOP", lastAnchor, lastPoint, 0, lastY)
        row:SetPoint("LEFT", content, "LEFT", CONTENT_COLUMN_LEFT, 0)
        row:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
        row:SetHeight(ROW_HEIGHT)
        row:EnableMouse(true)
        local isCurrent = false
        if currentAchievementID and ach.id then
            if not (issecretvalue and issecretvalue(currentAchievementID)) and not (issecretvalue and issecretvalue(ach.id)) then
                isCurrent = (ach.id == currentAchievementID)
            end
        end
        if ApplyVisuals then
            local bg = COLORS.bgCard or COLORS.bgLight or { 0.09, 0.09, 0.11, 0.92 }
            local edgeA = (seriesBorderColor and seriesBorderColor[4]) or 0.75
            local edge = isCurrent and { goldR, goldG, goldB, edgeA }
                or (seriesBorderColor and { seriesBorderColor[1], seriesBorderColor[2], seriesBorderColor[3], edgeA })
                or { COLORS.border[1], COLORS.border[2], COLORS.border[3], edgeA }
            ApplyVisuals(row, { bg[1], bg[2], bg[3], bg[4] or 0.92 }, edge)
        end
        local iconShell = Factory.CreateCollectionsDetailIconShell and Factory:CreateCollectionsDetailIconShell(row, SERIES_ICON_SIZE, {
            borderColor = seriesBorderColor,
        })
        if iconShell then
            iconShell:SetPoint("LEFT", row, "LEFT", SERIES_ROW_PAD, 0)
            iconShell:EnableMouse(false)
        end
        local iconHost = iconShell or row
        local iconPad = (ns.CollectionsDetailHeaderLayout and ns.CollectionsDetailHeaderLayout.DETAIL_ICON_PAD) or 2
        local icon = iconHost:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("TOPLEFT", iconHost, "TOPLEFT", iconPad, -iconPad)
        icon:SetPoint("BOTTOMRIGHT", iconHost, "BOTTOMRIGHT", -iconPad, iconPad)
        icon:SetTexture(ach.icon or "Interface\\Icons\\Achievement_General")
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local nameFs = FontManager:CreateFontString(row, "body", "OVERLAY")
        if iconShell then
            nameFs:SetPoint("LEFT", iconShell, "RIGHT", SERIES_ICON_GAP, 0)
        else
            nameFs:SetPoint("LEFT", row, "LEFT", SERIES_ICON_SIZE + SERIES_ICON_GAP, 0)
        end
        nameFs:SetPoint("RIGHT", row, "RIGHT", -PADDING, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(true)
        local ptsStr = (ach.points and ach.points > 0) and (" (" .. ach.points .. " pts)") or ""
        if isCurrent then
            nameFs:SetTextColor(goldR, goldG, goldB)
        elseif ach.isCollected then
            nameFs:SetTextColor(completeR, completeG, completeB)
        else
            nameFs:SetTextColor(bodyR, bodyG, bodyB)
        end
        nameFs:SetText((ach.name or "") .. ptsStr)
        row:SetScript("OnMouseDown", function()
            if onSelectAchievement then onSelectAchievement(ach) end
            if ach.id and not InCombatLockdown() and OpenAchievementFrameToAchievement then
                pcall(OpenAchievementFrameToAchievement, ach.id)
            end
        end)
        addDetailElement(row)
        lastAnchor = row
        lastPoint = "BOTTOMLEFT"
        lastY = -(SERIES_ROW_GAP + 2)
    end

    function panel:SetAchievement(achievement)
        clearDetailElements()
        lastAnchor = content
        lastPoint = "TOPLEFT"
        lastY = 0
        panel._currentAchievement = achievement

        if not achievement or not achievement.id then
            child:SetHeight(1)
            return
        end

        -- Header: same hierarchy as Mounts/Pets (CONTENT_INSET from edges, icon then name)
        local CDH = ns.CollectionsDetailHeaderLayout or {}
        local achRightColMinH = ACH_ROW_ADD_HEIGHT + (CDH.TRY_GAP or 4) + (CDH.TRY_ROW_H or 18)
        local achHdrH = math.max(ROW_HEIGHT + SECTION_GAP, DETAIL_ICON_SIZE + SECTION_GAP, achRightColMinH)
        local achHdrW = math.max(220, (child.GetWidth and child:GetWidth()) or 620)
        local headerRow = Factory:CreateContainer(content, achHdrW, achHdrH, false)
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, content)
        end
        headerRow:SetPoint("TOPLEFT", content, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetPoint("TOPRIGHT", content, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetHeight(achHdrH)
        local iconBorder = Factory:CreateContainer(headerRow, DETAIL_ICON_SIZE, DETAIL_ICON_SIZE, true)
        iconBorder:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
        local detailIconBorder = Factory.GetCollectionsDetailIconBorderColor and Factory:GetCollectionsDetailIconBorderColor()
        if ApplyVisuals then
            ApplyVisuals(iconBorder, {0.12, 0.12, 0.14, 0.95}, detailIconBorder or {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.75})
        end
        local headerIcon = iconBorder:CreateTexture(nil, "OVERLAY")
        headerIcon:SetAllPoints()
        headerIcon:SetTexture(achievement.icon or "Interface\\Icons\\Achievement_General")
        headerIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local DETAIL_HEADER_GAP = 10
        local goldR = (COLORS.gold and COLORS.gold[1]) or 1
        local goldG = (COLORS.gold and COLORS.gold[2]) or 0.82
        local goldB = (COLORS.gold and COLORS.gold[3]) or 0
        -- Sağ üst: mount/pet/toy ile aynı Factory sütunu (Wowhead en sağ, try satırı action genişliğinde; slot Add+Track için genişletildi)
        local achActionW = ACH_ROW_ADD_WIDTH + ACH_ACTION_GAP + ACH_TRACK_WIDTH
        local achAddCol = Factory:CreateCollectionsDetailRightColumn(headerRow, {
            withTryRow = true,
            actionSlotWidth = achActionW,
            actionSlotHeight = ACH_ROW_ADD_HEIGHT,
        })
        achAddCol.root:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
        local achControls = Factory:CreateContainer(achAddCol.actionSlot, ACH_ACTION_GAP + ACH_TRACK_WIDTH + ACH_ROW_ADD_WIDTH, ACH_ROW_ADD_HEIGHT, false)
        if not achControls then
            achControls = CreateFrame("Frame", nil, achAddCol.actionSlot)
        end
        achControls:SetAllPoints(achAddCol.actionSlot)

        local headerWowheadBtn = achAddCol.wowheadBtn
        local achIDForWh = achievement.id
        headerWowheadBtn:SetScript("OnClick", function(self)
            if achIDForWh and ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                ns.UI.Factory:ShowWowheadCopyURL("achievement", achIDForWh, self)
            end
        end)
        if achievement.id then
            headerWowheadBtn:Show()
        else
            headerWowheadBtn:Hide()
        end

        local detailActionInner = ACH_TRACK_WIDTH - 4
        local trackShell = Factory.CreateCollectionsDetailIconShell
            and Factory:CreateCollectionsDetailIconShell(achControls, ACH_TRACK_WIDTH, { borderColor = detailIconBorder })
        local trackBtn = trackShell and Factory.CreateAchievementTrackPinButton
            and Factory:CreateAchievementTrackPinButton(trackShell, achievement.id, {
                size = detailActionInner,
                frameLevelOffset = 25,
                isDisabled = function() return achievement.isCollected == true end,
            })
        if trackBtn and trackShell and Factory.CenterCollectionsDetailActionButton then
            Factory:CenterCollectionsDetailActionButton(trackShell, trackBtn)
        end
        if trackShell then
            trackShell:SetPoint("TOPRIGHT", achControls, "TOPRIGHT", 0, 0)
        elseif trackBtn then
            trackBtn:SetPoint("TOPRIGHT", achControls, "TOPRIGHT", 0, 0)
        end
        if trackBtn and trackBtn.WnRefreshAchievementTrackPin then
            trackBtn:WnRefreshAchievementTrackPin()
        end

        local isPlanned = WarbandNexus and WarbandNexus.IsAchievementPlanned and WarbandNexus:IsAchievementPlanned(achievement.id)
        local planShell = Factory.CreateCollectionsDetailIconShell
            and Factory:CreateCollectionsDetailIconShell(achControls, ACH_ROW_ADD_WIDTH, { borderColor = detailIconBorder })
        local addBtn = planShell and PlanCardFactory and PlanCardFactory.CreateAddButton(planShell, {
            iconOnly = true,
            width = detailActionInner,
            height = detailActionInner,
            anchorPoint = "CENTER",
            x = 0,
            y = 0,
        })
        if addBtn and planShell and Factory.CenterCollectionsDetailActionButton then
            Factory:CenterCollectionsDetailActionButton(planShell, addBtn)
        end
        if planShell and trackShell then
            planShell:SetPoint("RIGHT", trackShell, "LEFT", -ACH_ACTION_GAP, 0)
        elseif addBtn and trackShell then
            addBtn:ClearAllPoints()
            addBtn:SetPoint("RIGHT", trackShell, "LEFT", -ACH_ACTION_GAP, 0)
        end
        if addBtn then
            addBtn:SetFrameLevel(headerRow:GetFrameLevel() + 25)
        end
        if addBtn then
            M.RefreshCollectionsDetailPlanButton(addBtn, achievement.isCollected, isPlanned, function()
                if not achievement.id or not WarbandNexus or not WarbandNexus.AddPlan then return end
                local rewardInfo = WarbandNexus.GetAchievementRewardInfo and WarbandNexus:GetAchievementRewardInfo(achievement.id)
                local rewardText = rewardInfo and (rewardInfo.title or rewardInfo.itemName) or nil
                if not rewardText or rewardText == "" then
                    rewardText = achievement.rewardText or achievement.rewardTitle
                end
                WarbandNexus:AddPlan({
                    type = "achievement",
                    achievementID = achievement.id,
                    name = achievement.name,
                    icon = achievement.icon,
                    points = achievement.points,
                    source = achievement.source,
                    rewardText = rewardText,
                })
            end)
        end

        panel._achDetailTrackBtn = trackBtn
        panel._achDetailAddBtn = addBtn
        panel._achDetailAddedIndicator = nil

        if achAddCol.tryCountRow and achAddCol.tryCountRow.WnUpdateTryCount then
            achAddCol.tryCountRow:WnUpdateTryCount("achievement", achievement.id, achievement.name)
        end

        local headerName = FontManager:CreateFontString(headerRow, "header", "OVERLAY")
        headerName:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
        headerName:SetPoint("TOPRIGHT", achAddCol.root, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
        headerName:SetJustifyH("LEFT")
        headerName:SetWordWrap(true)
        headerName:SetTextColor(goldR, goldG, goldB)
        headerName:SetText((achievement.name or "") .. (achievement.points and achievement.points > 0 and (" (" .. achievement.points .. " pts)") or ""))

        addDetailElement(headerRow)
        lastAnchor = headerRow
        lastPoint = "BOTTOMLEFT"
        lastY = -SECTION_GAP

        if achievement.isCollected and WarbandNexus and WarbandNexus.GetCollectionsAcquiredAt then
            local obtTs = WarbandNexus:GetCollectionsAcquiredAt("achievement", achievement.id)
            local obtStr = obtTs and M.FormatCollectionsAcquiredDetail(obtTs) or nil
            if obtStr then
                local obtFs = FontManager:CreateFontString(content, "small", "OVERLAY")
                obtFs:SetPoint("TOP", lastAnchor, "BOTTOM", 0, lastY)
                obtFs:SetPoint("LEFT", content, "LEFT", CONTENT_COLUMN_LEFT, 0)
                obtFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
                obtFs:SetJustifyH("LEFT")
                obtFs:SetWordWrap(true)
                obtFs:SetTextColor(1, 1, 1, 1)
                obtFs:SetText(obtStr)
                addDetailElement(obtFs)
                lastAnchor = obtFs
                lastPoint = "BOTTOMLEFT"
                lastY = -SECTION_GAP
            end
        end

        if achievement.description and achievement.description ~= "" then
            lastY = lastY - SECTION_HEADER_GAP
            addSection((ns.L and ns.L["DESCRIPTION"]) or "Description", function(titleFs)
                local descFs = FontManager:CreateFontString(content, "body", "OVERLAY")
                descFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -SECTION_GAP)
                descFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
                descFs:SetJustifyH("LEFT")
                descFs:SetWordWrap(true)
                descFs:SetTextColor(bodyR, bodyG, bodyB)
                local descBody = (achievement.description or ""):gsub("[%c\r\n]+", " ")
                descFs:SetText(descBody)
                addDetailElement(descFs)
                lastAnchor = descFs
                lastPoint = "BOTTOMLEFT"
                lastY = -SECTION_GAP
            end)
        end

        -- Achievement series (e.g. Level 10, 20, 30... 80): all tiers with check/cross; current achievement highlighted
        local seriesIds = M.BuildAchievementSeries(achievement.id)
        if seriesIds and #seriesIds > 1 then
            lastY = lastY - SECTION_HEADER_GAP
            addSection((ns.L and ns.L["ACHIEVEMENT_SERIES"]) or "Achievement Series", function()
                for i = 1, #seriesIds do
                    local achID = seriesIds[i]
                    if achID and not (issecretvalue and issecretvalue(achID)) then
                        -- GetAchievementInfo: id, name, points, completed, month, day, year, description, flags, icon, ...
                        local ok, _, aName, aPoints, aCompleted, _, _, _, aDesc, _, aIcon = pcall(GetAchievementInfo, achID)
                        if ok and aName and not (issecretvalue and issecretvalue(aName)) then
                            addAchievementRow({ id = achID, name = aName, icon = aIcon, points = aPoints, isCollected = aCompleted, description = aDesc }, nil, achievement.id)
                        end
                    end
                end
            end)
        end

        local rewardInfo = WarbandNexus.GetAchievementRewardInfo and WarbandNexus:GetAchievementRewardInfo(achievement.id)
        local rewardDisplayText
        if rewardInfo then
            rewardDisplayText = rewardInfo.title or rewardInfo.itemName
        end
        if not rewardDisplayText or rewardDisplayText == "" then
            rewardDisplayText = achievement.rewardText or achievement.rewardTitle
        end
        if rewardDisplayText and rewardDisplayText ~= "" then
            rewardDisplayText = rewardDisplayText:gsub("^%s*[Rr]eward:?%s*", "")
            if rewardDisplayText ~= "" then
                lastY = lastY - SECTION_HEADER_GAP
                addSection((ns.L and ns.L["REWARD_LABEL"]) or "Reward", function(titleFs)
                    local rewardFs = FontManager:CreateFontString(content, "body", "OVERLAY")
                    rewardFs:SetPoint("TOPLEFT", titleFs, "BOTTOMLEFT", 0, -SECTION_GAP)
                    rewardFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
                    rewardFs:SetJustifyH("LEFT")
                    rewardFs:SetWordWrap(true)
                    if rewardInfo and rewardInfo.type == "title" then
                        rewardFs:SetTextColor(goldR, goldG, goldB)
                    else
                        rewardFs:SetTextColor(completeR, completeG, completeB)
                    end
                    rewardFs:SetText(rewardDisplayText)
                    addDetailElement(rewardFs)
                    lastAnchor = rewardFs
                    lastPoint = "BOTTOMLEFT"
                    lastY = -SECTION_GAP
                end)
            end
        end

        local numCriteria = GetAchievementNumCriteria and GetAchievementNumCriteria(achievement.id) or 0
        if numCriteria > 0 then
            lastY = lastY - SECTION_HEADER_GAP
            addSection((ns.L and ns.L["CRITERIA"]) or "Criteria", function(titleFs)
                local critAnchor = titleFs
                local critPoint = "BOTTOMLEFT"
                local critY = -SECTION_GAP
                local achSummary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(achievement.id)
                local formatRowSuffix = ns.UI_FormatCriterionRowSuffix
                local critRows = achSummary and achSummary.criteria
                local critCount = critRows and #critRows or numCriteria
                for i = 1, critCount do
                    local row = critRows and critRows[i]
                    local criteriaName = row and row.name
                    local completed = row and row.completed
                    if criteriaName and criteriaName ~= "" then
                        local progressStr = formatRowSuffix and formatRowSuffix(row, achSummary) or ""
                        local critFs = FontManager:CreateFontString(content, "body", "OVERLAY")
                        critFs:SetPoint("TOPLEFT", critAnchor, critPoint, 0, critY)
                        critFs:SetPoint("RIGHT", content, "RIGHT", -CONTENT_INSET, 0)
                        critFs:SetJustifyH("LEFT")
                        critFs:SetWordWrap(true)
                        if completed then
                            critFs:SetTextColor(completeR, completeG, completeB)
                        else
                            critFs:SetTextColor(bodyR, bodyG, bodyB)
                        end
                        critFs:SetText((criteriaName or "") .. progressStr)
                        addDetailElement(critFs)
                        critAnchor = critFs
                        critPoint = "BOTTOMLEFT"
                        critY = -SECTION_GAP
                    end
                end
                lastAnchor = critAnchor
                lastPoint = "BOTTOMLEFT"
                lastY = -SECTION_GAP
            end)
        end

        local totalH = math.abs(lastY) + PADDING
        child:SetHeight(math.max(totalH, 1))
    end

    return panel
end

-- ============================================================================
-- SUB-TAB BUTTONS
-- ============================================================================

local SUB_TABS = {
    { key = "recent", label = (ns.L and ns.L["COLLECTIONS_SUBTAB_RECENT"]) or "Recent", icon = "Interface\\Icons\\INV_Misc_Note_01" },
    { key = "achievements", label = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements", icon = "Interface\\Icons\\Achievement_General" },
    { key = "mounts", label = (ns.L and ns.L["CATEGORY_MOUNTS"]) or MOUNTS or "Mounts", icon = "Interface\\Icons\\Ability_Mount_RidingHorse" },
    { key = "pets", label = (ns.L and ns.L["CATEGORY_PETS"]) or PETS or "Pets", icon = "Interface\\Icons\\INV_Box_PetCarrier_01" },
    { key = "toys", label = (ns.L and ns.L["CATEGORY_TOYS"]) or (TOY_BOX or "Toys"), icon = "Interface\\Icons\\INV_Misc_Toy_07" },
}

-- Plans category bar ile birebir aynı (catBtnHeight=40, catBtnSpacing=8, DEFAULT_CAT_BTN_WIDTH=150)
local SUBTAB_BTN_HEIGHT = 40
local SUBTAB_BTN_SPACING = 8
local SUBTAB_ICON_SIZE = 28
local SUBTAB_ICON_LEFT = 10
local SUBTAB_ICON_TEXT_GAP = 8
local SUBTAB_TEXT_RIGHT = 10
local SUBTAB_DEFAULT_WIDTH = 150

function M.CreateSubTabBar(parent, onTabSelect)
    local bar = Factory:CreateContainer(parent, 400, SUBTAB_BTN_HEIGHT, false)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)

    -- Plans gibi metne göre buton genişliği hesapla
    local btnWidths = {}
    for i = 1, #SUB_TABS do
        local tabInfo = SUB_TABS[i]
        local tempFs = FontManager:CreateFontString(bar, "body", "OVERLAY")
        tempFs:SetText(tabInfo.label)
        local textW = tempFs:GetStringWidth() or 0
        tempFs:Hide()
        local needed = SUBTAB_ICON_LEFT + SUBTAB_ICON_SIZE + SUBTAB_ICON_TEXT_GAP + textW + SUBTAB_TEXT_RIGHT
        btnWidths[i] = math.max(needed, SUBTAB_DEFAULT_WIDTH)
    end

    local buttons = {}
    local xPos = 0
    local btnHeight = SUBTAB_BTN_HEIGHT
    local spacing = SUBTAB_BTN_SPACING

    local accentColor = COLORS.accent
    for i = 1, #SUB_TABS do
        local tabInfo = SUB_TABS[i]
        local btnWidth = btnWidths[i]
        local btn = ns.UI.Factory:CreateButton(bar, btnWidth, btnHeight)
        btn:SetPoint("TOPLEFT", xPos, 0)
        btn._tabKey = tabInfo.key

        if ApplyVisuals then
            ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
        end
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end

        -- Active indicator bar (main window tab ile aynı: alt çizgi vurgusu)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
        activeBar:SetAlpha(0)
        btn.activeBar = activeBar

        local btnIcon = btn:CreateTexture(nil, "ARTWORK")
        btnIcon:SetSize(SUBTAB_ICON_SIZE - 2, SUBTAB_ICON_SIZE - 2)
        btnIcon:SetPoint("LEFT", SUBTAB_ICON_LEFT, 0)
        btnIcon:SetTexture(tabInfo.icon)
        btnIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
        btnText:SetPoint("LEFT", btnIcon, "RIGHT", SUBTAB_ICON_TEXT_GAP, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", -SUBTAB_TEXT_RIGHT, 0)
        btnText:SetText(tabInfo.label)
        btnText:SetJustifyH("LEFT")
        btnText:SetWordWrap(false)
        btnText:SetTextColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        btn._text = btnText

        btn:SetScript("OnClick", function()
            if onTabSelect then onTabSelect(tabInfo.key) end
        end)

        if UpdateBorderColor then
            btn:SetScript("OnEnter", function(self)
                if self._active then return end
                UpdateBorderColor(self, {accentColor[1] * 1.2, accentColor[2] * 1.2, accentColor[3] * 1.2, 0.9})
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                UpdateBorderColor(self, {accentColor[1], accentColor[2], accentColor[3], 0.6})
            end)
        else
            btn:SetScript("OnEnter", function(self)
                if self._active then return end
                if self.SetBackdropColor then self:SetBackdropColor(0.10, 0.10, 0.12, 0.95) end
            end)
            btn:SetScript("OnLeave", function(self)
                if self._active then return end
                if self.SetBackdropColor then self:SetBackdropColor(0.12, 0.12, 0.15, 1) end
            end)
        end

        buttons[tabInfo.key] = btn
        xPos = xPos + btnWidths[i] + spacing
    end

    bar.buttons = buttons

    function bar:SetActiveTab(key)
        local acc = COLORS.accent
        for k, btn in pairs(buttons) do
            if k == key then
                btn._active = true
                if btn.activeBar then btn.activeBar:SetAlpha(1) end
                if ApplyVisuals then
                    ApplyVisuals(btn, {acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1}, {acc[1], acc[2], acc[3], 1})
                end
                if btn._text then
                    btn._text:SetTextColor(1, 1, 1)
                    local font, size = btn._text:GetFont()
                    if font and size then btn._text:SetFont(font, size, "OUTLINE") end
                end
                if UpdateBorderColor then UpdateBorderColor(btn, {acc[1], acc[2], acc[3], 1}) end
                if btn.SetBackdropColor then btn:SetBackdropColor(acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1) end
            else
                btn._active = false
                if btn.activeBar then btn.activeBar:SetAlpha(0) end
                if ApplyVisuals then
                    ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1})
                end
                if btn._text then
                    btn._text:SetTextColor(0.7, 0.7, 0.7)
                    local font, size = btn._text:GetFont()
                    if font and size then btn._text:SetFont(font, size, "") end
                end
                if UpdateBorderColor then UpdateBorderColor(btn, {acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1}) end
                if btn.SetBackdropColor then btn:SetBackdropColor(0.12, 0.12, 0.15, 1) end
            end
        end
    end

    return bar
end

-- ============================================================================
-- MOUNT DATA BUILDER (Source Grouped) — From global collection data (DB); fallback to API
-- ============================================================================

-- Pure API: hide-decision is delegated to C_MountJournal.GetMountInfoByID().shouldHideOnChar.
-- Placeholder/ability mounts (e.g. "Soar", "Unstable Rocket") are flagged hidden by the API
-- on characters that cannot use them, so no addon-side blacklist is required.

function M.BuildGroupedMountData(searchText, showCollected, showUncollected, optionalMounts)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for ci = 1, #SD.SOURCE_CATEGORIES do
        local cat = SD.SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end

    local function classify(src)
        return SD.ClassifyMountSourceCached(classifyCache, src)
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local idx = nameIndex[catKey]
        local pos = idx and idx[name]
        if pos then grouped[catKey][pos].isCollected = true end
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    -- Use optionalMounts when provided and non-empty to avoid repeated DB/API calls
    local allMounts
    if optionalMounts and #optionalMounts > 0 then
        allMounts = optionalMounts
    else
        allMounts = (WarbandNexus.GetAllMountsData and WarbandNexus:GetAllMountsData()) or {}
    end
    local useCache = #allMounts > 0

    -- Tab tıklandığında sadece DB/cache kullan; API çağrısı yapma (FPS ve performans).
    local query = SafeLower(searchText)
    local totalCount = 0
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    if useCache then
        for i = 1, #allMounts do
            local d = allMounts[i]
            if d and d.id then
                -- Live-query shouldHideOnChar: DB value may be stale from another character
                local shouldSkip = false
                if d.shouldHideOnChar then
                    shouldSkip = true  -- default to DB value
                    if C_MountJournal and C_MountJournal.GetMountInfoByID then
                        local _, _, _, _, _, _, _, _, _, sh = C_MountJournal.GetMountInfoByID(d.id)
                        if issecretvalue and sh and issecretvalue(sh) then
                            shouldSkip = false  -- secret = treat as visible
                        elseif sh == false then
                            shouldSkip = false  -- API says visible on this character
                        end
                    end
                end
                if not shouldSkip then
                    local name = d.name or tostring(d.id)
                    -- Pure API: isCollected from cache (no API call here).
                    local isCollected = (d.isCollected == true) or (d.collected == true)
                    if (showC and isCollected) or (showU and not isCollected) then
                        if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                            local sourceText = d.source or ""
                            local catKey = classify(d.sourceType)
                            if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                            if not nameAlreadyInCategory(catKey, name) then
                                addToCategory(catKey, {
                                    id = d.id,
                                    name = name,
                                    icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                                    source = sourceText,
                                    sourceType = d.sourceType,
                                    description = d.description,
                                    creatureDisplayID = d.creatureDisplayID,
                                    isCollected = isCollected,
                                })
                                totalCount = totalCount + 1
                            elseif isCollected then
                                updateCollectedInCategory(catKey, name, true)
                            end
                        end
                    end
                end
            end
        end
    else
        local mountIDs = (C_MountJournal and C_MountJournal.GetMountIDs and C_MountJournal.GetMountIDs()) or {}
        if #mountIDs == 0 then return grouped, 0 end
        for i = 1, #mountIDs do
            local mountID = mountIDs[i]
            -- Skip hidden mounts: live-query shouldHideOnChar (10th return, API is character-specific)
            local shouldHide = false
            local liveSourceType = nil
            if C_MountJournal and C_MountJournal.GetMountInfoByID then
                local _, _, _, _, _, st, _, _, _, sh = C_MountJournal.GetMountInfoByID(mountID)
                if issecretvalue and sh and issecretvalue(sh) then
                    -- secret = treat as visible
                elseif sh == true then
                    shouldHide = true
                end
                if not (issecretvalue and st and issecretvalue(st)) then liveSourceType = st end
            end
            if not shouldHide then
            local isCollected = M.SafeGetMountCollected(mountID)
            if (showC and isCollected) or (showU and not isCollected) then
                local meta = WarbandNexus:ResolveCollectionMetadata("mount", mountID)
                local name = (meta and meta.name) or ""
                if not name and C_MountJournal and C_MountJournal.GetMountInfoByID then
                    local n = C_MountJournal.GetMountInfoByID(mountID)
                    if n and not (issecretvalue and issecretvalue(n)) then name = n end
                end
                if not name then name = tostring(mountID) end
                if query == "" or SafeLower(name):find(query, 1, true) then
                    local sourceText = meta and meta.source or ""
                    local creatureDisplayID, description, src = M.SafeGetMountInfoExtra(mountID)
                    if sourceText == "" then sourceText = src or "" end
                    local icon = (meta and meta.icon) or "Interface\\Icons\\Ability_Mount_RidingHorse"
                    if not icon and C_MountJournal and C_MountJournal.GetMountInfoByID then
                        local _, _, ic = C_MountJournal.GetMountInfoByID(mountID)
                        if ic and not (issecretvalue and issecretvalue(ic)) then icon = ic end
                    end
                    local sourceTypeInt = (meta and meta.sourceType) or liveSourceType
                    local catKey = classify(sourceTypeInt)
                    if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                    if not nameAlreadyInCategory(catKey, name) then
                        addToCategory(catKey, {
                            id = mountID,
                            name = name,
                            icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                            source = sourceText,
                            sourceType = sourceTypeInt,
                            description = (meta and meta.description) or description or "",
                            creatureDisplayID = creatureDisplayID,
                            isCollected = isCollected,
                        })
                        totalCount = totalCount + 1
                    elseif isCollected then
                        updateCollectedInCategory(catKey, name, true)
                    end
                end
            end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b)
            return SafeLower(a.name) < SafeLower(b.name)
        end)
    end

    return grouped, totalCount
end

-- Chunked build: process mounts in small chunks per frame so no single frame freezes for ~1s.
function M.RunChunkedMountBuild(allMounts, searchText, showCollected, showUncollected, drawGen, contentFrame, onComplete)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for ci = 1, #SD.SOURCE_CATEGORIES do
        local cat = SD.SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end
    local function classify(src) return SD.ClassifyMountSourceCached(classifyCache, src) end
    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end
    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local pos = nameIndex[catKey] and nameIndex[catKey][name]
        if pos then grouped[catKey][pos].isCollected = true end
    end
    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local startIdx = 1
    local total = #allMounts

    local function processChunk()
        if M.state._mountsDrawGen ~= drawGen or M.state.currentSubTab ~= "mounts" then return end
        if not contentFrame or not contentFrame:IsVisible() then return end
        local limit = math.min(startIdx + RUN_CHUNK_SIZE - 1, total)
        for i = startIdx, limit do
            local d = allMounts[i]
            if d and d.id then
                -- Live-query shouldHideOnChar: DB value may be stale from another character
                local shouldSkip = false
                if d.shouldHideOnChar then
                    shouldSkip = true
                    if C_MountJournal and C_MountJournal.GetMountInfoByID then
                        local _, _, _, _, _, _, _, _, _, sh = C_MountJournal.GetMountInfoByID(d.id)
                        if issecretvalue and sh and issecretvalue(sh) then
                            shouldSkip = false
                        elseif sh == false then
                            shouldSkip = false
                        end
                    end
                end
                if not shouldSkip then
                local name = d.name or tostring(d.id)
                local isCollected = (d.isCollected == true) or (d.collected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                        local sourceText = d.source or ""
                        local catKey = classify(d.sourceType)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = d.id,
                                name = name,
                                icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
                                source = sourceText,
                                sourceType = d.sourceType,
                                description = d.description,
                                creatureDisplayID = d.creatureDisplayID,
                                isCollected = isCollected,
                            })
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
        end
        startIdx = limit + 1
        if startIdx > total then
            for _, items in pairs(grouped) do
                table.sort(items, function(a, b) return SafeLower(a.name) < SafeLower(b.name) end)
            end
            onComplete(grouped)
        else
            C_Timer.After(0, processChunk)
        end
    end
    C_Timer.After(0, processChunk)
end

-- Chunked build for pets (same idea as mounts).
function M.RunChunkedPetBuild(allPets, searchText, showCollected, showUncollected, drawGen, contentFrame, onComplete)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for ci = 1, #SD.PET_SOURCE_CATEGORIES do
        local cat = SD.PET_SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end
    local function classify(src) return SD.ClassifyPetSourceCached(classifyCache, src) end
    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end
    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local pos = nameIndex[catKey] and nameIndex[catKey][name]
        if pos then grouped[catKey][pos].isCollected = true end
    end
    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    local startIdx = 1
    local total = #allPets

    local function processChunk()
        if M.state._petDrawGen ~= drawGen or M.state.currentSubTab ~= "pets" then return end
        if not contentFrame or not contentFrame:IsVisible() then return end
        local limit = math.min(startIdx + RUN_CHUNK_SIZE - 1, total)
        for i = startIdx, limit do
            local d = allPets[i]
            if d and d.id then
                local name = d.name or tostring(d.id)
                local isCollected = (d.isCollected == true) or (d.collected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                        local sourceText = d.source or ""
                        local catKey = classify(d.sourceTypeIndex)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = d.id,
                                name = name,
                                icon = d.icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                sourceTypeIndex = d.sourceTypeIndex,
                                description = d.description,
                                creatureDisplayID = d.creatureDisplayID,
                                isCollected = isCollected,
                            })
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
        startIdx = limit + 1
        if startIdx > total then
            for _, items in pairs(grouped) do
                table.sort(items, function(a, b) return SafeLower(a.name) < SafeLower(b.name) end)
            end
            onComplete(grouped)
        else
            C_Timer.After(0, processChunk)
        end
    end
    C_Timer.After(0, processChunk)
end

-- BuildGroupedPetData: same structure as mounts, uses C_PetJournal / GetAllPetsData. Pet-specific categories (petbattle, puzzle).
function M.BuildGroupedPetData(searchText, showCollected, showUncollected, optionalPets)
    local grouped = {}
    local nameIndex = {}
    local classifyCache = {}
    for ci = 1, #SD.PET_SOURCE_CATEGORIES do
        local cat = SD.PET_SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end

    local function classify(src)
        return SD.ClassifyPetSourceCached(classifyCache, src)
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function updateCollectedInCategory(catKey, name, isCollected)
        if not isCollected or not name then return end
        local idx = nameIndex[catKey]
        local pos = idx and idx[name]
        if pos then grouped[catKey][pos].isCollected = true end
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    local allPets
    if optionalPets and #optionalPets > 0 then
        allPets = optionalPets
    else
        allPets = (WarbandNexus.GetAllPetsData and WarbandNexus:GetAllPetsData()) or {}
    end
    local useCache = #allPets > 0

    -- Tab tıklandığında sadece DB/cache kullan; API çağrısı yapma.
    local query = SafeLower(searchText)
    local totalCount = 0
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    if useCache then
        for i = 1, #allPets do
            local d = allPets[i]
            if not d or not d.id then
            else
                local name = d.name or tostring(d.id)
                local isCollected = (d.isCollected == true) or (d.collected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                        local sourceText = d.source or ""
                        local catKey = classify(d.sourceTypeIndex)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = d.id,
                                name = name,
                                icon = d.icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                sourceTypeIndex = d.sourceTypeIndex,
                                description = d.description,
                                creatureDisplayID = d.creatureDisplayID,
                                isCollected = isCollected,
                            })
                            totalCount = totalCount + 1
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
    else
        if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end
        if not InCombatLockdown() then
            pcall(function()
                if C_PetJournal.ClearSearchFilter then C_PetJournal.ClearSearchFilter() end
                if C_PetJournal.SetFilterChecked then
                    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
                    C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
                end
            end)
        end
        local numPets = C_PetJournal.GetNumPets and C_PetJournal.GetNumPets() or 0
        if numPets == 0 then return grouped, 0 end
        for i = 1, numPets do
            local _, speciesID = C_PetJournal.GetPetInfoByIndex(i)
            if speciesID then
                local isCollected = M.SafeGetPetCollected(speciesID)
                if (showC and isCollected) or (showU and not isCollected) then
                    local meta = WarbandNexus:ResolveCollectionMetadata("pet", speciesID)
                    local name = (meta and meta.name) or ""
                    if not name and C_PetJournal.GetPetInfoBySpeciesID then
                        local n = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                        if n and not (issecretvalue and issecretvalue(n)) then name = n end
                    end
                    if not name then name = tostring(speciesID) end
                    if query == "" or SafeLower(name):find(query, 1, true) then
                        local sourceText = meta and meta.source or ""
                        local creatureDisplayID, description, src = M.SafeGetPetInfoExtra(speciesID)
                        if sourceText == "" then sourceText = src or "" end
                        local icon = (meta and meta.icon) or "Interface\\Icons\\INV_Box_PetCarrier_01"
                        if not icon and C_PetJournal.GetPetInfoBySpeciesID then
                            local _, ic = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                            if ic and not (issecretvalue and issecretvalue(ic)) then icon = ic end
                        end
                        local sourceTypeIndex = meta and meta.sourceTypeIndex or nil
                        local catKey = classify(sourceTypeIndex)
                        if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                        if not nameAlreadyInCategory(catKey, name) then
                            addToCategory(catKey, {
                                id = speciesID,
                                name = name,
                                icon = icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
                                source = sourceText,
                                sourceTypeIndex = sourceTypeIndex,
                                description = (meta and meta.description) or description or "",
                                creatureDisplayID = creatureDisplayID,
                                isCollected = isCollected,
                            })
                            totalCount = totalCount + 1
                        elseif isCollected then
                            updateCollectedInCategory(catKey, name, true)
                        end
                    end
                end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b)
            return SafeLower(a.name) < SafeLower(b.name)
        end)
    end

    return grouped, totalCount
end

-- Toys: grouped by C_ToyBox source type. Returns { [catKey] = items[] } filtered by search and owned/missing.
function M.GetFilteredToysGrouped(searchText, showCollected, showUncollected)
    local sourceGrouped = (WarbandNexus.GetToysDataGroupedBySourceType and WarbandNexus:GetToysDataGroupedBySourceType()) or {}
    local grouped = {}
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    for sourceIndex, group in pairs(sourceGrouped) do
        local catKey = SD.SOURCE_INDEX_TO_TOY_CAT[sourceIndex] or "unknown"
        if not grouped[catKey] then grouped[catKey] = {} end
        local items = group.items or {}
        for i = 1, #items do
            local item = items[i]
            if item and item.id then
                local isCollected = (item.collected == true) or (item.isCollected == true)
                if (showC and isCollected) or (showU and not isCollected) then
                    local name = item.name or tostring(item.id)
                    if query == "" or (SafeLower(name):find(query, 1, true)) then
                        grouped[catKey][#grouped[catKey] + 1] = item
                    end
                end
            end
        end
    end
    return grouped
end

function M.BuildGroupedToyData(searchText, showCollected, showUncollected, optionalToys)
    local grouped = {}
    local nameIndex = {}
    for ci = 1, #SD.TOY_SOURCE_CATEGORIES do
        local cat = SD.TOY_SOURCE_CATEGORIES[ci]
        grouped[cat.key] = {}
        nameIndex[cat.key] = {}
    end

    local function nameAlreadyInCategory(catKey, name)
        if not name then return false end
        local idx = nameIndex[catKey]
        return idx and idx[name] ~= nil
    end

    local function addToCategory(catKey, entry)
        local list = grouped[catKey]
        list[#list + 1] = entry
        nameIndex[catKey][entry.name] = #list
    end

    local allToys = (optionalToys and #optionalToys > 0) and optionalToys or (WarbandNexus.GetAllToysData and WarbandNexus:GetAllToysData()) or {}
    local query = SafeLower(searchText)
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)

    local resolveSourceIndex = (WarbandNexus.GetToySourceTypeIndexForItem and function(id)
        return WarbandNexus:GetToySourceTypeIndexForItem(id)
    end) or function() return nil end

    for i = 1, #allToys do
        local d = allToys[i]
        if d and d.id then
            local name = d.name or tostring(d.id)
            local isCollected = (d.isCollected == true) or (d.collected == true)
            if (showC and isCollected) or (showU and not isCollected) then
                if query == "" or (name and SafeLower(name):find(query, 1, true)) then
                    local sourceTypeIndex = d.sourceTypeIndex or resolveSourceIndex(d.id)
                    local catKey = SD.ClassifyBattlePetByAPI(nil, sourceTypeIndex)
                    if not grouped[catKey] then grouped[catKey] = {} nameIndex[catKey] = {} end
                    if not nameAlreadyInCategory(catKey, name) then
                        addToCategory(catKey, {
                            id = d.id,
                            name = name,
                            icon = d.icon or DEFAULT_ICON_TOY,
                            source = d.source or "",
                            sourceTypeIndex = sourceTypeIndex,
                            description = d.description or "",
                            isCollected = isCollected,
                            collected = isCollected,
                        })
                    end
                end
            end
        end
    end

    for _, items in pairs(grouped) do
        table.sort(items, function(a, b) return SafeLower(a.name) < SafeLower(b.name) end)
    end
    return grouped
end

-- ============================================================================
-- DRAW MOUNTS CONTENT
-- Layout: LEFT = Header + Rows (scroll list), RIGHT = Model viewer (vertical, text inside same frame).
-- All in Factory containers; responsive width/height from window.
-- ============================================================================

local CONTENT_GAP = LAYOUT.CARD_GAP or 8

-- Per–sub-tab title block inside contentFrame (below search); reduces inner list/detail height.
local COLLECTIONS_SUBTAB_HEADER_H = 44
local COLLECTIONS_SUBTAB_HEADER_GAP = 8

local CONTENT_HEADER_LOCALE_KEYS = {
    achievements = { title = "COLLECTIONS_CONTENT_TITLE_ACHIEVEMENTS", sub = "COLLECTIONS_CONTENT_SUB_ACHIEVEMENTS" },
    mounts = { title = "COLLECTIONS_CONTENT_TITLE_MOUNTS", sub = "COLLECTIONS_CONTENT_SUB_MOUNTS" },
    pets = { title = "COLLECTIONS_CONTENT_TITLE_PETS", sub = "COLLECTIONS_CONTENT_SUB_PETS" },
    toys = { title = "COLLECTIONS_CONTENT_TITLE_TOYS", sub = "COLLECTIONS_CONTENT_SUB_TOYS" },
    recent = { title = "COLLECTIONS_CONTENT_TITLE_RECENT", sub = "COLLECTIONS_CONTENT_SUB_RECENT" },
}

function M.ApplyCollectionsContentHeader(contentFrame, tabKey, chFull)
    local loc = ns.L
    local keys = CONTENT_HEADER_LOCALE_KEYS[tabKey]
    local titlePlain = (keys and loc and loc[keys.title])
        or (tabKey == "achievements" and ((loc and loc["CATEGORY_ACHIEVEMENTS"]) or "Achievements"))
        or (tabKey == "mounts" and ((loc and loc["CATEGORY_MOUNTS"]) or "Mounts"))
        or (tabKey == "pets" and ((loc and loc["CATEGORY_PETS"]) or "Pets"))
        or (tabKey == "toys" and ((loc and loc["CATEGORY_TOYS"]) or "Toys"))
        or (tabKey == "recent" and ((loc and loc["COLLECTIONS_SUBTAB_RECENT"]) or "Recent"))
        or tostring(tabKey or "")
    local subPlain = (keys and loc and loc[keys.sub]) or ""

    local hdr = M.state._collectionsContentSubHeader
    if not hdr then
        hdr = Factory:CreateContainer(contentFrame, 120, COLLECTIONS_SUBTAB_HEADER_H, false)
        hdr._title = FontManager:CreateFontString(hdr, "header", "OVERLAY")
        hdr._title:SetPoint("TOPLEFT", hdr, "TOPLEFT", 4, -4)
        hdr._title:SetJustifyH("LEFT")
        hdr._subtitle = FontManager:CreateFontString(hdr, "subtitle", "OVERLAY")
        hdr._subtitle:SetPoint("TOPLEFT", hdr._title, "BOTTOMLEFT", 0, -2)
        hdr._subtitle:SetPoint("TOPRIGHT", hdr, "TOPRIGHT", -4, 0)
        hdr._subtitle:SetJustifyH("LEFT")
        hdr._subtitle:SetWordWrap(false)
        hdr._subtitle:SetNonSpaceWrap(false)
        hdr._subtitle:SetMaxLines(1)
        hdr._subtitle:SetTextColor(1, 1, 1, 1)
        M.state._collectionsContentSubHeader = hdr
    end
    hdr:SetParent(contentFrame)
    hdr:ClearAllPoints()
    hdr:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    hdr:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
    hdr:SetHeight(COLLECTIONS_SUBTAB_HEADER_H)
    local r, g, b = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3]
    local hexColor = format("%02x%02x%02x", r * 255, g * 255, b * 255)
    hdr._title:SetText("|cff" .. hexColor .. titlePlain .. "|r")
    hdr._subtitle:SetText(subPlain)
    hdr._subtitle:SetShown(subPlain ~= "")
    hdr:SetFrameLevel((contentFrame:GetFrameLevel() or 0) + 3)
    hdr:Show()

    local headerBlockH = COLLECTIONS_SUBTAB_HEADER_H + COLLECTIONS_SUBTAB_HEADER_GAP
    local innerCh = math.max(80, (chFull or 400) - headerBlockH)
    return headerBlockH, innerCh
end

-- Result container: only one sub-tab's content is visible. Hide all result-area frames before drawing current tab.
function M.HideAllCollectionsResultFrames()
    if M.state.loadingPanel then M.state.loadingPanel:Hide() end
    if M.state.mountListContainer then M.state.mountListContainer:Hide() end
    if M.state.mountListScrollBarContainer then M.state.mountListScrollBarContainer:Hide() end
    if M.state.viewerContainer then M.state.viewerContainer:Hide() end
    if M.state.modelViewer then
        M.state.modelViewer:SetMount(nil)
        M.state.modelViewer:SetPet(nil)
        M.state.modelViewer:SetMountInfo(nil)
        M.state.modelViewer:SetPetInfo(nil)
        M.state.modelViewer:Hide()
    end
    if M.state.petListContainer then M.state.petListContainer:Hide() end
    if M.state.petListScrollBarContainer then M.state.petListScrollBarContainer:Hide() end
    if M.state.achievementListContainer then M.state.achievementListContainer:Hide() end
    if M.state.achievementListScrollBarContainer then M.state.achievementListScrollBarContainer:Hide() end
    if M.state.achievementDetailContainer then M.state.achievementDetailContainer:Hide() end
    if M.state.toyListContainer then M.state.toyListContainer:Hide() end
    if M.state.toyListScrollBarContainer then M.state.toyListScrollBarContainer:Hide() end
    if M.state.toyDetailContainer then M.state.toyDetailContainer:Hide() end
    if M.state.toyDetailScrollBarContainer then M.state.toyDetailScrollBarContainer:Hide() end
    if M.state.recentTabPanel then M.state.recentTabPanel:Hide() end
    if M.state.collectionRightColumn then M.state.collectionRightColumn:Hide() end
    if M.state.collectionProgressFrame then M.state.collectionProgressFrame:Hide() end
    if M.state._collectionsContentSubHeader then M.state._collectionsContentSubHeader:Hide() end
end

function M.ResetCollectionsListScrollPositions()
    local scrollFrames = {
        M.state.mountListScrollFrame,
        M.state.petListScrollFrame,
        M.state.toyListScrollFrame,
        M.state.achievementListScrollFrame,
    }
    for i = 1, #scrollFrames do
        local sf = scrollFrames[i]
        if sf and sf.SetVerticalScroll then
            sf:SetVerticalScroll(0)
        end
    end
end

M.CONTENT_GAP = CONTENT_GAP
M.COLLECTED_COLOR = "|cff33e533"
M.DEFAULT_ICON_MOUNT = "Interface\\Icons\\Ability_Mount_RidingHorse"
M.DEFAULT_ICON_PET = "Interface\\Icons\\INV_Box_PetCarrier_01"
M.DEFAULT_ICON_TOY = "Interface\\Icons\\INV_Misc_Toy_07"
M.DEFAULT_ICON_ACHIEVEMENT = "Interface\\Icons\\Achievement_General"

