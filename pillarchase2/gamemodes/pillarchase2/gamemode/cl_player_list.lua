-- Top-of-screen Pillar Chase 2 player portraits, framing the round clock.
-- Timer art/countdown remains owned by cl_timer.lua; this draws its neighbors.
if SERVER then return end

local ASSETS = "Server/RoundHandler/GameGui/Top/PlrList/Plr/"
local border = Material(ASSETS .. "Border.png", "smooth")
local death = Material(ASSETS .. "Death.png", "smooth")
-- Monsters use a supplied 2D portrait, never a rendered SpawnIcon.
local exeIcon = Material(
    "Server/RoundHandler/GameGui/NewStats/SelfIcon/Renders/EXEIcon.png",
    "smooth"
)

local GOOD = Color(91, 246, 102)
local BAD = Color(250, 76, 104)
local MAX_VISIBLE = 10

local root, cards = nil, {}
local nextRoster = 0
local lastW, lastH = 0, 0

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

        -- Draw EXE's original 2D UI portrait INSIDE the border opening.
        -- This never renders the monster model or generates a SpawnIcon.
        if self.isEXE then
            local hole = ring * 0.62
            surface.SetMaterial(exeIcon)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.DrawTexturedRect(cx - hole * 0.5, cy - hole * 0.5,
                hole, hole)
        end
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

        -- Monster-chance numbers and the small people indicators are
        -- intentionally omitted until the actual chance system exists.
    end

    cards[#cards + 1] = card
    return card
end

local function updateCard(card, ply)
    card.player = ply
    card.dead = not ply:Alive()

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
    local centerY = timerCenterY -- portraits level with the clock
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
        lastW, lastH = sw, sh
    end

    local players = roster()
    local count = math.min(#players, MAX_VISIBLE)
    local left = math.ceil(count / 2)
    local timerSize = math.Clamp(math.Round(sh * 0.12), 96, 156)
    -- Almost as large as the stopwatch, but still slightly smaller.
    local ring = math.Round(timerSize * 0.86)

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
