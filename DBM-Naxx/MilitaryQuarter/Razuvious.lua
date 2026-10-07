local mod	= DBM:NewMod("Razuvious", "DBM-Naxx", 4)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20221016184543")
mod:SetCreatureID(16061)

mod:RegisterCombat("combat_yell", L.Yell1, L.Yell2, L.Yell3, L.Yell4)

mod:RegisterEventsInCombat(
	"SPELL_CAST_SUCCESS 55543 29107 29060 29061 9250607 9250609 26613",
	"SPELL_AURA_APPLIED 605 9250609",
	"UNIT_DIED"
)

local warnShoutNow		= mod:NewSpellAnnounce(29107, 1)
local warnShoutSoon		= mod:NewSoonAnnounce(29107, 3)
local warnShieldWall	= mod:NewAnnounce("WarningShieldWallSoon", 3, 29061, nil, nil, nil, 29061)
local warnKnife			= mod:NewTargetNoFilterAnnounce(9250609, 2) -- Frostmourne custom

local timerShout		= mod:NewNextTimer(15, 29107, nil, nil, nil, 2) -- Whitemane PTR buff notes say it should be 12, but was consistently 15s in the vod
local timerTaunt		= mod:NewCDTimer(20, 29060, nil, nil, nil, 5, nil, DBM_COMMON_L.TANK_ICON)
local timerShieldWall	= mod:NewCDTimer(20, 29061, nil, nil, nil, 5, nil, DBM_COMMON_L.TANK_ICON)
local timerMindControl	= mod:NewBuffActiveTimer(60, 605, nil, nil, nil, 6)
local timerKnifeCD		= mod:NewNextTimer(10, 9250609, nil, nil, nil, 3) -- Frostmourne custom, log 2026-10-06: 35.5, then every 10.0-10.1
local timerUnbalancingCD = mod:NewCDTimer(30, 26613, nil, "Tank|Healer", nil, 5, nil, DBM_COMMON_L.TANK_ICON) -- Frostmourne log 2026-10-06: 29.9 / 60.0 / 90.0

mod:AddRangeFrameOption(12, 9250696) -- Disciplinary Shout (Frostmourne custom)
mod:AddBoolOption("RangeFrame2", true, "misc") -- second radar (DBM-Range2 addon), 21 yd
DBM:GetModLocalization("Razuvious"):SetOptionLocalization({RangeFrame2 = "Show second range radar (21 yd) - needs DBM-Range2"})

function mod:OnCombatStart(delay)
	timerKnifeCD:Start(35.5 - delay)
	timerUnbalancingCD:Start(30 - delay)
	if self.Options.RangeFrame then
		DBM.RangeCheck:Show(12)
	end
	if self.Options.RangeFrame2 and DBM.RangeCheck2 then
		DBM.RangeCheck2:Show(21)
	end
	if self:IsDifficulty("normal25", "heroic25") then -- Frostmourne raid reports as heroic25; log 2026-10-06: shout every 15.0-15.5
		timerShout:Start(15 - delay)
		warnShoutSoon:Schedule(10 - delay)
	else
		timerShout:Start(25 - delay)
		warnShoutSoon:Schedule(20 - delay)
	end
end

function mod:OnCombatEnd()
	if self.Options.RangeFrame then
		DBM.RangeCheck:Hide()
	end
	if self.Options.RangeFrame2 and DBM.RangeCheck2 then
		DBM.RangeCheck2:Hide()
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	local spellId = args.spellId
	if args:IsSpellID(55543, 29107, 9250607) then  -- Disrupting Shout (9250607: Frostmourne custom)
		warnShoutNow:Show()
		if self:IsDifficulty("normal25", "heroic25") then
			timerShout:Start()
			warnShoutSoon:Schedule(10)
		else
			timerShout:Start(25)
			warnShoutSoon:Schedule(20)
		end
	elseif spellId == 29060 then -- Taunt
		timerTaunt:Start(20, args.sourceGUID)
	elseif spellId == 29061 and self:AntiSpam(2, 1) then -- ShieldWall
		timerShieldWall:Start(20, args.sourceGUID)
		warnShieldWall:Schedule(15)
	elseif spellId == 9250609 then -- Jagged Knife (Frostmourne custom)
		timerKnifeCD:Start()
	elseif spellId == 26613 then -- Unbalancing Strike
		timerUnbalancingCD:Start()
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == 605 and args:IsSrcTypePlayer() then -- Mind Control
		timerMindControl:Start(nil, args.sourceName)
	elseif args.spellId == 9250609 then -- Jagged Knife (Frostmourne custom)
		warnKnife:Show(args.destName)
	end
end

function mod:UNIT_DIED(args)
	local guid = args.destGUID
	local cid = self:GetCIDFromGUID(guid)
	if cid == 16803 then--Deathknight Understudy
		timerTaunt:Stop(args.destGUID)
		timerShieldWall:Stop(args.destGUID)
	end
end
