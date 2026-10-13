-- PC2 server-authoritative round flow.
-- 2 players -> 60s intermission -> EXE intro -> 5s tips -> role reveal
-- -> dynamic survival timer -> victory -> lobby. No Faker dependency.
if CLIENT then return end

local MIN_PLAYERS = 2
local INTERMISSION = 60
local INTRO_DURATION = 4.0
local TIPS_DURATION = 5.0
local REVEAL_DURATION = 3.3
local END_DURATION = 5.0
local MIN_SPAWN_GAP = 950 -- Source units; prefer this, maximize if map is small
local ROUND_BASE = 180
local ROUND_PER_EXTRA_PLAYER = 30
local ROUND_MAX = 480
local KILL_BONUS = 10

util.AddNetworkString("PC2_RoundIntroCamera")

local mode = "Waiting"
local phaseEnds = 0
local roundEnds = 0
local monster = nil
local participants = {}
local spawnChoices = {}
local monsterStart = nil
local introCamera = nil
local introAngles = nil
local lastMonster = nil
local nextThink = 0
local roundSerial = 0
local monsterMorphed = false

local function setMode(nextMode, seconds)
    mode = nextMode
    phaseEnds = CurTime() + (seconds or 0)
    SetGlobalString("PC2_RoundMode", mode)
    SetGlobalFloat("PC2_PhaseStart", CurTime())
    SetGlobalFloat("PC2_PhaseEndsAt", phaseEnds)
end

