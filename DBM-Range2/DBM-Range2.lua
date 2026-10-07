-- DBM-Range2: a second range radar next to DBM's own one, with an estimated boss marker (second radar only).
--   /range2 x          show the second radar with x yards (x = 1..200)
--   /range2            hide it (or show it with 10 yards if it is hidden)
--   /range2 boss       toggle the boss marker (red dot + translucent disc)
--   /range2 boss x     set the assumed tank-to-boss distance to x yards (default 5)
-- Boss mods can use it too:  if DBM.RangeCheck2 then DBM.RangeCheck2:Show(12) end  /  DBM.RangeCheck2:Hide()
--                            DBM.RangeCheck2:SetBossOffset(8) for bosses with a big hitbox
-- DBM's own files are not touched. Distances are measured the same way DBM's radar does it (map positions).
--
-- Boss marker: the 3.3.5 client never tells addons where an NPC stands, so the position is estimated:
--   * the boss's current target is taken as the tank (its map position is known)
--   * if the tank runs this addon too, it broadcasts its own facing; the boss is then placed
--     <offset> yards in front of the tank (red dot, disc around it reaching back to the tank)
--   * without the addon on the tank the facing is unknown: the dot sits on the tank and the disc
--     around the tank shows where the boss can be

local DBM = DBM
if not DBM then return end

local rc2 = {}
DBM.RangeCheck2 = rc2

local GetPlayerMapPosition, GetPlayerFacing = GetPlayerMapPosition, GetPlayerFacing
local UnitExists, UnitIsUnit, UnitIsDeadOrGhost, UnitIsConnected = UnitExists, UnitIsUnit, UnitIsDeadOrGhost, UnitIsConnected
local UnitClass, UnitName, GetRaidTargetIndex = UnitClass, UnitName, GetRaidTargetIndex
local GetNumRaidMembers, GetNumPartyMembers = GetNumRaidMembers, GetNumPartyMembers
local sin, cos, min, pi2 = math.sin, math.cos, math.min, math.pi * 2

local BLIP_TEX_COORDS = {
	["WARRIOR"]		= { 0, 0.125, 0, 0.25 },
	["PALADIN"]		= { 0.125, 0.25, 0, 0.25 },
	["HUNTER"]		= { 0.25, 0.375, 0, 0.25 },
	["ROGUE"]		= { 0.375, 0.5, 0, 0.25 },
	["PRIEST"]		= { 0.5, 0.625, 0, 0.25 },
	["DEATHKNIGHT"]	= { 0.625, 0.75, 0, 0.25 },
	["SHAMAN"]		= { 0.75, 0.875, 0, 0.25 },
	["MAGE"]		= { 0.875, 1, 0, 0.25 },
	["WARLOCK"]		= { 0, 0.125, 0.25, 0.5 },
	["DRUID"]		= { 0.25, 0.375, 0.25, 0.5 },
}

