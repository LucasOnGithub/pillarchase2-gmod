-- Top-of-screen Pillar Chase 2 player portraits, framing the round clock.
-- Timer art/countdown remains owned by cl_timer.lua; this draws its neighbors.
if SERVER then return end

local ASSETS = "Server/RoundHandler/GameGui/Top/PlrList/Plr/"
-- Ignore world depth/skybox depth; this is 2D HUD artwork, not a world decal.
local border = Material(ASSETS .. "Border.png", "smooth ignorez")
local death = Material(ASSETS .. "Death.png", "smooth ignorez")
local DIED_SOUND = "LobbyGUI/Sounds/Died.wav"

-- Roblox death tween values. Death.png is drawn in the HUD foreground so
-- the oversized starting image is not clipped by each player's portrait.
local DEATH_FADE_TIME = 0.35
local DEATH_SIZE_TIME = 0.50
local DEATH_START_SIZE = 5.0
local DEATH_END_SIZE = 1.1
local DEATH_START_ROTATION = 125
local DEATH_END_ALPHA = math.Round(255 * (1 - 0.15))
-- Monsters use a supplied 2D portrait, never a rendered SpawnIcon.
local exeIcon = Material(
    "Server/RoundHandler/GameGui/NewStats/SelfIcon/Renders/EXEIcon.png",
    "smooth ignorez"
)

local GOOD = Color(91, 246, 102)
local BAD = Color(250, 76, 104)
local MAX_VISIBLE = 10
-- Roblox UDim2.new(1.638, 0, 1.638, 0): each border is exactly
-- 1.638 times the portrait's width AND height (zero pixel offsets).
local BORDER_SCALE = 1.638
-- Scale only EXE's picture inside its border, not the border itself.
-- No center-crop zoom: show the entire supplied EXEIcon.png image.
local EXE_ICON_SCALE = 0.85

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

    -- Only the static SpawnIcon lives inside each small card. Draw the
    -- circular backgrounds and ALL borders on the full-screen parent
    -- instead. New siblings can otherwise cover an existing card's ring
    -- and make it look smaller after another player joins.
    card.Paint = function() end
    card.PaintOver = function() end

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

    -- Keep model entirely inside the artwork's ring opening. The border
    -- itself has a transparent center and paints ABOVE this portrait.
    card.avatar:SetSize(portraitSize, portraitSize)
    card.avatar:SetPos(math.Round((width - portraitSize) * 0.5),
        math.Round(ring * 0.64 - portraitSize * 0.5))
end

-- Every ring is drawn in root coordinates at this fixed, stored diameter.
-- Neither player count, card order nor monster status changes its size.
local function cardCircle(card)
    if not IsValid(card) or not card:IsVisible() or not card.ring then
        return nil
    end
    local x, y = card:GetPos()
    return x + card:GetWide() * 0.5, y + card.ring * 0.64, card.ring
end

local function drawRingBackdrop(cx, cy, ring, ink)
    draw.RoundedBox(ring * 0.33,
        cx - ring * 0.37, cy - ring * 0.37,
        ring * 0.74, ring * 0.74, Color(10, 13, 15, 225))

    -- The supplied Border.png provides the same faint outer glow.
    surface.SetMaterial(border)
    surface.SetDrawColor(ink.r, ink.g, ink.b, 18)
    local bloom = ring * 1.32
    surface.DrawTexturedRect(cx - bloom * 0.5, cy - bloom * 0.5,
        bloom, bloom)

    surface.SetDrawColor(ink.r, ink.g, ink.b, 38)
    bloom = ring * 1.16
    surface.DrawTexturedRect(cx - bloom * 0.5, cy - bloom * 0.5,
        bloom, bloom)
end

local function ensureRoot()
    if IsValid(root) then return end
    root = vgui.Create("DPanel")
    root:SetPaintBackground(false)
    root:SetMouseInputEnabled(false)
    root:SetKeyboardInputEnabled(false)
    root:SetZPos(-80)

    -- Paint once behind ALL portrait panels, so none of the glow/background
    -- is cut short when the roster layout gets new child panels.
    root.Paint = function()
        for _, card in ipairs(cards) do
            local cx, cy, ring = cardCircle(card)
            if cx then
                drawRingBackdrop(cx, cy, ring,
                    card.danger and BAD or GOOD)
            end
        end
    end

    -- Foreground borders move out of the VGUI hierarchy. The EXE monster
    -- status HUD adds another top-level VGUI panel upon morphing, which
    -- can draw above this parent and obscure part of its 1.638x rings.
    root.PaintOver = function() end

    cards = {}
    lastW, lastH = 0, 0
end

