-- Display.lua - the on-screen cooldown panel: rows, bars, text mode, layout.
local ADDON, ns = ...

local Display = {}
ns.Display = Display
LibStub("AceTimer-3.0"):Embed(Display)

local LSM = LibStub("LibSharedMedia-3.0")

local DEFAULT_FONT = STANDARD_TEXT_FONT
local DEFAULT_BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local GREY = { r = 0.7, g = 0.7, b = 0.7 }
local ABILITY_TAG = "|cffbfbfbf"   -- grey, for the ability name next to a player

local function fmtTime(s)
	s = math.floor(s + 0.5)
	if s >= 3600 then
		return string.format("%d:%02d:%02d", math.floor(s / 3600),
			math.floor((s % 3600) / 60), s % 60)
	elseif s >= 60 then
		return string.format("%d:%02d", math.floor(s / 60), s % 60)
	end
	return s .. "s"
end

local function classColor(class)
	return (class and RAID_CLASS_COLORS[class]) or GREY
end

local function targetText(e)
	local who = e.targetName or "?"
	if e.abilityKey == "soulstone" then
		return e.canRez and format(ns.L.SOULSTONE_CAN_REZ, who)
			or format(ns.L.SOULSTONE_ON, who)
	elseif e.abilityKey == "rebirth" then
		return format(ns.L.REBIRTH_ON, who)
	elseif e.abilityKey == "divineintervention" then
		return format(ns.L.DI_ON, who)
	end
	return who
end

-- A test member carries an explicit flag; a real one is checked via the API.
local function isDeadCorpse(m)
	if m.test then return m.testDead == true end
	if not m.unit then return false end
	return (UnitIsDeadOrGhost(m.unit) and not UnitIsGhost(m.unit)) and true or false
end

local function buildItems()
	local items = {}
	for _, e in ns.Targets:Iterate() do
		if ns.Abilities:IsEnabled(e.abilityKey) then
			items[#items + 1] = { kind = "target", entry = e }
		end
	end
	local showReady = ns.db.profile.showReady
	for _, m in ns.Roster:Iterate() do
		local dead = isDeadCorpse(m)
		for _, ability in ipairs(ns.Abilities:GetAll()) do
			if ns.Abilities:IsEnabled(ability.key)
				and ns.Abilities:AppliesTo(ability, m.class) then
				local remaining = ns.Cooldowns:GetRemaining(m.guid, ability.key)
				-- A dead shaman whose Reincarnation is ready can self-rez now.
				local canSelfRez = ability.key == "reincarnation"
					and remaining <= 0 and dead
				-- Hide dead members; the only exception is a row that lets
				-- them rez themselves right now.
				if (not dead or canSelfRez)
					and (remaining > 0 or canSelfRez or showReady) then
					items[#items + 1] = {
						kind = "cooldown", member = m, ability = ability,
						remaining = remaining, canSelfRez = canSelfRez,
					}
				end
			end
		end
	end
	return items
end

-- 0 = act now (can be resurrected), 1 = other target rows, 2 = plain cooldowns.
local function urgency(item)
	if item.kind == "target" then
		return item.entry.canRez and 0 or 1
	end
	return item.canSelfRez and 0 or 2
end

local function sortItems(items)
	local mode = ns.db.profile.sort
	table.sort(items, function(a, b)
		local ua, ub = urgency(a), urgency(b)
		if ua ~= ub then return ua < ub end
		if a.kind ~= b.kind then return a.kind == "target" end
		if a.kind == "target" then
			return (a.entry.targetName or "") < (b.entry.targetName or "")
		end
		if mode == "name" then
			return (a.member.name or "") < (b.member.name or "")
		elseif mode == "class" then
			if (a.member.class or "") ~= (b.member.class or "") then
				return (a.member.class or "") < (b.member.class or "")
			end
			return (a.member.name or "") < (b.member.name or "")
		end
		local aOn, bOn = a.remaining > 0, b.remaining > 0
		if aOn ~= bOn then return aOn end
		if aOn then return a.remaining < b.remaining end
		return (a.member.name or "") < (b.member.name or "")
	end)
end

function Display:CreateFrames()
	local p = ns.db.profile
	local f = CreateFrame("Frame", "RaidCooldownsFrame", UIParent)
	f:SetSize(p.width, 16)
	f:SetFrameStrata("MEDIUM")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(false)
	local fbg = f:CreateTexture(nil, "BACKGROUND")
	fbg:SetAllPoints()
	fbg:SetColorTexture(0, 0, 0, 0.25)
	self.frame = f

	local header = CreateFrame("Frame", nil, f)
	header:SetPoint("TOPLEFT")
	header:SetPoint("TOPRIGHT")
	header:SetHeight(16)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton")
	header:SetScript("OnDragStart", function() f:StartMoving() end)
	header:SetScript("OnDragStop", function()
		f:StopMovingOrSizing()
		local point, _, _, x, y = f:GetPoint()
		ns.db.profile.point = { point, x, y }
	end)
	header:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" and ns.Options then ns.Options:Open() end
	end)
	local hbg = header:CreateTexture(nil, "BACKGROUND")
	hbg:SetAllPoints()
	hbg:SetColorTexture(0.10, 0.10, 0.30, 0.85)
	local htext = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	htext:SetPoint("LEFT", 5, 0)
	htext:SetText(ns.L.ADDON_TITLE)
	self.header = header

	-- Red flash overlay for the Soulstone-ready alert.
	local flash = CreateFrame("Frame", nil, f)
	flash:SetAllPoints(f)
	flash:SetFrameStrata("HIGH")
	flash:EnableMouse(false)
	local ftex = flash:CreateTexture(nil, "OVERLAY")
	ftex:SetAllPoints()
	ftex:SetColorTexture(1, 0.15, 0.15)
	flash:SetAlpha(0)
	flash:Hide()
	self.flash = flash

	self.rows = {}