local function eligible()
    local list = {}
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:IsPlayer() then
            list[#list + 1] = ply
        end
    end
    return list
end

local function aliveSurvivors()
    local count = 0
    for ply in pairs(participants) do
        if IsValid(ply) and ply ~= monster and ply:Alive()
            and not ply:GetNWBool("PC2_Eliminated", false) then
            count = count + 1
        end
    end
    return count
end

local function clearMonster(ply)
    if not IsValid(ply) then return end
    -- Pill Pack uses module("pk_pills", package.seeall), so restore
    -- belongs to pk_pills, NOT to the global gamemode environment.
    if pk_pills and isfunction(pk_pills.restore) then
        pk_pills.restore(ply, true)
    end
    ply:SetNWBool("PC2_IsMonster", false)
    ply:SetNWString("PC2_MonsterForm", "")
    ply:SetNWEntity("PC2_ActiveMonsterPill", NULL)
end

local function lobbyPlayer(ply)
    if not IsValid(ply) then return end
    clearMonster(ply)
    ply:UnSpectate()
    ply:SetNoDraw(false)
    ply:SetNotSolid(false)
    ply:SetNoTarget(false)
    ply:Freeze(false)
    ply:SetNWBool("PC2_InRound", false)
    ply:SetNWBool("PC2_Eliminated", false)
    ply:SetNWString("PC2_RoundRole", "Lobby")
    -- Respawn even if still technically alive: late joiners entered
    -- OBS_MODE_ROAMING without dying. Spawning guarantees normal walking,
    -- a real player model and a lobby spawn instead of an observer origin.
    ply:Spawn()
    -- The EXE pill raises its owner's maximum HP to 9999. Fully reset
    -- both values when returning to the lobby for the next survivor round.
    ply:SetMaxHealth(100)
    ply:SetHealth(100)
end

local function spectator(ply)
    if not IsValid(ply) then return end
    ply:SetNWBool("PC2_Eliminated", true)
    ply:SetNWString("PC2_RoundRole", "Spectator")
    ply:SetNoTarget(true)
    ply:SetNoDraw(true)
    ply:SetNotSolid(true)
    ply:Freeze(false)
    ply:Spectate(OBS_MODE_ROAMING)
end

local function spawnPositions()
    local points, seen = {}, {}
    for _, class in ipairs({
        "info_player_start", "info_player_deathmatch", "info_player_counterterrorist",
        "info_player_terrorist", "info_player_rebel", "info_player_combine",
        "info_player_teamspawn", "gmod_player_start", "pc2_spawn"
    }) do
        for _, spot in ipairs(ents.FindByClass(class)) do
            local pos = spot:GetPos() + Vector(0, 0, 5)
            local key = math.floor(pos.x / 32) .. ":" .. math.floor(pos.y / 32)
            if not seen[key] then
                seen[key] = true
                points[#points + 1] = {pos = pos, ang = spot:GetAngles()}
            end
        end
    end

    -- No specialized map is required. Generate additional walkable,
    -- unobstructed ground locations if a normal Sandbox map has only
    -- one player start. This is also what gives us EXE-separated spawns.
    local seeds = table.Copy(points)
    if #seeds == 0 then
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) then
                seeds[#seeds + 1] = {pos = ply:GetPos(), ang = Angle(0, 0, 0)}
            end
        end
    end
    for _ = 1, 80 do
        if #seeds == 0 then break end
        local seed = seeds[math.random(#seeds)]
        local theta = math.Rand(0, math.pi * 2)
        local distance = math.Rand(360, 2400)
        local delta = Vector(math.cos(theta) * distance, math.sin(theta) * distance, 0)
        local top = seed.pos + delta + Vector(0, 0, 300)
        local down = util.TraceLine({
            start = top, endpos = top - Vector(0, 0, 920),
            mask = MASK_PLAYERSOLID_BRUSHONLY
        })
        if down.Hit and not down.HitSky and down.HitNormal.z > 0.65 then
            local point = down.HitPos + Vector(0, 0, 6)
            local hull = util.TraceHull({
                start = point, endpos = point,
                mins = Vector(-24, -24, 0), maxs = Vector(24, 24, 90),
                mask = MASK_PLAYERSOLID
            })
            if not hull.StartSolid and not hull.AllSolid
                and util.IsInWorld(point + Vector(0, 0, 36)) then
                local key = math.floor(point.x / 90) .. ":" .. math.floor(point.y / 90)
                if not seen[key] then
                    seen[key] = true
                    points[#points + 1] = {
                        pos = point, ang = Angle(0, math.Rand(-180, 180), 0)
                    }
                end
            end
        end
    end
    return points
end

-- Look for a place where the camera can stand well away from EXE.
-- Trace the full line to avoid putting it inside a wall or the skybox.
local function cameraAt(point)
    local eye = point.pos + Vector(0, 0, 82)
    local bestPos, bestAng, bestSpace = nil, nil, -1
    for index = 1, 8 do
        local yaw = point.ang.y + (index - 1) * 45
        local towardCam = Angle(0, yaw, 0):Forward()
        local requested = eye + towardCam * 260 + Vector(0, 0, 23)
        local hit = util.TraceHull({
            start = eye, endpos = requested,
            mins = Vector(-12, -12, -12), maxs = Vector(12, 12, 12),
            mask = MASK_SOLID_BRUSHONLY
        })
        local cameraPos = hit.Hit and hit.HitPos - towardCam * 18
            or requested
        local space = cameraPos:Distance(eye)
        if space > bestSpace and util.IsInWorld(cameraPos) then
            bestPos = cameraPos
            bestAng = (eye - cameraPos):Angle()
            bestSpace = space
        end
    end
    return bestPos, bestAng, bestSpace
end

local function selectSpawnPoint(points)
    local best, camPos, camAng, score = nil, nil, nil, -1
    for _, spot in ipairs(points) do
        local c, a, d = cameraAt(spot)
        if c and d and d >= 160 and d > score then
            best, camPos, camAng, score = spot, c, a, d
        end
    end
    return best, camPos, camAng
end

local function selectSurvivorSpawns(points, origin, amount)
    -- Never reuse EXE's spawn or put survivors within 950 units of it.
    -- Choose randomly from the valid pool, favouring separated survivors.
    local eligibleSpawns = {}
    for _, spot in ipairs(points) do
        if spot.pos:DistToSqr(origin) >= MIN_SPAWN_GAP * MIN_SPAWN_GAP then
            eligibleSpawns[#eligibleSpawns + 1] = spot
        end
    end
    if #eligibleSpawns < amount then return {} end
    local result = {}
    for _ = 1, amount do
        local separated = {}
        for _, spot in ipairs(eligibleSpawns) do
            local okay = true
            for _, taken in ipairs(result) do
                if spot.pos:DistToSqr(taken.pos) < 300 * 300 then
                    okay = false
                    break
                end
            end
            if okay then separated[#separated + 1] = spot end
        end
        if #separated == 0 then separated = eligibleSpawns end
        local choice = separated[math.random(#separated)]
        result[#result + 1] = choice
        table.RemoveByValue(eligibleSpawns, choice)
    end
    return result
end

local function finishRound(winner)
    if mode == "Waiting" or mode == "Intermission" or mode == "Ending" then return end
    setMode("Ending", END_DURATION)
    SetGlobalString("PC2_RoundWinner", winner)
    SetGlobalInt("PC2_TimerSeconds", 0)
    roundEnds = 0
    for ply in pairs(participants) do
        if IsValid(ply) then ply:Freeze(true) end
    end
end

local function resetRound()
    -- Invalidate delayed tip-phase callbacks from the cancelled round.
    roundSerial = roundSerial + 1
    monsterMorphed = false
    participants = {}
    monster = nil
    monsterStart, introCamera, introAngles = nil, nil, nil
    spawnChoices = {}
    -- Move to Waiting BEFORE restore()/Spawn(). The bundled pill's
    -- OnRemove respawns its owner, and PlayerSpawn would otherwise see
    -- mode=Ending and schedule the player back into spectator mode.
    setMode("Waiting")
    for _, ply in ipairs(player.GetAll()) do lobbyPlayer(ply) end
    SetGlobalEntity("PC2_RoundMonster", NULL)
    SetGlobalString("PC2_RoundWinner", "")
    SetGlobalInt("PC2_TimerSeconds", 0)
    SetGlobalInt("PC2_TimerMaxSeconds", 0)
end

local function startRound()
    local all = eligible()
    if #all < MIN_PLAYERS then setMode("Waiting") return end
    local possible = {}
    for _, ply in ipairs(all) do
        if ply ~= lastMonster then possible[#possible + 1] = ply end
    end
    if #possible == 0 then possible = all end
    monster = possible[math.random(#possible)]
    lastMonster = monster
    roundSerial = roundSerial + 1
    monsterMorphed = false
    participants = {}
    for _, ply in ipairs(all) do participants[ply] = true end
    local points = spawnPositions()
    if #points == 0 then
        print("[PC2 Round] No spawn points found. Cannot safely start a round.")
        resetRound()
        return
    end
    monsterStart, introCamera, introAngles = selectSpawnPoint(points)
    if not monsterStart or not introCamera then resetRound() return end
    spawnChoices = selectSurvivorSpawns(points, monsterStart.pos, #all - 1)
    if #spawnChoices < #all - 1 then
        print("[PC2 Round] Map lacks enough clear spawn points at least "
            .. MIN_SPAWN_GAP .. " units from EXE; round cancelled.")
        resetRound()
        return
    end

    local duration = math.min(ROUND_BASE + math.max(0, #all - 2)
        * ROUND_PER_EXTRA_PLAYER, ROUND_MAX)
    SetGlobalInt("PC2_TimerMaxSeconds", duration)
    SetGlobalInt("PC2_TimerSeconds", duration)
    SetGlobalString("PC2_RoundWinner", "")
    SetGlobalEntity("PC2_RoundMonster", monster)

    for _, ply in ipairs(all) do
        ply:SetNWBool("PC2_InRound", true)
        ply:SetNWBool("PC2_Eliminated", false)
        ply:SetNWString("PC2_RoundRole", ply == monster and "Monster" or "Survivor")
        ply:UnSpectate()
        ply:SetNoDraw(false)
        ply:SetNotSolid(false)
        ply:SetNoTarget(false)
        if pk_pills and isfunction(pk_pills.restore) then
            pk_pills.restore(ply, true)
        end
        ply:Spawn()
        ply:SetMaxHealth(100)
        ply:SetHealth(100)
        ply:Freeze(true)
    end

    monster:SetPos(monsterStart.pos)
    monster:SetEyeAngles(Angle(0, introAngles.y + 180, 0))
    -- Do NOT morph here. Until Faker is imported the intro is only
    -- the empty camera staging, low sound, darkness and static-out.
    -- Hiding the selected player's ordinary model prevents Dr. Kleiner
    -- from being seen where the future Faker model will appear.
    monster:SetNoDraw(true)

    setMode("Intro", INTRO_DURATION)
    net.Start("PC2_RoundIntroCamera")
    net.WriteVector(introCamera)
    net.WriteAngle(introAngles)
    net.Send(all)
end

local function showTips()
    if mode ~= "Intro" then return end
    if not IsValid(monster) then finishRound("Survivors") return end

    -- Enter the opaque five-second tip screen FIRST. Allow that networked
    -- phase change to reach clients before anything moves or morphs.
    setMode("Tips", TIPS_DURATION)
    local thisRound = roundSerial
    timer.Simple(0.35, function()
        if mode ~= "Tips" or thisRound ~= roundSerial
            or not IsValid(monster) or not participants[monster] then return end

        -- This is the module's actual API (not a global apply function).
        -- Mode lock-life prevents a player unmorphing in the middle of play.
        if not pk_pills or not isfunction(pk_pills.apply)
            or not isfunction(pk_pills.getPillTable)
            or not pk_pills.getPillTable("pc2_exe") then
            print("[PC2 Round] EXE form is not registered in pk_pills; "
                .. "verify pc2_pills/init.lua ran on the server.")
            resetRound()
            return
        end
        if not monster:Alive() then
            print("[PC2 Round] Chosen EXE is not alive during tips.")
            resetRound()
            return
        end

        local success, result = pcall(pk_pills.apply,
            monster, "pc2_exe", "lock-life")
        local mapped = isfunction(pk_pills.getMappedEnt)
            and pk_pills.getMappedEnt(monster) or nil
        if not success or not IsValid(result)
            or not IsValid(mapped) or mapped:GetPillForm() ~= "pc2_exe" then
            print("[PC2 Round] EXE morph failed during tips. "
                .. "Pill Pack returned: " .. tostring(result)
                .. "; success=" .. tostring(success)
                .. "; mapped=" .. tostring(mapped))
            resetRound()
            return
        end

        monsterMorphed = true
        -- Morph finished while the tip is still hiding the world.
        monster:SetNoDraw(false)
        monster:SetPos(monsterStart.pos)
        monster:SetVelocity(-monster:GetVelocity())
        monster:Freeze(true)

        -- Teleport survivors only after the dark tip is up. Spawn choices
        -- are already random and no closer than 950 units to EXE.
        local survivorIndex = 0
        for ply in pairs(participants) do
            if IsValid(ply) and ply ~= monster then
                survivorIndex = survivorIndex + 1
                local spot = spawnChoices[survivorIndex]
                if spot then
                    ply:SetPos(spot.pos)
                    ply:SetEyeAngles(spot.ang)
                end
                ply:SetVelocity(-ply:GetVelocity())
                ply:Freeze(true)
            end
        end
        print("[PC2 Round] EXE morphed successfully under tips.")
    end)
end
local function roleReveal()
    if mode ~= "Tips" then return end
    -- Never reveal or unfreeze players unless the pill exists. This
    -- also catches unexpectedly removed EXE entities during tips.
    local pill = IsValid(monster) and pk_pills
        and isfunction(pk_pills.getMappedEnt)
        and pk_pills.getMappedEnt(monster)
    if not monsterMorphed or not IsValid(pill)
        or pill:GetPillForm() ~= "pc2_exe" then
        print("[PC2 Round] EXE was not ready when tips ended; "
            .. "aborting round instead of starting without a monster.")
        resetRound()
        return
    end
    setMode("Reveal", REVEAL_DURATION)
end

local function startChase()
    if mode ~= "Reveal" then return end
    if not IsValid(monster) or not monster:Alive() then
        finishRound("Survivors")
        return
    end
    for ply in pairs(participants) do
        if IsValid(ply) and ply:Alive() then ply:Freeze(false) end
    end
    roundEnds = CurTime() + GetGlobalInt("PC2_TimerMaxSeconds", ROUND_BASE)
    setMode("Survive")
    SetGlobalFloat("PC2_RoundEndAt", roundEnds)
end

hook.Add("PlayerInitialSpawn", "PC2_RoundJoin", function(ply)
    ply:SetNWBool("PC2_InRound", false)
    ply:SetNWBool("PC2_Eliminated", false)
    ply:SetNWString("PC2_RoundRole", "Lobby")
    if mode ~= "Waiting" and mode ~= "Intermission" then
        timer.Simple(0.35, function()
            if IsValid(ply) and not participants[ply] then spectator(ply) end
        end)
    end
end)

hook.Add("PlayerSpawn", "PC2_RoundPlayerSpawn", function(ply)
    if mode == "Waiting" or mode == "Intermission" then
        ply:SetNWBool("PC2_Eliminated", false)
        ply:SetNoDraw(false)
        ply:SetNotSolid(false)
        ply:SetNoTarget(false)
        ply:UnSpectate()
    elseif not participants[ply] or ply:GetNWBool("PC2_Eliminated", false) then
        timer.Simple(0, function()
            if IsValid(ply) then spectator(ply) end
        end)
    end
end)

hook.Add("PlayerDeathThink", "PC2_RoundDisableRespawn", function(ply)
    if mode ~= "Waiting" and mode ~= "Intermission" then
        return true
    end
end)

hook.Add("EntityTakeDamage", "PC2_RoundDamageRules", function(target)
    if not IsValid(target) or not target:IsPlayer() then return end
    if mode ~= "Survive" or not participants[target]
        or target:GetNWBool("PC2_Eliminated", false) then
        return true
    end
end)

hook.Add("PlayerDeath", "PC2_RoundSurvivorDeath", function(victim)
    if mode ~= "Survive" or not participants[victim] then return end
    if victim == monster then
        finishRound("Survivors")
        return
    end
    if victim:GetNWBool("PC2_Eliminated", false) then return end
    -- Exactly once per survivor: add 10 seconds, even on the final kill.
    roundEnds = roundEnds + KILL_BONUS
    SetGlobalInt("PC2_TimerMaxSeconds",
        GetGlobalInt("PC2_TimerMaxSeconds", ROUND_BASE) + KILL_BONUS)
    SetGlobalFloat("PC2_RoundEndAt", roundEnds)
    SetGlobalInt("PC2_TimerSeconds", math.ceil(roundEnds - CurTime()))
    victim:SetNWBool("PC2_Eliminated", true)
    timer.Simple(0.25, function()
        if IsValid(victim) and participants[victim] then spectator(victim) end
    end)
    if aliveSurvivors() == 0 then finishRound("Monster") end
end)

hook.Add("PlayerDisconnected", "PC2_RoundDisconnected", function(ply)
    participants[ply] = nil
    if ply == monster and mode ~= "Waiting" and mode ~= "Intermission"
        and mode ~= "Ending" then
        finishRound("Survivors")
    elseif mode == "Survive" and aliveSurvivors() == 0 then
        finishRound("Monster")
    end
end)

-- Keep the round synchronized even if a player leaves midway through an
-- intro, and update the timer accurately from the authoritative deadline.
hook.Add("Think", "PC2_RoundTick", function()
    if CurTime() < nextThink then return end
    nextThink = CurTime() + 0.2
    local count = #eligible()
    if mode == "Waiting" then
        SetGlobalInt("PC2_TimerSeconds", 0)
        if count >= MIN_PLAYERS then setMode("Intermission", INTERMISSION) end
    elseif mode == "Intermission" then
        if count < MIN_PLAYERS then
            SetGlobalInt("PC2_TimerSeconds", 0)
            setMode("Waiting")
        else
            SetGlobalInt("PC2_TimerSeconds", math.max(0, math.ceil(phaseEnds - CurTime())))
            if CurTime() >= phaseEnds then startRound() end
        end
    elseif mode == "Intro" and CurTime() >= phaseEnds then
        showTips()
    elseif mode == "Tips" and CurTime() >= phaseEnds then
        roleReveal()
    elseif mode == "Reveal" and CurTime() >= phaseEnds then
        startChase()
    elseif mode == "Survive" then
        if not IsValid(monster) or not monster:Alive() then
            finishRound("Survivors")
        elseif aliveSurvivors() == 0 then
            finishRound("Monster")
        elseif CurTime() >= roundEnds then
            finishRound("Survivors")
        else
            SetGlobalInt("PC2_TimerSeconds",
                math.max(0, math.ceil(roundEnds - CurTime())))
        end
    elseif mode == "Ending" and CurTime() >= phaseEnds then
        resetRound()
    end
end)

SetGlobalString("PC2_RoundMode", "Waiting")
SetGlobalFloat("PC2_PhaseStart", CurTime())
SetGlobalFloat("PC2_PhaseEndsAt", CurTime())
SetGlobalInt("PC2_TimerSeconds", 0)
SetGlobalInt("PC2_TimerMaxSeconds", 0)
SetGlobalString("PC2_RoundWinner", "")
SetGlobalEntity("PC2_RoundMonster", NULL)
print("[PC2 Round] Handler active: 2 players minimum, 60s intermission")
