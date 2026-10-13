-- Pillar Chase 2 survivor HUD -- layout based on the game's NewStats GUI.
-- Visual layout only: XP/level progression is intentionally NOT implemented.
-- Existing gameplay values:
--    player:SetNWFloat("PC2_Stamina", value)
--    player:SetNWFloat("PC2_MaxStamina", value)
--    player:SetNWInt("PC2_Earnings", value)
--    player:SetNWInt("PC2_EarningsMax", value)
--    monster:SetNWBool("PC2_IsMonster", true)  -- heartbeat proximity source
-- Health uses player:Health() / player:GetMaxHealth().
if SERVER then return end

local PATH = "Server/RoundHandler/GameGui/NewStats/SelfIcon/"
local STUFF = PATH .. "ViewportFrame/NewStatsWork/Stuff/"

local art = {
    splash   = Material("Server/RoundHandler/GameGui/NewStats/SelfIcon.png", "smooth"),
    ring     = Material(PATH .. "Heart.png", "smooth"),
    currency = Material(PATH .. "Earning.png", "smooth"),
    heart = {
        Material(STUFF .. "Heart1.png", "smooth"),
        Material(STUFF .. "Heart2.png", "smooth"),
        Material(STUFF .. "Heart3.png", "smooth")
    },
    stamina = {
        Material(STUFF .. "Stamina1.png", "smooth"),
        Material(STUFF .. "Stamina2.png", "smooth"),
        Material(STUFF .. "Stamina3.png", "smooth")
    },
    shock = Material(STUFF .. "HeartShockwave.png", "smooth")
}

local WHITE = Color(255, 255, 255)
local SHADOW = Color(0, 0, 0, 220)
local STAMINA_YELLOW = Color(255, 187, 62)
local HEALTH_RED = Color(248, 62, 73)
local EARNINGS_PINK = Color(250, 39, 152)
local SOFT_GREY = Color(211, 221, 227)
local HEALTH_TEXT = {
    Color(135, 255, 135),
    Color(255, 225, 120),
    Color(255, 135, 135)
}

-- These are local HUD design coordinates in a 358x345 reference layout.
-- They scale as a group on different screen heights.
local W, H = 358, 345
local monsterRange = 1800
local proximity = 0
local nextMonsterScan = 0
local pulsePhase = 0
local pulseTime = RealTime()
local prevHeartState
local shockStarted = -100

local panel, modelView, modelPath, portraitSkin
local cachedScrH

local function UIscale()
    return math.Clamp(ScrH() / 1080, 0.67, 1.45)
end

local function S(value)
    return math.floor(value * UIscale() + 0.5)
end

local function showImage(texture, x, y, w, h, color)
    color = color or WHITE
    surface.SetMaterial(texture)
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)
    surface.DrawTexturedRect(S(x), S(y), S(w), S(h))
end

local function centerImage(texture, x, y, w, h, color)
    showImage(texture, x - w / 2, y - h / 2, w, h, color)
end

local function ratio(value, maximum)
    if maximum <= 0 then return 0 end
    return math.Clamp(value / maximum, 0, 1)
end

local function damageState(value)
    if value >= 0.6 then return 1 end
    if value >= 0.25 then return 2 end
    return 3
end

local function fonts()
    if cachedScrH == ScrH() then return end
    cachedScrH = ScrH()
    surface.CreateFont("PC2_StatsRef_Name", {
        font = "Georgia", size = S(19), weight = 800, antialias = true
    })
    surface.CreateFont("PC2_StatsRef_Number", {
        font = "Trebuchet MS", size = S(25), weight = 1000, antialias = true
    })
    surface.CreateFont("PC2_StatsRef_XP", {
        font = "Trebuchet MS", size = S(16), weight = 950, antialias = true
    })
end