end

function Display:GetRow(i)
	local row = self.rows[i]
	if row then return row end

	row = CreateFrame("Frame", nil, self.frame)
	row:EnableMouse(false)

	local icon = row:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("LEFT")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	row.icon = icon

	local bar = CreateFrame("StatusBar", nil, row)
	bar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 2, 0)
	bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)
	row.bar = bar

	local function applyShadow(fs)
		fs:SetShadowColor(0, 0, 0, 1)
		fs:SetShadowOffset(1, -1)
	end

	-- Time first, so the name field can be bounded to its left edge.
	local timeText = bar:CreateFontString(nil, "OVERLAY")
	timeText:SetPoint("RIGHT", -3, 0)
	timeText:SetJustifyH("RIGHT")
	applyShadow(timeText)
	row.time = timeText

	local name = bar:CreateFontString(nil, "OVERLAY")
	name:SetPoint("LEFT", 3, 0)
	name:SetPoint("RIGHT", timeText, "LEFT", -4, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	applyShadow(name)
	row.name = name

	local text = row:CreateFontString(nil, "OVERLAY")
	text:SetPoint("LEFT", icon, "RIGHT", 4, 0)
	text:SetPoint("RIGHT", row, "RIGHT", -3, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	applyShadow(text)
	row.text = text

	self.rows[i] = row
	return row
end

function Display:UpdateRow(row, item, font, size, barTex)
	local p, L = ns.db.profile, ns.L
	row.icon:SetSize(p.height, p.height)
	row.bar:SetStatusBarTexture(barTex)
	row.name:SetFont(font, size)
	row.time:SetFont(font, size)
	row.text:SetFont(font, size)

	if p.display == "text" then
		row.bar:Hide()
		row.text:Show()
	else
		row.bar:Show()
		row.text:Hide()
	end
	row.bar:SetMinMaxValues(0, 1)

	if item.kind == "cooldown" then
		local ab, m = item.ability, item.member
		local cc = classColor(m.class)
		row.icon:SetTexture(ab.icon or QUESTION_ICON)
		if item.canSelfRez then
			-- Bar is red, so the name now carries the class colour.
			local txt = format(L.CAN_REINCARNATE, m.name)
			row.bar:SetValue(1)
			row.bar:SetStatusBarColor(0.85, 0.1, 0.1)
			row.name:SetText(txt)
			row.name:SetTextColor(cc.r, cc.g, cc.b)
			row.time:SetText(L.REZ)
			row.time:SetTextColor(1, 0.5, 0.5)
			row.text:SetText(txt)
			row.text:SetTextColor(cc.r, cc.g, cc.b)
		else
			row.name:SetText(m.name .. "  " .. ABILITY_TAG .. ab.name .. "|r")
			local timeStr
			if item.remaining > 0 then
				-- On cooldown: the bar carries the class colour, so the name
				-- stays white for readability.
				row.name:SetTextColor(1, 1, 1)
				row.text:SetTextColor(1, 1, 1)
				local entry = ns.Cooldowns:Get(m.guid, ab.key)
				local dur = (entry and entry.duration) or item.remaining
				row.bar:SetValue(item.remaining / dur)
				row.bar:SetStatusBarColor(cc.r, cc.g, cc.b)
				row.time:SetText(fmtTime(item.remaining))
				row.time:SetTextColor(1, 1, 1)
				timeStr = fmtTime(item.remaining)
			else
				-- Ready: bar is green, so the name picks up the class colour.
				row.name:SetTextColor(cc.r, cc.g, cc.b)
				row.text:SetTextColor(cc.r, cc.g, cc.b)
				row.bar:SetValue(1)
				row.bar:SetStatusBarColor(0.12, 0.6, 0.12)
				row.time:SetText(L.READY)
				row.time:SetTextColor(0.6, 1, 0.6)
				timeStr = "|cff66ff66" .. L.READY .. "|r"
			end
			row.text:SetText(format("%s  %s%s|r  %s",
				m.name, ABILITY_TAG, ab.name, timeStr))
		end
		row:SetAlpha(m.online == false and 0.35 or 1)
	else
		local e = item.entry
		local ab = ns.Abilities:Get(e.abilityKey)
		row.icon:SetTexture((ab and ab.icon) or QUESTION_ICON)
		row.bar:SetValue(1)
		local txt = targetText(e)
		row.name:SetText(txt)
		row.text:SetText(txt)
		if e.canRez then
			-- Bar is red, so the name takes the target's class colour.
			local target = ns.Roster:Get(e.target)
			local cc = classColor(target and target.class)
			row.bar:SetStatusBarColor(0.85, 0.1, 0.1)
			row.name:SetTextColor(cc.r, cc.g, cc.b)
			row.text:SetTextColor(cc.r, cc.g, cc.b)
			row.time:SetText(L.REZ)
			row.time:SetTextColor(1, 0.5, 0.5)
		else
			row.bar:SetStatusBarColor(0.5, 0.42, 0.1)
			row.name:SetTextColor(1, 0.95, 0.7)
			row.text:SetTextColor(1, 0.95, 0.7)
			if e.expirationTime then
				local rem = e.expirationTime - GetTime()
				if rem > 0 then
					row.time:SetText(fmtTime(rem))
					if e.duration and e.duration > 0 then
						row.bar:SetValue(rem / e.duration)
					end
				else
					row.time:SetText("")
				end
			else
				row.time:SetText("")
			end
			row.time:SetTextColor(1, 0.95, 0.7)
		end
		row:SetAlpha(1)
	end
end

-- Full rebuild: recompute the item list, sort it, and lay out the rows.
function Display:Rebuild()
	local f = self.frame
	if not f then return end
	local p = ns.db.profile

	local items = buildItems()
	sortItems(items)
	self.items = items

	local font = LSM:Fetch("font", p.font) or DEFAULT_FONT
	local barTex = LSM:Fetch("statusbar", p.barTexture) or DEFAULT_BAR
	local rowH = p.height + p.spacing
	local headerShown = not p.locked
	local headerH = headerShown and 16 or 0
	self.header:SetShown(headerShown)

	local count = #items
	for i = 1, count do
		local row = self:GetRow(i)
		local y = -(headerH + (i - 1) * rowH)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		row:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, y)
		row:SetHeight(p.height)
		self:UpdateRow(row, items[i], font, p.fontSize, barTex)
		row:Show()
	end
	for i = count + 1, #self.rows do
		self.rows[i]:Hide()
	end
	self.shownCount = count

	if not self:ShouldShow() or (count == 0 and p.locked) then
		f:Hide()
		return
	end
	f:Show()
	f:SetWidth(p.width)
	f:SetHeight(math.max(headerH + count * rowH, p.height))
end

-- Cheap per-tick pass: just advance the countdown on active cooldown rows.
function Display:LightUpdate()
	local items = self.items
	if not items then return end
	local textMode = ns.db.profile.display == "text"
	for i = 1, (self.shownCount or 0) do
		local item = items[i]
		if item and item.kind == "cooldown" and not item.canSelfRez then
			local rem = ns.Cooldowns:GetRemaining(item.member.guid, item.ability.key)
			if item.remaining > 0 and rem <= 0 then
				self.dirty = true   -- finished: needs a re-sort / recategorise
			elseif rem > 0 then
				item.remaining = rem
				local row = self.rows[i]
				local entry = ns.Cooldowns:Get(item.member.guid, item.ability.key)
				local dur = (entry and entry.duration) or rem
				row.bar:SetValue(rem / dur)
				row.time:SetText(fmtTime(rem))
				if textMode then
					row.text:SetText(format("%s  %s%s|r  %s", item.member.name,
						ABILITY_TAG, item.ability.name, fmtTime(rem)))
				end
			end
		elseif item and item.kind == "target" then
			-- Advance the soulstone / Divine Intervention buff countdown and bar.
			local e = item.entry
			if not e.canRez and e.expirationTime then
				local rem = e.expirationTime - GetTime()
				if rem > 0 then
					local row = self.rows[i]
					row.time:SetText(fmtTime(rem))
					if e.duration and e.duration > 0 then
						row.bar:SetValue(rem / e.duration)
					end
				else
					self.dirty = true   -- buff expired
				end
			end
		end
	end
end

function Display:Tick()
	if self.dirty then
		self.dirty = false
		self:Rebuild()
	else
		self:LightUpdate()
	end
end

-- External entry point: request a rebuild on the next tick.
function Display:Refresh()
	self.dirty = true
end

-- Frame visibility policy: "always" | "group" | "raid" | "hidden".
function Display:ShouldShow()
	local v = ns.db.profile.visibility
	if v == "hidden" then return false end
	if v == "raid" then return IsInRaid() end
	if v == "group" then return IsInGroup() end
	return true
end

function Display:Flash()
	local flash = self.flash
	if not flash then return end
	flash.endAt = GetTime() + 1.5
	flash:SetAlpha(0)
	flash:Show()
	flash:SetScript("OnUpdate", function(self2)
		local left = self2.endAt - GetTime()
		if left <= 0 then
			self2:SetScript("OnUpdate", nil)
			self2:Hide()
		else
			self2:SetAlpha((math.sin(left * 13) * 0.5 + 0.5) * 0.5)
		end
	end)
end

function Display:OnSoulstoneAlert()
	if not ns.db.profile.alertSoulstone then return end
	if SOUNDKIT and SOUNDKIT.ALARM_CLOCK_WARNING_3 then
		PlaySound(SOUNDKIT.ALARM_CLOCK_WARNING_3, "Master")
	end
	self:Flash()
end

function Display:ApplyPosition()
	local f = self.frame
	if not f then return end
	local pt = ns.db.profile.point
	f:ClearAllPoints()
	f:SetPoint(pt[1] or "TOP", UIParent, pt[1] or "TOP", pt[2] or 0, pt[3] or 0)
	f:SetScale(ns.db.profile.scale or 1)
end

function Display:ApplyLock()
	self.dirty = true
end

function Display:Initialize()
	self:CreateFrames()
	self:ApplyPosition()
	self:Rebuild()
	self.dirty = false
	self:ScheduleRepeatingTimer("Tick", 0.1)
	local function dirty() Display.dirty = true end
	ns.On("COOLDOWN_CHANGED", dirty)
	ns.On("TARGETS_CHANGED", dirty)
	ns.On("ROSTER_CHANGED", dirty)
	ns.On("ABILITIES_CHANGED", dirty)
	ns.On("LIFESTATE_CHANGED", dirty)
	ns.On("ALERT_SOULSTONE", function() Display:OnSoulstoneAlert() end)
end
