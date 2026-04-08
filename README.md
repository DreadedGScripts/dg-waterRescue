<div align="center">

# 🌊 DG Water Rescue

### Realistic AI Maritime Rescue for FiveM

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Framework](https://img.shields.io/badge/framework-QBCore%20%7C%20Qbox%20%7C%20ESX%20%7C%20Standalone-blue.svg)

**AI lifeguard extraction, EMS-first dispatch, beach handoff, CPR, and critical-condition revive**

[Overview](#-overview) • [Features](#-features) • [Installation](#-installation) • [Configuration](#%EF%B8%8F-configuration) • [Events](#-trigger--events) • [Ecosystem](#-dg-ecosystem)

---

</div>

## 📋 Overview

**DG Water Rescue** is a free, standalone-first rescue system for FiveM that creates a realistic RP experience when a player goes down in water.

Full sequence:
1. Player dies in water → rescue is automatically triggered
2. AI lifeguard boat dispatches and drives to the player
3. Player is warped into the boat, boat beaches on shore
4. **EMS-first dispatch** — if real EMS are online (QBCore), they are notified with a blip; otherwise an AI ambulance responds
5. AI ambulance driver + treatment paramedic arrive at the beach
6. Paramedic carries the patient to the rear of the ambulance and performs CPR
7. Player is revived in critical condition (partial health)

| Property | Value |
|----------|-------|
| **Resource Name** | `dg-waterRescue` |
| **Version** | `2.0.0` |
| **License** | MIT (Free) |
| **Framework Support** | QBCore, Qbox, ESX, Standalone |
| **Primary Mode** | Standalone-first |
| **Bridge Integration** | Optional via [`dg-bridge`](https://github.com/DreadedGScripts/dg-bridge) |
| **Notification system** | Optional via [`dg-notifications`] (https://github.com/DreadedGScripts/dg-notifications) |

---

## ✨ Features

- **AI lifeguard boat** dispatches automatically on water death, always runs regardless of EMS status
- **EMS-first dispatch system** — checks for online QBCore EMS before spawning AI ambulance
  - Real EMS online: they receive a dispatch notification + timed rescue blip with route
  - No EMS online: AI ambulance with driver and treatment paramedic responds automatically
- **Two-paramedic ambulance crew** — driver navigates while the treatment paramedic handles the patient
- **Carry sequence** — paramedic walks the patient to the rear of the ambulance before CPR
- **CPR animation** at the ambulance rear with animation fallback
- **Partial-health revive** — player wakes up in critical condition for continued medical RP
- **Safe shore search** with hazard avoidance and beach zone preference
- **Side-of-boat handoff** — player exits to the side of the beached boat, not on top of it
- Optional billing and anti-abuse cooldown
- Notification fallback chain: `dg-notifications` → `QBCore` → `dg-bridge` → chat

---

## 📦 Installation

1. Drop `dg-waterRescue` into your resources folder
2. Add to your `server.cfg`:

```cfg
ensure dg-waterRescue
```

Recommended load order with optional integrations:

```cfg
ensure dg-bridge         # optional — framework abstraction & billing
ensure dg-notifications  # optional — enhanced UI notifications
ensure dg-waterRescue
```

---

## ⚙️ Configuration

All behavior is tunable in `config.lua`. No code changes required.

| Section | Purpose |
|---------|---------|
| `Config.Trigger` | Dead-in-water detection and manual trigger controls |
| `Config.Models` | Boat, lifeguard, paramedic, and ambulance models |
| `Config.Search` | Shore search radius, spawn offsets, and beach targeting |
| `Config.Navigation` | Boat/ambulance speeds and arrival thresholds |
| `Config.TimeoutsMs` | Per-stage timeout safety values |
| `Config.Medical` | CPR duration and partial revive health value |
| `Config.Realism` | Beach zone preference and hazard object filtering |
| `Config.Billing` | Optional rescue charge (requires `dg-bridge`) |
| `Config.Cooldown` | Anti-spam rescue cooldown |
| `Config.Dispatch` | EMS-first dispatch, QBCore job name, blip settings |

---

## 🧠 Trigger & Events

**Automatic trigger** — fires on `baseevents:onPlayerDied` when the player dies in water.

**Manual trigger:**
```lua
TriggerEvent('dg-waterRescue:beginRescue', vector3(x, y, z))
```

**EMS dispatch events (server → client):**
```lua
-- Sent to victim: AI ambulance or real EMS path
TriggerClientEvent('dg-waterRescue:client:dispatchDecision', src, { useAI = true, useAiAmbulance = false })

-- Sent to online EMS players: dispatch notification
TriggerClientEvent('dg-waterRescue:client:emsRescueAlert', emsId, coords)
```

---

## 🌐 DG Ecosystem

DG Water Rescue is part of the free DG Scripts ecosystem:

- [`dg-bridge`](https://github.com/DreadedGScripts/dg-bridge) — framework abstraction (QBCore / ESX / standalone billing, notifications, revive)
- [`dg-notifications`](https://github.com/DreadedGScripts/dg-notifications) — enhanced EMS-styled rescue notifications
- [`dg-adminmenu`](https://github.com/DreadedGScripts/dg-adminmenu-docs) — admin panel with reporting and server management tools
- [`dg-discord`](https://github.com/DreadedGScripts/dg-discord) — Discord bot integration for logging and automation

---

## 💬 Support & Contact

For questions, bug reports, or suggestions, join our Discord:

**[Dreaded Scripts Discord](https://discord.gg/ZNJ7tJ26Sn)**

You can also reach out directly to the author: `DrahMah`

## 🧪 Beta Testing

Interested in beta testing new features or preview builds for DG Water Rescue?

See the public documentation for details and sign-up instructions:

**[DG AdminMenu Docs & Beta Info](https://github.com/DreadedGScripts/dg-adminmenu-docs)**

_Note: Beta access and info is managed via the docs link above._