local function isSurvivor(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:Alive() then return false end
    if GetGlobalString("PC2_RoundMode", "Waiting") ~= "Survive"
        or not ply:GetNWBool("PC2_InRound", false)
        or ply:GetNWBool("PC2_Eliminated", false)
        or ply:GetNWString("PC2_RoundRole", "") ~= "Survivor" then
        return false
    end
    if ply:GetNWBool("PC2_IsMonster", false) then return false end
    if GAMEMODE and GAMEMODE.IsPC2Survivor then
        return GAMEMODE:IsPC2Survivor(ply)
    end
    return true
end

local function monsterDistance(ply)
    if CurTime() < nextMonsterScan then return end
    nextMonsterScan = CurTime() + 0.25
    local dist = monsterRange
    local position = ply:GetPos()
    for _, ent in ipairs(ents.GetAll()) do
        if ent ~= ply and ent:GetNWBool("PC2_IsMonster", false)
                and (not ent:IsPlayer() or ent:Alive()) then
            dist = math.min(dist, position:Distance(ent:GetPos()))
        end
    end
    proximity = math.Clamp(1 - dist / monsterRange, 0, 1)
end

local function heartBeat()
    local now = RealTime()
    local delta = math.Clamp(now - pulseTime, 0, 0.1)
    pulseTime = now
    pulsePhase = (pulsePhase + delta * Lerp(proximity, 66, 142) / 60) % 1
    local beat1 = math.exp(-((pulsePhase - 0.065) / 0.055) ^ 2)
    local beat2 = 0.67 * math.exp(-((pulsePhase - 0.25) / 0.07) ^ 2)
    return math.max(beat1, beat2) * (0.035 + 0.19 * proximity)
end

local function quadAnnulus(cx, cy, r0, r1, a, b)
    local ca, sa = math.cos(a), math.sin(a)
    local cb, sb = math.cos(b), math.sin(b)
    surface.DrawPoly({
        { x = cx + r0 * ca, y = cy + r0 * sa },
        { x = cx + r1 * ca, y = cy + r1 * sa },
        { x = cx + r1 * cb, y = cy + r1 * sb },
        { x = cx + r0 * cb, y = cy + r0 * sb }
    })
end

-- Draw a colored ring like the screenshot: subtle unfilled track, glow,
-- then a bright arc starting at twelve o'clock. Not the old horizontal row.
local function circularMeter(x, y, rad, percent, ink, background)
    local scale = UIscale()
    local cx, cy = S(x), S(y)
    local outer, inner = rad * scale, (rad - 5) * scale
    local divisions = 66
    local filled = math.Clamp(percent, 0, 1) * divisions
    local starts = -math.pi / 2
    draw.NoTexture()

    surface.SetDrawColor(24, 27, 28, 188)
    for j = 0, divisions - 1 do
        local a = starts + j * math.pi * 2 / divisions
        quadAnnulus(cx, cy, inner, outer, a, a + 2 * math.pi / divisions)
    end

    if filled > 0 then
        surface.SetDrawColor(ink.r, ink.g, ink.b, 40)
        for j = 0, math.ceil(filled) - 1 do
            local b = math.Clamp(filled - j, 0, 1)
            if b > 0 then
                local a = starts + j * math.pi * 2 / divisions
                quadAnnulus(cx, cy, outer - 2 * scale, outer + 5 * scale,
                    a, a + b * math.pi * 2 / divisions)
            end
        end
        surface.SetDrawColor(ink.r, ink.g, ink.b, 255)
        for j = 0, math.ceil(filled) - 1 do
            local b = math.Clamp(filled - j, 0, 1)
            if b > 0 then
                local a = starts + j * math.pi * 2 / divisions
                quadAnnulus(cx, cy, inner, outer,
                    a, a + b * math.pi * 2 / divisions)
            end
        end
    end
end

local function showCount(number, x, y, color)
    draw.SimpleTextOutlined(
        tostring(math.floor(number)), "PC2_StatsRef_Number",
        S(x), S(y), color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
        math.max(1, S(1.8)), SHADOW
    )
end

-- 3D panel is an actual clone of the player's model, not their Steam avatar.
-- Pose and camera are frozen; only model/skin/bodygroup/color updates.
local function refreshPortrait(ply)
    if not IsValid(modelView) then return end
    local wanted = ply:GetModel()
    if not wanted or wanted == "" then return end

    if wanted ~= modelPath or not IsValid(modelView.Entity) then
        modelPath = wanted
        modelView:SetModel(wanted)
        local ent = modelView.Entity
        if IsValid(ent) then
            local idle = ent:LookupSequence("idle_all_01")
            if idle == -1 then idle = ent:SelectWeightedSequence(ACT_IDLE) end
            if idle and idle >= 0 then ent:ResetSequence(idle) end
            ent:SetCycle(0)
            ent:SetPlaybackRate(0)
            ent:SetAngles(Angle(0, 19, 0))

            local mins, maxs = ent:GetRenderBounds()
            local tall = math.max(42, maxs.z - mins.z)
            local center = (mins + maxs) * 0.5
            local look = Vector(center.x, center.y, mins.z + tall * 0.67)
            modelView:SetFOV(36)
            modelView:SetLookAt(look)
            modelView:SetCamPos(look + Vector(tall * 0.72, -tall * 0.67, tall * 0.12))
        end
    end

    local ent = modelView.Entity
    if not IsValid(ent) then return end
    ent:SetSkin(ply:GetSkin())
    for id = 0, math.min(ply:GetNumBodyGroups() - 1, 30) do
        ent:SetBodygroup(id, ply:GetBodygroup(id))
    end
    ent.GetPlayerColor = function()
        if IsValid(ply) then return ply:GetPlayerColor() end
        return Vector(1, 1, 1)
    end
end

local function createSurvivorHUD()
    if IsValid(panel) then panel:Remove() end
    modelPath = nil
    cachedScrH = nil
    prevHeartState = nil
    nextMonsterScan = 0

    panel = vgui.Create("DPanel")
    panel:SetMouseInputEnabled(false)
    panel:SetKeyboardInputEnabled(false)
    panel:SetPaintBackground(false)
    panel:SetZPos(-100)

    modelView = vgui.Create("DModelPanel", panel)
    modelView:SetMouseInputEnabled(false)
    modelView:SetKeyboardInputEnabled(false)
    modelView.LayoutEntity = function() end

    local function resize()
        panel:SetSize(S(W), S(H))
        panel:SetPos(S(6), ScrH() - S(H) - S(7))
        modelView:SetPos(S(10), S(92))
        modelView:SetSize(S(187), S(202))
        fonts()
    end
    resize()

    -- Return to the survivor HUD even if the panel was previously hidden.
    panel.PC2Resize = resize

    -- Only the game's dark-blue ink texture is behind the model.
    -- No large rectangular panel, separators or HUD labels.
    panel.Paint = function(self, w, h)
        showImage(art.splash, -23, 44, 353, 292, Color(255, 255, 255, 255))
    end

    -- PaintOver renders above the portrait so the name and meters remain crisp.
    panel.PaintOver = function(self, w, h)
        local ply = LocalPlayer()
        if not isSurvivor(ply) then return end

        local maxHP = math.max(ply:GetMaxHealth(), 1)
        local hp = math.max(0, ply:Health())
        local hpRatio = ratio(hp, maxHP)
        local hpState = damageState(hpRatio)
        if prevHeartState and hpState > prevHeartState then
            shockStarted = RealTime()
        end
        prevHeartState = hpState

        local maxStamina = math.max(ply:GetNWFloat("PC2_MaxStamina", 100), 1)
        local stamina = math.Clamp(ply:GetNWFloat("PC2_Stamina", maxStamina), 0, maxStamina)
        local staminaRatio = ratio(stamina, maxStamina)
        local staminaState = damageState(staminaRatio)

        local earningsMax = math.max(ply:GetNWInt("PC2_EarningsMax", 100), 1)
        local earnings = math.max(ply:GetNWInt("PC2_Earnings", 0), 0)
        local earningsRatio = ratio(earnings, earningsMax)

        monsterDistance(ply)
        local beat = heartBeat()

        local name = ply:Nick()
        if #name > 18 then name = string.sub(name, 1, 17) .. "..." end
        draw.SimpleTextOutlined(name, "PC2_StatsRef_Name", S(110), S(99),
            WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, math.max(1, S(1)), SHADOW)

        -- Positions taken from the supplied in-game screenshot:
        -- stamina above, health to the right, earnings directly underneath.
        local staminaX, staminaY = 241, 99
        local healthX, healthY = 305, 157
        local earningsX, earningsY = 235, 218

        -- Faint, dark circles show through the gaps in the colorful arcs.
        draw.RoundedBox(S(37), S(staminaX - 37), S(staminaY - 37),
            S(74), S(74), Color(10, 11, 13, 150))
        draw.RoundedBox(S(40), S(healthX - 40), S(healthY - 40),
            S(80), S(80), Color(10, 11, 13, 150))
        draw.RoundedBox(S(37), S(earningsX - 37), S(earningsY - 37),
            S(74), S(74), Color(10, 11, 13, 150))

        circularMeter(staminaX, staminaY, 37, staminaRatio, STAMINA_YELLOW)
        circularMeter(healthX, healthY, 40, hpRatio, HEALTH_RED)
        circularMeter(earningsX, earningsY, 37, earningsRatio, EARNINGS_PINK)

        -- Artwork stays underneath the numbers, just like PC2.
        centerImage(art.stamina[staminaState], staminaX, staminaY, 36, 42,
            Color(208, 152, 55, 230))
        centerImage(art.heart[hpState], healthX, healthY, 36 * (1 + beat),
            44 * (1 + beat))

        local shockAge = RealTime() - shockStarted
        if shockAge >= 0 and shockAge < 0.4 then
            local t = shockAge / 0.4
            local size = 42 + t * 96
            surface.SetMaterial(art.shock)
            surface.SetDrawColor(255, 110, 110, math.floor((1 - t) * 53))
            surface.DrawTexturedRectRotated(S(healthX), S(healthY), S(size), S(size), t * 180)
        end

        centerImage(art.currency, earningsX, earningsY, 58, 58)
        showCount(stamina, staminaX, staminaY + 5, Color(255, 218, 145))
        showCount(hp, healthX, healthY + 4, HEALTH_TEXT[hpState])
        showCount(earnings, earningsX, earningsY + 5, WHITE)

        -- The PC2 XP slot is included visually for layout accuracy only.
        -- No XP values or level system are fabricated or tracked.
        draw.RoundedBox(S(3), S(36), S(303), S(161), S(29), Color(0, 0, 0, 182))
        draw.RoundedBox(S(2), S(40), S(308), S(147), S(20), Color(18, 18, 18, 175))
        draw.NoTexture()
        surface.SetDrawColor(250, 164, 107, 240)
        surface.DrawPoly({
            { x = S(42), y = S(308) },
            { x = S(108), y = S(308) },
            { x = S(101), y = S(328) },
            { x = S(42), y = S(328) }
        })
        draw.SimpleTextOutlined("XP", "PC2_StatsRef_XP",
            S(73), S(318), Color(255, 228, 194), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
            math.max(1, S(1)), SHADOW)
        draw.SimpleTextOutlined("-- / --", "PC2_StatsRef_XP",
            S(143), S(318), WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
            math.max(1, S(1)), SHADOW)
    end
end

hook.Add("Think", "PC2_CreateSurvivorHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if not IsValid(panel) then createSurvivorHUD() end
    if not IsValid(panel) then return end
    local visible = isSurvivor(ply)
    if panel:IsVisible() ~= visible then panel:SetVisible(visible) end
    if not visible then return end
    if panel.PC2Resize and (panel:GetWide() ~= S(W)
        or panel:GetTall() ~= S(H)
        or panel.y ~= ScrH() - S(H) - S(7)) then
        panel.PC2Resize()
    end
    refreshPortrait(ply)
end)

hook.Add("OnReloaded", "PC2_ReloadSurvivorHUD", function()
    if IsValid(panel) then panel:Remove() end
    panel = nil
end)

hook.Add("HUDShouldDraw", "PC2_HideDefaultSurvivorHud", function(name)
    if name == "CHudHealth" or name == "CHudBattery" then return false end
end)
