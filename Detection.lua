-- Detection.lua - learns cooldowns from the combat log (other raiders) and from
-- GetSpellCooldown (the local player), and routes target events to Targets.
local ADDON, ns = ...

local Detection = {}
ns.Detection = Detection
LibStub("AceEvent-3.0"):Embed(Detection)
LibStub("AceTimer-3.0"):Embed(Detection)

local GetSpellCooldown = GetSpellCooldown
local GetTime = GetTime
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo

local playerGUID

-- Reincarnation has no reliable combat-log event, so other shamans are detected
-- by watching for a corpse -> alive transition that no resurrection explains.
local lifeState = {}   -- guid -> "ALIVE" | "DEAD" | "GHOST"
local recentRez = {}   -- guid -> time() a rez was cast on / soulstone consumed
local REZ_WINDOW = 65  -- seconds; a resurrection prompt lasts ~60s

local function syncEnabled()
	return ns.db.profile.sync and ns.Sync ~= nil
end

function Detection:OnCast(ability, sourceGUID, destGUID, destName, castEpoch)
	if not ns.Roster:Get(sourceGUID) then return end  -- only track group members

	if sourceGUID ~= playerGUID then
		-- Another raider: infer the cooldown from the combat log.
		if ns.Cooldowns:StartCooldown(sourceGUID, ability.key, ability.cooldown,
			"observed", castEpoch, 0) then
			if syncEnabled() then
				ns.Sync:RelayObserved(sourceGUID, ability.key, ability.cooldown, castEpoch)
			end
		end
	end

	-- Rebirth-style abilities take their target from the cast destination.
	if ability.tracksTarget and not ability.auraName then
		ns.Targets:OnCastTarget(ability, sourceGUID, destGUID, destName)
	end
end

-- Soulstone: the cooldown begins when the stone is used (its buff is applied).
function Detection:OnAuraCooldown(ability, sourceGUID, castEpoch)
	if not sourceGUID or not ns.Roster:Get(sourceGUID) then return end
	if sourceGUID == playerGUID then
		if ns.Cooldowns:StartCooldown(sourceGUID, ability.key, ability.cooldown,
			"self", nil, 0) then
			if syncEnabled() then
				ns.Sync:BroadcastOwn(ability.key, ability.cooldown, 0)
			end
		end
	else
		if ns.Cooldowns:StartCooldown(sourceGUID, ability.key, ability.cooldown,
			"observed", castEpoch, 0) then
			if syncEnabled() then
				ns.Sync:RelayObserved(sourceGUID, ability.key, ability.cooldown, castEpoch)
			end
		end
	end
end

function Detection:OnCombatLog()
	local timestamp, subevent, _, sourceGUID, _, _, _,
		destGUID, destName, _, _, _, spellName = CombatLogGetCurrentEventInfo()

	if subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_RESURRECT" then
		if subevent == "SPELL_RESURRECT" and destGUID then
			recentRez[destGUID] = time()  -- a resurrection was cast on this unit
		end
		local ability = ns.Abilities:GetByCastName(spellName)
		if ability and sourceGUID then
			self:OnCast(ability, sourceGUID, destGUID, destName, timestamp)
		end
	elseif subevent == "SPELL_AURA_APPLIED" or subevent == "SPELL_AURA_REFRESH" then
		local ability = ns.Abilities:GetByAuraName(spellName)
		if ability then
			ns.Targets:OnAuraApplied(ability, sourceGUID, destGUID, destName)
			if subevent == "SPELL_AURA_APPLIED" and ability.cooldownOnAura then
				self:OnAuraCooldown(ability, sourceGUID, timestamp)
			end
		end
	elseif subevent == "SPELL_AURA_REMOVED" then
		local ability = ns.Abilities:GetByAuraName(spellName)
		if ability then
			if ability.key == "soulstone" and destGUID then
				recentRez[destGUID] = time()  -- soulstone consumed or expired
			end
			ns.Targets:OnAuraRemoved(ability, destGUID)
		end
	elseif subevent == "UNIT_DIED" then
		ns.Targets:OnUnitDied(destGUID)
	end
end

-- GetSpellCooldown is exact for the local player, so this data is authoritative.
function Detection:ScanSelf()
	local _, class = UnitClass("player")
	for _, ability in ipairs(ns.Abilities:GetAll()) do
		if ability.selfName and ns.Abilities:AppliesTo(ability, class) then
			local start, duration = GetSpellCooldown(ability.selfName)
			if start and start > 0 and duration and duration > 3 then
				local elapsed = GetTime() - start
				if ns.Cooldowns:StartCooldown(playerGUID, ability.key, duration,
					"self", nil, elapsed) then
					if syncEnabled() then
						ns.Sync:BroadcastOwn(ability.key, duration, elapsed)
					end
				end
			elseif ns.Cooldowns:GetRemaining(playerGUID, ability.key) > 0 then
				-- The store still shows a cooldown the game has cleared (early reset).
				ns.Cooldowns:SetReady(playerGUID, ability.key)
				if syncEnabled() then
					ns.Sync:BroadcastReady(ability.key)
				end
			end
		end
	end
