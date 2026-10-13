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
-- Prefer up to 950 Source units between EXE and other MAP spawn points.
local MAX_SPAWN_SEPARATION = 950
local MIN_SPAWN_SEPARATION = 400
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

-- Only actual BSP player spawn entities are legal. Never manufacture
-- locations from random traces: those can be outside the playable map.
local MAP_SPAWN_CLASSES = {
    "info_player_start", "info_player_deathmatch",
    "info_player_counterterrorist", "info_player_terrorist",
    "info_player_rebel", "info_player_combine",
    "info_player_teamspawn", "gmod_player_start", "pc2_spawn"
}

local function spawnPositions()
    local points, seen = {}, {}
    for _, className in ipairs(MAP_SPAWN_CLASSES) do
        for _, spot in ipairs(ents.FindByClass(className)) do
            local pos = spot:GetPos() + Vector(0, 0, 5)
            local key = math.floor(pos.x / 24) .. ":" ..
                math.floor(pos.y / 24) .. ":" .. math.floor(pos.z / 24)
            if not seen[key] and util.IsInWorld(pos + Vector(0, 0, 36)) then
                local tr = util.TraceHull({
                    start = pos, endpos = pos,
                    mins = Vector(-16, -16, 0),
                    maxs = Vector(16, 16, 72),
                    -- Don't reject a map spawn if a lobby player occupies it.
                    mask = MASK_PLAYERSOLID_BRUSHONLY
                })
                if not tr.StartSolid and not tr.AllSolid then
                    seen[key] = true
                    points[#points + 1] = {
                        pos = pos, ang = spot:GetAngles(),
                        className = className
                    }
                end
            end
        end
    end
    return points
end

-- Diagnostics for validating the BSP's true player spawn entities.
concommand.Add("pc2_round_spawns", function(ply)
    if IsValid(ply) and not ply:IsAdmin() then return end
    local points = spawnPositions()
    local function report(msg)
        print(msg)
        if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, msg) end
    end
    report(string.format("[PC2 Round] %s: %d usable map spawns",
        game.GetMap(), #points))
    for i, point in ipairs(points) do
        report(string.format("  #%d %s: (%.0f, %.0f, %.0f)", i,
            point.className, point.pos.x, point.pos.y, point.pos.z))
    end
end)

local function mapSeparation(points)
    local farthest = 0
    for i = 1, #points do
        for j = i + 1, #points do
            farthest = math.max(farthest,
                points[i].pos:DistToSqr(points[j].pos))
        end
    end
    local spread = math.sqrt(farthest)
    return math.min(MAX_SPAWN_SEPARATION,
        math.max(MIN_SPAWN_SEPARATION, spread * 0.6)), spread
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

-- A valid EXE spawn must have room for its cinematic camera AND enough
-- distant, real map spawn entities for every survivor.
local function selectSpawnPoint(points, survivorCount, minGap)
    local best, cameraPos, cameraAng, bestScore
    for _, spot in ipairs(points) do
        local far = 0
        for _, other in ipairs(points) do
            if other ~= spot and spot.pos:DistToSqr(other.pos) >= minGap * minGap then
                far = far + 1
            end
        end
        if far >= survivorCount then
            local camPos, camAng, clearance = cameraAt(spot)
            if camPos and clearance >= 160 then
                local score = clearance + math.Rand(0, 55)
                if not bestScore or score > bestScore then
                    best, cameraPos, cameraAng, bestScore =
                        spot, camPos, camAng, score
                end
            end
        end
    end
    return best, cameraPos, cameraAng
end

local function selectSurvivorSpawns(points, origin, amount, minGap)
    local available = {}
    for _, spot in ipairs(points) do
        if spot.pos:DistToSqr(origin) >= minGap * minGap then
            available[#available + 1] = spot
        end
    end
    if #available < amount then return {} end
    local selected = {}
    for _ = 1, amount do
        local separated = {}
        for _, candidate in ipairs(available) do
            local distant = true
            for _, existing in ipairs(selected) do
                if candidate.pos:DistToSqr(existing.pos) < 300 * 300 then
                    distant = false
                    break
                end
            end
            if distant then separated[#separated + 1] = candidate end
        end
        if #separated == 0 then separated = available end
        local chosen = separated[math.random(#separated)]
        selected[#selected + 1] = chosen
        table.RemoveByValue(available, chosen)
    end
    return selected
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
    if #points < #all then
        print(string.format("[PC2 Round] %s has %d valid map spawn entities "
            .. "for %d players. Need one unique map spawn per player; "
            .. "will not generate off-map positions. Run pc2_round_spawns.",
            game.GetMap(), #points, #all))
        resetRound()
        return
    end

    local minGap, mapSpread = mapSeparation(points)
    monsterStart, introCamera, introAngles =
        selectSpawnPoint(points, #all - 1, minGap)
    if not monsterStart or not introCamera then
        print(string.format("[PC2 Round] %s: no camera-safe EXE spawn "
            .. "with %d other map spawns at least %.0f units away "
            .. "(max map spawn separation %.0f). Run pc2_round_spawns.",
            game.GetMap(), #all - 1, minGap, mapSpread))
        resetRound()
        return
    end
    spawnChoices = selectSurvivorSpawns(points,
        monsterStart.pos, #all - 1, minGap)
    if #spawnChoices < #all - 1 then
        print("[PC2 Round] Not enough distant MAP spawn entities; round cancelled.")
        resetRound()
        return
    end
    print(string.format("[PC2 Round] EXE map spawn: %s (%.0f %.0f %.0f). "
        .. "Survivor map spawn count: %d; minimum distance: %.0f.",
        monsterStart.className, monsterStart.pos.x, monsterStart.pos.y,
        monsterStart.pos.z, #spawnChoices, minGap))

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

        -- Teleport survivors only after the tip is up. All spawn choices
        -- are real map player-start entities away from EXE.
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