local frame
local activeRange = 10
local userShown = false -- true when the player opened it with /range2 (a boss mod's Hide() then leaves it open)
local elapsedSince = 0

local function getMapSize()
	local ok, x, y = pcall(DBM.GetMapSize, DBM)
	if ok and x and y then
		return x, y
	end
end

local function saveDB()
	DBMRange2DB = DBMRange2DB or {}
	return DBMRange2DB
end

local function createFrame()
	local db = saveDB()
	frame = CreateFrame("Frame", "DBMRangeCheckRadar2", UIParent)
	frame:SetFrameStrata("DIALOG")
	frame:SetPoint(db.point or "CENTER", UIParent, db.point or "CENTER", db.x or 160, db.y or 0)
	frame:SetWidth(128)
	frame:SetHeight(128)
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint(1)
		local sv = saveDB()
		sv.point, sv.x, sv.y = point, x, y
	end)

	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints(frame)
	bg:SetBlendMode("BLEND")
	bg:SetTexture(0, 0, 0, 0.3)

	local circle = frame:CreateTexture(nil, "ARTWORK")
	circle:SetWidth(85)
	circle:SetHeight(85)
	circle:SetPoint("CENTER")
	circle:SetTexture("Interface\\AddOns\\DBM-Core\\textures\\radar_circle.blp")
	circle:SetVertexColor(0, 1, 0)
	circle:SetBlendMode("ADD")
	frame.circle = circle

	local player = frame:CreateTexture(nil, "OVERLAY")
	player:SetWidth(32)
	player:SetHeight(32)
	player:SetTexture("Interface\\Minimap\\MinimapArrow.blp")
	player:SetBlendMode("ADD")
	player:SetPoint("CENTER")

	local text = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
	text:SetWidth(128)
	text:SetHeight(15)
	text:SetPoint("BOTTOMLEFT", frame, "TOPLEFT")
	text:SetTextColor(1, 1, 1, 1)
	frame.text = text

	local inRangeText = frame:CreateFontString(nil, "OVERLAY", "GameTooltipText")
	inRangeText:SetWidth(128)
	inRangeText:SetHeight(15)
	inRangeText:SetPoint("TOPLEFT", frame, "BOTTOMLEFT")
	inRangeText:SetTextColor(1, 1, 1, 1)
	inRangeText:Hide()
	frame.inRangeText = inRangeText

	frame.dots = {}
	for i = 1, 40 do
		local dot = frame:CreateTexture(nil, "OVERLAY")
		dot:SetWidth(24)
		dot:SetHeight(24)
		dot:SetTexture("Interface\\Minimap\\PartyRaidBlips")
		dot:Hide()
		frame.dots[i] = dot
	end

	frame:Hide()
end

local function styleDot(dot, uId)
	local icon = GetRaidTargetIndex(uId)
	local _, class = UnitClass(uId)
	local key = icon and ("i" .. icon) or (class or "PRIEST")
	if dot.key == key then return end
	dot.key = key
	if icon and icon < 9 then
		dot:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. icon)
		dot:SetTexCoord(0, 1, 0, 1)
		dot:SetWidth(16)
		dot:SetHeight(16)
	else
		local c = BLIP_TEX_COORDS[class] or BLIP_TEX_COORDS["PRIEST"]
		dot:SetTexture("Interface\\Minimap\\PartyRaidBlips")
		dot:SetTexCoord(c[1], c[2], c[3], c[4])
		dot:SetWidth(24)
		dot:SetHeight(24)
	end
end

---------------------------------------------------------------------
-- Boss marker (estimated)
---------------------------------------------------------------------
local PREFIX = "DBMR2"
local DISC_ALPHA = 0.4		-- 40% visible
local DISC_MAX_SHARE = 0.25	-- disc diameter is at most 25% of the range circle's diameter
local CIRCLE_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- plain filled circle

local facings = {}	-- [name] = { f = facing, t = GetTime() }
local boss = {}		-- current estimate: boss.dx, boss.dy (yards from player, map axes), boss.tx, boss.ty (tank), boss.hasFacing
local bossUnit, tankUnit
local scanSince, sendSince, lastSent, lastSentTime = 1, 0, nil, 0

local function bossShown()
	return saveDB().bossShow ~= false
end

local function bossOffset()
	return rc2.bossOffsetOverride or saveDB().bossOffset or 5
end

local function isBoss(u)
	return UnitExists(u) and not UnitIsPlayer(u) and UnitCanAttack("player", u) and not UnitIsDeadOrGhost(u)
		and UnitAffectingCombat(u) and (UnitLevel(u) == -1 or UnitClassification(u) == "worldboss")
end

local function groupInfo()
	local raid = GetNumRaidMembers()
	if raid > 0 then
		return raid, "raid"
	end
	return GetNumPartyMembers(), "party"
end

