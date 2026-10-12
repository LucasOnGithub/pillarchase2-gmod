-- The local player's zero-stamina breathing sound.
-- Uses the existing 5.73-second WAV in content/sound/Player/Breathing.wav.
-- No breathing sounds are produced for ordinary stamina depletion
-- until the authoritative PC2_Exhausted state becomes true.
if SERVER then return end

local SOUND_PATH = "Player/Breathing.wav"
local BREATH_CLIP_DURATION = 5.73
local breathing
local trackedPlayer
local nextPlayback = 0

local function stopBreathing()
    if breathing then
        breathing:Stop()
        breathing = nil
    end
    nextPlayback = 0
end

hook.Add("Think", "PC2_WindedBreathing", function()
    local ply = LocalPlayer()

    if ply ~= trackedPlayer then
        stopBreathing()
        trackedPlayer = ply
    end

    if not IsValid(ply) or not ply:Alive()
        or ply:GetNWBool("PC2_IsMonster", false)
        or not ply:GetNWBool("PC2_Exhausted", false) then
        stopBreathing()
        return
    end

    if not breathing then
        breathing = CreateSound(ply, SOUND_PATH)
    end

    -- The clip repeats without overlapping while the survivor is exhausted.
    if breathing and RealTime() >= nextPlayback then
        breathing:Stop()
        breathing:PlayEx(0.8, 100)
        nextPlayback = RealTime() + BREATH_CLIP_DURATION
    end
end)

hook.Add("OnReloaded", "PC2_StopWindedBreathingOnReload", stopBreathing)
hook.Add("ShutDown", "PC2_StopWindedBreathingOnExit", stopBreathing)
