-- Broken-bone indicator shown at the middle-left for injured survivors.
-- The project's original asset belongs at content/materials/StatusEffects/BrokenBone.png.
if SERVER then return end

local ICON_PATH = "StatusEffects/BrokenBone.png"
local icon = Material(ICON_PATH, "smooth")
local cachedHeight
local WHITE = Color(255, 255, 255)
local TEXT = Color(241, 228, 216)
local SHADOW = Color(0, 0, 0, 225)

local function S(v)
    return math.floor(v * math.Clamp(ScrH() / 1080, 0.67, 1.45) + 0.5)
end

local function ensureFonts()
    if cachedHeight == ScrH() then return end
    cachedHeight = ScrH()
    surface.CreateFont("PC2_BrokenBoneTitle", {
        font = "Trebuchet MS", size = S(17), weight = 1000, antialias = true
    })
    surface.CreateFont("PC2_BrokenBoneDetail", {
        font = "Trebuchet MS", size = S(13), weight = 850, antialias = true
    })
end

hook.Add("HUDPaint", "PC2_BrokenBoneStatusHUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive()
        or ply:GetNWBool("PC2_IsMonster", false)
        or not ply:GetNWBool("PC2_BrokenBone", false) then return end

    ensureFonts()
    local x, y = S(16), math.floor(ScrH() * 0.48)
    local w, h = S(204), S(62)
    draw.RoundedBox(S(5), x, y, w, h, Color(15, 11, 15, 205))
    surface.SetDrawColor(166, 61, 66, 245)
    surface.DrawOutlinedRect(x, y, w, h, math.max(1, S(2)))

    local size = S(45)
    local ix, iy = x + S(8), y + math.floor((h - size) * .5)
    if not icon:IsError() then
        surface.SetMaterial(icon)
        surface.SetDrawColor(255, 255, 255, 255)
        surface.DrawTexturedRect(ix, iy, size, size)
    else
        -- Fallback only when BrokenBone.png has not yet been installed.
        draw.RoundedBox(S(4), ix, iy, size, size, Color(89, 30, 36, 210))
        surface.SetDrawColor(WHITE)
        local cx, cy = ix + size / 2, iy + size / 2
        surface.DrawLine(cx - S(12), cy + S(12), cx - S(2), cy + S(2))
        surface.DrawLine(cx + S(2), cy - S(2), cx + S(12), cy - S(12))
        surface.DrawLine(cx - S(9), cy - S(13), cx + S(9), cy + S(13))
    end

    local tx = x + S(64)
    draw.SimpleTextOutlined("BROKEN BONE", "PC2_BrokenBoneTitle",
        tx, y + S(13), TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, SHADOW)
    draw.SimpleTextOutlined("-15% MOVE SPEED", "PC2_BrokenBoneDetail",
        tx, y + S(36), WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, SHADOW)
end)