-- creature IDs of the encounter DBM currently has in combat (the real boss, not its adds)
local activeIds = {}
local function refreshActiveIds()
	for k in pairs(activeIds) do
		activeIds[k] = nil
	end
	local any = false
	for _, mod in ipairs(DBM.Mods or {}) do
		if mod.inCombat then
			if mod.mainBoss then
				activeIds[mod.mainBoss] = true
				any = true
			elseif mod.multiMobPullDetection then
				for _, cid in ipairs(mod.multiMobPullDetection) do
					activeIds[cid] = true
					any = true
				end
			elseif mod.creatureId then
				activeIds[mod.creatureId] = true
				any = true
			end
		end
	end
	return any
end

local function findBoss()
	bossUnit, tankUnit = nil, nil
	local known = refreshActiveIds()
	-- with a running DBM encounter only that boss counts; otherwise any boss-level enemy in combat
	local function matches(u)
		if known then
			return UnitExists(u) and not UnitIsDeadOrGhost(u) and UnitCanAttack("player", u)
				and activeIds[DBM:GetCIDFromGUID(UnitGUID(u))]
		end
		return isBoss(u)
	end
	local found
	if matches("target") then
		found = "target"
	elseif matches("focus") then
		found = "focus"
	else
		for i = 1, 4 do
			if matches("boss" .. i) then
				found = "boss" .. i
				break
			end
		end
		if not found then
			local num, prefix = groupInfo()
			for i = 1, num do
				if matches(prefix .. i .. "target") then
					found = prefix .. i .. "target"
					break
				end
			end
		end
	end
	if not found then return end
	bossUnit = found
	local tt = found .. "target"
	if not UnitExists(tt) then return end
	if UnitIsUnit(tt, "player") then
		tankUnit = "player"
		return
	end
	local num, prefix = groupInfo()
	for i = 1, num do
		if UnitIsUnit(tt, prefix .. i) then
			tankUnit = prefix .. i
			return
		end
	end
end

-- the tank's client tells the group where it is looking
local function broadcastFacing(elapsed)
	sendSince = sendSince + elapsed
	if sendSince < 0.25 then return end
	sendSince = 0
	if tankUnit ~= "player" then
		lastSent = nil
		return
	end
	local num = groupInfo()
	if num == 0 then return end
	local f = GetPlayerFacing() or 0
	local now = GetTime()
	local diff = lastSent and math.abs(f - lastSent) or 10
	if diff > math.pi then diff = pi2 - diff end
	if diff > 0.05 or now - lastSentTime > 2 then
		lastSent, lastSentTime = f, now
		SendAddonMessage(PREFIX, ("F:%.2f"):format(f), GetNumRaidMembers() > 0 and "RAID" or "PARTY")
	end
end

local function estimateBoss()
	boss.valid = false
	if not tankUnit or not bossShown() then return end
	local mapX, mapY = getMapSize()
	local playerX, playerY = GetPlayerMapPosition("player")
	if not mapX or (playerX == 0 and playerY == 0) then return end
	local tx, ty, facing = 0, 0, nil
	if tankUnit == "player" then
		facing = GetPlayerFacing() or 0
	else
		local unitX, unitY = GetPlayerMapPosition(tankUnit)
		if unitX == 0 and unitY == 0 then return end
		tx, ty = (unitX - playerX) * mapX, (unitY - playerY) * mapY
		local name = UnitName(tankUnit)
		local rec = name and facings[name]
		if rec and GetTime() - rec.t < 3 then
			facing = rec.f
		end
	end
	local off = bossOffset()
	boss.tx, boss.ty = tx, ty
	if facing then
		-- facing 0 = north, counter-clockwise; map x grows east, map y grows south
		boss.dx, boss.dy = tx - sin(facing) * off, ty - cos(facing) * off
		boss.hasFacing = true
	else
		boss.dx, boss.dy = tx, ty
		boss.hasFacing = false
	end
	boss.valid = true
end

local function ensureBossTextures(radar)
	if radar.r2disc then return end
	local disc = radar:CreateTexture(nil, "ARTWORK")
	disc:SetTexture(CIRCLE_TEX)
	disc:SetVertexColor(1, 0, 0)
	disc:SetAlpha(DISC_ALPHA)
	disc:Hide()
	radar.r2disc = disc
	local dot = radar:CreateTexture(nil, "OVERLAY")
	dot:SetTexture(CIRCLE_TEX)
	dot:SetVertexColor(1, 0, 0)
	dot:SetWidth(8)
	dot:SetHeight(8)
	dot:Hide()
	radar.r2dot = dot
