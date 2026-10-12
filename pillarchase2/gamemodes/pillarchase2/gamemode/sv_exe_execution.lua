-- EXE's broken-bone M1 execution. All animation timing and ragdoll physics
-- are authoritative on the server. Ordinary M1 remains a 45-damage strike.
if not SERVER then return end

PC2_EXEExecution = PC2_EXEExecution or {}
local EXEC = PC2_EXEExecution
local GRAB_AT = 0.69
local DECAPITATE_AT = 2.04
local DEFAULT_DURATION = 2.50
local SCREAM = "Player/DeathScream.mp3"
-- The execution bypasses TakeDamageInfo until the finishing blow, so
-- sv_status_effects' PostEntityTakeDamage hook will not play M1 impact.
-- Emit the same hit clips here, directly from the victim at contact.
local HIT_SOUNDS = {
    "Monsters/Hit1.wav",
    "Monsters/Hit2.wav",
    "Monsters/Hit3.wav",
    "Monsters/Hit4.wav"
}
local active = {}

local function facing(a, b)
    local diff = b - a
    return Angle(0, diff:Angle().y, 0)
end

-- Models from the survivor, including all bodygroups/skins, NOT EXE's puppet.
local function makeRagdoll(victim, pos, ang, held)
    if not IsValid(victim) then return end
    local model = victim:GetModel()
    -- Certain workshop playermodels cannot spawn as physics ragdolls.
    -- Use the game's Kleiner default as a compatible fallback rather than
    -- aborting the whole execution and granting damage immunity.
    if not model or not util.IsValidRagdoll(model) then
        model = "models/player/kleiner.mdl"
    end
    if not util.IsValidRagdoll(model) then return end
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
    rag:Activate()

    -- A ragdoll must have MOVABLE physics bones. Freezing every PhysObj
    -- immediately after spawning leaves it in the model's reference/A pose.
    -- During the jumpscare it passes through everything, but all of its
    -- joints still simulate gravity and can hang naturally from the head.
    rag:SetCollisionGroup(held and COLLISION_GROUP_IN_VEHICLE
        or COLLISION_GROUP_DEBRIS)
    rag.PC2EXEVictim = victim
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            phys:EnableCollisions(not held)
            phys:EnableMotion(true)
            phys:EnableGravity(true)
            phys:Wake()
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

-- SetupBones() is not available on the server for every entity class.
-- GetBonePosition normally works from the engine's cached server pose;
-- GetBoneMatrix provides a fallback when the cached position is the origin.
local function boneWorld(ent, name)
    if not IsValid(ent) then return end
    local bone = ent:LookupBone(name)
    if bone == nil or bone < 0 then return end

    local pos = ent:GetBonePosition(bone)
    if isvector(pos) and not pos:IsZero()
        and pos:DistToSqr(ent:GetPos()) > 0.01 then
        return pos
    end

    local matrix = ent:GetBoneMatrix(bone)
    if matrix then
        pos = matrix:GetTranslation()
        if isvector(pos) and not pos:IsZero()
            and pos:DistToSqr(ent:GetPos()) > 0.01 then
            return pos
        end
    end
end

-- Drive only the physics object for the head; the torso/arms/legs are left
-- to ragdoll constraints and gravity rather than being teleported each tick.
local function headPhysics(rag)
    if not IsValid(rag) then return end
    local bone = headBone(rag)
    if bone ~= nil and bone >= 0 then
        local physBone = rag:TranslateBoneToPhysBone(bone)
        if physBone ~= nil and physBone >= 0 then
            local phys = rag:GetPhysicsObjectNum(physBone)
            if IsValid(phys) then return phys end
        end
    end

    -- Workshop ragdolls can lack a dedicated head PhysObj; use the closest
    -- available physics body as a fallback instead of stopping the kill.
    local estimatedHead = rag:GetPos() + Vector(0, 0, 65)
    local nearest, distance
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        if IsValid(phys) then
            local squared = phys:GetPos():DistToSqr(estimatedHead)
            if not distance or squared < distance then
                nearest, distance = phys, squared
            end
        end
    end
    return nearest
end

local function ragdollHeadPosition(rag)
    if not IsValid(rag) then return end
    local phys = headPhysics(rag)
    if IsValid(phys) then return phys:GetPos() end
    return rag:GetPos() + Vector(0, 0, 63)
end

local function handsPosition(pill, attacker)
    if not IsValid(attacker) then return end
    local fallback = attacker:GetPos() + attacker:GetForward() * 45
        + Vector(0, 0, 60)
    if not IsValid(pill) then return fallback end
    local puppet = pill:GetPuppet()
    if not IsValid(puppet) then return fallback end

    local left = boneWorld(puppet, "LeftHand")
    local right = boneWorld(puppet, "RightHand")
    if left and right then return (left + right) * 0.5 end
    return left or right or fallback
