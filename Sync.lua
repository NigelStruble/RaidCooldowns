-- Sync.lua - shares cooldown state between raiders running the addon.
-- Two tiers travel over addon messages: authoritative "owner" data (a player's
-- own GetSpellCooldown) and lower-confidence "observed" data (first-hand
-- combat-log sightings). Received data is never re-broadcast, keeping relay to
-- one hop; the receiver's dedup (Cooldowns.lua) collapses duplicates.
local ADDON, ns = ...

local Sync = {}
ns.Sync = Sync
LibStub("AceComm-3.0"):Embed(Sync)
LibStub("AceEvent-3.0"):Embed(Sync)
LibStub("AceTimer-3.0"):Embed(Sync)
local AceSerializer = LibStub("AceSerializer-3.0")

local PREFIX = "RaidCD"
local PROTOCOL = 1   -- message-format version; lets future builds detect older peers
local GetTime = GetTime
local playerGUID

local function channel()
	if IsInRaid() then return "RAID" end
	if IsInGroup() then return "PARTY" end
	return nil
end

local function send(msg)
	if not ns.db.profile.sync then return end
	local ch = channel()
	if not ch then return end
	msg.v = PROTOCOL
	Sync:SendCommMessage(PREFIX, AceSerializer:Serialize(msg), ch)
end

-- The local player's own cooldown: authoritative "owner" data.
function Sync:BroadcastOwn(key, duration, elapsed)
	send({ t = "CD", tier = "owner", g = playerGUID, k = key, d = duration, e = elapsed })
end

function Sync:BroadcastReady(key)
	send({ t = "RDY", g = playerGUID, k = key })
end

-- A first-hand combat-log sighting of another raider: lower-confidence "observed"
-- data. Only ever called for casts seen locally, which is what keeps relay to a
-- single hop.
function Sync:RelayObserved(guid, key, duration, castEpoch)
	send({ t = "CD", tier = "observed", g = guid, k = key, d = duration, ce = castEpoch })
end

function Sync:RequestState()
	send({ t = "REQ" })
end

-- Answer a REQ with everything we know, so a joiner gets full raid coverage.
function Sync:DumpState()
	for guid, abilities in pairs(ns.Cooldowns.state) do
		for key, e in pairs(abilities) do
			local remaining = e.start + e.duration - GetTime()
			if remaining > 0 then
				local elapsed = e.duration - remaining
				if guid == playerGUID and e.source == "self" then
					send({ t = "CD", tier = "owner", g = guid, k = key,
						d = e.duration, e = elapsed })
				else
					send({ t = "CD", tier = "observed", g = guid, k = key,
						d = e.duration, ce = e.castEpoch, e = elapsed })
				end
			end
		end
	end
end

function Sync:OnComm(prefix, text, distribution, sender)
	if prefix ~= PREFIX or not ns.db.profile.sync then return end
	local ok, msg = AceSerializer:Deserialize(text)
	if not ok or type(msg) ~= "table" then return end

	if msg.t == "CD" then
		local source = (msg.tier == "owner") and "owner-sync" or "observed"
		local elapsed = msg.e
		if not elapsed and msg.ce then
			elapsed = time() - msg.ce
		end
		ns.Cooldowns:StartCooldown(msg.g, msg.k, msg.d, source, msg.ce, elapsed or 0)
	elseif msg.t == "RDY" then
		ns.Cooldowns:SetReady(msg.g, msg.k)
	elseif msg.t == "REQ" then
		self:DumpState()
	end
end

function Sync:OnGroupChanged()
	local inGroup = IsInGroup()
	if inGroup and not self.wasGrouped then
		self:ScheduleTimer("RequestState", 2)  -- newly grouped: ask for current state
	end
	self.wasGrouped = inGroup
end

function Sync:Initialize()
	playerGUID = UnitGUID("player")
	self:RegisterComm(PREFIX, "OnComm")
	self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupChanged")
	self.wasGrouped = IsInGroup()
	if self.wasGrouped then
		self:ScheduleTimer("RequestState", 3)
	end
end
