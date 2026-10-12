-- Pillar Chase 2 - survivor movement and stamina.
-- 1 Roblox stud = 0.28 m, 1 Source map unit ~= 0.01905 m.
local UNITS_PER_STUD = 0.28 / 0.01905

GM.SurvivorWalkStuds = 8
GM.SurvivorRunStuds = 23
GM.SurvivorWalkSpeed = GM.SurvivorWalkStuds * UNITS_PER_STUD
GM.SurvivorRunSpeed = GM.SurvivorRunStuds * UNITS_PER_STUD

-- Temporary settings until we have PC2's actual survivor control script.
-- NewStatsWork is the UI script; it doesn't specify drain/recovery speeds.
GM.SurvivorStaminaMax = 100
GM.SurvivorStaminaDrain = 12.5        -- points/sec (~8 seconds running)
GM.SurvivorStaminaRegen = 20          -- points/sec
GM.SurvivorStaminaRegenDelay = 1.25   -- seconds after stopping
GM.SurvivorStaminaRecovery = 25       -- threshold to recover from exhaustion

-- Before roles exist, every non-monster player is a survivor.
function GM:IsPC2Survivor(ply)
    return IsValid(ply) and ply:IsPlayer()
        and not ply:GetNWBool("PC2_IsMonster", false)
end

function GM:PlayerSpawn(ply, transition)
    self.BaseClass.PlayerSpawn(self, ply, transition)

    if not self:IsPC2Survivor(ply) then return end

    ply:SetWalkSpeed(self.SurvivorWalkSpeed)
    ply:SetRunSpeed(self.SurvivorRunSpeed)
    ply:SetSlowWalkSpeed(self.SurvivorWalkSpeed)

    if SERVER then
        -- New survivor life starts at full stamina.
        ply.PC2Stamina = self.SurvivorStaminaMax
        ply.PC2Exhausted = false
        ply.PC2SprintReleased = true
        ply.PC2RawSprintHeld = false
        ply.PC2LastSprintTime = -100
        ply.PC2NextStaminaSync = 0
        ply:SetNWFloat("PC2_Stamina", ply.PC2Stamina)
        ply:SetNWFloat("PC2_MaxStamina", self.SurvivorStaminaMax)
        ply:SetNWBool("PC2_Exhausted", false)
    end
end

-- Input is filtered in both realms for prediction and authoritative control.
hook.Add("StartCommand", "PC2_SurvivorMovementInput", function(ply, cmd)
    if not GAMEMODE or not GAMEMODE:IsPC2Survivor(ply) then return end

    cmd:RemoveKey(IN_JUMP)

    -- Remember the unfiltered Shift input server-side. Player:KeyDown()
    -- would see our stripped button and incorrectly treat it as released.
    if SERVER then
        ply.PC2RawSprintHeld = cmd:KeyDown(IN_SPEED)
    end

    local exhausted = SERVER and ply.PC2Exhausted
        or (CLIENT and ply:GetNWBool("PC2_Exhausted", false))
    if exhausted then
        cmd:RemoveKey(IN_SPEED)
    end
end)

-- The speed cap also applies while the exhaustion flag is catching up
-- over the network, so holding Shift cannot bypass a zero-stamina lock.
hook.Add("SetupMove", "PC2_SurvivorExhaustionSpeed", function(ply, mv, cmd)
    if not GAMEMODE or not GAMEMODE:IsPC2Survivor(ply) then return end

    local exhausted = SERVER and ply.PC2Exhausted
        or (CLIENT and ply:GetNWBool("PC2_Exhausted", false))
    if not exhausted then return end

    local limit = GAMEMODE.SurvivorWalkSpeed
    if mv:GetMaxSpeed() > limit then
        mv:SetMaxSpeed(limit)
    end
    if mv:GetMaxClientSpeed() > limit then
        mv:SetMaxClientSpeed(limit)
    end
end)

if SERVER then
    local previousTick = CurTime()

    hook.Add("Think", "PC2_ServerSurvivorStamina", function()
        local now = CurTime()
        local dt = math.Clamp(now - previousTick, 0, 0.1)
        previousTick = now
        if dt <= 0 then return end

        local gm = GAMEMODE
        if not gm then return end

        for _, ply in ipairs(player.GetAll()) do
            if not gm:IsPC2Survivor(ply) or not ply:Alive() then continue end
            if ply.PC2Stamina == nil then continue end

            local maxStamina = gm.SurvivorStaminaMax
            local oldStamina = math.Clamp(ply.PC2Stamina, 0, maxStamina)
            local stamina = oldStamina
            local exhausted = ply.PC2Exhausted == true
            local shiftHeld = ply.PC2RawSprintHeld == true

            if not shiftHeld then
                ply.PC2SprintReleased = true
            end

            local moving = ply:GetVelocity():Length2DSqr() > 100
            local sprinting = not exhausted and stamina > 0 and shiftHeld and moving
                and ply:OnGround() and not ply:Crouching()
                and ply:GetMoveType() == MOVETYPE_WALK

            if sprinting then
                stamina = math.max(0, stamina - gm.SurvivorStaminaDrain * dt)
                ply.PC2LastSprintTime = now

                if stamina <= 0 then
                    exhausted = true
                    ply.PC2SprintReleased = false
                end
            elseif now - (ply.PC2LastSprintTime or -100) >= gm.SurvivorStaminaRegenDelay then
                stamina = math.min(maxStamina, stamina + gm.SurvivorStaminaRegen * dt)

                -- Recover enough stamina AND release Shift once after
                -- exhaustion, preventing automatic sprint/winded cycling.
                if exhausted and stamina >= gm.SurvivorStaminaRecovery
                    and ply.PC2SprintReleased then
                    exhausted = false
                end
            end

            ply.PC2Stamina = stamina
            local changedExhaustion = ply.PC2Exhausted ~= exhausted
            if changedExhaustion then
                ply.PC2Exhausted = exhausted
                ply:SetNWBool("PC2_Exhausted", exhausted)
                ply.PC2NextStaminaSync = 0
            end

            -- Server owns stamina. Replicate at most 10 times/second,
            -- with immediate updates when exhaustion starts/ends.
            if now >= (ply.PC2NextStaminaSync or 0) then
                if math.abs(ply:GetNWFloat("PC2_Stamina", maxStamina) - stamina) > 0.001 then
                    ply:SetNWFloat("PC2_Stamina", stamina)
                end
                ply.PC2NextStaminaSync = now + 0.1
            end
        end
    end)
end
