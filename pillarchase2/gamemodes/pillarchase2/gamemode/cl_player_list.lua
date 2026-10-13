-- Top-of-screen Pillar Chase 2 player portraits, framing the round clock.
-- Timer art/countdown remains owned by cl_timer.lua; this draws its neighbors.
if SERVER then return end

local ASSETS = "Server/RoundHandler/GameGui/Top/PlrList/Plr/"
local border = Material(ASSETS .. "Border.png", "smooth")
local death = Material(ASSETS .. "Death.png", "smooth")
local DIED_SOUND = "LobbyGUI/Sounds/Died.wav"

-- Roblox death tween values. Death.png is drawn in the HUD foreground so
-- the oversized starting image is not clipped by each player's portrait.
local DEATH_FADE_TIME = 0.35
local DEATH_SIZE_TIME = 0.50
local DEATH_START_SIZE = 5.0
local DEATH_END_SIZE = 1.1
local DEATH_START_ROTATION = 125
local DEATH_END_ALPHA = math.Round(255 * (1 - 0.15))
-- Monsters use an image instead of a SpawnIcon/3D model preview.
-- Both types share the exact same portrait rectangle and border geometry.
local EXE_ICON = "Server/RoundHandler/GameGui/NewStats/SelfIcon/Renders/EXEIcon.png"

local GOOD = Color(91, 246, 102)
local BAD = Color(250, 76, 104)
local MAX_VISIBLE = 10
-- Roblox UDim2.new(1.638, 0, 1.638, 0): each border is exactly
-- 1.638 times the portrait's width AND height (zero pixel offsets).
local BORDER_SCALE = 1.638

local root, cards = nil, {}
local nextRoster = 0
local lastW, lastH = 0, 0

local function sineInOut(t)
    t = math.Clamp(t, 0, 1)
    return 0.5 - math.cos(t * math.pi) * 0.5
end

-- EXE marks the victim as being executed as soon as KillPC2 starts.
-- Show the dead-state portrait immediately, while the victim stays alive
-- at 1 HP until the jumpscare's finishing blow at 2.04 seconds.
-- When their actual death follows, the same state stays active so
-- the death icon and sound do not play a second time.
local function isPortraitDead(ply)
    return not ply:Alive()
        or ply:GetNWBool("PC2_EXEBeingExecuted", false)
end

-- A player entering the HUD already dead gets a settled overlay; all
-- subsequent alive -> dead transitions start the original animation.
local function updateDeathState(card, ply)
    local deadNow = isPortraitDead(ply)
    if card.player ~= ply then
        card.deathStarted = deadNow and (RealTime() - DEATH_SIZE_TIME) or nil
    elseif deadNow and not card.dead then
        card.deathStarted = RealTime()
        surface.PlaySound(DIED_SOUND)
    elseif not deadNow then
        card.deathStarted = nil
    end

    card.player = ply
    card.dead = deadNow
end

-- Match Sandbox's playermodel selector: SpawnIcon:SetModel(model) supplies
-- the cached, static model thumbnail, not a live 3D preview.
local function setPortraitModel(card, model)
    if not model or model == "" or card.modelName == model then return end
    card.modelName = model
    card.avatar:SetModel(model)
end