end

local function drawBoss(radar, range)
	ensureBossTextures(radar)
	local disc, dot = radar.r2disc, radar.r2dot
	local dist = boss.valid and (boss.dx * boss.dx + boss.dy * boss.dy) ^ 0.5
	if not dist or dist > range * 1.5 then
		disc:Hide()
		dot:Hide()
		return
	end
	local size = min(radar:GetWidth(), radar:GetHeight())
	local pixelsperyard = size / (range * 3)
	local rotation = pi2 - (GetPlayerFacing() or 0)
	local sinTheta, cosTheta = sin(rotation), cos(rotation)
	local x = ((boss.dx * cosTheta) - (-boss.dy * sinTheta)) * pixelsperyard
	local y = ((boss.dx * sinTheta) + (-boss.dy * cosTheta)) * pixelsperyard
	-- disc radius = tank-to-boss distance, capped at 25% of the range circle
	local diameter = min(bossOffset() * 2 * pixelsperyard, range * 2 * pixelsperyard * DISC_MAX_SHARE)
	disc:SetWidth(diameter)
	disc:SetHeight(diameter)
	disc:ClearAllPoints()
	disc:SetPoint("CENTER", radar, "CENTER", x, y)
	disc:Show()
	dot:ClearAllPoints()
	dot:SetPoint("CENTER", radar, "CENTER", x, y)
	dot:Show()
end

local function hideBoss(radar)
	if radar and radar.r2disc then
		radar.r2disc:Hide()
		radar.r2dot:Hide()
	end
end

local driver = CreateFrame("Frame")
local driverSince = 0
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
	if prefix ~= PREFIX or not sender then return end
	local f = tonumber(msg:match("^F:([%d%.]+)$"))
	if not f then return end
	sender = sender:match("^([^%-]+)") or sender
	local rec = facings[sender]
	if not rec then
		rec = {}
		facings[sender] = rec
	end
	rec.f, rec.t = f, GetTime()
end)
driver:SetScript("OnUpdate", function(_, elapsed)
	scanSince = scanSince + elapsed
	if scanSince >= 0.5 then
		scanSince = 0
		findBoss()
	end
	broadcastFacing(elapsed)
	driverSince = driverSince + elapsed
	if driverSince < 0.05 then return end
	driverSince = 0
	if not (frame and frame:IsShown()) then return end
	estimateBoss()
	drawBoss(frame, activeRange)
end)

function rc2:SetBossOffset(yards)
	self.bossOffsetOverride = tonumber(yards)
end

