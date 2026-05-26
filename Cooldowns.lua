-- Cooldowns.lua - central per-player / per-ability cooldown state store.
-- Times are kept in GetTime() space for smooth display; persistence converts
-- to wall-clock epoch (see Detection/Phase 9).
local ADDON, ns = ...

local Cooldowns = {}
ns.Cooldowns = Cooldowns
LibStub("AceEvent-3.0"):Embed(Cooldowns)

local GetTime = GetTime

-- state[guid][abilityKey] = { start, duration, source, castEpoch }
local state = {}
Cooldowns.state = state

-- "self" and "owner-sync" are owner-authoritative; "observed" is inferred from
-- the combat log (locally or relayed) and ranks below them.
local function rank(source)
	return source == "observed" and 1 or 2
end

local function isExpired(e)
	return (e.start + e.duration) <= GetTime()
end

-- Persist active cooldowns as wall-clock epochs so they survive /reload and relog.
function Cooldowns:Save()
	local cache = {}
	local now, epochNow = GetTime(), time()
	for guid, abilities in pairs(state) do
		for key, e in pairs(abilities) do
			local remaining = e.start + e.duration - now
			if remaining > 0 then
				cache[#cache + 1] = {
					g = guid, k = key, dur = e.duration,
					expiry = epochNow + remaining, src = e.source,
				}
			end
		end
	end
	ns.db.global.cooldownCache = cache
end

function Cooldowns:LoadCache()
	local cache = ns.db.global.cooldownCache
	ns.db.global.cooldownCache = nil
	if type(cache) ~= "table" then return end
	local epochNow = time()
	for _, c in ipairs(cache) do
		local remaining = (c.expiry or 0) - epochNow
		if remaining > 0 and c.dur and c.dur > 0 then
			self:StartCooldown(c.g, c.k, c.dur, c.src or "observed", nil, c.dur - remaining)
		end
	end
end

function Cooldowns:Initialize()
	wipe(state)
	self:LoadCache()
	self:RegisterEvent("PLAYER_LOGOUT", "Save")
end

-- Record a cooldown. `elapsed` is how many seconds have already passed since it
-- started (0 for a fresh local sighting, >0 for sync data describing a cooldown
-- that began on another client). Returns true if the stored state changed.
function Cooldowns:StartCooldown(guid, key, duration, source, castEpoch, elapsed)
	if not guid or not key then return false end
	if not duration or duration <= 0 then return false end
	elapsed = elapsed or 0
	if elapsed >= duration then return false end -- already over; nothing to show
	source = source or "observed"

	local players = state[guid]
	if not players then
		players = {}
		state[guid] = players
	end

	local newStart = GetTime() - elapsed
	local existing = players[key]
	if existing and not isExpired(existing) then
		local er, nr = rank(existing.source), rank(source)
		if er > nr then
			-- existing is owner-authoritative, incoming is only observed: ignore.
			return false
		elseif er == nr then
			-- both observed: earliest sighting wins, so duplicate reports of one
			-- cast collapse together regardless of arrival order.
			if nr == 1 and existing.castEpoch and castEpoch
				and castEpoch >= existing.castEpoch then
				return false
			end
			-- same tier and timing: a refresh with nothing new to store.
			if existing.duration == duration
				and math.abs(existing.start - newStart) < 1.5 then
				return false
			end
		end
	end

	players[key] = {
		start = newStart,
		duration = duration,
		source = source,
		castEpoch = castEpoch,
	}
	ns.Fire("COOLDOWN_CHANGED", guid, key)
	return true
end

-- Owner-authoritative report that an ability is off cooldown.
function Cooldowns:SetReady(guid, key)
	local players = state[guid]
	if players and players[key] then
		players[key] = nil
		ns.Fire("COOLDOWN_CHANGED", guid, key)
	end
end

function Cooldowns:Get(guid, key)
	local players = state[guid]
	return players and players[key] or nil
end

function Cooldowns:GetRemaining(guid, key)
	local e = self:Get(guid, key)
	if not e then return 0 end
	local r = e.start + e.duration - GetTime()
	return r > 0 and r or 0
end

function Cooldowns:IsReady(guid, key)
	return self:GetRemaining(guid, key) <= 0
end

function Cooldowns:ClearPlayer(guid)
	if state[guid] then
		state[guid] = nil
		ns.Fire("COOLDOWN_CHANGED", guid, nil)
	end
end
