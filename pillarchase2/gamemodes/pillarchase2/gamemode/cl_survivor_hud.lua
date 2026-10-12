-- Pillar Chase 2 - Survivor HUD.
-- Adapted from the PC2 NewStatsWork layout/data behaviour:
-- static playermodel viewport, health/heart states, stamina, earnings.
-- XP is intentionally not implemented.
--
-- Server-facing values for the future round/economy systems:
--   survivor:SetNWInt("PC2_Earnings", coins)
--   survivor:SetNWInt("PC2_EarningsMax", maxCoins)
--   survivor:SetNWFloat("PC2_Stamina", stamina)
--   survivor:SetNWFloat("PC2_MaxStamina", maxStamina)
--   monster:SetNWBool("PC2_IsMonster", true)
-- Any player, NPC, or nextbot explicitly marked as a monster can drive
-- the heart proximity pulse. Ordinary players never count as monsters.

if SERVER then return end

local ASSETS = "Server/RoundHandler/GameGui/NewStats/SelfIcon/"
local STUFF = ASSETS .. "ViewportFrame/NewStatsWork/Stuff/"
local textures = {
    background = Material("Server/RoundHandler/GameGui/NewStats/SelfIcon.png", "smooth"),
    ring       = Material(ASSETS .. "Heart.png", "smooth"),
    earnings   = Material(ASSETS .. "Earning.png", "smooth"),
    heart      = {
        Material(STUFF .. "Heart1.png", "smooth"),
        Material(STUFF .. "Heart2.png", "smooth"),
        Material(STUFF .. "Heart3.png", "smooth")
    },
    stamina    = {
        Material(STUFF .. "Stamina1.png", "smooth"),
        Material(STUFF .. "Stamina2.png", "smooth"),
        Material(STUFF .. "Stamina3.png", "smooth")
    },
    shockwave  = Material(STUFF .. "HeartShockwave.png", "smooth")
}

local WHITE = Color(255, 255, 255)
local HEALTH_GOOD = Color(135, 255, 135)
local HEALTH_MID = Color(255, 225, 120)
local HEALTH_BAD = Color(255, 135, 135)
local STAMINA_GOOD = Color(255, 200, 75)
local STAMINA_MID = Color(185, 125, 75)
local STAMINA_BAD = Color(125, 65, 25)
local EARNINGS_COLOR = Color(238, 49, 156)
local OUTLINE = Color(2, 8, 13, 230)

-- Approximate 3D audio/visual detection distance in Source units.
-- No monster role system is present yet, so this remains a calm HUD
-- until an entity is marked with PC2_IsMonster.
local HEARTBEAT_RANGE = 1800
local nextProximityScan = 0
local monsterProximity = 0
local heartbeatPhase = 0
local lastHeartbeatTime = RealTime()
local previousHealthState
local healthShockTime = -100
local root
local portrait
local currentModel
local currentScreenHeight

local function scaled(value, scale)
    return math.floor(value * scale + 0.5)
end

local function drawImage(material, x, y, w, h, tint)
    tint = tint or WHITE
    surface.SetDrawColor(tint.r, tint.g, tint.b, tint.a or 255)
    surface.SetMaterial(material)
    surface.DrawTexturedRect(x, y, w, h)
end

local function drawImageCentered(material, x, y, w, h, tint)
    drawImage(material, x - w / 2, y - h / 2, w, h, tint)
end

local function clampRatio(current, maximum)
    if maximum <= 0 then return 0 end
    return math.Clamp(current / maximum, 0, 1)
end

local function getState(ratio)
    if ratio >= 0.6 then return 1 end
    if ratio >= 0.25 then return 2 end
    return 3
end

local function ringSegment(cx, cy, inside, outside, beginAngle, endAngle)
    local a = math.rad(beginAngle)
    local b = math.rad(endAngle)
    surface.DrawPoly({
        { x = cx + math.cos(a) * inside,  y = cy + math.sin(a) * inside },
        { x = cx + math.cos(a) * outside, y = cy + math.sin(a) * outside },
        { x = cx + math.cos(b) * outside, y = cy + math.sin(b) * outside },
        { x = cx + math.cos(b) * inside,  y = cy + math.sin(b) * inside }
    })
