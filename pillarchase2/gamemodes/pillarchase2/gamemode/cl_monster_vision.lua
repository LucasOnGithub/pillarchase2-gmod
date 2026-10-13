-- Monster-only low-light visibility. Runs on the viewing client so map
-- lighting and the survivor experience stay completely unchanged.
if SERVER then return end

-- 0 disables the effect; 1 is the default; values up to 2 brighten more.
-- This is a client preference, not a global mat_fullbright/gamma change.
local intensity = CreateClientConVar(
    "pc2_monster_vision_strength", "1", true, false,
    "Brightness of monster vision (0 = off, 1 = normal, 2 = brighter)", 0, 2)

local colour = {
    ["$pp_colour_addr"] = 0,
    ["$pp_colour_addg"] = 0,
    ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = 0,
    ["$pp_colour_contrast"] = 1,
    ["$pp_colour_colour"] = 1,
    ["$pp_colour_mulr"] = 0,
    ["$pp_colour_mulg"] = 0,
    ["$pp_colour_mulb"] = 0
}

local function monsterViewer()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    if not ply:GetNWBool("PC2_IsMonster", false)
        and ply:GetNWString("PC2_MonsterForm", "") == "" then
        return
    end
    return ply
end

-- Lift dark parts of the rendered world without washing out the colours.
-- This runs before HUD drawing and never changes survivor screens.
hook.Add("RenderScreenspaceEffects", "PC2_MonsterLowLightVision", function()
    if not monsterViewer() then return end
    local amount = math.Clamp(intensity:GetFloat(), 0, 2)
    if amount <= 0 then return end

    colour["$pp_colour_brightness"] = 0.085 * amount
    colour["$pp_colour_contrast"] = 1 + 0.06 * amount
    colour["$pp_colour_colour"] = 1 + 0.03 * amount
    DrawColorModify(colour)
end)

-- Screen brightening alone cannot reveal walls/models that the map
-- rendered pure black. This client-only, shadowless fill light follows
-- the MONSTER MODEL'S HEAD rather than a point far in front of the camera.
-- It expires promptly on unmorph, death or when the setting is disabled.
local function monsterHeadPosition(ply)
    local pill = ply:GetNWEntity("PC2_ActiveMonsterPill")
    if IsValid(pill) and pill.GetPuppet then
        local puppet = pill:GetPuppet()
        if IsValid(puppet) then
            -- EXE uses "Head"; Valve-style monster models may use these.
            local bone = puppet:LookupBone("Head")
                or puppet:LookupBone("ValveBiped.Bip01_Head1")
                or puppet:LookupBone("head")
            if bone ~= nil and bone >= 0 then
                local pos = puppet:GetBonePosition(bone)
                if isvector(pos) and not pos:IsZero()
                    and pos:DistToSqr(puppet:GetPos()) > 1 then
                    return pos
                end

                local matrix = puppet:GetBoneMatrix(bone)
                if matrix then
                    pos = matrix:GetTranslation()
                    if isvector(pos) and not pos:IsZero() then
                        return pos
                    end
                end
            end
        end
    end

    -- Covers monsters without a networked puppet and its initial spawn.
    return ply:EyePos()
end

local nextLight = 0
hook.Add("Think", "PC2_MonsterLowLightFill", function()
    local ply = monsterViewer()
    if not ply then return end

    local amount = math.Clamp(intensity:GetFloat(), 0, 2)
    if amount <= 0 then return end

    local now = CurTime()
    if now < nextLight then return end
    nextLight = now + 0.05

    local light = DynamicLight(ply:EntIndex() + 32768)
    if not light then return end

    -- A short horizontal offset keeps the light outside EXE's face,
    -- without moving it above/below head level when looking up or down.
    local head = monsterHeadPosition(ply)
    local levelForward = Angle(0, ply:EyeAngles().y, 0):Forward()
    light.pos = head + levelForward * 22
    light.r = 235
    light.g = 240
    light.b = 255
    light.brightness = 1.25 * amount
    -- Roughly twice the previous ~520-unit reach, especially useful on
    -- dark PC2 maps. Only this client's monster view receives the light.
    light.size = 1200 + 180 * (amount - 1)
    light.decay = 0
    light.dietime = now + 0.12
    light.noworld = false
    light.nomodel = false
end)
