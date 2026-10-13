-- Zero-stamina winded breathing, using sound/Player/Breathing.wav.
-- The 5.7s clip is stopped after exactly 3.25s (or earlier upon death).
-- Only the local survivor hears this sound; no overlapping replays.
if SERVER then return end

local SOUND_PATH = "Player/Breathing.wav"
local breathing
local trackedPlayer

local function stopBreathing()
    if breathing then
        breathing:Stop()
        breathing = nil
    end
end

hook.Add("Think", "PC2_WindedBreathing", function()
    if GetGlobalString("PC2_RoundMode", "Waiting") ~= "Survive" then
        stopBreathing()
        return
    end
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

    -- Client checks the timestamp every frame: the audio stops at the
    -- 3.25-second deadline even before an NWBool=false packet arrives.
    local windedEnd = ply:GetNWFloat("PC2_WindedEnd", 0)
    if windedEnd <= 0 or CurTime() >= windedEnd then
        stopBreathing()
        return
    end

    if not breathing then
        breathing = CreateSound(ply, SOUND_PATH)
        if breathing then breathing:PlayEx(0.8, 100) end
    end
end)

hook.Add("OnReloaded", "PC2_StopWindedBreathingOnReload", stopBreathing)
hook.Add("ShutDown", "PC2_StopWindedBreathingOnExit", stopBreathing)