-- Screen-space overlay paints on top of every VGUI panel, at unchanged
-- pixel dimensions whether the card is survivor or EXE.
hook.Add("PostRenderVGUI", "PC2_TopPlayerListForeground", function()
    if not IsValid(root) then return end
    if gui.IsGameUIVisible() then return end

    -- A depth buffer may still contain map geometry/skybox depth by the
    -- time PostRenderVGUI fires. HUD artwork must never be tested against
    -- that depth. Restore normal depth range after drawing.
    cam.IgnoreZ(true)

        -- EXE uses ONLY the PNG artwork at 85% of the inner opening.
        for _, card in ipairs(cards) do
            local cx, cy, ring = cardCircle(card)
            if cx and card.isEXE then
                local iconSize = (ring / BORDER_SCALE) * EXE_ICON_SCALE
                surface.SetMaterial(exeIcon)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(
                    cx - iconSize * 0.5, cy - iconSize * 0.5,
                    iconSize, iconSize)
            end
        end

        -- Render all the actual 1.638x borders together at their fixed
        -- diameters. Player count and monster form only affect the color.
        surface.SetMaterial(border)
        for _, card in ipairs(cards) do
            local cx, cy, ring = cardCircle(card)
            if cx then
                local ink = card.danger and BAD or GOOD
                local x, y = cx - ring * 0.5, cy - ring * 0.5

                -- One-pixel dark shadow prevents the translucent border
                -- artwork vanishing against white skies or bright lights.
                -- Both passes use the ORIGINAL diameter: no scaling.
                surface.SetDrawColor(8, 10, 12, 235)
                surface.DrawTexturedRect(x + 1, y + 1, ring, ring)
                surface.SetDrawColor(ink.r, ink.g, ink.b, 255)
                surface.DrawTexturedRect(x, y, ring, ring)
            end
        end

        -- Death icons stay over the borders (including the unclipped 5x
        -- beginning of their original animation).
        local now = RealTime()
        surface.SetMaterial(death)
        for _, card in ipairs(cards) do
            local cx, cy, ring = cardCircle(card)
            if cx and card.dead and card.deathStarted then
                local elapsed = math.max(0, now - card.deathStarted)
                local fade = math.Clamp(elapsed / DEATH_FADE_TIME, 0, 1)
                local sizeT = sineInOut(elapsed / DEATH_SIZE_TIME)
                local turnT = sineInOut(elapsed / DEATH_FADE_TIME)
                local size = ring * Lerp(sizeT,
                    DEATH_START_SIZE, DEATH_END_SIZE)
                local rotation = Lerp(turnT, DEATH_START_ROTATION, 0)
                local alpha = math.Round(DEATH_END_ALPHA * fade)

                -- Pure red, not the ring's role tint.
                surface.SetDrawColor(255, 0, 0, alpha)
                surface.DrawTexturedRectRotated(
                    cx, cy, size, size, rotation)
            end
        end

    cam.IgnoreZ(false)
end)

-- Diagnostics: run pc2_topbar_debug before and after morphing to print
-- each border diameter and verify the underlying pixel size is stable.
concommand.Add("pc2_topbar_debug", function()
    local baseTimer = math.Clamp(math.Round(ScrH() * 0.12), 96, 156)
    local portrait = math.Round(baseTimer * 0.86 * 0.62)
    local calculatedRing = portrait * BORDER_SCALE
    print(string.format(
        "[PC2 topbar] screen=%dx%d timer=%d portrait=%d border=%.2fpx ignorez=%s",
        ScrW(), ScrH(), baseTimer, portrait, calculatedRing,
        tostring(border:GetInt("$ignorez"))))
    local count = 0
    for _, card in ipairs(cards) do
        if IsValid(card) and card:IsVisible() then
            count = count + 1
            local ply = card.player
            local cx, cy, ring = cardCircle(card)
            print(string.format(
                "[PC2 topbar] slot=%d player=%s EXE=%s border=%.2fpx center=(%.1f,%.1f)",
                count, IsValid(ply) and ply:Nick() or "unknown",
                tostring(card.isEXE), ring or -1, cx or -1, cy or -1))
        end
    end
    print(string.format("[PC2 topbar] visible cards=%d", count))
end)

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
    -- UDim2.new(1.638, 0, 1.638, 0) means 1.638 times the
    -- portrait holder's dimensions (no pixel offsets). Use the compact
    -- reference holder that matched the timer rather than treating the
    -- timer-sized preview as the holder. Drawing in the shared root layer
    -- keeps the same diameter when players join or change roles.
    local portraitSize = math.Round(timerSize * 0.86 * 0.62)
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
