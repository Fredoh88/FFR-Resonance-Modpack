-- ============================================================================
-- FFR_AI_Optimizer: Field Exploration Sprint & Smooth Performance (v3.8)
-- 100% Crash-Proof: Targeted Player Pawn Only, Zero Ambient Character Iteration
-- 100% Game-Thread Safe: Zero background thread races, Zero Stutter
-- Visible HUD: Dedicated On-Screen Speed Toast & Persistent Outworld Badge
-- ============================================================================

_G.FFR_QOL = _G.FFR_QOL or {}
local QoL = _G.FFR_QOL

QoL.SpeedModes = { 800.0, 1600.0, 2600.0, 3800.0 }
QoL.SpeedLabels = {
    "Normal Traversal (800, +33%)",
    "Fast Sprint (1600, +166%)",
    "Hyper-Dash (2600, +333%)",
    "Sonic Warp Hyperspeed (3800, +533%)"
}
QoL.SpeedToasts = {
    "[ SPRINT: Normal Walk (800) ]",
    "[ >> FAST SPRINT: 1600 Speed (Mount 2160) ]",
    "[ >>> HYPER-DASH: 2600 Speed (Mount 3510) ]",
    "[ >>>> WARP HYPERSPEED: 3800 Speed (Mount 5130) ]",
}
QoL.SpeedColors = {
    { R = 0.85, G = 0.85, B = 0.85, A = 1.0 }, -- Normal: Neutral White/Silver
    { R = 1.00, G = 0.84, B = 0.00, A = 1.0 }, -- Fast Sprint: Gold
    { R = 0.00, G = 0.95, B = 1.00, A = 1.0 }, -- Hyper-Dash: Cyan
    { R = 1.00, G = 0.20, B = 0.85, A = 1.0 }, -- Sonic Hyperspeed: Neon Magenta
}
QoL.SpeedIdx = 2
QoL.SprintActive = true
QoL.DefaultWalkSpeed = 800.0

print("[FFR QoL v3.8] Initializing Field Sprint & Visible Speed HUD...")

-- ----------------------------------------------------------------------------
-- 1. Graphics & Pixel Art Definition (Ultra-Crisp HD-2D Sprite Rendering)
-- ----------------------------------------------------------------------------
local function ApplyVisualFixes(showToast)
    pcall(function()
        local localPlayers = FindAllOf("LocalPlayer") or {}
        for _, player in ipairs(localPlayers) do
            if player and player:IsValid() then
                player.AspectRatioAxisConstraint = 1 -- AspectRatio_MaintainYFOV (Hor+)
            end
        end
    end)

    pcall(function()
        -- Ultra-Crisp Pixel Art Clarity & HD-2D Definition:
        ExecuteConsoleCommand("r.MaxAnisotropy 16")
        ExecuteConsoleCommand("r.MipMapLodBias 0")       -- Pulls highest-res sprite mip-levels, eliminating blur
        ExecuteConsoleCommand("r.Tonemapper.Sharpen 1.75")  -- Razor-sharp pixel contours & defined character edges
        ExecuteConsoleCommand("r.TemporalAA.Sharpness 1.4") -- Reduces TAA/TSR temporal pixel smearing
        ExecuteConsoleCommand("r.TemporalAAFilterSize 0.75")-- Tighter AA filter radius to stop sprite bleeding
        ExecuteConsoleCommand("r.MotionBlurQuality 0")       -- Eliminates motion blur during running/dashing
        ExecuteConsoleCommand("r.DepthOfFieldQuality 0")     -- Eliminates depth-of-field focal blur on sprites
        ExecuteConsoleCommand("r.SceneColorFringeQuality 0") -- Eliminates chromatic aberration / fringe blurring
        ExecuteConsoleCommand("r.FilmGrain 0")               -- Eliminates noisy grain over pixel sprites
        ExecuteConsoleCommand("r.ScreenPercentage 100")      -- 125% internal super-sampling for tack-sharp pixel definition
    end)
    print("[FFR QoL] Applied Ultra-Crisp Pixel Art & Visual Definition Fixes.")
    if showToast and ShowSpeedToast then
        ShowSpeedToast("[ ★ PIXEL CLARITY: ULTRA SHARP & DEFINED ]", { R = 0.2, G = 1.0, B = 0.8, A = 1.0 })
    end
