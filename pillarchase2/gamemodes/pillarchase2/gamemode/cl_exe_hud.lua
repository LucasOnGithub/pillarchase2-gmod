-- EXE monster HUD, adapted to the PC2 NewStats-style artwork.
-- The screenshot shows a character portrait, player name, amber
-- circular stamina meter, purple statistic circle and a low health bar.
-- All displayed health/stamina/trap numbers are REAL networked values;
-- no fabricated XP, level, or kill statistics are shown.
if SERVER then return end

local splash = Material("Server/RoundHandler/GameGui/NewStats/SelfIcon.png", "smooth")
local assetDir = "Server/RoundHandler/GameGui/NewStats/SelfIcon/ViewportFrame/NewStatsWork/Stuff/"
local staminaArt = {
    Material(assetDir .. "Stamina1.png", "smooth"),
    Material(assetDir .. "Stamina2.png", "smooth"),
    Material(assetDir .. "Stamina3.png", "smooth")
}
local trapArt = Material("Server/RoundHandler/GameGui/NewStats/SelfIcon/Heart.png", "smooth")
-- The real imported EXE portrait, added to main while this change was in progress.
local exePortrait = Material(
    "Server/RoundHandler/GameGui/NewStats/SelfIcon/Renders/EXE.png", "smooth")
local white = Color(255, 255, 255)
local outline = Color(0, 0, 0, 235)
local gold = Color(254, 187, 56)
local magenta = Color(235, 47, 163)
local ink = Color(12, 10, 21, 175)

local panel
local cachedSize

local function scale()
    return math.Clamp(ScrH() / 1080, 0.67, 1.45)
end

local function px(v)
    return math.floor(v * scale() + 0.5)
end

-- pk_pills.getMappedEnt uses a Lua-side player field. On the client,
-- it can be missing while the replicated costume/player data is loading.
-- The server now also publishes the currently active EXE pill on the player.
local function exePill(ply)
    if not IsValid(ply) or not ply:Alive() then return end

    local networked = ply:GetNWEntity("PC2_ActiveMonsterPill")
    if IsValid(networked) and networked.GetPillForm
        and networked:GetPillForm() == "pc2_exe" then
        return networked
    end

    if pk_pills and pk_pills.getMappedEnt then
        local mapped = pk_pills.getMappedEnt(ply)
        if IsValid(mapped) and mapped.GetPillForm
            and mapped:GetPillForm() == "pc2_exe" then
            return mapped
        end
    end
end

local function isEXEMonster(ply)
    if not IsValid(ply) or not ply:Alive() then return false end

    -- The role marker allows the HUD to show as soon as a player morphs,
    -- even if the costume entity is not available clientside yet.
    if ply:GetNWBool("PC2_IsMonster", false)
        and ply:GetNWString("PC2_MonsterForm", "") == "pc2_exe" then
        return true
    end

    return IsValid(exePill(ply))
end

local function showImage(img, x, y, w, h, tint)
    tint = tint or white
    surface.SetMaterial(img)
    surface.SetDrawColor(tint.r, tint.g, tint.b, tint.a or 255)
    surface.DrawTexturedRect(px(x), px(y), px(w), px(h))
end

local function drawRing(cx, cy, radius, ratio, color)
    cx, cy, radius = px(cx), px(cy), px(radius)
    draw.RoundedBox(radius, cx - radius, cy - radius,
        radius * 2, radius * 2, ink)

    local inner, outer = radius - px(7), radius - px(2)
    local segments = 48
    local filled = math.Clamp(ratio, 0, 1) * segments
    surface.SetDrawColor(color)
    draw.NoTexture()
    for i = 0, segments - 1 do
        local portion = math.Clamp(filled - i, 0, 1)
        if portion > 0 then
            local a = -math.pi / 2 + (i / segments) * math.pi * 2
            local b = -math.pi / 2 + ((i + portion) / segments) * math.pi * 2
            local ca, sa, cb, sb = math.cos(a), math.sin(a), math.cos(b), math.sin(b)
            surface.DrawPoly({
                { x = cx + inner * ca, y = cy + inner * sa },
                { x = cx + outer * ca, y = cy + outer * sa },
                { x = cx + outer * cb, y = cy + outer * sb },
                { x = cx + inner * cb, y = cy + inner * sb }
            })
        end
    end
end

local function fonts()
    local size = ScrH()
    if cachedSize == size then return end
    cachedSize = size
    surface.CreateFont("PC2_EXEStatsName", {
        font = "Georgia", size = px(18), weight = 850, antialias = true
    })
    surface.CreateFont("PC2_EXEStatsNumber", {
        font = "Trebuchet MS", size = px(26), weight = 1000, antialias = true
    })
    surface.CreateFont("PC2_EXEStatsSmall", {
        font = "Trebuchet MS", size = px(16), weight = 900, antialias = true
    })
