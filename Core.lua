-- Core.lua - addon bootstrap, shared namespace, lifecycle, slash commands.
local ADDON, ns = ...

--------------------------------------------------------------------------------
-- Internal event bus. Modules react to state changes without referencing each
-- other directly, which keeps load order and dependencies simple.
--------------------------------------------------------------------------------
ns.callbacks = {}

function ns.On(event, fn)
	local list = ns.callbacks[event]
	if not list then
		list = {}
		ns.callbacks[event] = list
	end
	list[#list + 1] = fn
end

function ns.Fire(event, ...)
	local list = ns.callbacks[event]
	if not list then return end
	for i = 1, #list do
		list[i](...)
	end
end

function ns.Debug(...)
	if ns.db and ns.db.profile.debug then
		print("|cff66ccffRaidCD|r", ...)
	end
end

--------------------------------------------------------------------------------
-- Addon object
--------------------------------------------------------------------------------
local RC = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0")
ns.addon = RC
RC.ns = ns

local defaults = {
	profile = {
		debug = false,
		locked = false,
		scale = 1.0,
		sort = "time",          -- "time" | "class" | "name"
		display = "bar",        -- "bar" | "text"
		showReady = true,       -- show abilities that are off cooldown
		sync = true,
		alertSoulstone = true,  -- sound + flash when a Soulstone becomes usable
		visibility = "always",  -- "always" | "group" | "raid" | "hidden"
		barTexture = "Blizzard",
		font = "Friz Quadrata TT",
		fontSize = 11,
		width = 230,
		height = 18,
		spacing = 2,
		point = { "TOP", 0, -240 },
		abilities = { ["*"] = true },   -- per built-in ability key: shown?
		custom = {},                    -- custom ability defs, keyed by key
	},
}

-- Modules are initialised in dependency order once the game is ready.
local MODULE_ORDER = {
	"Abilities", "Cooldowns", "Roster", "Targets", "Detection", "Sync", "Display",
}

function RC:OnInitialize()
	self.db = LibStub("AceDB-3.0"):New("RaidCooldownsDB", defaults, true)
	ns.db = self.db

	self:RegisterChatCommand("raidcd", "OnSlash")
	self:RegisterChatCommand("rcd", "OnSlash")
end

function RC:OnEnable()
	for _, name in ipairs(MODULE_ORDER) do
		local m = ns[name]
		if m and m.Initialize then
			m:Initialize()
		end
	end
	-- Options last: its panel lists abilities, so the registry must exist first.
	if ns.Options then
		ns.Options:Setup()
	end
	ns.Fire("ENABLED")
	ns.Debug("enabled")
end

function RC:OnSlash(input)
	local cmd = strtrim(input or ""):lower():match("^(%S*)")
	local L = ns.L

	if cmd == "lock" then
		ns.db.profile.locked = true
		if ns.Display then ns.Display:ApplyLock() end
		self:Print(L.MSG_LOCKED)
	elseif cmd == "unlock" then
		ns.db.profile.locked = false
		if ns.Display then ns.Display:ApplyLock() end
		self:Print(L.MSG_UNLOCKED)
	elseif cmd == "test" then
		if ns.Detection and ns.Detection.RunTest then ns.Detection:RunTest() end
	elseif cmd == "reset" then
		ns.db.profile.point = { "TOP", 0, -240 }
		ns.db.profile.scale = 1.0
		if ns.Display then ns.Display:ApplyPosition() end
		self:Print(L.MSG_RESET)
	elseif cmd == "config" or cmd == "" then
		if ns.Options then ns.Options:Open() end
	else
		self:Print(L.MSG_COMMANDS)
	end
end
