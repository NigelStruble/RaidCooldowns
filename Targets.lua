-- Targets.lua - tracks who Soulstone / Rebirth / Divine Intervention were used
-- on, plus the "can resurrect" state when a Soulstone holder dies.
local ADDON, ns = ...

local Targets = {}
ns.Targets = Targets
LibStub("AceTimer-3.0"):Embed(Targets)

-- active[key] = { abilityKey, caster, casterName, target, targetName,
--                 canRez, expires, duration, expirationTime, test }
-- keyed by caster GUID (each relevant class has only one such ability at a time).
local active = {}
Targets.active = active

local GetTime = GetTime

local function changed()
	ns.Fire("TARGETS_CHANGED")
end

-- Read a unit's buff by name; returns duration, expirationTime, or nil.
local function readAura(unit, auraName)
	if not unit or not auraName then return end
	for i = 1, 40 do
		local name, _, _, _, duration, expirationTime = UnitBuff(unit, i)
		if not name then return end
		if name == auraName then
			return duration, expirationTime
		end
	end
end

-- Rebirth-style: the target is the destination of the cast.
function Targets:OnCastTarget(ability, casterGUID, targetGUID, targetName)
	if not ability.tracksTarget or ability.auraName then return end
	if not casterGUID or not targetGUID then return end
	local m = ns.Roster:Get(casterGUID)
	active[casterGUID] = {
		abilityKey = ability.key,
		caster = casterGUID,
		casterName = m and m.name,
		target = targetGUID,
		targetName = targetName,
		expires = GetTime() + 65,  -- the resurrect prompt lapses if declined
	}
	changed()
end

-- Soulstone / Divine Intervention: the target is whoever receives the buff.
function Targets:OnAuraApplied(ability, casterGUID, targetGUID, targetName)
	if not ability.tracksTarget or not ability.auraName then return end
	if not targetGUID then return end
	local m = casterGUID and ns.Roster:Get(casterGUID)
	local entry = {
		abilityKey = ability.key,
		caster = casterGUID,
		casterName = m and m.name,
		target = targetGUID,
		targetName = targetName,
	}
	-- Capture how long the buff itself lasts, if the holder is reachable.
	local duration, expirationTime = readAura(ns.Roster:GetUnit(targetGUID), ability.auraName)
	entry.duration, entry.expirationTime = duration, expirationTime
	active[casterGUID or targetGUID] = entry
	changed()
end

-- A buff-based effect was removed. Soulstone is deliberately excluded: dying
-- clears the visible buff, and that is exactly when the stone becomes usable, so
-- the soulstone lifecycle is driven entirely by Tick instead.
function Targets:OnAuraRemoved(ability, targetGUID)
	if not ability.auraName or ability.key == "soulstone" then return end
	for k, e in pairs(active) do
		if e.abilityKey == ability.key and e.target == targetGUID then
			active[k] = nil
			changed()
		end
	end
end

function Targets:OnUnitDied(guid)
	for _, e in pairs(active) do
		if e.abilityKey == "soulstone" and e.target == guid and not e.canRez then
			e.canRez = true
			changed()
			ns.Fire("ALERT_SOULSTONE")
		end
	end
end

-- Periodic resolution of dead/alive transitions, soulstone presence and time-outs.
function Targets:Tick()
	local now = GetTime()
	local dirty = false
	local ss = ns.Abilities:Get("soulstone")
	local ssAura = ss and ss.auraName

	for k, e in pairs(active) do
		if not e.test then
			local unit = ns.Roster:GetUnit(e.target)
			if not unit then
				active[k] = nil  -- target left the group
				dirty = true
			elseif e.abilityKey == "soulstone" then
				if UnitIsDeadOrGhost(unit) then
					-- Dead: the stone is usable. The buff aura is gone now, but
					-- that must not delete the entry.
					if not e.canRez then
						e.canRez = true
						dirty = true
						ns.Fire("ALERT_SOULSTONE")
					end
				else
					-- Alive: the buff itself is the source of truth.
					local duration, expirationTime = readAura(unit, ssAura)
					if duration then
						if e.canRez then e.canRez = false; dirty = true end
						if e.expirationTime ~= expirationTime then
							e.duration, e.expirationTime = duration, expirationTime
							dirty = true
						end
					else
						active[k] = nil  -- alive with no stone: used or expired
						dirty = true
					end
				end
			elseif e.abilityKey == "rebirth" then
				if not UnitIsDeadOrGhost(unit) then
					active[k] = nil  -- target accepted the battle-res
					dirty = true
				elseif e.expires and now > e.expires then
					active[k] = nil  -- prompt declined / expired
					dirty = true
				end
			end
			-- Divine Intervention clears on SPELL_AURA_REMOVED, handled elsewhere.
		end
	end
	if dirty then changed() end
end

-- Reconstruct entries from auras already applied (e.g. after a /reload).
function Targets:ScanAuras()
	for _, ability in ipairs(ns.Abilities:GetAll()) do
		if ability.auraName then
			for _, m in ns.Roster:Iterate() do
				if m.unit then
					for i = 1, 40 do
						local name, _, _, _, _, _, source = UnitBuff(m.unit, i)
						if not name then break end
						if name == ability.auraName then
							self:OnAuraApplied(ability, source and UnitGUID(source),
								m.guid, m.name)
						end
					end
				end
			end
		end
	end
end

function Targets:OnRosterChanged()
	for k, e in pairs(active) do
		if not e.test and not ns.Roster:Get(e.target) then
			active[k] = nil
		end
	end
	self:ScanAuras()
	changed()
end

function Targets:Initialize()
	ns.On("ROSTER_CHANGED", function() Targets:OnRosterChanged() end)
	self:ScheduleRepeatingTimer("Tick", 0.5)
	self:ScanAuras()
end

function Targets:Iterate()
	return pairs(active)
end
