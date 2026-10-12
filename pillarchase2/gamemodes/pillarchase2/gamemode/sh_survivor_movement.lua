-- Pillar Chase 2 - default survivor movement.
-- Roblox: 1 stud = 0.28 m (Creator Hub).
-- Source/Hammer's map-scale convention: 1 unit ~= 0.75 in = 0.01905 m.
-- Scale can be adjusted when recreating maps to match PC2's perceived speed.
local SOURCE_UNITS_PER_ROBLOX_STUD = 0.28 / 0.01905

GM.SurvivorWalkStuds = 8
GM.SurvivorRunStuds  = 23
GM.SurvivorWalkSpeed = GM.SurvivorWalkStuds * SOURCE_UNITS_PER_ROBLOX_STUD
GM.SurvivorRunSpeed  = GM.SurvivorRunStuds * SOURCE_UNITS_PER_ROBLOX_STUD

-- Currently everyone is a survivor. Replace this check when roles exist,
-- so future monster players can use their own speed and jump rules.
function GM:IsPC2Survivor(ply)
    return IsValid(ply) and ply:IsPlayer()
end

-- Keep base gamemode spawn behaviour (player class/model/loadout), then
-- override the movement speeds after the base class applies its defaults.
function GM:PlayerSpawn(ply, transition)
    self.BaseClass.PlayerSpawn(self, ply, transition)

    if not self:IsPC2Survivor(ply) then return end

    ply:SetWalkSpeed(self.SurvivorWalkSpeed)
    ply:SetRunSpeed(self.SurvivorRunSpeed)
    -- Alt (+walk) should not give survivors a third, slower movement speed.
    ply:SetSlowWalkSpeed(self.SurvivorWalkSpeed)
end

-- Strip the jump button from predicted input, not just jump velocity.
-- This runs on server and client (except clientside singleplayer prediction).
hook.Add("StartCommand", "PC2_DisableSurvivorJump", function(ply, cmd)
    if not GAMEMODE:IsPC2Survivor(ply) then return end
    cmd:RemoveKey(IN_JUMP)
end)
