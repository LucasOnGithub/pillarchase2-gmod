-- Pillar Chase 2 - survivor movement and stamina.
-- Roblox speed: 8 studs/s walk, 23 studs/s sprint.
-- Map scale: 1 stud = 0.28m; 1 Source unit ~= 0.01905m.
local UNITS_PER_STUD = 0.28 / 0.01905

GM.SurvivorWalkStuds = 8
GM.SurvivorRunStuds = 23
GM.SurvivorWalkSpeed = GM.SurvivorWalkStuds * UNITS_PER_STUD
GM.SurvivorRunSpeed = GM.SurvivorRunStuds * UNITS_PER_STUD

-- Unlike the original Roblox studs/s values, Source's movement pipeline
-- can apply a global sv_maxspeed ceiling (often 320 units/s). Our requested
-- 23 Roblox studs/s equals ~338 Source units/s, so make sure the server
-- ceiling is not lower than the intended survivor run speed.
local function ensureSourceSpeedCeiling()
    if not SERVER then return end
    local cap = GetConVar("sv_maxspeed")
    if not cap then return end
    local required = math.ceil(GM.SurvivorRunSpeed)
    if cap:GetFloat() < required then
        cap:SetFloat(required)
        print(string.format("[PC2 Movement] sv_maxspeed raised to %d "
            .. "to allow the full 23-stud/s survivor sprint.", required))
    end
end

-- PC2 Wiki survivor stamina figures supplied by the project author:
-- -2 / 0.2s sprinting, +4 / 0.2s while resting, winded for 3.25s.
GM.SurvivorStaminaMax = 100
GM.SurvivorStaminaInterval = 0.2
GM.SurvivorStaminaDrainPerTick = 2
GM.SurvivorStaminaRegenPerTick = 4
GM.SurvivorWindedDuration = 3.25

-- All players spawn as Dr. Kleiner by default. Morphs retain their own
-- separate puppet model while active; unmorphing respawns as Kleiner.
function GM:PlayerSetModel(ply)
    if SERVER and IsValid(ply) then
        ply:SetModel("models/player/kleiner.mdl")
    end
end

-- Until roles exist, every player not explicitly marked as a monster
-- is treated as a survivor. Monsters will get separate movement rules.
function GM:IsPC2Survivor(ply)
    return IsValid(ply) and ply:IsPlayer()
        and not ply:GetNWBool("PC2_IsMonster", false)
end

function GM:PlayerSpawn(ply, transition)
    -- Injury never carries across spawns or returning to survivor form.
    if SERVER then ply:SetNWBool("PC2_BrokenBone", false) end
    -- Allow the base player class to set its normal model and loadout.
    self.BaseClass.PlayerSpawn(self, ply, transition)
    if not self:IsPC2Survivor(ply) then return end

    ply:SetWalkSpeed(self.SurvivorWalkSpeed)
    ply:SetRunSpeed(self.SurvivorRunSpeed)
    ply:SetSlowWalkSpeed(self.SurvivorWalkSpeed)

    if SERVER then
        ensureSourceSpeedCeiling()
        ply.PC2Stamina = self.SurvivorStaminaMax
        ply.PC2Winded = false
        ply.PC2WindedEnd = 0
        ply.PC2SprintReleaseRequired = false
        ply.PC2RawSprintHeld = false
        ply.PC2NextStaminaTick = CurTime() + self.SurvivorStaminaInterval

        ply:SetNWFloat("PC2_Stamina", ply.PC2Stamina)
        ply:SetNWFloat("PC2_MaxStamina", self.SurvivorStaminaMax)
        ply:SetNWFloat("PC2_WindedEnd", 0)
        ply:SetNWBool("PC2_Exhausted", false)
        ply:SetNWBool("PC2_SprintReleaseRequired", false)
    end
end

local function sprintBlocked(ply)
    if SERVER then
        return ply.PC2Winded == true
            or ply.PC2SprintReleaseRequired == true
            or (ply.PC2Stamina ~= nil and ply.PC2Stamina <= 0)
    end

    return ply:GetNWBool("PC2_Exhausted", false)
        or ply:GetNWBool("PC2_SprintReleaseRequired", false)
        or ply:GetNWFloat("PC2_Stamina", 100) <= 0
end

