-- PC2 pill pack registration (works inside the gamemode without a separate addon).
-- Runtime must be initialized before loading this file.
AddCSLuaFile()
assert(pk_pills and pk_pills.packStart, "PC2: pk_pills has not loaded")
pk_pills.packStart("Pillar Chase 2", "pc2", "icon16/user.png")
-- EXE's model sequences already contain AE_CL_PLAYSOUND (5004)
-- events for these sounds. Register them before the pill form loads.
include("animsound.lua")
include("ppp_include/pill_pc2_exe.lua")
print("[PC2] Registered EXE as pk_pill_apply pc2_exe")