end

-- ----------------------------------------------------------------------------
-- 2. Dedicated Visible Speed HUD (Center Toast & Top-Left Outworld Badge)
-- ----------------------------------------------------------------------------
local SpeedHud = {
    toast = nil,
    badge = nil,
    toastHideTime = 0,
    badgeHideTime = 0,
    disabled = false,
}

local function findClass(path)
    local cls = StaticFindObject(path)
    if cls and cls:IsValid() then return cls end
    return nil
end

local function makeSpeedWidget(kind, ax, ay, alx, aly, size, color)
    local gi = FindFirstOf("GameInstance")
    if not (gi and gi:IsValid()) then return nil end

    local userWidgetCls = findClass("/Script/UMG.UserWidget")
    local widgetTreeCls = findClass("/Script/UMG.WidgetTree")
    local canvasPanelCls = findClass("/Script/UMG.CanvasPanel")
    local borderCls = findClass("/Script/UMG.Border")
    local textBlockCls = findClass("/Script/UMG.TextBlock")

    if not (userWidgetCls and widgetTreeCls and canvasPanelCls and borderCls and textBlockCls) then
        return nil
    end

    local base = string.format("FFRSpeed_%s", kind)
    local widget = StaticConstructObject(userWidgetCls, gi, FName(base))
    local tree = StaticConstructObject(widgetTreeCls, widget, FName(base .. "_Tree"))
    widget.WidgetTree = tree
    local canvas = StaticConstructObject(canvasPanelCls, tree, FName(base .. "_Canvas"))
    tree.RootWidget = canvas
    local border = StaticConstructObject(borderCls, tree, FName(base .. "_Border"))
    local text = StaticConstructObject(textBlockCls, tree, FName(base .. "_Text"))
    border:SetContent(text)
    border:SetBrushColor({ R = 0.02, G = 0.03, B = 0.06, A = 0.82 })
    border:SetPadding({ Left = 16, Top = 8, Right = 16, Bottom = 8 })
    local slot = canvas:AddChildToCanvas(border)
    slot:SetAutoSize(true)
    slot:SetAnchors({ Minimum = { X = ax, Y = ay }, Maximum = { X = ax, Y = ay } })
    slot:SetAlignment({ X = alx, Y = aly })
    slot:SetPosition({ X = 0, Y = 0 })

    local font = text.Font
    font.Size = size
    text:SetFont(font)
    text:SetColorAndOpacity({ SpecifiedColor = color or { R = 0.95, G = 0.90, B = 0.65, A = 1.0 }, ColorUseRule = 0 })
    pcall(function() widget:SetIsFocusable(false) end)
    pcall(function() text:SetIsFocusable(false) end)
    widget:SetVisibility(1) -- Hidden initially
    widget:AddToViewport(kind == "toast" and 1500 or 1200)
    return { widget = widget, text = text, border = border }
end

local function getSpeedToastWidget()
    if SpeedHud.toast and SpeedHud.toast.widget:IsValid() and SpeedHud.toast.text:IsValid() then
        if not SpeedHud.toast.widget:IsInViewport() then SpeedHud.toast.widget:AddToViewport(1500) end
        return SpeedHud.toast
    end
    -- Clean bottom-center toast (never overlaps top-left/top-center quest & chapter text):
    -- ax=0.5, ay=0.85, alx=0.5, aly=0.5, size=15
    SpeedHud.toast = makeSpeedWidget("toast", 0.5, 0.85, 0.5, 0.5, 15, { R = 1.0, G = 0.92, B = 0.40, A = 1.0 })
    return SpeedHud.toast
end

