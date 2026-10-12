AddCSLuaFile()

-- Player-controlled EXE Thorny Grave trap.
-- Ported from npc_drg_pc2_exetrap: 60-unit capture radius,
-- 2 damage per second, 15 hits/uses to remove, 4-second EXE speed bonus.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "EXE - Thorny Grave"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH

local MODEL = "models/noodles/pillarchase2/exe/exetrap.mdl"
local GRAB_RADIUS = 60
local DAMAGE_INTERVAL = 1
local DAMAGE = 2
local MAX_HITS = 15

function ENT:Initialize()
    self:SetModel(MODEL)
    if CLIENT then return end

    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)
    self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    self.HitsLeft = MAX_HITS
    self.NextDamage = CurTime() + DAMAGE_INTERVAL
    self.TrapSequence = "idle"
    self:ResetSequence("idle")
end

function ENT:Draw()
    self:DrawModel()
end

if CLIENT then return end

local function eligible(ent, owner)
    if not IsValid(ent) or ent == owner then return false end
    if ent:IsPlayer() then
        return ent:Alive() and not ent:GetNWBool("PC2_IsMonster", false)
    end
    return (ent:IsNPC() or ent:IsNextBot()) and ent:Health() > 0
end

function ENT:ReleaseVictim()
    local victim = self.CaughtVictim
    self.CaughtVictim = nil
    self:SetNWEntity("PC2_TrapVictim", NULL)
    if not IsValid(victim) then return end

    if victim:GetNWEntity("PC2_TrapHolding") == self then
        victim:SetNWEntity("PC2_TrapHolding", NULL)
        if victim:IsPlayer() then victim:Freeze(false) end
    end
end

function ENT:HitTrap()
    if self.Removing then return end
    self.HitsLeft = (self.HitsLeft or MAX_HITS) - 1
    self:EmitSound("ambient/energy/zap1.wav", 75, 100)
    self:EmitSound("physics/flesh/flesh_squishy_impact_hard1.wav", 75, 100)
    if self.HitsLeft <= 0 then
        self.Removing = true
        self:ReleaseVictim()
        self:Remove()
    end
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    if activator == self:GetNWEntity("PC2_EXEOwner") then return end
    self:HitTrap()
end

function ENT:OnTakeDamage(damage)
    if damage:GetDamage() > 0 then self:HitTrap() end
end

function ENT:Capture(victim)
    if not eligible(victim, self:GetNWEntity("PC2_EXEOwner")) then return end
    if IsValid(victim:GetNWEntity("PC2_TrapHolding")) then return end

    self.CaughtVictim = victim
    self:SetNWEntity("PC2_TrapVictim", victim)
    victim:SetNWEntity("PC2_TrapHolding", self)
    if victim:IsPlayer() then victim:Freeze(true) end
    -- Original trap holds its victim at the center while grabbing.
    victim:SetPos(self:GetPos() + Vector(0, 0, 2))
    victim:SetAngles(self:GetAngles())

    self.TrapSequence = "grab"
    self:ResetSequence("grab")
    self:EmitSound("noodles/pillarchase2/exe/exetrap.wav", 90, 100)

    -- The Nextbot accelerates for four seconds when its trap catches someone.
    local pill = self:GetNWEntity("PC2_EXEPill")
    if IsValid(pill) then
        pill.PC2_EXESpeedBoostUntil = CurTime() + 4
        pill:SetNWFloat("PC2_EXESpeedBoostUntil", pill.PC2_EXESpeedBoostUntil)
    end
end

function ENT:Think()
    local owner = self:GetNWEntity("PC2_EXEOwner")
    local pill = self:GetNWEntity("PC2_EXEPill")
    if not IsValid(owner) or not owner:Alive() or not IsValid(pill) then
        self:Remove()
        return
    end

    if not IsValid(self.CaughtVictim) or not eligible(self.CaughtVictim, owner) then
        if self.CaughtVictim ~= nil then self:ReleaseVictim() end

        if self.TrapSequence ~= "idle" then
            self.TrapSequence = "idle"
            self:ResetSequence("idle")
        end
        local center = self:GetPos() + Vector(0, 0, 40)
        for _, candidate in ipairs(ents.FindInSphere(center, GRAB_RADIUS)) do
            if eligible(candidate, owner)
                and not IsValid(candidate:GetNWEntity("PC2_TrapHolding")) then
                self:Capture(candidate)
                break
            end
        end
    end

    local victim = self.CaughtVictim
    if IsValid(victim) then
        -- Immobilize at the trap, rather than teleport every frame.
        -- Freeze the victim where captured; no teleporting them each tick.
        -- If a non-player victim escapes, release it normally.
        if not victim:IsPlayer()
            and victim:GetPos():DistToSqr(self:GetPos()) > 48 * 48 then
            self:ReleaseVictim()
        elseif CurTime() >= self.NextDamage then
            self.NextDamage = CurTime() + DAMAGE_INTERVAL
            local dmg = DamageInfo()
            dmg:SetAttacker(owner)
            dmg:SetInflictor(self)
            dmg:SetDamage(DAMAGE)
            dmg:SetDamageType(DMG_GENERIC)
            victim:TakeDamageInfo(dmg)
        end
    end

    self:NextThink(CurTime() + .1)
    return true
end

function ENT:OnRemove()
    self:ReleaseVictim()

    -- Give the owning EXE a trap slot back as soon as this is destroyed.
    local pill = self:GetNWEntity("PC2_EXEPill")
    if not IsValid(pill) then return end
    local traps = pill.PC2_EXETraps
    if not traps then return end
    for i = #traps, 1, -1 do
        if traps[i] == self or not IsValid(traps[i]) then
            table.remove(traps, i)
        end
    end
    pill:SetNWInt("PC2_EXE_TrapCount", #traps)
    local owner = pill:GetPillUser()
    if IsValid(owner) then owner:SetNWInt("PC2_EXE_TrapCount", #traps) end
end