local function createCard()
    local card = vgui.Create("DPanel", root)
    card:SetMouseInputEnabled(false)
    card:SetKeyboardInputEnabled(false)
    card:SetPaintBackground(false)

    card.avatar = vgui.Create("SpawnIcon", card)
    card.avatar:SetMouseInputEnabled(false)
    card.avatar:SetKeyboardInputEnabled(false)
    card.avatar:SetSize(64, 64)

    -- A DImage is a flat PNG: no viewport or model rendering for EXE.
    -- Its layout is identical to the survivor SpawnIcon. This prevents
    -- switching roles from changing the visible portrait's scale.
    card.monsterIcon = vgui.Create("DImage", card)
    card.monsterIcon:SetImage(EXE_ICON)
    card.monsterIcon:SetMouseInputEnabled(false)
    card.monsterIcon:SetVisible(false)

    card.Paint = function(self, w, h)
        local ring = self.ring or 64
        local cx, cy = w * 0.5, ring * 0.64
        local color = self.danger and BAD or GOOD

        draw.RoundedBox(ring * 0.33, cx - ring * 0.37, cy - ring * 0.37,
            ring * 0.74, ring * 0.74, Color(10, 13, 15, 225))

        -- Reuse the actual supplied circular artwork for both glow and rim.
        surface.SetMaterial(border)
        surface.SetDrawColor(color.r, color.g, color.b, 18)
        local bloom = ring * 1.32
        surface.DrawTexturedRect(cx - bloom / 2, cy - bloom / 2, bloom, bloom)
        surface.SetDrawColor(color.r, color.g, color.b, 38)
        bloom = ring * 1.16
        surface.DrawTexturedRect(cx - bloom / 2, cy - bloom / 2, bloom, bloom)

        -- The SpawnIcon/DImage children draw here at the SAME size for
        -- survivors and EXE. PaintOver puts the tinted border above both.
    end

    card.PaintOver = function(self, w, h)
        local ring = self.ring or 64
        local cx, cy = w * 0.5, ring * 0.64
        local ink = self.danger and BAD or GOOD

        surface.SetMaterial(border)
        surface.SetDrawColor(ink.r, ink.g, ink.b, 255)
        surface.DrawTexturedRect(cx - ring * 0.5, cy - ring * 0.5, ring, ring)

        -- Animated death artwork is drawn above all cards by root.PaintOver.
        -- This avoids clipping the 5x-to-1.1x zoom to the card's bounds.
    end

    cards[#cards + 1] = card
    return card
end

local function updateCard(card, ply)
    updateDeathState(card, ply)

    local monsterForm = ply:GetNWString("PC2_MonsterForm", "")
    local isMonster = ply:GetNWBool("PC2_IsMonster", false)
        or monsterForm ~= ""
    card.danger = card.dead or isMonster
    card.isEXE = isMonster and monsterForm == "pc2_exe"

    -- No model preview/viewport is used for monsters. Currently EXE has
    -- an artwork icon; future monsters can supply their own render images.
    -- Survivors retain the static Sandbox model-selector thumbnails.
    card.avatar:SetVisible(not isMonster)
    card.monsterIcon:SetVisible(card.isEXE)
    if not isMonster then
        setPortraitModel(card, ply:GetModel())
    end
end

local function layoutCard(card, index, side, numLeft, ring, timerSize, portraitSize)
    local w = ScrW()
    local center = w * 0.5
    local near = timerSize * 0.65 + ring * 0.57
    local far = math.max(near, center - ring * 0.58 - 7)
    local interval = math.max(0, math.min((far - near) / 4, ring * 2.12))
    local indexFromClock = side == -1 and (numLeft - index) or index - numLeft - 1
    local dist = near + math.max(indexFromClock, 0) * interval
    local x = center + side * dist

    local timerCenterY = 12 + timerSize * 0.5
    local centerY = timerCenterY -- portraits level with the clock
    local width = math.Round(ring * 1.44)
    local height = math.Round(ring * 1.40)
    card:SetSize(width, height)
    card:SetPos(math.Round(x - width * 0.5),
        math.Round(centerY - ring * 0.64))
    card.ring = ring

    -- Both portrait types share one square, centred in the same ring.
    -- Switching between survivor and monster changes only visibility.
    local portraitX = math.Round((width - portraitSize) * 0.5)
    local portraitY = math.Round(ring * 0.64 - portraitSize * 0.5)
    card.avatar:SetSize(portraitSize, portraitSize)
    card.avatar:SetPos(portraitX, portraitY)
    card.monsterIcon:SetSize(portraitSize, portraitSize)
    card.monsterIcon:SetPos(portraitX, portraitY)
end

local function ensureRoot()
    if IsValid(root) then return end
    root = vgui.Create("DPanel")
    root:SetPaintBackground(false)
    root:SetMouseInputEnabled(false)
    root:SetKeyboardInputEnabled(false)
    root:SetZPos(-80)
    root.Paint = function() end

    -- Draw after every portrait, on a full-screen transparent parent.
    -- This lets the Roblox-style 5x death icon spin and shrink without
    -- getting cut off at the individual portrait's rectangular bounds.
    root.PaintOver = function()
        local now = RealTime()
        surface.SetMaterial(death)
        for _, card in ipairs(cards) do
            if IsValid(card) and card:IsVisible() and card.dead
                and card.deathStarted and card.ring then

                local elapsed = math.max(0, now - card.deathStarted)
                local fade = math.Clamp(elapsed / DEATH_FADE_TIME, 0, 1)
                local sizeT = sineInOut(elapsed / DEATH_SIZE_TIME)
                local turnT = sineInOut(elapsed / DEATH_FADE_TIME)

                local size = card.ring * Lerp(sizeT,
                    DEATH_START_SIZE, DEATH_END_SIZE)
                local rotation = Lerp(turnT, DEATH_START_ROTATION, 0)
                local alpha = math.Round(DEATH_END_ALPHA * fade)

                local x, y = card:GetPos()
                local centerX = x + card:GetWide() * 0.5
                local centerY = y + card.ring * 0.64

                -- Pure red, not the ring's pink/red role tint.
                surface.SetDrawColor(255, 0, 0, alpha)
                surface.DrawTexturedRectRotated(
                    centerX, centerY, size, size, rotation)
            end
        end
    end

    cards = {}
    lastW, lastH = 0, 0
end

local function roster()
    local players = {}
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() then players[#players + 1] = ply end
    end
    -- Stable ordering means portraits do not shuffle during a round.
    table.sort(players, function(a, b) return a:EntIndex() < b:EntIndex() end)

    -- Keep the local player visible on a server with more than ten players.
    if #players > MAX_VISIBLE then
        local me = LocalPlayer()
        local index
        for i, ply in ipairs(players) do
            if ply == me then index = i break end
        end
        if index and index > MAX_VISIBLE then
            table.remove(players, index)
            table.insert(players, 1, me)
        end
    end
    return players
end

hook.Add("Think", "PC2_TopPlayerListUpdate", function()
    -- Track living/dead transitions every frame so the death sound and
    -- tween don't wait for the slower 0.25-second roster refresh.
    for _, card in ipairs(cards) do
        if IsValid(card) and card:IsVisible() and IsValid(card.player) then
            updateDeathState(card, card.player)
        end
    end

    if CurTime() < nextRoster then return end
    nextRoster = CurTime() + 0.25

    ensureRoot()
    if not IsValid(root) then return end

    local sw, sh = ScrW(), ScrH()
    if lastW ~= sw or lastH ~= sh then
        -- Full screen for unclipped death animation; otherwise transparent.
        root:SetSize(sw, sh)
        root:SetPos(0, 0)
        lastW, lastH = sw, sh
    end

    local players = roster()
    local count = math.min(#players, MAX_VISIBLE)
    local left = math.ceil(count / 2)
    local timerSize = math.Clamp(math.Round(sh * 0.12), 96, 156)
    -- UDim2.new(1.638, 0, 1.638, 0): scale the FULL base portrait
    -- by 1.638 on both axes. Do not pre-shrink by 0.62: that almost
    -- cancels out the requested enlargement (0.62 * 1.638 ~= 1).
    -- This is computed once for every player, regardless of monster state.
    local portraitSize = math.Round(timerSize * 0.86)
    local ring = portraitSize * BORDER_SCALE

    for i = 1, count do
        local card = cards[i] or createCard()
        local side = i <= left and -1 or 1
        layoutCard(card, i, side, left, ring, timerSize, portraitSize)
        updateCard(card, players[i])
        card:SetVisible(true)
    end
    for i = count + 1, #cards do
        cards[i]:SetVisible(false)
    end
end)

hook.Add("OnReloaded", "PC2_TopPlayerListReload", function()
    if IsValid(root) then root:Remove() end
    root, cards = nil, {}
    nextRoster = 0
end)
