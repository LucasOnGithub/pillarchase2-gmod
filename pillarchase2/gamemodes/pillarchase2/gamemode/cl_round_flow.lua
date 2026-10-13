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

-- The Roblox original chooses a random ImageLabel under
-- LobbyGUI.Tips.EXE, then fades it and its TextLabel descendants.
-- The TextLabel.Text values live in the GUI instances, not the script.
-- These gameplay descriptions are provisional until the originals arrive.
local EXE_TIP_DIR = "LobbyGUI/Tips/EXE/"
local EXE_TIP_TEXT = {
    {
        keyword = "Too Slow",
        title = "TOO SLOW",
        text = "EXE can charge forward and grab survivors. Get out of his path!"
    },
    {
        keyword = "Thorny Grave",
        title = "THORNY GRAVE",
        text = "Watch for EXE's traps on the ground. Struggle to escape if caught!"
    }
}
local selectedTip
local warnedMissingTipArt = false

local function loadEXETip()
    local dir = "materials/" .. EXE_TIP_DIR
    -- Loose .png/.jpg files in gamemodes/pillarchase2/content/materials
    -- are found by the GAME search path on installed GMod clients.
    local paths, used = {}, {}
    for _, extension in ipairs({"png", "jpg", "jpeg", "vmt"}) do
        local found = file.Find(dir .. "*." .. extension, "GAME") or {}
        for _, name in ipairs(found) do
            if not used[name] then
                used[name] = true
                paths[#paths + 1] = name
            end
        end
    end
    table.sort(paths)
    local chosen = #paths > 0 and math.random(#paths) or 0
    local fileName = paths[chosen]
    if not fileName then
        if not warnedMissingTipArt then
            warnedMissingTipArt = true
            print("[PC2 Tips] No imported images found in materials/"
                .. EXE_TIP_DIR
                .. " (they must be installed/mounted on this client).")
        end
        local entry = EXE_TIP_TEXT[math.random(#EXE_TIP_TEXT)]
        return {material = nil, title = entry.title, text = entry.text}
    end

    local lowered = string.lower(fileName)
    -- Support descriptive files and the common Roblox 1/2 or Tip1/Tip2
    -- naming scheme. Unnamed images rotate between the two subjects.
    local index
    if string.find(lowered, "thorn", 1, true)
        or string.find(lowered, "grave", 1, true)
        or string.find(lowered, "tip2", 1, true)
        or string.find(lowered, "2.", 1, true) then
        index = 2
    elseif string.find(lowered, "slow", 1, true)
        or string.find(lowered, "tip1", 1, true)
        or string.find(lowered, "1.", 1, true) then
        index = 1
    else
        index = ((chosen - 1) % #EXE_TIP_TEXT) + 1
    end
    local entry = EXE_TIP_TEXT[index]
    local materialPath = EXE_TIP_DIR .. fileName
    local mat = Material(materialPath, "smooth")
    if mat:IsError() then
        print("[PC2 Tips] Could not load material: " .. materialPath)
        mat = nil
    end
    return {
        material = mat,
        fileName = fileName,
        title = entry.title,
        text = entry.text
    }
end

local function drawEXETip(sw, sh, alpha)
    if not selectedTip then return end
    local art = selectedTip.material
    if art then
        -- Preserve the source image's aspect ratio instead of stretching it.
        local maxW, maxH = sw * 0.76, sh * 0.64
        local w, h = math.max(1, art:Width()), math.max(1, art:Height())
        local scale = math.min(maxW / w, maxH / h)
        local imageW, imageH = w * scale, h * scale
        surface.SetDrawColor(255, 255, 255, alpha)
        surface.SetMaterial(art)
        surface.DrawTexturedRect((sw - imageW) * 0.5,
            sh * 0.46 - imageH * 0.5, imageW, imageH)
    end

    -- The TextLabels in the original Roblox GUI were independent
    -- descendants of each ImageLabel, fading alongside the image.
    -- Keep captions separate so the source PNG remains unchanged.
    local centerX = sw * 0.5
    local captionY = sh * 0.81
    local captionW = math.min(sw * 0.76, 1160 * sh / 1080)
    surface.SetDrawColor(0, 0, 0, math.floor(alpha * 0.72))
    surface.DrawRect(centerX - captionW * 0.5,
        captionY - sh * 0.055, captionW, sh * 0.12)
    centerLine(selectedTip.title, "PC2_RoundMedium",
        centerX, captionY - sh * 0.023,
        Color(110, 245, 123), alpha)
    centerLine(selectedTip.text, "PC2_RoundSmall",
        centerX, captionY + sh * 0.02,
        Color(238, 240, 247), alpha)
end

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
        selectedTip = loadEXETip()
        surface.PlaySound("LobbyGUI/Sounds/DarkFade.wav")
    elseif nextMode == "Reveal" and participant(ply) then
        surface.PlaySound("LobbyGUI/Sounds/Fade1.wav")
        surface.PlaySound("LobbyGUI/Sounds/Boom.wav")
    elseif nextMode == "Ending" and participant(ply) then
        surface.PlaySound("LobbyGUI/Sounds/DarkFade.wav")
    elseif nextMode == "Waiting" or nextMode == "Intermission" then
        introPos, introAngle = nil, nil
        selectedTip = nil
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
        -- Solid black backing hides the delayed EXE morph and teleport.
        -- The original tip ImageLabel and its TextLabels fade together:
        -- 0.6s fade in; fade the tip out near the end of the five seconds.
        shade(255)
        local t = progress()
        local secondsLeft = math.max(0,
            GetGlobalFloat("PC2_PhaseEndsAt", CurTime()) - CurTime())
        local fadedIn = math.Clamp((CurTime() - modeStarted) / 0.6, 0, 1)
        local fadedOut = math.Clamp(secondsLeft / 1.0, 0, 1)
        drawEXETip(sw, sh, math.Round(255 * math.min(fadedIn, fadedOut)))
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
    selectedTip = nil
    currentMode = ""
end)
