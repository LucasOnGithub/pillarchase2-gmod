-- Shared gamemode metadata.
GM.Name = "Pillar Chase 2"
GM.Author = "Lucas & The_BladeNinja"
GM.Website = "https://github.com/LucasOnGithub/pillarchase2-gmod"

-- Default survivor movement until the lobby/role system is implemented.
include("sh_survivor_movement.lua")

-- Pillar Chase 2 has no fall damage, for survivors and monsters alike.
-- Return zero for the standard Source/GMod landing damage calculation.
function GM:GetFallDamage(ply, speed)
    return 0
end

-- Also stop damage explicitly marked DMG_FALL by maps or other addons.
-- Other damage types (EXE's melee, bites and traps) are unaffected.
if SERVER then
    hook.Add("EntityTakeDamage", "PC2_NoFallDamage", function(target, dmg)
        if IsValid(target) and target:IsPlayer()
            and dmg:IsDamageType(DMG_FALL) then
            return true
        end
    end)

    -- Survivors and monsters pass through other players instead of
    -- physically blocking them. Disable Source's player-avoidance steering
    -- as well, otherwise movement may still push around nearby players.
    local function noPlayerCollision(ply)
        if not IsValid(ply) or not ply:IsPlayer() then return end
        if ply:GetCollisionGroup() ~= COLLISION_GROUP_PASSABLE_DOOR then
            ply:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
        end
        ply:SetAvoidPlayers(false)
    end

    -- Apply immediately on spawn, then enforce it if an addon/pill changes
    -- the player's collision group during gameplay.
    hook.Add("PlayerSpawn", "PC2_NoPlayerCollisionSpawn", noPlayerCollision)
    hook.Add("PlayerTick", "PC2_NoPlayerCollision", noPlayerCollision)
end
