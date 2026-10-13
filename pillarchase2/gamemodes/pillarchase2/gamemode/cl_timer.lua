-- Pillar Chase 2 - round timer HUD (client).
-- Uses the original UI artwork in content/materials/Server/RoundHandler/GameGui/Timer/.
-- No round handler exists yet, so PC2_TimerSeconds defaults to 0 (0:00).
--
-- A future server-side round handler can drive this by calling:
--   SetGlobalInt("PC2_TimerSeconds", secondsRemaining)
--   SetGlobalInt("PC2_TimerMaxSeconds", roundDuration)
--   SetGlobalString("PC2_RoundMode", "Survive") -- or "Intermission"
--
-- The hand follows the original WorkTimerUI rotation:
--   -secondsRemaining / roundDuration * 360
-- and the dial briefly pulses when the displayed second changes.

local assets = "Server/RoundHandler/GameGui/Timer/"
local clockBackground = Material(assets .. "TimerBackground.png", "smooth")
local clockHand = Material(assets .. "TimerHand.png", "smooth")
local clockGlow = Material(assets .. "Glow.png", "smooth")

local white = Color(255, 255, 255)
local danger = Color(255, 75, 75)
local softWhite = Color(225, 225, 225)
local textOutline = Color(0, 0, 0, 220)

local lastSeconds
local pulseStarted = -100
local handAngle
local fontHeight

local function formatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function drawTexture(texture, x, y, size, color, angle)
    surface.SetMaterial(texture)
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)

    if angle ~= nil then
        surface.DrawTexturedRectRotated(x, y, size, size, angle)
    else
        surface.DrawTexturedRect(x - size / 2, y - size / 2, size, size)
    end
end

local function ensureFont()
    local height = ScrH()
    if fontHeight == height then return end

    fontHeight = height
    surface.CreateFont("PC2_RoundTimer", {
        font = "Trebuchet MS",
        size = math.Clamp(math.Round(height * 0.026), 18, 32),
        weight = 950,
        antialias = true
    })
end

hook.Add("HUDPaint", "PC2_RoundTimerHUD", function()
    local ply = LocalPlayer()
    -- The lobby/intermission has its own countdown UI. The clock only
    -- belongs to a living round participant once gameplay starts.
    if not IsValid(ply) or not ply:GetNWBool("PC2_InRound", false)
        or ply:GetNWBool("PC2_Eliminated", false)
        or GetGlobalString("PC2_RoundMode", "Waiting") ~= "Survive" then
        lastSeconds = nil
        return
    end
    ensureFont()

    -- For now these are both zero: the round handler will set them later.
    local seconds = math.max(0, GetGlobalInt("PC2_TimerSeconds", 0))
    local maxSeconds = math.max(0, GetGlobalInt("PC2_TimerMaxSeconds", 0))
    local intermission = GetGlobalString("PC2_RoundMode", "Survive") == "Intermission"
    local lowTime = seconds <= (intermission and 10 or 20)

    if lastSeconds ~= nil and lastSeconds ~= seconds then
        pulseStarted = RealTime()
    end
    lastSeconds = seconds

    -- Roblox's 6 -> 6.35 -> 6 dial size tween (.15s out, .25s back).
    local elapsed = RealTime() - pulseStarted
    local pulse = 0

    if elapsed >= 0 and elapsed < 0.15 then
        pulse = (6.35 / 6 - 1) * math.sin((elapsed / 0.15) * math.pi / 2)
    elseif elapsed >= 0.15 and elapsed < 0.4 then
        pulse = (6.35 / 6 - 1) * (1 - (elapsed - 0.15) / 0.25)
    end

    local size = math.Clamp(math.Round(ScrH() * 0.12), 96, 156) * (1 + pulse)
    local x = ScrW() * 0.5
    local y = math.Round(12 + math.Clamp(math.Round(ScrH() * 0.12), 96, 156) * 0.5)

    local color = (not intermission and lowTime) and danger or white
    local handColor = (not intermission and lowTime) and danger or softWhite

    -- The Roblox timer hand completes one revolution during a full countdown.
    local targetAngle = 0
    if maxSeconds > 0 then
        targetAngle = -math.Clamp(seconds / maxSeconds, 0, 1) * 360
    end
    if handAngle == nil then
        handAngle = targetAngle
    else
        -- Match the original UI's 0.15-second tween when the timer changes.
        handAngle = Lerp(math.Clamp(FrameTime() / 0.15, 0, 1), handAngle, targetAngle)
    end

    -- The glow is drawn first so the clock outline/hand stay clearly visible.
    local glowColor = Color(handColor.r, handColor.g, handColor.b, 30)
    drawTexture(clockGlow, x, y + size * 0.045, size * 0.96, glowColor)

    drawTexture(clockBackground, x, y, size, color)
    drawTexture(clockHand, x, y, size, handColor, handAngle)

    -- Center text is drawn last so the hand never obscures the digits.
    draw.SimpleTextOutlined(
        formatTime(seconds), "PC2_RoundTimer",
        x, y + size * 0.045,
        color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER,
        2, textOutline
    )
end)
