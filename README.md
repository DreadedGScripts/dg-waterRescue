<div align="center">

# 🌊 DG Water Rescue

### Realistic AI Maritime Rescue for FiveM

![Version](https://img.shields.io/badge/version-2.0.0-blue.svg)
![License](https://img.shields.io/badge/license-Commercial-red.svg)
![Framework](https://img.shields.io/badge/framework-QBCore%20%7C%20ESX%20%7C%20Standalone-green.svg)

**AI lifeguard extraction, beach handoff, ambulance response, CPR, and critical-condition revive**

[Overview](#-overview) • [Features](#-features) • [Installation](#-installation) • [Configuration](#%EF%B8%8F-configuration) • [Beta Program](#-beta-program)

---

</div>

## 📋 Overview

**DG Water Rescue** is a standalone-first rescue system built for realistic RP outcomes when a player dies in water.

Full sequence:
1. Player dies in water
2. Lifeguard rescue boat dispatches and extracts the player
3. Boat lands at a safer shore point
4. Ambulance team meets at the beach
5. Paramedic performs CPR
6. Player is revived in critical condition (partial health)

| Property | Value |
|----------|-------|
| **Resource Name** | `dg-waterRescue` |
| **Version** | `2.0.0` |
| **Framework Support** | QBCore, ESX, Standalone |
| **Primary Mode** | Standalone-first |
| **Bridge Integration** | Optional via [`dg-bridge`](https://github.com/DreadedGScripts/dg-bridge) |

---

## ✨ Features

- AI-only rescue responders for consistent behavior
- Water-death trigger with guarded rescue state flow
- Safe shore search with hazard avoidance bias
- Beach transfer + ambulance rendezvous
- CPR animation sequence and partial revive outcome
- Optional billing and anti-abuse cooldown controls
- Notification fallback chain:
	- `dg-notifications` → `dg-bridge` → chat fallback

---

## 📦 Installation

```cfg
ensure dg-waterRescue
```

Recommended order:

```cfg
ensure dg-bridge         # optional but recommended for compatibility/billing
ensure dg-notifications  # optional UI notifications
ensure dg-waterRescue
```

---

## ⚙️ Configuration

Edit `config.lua` to tune realism and behavior.

| Section | Purpose |
|---------|---------|
| `Config.Trigger` | Dead-in-water and manual trigger controls |
| `Config.Models` | Boat, lifeguard, paramedic, and ambulance models |
| `Config.Search` | Shore search and spawn planning |
| `Config.Navigation` | Boat/ambulance speeds and thresholds |
| `Config.TimeoutsMs` | Timeout safety for each rescue stage |
| `Config.Medical` | CPR timing and partial revive health |
| `Config.Realism` | Beach preference and hazard filtering |
| `Config.Billing` | Optional rescue charges |
| `Config.Cooldown` | Anti-spam rescue cooldown |

---

## 🧠 Trigger & Events

- Automatic trigger: `baseevents:onPlayerDied` (water deaths)
- Manual trigger (optional):

```lua
TriggerEvent('dg-waterRescue:beginRescue', coords)
```

---

## 🌐 DG Ecosystem

DG Water Rescue is designed to work cleanly with your other DG resources:

- [`dg-bridge`](https://github.com/DreadedGScripts/dg-bridge) - framework abstraction (QBCore/ESX/standalone)
- [`dg-notifications`](https://github.com/DreadedGScripts/dg-notifications) - enhanced rescue event notifications
- [`dg-adminmenu`](https://github.com/DreadedGScripts/dg-adminmenu-docs) - admin operations, reporting, and ecosystem management
- [`dg-discord`](https://github.com/DreadedGScripts/dg-discord) - Discord logging/automation support

---

## 🧪 Beta Program

### DG AdminPanel Beta Tester Call

I am actively looking for **beta tester servers** for `dg-adminmenu`.

**What I need:**
- A server with a real active player population (not empty/dev-only)
- Willingness to run and test features in real sessions
- Bug/feedback reporting during beta

**Tester reward:**
- Servers accepted into beta testing will receive the finalized `dg-adminmenu` script **for free** once release is complete.

If your server is interested, contact me with your server details and expected active player window.

---

## 🛠️ Notes

- Built for balanced realism with practical fallback behavior.
- Billing/cooldown are configurable and can be disabled.
- Partial-health revive is intentional for medical RP continuity.
