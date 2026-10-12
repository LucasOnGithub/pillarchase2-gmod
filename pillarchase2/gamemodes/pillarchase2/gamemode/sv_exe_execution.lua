-- EXE's broken-bone M1 execution. All animation timing and ragdoll physics
-- are authoritative on the server. Ordinary M1 remains a 45-damage strike.
if not SERVER then return end

PC2_EXEExecution = PC2_EXEExecution or {}
local EXEC = PC2_EXEExecution
local GRAB_AT = 0.69
local DECAPITATE_AT = 2.04
local DEFAULT_DURATION = 2.50
local SCREAM = "Player/DeathScream.mp3"
local active = {}
local ZERO = Vector(0, 0, 0)

local function facing(a, b)
    local diff = b - a
    return Angle(0, diff:Angle().y, 0)
end

-- Models from the survivor, including all bodygroups/skins, NOT EXE's puppet.
local function makeRagdoll(victim, pos, ang, held)
    if not IsValid(victim) then return end
    local model = victim:GetModel()
    if not model or not util.IsValidRagdoll(model) then return end
    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then return end
    rag:SetModel(model)
    rag:SetPos(pos)
    rag:SetAngles(ang)
    rag:SetSkin(victim:GetSkin())
    for i = 0, victim:GetNumBodyGroups() - 1 do
        rag:SetBodygroup(i, victim:GetBodygroup(i))
    end
    rag:SetColor(victim:GetColor())
    rag:Spawn()
    if not IsValid(rag) then return end

    rag:SetCollisionGroup(held and COLLISION_GROUP_IN_VEHICLE
        or COLLISION_GROUP_DEBRIS)
    rag.PC2EXEVictim = victim
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            if held then
                phys:EnableCollisions(false)
                phys:EnableMotion(false)
                phys:EnableGravity(false)
                phys:SetVelocity(ZERO)
            else
                phys:EnableCollisions(true)
                phys:EnableMotion(true)
                phys:EnableGravity(true)
                phys:Wake()
            end
        end
    end
    return rag
end

local function headBone(rag)
    if not IsValid(rag) then return end
    return rag:LookupBone("ValveBiped.Bip01_Head1")
        or rag:LookupBone("Head")
        or rag:LookupBone("head")
end

local function hideHead(rag)
    if not IsValid(rag) then return end
    local root = headBone(rag)
    local hidden = {}
    if root then hidden[root] = true end

    -- Hide all of the head's descendants, including eye/jaw/hair bones.
    for i = 0, (rag:GetBoneCount() or 0) - 1 do
        local name = string.lower(rag:GetBoneName(i) or "")
        if name:find("head", 1, true) or name:find("jaw", 1, true)
            or name:find("face", 1, true) or name:find("eye", 1, true)
            or name:find("hair", 1, true) or name:find("teeth", 1, true) then
            hidden[i] = true
        end
        local parent = rag:GetBoneParent(i)
        while parent and parent >= 0 do
            if parent == root then hidden[i] = true break end
            parent = rag:GetBoneParent(parent)
        end
    end
    for bone in pairs(hidden) do
        rag:ManipulateBoneScale(bone, Vector(0, 0, 0))
    end
    rag:SetNWBool("PC2_EXEHeadless", true)
end

local function boneWorld(rag, name)
    if not IsValid(rag) then return end
    local bone = rag:LookupBone(name)
    if bone == nil then return end
    rag:SetupBones()
    local pos = rag:GetBonePosition(bone)
    if isvector(pos) and not pos:IsZero() then return pos end
end

local function handsPosition(pill, attacker)
    if not IsValid(pill) then return end
    local puppet = pill:GetPuppet()
    if not IsValid(puppet) then return end
    puppet:SetupBones()
    local left = boneWorld(puppet, "LeftHand")
    local right = boneWorld(puppet, "RightHand")
    if left and right then return (left + right) * 0.5 end
    if left or right then return left or right end
    return attacker:GetPos() + attacker:GetForward() * 45 + Vector(0, 0, 60)
end

-- Translate *every* physical bone so the victim's HEAD follows the
-- midpoint of EXE's animated hands after KillPC2 reaches 0.69 seconds.
local function holdHead(state)
    local rag = state.held
    if not IsValid(rag) then return end
    local where = handsPosition(state.pill, state.attacker)
    if not where then return end

    rag:SetupBones()
    local head = headBone(rag)
    local headPos = head and select(1, rag:GetBonePosition(head))
    if not isvector(headPos) or headPos:IsZero() then
        headPos = rag:GetPos() + Vector(0, 0, 63)
    end
    local shift = where - headPos
    if shift:LengthSqr() < 0.0001 then return end
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:SetPos(phys:GetPos() + shift, true)
            phys:SetVelocity(ZERO)
        end
    end
    rag:InvalidateBoneCache()
end

