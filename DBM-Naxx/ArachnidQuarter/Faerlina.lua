local mod	= DBM:NewMod("Faerlina", "DBM-Naxx", 1)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20221016190115")
mod:SetCreatureID(15953)

mod:RegisterCombat("combat_yell", L.Pull)

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 28798 54100 28732 54097 28794 54099 9250587",
	"SPELL_CAST_SUCCESS 28796 54098 9250585 9250587 9250687",
	"UNIT_DIED"
)

local warnEmbraceActive		= mod:NewSpellAnnounce(28732, 1)
local warnEmbraceExpire		= mod:NewAnnounce("WarningEmbraceExpire", 2, 28732, nil, nil, nil, 28732)
local warnEmbraceExpired	= mod:NewFadesAnnounce(28732, 3)
local warnEnrageSoon		= mod:NewSoonAnnounce(28131, 3)
local warnEnrageNow			= mod:NewSpellAnnounce(28131, 4)

local specWarnEnrage		= mod:NewSpecialWarningDefensive(28131, nil, nil, nil, 3, 2)
local specWarnGTFO			= mod:NewSpecialWarningGTFO(28794, nil, nil, nil, 1, 8)
local specWarnRisen			= mod:NewSpecialWarning("SpecWarnRisenWorshipper", nil, nil, nil, 1, 2) -- Frostmourne custom: a dead Worshipper rises about 6s later
DBM:GetModLocalization("Faerlina"):SetWarningLocalization({SpecWarnRisenWorshipper = "Risen Worshipper!"})
DBM:GetModLocalization("Faerlina"):SetOptionLocalization({SpecWarnRisenWorshipper = "Show special warning when a Risen Worshipper appears"})

local timerEmbrace			= mod:NewBuffActiveTimer(30, 28732, nil, nil, nil, 6)
local timerEnrage			= mod:NewCDTimer(60, 28131, nil, nil, nil, 6)
local timerPoisonVolleyCD	= mod:NewCDTimer(14, 54098, nil, nil, nil, 5)
local timerRainOfFireCD		= mod:NewNextTimer(12, 9250587, nil, nil, nil, 3) -- Frostmourne custom, log 2026-10-06: every 12.0-12.1

mod.vb.enraged = false
local risenSeen = {}

function mod:OnCombatStart(delay)
	table.wipe(risenSeen)
	-- Frostmourne raid reports as heroic25; logs 2026-10-06: first Frenzy at 74.1 and 74.6 (two pulls)
	local firstEnrage = self:IsDifficulty("heroic25") and 74 or 60
	timerEnrage:Start(firstEnrage - delay)
	warnEnrageSoon:Schedule(firstEnrage - 5 - delay)
	timerPoisonVolleyCD:Start(12.6-delay) -- REVIEW! variance? (25man Lordaeron 2022/10/16) - 12.6
	-- no Rain of Fire bar on pull: the first cast came at 8.6, 15.5 and 18.0 in three pulls
	self.vb.enraged = false
end

function mod:SPELL_AURA_APPLIED(args)
	if args:IsSpellID(28798, 54100) then -- Frenzy
		self.vb.enraged = true
		--if self:IsTanking("player", nil, nil, true, args.destGUID) then -- Whitemane PTR (boss1 doesn't work currently, changed to GUID-based)
		if self:IsTanking("player", "boss1", nil, true) then -- seems to be fixed now
			specWarnEnrage:Show()
			specWarnEnrage:Play("defensive")
		else
			warnEnrageNow:Show()
		end
	elseif args:IsSpellID(28732, 54097)	and args:GetDestCreatureID() == 15953 and self:AntiSpam(5, 2) then	-- Widow's Embrace
		warnEmbraceExpire:Cancel()
		warnEmbraceExpired:Cancel()
		warnEnrageSoon:Cancel()
		timerPoisonVolleyCD:Cancel()
		timerPoisonVolleyCD:Schedule(30, 10) -- seems inconsistent
		timerEnrage:Stop()
		if self.vb.enraged then
			timerEnrage:Start()
			warnEnrageSoon:Schedule(55)
		else
			timerEnrage:Start(35)
			warnEnrageSoon:Schedule(30)
		end
		timerEmbrace:Start()
		warnEmbraceActive:Show()
		warnEmbraceExpire:Schedule(25)
		warnEmbraceExpired:Schedule(30)
		self.vb.enraged = false
	elseif args:IsSpellID(28794, 54099, 9250587) and args:IsPlayer() then
		specWarnGTFO:Show(args.spellName)
		specWarnGTFO:Play("watchfeet")
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args:IsSpellID(28796, 54098, 9250585) then -- Poison Bolt Volley (9250585: Frostmourne custom)
		timerPoisonVolleyCD:Start()
	elseif args.spellId == 9250587 then -- Rain of Fire (Frostmourne custom)
		timerRainOfFireCD:Start()
	elseif args.spellId == 9250687 then -- Vengeful Blight: only Risen Worshippers cast it
		if args.sourceGUID and not risenSeen[args.sourceGUID] then
			risenSeen[args.sourceGUID] = true
			specWarnRisen:Show()
			specWarnRisen:Play("killmob")
		end
	end
end

function mod:UNIT_DIED(args)
	local cid = self:GetCIDFromGUID(args.destGUID)
	if cid == 15953 then
		warnEnrageSoon:Cancel()
		warnEmbraceExpire:Cancel()
		warnEmbraceExpired:Cancel()
		timerPoisonVolleyCD:Cancel()
		timerRainOfFireCD:Cancel()
	end
end