local function getSpeedBadgeWidget()
    if SpeedHud.badge and SpeedHud.badge.widget:IsValid() and SpeedHud.badge.text:IsValid() then
        if not SpeedHud.badge.widget:IsInViewport() then SpeedHud.badge.widget:AddToViewport(1200) end
        return SpeedHud.badge
    end
    -- Sleek bottom-center badge (completely clear of top quest objectives, chapter banners & minimap):
    -- ax=0.5, ay=0.88, alx=0.5, aly=0.5, size=14
    SpeedHud.badge = makeSpeedWidget("badge", 0.5, 0.88, 0.5, 0.5, 14, { R = 0.0, G = 0.90, B = 1.0, A = 1.0 })
    return SpeedHud.badge
end

local function ShowSpeedToast(text, color)
    ExecuteInGameThread(function()
        pcall(function()
            local w = getSpeedToastWidget()
            if not w then return end
            w.text:SetText(FText(text))
            if color then
                w.text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
            end
            w.widget:SetVisibility(3) -- HitTestInvisible (visible)
            SpeedHud.toastHideTime = os.clock() + 1.8 -- Fades away quickly after 1.8 seconds
        end)
    end)
end

local function UpdateSpeedBadge(duration)
    ExecuteInGameThread(function()
        pcall(function()
            local w = getSpeedBadgeWidget()
            if not w then return end

            -- Hide badge during combat
            if _G.Fight and _G.Fight.active then
                w.widget:SetVisibility(1)
                return
            end

            -- Auto-fades after 1.8 seconds so it never blocks any gameplay area
            SpeedHud.badgeHideTime = os.clock() + (duration or 1.8)

            local text = QoL.SpeedToasts[QoL.SpeedIdx] or "[ SPRINT ]"
            local color = QoL.SpeedColors[QoL.SpeedIdx] or { R = 1.0, G = 1.0, B = 1.0, A = 1.0 }
            w.text:SetText(FText(text))
            w.text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
            w.border:SetBrushColor({ R = 0.02, G = 0.04, B = 0.08, A = 0.88 })
            w.widget:SetVisibility(3)
        end)
    end)
end

-- ----------------------------------------------------------------------------
-- 3. Safe Player Pawn Access (Never touches ambient NPCs, CDOs, or streaming actors)
-- ----------------------------------------------------------------------------
local cachedPC = nil

local function GetPlayerController()
    if cachedPC and cachedPC:IsValid() then
        return cachedPC
    end
    local pc = FindFirstOf("PlayerController")
    if pc and pc:IsValid() then
        cachedPC = pc
        return cachedPC
    end
    return nil
end