end

-- Two-half circular meter equivalent to the PC2 UIGradient health/stamina bars.
local function drawProgress(cx, cy, radius, fraction, color, scale)
    local outer = radius * scale
    local inner = outer - 5 * scale
    local segments = 72
    local progress = math.Clamp(fraction, 0, 1) * segments

    draw.NoTexture()
    surface.SetDrawColor(20, 33, 46, 220)
    for i = 0, segments - 1 do
        ringSegment(cx, cy, inner, outer, -90 + i * 360 / segments, -90 + (i + 1) * 360 / segments)
    end

    surface.SetDrawColor(color.r, color.g, color.b, 255)
    for i = 0, math.ceil(progress) - 1 do
        local portion = math.Clamp(progress - i, 0, 1)
        if portion > 0 then
            ringSegment(cx, cy, inner, outer, -90 + i * 360 / segments, -90 + (i + portion) * 360 / segments)
        end
    end
end

local function getHudScale()
    return math.Clamp(ScrH() / 1080, 0.68, 1.20)
end

local function refreshFonts()
    if currentScreenHeight == ScrH() then return end
    currentScreenHeight = ScrH()
    local scale = getHudScale()
    surface.CreateFont("PC2_StatsPlayerName", {
        font = "Trebuchet MS", size = scaled(19, scale),
        weight = 900, antialias = true
    })
    surface.CreateFont("PC2_StatsNumber", {
        font = "Trebuchet MS", size = scaled(18, scale),
        weight = 900, antialias = true
    })
    surface.CreateFont("PC2_StatsLabel", {
        font = "Trebuchet MS", size = scaled(11, scale),
        weight = 850, antialias = true
    })
end

local function isSurvivor(ply)
    if not IsValid(ply) or not ply:Alive() then return false end
    if ply:GetNWBool("PC2_IsMonster", false) then return false end

    local gamemode = GAMEMODE
    if gamemode and gamemode.IsPC2Survivor then
        return gamemode:IsPC2Survivor(ply)
    end

    return true
end

local function scanMonsterProximity(ply)
    if CurTime() < nextProximityScan then return end
    nextProximityScan = CurTime() + 0.25
    local nearest = HEARTBEAT_RANGE
    local origin = ply:GetPos()

    for _, entity in ipairs(ents.GetAll()) do
        if entity ~= ply and entity:GetNWBool("PC2_IsMonster", false) then
            if entity:IsPlayer() and not entity:Alive() then continue end

            local distance = origin:Distance(entity:GetPos())
            if distance < nearest then
                nearest = distance
            end
        end
    end

    monsterProximity = math.Clamp(1 - nearest / HEARTBEAT_RANGE, 0, 1)
end

-- A quiet resting double beat, speeding up and growing as the monster closes in.
local function heartbeatAmount()
    local now = RealTime()
    local dt = math.min(now - lastHeartbeatTime, 0.1)
    lastHeartbeatTime = now
    local bpm = Lerp(monsterProximity, 66, 142)
    heartbeatPhase = (heartbeatPhase + math.max(dt, 0) * bpm / 60) % 1

    local first = math.exp(-((heartbeatPhase - 0.06) / 0.06) ^ 2)
    local second = math.exp(-((heartbeatPhase - 0.26) / 0.075) ^ 2) * 0.65
    return math.max(first, second) * (0.055 + monsterProximity * 0.20)
end