end

-- Keep the head fixed near the original survivor position before 0.69 s,
-- then smoothly follow EXE's animated hands. Every other physics bone
-- stays fully simulated so the body bends and dangles, not A-poses.
local function holdHead(state)
    local rag = state.held
    if not IsValid(rag) then return end

    local where = state.grabbed
        and handsPosition(state.pill, state.attacker)
        or state.initialHeadPos
    if not isvector(where) then return end

    local head = headPhysics(rag)
    if not IsValid(head) then return end
    head:Wake()
    head:ComputeShadowControl({
        pos = where,
        angle = head:GetAngles(), -- allow the head to rotate naturally
        secondstoarrive = 0.04,
        maxangular = 1000,
        maxangulardamp = 1000,
        maxspeed = 100000,
        maxspeeddamp = 10000,
        dampfactor = 0.8,
        teleportdistance = 150,
        delta = math.max(FrameTime(), 0.01)
    })
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
        if state.victim:Alive() then
            -- Undo the temporary one-HP protection if interrupted.
            if not state.killed then
                state.victim:SetHealth(math.max(1, state.originalHealth))
            end
            state.victim:Freeze(false)
        end
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
        gorePos = ragdollHeadPosition(held) or gorePos
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
    local hasSequence = IsValid(puppet) and seq ~= nil and seq >= 0
    local duration = DEFAULT_DURATION
    if hasSequence then
        duration = math.max(DEFAULT_DURATION, puppet:SequenceDuration(seq) or 0)
    end
    local pos, ang = victim:GetPos(), facing(victim:GetPos(), attacker:GetPos())
    local held = makeRagdoll(victim, pos, ang, true)
    -- Missing ragdoll physics or a delayed puppet must NEVER turn a
    -- confirmed M1 hit into zero damage and an impossible kill. The timed
    -- sequence still executes, and the ordinary survivor is visible when
    -- there is no substitute ragdoll.

    local now = CurTime()
    local state = {
        attacker = attacker, pill = pill, victim = victim, held = held,
        started = now, endTime = now + duration,
        -- Holds the simulated head near the victim until EXE reaches the
        -- grab moment; otherwise a noncolliding ragdoll falls through floors.
        initialHeadPos = IsValid(held) and ragdollHeadPosition(held) or nil,
        originalHealth = victim:Health(),
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
    -- GMod treats zero health as death; one HP is a reliable living state.
    -- Damage is also blocked during this animation, until the final frame.
    victim:SetHealth(1)
    -- Do not turn the victim invisible unless a visible stand-in exists.
    -- SetNoDraw would also stop networking the player, so use alpha.
    if IsValid(held) then
        victim:SetRenderMode(RENDERMODE_TRANSALPHA)
        local original = state.originalColor
        victim:SetColor(Color(original.r, original.g, original.b, 0))
        victim:DrawShadow(false)
    end

    -- Remove the attack gesture immediately on the confirming M1 hit.
    -- This avoids AttackPC2 blending on top of KillPC2.
    if pill.PC2ActiveOverlay then
        local layer = pill.PC2ActiveOverlay.layer
        if IsValid(puppet) and layer and puppet:IsValidLayer(layer) then
            puppet:SetLayerWeight(layer, 0)
            puppet:RemoveLayer(layer)
        end
        pill.PC2ActiveOverlay = nil
    end
    if IsValid(puppet) and puppet.RemoveAllGestures then
        puppet:RemoveAllGestures()
    end
    if hasSequence then
        pill:PillAnim("kill", true)
        puppet:ResetSequence(seq)
        puppet:SetCycle(0)
        puppet:SetPlaybackRate(1)
    else
        -- The timed finisher still kills at 2.04 if KillPC2 could not
        -- be resolved because the puppet is not initialized yet.
        ErrorNoHalt("[PC2 EXE] KillPC2 not ready; using timed execution fallback\n")
    end

    pill.PC2_EXEBusyUntil = state.endTime
    pill.PC2_EXENextAttack = state.endTime
    pill:PillSound("jumpscare")

    -- Both sounds play on the victim at the precise moment M1 connects.
    -- Separate channels avoid the scream replacing the impact or vice versa.
    victim:EmitSound(HIT_SOUNDS[math.random(#HIT_SOUNDS)],
        75, 100, 1, CHAN_BODY)
    victim:EmitSound(SCREAM, 85, 100, 1, CHAN_VOICE)
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
            end
            -- Update once per server tick: pin only the head, letting
            -- ragdoll constraints and gravity solve the rest of the body.
            if not state.killed then
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