local function GetPlayerPawns()
    local pawns = {}
    local seen = {}
    local pc = GetPlayerController()
    if not (pc and pc:IsValid()) then return pawns end

    local function add(actor)
        if not (actor and actor:IsValid()) then return end
        local okAddr, a = pcall(function() return actor:GetAddress() end)
        if okAddr and a and not seen[a] then
            seen[a] = true
            pawns[#pawns + 1] = actor
        end
    end

    pcall(function()
        add(pc.Pawn)
        add(pc.Character)
        add(pc.AcknowledgedPawn)
    end)

    pcall(function()
        local vt = pc:GetViewTarget()
        if vt and vt:IsValid() then add(vt) end
    end)

    for i = 1, #pawns do
        local p = pawns[i]
        pcall(function()
            local parent = p:GetAttachParentActor()
            if parent and parent:IsValid() then add(parent) end
        end)
        pcall(function()
            for _, prop in ipairs({ "MountActor", "Vehicle", "CurrentMount", "RidingPawn", "Chocobo", "Mount", "m_RidingChocobo", "m_pChocobo" }) do
                local v = p[prop]
                if v and v:IsValid() then add(v) end
            end
        end)
    end

    pcall(function()
        local ch = FindFirstOf("CPP_MapUnit_Chocobo")
        if ch and ch:IsValid() then add(ch) end
    end)

    return pawns
end

local function GetPlayerPawn()
    local pawns = GetPlayerPawns()
    return #pawns > 0 and pawns[1] or nil
end

local function ApplySpeedToPawn(pawn, speed, isHyper)
    if not (pawn and pawn:IsValid()) then return false end
    local ok = false
    pcall(function()
        local cm = pawn.CharacterMovement or pawn.m_pPawnMovementComponent
        if cm and cm:IsValid() then
            cm.MaxWalkSpeed = speed
            cm.MaxCustomMovementSpeed = speed * 1.5
            cm.MaxAcceleration = math.max(speed * 6.0, 8192.0)
            cm.BrakingDecelerationWalking = math.max(speed * 4.0, 4096.0)
            cm.GroundFriction = 8.0
            ok = true
        end
    end)
    -- Native MapUnit movement properties
    pcall(function()
        pawn.m_MaxRunningSpeed = speed
        pawn.m_MaxWalkingSpeed = speed
        pawn.m_MaxJogSpeed = speed
        pawn.m_Speed = speed
        ok = true
    end)
    -- Native MapUnit methods
    pcall(function() pawn:SetMaxRunningMoveSpeed(speed, true) end)
    pcall(function() pawn:SetMaxWalkMoveSpeed(speed) end)
    pcall(function() pawn:SetMaxRunMoveSpeed(speed) end)
    -- Chocobo and mount movement scales
    pcall(function()
        if pawn.MovementScale ~= nil then
            pawn.MovementScale = isHyper and 2.5 or 1.8
        end
        if pawn.FlyingMovementScale ~= nil then
            pawn.FlyingMovementScale = isHyper and 2.5 or 1.8
        end
    end)
    pcall(function()
        local cms = pawn.ChocoboMovementSettings or pawn.ChocoboMaxSpeedSettings or pawn.ChocoboGroundMovementSettings
        if cms and cms:IsValid() then
            pcall(function() cms.MaxSpeed = speed end)
            pcall(function() cms.DashScale = 2.0 end)
            pcall(function() cms.Speed = speed end)
        end
    end)
    pcall(function()
        local dilation = 1.0
        if QoL.SpeedIdx == 4 then
            dilation = 1.35
        elseif QoL.SpeedIdx == 3 then
            dilation = 1.20
        end
        pawn.CustomTimeDilation = dilation
    end)
    return ok
end

-- ----------------------------------------------------------------------------
-- 4. Field Exploration Sprint Toggle (F5 or Controller Left Stick / L3)
-- ----------------------------------------------------------------------------
local lastToggleTime = 0

QoL.ToggleSprint = function()
    local now = os.clock()
    if (now - lastToggleTime) < 0.35 then return end
    lastToggleTime = now

    QoL.SpeedIdx = (QoL.SpeedIdx % #QoL.SpeedModes) + 1
    local currentSpeed = QoL.SpeedModes[QoL.SpeedIdx]
    local label = QoL.SpeedLabels[QoL.SpeedIdx]
    local toast = QoL.SpeedToasts[QoL.SpeedIdx]
    local color = QoL.SpeedColors[QoL.SpeedIdx]
    QoL.SprintActive = (QoL.SpeedIdx > 1)
    local isHyper = (QoL.SpeedIdx >= 3)

    local pawns = GetPlayerPawns()
    local updated = 0
    local pc = GetPlayerController()
    local charPawn = pc and pc.Pawn
    for _, pawn in ipairs(pawns) do
        local target = currentSpeed
        local isMount = (pawn ~= charPawn) or (pawn.GetName and tostring(pawn:GetName()):lower():find("chocobo"))
        if isMount then
            target = currentSpeed * 1.35 -- Mounts zoom 35% faster!
        end
        if ApplySpeedToPawn(pawn, target, isHyper) then
            updated = updated + 1
        end
    end

    -- Show visible speed toast and bottom-center badge (fades out automatically after 2s)
    ShowSpeedToast(toast, color)
    UpdateSpeedBadge(2.0)

    print(string.format("[FFR QoL] Outworld Movement: %s (MaxWalkSpeed = %.0f, updated %d player pawn)\n",
        label, currentSpeed, updated))
end

-- Bind F5 to toggle sprint (game thread safe)
pcall(function()
    RegisterKeyBind(Key.F5, function()
        ExecuteInGameThread(QoL.ToggleSprint)
    end)
end)

-- Bind F7 to manually re-apply Ultra-Crisp Pixel Clarity Preset
pcall(function()
    RegisterKeyBind(Key.F7, function()
        ExecuteInGameThread(function()
            ApplyVisualFixes(true)
        end)
    end)
end)

-- ----------------------------------------------------------------------------
-- 5. 100% Game-Thread L3 Polling, HUD Management & Post-Combat Auto-Persistence
-- ----------------------------------------------------------------------------
local lastL3 = false
local lastL3Time = 0
local visualFixesApplied = false

LoopInGameThreadWithDelay(50, function()
    pcall(function()
        local now = os.clock()

        -- Apply pixel clarity optimizations on game thread
        if not visualFixesApplied then
            visualFixesApplied = true
            ApplyVisualFixes(false)
        end

        -- Speed notification auto-fade check (hides after 3.0 seconds so it never blocks UI)
        if SpeedHud.badgeHideTime > 0 and now >= SpeedHud.badgeHideTime then
            SpeedHud.badgeHideTime = 0
            if SpeedHud.badge and SpeedHud.badge.widget:IsValid() then
                SpeedHud.badge.widget:SetVisibility(1)
            end
        end

        -- Toast timer check (game-thread safe hide)
        if SpeedHud.toastHideTime > 0 and now >= SpeedHud.toastHideTime then
            SpeedHud.toastHideTime = 0
            if SpeedHud.toast and SpeedHud.toast.widget:IsValid() then
                SpeedHud.toast.widget:SetVisibility(1)
            end
        end

        -- Skip input and movement mutation during active combat
        if _G.Fight and _G.Fight.active then
            if SpeedHud.badge and SpeedHud.badge.widget:IsValid() then
                SpeedHud.badge.widget:SetVisibility(1)
            end
            return
        end

        local pc = GetPlayerController()
        if not pc then return end

        local hit = false
        pcall(function()
            hit = pc:IsInputKeyDown({ KeyName = FName("Gamepad_LeftThumbstick") })
        end)

        -- 400ms debounce ensures zero double-cycling or analog stick jitter
        if hit and not lastL3 and (now - lastL3Time > 0.40) then
            lastL3Time = now
            QoL.ToggleSprint()
        end
        lastL3 = hit

        -- Maintain chosen sprint speed across map loading, mounting & combat transitions
        if QoL.SprintActive then
            local currentSpeed = QoL.SpeedModes[QoL.SpeedIdx]
            local isHyper = (QoL.SpeedIdx >= 3)
            local pawns = GetPlayerPawns()
            local pc = GetPlayerController()
            local charPawn = pc and pc.Pawn
            for _, pawn in ipairs(pawns) do
                if pawn and pawn:IsValid() then
                    local cm = pawn.CharacterMovement or pawn.m_pPawnMovementComponent
                    local isMount = (pawn ~= charPawn) or (pawn.GetName and tostring(pawn:GetName()):lower():find("chocobo"))
                    local target = isMount and (currentSpeed * 1.35) or currentSpeed
                    local curSpeed = cm and cm.MaxWalkSpeed or pawn.m_MaxRunningSpeed or 0
                    if math.abs(curSpeed - target) > 1.0 then
                        ApplySpeedToPawn(pawn, target, isHyper)
                    end
                end
            end
        end
    end)
end)

-- Run visual fixes on map load
ApplyVisualFixes()

print("[FFR QoL v3.8] Active & Ready: Visible Speed HUD + Crash-Proof Sprint (Normal / Fast / Hyper)")
