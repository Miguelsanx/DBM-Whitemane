local mod	= DBM:NewMod("Maexxna", "DBM-Naxx", 1)
local L		= mod:GetLocalizedStrings()

mod:SetRevision("20220627034419")
mod:SetCreatureID(15952)
mod:RegisterCombat("combat")

mod:RegisterEventsInCombat(
	"SPELL_AURA_APPLIED 28622 29484 54125 9250574",
	"SPELL_CAST_SUCCESS 9250576",
	"CHAT_MSG_RAID_BOSS_EMOTE"
)

--TODO, verify nax40 web wrap timer
local warnWebWrap		= mod:NewTargetNoFilterAnnounce(28622, 2)
local warnWebSpraySoon	= mod:NewSoonAnnounce(29484, 1)
local warnWebSprayNow	= mod:NewSpellAnnounce(29484, 3)
local warnSpidersSoon	= mod:NewAnnounce("WarningSpidersSoon", 2, 17332)
local warnSpidersNow	= mod:NewAnnounce("WarningSpidersNow", 4, 17332)
local warnPoisonShock	= mod:NewSpellAnnounce(9250576, 2) -- Frostmourne custom

local specWarnWebWrap	= mod:NewSpecialWarningSwitch(28622, "RangedDps", nil, nil, 1, 2)
local yellWebWrap		= mod:NewYellMe(28622)

local timerWebSpray		= mod:NewNextTimer(40, 29484, nil, nil, nil, 2) -- Frostmourne log 2026-10-06: 40.1 / 80.3 (was 30.5)
local timerPoisonShockCD = mod:NewCDTimer(40, 9250576, nil, nil, nil, 3) -- Frostmourne custom, log 2026-10-06: 9.9 / 50.0
local timerWebWrap		= mod:NewNextTimer(30, 28622, nil, "RangedDps|Healer", nil, 3)
local timerSpider		= mod:NewTimer(30.2, "TimerSpider", 17332, nil, nil, 1)

local emoteSpiderlings = "Spiderlings appear on the web!"

function mod:OnCombatStart(delay)
	warnWebSpraySoon:Schedule(35 - delay)
	timerWebSpray:Start(40 - delay)
	timerPoisonShockCD:Start(10 - delay)
	timerWebWrap:Start(15 - delay)
	warnSpidersSoon:Schedule(20.2 - delay)
	timerSpider:Start(25.2 - delay)
end

function mod:OnCombatEnd(wipe)
	if not wipe then
		if DBT:GetBar(L.ArachnophobiaTimer) then
			DBT:CancelBar(L.ArachnophobiaTimer)
		end
	end
end

function mod:SPELL_AURA_APPLIED(args)
	if args.spellId == 28622 then -- Web Wrap
		warnWebWrap:CombinedShow(0.5, args.destName)
		if self:AntiSpam(3, 1) then
			specWarnWebWrap:Show()
			if self:IsDifficulty("normal25") then
				timerWebWrap:Start()
			else
				timerWebWrap:Start(25)
			end
		end
		
		if args.destName == UnitName("player") then
			yellWebWrap:Yell()
		elseif not DBM:UnitDebuff("player", args.spellName) and self:AntiSpam(3, 2) then
			specWarnWebWrap:Play("targetchange")
		end
	elseif args:IsSpellID(29484, 54125, 9250574) and self:AntiSpam(3, 3) then -- Web Spray (9250574: Frostmourne custom)
		warnWebSprayNow:Show()
		warnWebSpraySoon:Schedule(35)
		timerWebSpray:Start()
	end
end

function mod:SPELL_CAST_SUCCESS(args)
	if args.spellId == 9250576 then -- Poison Shock (Frostmourne custom)
		warnPoisonShock:Show()
		timerPoisonShockCD:Start()
	end
end

function mod:CHAT_MSG_RAID_BOSS_EMOTE(msg)
	if msg == emoteSpiderlings then
		self:SendSync("Spiderlings")
	end
end

function mod:OnSync(event)
	if event == "Spiderlings" then
		warnSpidersNow:Show()
		warnSpidersSoon:Schedule(25.2)
		timerSpider:Start()
	end
end
