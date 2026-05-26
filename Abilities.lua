-- Abilities.lua - built-in ability registry plus custom-ability merging.
local ADDON, ns = ...

local Abilities = {}
ns.Abilities = Abilities

local GetSpellInfo = GetSpellInfo

-- Built-in abilities. Each TBC spell has several ranks with different IDs but a
-- shared localized name and icon, so detection matches on the resolved name and
-- one representative ID per role is enough. `cooldown` is a fallback for
-- non-addon raiders seen via combat log; real values come from GetSpellCooldown
-- (self) and sync.
local builtins = {
	{
		key = "soulstone", name = ns.L.SOULSTONE, class = "WARLOCK",
		cooldown = 1800,        -- VERIFY (TBC soulstone cooldown)
		-- The cooldown starts when the soulstone item is USED (its buff lands),
		-- not when "Create Soulstone" makes the item - hence cooldownOnAura.
		auraSpellID = 20707,    -- Soulstone Resurrection (buff)
		iconSpellID = 20707,
		cooldownOnAura = true,
		tracksTarget = true,
	},
	{
		key = "rebirth", name = ns.L.REBIRTH, class = "DRUID",
		cooldown = 1200,        -- 20 minutes in TBC
		castSpellID = 20484, selfSpellID = 20484, iconSpellID = 20484,
		tracksTarget = true,
	},
	{
		key = "divineintervention", name = ns.L.DIVINE_INTERVENTION, class = "PALADIN",
		cooldown = 3600,        -- VERIFY
		castSpellID = 19752, selfSpellID = 19752,
		auraSpellID = 19753,    -- Divine Intervention (buff on the protected ally)
		iconSpellID = 19752,
		tracksTarget = true,
	},
	{
		key = "reincarnation", name = ns.L.REINCARNATION, class = "SHAMAN",
		cooldown = 3600,        -- VERIFY
		-- Other shamans are detected via the corpse->alive heuristic in
		-- Detection.lua; castSpellID is kept as a bonus path if it ever logs.
		castSpellID = 20608, selfSpellID = 20608, iconSpellID = 20608,
		tracksTarget = false,
	},
}
Abilities.builtins = builtins

local list, byKey, byCastName, byAuraName

local function resolve(def)
	def.castName = def.castSpellID and GetSpellInfo(def.castSpellID) or nil
	def.auraName = def.auraSpellID and GetSpellInfo(def.auraSpellID) or nil
	def.selfName = def.selfSpellID and GetSpellInfo(def.selfSpellID) or nil
	local _, _, icon = GetSpellInfo(def.iconSpellID or def.castSpellID
		or def.auraSpellID or 0)
	def.icon = icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

function Abilities:Initialize()
	self:Rebuild()
end

-- (Re)build the merged registry: built-ins plus the player's custom abilities.
function Abilities:Rebuild()
	list, byKey, byCastName, byAuraName = {}, {}, {}, {}

	for _, def in ipairs(builtins) do
		def.builtin = true
		resolve(def)
		list[#list + 1] = def
		byKey[def.key] = def
	end

	for key, c in pairs(ns.db.profile.custom) do
		local def = {
			key = key, name = c.name or key, class = c.class,
			cooldown = c.cooldown or 60,
			castSpellID = c.spellID, selfSpellID = c.spellID, iconSpellID = c.spellID,
			custom = true, tracksTarget = false,
		}
		resolve(def)
		list[#list + 1] = def
		byKey[key] = def
	end

	for _, def in ipairs(list) do
		if def.castName then byCastName[def.castName] = def end
		if def.auraName then byAuraName[def.auraName] = def end
	end

	ns.Fire("ABILITIES_CHANGED")
end

function Abilities:GetAll() return list end
function Abilities:Get(key) return byKey[key] end
function Abilities:GetByCastName(name) return name and byCastName[name] or nil end
function Abilities:GetByAuraName(name) return name and byAuraName[name] or nil end

function Abilities:IsEnabled(key)
	local def = byKey[key]
	if not def then return false end
	if def.custom then
		local c = ns.db.profile.custom[key]
		return c ~= nil and c.enabled ~= false
	end
	return ns.db.profile.abilities[key] ~= false
end

-- class == nil means the ability applies to any class (e.g. item-based customs).
function Abilities:AppliesTo(def, class)
	return def.class == nil or def.class == class
end