-- Both client and server filter jump/sprint for correct prediction.
hook.Add("StartCommand", "PC2_SurvivorMovementInput", function(ply, cmd)
    if not GAMEMODE or not GAMEMODE:IsPC2Survivor(ply) then return end

    -- Read the *unfiltered* Shift key, before we strip IN_SPEED.
    if SERVER then
        local shiftHeld = cmd:KeyDown(IN_SPEED)
        ply.PC2RawSprintHeld = shiftHeld

        -- After winded, require a release of Shift before sprinting
        -- again, to prevent endlessly running -> 0 -> winded on hold.
        if ply.PC2SprintReleaseRequired and not shiftHeld then
            ply.PC2SprintReleaseRequired = false
            ply:SetNWBool("PC2_SprintReleaseRequired", false)
        end
    end

    cmd:RemoveKey(IN_JUMP)
    if sprintBlocked(ply) then
        cmd:RemoveKey(IN_SPEED)
    end
end)

-- Enforce both movement caps on SERVER and CLIENT every prediction tick,
-- not only on PlayerSpawn. The stamina module previously only *reduced*
-- the caps on exhaustion, so it could never correct a 320-unit Source cap,
-- stale spawn speed, or slow client-side prediction after stamina changes.
-- Normal healthy movement is strictly 8/23 Roblox studs per second.
hook.Add("SetupMove", "PC2_SurvivorExactMoveSpeed", function(ply, mv)
    if not GAMEMODE or not GAMEMODE:IsPC2Survivor(ply)
        or not ply:Alive() or ply:GetNWBool("PC2_Eliminated", false) then
        return
    end

    -- IN_SPEED has already been stripped by StartCommand when exhausted.
    -- A held +walk bind never counts as sprinting.
    local buttons = mv:GetButtons()
    local sprinting = bit.band(buttons, IN_SPEED) ~= 0
        and bit.band(buttons, IN_WALK) == 0
        and not sprintBlocked(ply)
    local targetSpeed = sprinting and GAMEMODE.SurvivorRunSpeed
        or GAMEMODE.SurvivorWalkSpeed

    -- Preserve the previously implemented 15% injury penalty instead of
    -- baking it into the base speed, and respect the 3.25s winded limit.
    if ply:GetNWBool("PC2_BrokenBone", false) then
        targetSpeed = targetSpeed * 0.85
    end

    -- Don't undo engine crouch / deliberate +walk reduction. The source
    -- input velocity still applies crouch slowdown even with a higher cap,
    -- but explicitly avoid raising its special-mode cap just in case.
    local reducedMovement = ply:Crouching()
        or bit.band(buttons, IN_DUCK) ~= 0
        or bit.band(buttons, IN_WALK) ~= 0
    if reducedMovement then
        if mv:GetMaxSpeed() > 0 then
            targetSpeed = math.min(targetSpeed, mv:GetMaxSpeed())
        end
        if mv:GetMaxClientSpeed() > 0 then
            targetSpeed = math.min(targetSpeed, mv:GetMaxClientSpeed())
        end
    end

    -- Both are required; SetMaxClientSpeed alone may not match server
    -- prediction, and SetMaxSpeed alone may have no effect in SetupMove.
    mv:SetMaxSpeed(targetSpeed)
    mv:SetMaxClientSpeed(targetSpeed)
end)

