# RaidCooldowns

A World of Warcraft (Burning Crusade Classic — TBC Anniversary, interface 2.5.5)
addon that tracks the wipe-recovery cooldowns your raid relies on, and shows
them in a single, sortable panel.

## What it tracks

- **Soulstone** (Warlock) — including which player currently has it, and a
  highlighted alert when a held Soulstone becomes usable to rez.
- **Rebirth** (Druid) — and which dead raid member it can be cast on.
- **Divine Intervention** (Paladin) — including the active DI buff and the
  target it's on.
- **Reincarnation** (Shaman) — including a "can rez" callout when a dead
  Shaman's Reincarnation is off cooldown.

Cooldown state is shared between raid members running the addon (via
AceComm), so you don't need every player on it for the panel to be accurate.

## Features

- Bar mode or text-only mode for each row.
- Sort by remaining time, class, or name.
- Class-coloured names and bars; ready abilities show in green; dead players
  are hidden unless they can self-rez right now.
- Optional sound + flash alert when a Soulstone becomes usable.
- Visibility filter: always shown, in any group, in a raid, or hidden.
- Configurable bar texture and font via LibSharedMedia.
- Movable, scalable, lockable frame.
- AceDB profiles.

## Installation

1. Download or clone this repo.
2. Drop the `RaidCooldowns` folder into your
   `World of Warcraft\_classic_\Interface\AddOns\` directory.
3. Make sure the folder is named exactly `RaidCooldowns` (it must match the
   `.toc` filename).
4. Restart the game client, or run `/reload` if it's already running.

The addon embeds Ace3, LibStub, and LibSharedMedia, so no separate library
installs are required.

## Slash commands

| Command           | Effect                                              |
| ----------------- | --------------------------------------------------- |
| `/rcd` or `/raidcd` | Open the configuration panel.                     |
| `/rcd lock`       | Lock the frame (hides the drag header).             |
| `/rcd unlock`     | Unlock the frame so it can be moved.                |
| `/rcd test`       | Populate the panel with test data.                  |
| `/rcd reset`      | Reset the frame's position and scale.               |

Right-clicking the header also opens the config panel.

## License

[MIT](LICENSE) © 2026 Nigel Struble
