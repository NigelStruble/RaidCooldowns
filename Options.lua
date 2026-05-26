-- Options.lua - AceConfig options panel, custom abilities, slash-command entry.
local ADDON, ns = ...

local Options = {}
ns.Options = Options

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local LSM = LibStub("LibSharedMedia-3.0")
local L = ns.L

local APP = "RaidCooldowns"
local optionsTable

local function refreshDisplay()
	if ns.Display then ns.Display:Refresh() end
end

local function get(info) return ns.db.profile[info[#info]] end
local function set(info, val)
	ns.db.profile[info[#info]] = val
	refreshDisplay()
end

-- Scratch values for the "add custom ability" form (not saved).
local newCustom = { class = "" }

local CLASS_VALUES = { [""] = L.OPT_ANY_CLASS }
for token, localized in pairs(LOCALIZED_CLASS_NAMES_MALE) do
	CLASS_VALUES[token] = localized
end

local function abilityArgs()
	local args = {}
	for i, ab in ipairs(ns.Abilities.builtins) do
		args[ab.key] = {
			type = "toggle", order = i, width = "full",
			name = ab.name,
			desc = format(L.OPT_SHOW_ABILITY, ab.name),
			get = function() return ns.db.profile.abilities[ab.key] ~= false end,
			set = function(_, v)
				ns.db.profile.abilities[ab.key] = v
				refreshDisplay()
			end,
		}
	end
	return args
end

local function removeCustom(key)
	ns.db.profile.custom[key] = nil
	ns.Abilities:Rebuild()
	Options:Refresh()
end

local function customArgs()
	local args = {
		intro = {
			type = "description", order = 0, fontSize = "medium",
			name = L.OPT_CUSTOM_INTRO .. "\n",
		},
		newName = {
			type = "input", order = 1, name = L.OPT_NAME,
			get = function() return newCustom.name or "" end,
			set = function(_, v) newCustom.name = v end,
		},
		newSpell = {
			type = "input", order = 2, name = L.OPT_SPELL_ID,
			get = function() return newCustom.spellID and tostring(newCustom.spellID) or "" end,
			set = function(_, v) newCustom.spellID = tonumber(v) end,
		},
		newCD = {
			type = "input", order = 3, name = L.OPT_COOLDOWN,
			get = function() return newCustom.cooldown and tostring(newCustom.cooldown) or "" end,
			set = function(_, v) newCustom.cooldown = tonumber(v) end,
		},
		newClass = {
			type = "select", order = 4, name = L.OPT_CLASS, values = CLASS_VALUES,
			get = function() return newCustom.class or "" end,
			set = function(_, v) newCustom.class = v end,
		},
		add = {
			type = "execute", order = 5, name = L.OPT_ADD,
			func = function()
				if not newCustom.spellID or not newCustom.cooldown
					or newCustom.cooldown <= 0 then
					ns.addon:Print(L.MSG_NEED_FIELDS)
					return
				end
				local key = "custom_" .. newCustom.spellID
				ns.db.profile.custom[key] = {
					name = (newCustom.name and newCustom.name ~= "" and newCustom.name)
						or format(L.OPT_CUSTOM_DEFAULT_NAME, newCustom.spellID),
					spellID = newCustom.spellID,
					cooldown = newCustom.cooldown,
					class = (newCustom.class ~= "" and newCustom.class) or nil,
					enabled = true,
				}
				newCustom.name, newCustom.spellID, newCustom.cooldown = nil, nil, nil
				ns.Abilities:Rebuild()
				Options:Refresh()
			end,
		},
	}

	local order = 10
	for key, c in pairs(ns.db.profile.custom) do
		args[key] = {
			type = "group", order = order, inline = true, name = c.name or key,
			args = {
				enabled = {
					type = "toggle", order = 1, name = L.OPT_ENABLED,
					get = function() return c.enabled ~= false end,
					set = function(_, v) c.enabled = v; refreshDisplay() end,
				},
				cname = {
					type = "input", order = 2, name = L.OPT_NAME,
					get = function() return c.name or "" end,
					set = function(_, v) c.name = v; ns.Abilities:Rebuild(); Options:Refresh() end,
				},
				cooldown = {
					type = "input", order = 3, name = L.OPT_COOLDOWN,
					get = function() return tostring(c.cooldown or 0) end,
					set = function(_, v)
						c.cooldown = tonumber(v) or c.cooldown
						ns.Abilities:Rebuild()
					end,
				},
				remove = {
					type = "execute", order = 4, name = L.OPT_REMOVE,
					confirm = true, confirmText = L.OPT_REMOVE_CONFIRM,
					func = function() removeCustom(key) end,
				},
			},
		}
		order = order + 1
	end
	return args
end

local function buildOptions()
	return {
		type = "group", name = APP,
		args = {
			general = {
				type = "group", order = 1, name = L.OPT_GENERAL, get = get, set = set,
				args = {
					locked = {
						type = "toggle", order = 1, name = L.OPT_LOCK, desc = L.OPT_LOCK_DESC,
						set = function(_, v)
							ns.db.profile.locked = v
							if ns.Display then ns.Display:ApplyLock() end
						end,
					},
					display = {
						type = "select", order = 2, name = L.OPT_DISPLAY,
						values = { bar = L.OPT_DISPLAY_BAR, text = L.OPT_DISPLAY_TEXT },
					},
					showReady = {
						type = "toggle", order = 3,
						name = L.OPT_SHOW_READY, desc = L.OPT_SHOW_READY_DESC,
					},
					sort = {
						type = "select", order = 4, name = L.OPT_SORT,
						values = { time = L.OPT_SORT_TIME, name = L.OPT_SORT_NAME,
							class = L.OPT_SORT_CLASS },
					},
					sync = {
						type = "toggle", order = 5,
						name = L.OPT_SYNC, desc = L.OPT_SYNC_DESC,
					},
					alertSoulstone = {
						type = "toggle", order = 6,
						name = L.OPT_ALERT, desc = L.OPT_ALERT_DESC,
					},
					visibility = {
						type = "select", order = 7, name = L.OPT_VISIBILITY,
						values = {
							always = L.OPT_VIS_ALWAYS,
							group = L.OPT_VIS_GROUP,
							raid = L.OPT_VIS_RAID,
							hidden = L.OPT_VIS_HIDDEN,
						},
					},
					appearance = { type = "header", order = 10, name = L.OPT_APPEARANCE },
					scale = {
						type = "range", order = 11, name = L.OPT_SCALE,
						min = 0.5, max = 2.0, step = 0.05,
						set = function(_, v)
							ns.db.profile.scale = v
							if ns.Display then ns.Display:ApplyPosition() end
						end,
					},
					width = { type = "range", order = 12, name = L.OPT_WIDTH,
						min = 120, max = 420, step = 5 },
					height = { type = "range", order = 13, name = L.OPT_HEIGHT,
						min = 10, max = 40, step = 1 },
					fontSize = { type = "range", order = 14, name = L.OPT_FONT_SIZE,
						min = 7, max = 22, step = 1 },
					font = {
						type = "select", order = 15, name = L.OPT_FONT, width = "double",
						values = function() return LSM:HashTable("font") end,
					},
					barTexture = {
						type = "select", order = 16, name = L.OPT_TEXTURE, width = "double",
						values = function() return LSM:HashTable("statusbar") end,
					},
				},
			},
			abilities = {
				type = "group", order = 2, name = L.OPT_ABILITIES, args = abilityArgs(),
			},
			custom = {
				type = "group", order = 3, name = L.OPT_CUSTOM, args = customArgs(),
			},
		},
	}
end

function Options:Setup()
	optionsTable = buildOptions()
	local AceDBOptions = LibStub("AceDBOptions-3.0", true)
	if AceDBOptions then
		optionsTable.args.profiles = AceDBOptions:GetOptionsTable(ns.db)
		optionsTable.args.profiles.order = 9
	end
	AceConfig:RegisterOptionsTable(APP, optionsTable)
	AceConfigDialog:AddToBlizOptions(APP, APP)
	AceConfigDialog:SetDefaultSize(APP, 560, 470)
end

-- Rebuild the custom-ability list after one is added or removed.
function Options:Refresh()
	if not optionsTable then return end
	optionsTable.args.custom.args = customArgs()
	AceConfigRegistry:NotifyChange(APP)
	refreshDisplay()
end

function Options:Open()
	AceConfigDialog:Open(APP)
end
