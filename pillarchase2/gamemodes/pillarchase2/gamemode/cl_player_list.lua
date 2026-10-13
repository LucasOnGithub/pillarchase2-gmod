-- Top-of-screen Pillar Chase 2 player portraits, framing the round clock.
-- Timer art/countdown remains owned by cl_timer.lua; this draws its neighbors.
if SERVER then return end

local ASSETS = "Server/RoundHandler/GameGui/Top/PlrList/Plr/"
local border = Material(ASSETS .. "Border.png", "smooth")
local death = Material(ASSETS .. "Death.png", "smooth")

local GOOD = Color(91, 246, 102)
local BAD = Color(250, 76, 104)
local WHITE = Color(255, 255, 255)
local BLACK = Color(0, 0, 0, 210)
local MODEL_EXE = "models/noodles/pillarchase2/exe.mdl"
local MAX_VISIBLE = 10

local root, cards = nil, {}
local nextRoster = 0
local lastW, lastH = 0, 0

local function makeFonts()
    local size = math.Clamp(math.Round(ScrH() * 0.020), 15, 26)
    surface.CreateFont("PC2_TopPlayerNumber", {
        font = "Trebuchet MS", size = size, weight = 900,
        antialias = true, shadow = true
    })
end

-- Every model portrait holds a frozen pose, matching the still images
-- in the Roblox top bar without requiring separate PNGs for every player.
local function setPortraitModel(card, model)
    if not model or model == "" or card.modelName == model then return end
    card.modelName = model
    card.avatar:SetModel(model)

    local modelEnt = card.avatar.Entity
    if not IsValid(modelEnt) then return end

    local idle = modelEnt:LookupSequence("idle_all_01")
    if idle < 0 then idle = modelEnt:SelectWeightedSequence(ACT_IDLE) end
    if idle and idle >= 0 then modelEnt:ResetSequence(idle) end
    modelEnt:SetCycle(0)
    modelEnt:SetPlaybackRate(0)
    modelEnt:SetAngles(Angle(0, 24, 0))

    local mins, maxs = modelEnt:GetRenderBounds()
    local tall = math.max(40, maxs.z - mins.z)
    local center = (mins + maxs) * 0.5
    local look = Vector(center.x, center.y, mins.z + tall * 0.75)
    card.avatar:SetFOV(36)
    card.avatar:SetLookAt(look)
    card.avatar:SetCamPos(look + Vector(tall * 0.66, -tall * 0.58, tall * 0.055))
end

-- Tiny white figures beneath each circular portrait, matching the
-- two standing/running silhouettes from the reference artwork.
local function drawRunner(x, y, scale, ink)
    surface.SetDrawColor(ink.r, ink.g, ink.b, ink.a)
    draw.RoundedBox(scale * 2, x - scale * 2, y, scale * 4, scale * 4, ink)
    surface.DrawLine(x, y + scale * 4, x + scale * 2, y + scale * 10)
    surface.DrawLine(x - scale, y + scale * 6, x - scale * 6, y + scale * 9)
    surface.DrawLine(x + scale, y + scale * 6, x + scale * 5, y + scale * 4)
    surface.DrawLine(x + scale * 2, y + scale * 10, x - scale * 3, y + scale * 14)
    surface.DrawLine(x + scale * 2, y + scale * 10, x + scale * 7, y + scale * 13)
end

