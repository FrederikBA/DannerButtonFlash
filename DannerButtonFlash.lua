--------------------------------------------------------------------------------
--  DannerButtonFlash
--
--  WoW Forever port of jButtonFlash (jwldnr, backported by fondlez): plays a
--  short star burst over an action button when it is pressed, like the old
--  SnowFallKeyPress highlight.
--
--  WoW Forever runs the 12.1 engine, so the modern API applies. Presses reach
--  us two ways:
--    * Blizzard's own binding commands (ActionButtonDown, MultiActionButtonDown,
--      PetActionButtonDown) -- the stock bars without an action bar addon.
--      These call the action directly and never run the button's click
--      scripts, so they are hooked as functions.
--    * Clicks -- mouse presses, and keybinds routed through
--      SetOverrideBindingClick. EllesmereUI Action Bars (EABButton<slot>) and
--      Bartender4 dispatch every keybind this way, so a PostClick hook on the
--      button covers both key and mouse for them.
--
--  Taint-safe: post-hooks only (hooksecurefunc / HookScript), our own flash
--  frame, and per-button state kept outside the secure button tables.
--------------------------------------------------------------------------------

local TEXTURE = [[Interface\Cooldown\star4]]
local TEXTURE_OFFSET = 3   -- px the burst extends past each button edge
local BURST_SCALE = 1.5    -- instant pop size
local SHRINK_TIME = 0.3    -- shrink + spin duration
local SPIN_DEGREES = 90

-- Button families hooked for clicks: name prefix -> highest index. Missing
-- names are skipped, so bars that are not built cost nothing.
local CLICK_BUTTONS = {
    ActionButton = 12,
    MultiBarBottomLeftButton = 12,
    MultiBarBottomRightButton = 12,
    MultiBarRightButton = 12,
    MultiBarLeftButton = 12,
    MultiBar5Button = 12,
    MultiBar6Button = 12,
    MultiBar7Button = 12,
    StanceButton = 10,
    PetActionButton = 10,
    EABButton = 180,       -- EllesmereUI Action Bars: one per action slot (15 pages)
    BT4Button = 180,       -- Bartender4
    BT4PetButton = 10,
    BT4StanceButton = 10,
}

-- Per-button state lives outside the (secure) button tables.
local hooked = setmetatable({}, { __mode = "k" })
local downSeen = setmetatable({}, { __mode = "k" })

--------------------------------------------------------------------------------
--  Flash
--------------------------------------------------------------------------------
local flashFrame, flashAnim

local function SetScaleAnim(anim, x, y)
    if anim.SetScaleTo then
        anim:SetScaleFrom(1, 1)
        anim:SetScaleTo(x, y)
    else
        anim:SetScale(x, y)
    end
end

local function CreateFlash()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("TOOLTIP")

    local texture = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    texture:SetTexture(TEXTURE)
    texture:SetAlpha(0)
    texture:SetAllPoints(frame)
    texture:SetBlendMode("ADD")

    local group = texture:CreateAnimationGroup()

    local alpha = group:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0)
    alpha:SetOrder(1)

    local pop = group:CreateAnimation("Scale")
    SetScaleAnim(pop, BURST_SCALE, BURST_SCALE)
    pop:SetDuration(0)
    pop:SetOrder(1)

    local shrink = group:CreateAnimation("Scale")
    SetScaleAnim(shrink, 0.01, 0.01) -- ~0; avoids a zero scale
    shrink:SetDuration(SHRINK_TIME)
    shrink:SetOrder(2)

    local spin = group:CreateAnimation("Rotation")
    spin:SetDegrees(SPIN_DEGREES)
    spin:SetDuration(SHRINK_TIME)
    spin:SetOrder(2)

    flashFrame, flashAnim = frame, group
end

local function AnimateButton(button)
    if not button or not flashFrame or not button:IsVisible() then return end

    flashFrame:ClearAllPoints()
    flashFrame:SetPoint("TOPLEFT", button, "TOPLEFT", -TEXTURE_OFFSET, TEXTURE_OFFSET)
    flashFrame:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", TEXTURE_OFFSET, -TEXTURE_OFFSET)

    flashAnim:Stop()
    flashAnim:Play()
end

--------------------------------------------------------------------------------
--  Blizzard binding commands
--------------------------------------------------------------------------------
local function InPetBattle()
    return C_PetBattles and C_PetBattles.IsInBattle and C_PetBattles.IsInBattle() and PetBattleFrame ~= nil
end

local function OnActionButtonDown(id)
    if not id or InPetBattle() then return end
    local button = GetActionButtonForID and GetActionButtonForID(id) or _G["ActionButton" .. id]
    AnimateButton(button)
end

local function OnMultiActionButtonDown(bar, id)
    if not bar or not id then return end
    AnimateButton(_G[bar .. "Button" .. id])
end

local function OnPetActionButtonDown(id)
    if not id then return end
    AnimateButton(_G["PetActionButton" .. id])
end

local function HookBindingCommands()
    if ActionButtonDown then hooksecurefunc("ActionButtonDown", OnActionButtonDown) end
    if MultiActionButtonDown then hooksecurefunc("MultiActionButtonDown", OnMultiActionButtonDown) end
    if PetActionButtonDown then hooksecurefunc("PetActionButtonDown", OnPetActionButtonDown) end
end

--------------------------------------------------------------------------------
--  Clicks (mouse + override-click keybinds)
--------------------------------------------------------------------------------
-- A button registered for both edges clicks twice per press (down, then up);
-- one registered for the up edge only clicks once with down=false. Flash on
-- the first edge of each press.
local function Button_PostClick(button, _, down)
    if down then
        downSeen[button] = true
        AnimateButton(button)
    elseif downSeen[button] then
        downSeen[button] = nil
    else
        AnimateButton(button)
    end
end

local function HookClickButtons()
    if InCombatLockdown() then return false end
    for prefix, count in pairs(CLICK_BUTTONS) do
        for i = 1, count do
            local button = _G[prefix .. i]
            if button and not hooked[button] and button.HookScript then
                hooked[button] = true
                button:HookScript("PostClick", Button_PostClick)
            end
        end
    end
    return true
end

--------------------------------------------------------------------------------
--  Events
--------------------------------------------------------------------------------
-- Action bar addons build (and later add) their buttons after login, so the
-- click hooks are re-scanned whenever bars or bindings may have changed.
local pendingScan = false
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        CreateFlash()
        HookBindingCommands()
        self:RegisterEvent("PLAYER_ENTERING_WORLD")
        self:RegisterEvent("UPDATE_BINDINGS")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        pendingScan = not HookClickButtons()
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pendingScan then pendingScan = not HookClickButtons() end
    else
        pendingScan = not HookClickButtons()
    end
end)
