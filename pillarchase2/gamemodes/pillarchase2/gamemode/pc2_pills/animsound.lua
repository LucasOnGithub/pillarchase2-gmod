-- EXE animation-event sounds.
-- EXE.mdl already sends animation event 5004 (AE_CL_PLAYSOUND):
--   walk -> DS.EXE.WalkStep (twice per cycle)
--   run and charge -> DS.EXE.RunStep (twice per cycle)
-- There is no need to estimate step intervals or replay these in Think.
AddCSLuaFile()

local stepFiles = {
    "dark/EXE/Footsteps/Step1.wav",
    "dark/EXE/Footsteps/Step2.wav"
}

local available = {}
for _, filename in ipairs(stepFiles) do
    if file.Exists("sound/" .. filename, "GAME") then
        available[#available + 1] = filename
    end
end

-- The Step1/Step2 files supplied in the reference sound script haven't
-- been added to this repository yet. Until then, keep EXE audible using
-- the project's existing sound, but still trigger on the MODEL's events.
if #available == 0 then
    available = { "noodles/pillarchase2/exe/exestep.wav" }
    if SERVER then
        print("[PC2 EXE] Step1.wav / Step2.wav missing; using exestep.wav until they are installed.")
    end
end

sound.Add({
    name = "DS.EXE.WalkStep",
    channel = CHAN_USER_BASE + 10,
    volume = 1.0,
    sound = available
})

sound.Add({
    name = "DS.EXE.RunStep",
    channel = CHAN_USER_BASE + 10,
    -- Source script specifies 1.2 volume; GMod SoundData volume is
    -- 0..1, so increase sound level instead of passing an invalid value.
    volume = 1.0,
    level = 80,
    sound = available
})