if SERVER then
    local function startWinded(ply, time)
        ply.PC2Stamina = 0
        ply.PC2Winded = true
        ply.PC2WindedEnd = time + GAMEMODE.SurvivorWindedDuration
        ply.PC2SprintReleaseRequired = true

        -- Replicate before/with winded state, so clients can stop
        -- the breathing audio locally at the exact end timestamp.
        ply:SetNWFloat("PC2_Stamina", 0)
        ply:SetNWFloat("PC2_WindedEnd", ply.PC2WindedEnd)
        ply:SetNWBool("PC2_SprintReleaseRequired", true)
        ply:SetNWBool("PC2_Exhausted", true)
    end

    local function endWinded(ply, time)
        ply.PC2Winded = false
        ply.PC2WindedEnd = 0
        -- Keep stamina at zero through the entire winded period.
        -- First +4 regen tick occurs 0.2s AFTER winded ends.
        ply.PC2NextStaminaTick = time + GAMEMODE.SurvivorStaminaInterval
        ply:SetNWBool("PC2_Exhausted", false)
        ply:SetNWFloat("PC2_WindedEnd", 0)
    end

    hook.Add("Think", "PC2_ServerSurvivorStamina", function()
        local time = CurTime()
        local gm = GAMEMODE
        if not gm then return end

        for _, ply in ipairs(player.GetAll()) do
            if not gm:IsPC2Survivor(ply) or not ply:Alive()
                or ply:GetNWBool("PC2_Eliminated", false) then continue end

            -- Gamemode/player-class or pill respawns can reset these
            -- values independently of stamina. Keep them authoritative
            -- without repeatedly resetting the stamina itself.
            if ply:GetWalkSpeed() ~= gm.SurvivorWalkSpeed then
                ply:SetWalkSpeed(gm.SurvivorWalkSpeed)
            end
            if ply:GetRunSpeed() ~= gm.SurvivorRunSpeed then
                ply:SetRunSpeed(gm.SurvivorRunSpeed)
            end
            if ply:GetSlowWalkSpeed() ~= gm.SurvivorWalkSpeed then
                ply:SetSlowWalkSpeed(gm.SurvivorWalkSpeed)
            end

            if ply.PC2Stamina == nil then continue end

            if ply.PC2Winded then
                if time >= ply.PC2WindedEnd then
                    endWinded(ply, time)
                end
                -- No draining or regenerating for the full 3.25s.
                continue
            end

            local nextTick = ply.PC2NextStaminaTick or (time + gm.SurvivorStaminaInterval)
            -- Fixed 0.2-second increments match PC2's -2 / +4 figures.
            -- Cap catch-up after server stalls rather than doing unlimited work.
            local steps = 0
            while time >= nextTick and steps < 10 do
                steps = steps + 1
                nextTick = nextTick + gm.SurvivorStaminaInterval

                local stamina = math.Clamp(ply.PC2Stamina, 0, gm.SurvivorStaminaMax)
                local moving = ply:GetVelocity():Length2DSqr() > 100
                local sprinting = not ply.PC2SprintReleaseRequired
                    and stamina > 0 and ply.PC2RawSprintHeld == true
                    and moving and ply:OnGround() and not ply:Crouching()
                    and ply:GetMoveType() == MOVETYPE_WALK

                if sprinting then
                    stamina = math.max(0, stamina - gm.SurvivorStaminaDrainPerTick)
                else
                    stamina = math.min(gm.SurvivorStaminaMax,
                        stamina + gm.SurvivorStaminaRegenPerTick)
                end

                ply.PC2Stamina = stamina

                if stamina <= 0 and sprinting then
                    startWinded(ply, time)
                    break
                end

                -- The HUD reads the authoritative server value.
                if math.abs(ply:GetNWFloat("PC2_Stamina", -1) - stamina) > 0.001 then
                    ply:SetNWFloat("PC2_Stamina", stamina)
                end
            end

            if ply.PC2Winded then
                ply.PC2NextStaminaTick = time + gm.SurvivorStaminaInterval
            elseif steps >= 10 and time >= nextTick then
                ply.PC2NextStaminaTick = time + gm.SurvivorStaminaInterval
            else
                ply.PC2NextStaminaTick = nextTick
            end
        end
    end)
end

-- Inspect actual server/client player speeds and horizontal velocity. Use
-- "pc2_speed_debug" in the client console while holding W and Shift; once
-- fully accelerated on level ground, velocity should approach 8 or 23
-- Roblox studs/s (not Source units/s). Commands work on both realms.
concommand.Add("pc2_speed_debug", function(ply)
    local target = SERVER and ply or LocalPlayer()
    if not IsValid(target) then
        print("[PC2 Speed] Run this as a player (client console).")
        return
    end
    local actualStuds = target:GetVelocity():Length2D() / UNITS_PER_STUD
    local shiftHeld = SERVER and target.PC2RawSprintHeld == true
        or (CLIENT and (input.IsKeyDown(KEY_LSHIFT)
            or input.IsKeyDown(KEY_RSHIFT)))
    print(string.format(
        "[PC2 Speed] %s walk=%.2f/%.2f run=%.2f/%.2f Source units/s; "
        .. "velocity=%.2f Roblox studs/s; stamina=%.0f; "
        .. "exhausted=%s brokenBone=%s sprintHeld=%s",
        target:Nick(), target:GetWalkSpeed(), GM.SurvivorWalkSpeed,
        target:GetRunSpeed(), GM.SurvivorRunSpeed, actualStuds,
        target:GetNWFloat("PC2_Stamina", 100),
        tostring(target:GetNWBool("PC2_Exhausted", false)),
        tostring(target:GetNWBool("PC2_BrokenBone", false)),
        tostring(shiftHeld)))
end)