local function update()
	local mapX, mapY = getMapSize()
	local playerX, playerY = GetPlayerMapPosition("player")
	if not mapX or (playerX == 0 and playerY == 0) then
		-- no usable map data in this zone: nothing can be measured
		for i = 1, 40 do
			frame.dots[i]:Hide()
		end
		frame.circle:SetVertexColor(1, 1, 1)
		frame.inRangeText:SetText("no map data here")
		frame.inRangeText:Show()
		hideBoss(frame)
		return
	end

	local pixelsperyard = min(frame:GetWidth(), frame:GetHeight()) / (activeRange * 3)
	local rotation = pi2 - (GetPlayerFacing() or 0)
	local sinTheta, cosTheta = sin(rotation), cos(rotation)

	local raid = GetNumRaidMembers()
	local num = raid > 0 and raid or GetNumPartyMembers()
	local prefix = raid > 0 and "raid" or "party"
	local close, closestRange, closestName = 0, nil, nil

	for i = 1, 40 do
		local dot = frame.dots[i]
		local uId = prefix .. i
		if i <= num and UnitExists(uId) and not UnitIsUnit(uId, "player") and not UnitIsDeadOrGhost(uId) and UnitIsConnected(uId) then
			local unitX, unitY = GetPlayerMapPosition(uId)
			if unitX == 0 and unitY == 0 then
				dot:Hide()
			else
				local dx, dy = (unitX - playerX) * mapX, (unitY - playerY) * mapY
				local range = (dx * dx + dy * dy) ^ 0.5
				if range < activeRange + 0.5 then
					close = close + 1
					if not closestRange or range < closestRange then
						closestRange, closestName = range, UnitName(uId)
					end
				end
				if range < activeRange * 1.5 then
					styleDot(dot, uId)
					dot:ClearAllPoints()
					dot:SetPoint("CENTER", frame, "CENTER", ((dx * cosTheta) - (-dy * sinTheta)) * pixelsperyard, ((dx * sinTheta) + (-dy * cosTheta)) * pixelsperyard)
					dot:Show()
				else
					dot:Hide()
				end
			end
		else
			dot:Hide()
		end
	end

	if UnitIsDeadOrGhost("player") then
		frame.circle:SetVertexColor(1, 1, 1)
		frame.inRangeText:Hide()
	elseif close > 0 then
		frame.circle:SetVertexColor(1, 0, 0)
		if close == 1 then
			frame.inRangeText:SetText(("%s (%0.1f yd)"):format(closestName or "?", closestRange))
		else
			frame.inRangeText:SetText(("%d players (%0.1f yd)"):format(close, closestRange))
		end
		frame.inRangeText:Show()
	else
		frame.circle:SetVertexColor(0, 1, 0)
		frame.inRangeText:Hide()
	end
end

local function onUpdate(self, elapsed)
	elapsedSince = elapsedSince + elapsed
	if elapsedSince < 0.05 then return end
	elapsedSince = 0
	update()
end

-- Show(range, byUser): byUser is set by /range2 only
function rc2:Show(range, byUser)
	range = tonumber(range) or 10
	if range < 1 then range = 1 end
	if range > 200 then range = 200 end
	if not frame then
		createFrame()
	end
	activeRange = range
	if byUser then
		userShown = true
	end
	local pixelsperyard = min(frame:GetWidth(), frame:GetHeight()) / (activeRange * 3)
	frame.circle:SetWidth(activeRange * pixelsperyard * 2)
	frame.circle:SetHeight(activeRange * pixelsperyard * 2)
	frame.text:SetText(("Range 2: %d yd"):format(activeRange))
	for i = 1, 40 do
		frame.dots[i].key = nil
	end
	frame:SetScript("OnUpdate", onUpdate)
	frame:Show()
	update()
end

-- Hide(force): a boss mod's plain Hide() leaves a radar the player opened with /range2 alone
function rc2:Hide(force)
	if not frame then return end
	if userShown and not force then return end
	userShown = false
	frame:SetScript("OnUpdate", nil)
	frame:Hide()
end

function rc2:IsShown()
	return frame and frame:IsShown() or false
end

function rc2:GetRange()
	return activeRange
end

SLASH_DBMRANGETWO1 = "/range2"
SLASH_DBMRANGETWO2 = "/distance2"
SlashCmdList["DBMRANGETWO"] = function(msg)
	msg = (msg or ""):lower()
	local bossArg = msg:match("^%s*boss%s*(%S*)")
	if bossArg then
		local db = saveDB()
		local yards = tonumber(bossArg)
		if yards and yards >= 0 and yards <= 50 then
			db.bossOffset = yards
			db.bossShow = true
			DBM:AddMsg(("Range 2: boss marker on, tank-to-boss distance %s yd"):format(yards))
		else
			db.bossShow = not bossShown()
			if not db.bossShow then
				hideBoss(frame)
			end
			DBM:AddMsg("Range 2: boss marker " .. (db.bossShow and "on" or "off"))
		end
		return
	end
	local r = tonumber(msg:match("^%s*(%S*)"))
	if r then
		rc2:Show(r, true)
	elseif rc2:IsShown() then
		rc2:Hide(true)
	else
		rc2:Show(10, true)
	end
end
