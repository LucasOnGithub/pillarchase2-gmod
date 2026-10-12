-- EXE monster HUD using the survivor NewStats artwork, meters and XP bar.
-- The 3D survivor preview is replaced with EXE's imported portrait.
-- Existing gameplay values:
--    player:SetNWFloat("PC2_Stamina", value)
--    player:SetNWFloat("PC2_MaxStamina", value)
--    player:SetNWInt("PC2_Earnings", value)
--    player:SetNWInt("PC2_EarningsMax", value)
-- Monster health stays server-side and is intentionally hidden from this HUD.
if SERVER then return end

local PATH = "Server/RoundHandler/GameGui/NewStats/SelfIcon/"
local STUFF = PATH .. "ViewportFrame/NewStatsWork/Stuff/"

local art = {
    splash   = Material("Server/RoundHandler/GameGui/NewStats/SelfIcon.png", "smooth"),
    exe      = Material(PATH .. "Renders/EXE.png", "smooth"),
    currency = Material(PATH .. "Earning.png", "smooth"),
    stamina = {
        Material(STUFF .. "Stamina1.png", "smooth"),
        Material(STUFF .. "Stamina2.png", "smooth"),
        Material(STUFF .. "Stamina3.png", "smooth")
    }
}

local WHITE = Color(255, 255, 255)
local SHADOW = Color(0, 0, 0, 220)
local STAMINA_YELLOW = Color(255, 187, 62)
local EARNINGS_PINK = Color(250, 39, 152)

-- These are local HUD design coordinates in a 358x345 reference layout.
-- They scale as a group on different screen heights.
local W, H = 358, 345
local panel
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
    surface.CreateFont("PC2_EXE_StatsRef_Name", {
        font = "Georgia", size = S(19), weight = 800, antialias = true
    })
    surface.CreateFont("PC2_EXE_StatsRef_Number", {
        font = "Trebuchet MS", size = S(25), weight = 1000, antialias = true
    })
    surface.CreateFont("PC2_EXE_StatsRef_XP", {
        font = "Trebuchet MS", size = S(16), weight = 950, antialias = true
    })
end

-- Read authoritative server identity even while the client pill mapping loads.
local function isEXEMonster(ply)
    if not IsValid(ply) or not ply:Alive() then return false end
    if ply:GetNWBool("PC2_IsMonster", false)
        and ply:GetNWString("PC2_MonsterForm", "") == "pc2_exe" then
        return true
    end
    local pill = ply:GetNWEntity("PC2_ActiveMonsterPill")
    if IsValid(pill) and pill.GetPillForm and pill:GetPillForm() == "pc2_exe" then return true end
    if pk_pills and pk_pills.getMappedEnt then
        pill = pk_pills.getMappedEnt(ply)
        return IsValid(pill) and pill.GetPillForm and pill:GetPillForm() == "pc2_exe"
    end
    return false
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
        tostring(math.floor(number)), "PC2_EXE_StatsRef_Number",
        S(x), S(y), color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
        math.max(1, S(1.8)), SHADOW
    )
end

local function createEXEHUD()
    if IsValid(panel) then panel:Remove() end
    cachedScrH = nil

    panel = vgui.Create("DPanel")
    panel:SetMouseInputEnabled(false)
    panel:SetKeyboardInputEnabled(false)
    panel:SetPaintBackground(false)
    panel:SetZPos(-100)

    local function resize()
        panel:SetSize(S(W), S(H))
        panel:SetPos(S(6), ScrH() - S(H) - S(7))
        fonts()
    end
    resize()

    -- A hidden panel may stop thinking; drive visibility from global Think.
    panel.PC2Resize = resize

    -- Only the game's dark-blue ink texture is behind the model.
    -- No large rectangular panel, separators or HUD labels.
    panel.Paint = function(self, w, h)
        showImage(art.splash, -23, 44, 353, 292, Color(255, 255, 255, 255))
        showImage(art.exe, 10, 92, 187, 202)
    end

    -- PaintOver renders above the portrait so the name and meters remain crisp.
    panel.PaintOver = function(self, w, h)
        local ply = LocalPlayer()
        if not isEXEMonster(ply) then return end

        local maxStamina = math.max(ply:GetNWFloat("PC2_MaxStamina", 100), 1)
        local stamina = math.Clamp(ply:GetNWFloat("PC2_Stamina", maxStamina), 0, maxStamina)
        local staminaRatio = ratio(stamina, maxStamina)
        local staminaState = damageState(staminaRatio)

        local earningsMax = math.max(ply:GetNWInt("PC2_EarningsMax", 100), 1)
        local earnings = math.max(ply:GetNWInt("PC2_Earnings", 0), 0)
        local earningsRatio = ratio(earnings, earningsMax)

        local name = ply:Nick()
        if #name > 18 then name = string.sub(name, 1, 17) .. "..." end
        draw.SimpleTextOutlined(name, "PC2_EXE_StatsRef_Name", S(110), S(99),
            WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, math.max(1, S(1)), SHADOW)

        -- Monster layout:
        -- stamina replaces the survivor HP meter on the right;
        -- earnings occupies the old upper stamina position.
        -- The former bottom earnings circle is intentionally empty.
        local staminaX, staminaY = 305, 157
        local earningsX, earningsY = 241, 99

        draw.RoundedBox(S(40), S(staminaX - 40), S(staminaY - 40),
            S(80), S(80), Color(10, 11, 13, 150))
        draw.RoundedBox(S(37), S(earningsX - 37), S(earningsY - 37),
            S(74), S(74), Color(10, 11, 13, 150))

        circularMeter(staminaX, staminaY, 40, staminaRatio, STAMINA_YELLOW)
        circularMeter(earningsX, earningsY, 37, earningsRatio, EARNINGS_PINK)

        centerImage(art.stamina[staminaState], staminaX, staminaY, 36, 42,
            Color(208, 152, 55, 230))
        centerImage(art.currency, earningsX, earningsY, 58, 58)
        showCount(stamina, staminaX, staminaY + 5, Color(255, 218, 145))
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
        draw.SimpleTextOutlined("XP", "PC2_EXE_StatsRef_XP",
            S(73), S(318), Color(255, 228, 194), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
            math.max(1, S(1)), SHADOW)
        draw.SimpleTextOutlined("-- / --", "PC2_EXE_StatsRef_XP",
            S(143), S(318), WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
            math.max(1, S(1)), SHADOW)
    end
end

hook.Add("Think", "PC2_CreateEXEMonsterHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    if not IsValid(panel) then createEXEHUD() end
    if not IsValid(panel) then return end
    local visible = isEXEMonster(ply)
    if panel:IsVisible() ~= visible then panel:SetVisible(visible) end
    if visible and panel.PC2Resize
        and (panel:GetWide() ~= S(W) or panel:GetTall() ~= S(H)
            or panel.y ~= ScrH() - S(H) - S(7)) then
        panel.PC2Resize()
    end
end)

hook.Add("OnReloaded", "PC2_ReloadEXEMonsterHUD", function()
    if IsValid(panel) then panel:Remove() end
    panel = nil
end)