local function syncPortrait(ply)
    if not IsValid(portrait) then return end

    local modelPath = ply:GetModel()
    if not modelPath or modelPath == "" then return end
    if modelPath ~= currentModel or not IsValid(portrait.Entity) then
        currentModel = modelPath
        portrait:SetModel(modelPath)

        local entity = portrait.Entity
        if IsValid(entity) then
            -- No automatic idle animation or spinning: this is a still viewport.
            local seq = entity:LookupSequence("idle_all_01")
            if seq < 0 then seq = entity:SelectWeightedSequence(ACT_IDLE) end
            if seq and seq >= 0 then entity:ResetSequence(seq) end
            entity:SetCycle(0)
            entity:SetPlaybackRate(0)
            entity:SetAngles(Angle(0, 25, 0))

            local mins, maxs = entity:GetRenderBounds()
            local height = math.max(maxs.z - mins.z, 45)
            local center = (mins + maxs) * 0.5
            portrait:SetFOV(40)
            portrait:SetLookAt(center + Vector(0, 0, height * 0.02))
            portrait:SetCamPos(center + Vector(height * 0.85, -height * 0.85, height * 0.07))
        end
    end

    local entity = portrait.Entity
    if IsValid(entity) then
        entity:SetSkin(ply:GetSkin())
        for index = 0, math.min(ply:GetNumBodyGroups() - 1, 30) do
            entity:SetBodygroup(index, ply:GetBodygroup(index))
        end
        entity.GetPlayerColor = function()
            if IsValid(ply) then return ply:GetPlayerColor() end
            return Vector(1, 1, 1)
        end
    end
end

