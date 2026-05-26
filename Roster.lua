-- Roster.lua - tracks group/raid membership, classes and unit tokens.
-- New members carry no cooldown entries, so they read as "ready" by default,
-- which is the desired "assume ready on join" behaviour.
local ADDON, ns = ...

local Roster = {}
ns.Roster = Roster
LibStub("AceEvent-3.0"):Embed(Roster)

local members = {}   -- ordered list of { guid, name, class, unit, online }
local byGUID = {}
Roster.members = members
Roster.byGUID = byGUID

local function addUnit(unit)
	local guid = UnitGUID(unit)
	if not guid then return end
	local name = UnitName(unit)
	local _, class = UnitClass(unit)
	local m = byGUID[guid]
	if m then
		m.unit = unit
		m.name = name or m.name
		m.class = class or m.class
		m.online = UnitIsConnected(unit)
	else
		m = {
			guid = guid,
			name = name or UNKNOWN,
			class = class,
			unit = unit,
			online = UnitIsConnected(unit),
		}
		byGUID[guid] = m
		members[#members + 1] = m
	end
	m.seen = true
end

function Roster:Rebuild()
	for _, m in ipairs(members) do m.seen = false end

	if IsInRaid() then
		for i = 1, GetNumGroupMembers() do
			addUnit("raid" .. i)
		end
	elseif IsInGroup() then
		addUnit("player")
		for i = 1, GetNumGroupMembers() - 1 do
			addUnit("party" .. i)
		end
	else
		addUnit("player")
	end

	for i = #members, 1, -1 do
		local m = members[i]
		if not m.seen then
			byGUID[m.guid] = nil
			table.remove(members, i)
			ns.Cooldowns:ClearPlayer(m.guid)
			ns.Fire("ROSTER_MEMBER_LEFT", m.guid)
		end
	end

	ns.Fire("ROSTER_CHANGED")
end

function Roster:Initialize()
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "Rebuild")
	self:RegisterEvent("PLAYER_ENTERING_WORLD", "Rebuild")
	self:Rebuild()
end

function Roster:GetUnit(guid)
	local m = byGUID[guid]
	return m and m.unit or nil
end

function Roster:Get(guid)
	return byGUID[guid]
end

function Roster:Iterate()
	return ipairs(members)
end
