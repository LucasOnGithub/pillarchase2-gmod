# Pillar Chase 2 — local GMod installation

Install the entire `pillarchase2/gamemodes/pillarchase2/` folder as:

```
garrysmod/gamemodes/pillarchase2/
```

It includes `gamemode/`, `entities/` (the bundled pill runtime),
`content/` (models, materials, and sounds), `pillarchase2.txt`,
`logo.png`, and `icon24.png`.

**Do not copy only the `gamemode/` subfolder.** Do not separately
install the repository's legacy `pillarchase2/lua/` tree when using
this self-contained gamemode; that tree is for an alternate addon layout.

Restart Garry's Mod, select Pillar Chase 2 and start a map. For testing,
run this in the **in-game client console** while alive:

```
pk_pill_apply pc2_exe
```

You can revert with `pk_pill_restore`.

The PC2 gamemode is based on GMod's base gamemode rather than Sandbox,
so a Sandbox-style Pills spawn-menu tab may not be available.
The console command is the supported development test route.

If it still says Unknown command, check that
`garrysmod/gamemodes/pillarchase2/gamemode/pc2_pills/init.lua`
exists on your computer, and check the console for `[PC2]`
registration messages and Lua errors.
