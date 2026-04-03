# dg-waterRescue

Realistic AI water rescue for FiveM. If a player dies in water, a lifeguard boat extracts them, lands at a safer shore point, hands off to an ambulance team, performs CPR, and revives the player in a critical condition.

## Highlights
- Standalone-first design (works without framework)
- Optional ESX/QBCore support through `dg-bridge`
- AI-only responders (lifeguard boat + ambulance + paramedic)
- Safe-shore search with hazard avoidance bias
- CPR sequence with partial revive outcome
- Optional rescue billing and cooldown controls

## Resource Structure
- `config.lua` - all settings
- `client/utils.lua` - shared client helpers
- `client/framework.lua` - revive/notification bridge layer
- `client/routing.lua` - safe shore selection
- `client/rescue.lua` - state-machine rescue flow
- `client/main.lua` - event entry points
- `server/main.lua` - cooldown tracking and optional billing

## Installation
1. Place `dg-waterRescue` in your resources folder.
2. Add `ensure dg-waterRescue` to your server config.
3. Optional: ensure `dg-bridge` for framework billing/notify integration.

## Trigger Behavior
- Default trigger: `baseevents:onPlayerDied` + dead in water check.
- Optional manual trigger event: `dg-waterRescue:beginRescue`.

## Key Config Areas
- `Config.Trigger` - trigger gates
- `Config.Models` - boat/ped/ambulance models
- `Config.Search` - shoreline and spawn search behavior
- `Config.Navigation` - movement speeds and thresholds
- `Config.TimeoutsMs` - rescue stage timeouts
- `Config.Medical` - CPR and partial revive health
- `Config.Realism` - beach preference and hazard scans
- `Config.Billing` - rescue charges
- `Config.Cooldown` - anti-abuse cooldown

## Notes
- This version revives to partial health for realism.
- Billing/cooldown are configurable and can be disabled.
