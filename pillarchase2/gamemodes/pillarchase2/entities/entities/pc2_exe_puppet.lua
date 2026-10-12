AddCSLuaFile()

-- Special EXE puppet: the stock pill_puppet is ENT.Type = "ai", which
-- does not support AddGestureSequence as a BaseAnimatingOverlay.
-- This anim-type version supports networking EXE's upper-body gestures
-- without modifying the other pills' puppet or animation systems.
ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.AutomaticFrameAdvance = true
ENT.RenderGroup = RENDERGROUP_OPAQUE
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "PillForm")
    self:NetworkVar("Entity", 1, "PillCostume")
    self:NetworkVar("Entity", 2, "PillUser")
end

function ENT:Initialize()
    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    local form = pk_pills and pk_pills.getPillTable(self:GetPillForm())
    if form and form.initialize then
        form.initialize(self:GetPillUser(), self:GetPillCostume(), self)
    end
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    self:Draw()
end

-- Keep animation playback advancing in the engine and on clients.
function ENT:Think()
    if SERVER then
        self:NextThink(CurTime())
        return true
    end
end
