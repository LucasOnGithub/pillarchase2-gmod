-- Pillar Chase 2 - survivor movement and stamina.
-- Roblox speed: 8 studs/s walk, 23 studs/s sprint.
-- Map scale: 1 stud = 0.28m; 1 Source unit ~= 0.01905m.
local UNITS_PER_STUD = 0.28 / 0.01905

GM.SurvivorWalkStuds = 8
GM.SurvivorRunStuds = 23
GM.SurvivorWalkSpeed = GM.SurvivorWalkStuds * UNITS_PER_STUD
GM.SurvivorRunSpeed = GM.SurvivorRunStuds * UNITS_PER_STUD

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

hook.Add("SetupMove", "PC2_SurvivorExhaustionSpeed", function(ply, mv, cmd)
    if not GAMEMODE or not GAMEMODE:IsPC2Survivor(ply) then return end
    if not sprintBlocked(ply) then return end

    -- Prevent any client input from bypassing forced-walk speed.
    local speed = GAMEMODE.SurvivorWalkSpeed
    if mv:GetMaxSpeed() > speed then mv:SetMaxSpeed(speed) end
    if mv:GetMaxClientSpeed() > speed then mv:SetMaxClientSpeed(speed) end
end)

-- Apply the 15% broken-bone penalty to BOTH client prediction and
-- server movement; never permanently overwrite the player's base speeds.
hook.Add("SetupMove", "PC2_BrokenBoneMovement", function(ply, mv)
    if not GAMEMODE or not GAMEMODE:IsPC2Survivor(ply) then return end
    if not ply:Alive() or not ply:GetNWBool("PC2_BrokenBone", false) then return end

    local sprinting = bit.band(mv:GetButtons(), IN_SPEED) ~= 0
    local normalSpeed = sprinting and GAMEMODE.SurvivorRunSpeed
        or GAMEMODE.SurvivorWalkSpeed
    local limit = normalSpeed * 0.85

    if mv:GetMaxSpeed() > limit then mv:SetMaxSpeed(limit) end
    if mv:GetMaxClientSpeed() > limit then mv:SetMaxClientSpeed(limit) end
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
            if not gm:IsPC2Survivor(ply) or not ply:Alive() then continue end
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
