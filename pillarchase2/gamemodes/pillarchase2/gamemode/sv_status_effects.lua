-- Server-authoritative EXE hit audio and survivor broken-bone injury.
-- Sounds originate at the struck survivor, not the monster.
if not SERVER then return end

-- Ensure clients on dedicated servers download the uniquely named voice clip.
resource.AddFile("sound/pc2_status/hurt_voice.wav")

local HIT_SOUNDS = {
    "Monsters/Hit1.wav",
    "Monsters/Hit2.wav",
    "Monsters/Hit3.wav",
    "Monsters/Hit4.wav"
}
-- Unique path avoids Source/GMod or addon sound files shadowing our audio.
local HURT_SOUND = "pc2_status/hurt_voice.wav"
local BREAK_SOUND = "Player/BrokenBone.wav"

local function survivor(ply)
    return IsValid(ply) and ply:IsPlayer()
        and not ply:GetNWBool("PC2_IsMonster", false)
end

local function exeDamage(dmg)
    local attacker = dmg:GetAttacker()
    if IsValid(attacker) and attacker:IsPlayer()
        and attacker:GetNWString("PC2_MonsterForm", "") == "pc2_exe" then
        return true
    end

    local inflictor = dmg:GetInflictor()
    return IsValid(inflictor) and inflictor.GetPillForm
        and inflictor:GetPillForm() == "pc2_exe"
end

local function lowHealth(ply)
    return ply:Health() > 0
        and ply:Health() <= math.max(1, ply:GetMaxHealth()) * 0.25
end

hook.Add("PostEntityTakeDamage", "PC2_EXEHitAndBrokenBoneSounds",
    function(victim, dmg, wasDamageTaken)
        if not survivor(victim) or wasDamageTaken == false
            or dmg:GetDamage() <= 0 then return end

        -- A random impact clip for every damaging EXE strike/grab/trap tick.
        if exeDamage(dmg) then
            victim:EmitSound(HIT_SOUNDS[math.random(#HIT_SOUNDS)],
                75, 100, 1, CHAN_AUTO)
        end

        -- Any further damage while critically injured plays both clips.
        -- The hit crossing the 25% threshold counts as well.
        if lowHealth(victim) then
            -- Distinct channels: the injury voice should not be replaced
            -- by the bone-crack sound emitted from the same victim.
            victim:EmitSound(HURT_SOUND, 75, 100, 1, CHAN_VOICE)
            victim:EmitSound(BREAK_SOUND, 75, 100, 1, CHAN_BODY)
            if not victim:GetNWBool("PC2_BrokenBone", false) then
                victim:SetNWBool("PC2_BrokenBone", true)
            end
        end
    end)

-- Clear injury after healing above 25% or on death. The status also gets
-- reset in PlayerSpawn, so it cannot persist into the next life.
local nextCheck = 0
hook.Add("Think", "PC2_UpdateBrokenBoneStatus", function()
    local now = CurTime()
    if now < nextCheck then return end
    nextCheck = now + 0.15

    for _, ply in ipairs(player.GetAll()) do
        local active = survivor(ply) and ply:Alive() and lowHealth(ply)
        if ply:GetNWBool("PC2_BrokenBone", false) ~= active then
            ply:SetNWBool("PC2_BrokenBone", active)
        end
    end
end)
