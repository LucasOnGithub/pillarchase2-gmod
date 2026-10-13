-- PC2 client round intro, intermission, role reveal and spectator camera.
-- Adapted from the supplied Roblox EXE intro, Darkness and monster reveal
-- scripts. Faker is not currently imported: stage EXE and play Low + static.
if SERVER then return end

local introPos, introAngle
local currentMode = ""
local modeStarted = 0
local screenClicker = false
local oldSpec = false
local dragging = false
local mouseX, mouseY = 0, 0
local orbit = Angle(8, 0, 0)
local spectateTarget
local stageFontsH = 0
local noiseLast = 0
local noise = {}

net.Receive("PC2_RoundIntroCamera", function()
    introPos = net.ReadVector()
    introAngle = net.ReadAngle()
end)

local function phase()
    return GetGlobalString("PC2_RoundMode", "Waiting")
end

local function participant(ply)
    return IsValid(ply) and ply:GetNWBool("PC2_InRound", false)
end

local function spectator()
    local ply = LocalPlayer()
    return IsValid(ply) and (ply:GetNWString("PC2_RoundRole", "Lobby") == "Spectator"
        or ply:GetNWBool("PC2_Eliminated", false))
end

local function targets()
    local options = {}
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() and participant(ply)
            and not ply:GetNWBool("PC2_Eliminated", false) then
            options[#options + 1] = ply
        end
    end
    table.sort(options, function(a, b) return a:EntIndex() < b:EntIndex() end)
    return options
end

local function switchTarget(offset)
    local options = targets()
    if #options == 0 then spectateTarget = nil return end
    local index = 1
    for i, ply in ipairs(options) do
        if ply == spectateTarget then index = i break end
    end
    spectateTarget = options[((index - 1 + offset) % #options) + 1]
    orbit = Angle(8, spectateTarget:EyeAngles().y, 0)
end

concommand.Add("pc2_spectate_next", function()
    if spectator() then switchTarget(1) end
end)
concommand.Add("pc2_spectate_prev", function()
    if spectator() then switchTarget(-1) end
end)

local function ensureFonts()
    if stageFontsH == ScrH() then return end
    stageFontsH = ScrH()
    local scale = math.Clamp(ScrH() / 1080, 0.67, 1.5)
    surface.CreateFont("PC2_RoundHeadline", {
        font = "Trebuchet MS", size = math.floor(47 * scale),
        weight = 1000, antialias = true
    })
    surface.CreateFont("PC2_RoundMedium", {
        font = "Trebuchet MS", size = math.floor(27 * scale),
        weight = 850, antialias = true
    })
    surface.CreateFont("PC2_RoundSmall", {
        font = "Trebuchet MS", size = math.floor(19 * scale),
        weight = 700, antialias = true
    })
end

local function centerLine(text, font, x, y, color, alpha)
    local col = Color(color.r, color.g, color.b, alpha or 255)
    draw.SimpleTextOutlined(text, font, x, y, col,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, alpha or 255))
end

local function shade(alpha)
    if alpha <= 0 then return end
    surface.SetDrawColor(0, 0, 0, math.Clamp(alpha, 0, 255))
    surface.DrawRect(0, 0, ScrW(), ScrH())
end

local function progress()
    local began = GetGlobalFloat("PC2_PhaseStart", 0)
    local ends = GetGlobalFloat("PC2_PhaseEndsAt", 0)
    local duration = math.max(0.01, ends - began)
    return math.Clamp((CurTime() - began) / duration, 0, 1)
end

local function staticEffect(amp)
    if CurTime() > noiseLast then
        noiseLast = CurTime() + 0.055
        noise = {}
        for i = 1, 70 do
            noise[i] = {
                x = math.Rand(0, 1), y = math.Rand(0, 1),
                w = math.Rand(0.03, 0.4), h = math.Rand(1, 8),
                alpha = math.random(55, 195)
            }
        end
    end
    surface.SetDrawColor(0, 0, 0, 120 * amp)
    surface.DrawRect(0, 0, ScrW(), ScrH())
    for _, stripe in ipairs(noise) do
        surface.SetDrawColor(235, 239, 248, stripe.alpha * amp)
        surface.DrawRect(stripe.x * ScrW(), stripe.y * ScrH(),
            stripe.w * ScrW(), stripe.h)
    end
end

local function onPhaseChange(nextMode)
    currentMode = nextMode
    modeStarted = CurTime()
    local ply = LocalPlayer()
    if nextMode == "Intro" and participant(ply) then
        surface.PlaySound("Map/Intro/Low.wav")
        surface.PlaySound("LobbyGUI/Sounds/DarkFade.wav")
    elseif nextMode == "Tips" and participant(ply) then
        surface.PlaySound("LobbyGUI/Sounds/DarkFade.wav")
    elseif nextMode == "Reveal" and participant(ply) then
        surface.PlaySound("LobbyGUI/Sounds/Fade1.wav")
        surface.PlaySound("LobbyGUI/Sounds/Boom.wav")
    elseif nextMode == "Ending" and participant(ply) then
        surface.PlaySound("LobbyGUI/Sounds/DarkFade.wav")
    elseif nextMode == "Waiting" or nextMode == "Intermission" then
        introPos, introAngle = nil, nil
    end
end

hook.Add("Think", "PC2_RoundClientState", function()
    local nextMode = phase()
    if currentMode ~= nextMode then onPhaseChange(nextMode) end

    local isSpec = spectator()
    if isSpec ~= oldSpec then
        oldSpec = isSpec
        dragging = false
        spectateTarget = nil
        if isSpec then
            orbit = Angle(8, IsValid(LocalPlayer()) and LocalPlayer():EyeAngles().y or 0, 0)
        end
    end

    -- Free the cursor while spectating so inventories and future clickable
    -- interfaces will work; rotate the orbit camera only while RMB is held.
    if screenClicker ~= isSpec then
        screenClicker = isSpec
        gui.EnableScreenClicker(isSpec)
    end
    if not isSpec then return end

    local options = targets()
    if not IsValid(spectateTarget) or not table.HasValue(options, spectateTarget) then
        spectateTarget = options[1]
        if IsValid(spectateTarget) then
            orbit = Angle(8, spectateTarget:EyeAngles().y, 0)
        end
    end

    if input.WasKeyPressed(KEY_RIGHT) then switchTarget(1) end
    if input.WasKeyPressed(KEY_LEFT) then switchTarget(-1) end
    local rmb = input.IsMouseDown(MOUSE_RIGHT)
    local mx, my = gui.MousePos()
    if rmb and dragging then
        orbit.y = math.NormalizeAngle(orbit.y - (mx - mouseX) * 0.3)
        orbit.p = math.Clamp(orbit.p + (my - mouseY) * 0.3, -75, 80)
    end
    dragging = rmb
    mouseX, mouseY = mx, my
end)

hook.Add("CreateMove", "PC2_RoundSpectatorMovement", function(cmd)
    if not spectator() then return end
    cmd:SetForwardMove(0)
    cmd:SetSideMove(0)
    cmd:SetUpMove(0)
end)

hook.Add("CalcView", "PC2_RoundCamera", function(ply, pos, ang, fov)
    local state = phase()
    if state == "Intro" and participant(ply) and introPos and introAngle then
        return {origin = introPos, angles = introAngle, fov = 80, drawviewer = true}
    end
    if (state == "Tips" or state == "Reveal") and participant(ply) then
        -- Camera can resume normally under the completely opaque tip screen.
        return nil
    end
    if not spectator() then return end

    local target = spectateTarget
    if not IsValid(target) or not target:Alive() then
        return {origin = pos, angles = orbit, fov = 85, drawviewer = false}
    end
    -- Follow EXE's actual puppet rather than its hidden pill user.
    local puppet = target:GetNWEntity("PC2_ActiveMonsterPill")
    if IsValid(puppet) and puppet.GetPuppet then
        local visible = puppet:GetPuppet()
        if IsValid(visible) then puppet = visible end
    end
    local origin = (IsValid(puppet) and target:GetNWBool("PC2_IsMonster", false))
        and puppet:WorldSpaceCenter() or target:EyePos()
    local wanted = origin - orbit:Forward() * 155 + Vector(0, 0, 24)
    local tr = util.TraceHull({
        start = origin, endpos = wanted, filter = {ply, target, puppet},
        mins = Vector(-5, -5, -5), maxs = Vector(5, 5, 5),
        mask = MASK_SOLID
    })
    local destination = tr.Hit and (tr.HitPos + tr.HitNormal * 7) or wanted
    return {origin = destination, angles = orbit,
        fov = 85, drawviewer = false}
end)

hook.Add("HUDPaint", "PC2_RoundSequenceScreen", function()
    ensureFonts()
    local state = phase()
    local sw, sh = ScrW(), ScrH()
    local x, y = sw * 0.5, sh * 0.47
    local elapsed = CurTime() - modeStarted
    local white = Color(238, 240, 247)
    local gray = Color(174, 178, 185)
    local red = Color(255, 63, 76)
    local green = Color(93, 248, 122)

    if state == "Waiting" then
        centerLine("WAITING FOR PLAYERS", "PC2_RoundHeadline", x, y, white)
        centerLine("At least 2 players are needed to start intermission.",
            "PC2_RoundSmall", x, y + 52, gray)
    elseif state == "Intermission" then
        local remaining = math.max(0, GetGlobalInt("PC2_TimerSeconds", 60))
        centerLine("INTERMISSION", "PC2_RoundHeadline", x, y, white)
        centerLine(string.format("%01d:%02d", math.floor(remaining / 60),
            remaining % 60), "PC2_RoundMedium", x, y + 57, green)
    elseif state == "Intro" and participant(LocalPlayer()) then
        local t = progress()
        if t < 0.15 then
            shade(255 * (1 - t / 0.15))
        elseif t > 0.83 then
            shade(255 * math.Clamp((t - 0.83) / 0.17, 0, 1))
        end
        -- Original Faker animation is intentionally omitted until imported:
        -- low intro sound, the EXE camera, and a two-stage static-out.
        if t >= 0.46 and t < 0.9 then
            staticEffect(math.min(1, (t - 0.46) * 8))
        end
    elseif state == "Tips" and participant(LocalPlayer()) then
        shade(255)
        local t = progress()
        local opacity = 255 * math.Clamp(math.min(t * 6, (1 - t) * 6), 0, 1)
        centerLine("TIP", "PC2_RoundSmall", x, y - 56, green, opacity)
        centerLine("Listen closely. Use your surroundings.",
            "PC2_RoundMedium", x, y, white, opacity)
        centerLine("Survivors spawn far from EXE. Keep moving.",
            "PC2_RoundSmall", x, y + 55, gray, opacity)
    elseif state == "Reveal" and participant(LocalPlayer()) then
        local t = progress()
        shade(255 * math.Clamp(1 - t * 3.5, 0, 1))
        local isMonster = LocalPlayer():GetNWString("PC2_RoundRole") == "Monster"
        local opacity = 255 * math.Clamp(math.min(t * 5, (1 - t) * 5), 0, 1)
        centerLine(isMonster and "YOU ARE A MONSTER" or "YOU ARE A SURVIVOR",
            "PC2_RoundHeadline", x, y, isMonster and red or green, opacity)
        centerLine(isMonster and "KILL THEM ALL" or "SURVIVE UNTIL THE TIMER ENDS",
            "PC2_RoundMedium", x, y + 58, white, opacity)
    elseif state == "Ending" then
        local t = progress()
        shade(255 * math.Clamp(t * 3, 0, 1))
        centerLine(GetGlobalString("PC2_RoundWinner", "") == "Monster"
            and "MONSTER VICTORY" or "SURVIVORS WIN",
            "PC2_RoundHeadline", x, y, white)
    end

    if spectator() and state == "Survive" then
        local name = IsValid(spectateTarget) and spectateTarget:Nick() or "No players alive"
        centerLine("SPECTATING " .. name, "PC2_RoundMedium",
            x, sh * 0.86, white)
        centerLine("Hold RIGHT MOUSE to turn  |  LEFT / RIGHT ARROWS to switch",
            "PC2_RoundSmall", x, sh * 0.9, gray)
    end
end)

hook.Add("OnReloaded", "PC2_RoundClientCleanup", function()
    if screenClicker then gui.EnableScreenClicker(false) end
    screenClicker, oldSpec, dragging = false, false, false
    introPos, introAngle, spectateTarget = nil, nil, nil
    currentMode = ""
end)
