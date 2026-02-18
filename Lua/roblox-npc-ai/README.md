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


## Additional stability changes

- Server network ownership enforced for NPC roots (`SetNetworkOwner(nil)`) to reduce client-side jolt/teleport effects during aggro/chase.
- Chase repath now has both time and distance gates so NPCs do not constantly restart paths every frame.
- Roam now includes stuck detection to reset a bad roam target if the NPC stops making progress.

- Roam target selection now tries several candidates and prefers path-reachable points to reduce wall-running/stuck behavior.
- Chase speed is now capped (`MaxChaseSpeed`) and smoothed to prevent instant acceleration spikes that can look like lag/teleporting.
- Waypoint traversal uses timeouts and skips near-zero first waypoints to reduce jitter at repath boundaries.

## Latest behavior tuning

- Added a dedicated **Idle** animation state during roaming pauses so NPCs pause and look less robotic between roam points.
- Added roam pause windows and state-entry hooks to prevent ROAM/CHASE behavior overlap and improve movement smoothness.
- Attack damage timing is now synchronized with animation via `AttackHitDelay` so the hit lands when the swing appears to connect.
- Reduced chase speed spikes with lower default alert multiplier and hard cap (`MaxChaseSpeed`).