local function clear(state, keepBody)
    if state.cleaned then return end
    state.cleaned = true
    active[state] = nil

    if IsValid(state.held) then state.held:Remove() end
    if IsValid(state.victim) then
        state.victim.PC2EXEExecutionVictim = nil
        state.victim:SetNWBool("PC2_EXEBeingExecuted", false)
        state.victim:SetColor(state.originalColor)
        state.victim:SetRenderMode(state.originalRenderMode)
        state.victim:DrawShadow(true)
        if state.victim:Alive() then state.victim:Freeze(false) end
    end
    if IsValid(state.attacker) then
        state.attacker:Freeze(false)
    end
    if IsValid(state.pill) then
        state.pill.PC2EXEExecutionState = nil
        if not keepBody then
            state.pill.anim = nil
            state.pill.animFreeze = nil
            state.pill.animStart = nil
            state.pill.PC2_EXEBusyUntil = 0
        end
    end
end

local function bloodAt(pos, attacker)
    local data = EffectData()
    data:SetOrigin(pos)
    data:SetNormal(Vector(0, 0, 1))
    data:SetScale(3)
    data:SetMagnitude(5)
    data:SetRadius(12)
    util.Effect("BloodImpact", data, true, true)
    util.Decal("Blood", pos + Vector(0, 0, 12),
        pos - Vector(0, 0, 32), {attacker})
end

local function finishVictim(state)
    if state.killed then return end
    state.killed = true
    local victim, attacker, held = state.victim, state.attacker, state.held
    if not IsValid(victim) or not victim:Alive() then return end

    local gorePos = victim:WorldSpaceCenter() + Vector(0, 0, 23)
    if IsValid(held) then
        local h = headBone(held)
        if h then
            held:SetupBones()
            local at = held:GetBonePosition(h)
            if isvector(at) and not at:IsZero() then gorePos = at end
        end
    end

    local corpse = makeRagdoll(victim,
        IsValid(held) and held:GetPos() or victim:GetPos(),
        IsValid(held) and held:GetAngles() or victim:GetAngles(), false)
    if IsValid(corpse) then
        if IsValid(held) then
            for i = 0, math.min(corpse:GetPhysicsObjectCount(),
                held:GetPhysicsObjectCount()) - 1 do
                local from = held:GetPhysicsObjectNum(i)
                local to = corpse:GetPhysicsObjectNum(i)
                if IsValid(from) and IsValid(to) then
                    to:SetPos(from:GetPos(), true)
                    to:SetAngles(from:GetAngles())
                    to:Wake()
                end
            end
        end
        hideHead(corpse)
        SafeRemoveEntityDelayed(corpse, 30)
    end

    if IsValid(held) then held:Remove() end
    state.held = nil
    bloodAt(gorePos, attacker)

    -- Deliberately suppress the automatic full-headed death ragdoll.
    -- The custom headless body above replaces it.
    victim.PC2EXEExecutionNoDefaultRagdoll = true
    victim:Freeze(false)
    -- A regular Kill() is credited as suicide. Use EXE as the lethal
    -- attacker while exempting only this final blow from sequence immunity.
    state.finishing = true
    local damage = DamageInfo()
    damage:SetAttacker(IsValid(attacker) and attacker or victim)
    damage:SetInflictor(IsValid(state.pill) and state.pill
        or (IsValid(attacker) and attacker or victim))
    damage:SetDamage(math.max(victim:Health(), 1) + 1000)
    damage:SetDamageType(DMG_SLASH)
    victim:TakeDamageInfo(damage)
    if victim:Alive() then
        -- Rare cases with other plugins modifying lethal damage.
        victim:Kill()
    end
    timer.Simple(0, function()
        if not IsValid(victim) then return end
        local defaultRag = victim:GetRagdollEntity()
        if IsValid(defaultRag) and defaultRag ~= corpse then
            defaultRag:Remove()
        end
        victim.PC2EXEExecutionNoDefaultRagdoll = nil
    end)
end