local function createHud()
    if IsValid(root) then root:Remove() end
    currentModel = nil
    currentScreenHeight = nil
    previousHealthState = nil
    nextProximityScan = 0

    root = vgui.Create("DPanel")
    root:SetMouseInputEnabled(false)
    root:SetKeyboardInputEnabled(false)
    root:SetPaintBackground(false)
    root:SetZPos(-100)

    portrait = vgui.Create("DModelPanel", root)
    portrait:SetMouseInputEnabled(false)
    portrait:SetKeyboardInputEnabled(false)
    portrait.LayoutEntity = function() end

    local function resize()
        local scale = getHudScale()
        root:SetSize(scaled(434, scale), scaled(178, scale))
        root:SetPos(scaled(18, scale), ScrH() - scaled(196, scale))
        portrait:SetPos(scaled(7, scale), scaled(13, scale))
        portrait:SetSize(scaled(141, scale), scaled(156, scale))
        refreshFonts()
    end

    resize()

    root.Think = function(self)
        local ply = LocalPlayer()
        local visible = isSurvivor(ply)
        self:SetVisible(visible)
        if not visible then return end

        local scale = getHudScale()
        local newWidth, newHeight = scaled(434, scale), scaled(178, scale)
        if self:GetWide() ~= newWidth or self:GetTall() ~= newHeight
            or self.y ~= ScrH() - scaled(196, scale) then
            resize()
        end
        syncPortrait(ply)
    end

    root.Paint = function(self, w, h)
        local scale = getHudScale()
        draw.RoundedBox(scaled(14, scale), 0, 0, w, h, Color(5, 15, 25, 212))
        draw.RoundedBox(scaled(12, scale), scaled(4, scale), scaled(4, scale),
            w - scaled(8, scale), h - scaled(8, scale), Color(11, 30, 47, 178))
        drawImage(textures.background, 0, 0, scaled(178, scale), scaled(178, scale),
            Color(255, 255, 255, 235))
        surface.SetDrawColor(76, 117, 133, 45)
        surface.DrawRect(scaled(149, scale), scaled(13, scale), scaled(1, scale), h - scaled(28, scale))
    end

    root.PaintOver = function(self)
        local ply = LocalPlayer()
        if not isSurvivor(ply) then return end
        local scale = getHudScale()
        local function S(value) return scaled(value, scale) end

        local maxHealth = math.max(ply:GetMaxHealth(), 1)
        local health = math.max(0, ply:Health())
        local healthRatio = clampRatio(health, maxHealth)
        local healthState = getState(healthRatio)
        if previousHealthState and healthState > previousHealthState then
            healthShockTime = RealTime()
        end
        previousHealthState = healthState

        local staminaMax = math.max(ply:GetNWFloat("PC2_MaxStamina", 100), 1)
        local stamina = math.Clamp(ply:GetNWFloat("PC2_Stamina", staminaMax), 0, staminaMax)
        local staminaRatio = clampRatio(stamina, staminaMax)
        local staminaState = getState(staminaRatio)
        local earningsMax = math.max(ply:GetNWInt("PC2_EarningsMax", 100), 1)
        local earnings = math.max(0, ply:GetNWInt("PC2_Earnings", 0))
        local earningsRatio = clampRatio(earnings, earningsMax)

        scanMonsterProximity(ply)
        local pulse = heartbeatAmount()

        local name = ply:Nick()
        if #name > 19 then name = string.sub(name, 1, 18) .. "..." end
        draw.SimpleTextOutlined(name, "PC2_StatsPlayerName", S(162), S(13),
            WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, OUTLINE)
        draw.SimpleText("SURVIVOR", "PC2_StatsLabel", S(163), S(37),
            Color(125, 188, 202), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        local cxHealth, cxStamina, cxEarning = S(195), S(285), S(374)
        local cy = S(105)
        local healthColor = ({ HEALTH_GOOD, HEALTH_MID, HEALTH_BAD })[healthState]
        local staminaColor = ({ STAMINA_GOOD, STAMINA_MID, STAMINA_BAD })[staminaState]

        drawImageCentered(textures.ring, cxHealth, cy, S(76), S(80), Color(215, 225, 231, 80))
        drawImageCentered(textures.ring, cxStamina, cy, S(76), S(80), Color(215, 225, 231, 80))
        drawProgress(cxHealth, cy, 34, healthRatio, healthColor, scale)
        drawProgress(cxStamina, cy, 34, staminaRatio, staminaColor, scale)
        drawProgress(cxEarning, cy, 34, earningsRatio, EARNINGS_COLOR, scale)

        -- Draw the anatomical heart as a static image except for its heartbeat size.
        local heartWidth = S(41) * (1 + pulse)
        local heartHeight = S(49) * (1 + pulse)
        drawImageCentered(textures.heart[healthState], cxHealth, cy, heartWidth, heartHeight)

        -- Reproduce the PC2 change-of-heart-state shockwave, without requiring
        -- the missing Roblox shatter sounds.
        local shockElapsed = RealTime() - healthShockTime
        if shockElapsed >= 0 and shockElapsed < 0.4 then
            local progress = shockElapsed / 0.4
            local size = S(28 + 105 * progress)
            local fade = math.floor((1 - progress) * 65)
            surface.SetDrawColor(255, 135, 135, fade)
            surface.SetMaterial(textures.shockwave)
            surface.DrawTexturedRectRotated(cxHealth, cy, size, size, progress * 180)
        end

        drawImageCentered(textures.stamina[staminaState], cxStamina, cy, S(43), S(52))
        drawImageCentered(textures.earnings, cxEarning, cy, S(58), S(58))

        draw.SimpleText(tostring(math.floor(health)), "PC2_StatsNumber",
            cxHealth, S(141), healthColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(math.floor(stamina)), "PC2_StatsNumber",
            cxStamina, S(141), staminaColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(math.floor(earnings)), "PC2_StatsNumber",
            cxEarning, S(141), EARNINGS_COLOR, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        draw.SimpleText("HEALTH", "PC2_StatsLabel", cxHealth, S(161),
            WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("STAMINA", "PC2_StatsLabel", cxStamina, S(161),
            WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("EARNINGS", "PC2_StatsLabel", cxEarning, S(161),
            WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

hook.Add("Think", "PC2_CreateSurvivorHUD", function()
    if not IsValid(root) and IsValid(LocalPlayer()) then
        createHud()
    end
end)

hook.Add("OnReloaded", "PC2_ReloadSurvivorHUD", function()
    if IsValid(root) then root:Remove() end
    root = nil
end)

hook.Add("HUDShouldDraw", "PC2_HideDefaultHealth", function(name)
    if name == "CHudHealth" or name == "CHudBattery" then
        return false
    end
end)