end

local function lifeOf(unit)
	if not UnitIsDeadOrGhost(unit) then return "ALIVE" end
	if UnitIsGhost(unit) then return "GHOST" end
	return "DEAD"
end

-- A shaman going straight from corpse to alive, with no resurrection to explain
-- it, has used Reincarnation. Releasing to a ghost first rules it out, as does a
-- recent rez or a consumed soulstone. We also require the shaman to be visible:
-- out of range the combat log never delivers the resurrection cast on them, so a
-- corpse -> alive jump there could be a different res we simply never saw. Fires
-- LIFESTATE_CHANGED on any transition so the display can refresh the dead-shaman
-- highlight.
function Detection:CheckReincarnation()
	local reinc = ns.Abilities:Get("reincarnation")
	if not reinc then return end
	for _, m in ns.Roster:Iterate() do
		if m.class == "SHAMAN" and m.unit and UnitExists(m.unit) then
			local cur = lifeOf(m.unit)
			local prev = lifeState[m.guid]
			if prev ~= cur then
				if prev == "DEAD" and cur == "ALIVE" and m.guid ~= playerGUID then
					local rez = recentRez[m.guid]
					local recentlyRezzed = rez and (time() - rez) <= REZ_WINDOW
					if not recentlyRezzed and UnitIsVisible(m.unit) then
						if ns.Cooldowns:StartCooldown(m.guid, "reincarnation",
							reinc.cooldown, "observed", time(), 0) then
							if syncEnabled() then
								ns.Sync:RelayObserved(m.guid, "reincarnation",
									reinc.cooldown, time())
							end
						end
					end
				end
				lifeState[m.guid] = cur
				ns.Fire("LIFESTATE_CHANGED")
			end
		end
	end
end

function Detection:Initialize()
	playerGUID = UnitGUID("player")
	self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnCombatLog")
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "ScanSelf")
	self:ScheduleTimer("ScanSelf", 2)  -- catch a cooldown already running at load
	self:ScheduleRepeatingTimer("CheckReincarnation", 1)
	ns.On("ROSTER_MEMBER_LEFT", function(guid)
		lifeState[guid] = nil
		recentRez[guid] = nil
	end)
end

-- /raidcd test - inject fake raiders so the UI can be checked solo; run again to
-- clear them.
function Detection:RunTest()
	if self.testActive then
		self:ClearTest()
		return
	end
	self.testActive = true
	local classes = { "WARLOCK", "DRUID", "PALADIN", "SHAMAN" }
	for i, class in ipairs(classes) do
		local guid = "RCTest" .. i
		local name = "Test" .. class:sub(1, 1) .. class:sub(2):lower()
		if not ns.Roster.byGUID[guid] then
			local m = { guid = guid, name = name, class = class, online = true, test = true }
			ns.Roster.byGUID[guid] = m
			ns.Roster.members[#ns.Roster.members + 1] = m
		end
		for _, ability in ipairs(ns.Abilities:GetAll()) do
			-- Leave the shaman's Reincarnation ready and mark them dead, so the
			-- "can Reincarnate" highlight shows up in the test.
			if ability.class == class and ability.key ~= "reincarnation" then
				ns.Cooldowns:StartCooldown(guid, ability.key, 15 + i * 35,
					"observed", time(), 0)
			end
		end
	end
	local shaman = ns.Roster.byGUID["RCTest4"]
	if shaman then shaman.testDead = true end
	if ns.Abilities:Get("soulstone") then
		ns.Targets.active["RCTest1"] = {
			abilityKey = "soulstone", caster = "RCTest1", casterName = "TestWarlock",
			target = "RCTest2", targetName = "TestDruid", canRez = true, test = true,
		}
	end
	ns.Fire("ROSTER_CHANGED")
	ns.Fire("TARGETS_CHANGED")
	ns.addon:Print(ns.L.MSG_TEST_ON)
end

function Detection:ClearTest()
	self.testActive = false
	for i = 1, 4 do
		local guid = "RCTest" .. i
		if ns.Roster.byGUID[guid] then
			ns.Roster.byGUID[guid] = nil
			ns.Cooldowns:ClearPlayer(guid)
		end
		ns.Targets.active[guid] = nil
	end
	for i = #ns.Roster.members, 1, -1 do
		if ns.Roster.members[i].test then
			table.remove(ns.Roster.members, i)
		end
	end
	ns.Fire("ROSTER_CHANGED")
	ns.Fire("TARGETS_CHANGED")
	ns.addon:Print(ns.L.MSG_TEST_OFF)
end
