-- PC2 EXE playable pill, ported from npc_drg_pc2_exe (DrGBase Nextbot).
-- Standalone pk_pills form: does NOT require DrGBase.
AddCSLuaFile()

local ID = "pc2_exe"
local MODEL = "models/noodles/pillarchase2/exe.mdl"
local TRAP = "pc2_exe_trap"

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
    util.AddNetworkString("pc2_exe_ability")
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
    animate(ent, "attack")
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

    ent.PC2_EXETooSlowUntil = now + 3
    ent.PC2_EXENextTooSlow = now + 3 + getSetting("tooSlowCooldown", "_TooSlowCooldown")
    ent.PC2_EXETooSlowGrabbed = false
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
    ent.PC2_EXEBusyUntil = now + 1.15
    ent:SetNWFloat("PC2_EXE_ThornyReady", ent.PC2_EXENextThorny)
    ent:PillSound("deploy")
    animate(ent, "trap")

    -- The Nextbot creates its trap at PlantSeed (left hand animation event).
    timer.Simple(.8, function()
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
        ent.PC2_EXETooSlowUntil = now
        ent.PC2_EXEBusyUntil = now + 1.6
        ent:SetNWFloat("PC2_EXE_TooSlowUntil", 0)
        ent:PillSound("grab")
        animate(ent, "bite")
        if victim:IsPlayer() then victim:Freeze(true) end
        timer.Simple(.60, function()
            if not isEXE(ent) or not IsValid(victim) then return end
            damage(ply, ent, victim, getSetting("bite", "_TooSlowDamage"))
        end)
        timer.Simple(1.3, function()
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
    health = 1000,
    hull = Vector(30, 30, 90),
    duckBy = 0,
    jumpPower = 0,
    noFallDamage = true,
    hideWeapons = true,
    movePoseMode = false,
    -- The close possession camera must not render the player's own
    -- model in front of its lens.
    hidePuppetForFirstPerson = function()
        local setting = GetConVar("pc2_exe_firstperson")
        return setting and setting:GetBool() or false
    end,
    -- Original possession: first view 115u behind + (0,10,15) offset,
    -- second close view +25u forward. Press B to toggle view.
    -- Used by the base camera if custom CalcView is unavailable.
    camera = {
        offset = Vector(0, 10, 100),
        dist = 115
    },
    moveSpeed = {
        walk = 60,
        run = 395
    },
    anims = {
        default = {
            idle = "Idle",
            walk = "walk",
            run = "run",
            attack = "Attack1",
            kill = "Jumpscare",
            bite = "Bite",
            trap = "Plant",
            charge = "RunCharge"
        }
    },
    sounds = {
        step = "noodles/pillarchase2/exe/exestep.wav",
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
            ent:SetNWFloat("PC2_EXE_TooSlowReady", 0)
            ent:SetNWFloat("PC2_EXE_ThornyReady", 0)
            ent:SetNWFloat("PC2_EXE_SniffUntil", 0)
        end
    end,
    attack = {
        mode = "trigger",
        func = melee
    },
    attack2 = {
        mode = "trigger",
        func = tooSlow
    },
    reload = thornyGrave,
    -- An EXE-specific camera callback is supported by a tiny addition
    -- to ppp_includes/nocompat.lua. The other pills remain unchanged.
    calcView = function(ply, ent, pos, angles, fov)
        if not isEXE(ent) then return end
        if ply:GetViewEntity() ~= ply then return end

        local firstPerson = CLIENT and GetConVar("pc2_exe_firstperson")
            and GetConVar("pc2_exe_firstperson"):GetBool()
        local start = ply:EyePos()
        if firstPerson then
            return {
                origin = start + angles:Forward() * 25,
                angles = angles,
                fov = fov,
                drawviewer = false
            }
        end

        local cameraPos = start + angles:Right() * 10 + Vector(0, 0, 15)
        local desired = cameraPos - angles:Forward() * 115
        local puppet = ent:GetPuppet()
        local tr = util.TraceHull({
            start = cameraPos,
            endpos = desired,
            mins = Vector(-5, -5, -5), maxs = Vector(5, 5, 5),
            filter = {ply, ent, puppet},
            mask = MASK_VISIBLE
        })
        return {
            origin = tr.HitPos,
            angles = angles,
            fov = fov,
            drawviewer = true
        }
    end
})

-- Server driver: keep original Nextbot mode speeds and sniff reveal cadence.
if SERVER then
    hook.Add("Think", "PC2_EXEPillServer", function()
        local now = CurTime()
        for _, ply in ipairs(player.GetAll()) do
            local ent = pk_pills.getMappedEnt(ply)
            if isEXE(ent) and ply:Alive() then
                if not ply:GetNWBool("PC2_IsMonster", false) then
                    ply:SetNWBool("PC2_IsMonster", true)
                end
                local boosted = now < (ent.PC2_EXESpeedBoostUntil or 0)
                local charging = now < (ent.PC2_EXETooSlowUntil or 0)
                local mult = boosted and 1.5 or 1
                local walk = 60 * mult
                local run = (charging and 500 or 395 * mult)
                if ply:GetWalkSpeed() ~= walk then ply:SetWalkSpeed(walk) end
                if ply:GetRunSpeed() ~= run then ply:SetRunSpeed(run) end

                if charging and not ent.PC2_EXETooSlowGrabbed then
                    tickTooSlow(ply, ent, now)
                    if ent.PC2_EXETooSlowUntil > now then
                        ent:PillAnimTick("charge")
                    end
                end

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

    net.Receive("pc2_exe_ability", function(_, ply)
        local selected = net.ReadUInt(2)
        local pill = pk_pills.getMappedEnt(ply)
        if not isEXE(pill) or not ply:Alive() then return end
        if selected == 1 then tooSlow(ply, pill) end
        if selected == 2 then thornyGrave(ply, pill) end
    end)
else
    local view = CreateClientConVar("pc2_exe_firstperson", "0", true, false,
        "EXE view: 0 = original third-person view, 1 = close/first-person.")
    hook.Add("Think", "PC2_EXEKeys", function()
        if gui.IsGameUIVisible() or vgui.GetKeyboardFocus() then return end
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local pill = pk_pills.getMappedEnt(ply)
        if not isEXE(pill) then return end

        if input.WasKeyPressed(KEY_1) then
            net.Start("pc2_exe_ability")
            net.WriteUInt(1, 2)
            net.SendToServer()
        elseif input.WasKeyPressed(KEY_2) then
            net.Start("pc2_exe_ability")
            net.WriteUInt(2, 2)
            net.SendToServer()
        elseif input.WasKeyPressed(KEY_B) then
            RunConsoleCommand("pc2_exe_firstperson", view:GetBool() and "0" or "1")
        end
    end)

    surface.CreateFont("PC2_EXEAbility", {
        font = "Trebuchet MS", size = 18, weight = 900
    })
    surface.CreateFont("PC2_EXEAbilitySmall", {
        font = "Trebuchet MS", size = 14, weight = 700
    })

    hook.Add("HUDPaint", "PC2_EXEAbilities", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local pill = pk_pills.getMappedEnt(ply)
        if not isEXE(pill) then return end

        local y = ScrH() - 94
        local mid = ScrW() / 2
        for index, data in ipairs({
            {label = "TOO SLOW", key = "1 / RMB", time = pill:GetNWFloat("PC2_EXE_TooSlowReady", 0)},
            {label = "THORNY GRAVE", key = "2 / R", time = pill:GetNWFloat("PC2_EXE_ThornyReady", 0)}
        }) do
            local x = mid + (index == 1 and -150 or 10)
            local left = math.max(0, data.time - CurTime())
            draw.RoundedBox(8, x, y, 140, 58, Color(12, 7, 12, 215))
            draw.RoundedBox(4, x + 3, y + 3, 134, 4,
                left > 0 and Color(126, 31, 40) or Color(201, 60, 84))
            draw.SimpleText(data.label, "PC2_EXEAbility", x + 70, y + 21,
                color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(left > 0 and string.format("%.1fs", left) or data.key,
                "PC2_EXEAbilitySmall", x + 70, y + 43,
                left > 0 and Color(219, 123, 125) or Color(255, 226, 226),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
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
