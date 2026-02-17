# Roblox NPC Pathfinding + Combat State Fixes

This folder contains a cleaned-up version of your NPC AI scripts with fixes for the two issues you reported:

1. **Animations not playing consistently**
2. **NPC trying to path and attack at the same time (causing forward snapping/teleport behavior)**

## What was fixed

- Added explicit animation track priorities (`Movement` for walk/run, `Action` for attack).
- Added a safe animation transition helper so only one track is active at a time.
- Reworked path follow cancellation so old path jobs are stopped before new movement starts.
- Stopped pathing immediately when entering `ATTACK`.
- Added chase repath throttling to avoid spamming path computations every tick.
- Tightened target validity checks so dead/missing targets cleanly return to `ROAM`.

## Files

- `NPC_Controller.server.lua`
- `NPC_StateMachine.lua`
- `NPC_Pathfinder.lua`

## Important setup notes

- In ServerScriptService, make sure module names match your `require` calls exactly:
  - `require(script.Parent.NPC_Pathfinder)` expects a ModuleScript named **NPC_Pathfinder**.
- The animation IDs are placeholders from your original script. If an animation is not owned/allowed for the experience, Roblox will silently fail to play it.