local function createCard()
    local card = vgui.Create("DPanel", root)
    card:SetMouseInputEnabled(false)
    card:SetKeyboardInputEnabled(false)
    card:SetPaintBackground(false)

    card.avatar = vgui.Create("DModelPanel", card)
    card.avatar:SetMouseInputEnabled(false)
    card.avatar:SetKeyboardInputEnabled(false)
    card.avatar:SetPaintBackground(false)
    card.avatar.LayoutEntity = function() end
    card.avatar:SetAmbientLight(Color(165, 165, 165))

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
    end

    card.PaintOver = function(self, w, h)
        local ring = self.ring or 64
        local cx, cy = w * 0.5, ring * 0.64
        local ink = self.danger and BAD or GOOD

        surface.SetMaterial(border)
        surface.SetDrawColor(ink.r, ink.g, ink.b, 255)
        surface.DrawTexturedRect(cx - ring * 0.5, cy - ring * 0.5, ring, ring)

        if self.dead then
            surface.SetMaterial(death)
            surface.SetDrawColor(255, 255, 255, 220)
            local size = ring * 0.46
            surface.DrawTexturedRect(cx - size * 0.5, cy - size * 0.5,
                size, size)
        end

        if self.score ~= nil then
            draw.SimpleTextOutlined(tostring(self.score),
                "PC2_TopPlayerNumber", cx - ring * 0.46, cy - ring * 0.40,
                WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, BLACK)
        end

        local unit = math.max(0.65, ring / 82)
        local iconY = cy + ring * 0.43
        local silhouette = self.dead
            and Color(185, 185, 185, 130) or Color(255, 255, 255, 238)
        drawRunner(cx - ring * 0.18, iconY, unit, silhouette)
        drawRunner(cx + ring * 0.09, iconY, unit, silhouette)
    end

    cards[#cards + 1] = card
    return card
end

local function portraitModel(ply)
    if ply:GetNWString("PC2_MonsterForm", "") == "pc2_exe" then
        return MODEL_EXE
    end
    return ply:GetModel()
end

local function updateCard(card, ply)
    card.player = ply
    card.dead = not ply:Alive()
    card.danger = card.dead or ply:GetNWBool("PC2_IsMonster", false)
    -- The proper level will appear when the round/level system supplies it;
    -- until then, use the engine's real player score rather than fake levels.
    card.score = ply:GetNWInt("PC2_Level", ply:Frags())

    setPortraitModel(card, portraitModel(ply))
    local model = card.avatar.Entity
    if not IsValid(model) then return end

    if not ply:GetNWBool("PC2_IsMonster", false) then
        model:SetSkin(ply:GetSkin())
        for i = 0, math.min(ply:GetNumBodyGroups() - 1, 30) do
            model:SetBodygroup(i, ply:GetBodygroup(i))
        end
        model.GetPlayerColor = function()
            return IsValid(ply) and ply:GetPlayerColor() or Vector(1, 1, 1)
        end
    end
end

local function layoutCard(card, index, side, numLeft, ring, timerSize)
    local w = ScrW()
    local center = w * 0.5
    local near = timerSize * 0.65 + ring * 0.57
    local far = math.max(near, center - ring * 0.58 - 7)
    local interval = math.max(0, math.min((far - near) / 4, ring * 2.12))
    local indexFromClock = side == -1 and (numLeft - index) or index - numLeft - 1
    local dist = near + math.max(indexFromClock, 0) * interval
    local x = center + side * dist

    local timerCenterY = 12 + timerSize * 0.5
    local centerY = timerCenterY - timerSize * 0.04
    local width = math.Round(ring * 1.44)
    local height = math.Round(ring * 1.40)
    card:SetSize(width, height)
    card:SetPos(math.Round(x - width * 0.5),
        math.Round(centerY - ring * 0.64))
    card.ring = ring

    -- Keep model entirely inside the artwork's ring opening. The border
    -- itself has a transparent center and paints ABOVE this portrait.
    local hole = math.Round(ring * 0.62)
    card.avatar:SetSize(hole, hole)
    card.avatar:SetPos(math.Round((width - hole) * 0.5),
        math.Round(ring * 0.64 - hole * 0.5))
end

local function ensureRoot()
    if IsValid(root) then return end
    root = vgui.Create("DPanel")
    root:SetPaintBackground(false)
    root:SetMouseInputEnabled(false)
    root:SetKeyboardInputEnabled(false)
    root:SetZPos(-80)
    root.Paint = function() end
    cards = {}
    lastW, lastH = 0, 0
    makeFonts()
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
    if CurTime() < nextRoster then return end
    nextRoster = CurTime() + 0.25

    ensureRoot()
    if not IsValid(root) then return end

    local sw, sh = ScrW(), ScrH()
    if lastW ~= sw or lastH ~= sh then
        root:SetSize(sw, math.max(150, math.Round(sh * 0.23)))
        root:SetPos(0, 0)
        makeFonts()
        lastW, lastH = sw, sh
    end

    local players = roster()
    local count = math.min(#players, MAX_VISIBLE)
    local left = math.ceil(count / 2)
    local timerSize = math.Clamp(math.Round(sh * 0.12), 96, 156)
    local ring = math.Clamp(math.Round(timerSize * 0.71), 58, 110)

    for i = 1, count do
        local card = cards[i] or createCard()
        local side = i <= left and -1 or 1
        layoutCard(card, i, side, left, ring, timerSize)
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
