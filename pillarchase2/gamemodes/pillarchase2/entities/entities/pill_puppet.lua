AddCSLuaFile()
ENT.Type = "ai"
ENT.Base = "base_entity"

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "PillForm")
    self:NetworkVar("Entity", 1, "PillCostume")
    self:NetworkVar("Entity", 2, "PillUser")
end

function ENT:Initialize()
    self:SetRenderMode(RENDERMODE_TRANSALPHA)

    if SERVER then
        self._queuedEvents = { named = {} }
    end

    local formTable = pk_pills.getPillTable(self:GetPillForm())
    
    if formTable and formTable.initialize then
        formTable.initialize(self:GetPillUser(), self:GetPillCostume(), self)
    end
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:DrawTranslucent()
    self:Draw()
end

function ENT:QueueEvent(event, id)
    if CLIENT then return end

    if id then
        self._queuedEvents.named[id] = event
    else
        table.insert(self._queuedEvents, event)
    end
end

if CLIENT then return end

DEFINE_BASECLASS('base_ai')

function ENT:RunAI(strExpr)
    local events = self._queuedEvents
    local eventCount = #self._queuedEvents

    if eventCount > 0 then
        for i = eventCount, 1, -1 do
            local event = table.remove(events, i)
            event(self)
        end
    end

    local called_named_event = false

    for _, event in pairs(events.named) do
        event(self)
        called_named_event = true
    end

    if called_named_event then
        events.named = {}
    end

    BaseClass.RunAI(self, strExpr)
end