function EXEC.Start(attacker, pill, victim)
    if not IsValid(attacker) or not attacker:Alive()
        or not IsValid(victim) or not victim:IsPlayer() or not victim:Alive()
        or not victim:GetNWBool("PC2_BrokenBone", false)
        or victim.PC2EXEExecutionVictim
        or not IsValid(pill) or pill.PC2EXEExecutionState then
        return false
    end

    local puppet = pill:GetPuppet()
    local seq = IsValid(puppet) and puppet:LookupSequence("KillPC2") or -1
    if not IsValid(puppet) or not seq or seq < 0 then return false end
    local duration = math.max(DEFAULT_DURATION, puppet:SequenceDuration(seq) or 0)
    local pos, ang = victim:GetPos(), facing(victim:GetPos(), attacker:GetPos())
    local held = makeRagdoll(victim, pos, ang, true)
    if not IsValid(held) then return false end

    local now = CurTime()
    local state = {
        attacker = attacker, pill = pill, victim = victim, held = held,
        started = now, endTime = now + duration,
        originalColor = victim:GetColor(),
        originalRenderMode = victim:GetRenderMode()
    }
    active[state] = true
    pill.PC2EXEExecutionState = state
    victim.PC2EXEExecutionVictim = state
    victim:SetNWBool("PC2_EXEBeingExecuted", true)
    attacker:Freeze(true)
    victim:SetEyeAngles(ang)
    victim:SetAngles(ang)
    victim:Freeze(true)
    -- Server SetNoDraw(true) also stops entity networking in GMod.
    -- Transparent color plus client PrePlayerDraw hides only the model
    -- while the survivor's entity, health and camera still replicate.
    victim:SetRenderMode(RENDERMODE_TRANSALPHA)
    local original = state.originalColor
    victim:SetColor(Color(original.r, original.g, original.b, 0))
    victim:DrawShadow(false)

    -- Remove the attack gesture immediately on the confirming M1 hit.
    -- This avoids AttackPC2 blending on top of KillPC2.
    if pill.PC2ActiveOverlay then
        local layer = pill.PC2ActiveOverlay.layer
        if layer and puppet:IsValidLayer(layer) then
            puppet:SetLayerWeight(layer, 0)
            puppet:RemoveLayer(layer)
        end
        pill.PC2ActiveOverlay = nil
    end
    if puppet.RemoveAllGestures then puppet:RemoveAllGestures() end
    pill:PillAnim("kill", true)
    puppet:ResetSequence(seq)
    puppet:SetCycle(0)
    puppet:SetPlaybackRate(1)

    pill.PC2_EXEBusyUntil = state.endTime
    pill.PC2_EXENextAttack = state.endTime
    pill:PillSound("jumpscare")
    return true
end

function EXEC.IsBusy(pill)
    return IsValid(pill) and pill.PC2EXEExecutionState ~= nil
end

-- Death is still server-authored and counts as an ordinary player kill,
-- but MUST NOT create the engine's default full-headed ragdoll.
hook.Add("DoPlayerDeath", "PC2_EXEExecutionSuppressDefaultRagdoll",
    function(victim, attacker)
        if not victim.PC2EXEExecutionNoDefaultRagdoll then return end
        victim:AddDeaths(1)
        if IsValid(attacker) and attacker:IsPlayer() then
            if attacker == victim then
                attacker:AddFrags(-1)
            else
                attacker:AddFrags(1)
            end
        end
        return true
    end)

-- Keep other damage from breaking the scripted sequence before 2.04.
hook.Add("EntityTakeDamage", "PC2_EXEExecutionVictimInvulnerable",
    function(target)
        if target:IsPlayer() and target.PC2EXEExecutionVictim
            and not target.PC2EXEExecutionVictim.finishing then
            return true
        end
    end)

hook.Add("Think", "PC2_EXEExecutionUpdate", function()
    local now = CurTime()
    for state in pairs(active) do
        local attacker, victim, pill = state.attacker, state.victim, state.pill
        if not IsValid(attacker) or not attacker:Alive()
            or not IsValid(victim) or (not victim:Alive() and not state.killed)
            or not IsValid(pill) or pill:GetPillUser() ~= attacker
            or attacker:GetNWString("PC2_MonsterForm", "") ~= "pc2_exe" then
            clear(state, false)
        else
            local elapsed = now - state.started
            if elapsed >= GRAB_AT and not state.grabbed then
                state.grabbed = true
                victim:EmitSound(SCREAM, 85, 100, 1, CHAN_VOICE)
            end
            if state.grabbed and not state.killed
                and now >= (state.nextRagUpdate or 0) then
                state.nextRagUpdate = now + 0.03
                holdHead(state)
            end
            if elapsed >= DECAPITATE_AT and not state.killed then
                finishVictim(state)
            end
            if now >= state.endTime then
                clear(state, true)
            end
        end
    end
end)

hook.Add("PlayerDisconnected", "PC2_EXEExecutionDisconnected", function(ply)
    for state in pairs(active) do
        if state.victim == ply or state.attacker == ply then
            clear(state, false)
        end
    end
end)

hook.Add("PlayerSpawn", "PC2_EXEExecutionRespawnCleanup", function(ply)
    for state in pairs(active) do
        if state.victim == ply or state.attacker == ply then clear(state, false) end
    end
    local wasBeingExecuted = ply.PC2EXEExecutionVictim ~= nil
        or ply:GetNWBool("PC2_EXEBeingExecuted", false)
    ply.PC2EXEExecutionNoDefaultRagdoll = nil
    ply.PC2EXEExecutionVictim = nil
    ply:SetNWBool("PC2_EXEBeingExecuted", false)
    if wasBeingExecuted then
        ply:SetRenderMode(RENDERMODE_NORMAL)
        ply:SetColor(color_white)
        ply:DrawShadow(true)
    end
end)
