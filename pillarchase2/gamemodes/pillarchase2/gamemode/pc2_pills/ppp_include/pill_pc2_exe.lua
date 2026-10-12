-- PC2 EXE playable pill, ported from npc_drg_pc2_exe (DrGBase Nextbot).
-- Standalone pk_pills form: does NOT require DrGBase.
AddCSLuaFile()

local ID = "pc2_exe"
local MODEL = "models/noodles/pillarchase2/exe.mdl"
local TRAP = "pc2_exe_trap"

-- Same Roblox-stud conversion used by sh_survivor_movement.lua:
-- 1 Roblox stud = 0.28 m; 1 Source unit = 0.01905 m.
local SOURCE_UNITS_PER_STUD = 0.28 / 0.01905
local WALK_SPEED = 5 * SOURCE_UNITS_PER_STUD
local RUN_SPEED = 19 * SOURCE_UNITS_PER_STUD
local CHARGE_SPEED = 28.5 * SOURCE_UNITS_PER_STUD
local CHARGE_DURATION = 2.30
local CHARGE_RECOVERY = 0.60

-- EXE-specific adaptation of the supplied bone camera handler.
-- The pill base already calls formTable.calcView from its momo_calcview
-- hook. Avoid overriding pill_ent_costume:Think or replacing CalcView for
-- any other pill, as the old Rachel hook does.
local function boneAnchor(puppet, boneInfo, fallback)
    if not IsValid(puppet) or not boneInfo then return fallback end

    local boneID = puppet:LookupBone(boneInfo[1])
    if boneID == nil then return fallback end

    puppet:SetupBones()
    local bonePos = puppet:GetBonePosition(boneID)
    if not isvector(bonePos) then
        local matrix = puppet:GetBoneMatrix(boneID)
        if matrix then bonePos = matrix:GetTranslation() end
    end

    if not isvector(bonePos) or bonePos:IsZero() then
        return fallback
    end

    return bonePos
end

local function offsetFromBone(puppet, boneInfo, viewAngles, fallback)
    local anchor = boneAnchor(puppet, boneInfo, fallback)
    -- Camera position follows the animated bone, while the horizontal
    -- offsets follow the player's view direction, not head roll/pitch.
    local yaw = Angle(0, viewAngles.y, 0)
    return anchor + yaw:Forward() * boneInfo[2]
        + yaw:Right() * boneInfo[3]
        + Vector(0, 0, boneInfo[4])
end

-- The source Nextbot reads these settings from a DIFFERENT addon's ConVars,
-- which are not included in pillarchase_nextbot.zip. The original ConVar
-- names take precedence if present; these fallback defaults are editable.
local FALLBACK = {
    melee = 35, bite = 70, tooSlowCooldown = 18, thornyCooldown = 20
}
local function getSetting(key, sourceName)
    local source = GetConVar(sourceName)
    if source then return source:GetFloat() end
    local cv = GetConVar("pc2_exe_" .. key)
    return cv and cv:GetFloat() or FALLBACK[key]
end

if SERVER then
    CreateConVar("pc2_exe_melee", tostring(FALLBACK.melee), FCVAR_ARCHIVE,
        "EXE melee damage when _EXEDamage is absent.")
    CreateConVar("pc2_exe_bite", tostring(FALLBACK.bite), FCVAR_ARCHIVE,
        "EXE Too Slow grab damage when _TooSlowDamage is absent.")
    CreateConVar("pc2_exe_tooSlowCooldown", tostring(FALLBACK.tooSlowCooldown), FCVAR_ARCHIVE,
        "EXE Too Slow cooldown when _TooSlowCooldown is absent.")
    CreateConVar("pc2_exe_thornyCooldown", tostring(FALLBACK.thornyCooldown), FCVAR_ARCHIVE,
        "EXE Thorny Grave cooldown when _ThornyGraveCooldown is absent.")
    -- Ability buttons and RMB are now handled server-side with
    -- PlayerButtonDown / KeyPress, like the Bendy Redrawn pill.
end

local function isEXE(ent)
    return IsValid(ent) and ent.GetPillForm and ent:GetPillForm() == ID
end

local function enemy(ply, other)
    if not IsValid(other) or other == ply then return false end
    if other:IsPlayer() then
        return other:Alive() and not other:GetNWBool("PC2_IsMonster", false)
    end
    return (other:IsNPC() or other:IsNextBot()) and other:Health() > 0
