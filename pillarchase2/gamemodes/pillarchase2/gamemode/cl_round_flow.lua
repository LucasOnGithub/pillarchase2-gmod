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

-- Copied from the supplied pc2_lobby_cl.lua intermission HUD.
-- The materials belong under content/materials/pc2hud/ on the client.
-- Keep the existing round-phase globals instead of registering the old
-- PC2_LobbyState net receiver (which this gamemode does not send).
local intermissionTimerMat = Material("pc2hud/timer.png", "smooth")
local intermissionLabelMat = Material("pc2hud/font/intermission.png", "smooth")
local intermissionLastSecond
local intermissionPulse = 0
local intermissionPulseSpeed = 5
local intermissionPulseAmount = 0.08
local warnedIntermissionMaterials = false

-- Exact Sound instance properties from the original Roblox LobbyGUI:
--   PlaybackSpeed = 1.25, Volume = 0.65.
-- EmitSound pitch uses 100 = 1.00x and volume uses a 0..1 fraction.
-- -2 is GMod's non-spatial UI sound channel, preserving the original.
local DARKFADE_PITCH = 125
local DARKFADE_VOLUME = 0.65
local function playDarkFade()
    EmitSound("LobbyGUI/Sounds/DarkFade.wav", Vector(0, 0, 0),
        -2, CHAN_AUTO, DARKFADE_VOLUME, 75, 0, DARKFADE_PITCH, 0)
end

-- Exact static textures imported from the original intro UI.
-- The "FirstStatic" and "StaticUI" layers each contain two noise
-- frames. Alternate the actual PNG frames; do not synthesize stripes.
-- Material() may return additional values on this GMod build.
-- Parentheses force a single IMaterial result for EACH table entry,
-- particularly the last expression (Lua otherwise expands its returns).
local firstStaticFrames = {
    (Material("Map/Intro/FirstStatic1.png", "smooth")),
    (Material("Map/Intro/FirstStatic2.png", "smooth"))
}
local staticUIFrames = {
    (Material("Map/Intro/StaticUI1.png", "smooth")),
    (Material("Map/Intro/StaticUI2.png", "smooth"))
}
local missingStaticReported = false

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
-- drawEXETip is defined before the text utilities below. Forward declare
-- so it captures the actual local renderer, not an absent global function.
local centerLine

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

centerLine = function(text, font, x, y, color, alpha)
    local col = Color(color.r, color.g, color.b, alpha or 255)
    draw.SimpleTextOutlined(text, font, x, y, col,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 2, Color(0, 0, 0, alpha or 255))
end

local function shade(alpha)
    if alpha <= 0 then return end
    surface.SetDrawColor(0, 0, 0, math.Clamp(alpha, 0, 255))
    surface.DrawRect(0, 0, ScrW(), ScrH())
end

