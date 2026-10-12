-- Server-authoritative EXE hit audio and survivor broken-bone injury.
-- Sounds originate at the struck survivor, not the monster.
if not SERVER then return end

local HIT_SOUNDS = {
    "Monsters/Hit1.wav",
    "Monsters/Hit2.wav",
    "Monsters/Hit3.wav",
    "Monsters/Hit4.wav"
}
local HURT_SOUND = "Player/Hurt.wav"
local BREAK_SOUND = "Player/BrokenBone.wav"
local DEATH_SCREAM = "Player/DeathScream.mp3"

-- A death is confirmed here (not predicted from incoming damage). The
-- two abilities mark only their own TakeDamageInfo call; ordinary M1 and
-- scripted KillPC2 executions do not carry one of these marks.
hook.Add("PlayerDeath", "PC2_EXEAbilityDeathScream", function(victim)
    if not IsValid(victim) or victim.PC2EXEExecutionVictim then return end

    local source = victim.PC2EXEAbilityDamageSource
    if source ~= "too_slow" and source ~= "thorny_grave" then return end

    -- CHAN_AUTO avoids another voice-channel sound replacing the scream.
    victim:EmitSound(DEATH_SCREAM, 85, 100, 1, CHAN_AUTO)
end)

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

        -- Play the injury sounds ONCE when broken-bone status is first
        -- applied, not again on subsequent hits while it remains active.
        if lowHealth(victim) and not victim:GetNWBool("PC2_BrokenBone", false) then
            victim:SetNWBool("PC2_BrokenBone", true)
            -- Separate channels let the voice and crack play together.
            victim:EmitSound(HURT_SOUND, 75, 100, 1, CHAN_VOICE)
            victim:EmitSound(BREAK_SOUND, 75, 100, 1, CHAN_BODY)
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