end

local function getVictims(ply, ent, radius, minimumDot)
    local victims = {}
    local origin = ply:GetPos() + Vector(0, 0, 44)
    local forward = ply:EyeAngles():Forward()
    forward.z = 0
    forward:Normalize()
    for _, other in ipairs(ents.FindInSphere(origin, radius)) do
        if enemy(ply, other) then
            local destination = other:WorldSpaceCenter()
            local delta = destination - origin
            delta.z = 0
            local distance = delta:Length()
            if distance > 1 then delta:Normalize() end
            if distance <= 1 or forward:Dot(delta) >= minimumDot then
                local tr = util.TraceLine({
                    start = origin, endpos = destination,
                    filter = {ply, ent, ent:GetPuppet()},
                    mask = MASK_SHOT
                })
                if not tr.Hit or tr.Entity == other then
                    victims[#victims + 1] = other
                end
            end
        end
    end
    return victims
end

local function damage(ply, ent, target, amount)
    if not IsValid(target) or not enemy(ply, target) then return false end
    local dmg = DamageInfo()
    dmg:SetAttacker(ply)
    dmg:SetInflictor(ent)
    dmg:SetDamage(amount)
    dmg:SetDamageType(DMG_SLASH)
    target:TakeDamageInfo(dmg)
    return true
end

local function animate(ent, name)
    if not IsValid(ent) then return false end
    local puppet = ent:GetPuppet()
    local sequence = ent.formTable and ent.formTable.anims
        and ent.formTable.anims.default[name]
    if not IsValid(puppet) or not sequence or puppet:LookupSequence(sequence) < 0 then
        return false
    end
    ent:PillAnim(name, true)
    return true
end

local function playKill(ply, ent, target, amount)
    if not IsValid(target) or not isEXE(ent) or not ply:Alive() then return end
    if target:IsPlayer() and not target:Alive() then return end

    if not animate(ent, "kill") then animate(ent, "bite") end
    ent:PillSound("jumpscare")
    -- The source's base-class cinematic is not present in the upload.
    -- This locks the victim for the animation and applies the lethal hit.
    if target:IsPlayer() then
        target:Freeze(true)
    end
    timer.Simple(1.2, function()
        if IsValid(target) then
            if enemy(ply, target) then damage(ply, ent, target, amount) end
            if target:IsPlayer() then target:Freeze(false) end
        end
    end)
end

local function melee(ply, ent)
    if not isEXE(ent) or not ply:Alive() then return end
    local now = CurTime()
    if now < (ent.PC2_EXENextAttack or 0)
        or now < (ent.PC2_EXETooSlowUntil or 0)
        or now < (ent.PC2_EXEBusyUntil or 0) then return end

    ent.PC2_EXENextAttack = now + 1.6
    ent.PC2_EXEBusyUntil = now + 0.55 -- original Nextbot melee delay
    -- AttackPC2 uses a private upper-body bone weightlist in EXE.mdl.
    -- Keep the lower-body animation (idle/walk/run) visible beneath it.
    -- Native 60 FPS / 74-frame timing; no speed multiplier or early autokill.
    ent:PillOverlaySequence("attack")
    ent:PillSound("attack")

    -- Original Nextbot damages via the model's "Melee" animation event.
    -- Pill puppets do not dispatch that DrGBase event; use a timed hit.
    timer.Simple(.45, function()
        if not isEXE(ent) or not IsValid(ply) or not ply:Alive() then return end
        local amount = getSetting("melee", "_EXEDamage")
        local victims = getVictims(ply, ent, 105, 0.30)
        for _, victim in ipairs(victims) do
            if victim:Health() <= amount then
                playKill(ply, ent, victim, amount)
                break
            else
                damage(ply, ent, victim, amount)
            end
        end
    end)
end

local function tooSlow(ply, ent)
    if not isEXE(ent) or not ply:Alive() then return end
    local now = CurTime()
    if now < (ent.PC2_EXENextTooSlow or 0)
        or now < (ent.PC2_EXEBusyUntil or 0)
        or now < (ent.PC2_EXETooSlowUntil or 0) then return end

    -- The charge animation and high-speed movement last exactly 2.30s.
    -- Cooldown starts from the end of that window, not from key press.
    ent.PC2_EXETooSlowUntil = now + CHARGE_DURATION
    ent.PC2_EXENextTooSlow = ent.PC2_EXETooSlowUntil
        + getSetting("tooSlowCooldown", "_TooSlowCooldown")
    ent.PC2_EXETooSlowGrabbed = false
    ent.PC2_EXERecoveryUntil = 0
    ent:SetNWFloat("PC2_EXE_RecoveryUntil", 0)
    ent:SetNWFloat("PC2_EXE_TooSlowUntil", ent.PC2_EXETooSlowUntil)
    ent:SetNWFloat("PC2_EXE_TooSlowReady", ent.PC2_EXENextTooSlow)
    ent:PillSound("tooslow")
end

local function thornyGrave(ply, ent)
    if not isEXE(ent) or not ply:Alive() then return end
    local now = CurTime()
    if now < (ent.PC2_EXENextThorny or 0)
        or now < (ent.PC2_EXEBusyUntil or 0)
        or now < (ent.PC2_EXETooSlowUntil or 0) then return end
    ent.PC2_EXENextThorny = now + getSetting("thornyCooldown", "_ThornyGraveCooldown")
    -- Source model's trap sequence: 122 frames at 60 FPS (~2.03 sec),
    -- with PlantSeed at cycle .537 (~1.09 sec).
    ent.PC2_EXEBusyUntil = now + 122 / 60
    ent:SetNWFloat("PC2_EXE_ThornyReady", ent.PC2_EXENextThorny)
    ent:SetNWFloat("PC2_EXE_TrapCastingUntil", ent.PC2_EXEBusyUntil)
    ent:PillSound("deploy")
    animate(ent, "trap")

    -- The Nextbot creates its trap at PlantSeed (left hand animation event).
    timer.Simple((122 / 60) * 0.5371900797, function()
        if not isEXE(ent) or not ply:Alive() then return end

        local puppet = ent:GetPuppet()
        local spawnPos = ply:GetPos() + ply:GetForward() * 25 + Vector(0, 0, 15)
        if IsValid(puppet) then
            local bone = puppet:LookupBone("LeftHand")
            if bone then
                local position = puppet:GetBonePosition(bone)
                if position then spawnPos = position end
            end
        end

        local ground = util.TraceLine({
            start = spawnPos + Vector(0, 0, 30),
            endpos = spawnPos - Vector(0, 0, 150),
            filter = {ply, ent, puppet},
            mask = MASK_SOLID
        })
        if ground.Hit then spawnPos = ground.HitPos + Vector(0, 0, 2) end

        local trap = ents.Create(TRAP)
        if not IsValid(trap) then return end
        trap:SetPos(spawnPos)
        trap:SetAngles(Angle(0, ply:EyeAngles().y, 0))
        trap:SetOwner(ply)
        trap:SetNWEntity("PC2_EXEOwner", ply)
        trap:SetNWEntity("PC2_EXEPill", ent)
        trap:Spawn()
        ent:DeleteOnRemove(trap)
    end)
end

-- The original Too Slow scans victims within ~70 units for its grab.
local function tickTooSlow(ply, ent, now)
    if now >= (ent.PC2_EXETooSlowUntil or 0)
        or ent.PC2_EXETooSlowGrabbed then return end
    for _, victim in ipairs(getVictims(ply, ent, 70, -0.25)) do
        ent.PC2_EXETooSlowGrabbed = true
        ent.PC2_EXETooSlowUntil = 0
        -- Being interrupted by a successful grab also ends the charge
        -- and applies the same 0.60-second no-sprint recovery.
        ent.PC2_EXERecoveryUntil = now + CHARGE_RECOVERY
        ent:SetNWFloat("PC2_EXE_RecoveryUntil", ent.PC2_EXERecoveryUntil)
        -- Bite clip: 210 frames @ 60 FPS; its named Bite and BiteEnd
        -- events fire at cycles ~0.531 and ~0.612 respectively.
        ent.PC2_EXEBusyUntil = now + 210 / 60 * 0.6125
        ent:SetNWFloat("PC2_EXE_TooSlowUntil", 0)
        ent:PillSound("grab")
        animate(ent, "bite")
        if victim:IsPlayer() then victim:Freeze(true) end
        timer.Simple(210 / 60 * 0.53110045, function()
            if not isEXE(ent) or not IsValid(victim) then return end
            damage(ply, ent, victim, getSetting("bite", "_TooSlowDamage"))
        end)
        timer.Simple(210 / 60 * 0.61244017, function()
            if IsValid(victim) and victim:IsPlayer() then
                victim:Freeze(false)
            end
        end)
        break
    end
end

pk_pills.register(ID, {
    printName = "EXE",
    side = "pc2_monster",
    type = "ply",
    model = MODEL,
    -- Gesture layers require an anim-type puppet (BaseAnimatingOverlay).
    puppetClass = "pc2_exe_puppet",
    health = 1000,
    hull = Vector(30, 30, 90),
    duckBy = 0,
    jumpPower = 0,
    noFallDamage = true,
    hideWeapons = true,
    movePoseMode = false,
    -- Scoped alternative to the supplied rachel_initialize camera hook.
    -- Our existing momo_calcview -> formTable.calcView hook is enabled,
    -- so we do not need to replace the pill costume's Think function.
    boneCameraEnabled = true,
    firstPersonBody = true,
    firstPersonHideHead = true,
    rotateWhenIdle = true,
    -- Bone entry format from the supplied code:
    -- { bone name, forward, right, vertical } (Source units).
    -- EXE has UpperTorso rather than a bone literally named "Spine".
    ThirdPersonBone = { "UpperTorso", 0, 23, 23 },
    FirstPersonBone = { "Head", 43, 0, 2 },
    -- Original possession camera remains 115 Source units behind EXE.
    -- RMB toggles first-person and the shoulder/spine third-person view.
    camera = {
        offset = Vector(0, 10, 100),
        dist = 115
    },
    moveSpeed = {
        walk = WALK_SPEED, -- 5 Roblox studs/s
        run = RUN_SPEED   -- 19 Roblox studs/s
    },
    anims = {
        default = {
            idle = "IdlePC2",
            walk = "walk",
            run = "run",
            -- EXE's exported animation clips have in-place motion.
            -- Avoid velocity/ground-speed scaling multiplying the puppet's
            -- global playback rate (and therefore its gesture rate).
            walk_rate = 1,
            run_rate = 1,
            attack = "AttackPC2",
            kill = "KillPC2",
            bite = "bite",
            trap = "trap",
            charge = "charge",
            charge_rate = 1.2 -- requested Too Slow charge speed (1.2x)
        }
    },
    -- Charge is played as EXE's base locomotion clip for the full boost.
    loopAnims = { charge = true },
    overrideAnim = function(ply, ent)
        if ent.PC2_EXETooSlowUntil
            and CurTime() < ent.PC2_EXETooSlowUntil
            and not ent.PC2_EXETooSlowGrabbed then
            return "charge"
        end
    end,
    -- Walking, running and charging use the EXE model's 5004 animation
    -- events, not generic PlayerFootstep timing or the old step sample.
    muteSteps = true,
    sounds = {
        attack = "noodles/pillarchase2/exe/exeattack.wav",
        sniff = "noodles/pillarchase2/exe/exesniff.wav",
        grab = "noodles/pillarchase2/exe/exegrab.wav",
        jumpscare = "noodles/pillarchase2/exe/exejumpscare.wav",
        deploy = "noodles/pillarchase2/exe/deploysfx.wav",
        trap = "noodles/pillarchase2/exe/exetrap.wav",
        tooslow = "noodles/pillarchase2/exe/laughtooslow.wav"
    },
    initialize = function(ply, ent, puppet)
        if SERVER and IsValid(ply) and isEXE(ent) then
            ply:SetNWBool("PC2_IsMonster", true)
            ent.PC2_EXENextAttack = 0
            ent.PC2_EXENextTooSlow = 0
            ent.PC2_EXENextThorny = 0
            ent.PC2_EXESniffStart = 0
            ent.PC2_EXESpeedBoostUntil = 0
            ent.PC2_EXETooSlowUntil = 0
            ent.PC2_EXERecoveryUntil = 0
            ent:SetNWFloat("PC2_EXE_RecoveryUntil", 0)
            ent:SetNWFloat("PC2_EXE_TooSlowReady", 0)
            ent:SetNWFloat("PC2_EXE_ThornyReady", 0)
            ent:SetNWFloat("PC2_EXE_TrapCastingUntil", 0)
            ent:SetNWFloat("PC2_EXE_SniffUntil", 0)
            ent:SetNWBool("PC2_EXE_FirstPerson", true)
        end
    end,
    -- LMB is EXE's regular melee attack, not an ability hotkey.
    -- Do NOT expose attack2 or reload: the pill base automatically
    -- binds those to RMB and R. Too Slow and Thorny Grave are invoked
    -- exclusively through the number-key ability network handler.
    attack = {
        mode = "trigger",
        func = melee
    },
    -- An EXE-specific camera callback is supported by a tiny addition
    -- to ppp_includes/nocompat.lua. The other pills remain unchanged.
    calcView = function(ply, ent, pos, angles, fov)
        if not isEXE(ent) or ply:GetViewEntity() ~= ply then return end
        if not ent.formTable or not ent.formTable.boneCameraEnabled then return end

        local puppet = ent:GetPuppet()
        -- KeyPress(IN_ATTACK2) on the SERVER owns this state; reading an
        -- NWBool works in singleplayer even when client key hooks don't.
        local firstPerson = ent:GetNWBool("PC2_EXE_FirstPerson", true)

        if firstPerson then
            -- Head bone location is evaluated every frame, so it follows
            -- EXE's idle, walking, running and ability animations.
            -- 43 units forward of the head avoids seeing its muzzle.
            local desired = offsetFromBone(
                puppet, ent.formTable.FirstPersonBone, angles, ply:EyePos())
            return {
                origin = desired,
                angles = angles,
                fov = fov,
                drawviewer = true, -- REQUIRED to see EXE's own puppet.
                znear = 4
            }
        end

        -- Third person tracks EXE's spine/UpperTorso, moved a little
        -- LOWER and farther to the RIGHT, as requested.
        local anchor = offsetFromBone(
            puppet, ent.formTable.ThirdPersonBone,
            angles, ply:EyePos() - Vector(0, 0, 18))
        local distance = ent.formTable.camera and ent.formTable.camera.dist or 115
        local desired = anchor - angles:Forward() * distance
        local trace = util.TraceHull({
            start = anchor,
            endpos = desired,
            mins = Vector(-5, -5, -5),
            maxs = Vector(5, 5, 5),
            filter = { ply, ent, puppet },
            mask = MASK_VISIBLE
        })
        return {
            origin = trace.HitPos,
            angles = angles,
            fov = fov,
            drawviewer = true
        }

    end
})

-- Remove sprint while recovering on BOTH realms, just as survivor
-- stamina filtering is applied on client and server for prediction.
-- An additional SetupMove cap prevents +speed binds or stale speed values
-- from bypassing the 5-stud/s post-charge movement limit.
local function recoveringFromCharge(ply)
    if not IsValid(ply) then return false end
    local pill = pk_pills.getMappedEnt(ply)
    if not isEXE(pill) then return false end
    local recoveryUntil = SERVER and (pill.PC2_EXERecoveryUntil or 0)
        or pill:GetNWFloat("PC2_EXE_RecoveryUntil", 0)
    return CurTime() < recoveryUntil
end

hook.Add("StartCommand", "PC2_EXE_PostChargeNoSprint", function(ply, cmd)
    if recoveringFromCharge(ply) then
        cmd:RemoveKey(IN_SPEED)
    end
end)

hook.Add("SetupMove", "PC2_EXE_PostChargeWalkCap", function(ply, mv)
    if not recoveringFromCharge(ply) then return end
    if mv:GetMaxSpeed() > WALK_SPEED then mv:SetMaxSpeed(WALK_SPEED) end
    if mv:GetMaxClientSpeed() > WALK_SPEED then
        mv:SetMaxClientSpeed(WALK_SPEED)
    end
end)

-- Server driver: enforce EXE's Roblox-stud speeds throughout the charge.
if SERVER then
    hook.Add("Think", "PC2_EXEPillServer", function()
        local now = CurTime()
        for _, ply in ipairs(player.GetAll()) do
            local ent = pk_pills.getMappedEnt(ply)
            if isEXE(ent) and ply:Alive() then
                if not ply:GetNWBool("PC2_IsMonster", false) then
                    ply:SetNWBool("PC2_IsMonster", true)
                end
                -- End the charge on its original timestamp, regardless
                -- of server Think timing. Begin the 0.60s walk-only period.
                local chargeUntil = ent.PC2_EXETooSlowUntil or 0
                if chargeUntil > 0 and now >= chargeUntil then
                    ent.PC2_EXETooSlowUntil = 0
                    ent.PC2_EXERecoveryUntil = chargeUntil + CHARGE_RECOVERY
                    ent:SetNWFloat("PC2_EXE_TooSlowUntil", 0)
                    ent:SetNWFloat("PC2_EXE_RecoveryUntil", ent.PC2_EXERecoveryUntil)
                end

                if now < (ent.PC2_EXETooSlowUntil or 0)
                    and not ent.PC2_EXETooSlowGrabbed then
                    tickTooSlow(ply, ent, now)
                end

                -- Calculate movement AFTER grab checks, so a successful
                -- grab immediately replaces charge speed with recovery.
                local charging = now < (ent.PC2_EXETooSlowUntil or 0)
                    and not ent.PC2_EXETooSlowGrabbed
                local recovering = now < (ent.PC2_EXERecoveryUntil or 0)
                local walk, run
                if charging then
                    -- Full charge speed even without holding Shift.
                    walk, run = CHARGE_SPEED, CHARGE_SPEED
                elseif recovering then
                    -- For 0.60s Shift has no speed benefit.
                    walk, run = WALK_SPEED, WALK_SPEED
                else
                    -- Keep the existing 4s Thorny Grave capture bonus.
                    local boosted = now < (ent.PC2_EXESpeedBoostUntil or 0)
                    local bonus = boosted and 1.5 or 1
                    walk, run = WALK_SPEED * bonus, RUN_SPEED * bonus
                end
                if ply:GetWalkSpeed() ~= walk then ply:SetWalkSpeed(walk) end
                if ply:GetRunSpeed() ~= run then ply:SetRunSpeed(run) end

                if now >= (ent.PC2_EXESniffStart or 0) then
                    ent.PC2_EXESniffStart = now + 12
                    ent:SetNWFloat("PC2_EXE_SniffUntil", now + 2)
                    ent:PillSound("sniff")
                end
            elseif ply:GetNWBool("PC2_IsMonster", false) then
                -- Restoring/changing form clears monster status and unfreezes
                -- players who were caught during an interrupted kill.
                ply:SetNWBool("PC2_IsMonster", false)
                if ply:Alive() then ply:Freeze(false) end
            end
        end
    end)

    -- Match Bendy Redrawn's server-side number-key ability dispatch.
    -- PlayerButtonDown receives KEY_1/KEY_2; unlike input.WasKeyPressed
    -- on the client, this works in GMod singleplayer.
    hook.Add("PlayerButtonDown", "PC2_EXE_NumberAbilities", function(ply, button)
        if button ~= KEY_1 and button ~= KEY_2 then return end
        if not IsValid(ply) or not ply:Alive() then return end
        local pill = pk_pills.getMappedEnt(ply)
        if not isEXE(pill) then return end

        if button == KEY_1 then
            tooSlow(ply, pill)
        elseif button == KEY_2 then
            thornyGrave(ply, pill)
        end
    end)

    -- RMB (+attack2) is an IN_* button, so use the corresponding KeyPress
    -- hook rather than client polling. Its state is networked to the owner.
    -- The EXE pill has no 'attack2' field, so RMB won't fire an ability.
    hook.Add("KeyPress", "PC2_EXE_SwitchCamera", function(ply, key)
        if key ~= IN_ATTACK2 or not IsValid(ply) or not ply:Alive() then return end
        local pill = pk_pills.getMappedEnt(ply)
        if not isEXE(pill) then return end
        -- Avoid a second toggle from re-prediction within the same press.
        local now = CurTime()
        if now < (pill.PC2_EXENextCameraToggle or 0) then return end
        pill.PC2_EXENextCameraToggle = now + 0.20
        pill:SetNWBool("PC2_EXE_FirstPerson",
            not pill:GetNWBool("PC2_EXE_FirstPerson", true))
    end)
else

    -- The original DrGBase EXE HUD uses these four artwork names.
    -- Ready and cooling-down each have their own image, unlike the
    -- old text-only placeholder. They can be shipped with the gamemode
    -- under content/materials/noodles/pillarchase2/.
    local iconNames = {
        tooSlow = {
            "noodles/pillarchase2/TooSlow_1.png",
            "noodles/pillarchase2/TooSlow_2.png"
        },
        thorny = {
            "noodles/pillarchase2/thornygrave_1.png",
            "noodles/pillarchase2/thornygrave_2.png"
        }
    }
    local icons = {}
    local iconExists = {}

    for ability, states in pairs(iconNames) do
        icons[ability] = {}
        iconExists[ability] = {}
        for i, name in ipairs(states) do
            icons[ability][i] = Material(name, "smooth")
            iconExists[ability][i] = file.Exists("materials/" .. name, "GAME")
                and not icons[ability][i]:IsError()
        end
    end

    surface.CreateFont("PC2_EXEAbility", {
        font = "Trebuchet MS", size = 17, weight = 900
    })
    surface.CreateFont("PC2_EXEAbilitySmall", {
        font = "Trebuchet MS", size = 14, weight = 800
    })

    local abilityCards = {
        { name = "TOO SLOW", key = "1", icon = "tooSlow",
            readyTime = "PC2_EXE_TooSlowReady",
            activeTime = "PC2_EXE_TooSlowUntil" },
        { name = "THORNY GRAVE", key = "2", icon = "thorny",
            readyTime = "PC2_EXE_ThornyReady",
            activeTime = "PC2_EXE_TrapCastingUntil" }
    }

    hook.Add("HUDPaint", "PC2_EXEAbilities", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() then return end
        local pill = pk_pills.getMappedEnt(ply)
        if not isEXE(pill) then return end

        -- The source HUD places two large ability icons centered at
        -- the bottom of the screen. Adapt their positions to GMod's HUD.
        local size = math.Clamp(math.Round(ScrH() * 0.105), 64, 116)
        local gap = math.Clamp(math.Round(ScrH() * 0.032), 16, 42)
        local totalWidth = size * 2 + gap
        local x0 = math.floor((ScrW() - totalWidth) * .5)
        local y = ScrH() - size - math.Round(ScrH() * 0.040)

        for i, ability in ipairs(abilityCards) do
            local x = x0 + (i - 1) * (size + gap)
            local timeLeft = math.max(0, pill:GetNWFloat(ability.readyTime, 0) - CurTime())
            local activeLeft = math.max(0, pill:GetNWFloat(ability.activeTime, 0) - CurTime())
            local ready = timeLeft <= 0 and activeLeft <= 0
            local imageState = ready and 1 or 2
            local texture = icons[ability.icon][imageState]

            if iconExists[ability.icon][imageState] then
                surface.SetMaterial(texture)
                surface.SetDrawColor(255, 255, 255, 255)
                surface.DrawTexturedRect(x, y, size, size)
            else
                -- These files aren't in the current GitHub main tree.
                -- A readable fallback prevents invisible controls until
                -- their actual Roblox artwork is added at the paths above.
                draw.RoundedBox(6, x, y, size, size,
                    ready and Color(28, 25, 33, 230) or Color(59, 21, 24, 230))
                surface.SetDrawColor(ready and Color(201, 75, 89)
                    or Color(106, 32, 43))
                surface.DrawOutlinedRect(x, y, size, size, 2)
                draw.SimpleText(ability.name, "PC2_EXEAbilitySmall",
                    x + size / 2, y + size / 2, color_white,
                    TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            draw.SimpleTextOutlined(ability.key, "PC2_EXEAbility",
                x + 5, y + 6, color_white,
                TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP, 1, Color(0, 0, 0))

            local status
            if activeLeft > 0 then
                status = "ACTIVE"
            elseif timeLeft > 0 then
                status = string.format("%.1fs", timeLeft)
            else
                status = "READY"
            end
            draw.SimpleTextOutlined(status, "PC2_EXEAbilitySmall",
                x + size / 2, y + size - 7, color_white,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0))
        end
    end)

    hook.Add("PreDrawHalos", "PC2_EXESniffHalo", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local pill = pk_pills.getMappedEnt(ply)
        if not isEXE(pill) or CurTime() >= pill:GetNWFloat("PC2_EXE_SniffUntil", 0) then
            return
        end
        local marked = {}
        for _, ent in ipairs(ents.GetAll()) do
            if enemy(ply, ent) then marked[#marked + 1] = ent end
        end
        if #marked > 0 then
            halo.Add(marked, Color(255, 0, 0), 10, 10, 5, true, true)
        end
    end)
end
