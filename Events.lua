-- Events.lua
-- Addon-wide event watcher frames not tied to a single object instance. Loads last: handlers call
-- into every other file, but only run once a real game event fires.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Login / logout (Core.lua)
-------------------------------------------------------------------------

-- PLAYER_ENTERING_WORLD (not PLAYER_LOGIN) gives the native bars more time to settle; unregistered after first fire.
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loadFrame:RegisterEvent("PLAYER_LOGOUT")

loadFrame:SetScript("OnEvent", function()
	if event == "PLAYER_LOGOUT" then
		ACAB:SaveActiveProfileData()
		return
	end

	loadFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")

	-- WaitForNativeBarSettle calls its callback as a plain function; the wrapper keeps RunLoginSequence's self.
	ACAB:WaitForNativeBarSettle(function(earlyLeft, earlyTop, settledLeft, settledTop, waited)
		ACAB:RunLoginSequence(earlyLeft, earlyTop, settledLeft, settledTop, waited)
	end)
end)

-------------------------------------------------------------------------
-- Custom-bar grid visibility (Button.lua)
-------------------------------------------------------------------------

local gridVisibilityFrame = CreateFrame("Frame")
gridVisibilityFrame:RegisterEvent("ACTIONBAR_SHOWGRID")
gridVisibilityFrame:RegisterEvent("ACTIONBAR_HIDEGRID")
gridVisibilityFrame:SetScript("OnEvent", function()
	ACAB.isShowingActionGrid = (event == "ACTIONBAR_SHOWGRID")

	ACAB:SweepCustomBarGridVisibility()
end)

-------------------------------------------------------------------------
-- Main Bar bonus-actionbar frame (DefaultBars.lua)
-------------------------------------------------------------------------

-- UPDATE_BONUS_ACTIONBAR covers bonus-page forms (Bear/Cat); PLAYER_AURAS_CHANGED catches the rest
-- (Travel/Aquatic), since UPDATE_SHAPESHIFT_FORM never fires on this client (§5aj).
local mainBarBonusEventFrame = CreateFrame("Frame", "ACABMainBarBonusEventFrame")
mainBarBonusEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
mainBarBonusEventFrame:RegisterEvent("PLAYER_AURAS_CHANGED")

local lastDefaultBarStanceIndex = false

mainBarBonusEventFrame:SetScript("OnEvent", function()
	if event == "UPDATE_BONUS_ACTIONBAR" then
		ACAB:HideBonusActionBarFrame()
		ACAB:RefreshDefaultBarSlots()
		lastDefaultBarStanceIndex = ACAB:GetActiveStanceIndex()
		return
	end

	-- PLAYER_AURAS_CHANGED fires on every aura change - only refresh when the active stance index changed.
	local stanceIndex = ACAB:GetActiveStanceIndex()

	if stanceIndex ~= lastDefaultBarStanceIndex then
		lastDefaultBarStanceIndex = stanceIndex
		ACAB:RefreshDefaultBarSlots()
	end
end)

-------------------------------------------------------------------------
-- Pet Bar visibility (DefaultBars.lua)
-------------------------------------------------------------------------

local petBarVisibilityFrame = CreateFrame("Frame")
petBarVisibilityFrame:RegisterEvent("PET_BAR_UPDATE")
petBarVisibilityFrame:RegisterEvent("UNIT_PET")
petBarVisibilityFrame:RegisterEvent("PLAYER_CONTROL_LOST")
petBarVisibilityFrame:RegisterEvent("PLAYER_CONTROL_GAINED")
petBarVisibilityFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
petBarVisibilityFrame:SetScript("OnEvent", function()
	if event == "UNIT_PET" and arg1 ~= "player" then
		return
	end

	ACAB:RefreshPetBarVisibility()
end)

-------------------------------------------------------------------------
-- Stance/form set changes (PetStanceBars.lua)
-------------------------------------------------------------------------

-- UPDATE_SHAPESHIFT_FORMS: the available form set changed (kept registered despite §5aj).
local stanceFormEventFrame = CreateFrame("Frame", "ACABStanceFormEventFrame")
stanceFormEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
stanceFormEventFrame:SetScript("OnEvent", function()
	-- Native mode.
	ACAB:RebuildStanceBarContainer()

	-- Styled mode: re-lay-out the pool bar if the live form count changed its shape.
	if ACAB:ApplyStanceBarLiveShape() then
		local styledBar = ACAB.bars and ACAB.bars[ACAB.STANCE_BAR_ID]

		if styledBar then
			ACAB:ApplyBarShape(styledBar)
		end

		if ACAB.RefreshBarSettingsPage then
			ACAB:RefreshBarSettingsPage(ACAB.STANCE_BAR_ID)
		end
	end

	-- Re-syncs bars 1-5's per-stance assignment rows on any already-built settings page.
	if ACAB.RebuildAllDefaultBarAssignmentRows then
		ACAB:RebuildAllDefaultBarAssignmentRows()
	end
end)

-------------------------------------------------------------------------
-- Cast Bar position retry (NativeElements.lua)
-------------------------------------------------------------------------

-- Retries Cast Bar positioning on cast start until ACABDB.castBarPosition exists.
local castBarEventFrame = CreateFrame("Frame", "ACABCastBarEventFrame")
castBarEventFrame:RegisterEvent("UNIT_SPELLCAST_START")
castBarEventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
castBarEventFrame:SetScript("OnEvent", function()
	if not ACABDB or not ACABDB.castBarPosition then
		ACAB:ApplyCastBarPosition()
	end
end)

-------------------------------------------------------------------------
-- "Better Experience Bar" live updates (ExperienceBar.lua)
-------------------------------------------------------------------------

-- Always registered; BetterExpBarOnEvent's callees are nil-safe and gate on ACABDB.betterExpBarEnabled.
local betterExpBarEventFrame = CreateFrame("Frame", "ACABBetterExpBarEventFrame")
betterExpBarEventFrame:RegisterEvent("PLAYER_XP_UPDATE")
betterExpBarEventFrame:RegisterEvent("UPDATE_EXHAUSTION")
betterExpBarEventFrame:RegisterEvent("PLAYER_LEVEL_UP")

-- Resting state changes (inn/city enter/leave), re-evaluating the rested overlay's GetRestState() gate.
betterExpBarEventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")

betterExpBarEventFrame:SetScript("OnEvent", function()
	ACAB:BetterExpBarOnEvent()
end)

-------------------------------------------------------------------------
-- Position reassert after combat / looting (DefaultBars.lua)
-------------------------------------------------------------------------

-- Native FrameXML may re-anchor wrapped native frames on its own; re-apply ours after combat and looting.
local positionReassertFrame = CreateFrame("Frame", "ACABPositionReassertFrame")
positionReassertFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
positionReassertFrame:RegisterEvent("LOOT_CLOSED")
positionReassertFrame:SetScript("OnEvent", function()
	ACAB:ReassertNativeElementPositions()
end)
