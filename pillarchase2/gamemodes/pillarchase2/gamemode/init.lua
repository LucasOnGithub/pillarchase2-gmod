-- Server-side gamemode entry point.
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("sh_survivor_movement.lua")
AddCSLuaFile("cl_timer.lua")
AddCSLuaFile("cl_survivor_hud.lua")
AddCSLuaFile("cl_stamina.lua")

include("shared.lua")
include("pc2_pills/init.lua")