end

local function createHUD()
    if IsValid(panel) then panel:Remove() end
    cachedSize = nil
    panel = vgui.Create("DPanel")
    panel:SetPaintBackground(false)
    panel:SetMouseInputEnabled(false)
    panel:SetKeyboardInputEnabled(false)
    panel:SetZPos(-90)

    local function resize()
        panel:SetSize(px(352), px(332))
        panel:SetPos(px(7), ScrH() - px(339))
        fonts()
    end
    resize()

    -- Keep sizing separate from visibility. Hidden GMod VGUI panels
    -- may stop running their Think, so the global hook below must control
    -- visibility even while the monster HUD is not on screen.
    panel.PC2Resize = resize

    panel.Paint = function()
        -- Same ink-splash material as the survivor HUD reference.
        showImage(splash, -22, 44, 353, 288)
        -- EXE portrait has transparent edges matching the reference UI.
        showImage(exePortrait, 19, 94, 179, 183)
    end

    panel.PaintOver = function()
        local ply = LocalPlayer()
        if not isEXEMonster(ply) then return end
        local pill = exePill(ply)

        local name = ply:Nick()
        if #name > 18 then name = string.sub(name, 1, 17) .. "..." end
        draw.SimpleTextOutlined(name, "PC2_EXEStatsName",
            px(111), px(80), white,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, px(1), outline)

        local maximum = math.max(1, ply:GetNWFloat("PC2_MaxStamina", 105))
        local stamina = math.Clamp(ply:GetNWFloat("PC2_Stamina", maximum), 0, maximum)
        local ratio = stamina / maximum
        local state = ratio >= .6 and 1 or ratio >= .25 and 2 or 3
        local traps = math.Clamp(IsValid(pill)
            and pill:GetNWInt("PC2_EXE_TrapCount",
                ply:GetNWInt("PC2_EXE_TrapCount", 0))
            or ply:GetNWInt("PC2_EXE_TrapCount", 0), 0, 5)

        -- Amber stamina meter (105 max), purple trap counter (0..5).
        drawRing(295, 162, 41, ratio, gold)
        showImage(staminaArt[state], 276, 138, 38, 43,
            Color(219, 146, 42, 225))
        draw.SimpleTextOutlined(tostring(math.floor(stamina)), "PC2_EXEStatsNumber",
            px(295), px(171), Color(255, 220, 151),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, px(2), outline)

        drawRing(221, 99, 34, traps / 5, magenta)
        showImage(trapArt, 204, 77, 34, 39,
            Color(243, 60, 190, 215))
        draw.SimpleTextOutlined(tostring(traps), "PC2_EXEStatsNumber",
            px(221), px(105), Color(255, 142, 228),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, px(2), outline)
        draw.SimpleTextOutlined("TRAPS", "PC2_EXEStatsSmall",
            px(221), px(141), white,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, px(1), outline)

        local health = math.max(0, ply:Health())
        local maxHP = math.max(1, ply:GetMaxHealth())
        local fraction = math.Clamp(health / maxHP, 0, 1)
        draw.RoundedBox(px(4), px(39), px(291), px(169), px(28),
            Color(8, 6, 9, 221))
        draw.RoundedBox(px(3), px(44), px(296), px(159), px(18),
            Color(61, 30, 30, 239))
        draw.RoundedBox(px(3), px(44), px(296),
            math.max(0, px(159) * fraction), px(18),
            Color(250, 129, 80, 232))
        draw.SimpleTextOutlined(string.format("%d / %d", health, maxHP),
            "PC2_EXEStatsSmall", px(123), px(305), white,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, px(1), outline)
    end
end

hook.Add("Think", "PC2_CreateEXEMonsterHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    if not IsValid(panel) then createHUD() end
    if not IsValid(panel) then return end

    -- This hook keeps running even if the panel is hidden. It also
    -- immediately hides the monster HUD after EXE is restored/removed.
    local show = isEXEMonster(ply)
    if panel:IsVisible() ~= show then panel:SetVisible(show) end
    if show and panel.PC2Resize
        and (panel:GetWide() ~= px(352) or panel:GetTall() ~= px(332)
            or panel.y ~= ScrH() - px(339)) then
        panel.PC2Resize()
    end
end)

hook.Add("OnReloaded", "PC2_ReloadEXEMonsterHUD", function()
    if IsValid(panel) then panel:Remove() end
    panel = nil
end)
