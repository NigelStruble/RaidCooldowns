-- Locale.lua - every user-facing string in one table, ready for translation.
-- To localise the addon, translate the values below; keep the %s placeholders.
local ADDON, ns = ...

local L = {}
ns.L = L

L.ADDON_TITLE = "RaidCooldowns"

-- Ability names
L.SOULSTONE = "Soulstone"
L.REBIRTH = "Rebirth"
L.DIVINE_INTERVENTION = "Divine Intervention"
L.REINCARNATION = "Reincarnation"

-- Panel rows
L.READY = "Ready"
L.REZ = "REZ"
L.SOULSTONE_ON = "Soulstone on %s"
L.SOULSTONE_CAN_REZ = "%s can use Soulstone!"
L.REBIRTH_ON = "Rebirth on %s"
L.DI_ON = "Divine Intervention on %s"
L.CAN_REINCARNATE = "%s can Reincarnate!"

-- Slash-command feedback
L.MSG_LOCKED = "frame locked."
L.MSG_UNLOCKED = "frame unlocked - drag the header to move it."
L.MSG_RESET = "frame position reset."
L.MSG_COMMANDS = "commands: /raidcd config | lock | unlock | reset | test"
L.MSG_TEST_ON = "test data injected - 4 fake raiders, cooldowns and a soulstone."
L.MSG_TEST_OFF = "test data cleared."
L.MSG_NEED_FIELDS = "a valid spell ID and cooldown are required."

-- Options panel
L.OPT_GENERAL = "General"
L.OPT_LOCK = "Lock frame"
L.OPT_LOCK_DESC = "Hide the drag handle and lock the panel in place."
L.OPT_DISPLAY = "Display style"
L.OPT_DISPLAY_BAR = "Progress bars"
L.OPT_DISPLAY_TEXT = "Text only"
L.OPT_SHOW_READY = "Show ready abilities"
L.OPT_SHOW_READY_DESC = "Show abilities that are off cooldown, not just active ones."
L.OPT_SORT = "Sort by"
L.OPT_SORT_TIME = "Time remaining"
L.OPT_SORT_NAME = "Name"
L.OPT_SORT_CLASS = "Class"
L.OPT_SYNC = "Sync with addon users"
L.OPT_SYNC_DESC = "Share and receive cooldown data with other raiders running RaidCooldowns."
L.OPT_ALERT = "Alert on Soulstone ready"
L.OPT_ALERT_DESC = "Play a sound and flash the panel when a Soulstone holder dies and can be resurrected."
L.OPT_VISIBILITY = "Show frame"
L.OPT_VIS_ALWAYS = "Always"
L.OPT_VIS_GROUP = "Only in a group"
L.OPT_VIS_RAID = "Only in a raid"
L.OPT_VIS_HIDDEN = "Never (hidden)"
L.OPT_APPEARANCE = "Appearance"
L.OPT_SCALE = "Scale"
L.OPT_WIDTH = "Bar width"
L.OPT_HEIGHT = "Bar height"
L.OPT_FONT_SIZE = "Font size"
L.OPT_FONT = "Font"
L.OPT_TEXTURE = "Bar texture"
L.OPT_ABILITIES = "Abilities"
L.OPT_SHOW_ABILITY = "Show %s on the panel."
L.OPT_CUSTOM = "Custom Abilities"
L.OPT_CUSTOM_INTRO = "Track any extra ability by spell ID - for example an item or trinket. The cooldown is in seconds."
L.OPT_NAME = "Name"
L.OPT_SPELL_ID = "Spell ID"
L.OPT_COOLDOWN = "Cooldown (sec)"
L.OPT_CLASS = "Class"
L.OPT_ANY_CLASS = "Any class"
L.OPT_ADD = "Add ability"
L.OPT_ENABLED = "Enabled"
L.OPT_REMOVE = "Remove"
L.OPT_REMOVE_CONFIRM = "Remove this custom ability?"
L.OPT_CUSTOM_DEFAULT_NAME = "Spell %s"
