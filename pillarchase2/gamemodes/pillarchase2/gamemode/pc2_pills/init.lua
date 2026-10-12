-- Initialize the bundled Pill Pack runtime inside the PC2 gamemode.
-- Previously these scripts existed only in a sibling /lua/ addon directory,
-- which was NOT loaded when installing garrysmod/gamemodes/pillarchase2/.
if SERVER then
    AddCSLuaFile("pc2_pills/init.lua")
    AddCSLuaFile("pc2_pills/pk_pills.lua")
    AddCSLuaFile("pc2_pills/pack_pc2.lua")
    AddCSLuaFile("pc2_pills/ppp_include/pill_pc2_exe.lua")

    -- These are included dynamically by pk_pills.lua. Send client modules
    -- explicitly so dedicated servers work with sv_allowcslua=0.
    for _, name in ipairs({
        "console.lua", "join_prompt.lua", "locomotion.lua",
        "nocompat.lua", "restricted.lua", "tf2lib.lua",
        "util.lua", "vox.lua"
    }) do
        AddCSLuaFile("pc2_pills/ppp_includes/" .. name)
    end
end

if not pk_pills or not pk_pills.getPillTable or not pk_pills.apply then
    include("pc2_pills/pk_pills.lua")
end

include("pc2_pills/pack_pc2.lua")