-- Original pc2_lobby_cl.lua intermission layout, animation and text.
-- HUDPaint reads the authoritative server's PC2_TimerSeconds rather
-- than maintaining a second countdown via a separate net message.
local function drawIntermissionHUD(scrW, remaining)
    if remaining ~= intermissionLastSecond then
        intermissionLastSecond = remaining
        intermissionPulse = intermissionPulseAmount
    else
        intermissionPulse = Lerp(
            math.Clamp(FrameTime() * intermissionPulseSpeed, 0, 1),
            intermissionPulse, 0)
    end

    local baseBoxWidth, baseBoxHeight = 200, 50
    local topY = 50
    local scale = 1 + intermissionPulse
    local boxWidth = baseBoxWidth * scale
    local boxHeight = baseBoxHeight * scale
    local boxX = (scrW - boxWidth) * 0.5
    local boxY = topY - (boxHeight - baseBoxHeight) * 0.5

    local labelWidth, labelHeight = 160, 28
    local labelX = (scrW - labelWidth) * 0.5
    local labelY = boxY - labelHeight - 4

    surface.SetDrawColor(255, 255, 255, 255)
    if not intermissionTimerMat:IsError() then
        surface.SetMaterial(intermissionTimerMat)
        surface.DrawTexturedRect(boxX, boxY, boxWidth, boxHeight)
    end
    if not intermissionLabelMat:IsError() then
        surface.SetMaterial(intermissionLabelMat)
        surface.DrawTexturedRect(labelX, labelY, labelWidth, labelHeight)
    else
        -- No substitute image: text remains readable until the user
        -- commits the original pc2hud images to the repository.
        draw.SimpleText("INTERMISSION", "Trebuchet24", scrW * 0.5,
            labelY + labelHeight * 0.5, Color(255, 255, 255, 255),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    if not warnedIntermissionMaterials
        and (intermissionTimerMat:IsError() or intermissionLabelMat:IsError()) then
        warnedIntermissionMaterials = true
        print("[PC2 Intermission] Expected original materials at "
            .. "materials/pc2hud/timer.png and "
            .. "materials/pc2hud/font/intermission.png")
    end

    local timeText = string.format("%02d:%02d",
        math.floor(remaining / 60), remaining % 60)
    draw.SimpleText(timeText, "Trebuchet24",
        scrW * 0.5, boxY + boxHeight * 0.5,
        Color(255, 255, 255, 255),
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

local function progress()
    local began = GetGlobalFloat("PC2_PhaseStart", 0)
    local ends = GetGlobalFloat("PC2_PhaseEndsAt", 0)
    local duration = math.max(0.01, ends - began)
    return math.Clamp((CurTime() - began) / duration, 0, 1)
end

local function drawImportedStatic(frames, alpha)
    if alpha <= 0 then return end
    -- Alternate the source image frames at 20 Hz. FirstStatic starts
    -- faint (Roblox ImageTransparency = 0.68); StaticUI takes over for
    -- the strong static-out at the end of the intro.
    local frame = frames[(math.floor(RealTime() * 20) % #frames) + 1]
    -- Never index a numeric texture ID or malformed frame as IMaterial;
    -- an invalid frame should log once, not throw every HUDPaint frame.
    if not frame or type(frame) == "number" or frame:IsError() then
        if not missingStaticReported then
            missingStaticReported = true
            print("[PC2 Intro] Missing original static materials under "
                .. "materials/Map/Intro (FirstStatic1/2, StaticUI1/2).")
        end
        return
    end
    surface.SetMaterial(frame)
    surface.SetDrawColor(255, 255, 255, math.Clamp(alpha, 0, 255))
    surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
end

local function onPhaseChange(nextMode)
    currentMode = nextMode
    modeStarted = CurTime()
    local ply = LocalPlayer()
    if nextMode == "Intro" and participant(ply) then
        surface.PlaySound("Map/Intro/Low.wav")
        playDarkFade()
    elseif nextMode == "Tips" and participant(ply) then
        selectedTip = loadEXETip()
        playDarkFade()
    elseif nextMode == "Reveal" and participant(ply) then
        surface.PlaySound("LobbyGUI/Sounds/Fade1.wav")
        surface.PlaySound("LobbyGUI/Sounds/Boom.wav")
    elseif nextMode == "Ending" and participant(ply) then
        playDarkFade()
    elseif nextMode == "Waiting" or nextMode == "Intermission" then
        introPos, introAngle = nil, nil
        selectedTip = nil
        -- Force an 8% pulse on the first countdown update of each
        -- new intermission, exactly like the supplied lobby script.
        intermissionLastSecond = nil
        intermissionPulse = 0
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
        -- Show the normal Intermission artwork and its 01:00 clock while
        -- waiting for the required two players. Do not read the global
        -- timer here: the server holds it at 0 in the Waiting phase.
        -- The actual countdown begins only when Intermission starts.
        drawIntermissionHUD(sw, 60)
    elseif state == "Intermission" then
        local remaining = math.ceil(math.max(
            GetGlobalInt("PC2_TimerSeconds", 60), 0))
        drawIntermissionHUD(sw, remaining)
    elseif state == "Intro" and participant(LocalPlayer()) then
        -- Roblox EXE Intro script:
        --   0.10s wait, then Darkness fades out over 0.45s.
        --   IntroValue >= 2.12 occurs about 1.97s after its tween begins;
        --   Darkness then fades back in over only 0.10s.
        -- Our shortened no-Faker intro keeps these actual timings.
        local seconds = math.max(0, CurTime()
            - GetGlobalFloat("PC2_PhaseStart", CurTime()))
        if seconds < 0.1 then
            shade(255)
        elseif seconds < 0.55 then
            shade(255 * (1 - (seconds - 0.1) / 0.45))
        elseif seconds >= 1.97 and seconds < 2.07 then
            shade(255 * (seconds - 1.97) / 0.1)
        elseif seconds >= 2.07 then
            shade(255)
        end
        -- The imported source static image fades to 32% opacity in
        -- 1.22 seconds from the 0.93-second cue. Follow it with the
        -- actual StaticUI PNGs for the static-out.
        if seconds >= 0.93 and seconds < 2.12 then
            drawImportedStatic(firstStaticFrames,
                82 * math.Clamp((seconds - 0.93) / 1.22, 0, 1))
        elseif seconds >= 2.12 and seconds < 3.8 then
            drawImportedStatic(staticUIFrames, 255)
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
    intermissionLastSecond = nil
    intermissionPulse = 0
    currentMode = ""
end)
