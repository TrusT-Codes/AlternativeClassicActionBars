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

	if not ACAB:CheckRequiredMods() then return end

	-- WaitForNativeBarSettle calls its callback as a plain function; the wrapper keeps RunLoginSequence's self.
	ACAB:WaitForNativeBarSettle(function()
		ACAB:RunLoginSequence()
	end)
end)

-------------------------------------------------------------------------
-- Custom-bar grid visibility (Button.lua)
-------------------------------------------------------------------------

local gridVisibilityFrame = CreateFrame("Frame")
gridVisibilityFrame:RegisterEvent("ACTIONBAR_SHOWGRID")
gridVisibilityFrame:RegisterEvent("ACTIONBAR_HIDEGRID")
gridVisibilityFrame:RegisterEvent("PET_BAR_SHOWGRID")
gridVisibilityFrame:RegisterEvent("PET_BAR_HIDEGRID")
gridVisibilityFrame:SetScript("OnEvent", function()
	-- Pet spell drags fire the PET_BAR_* pair instead of the ACTIONBAR_* pair.
	ACAB.isShowingActionGrid = (event == "ACTIONBAR_SHOWGRID" or event == "PET_BAR_SHOWGRID")

	-- must skip before login: bars aren't built yet
	if not ACAB.loginSequenceDone then return end

	ACAB:SweepCustomBarGridVisibility()
end)

-------------------------------------------------------------------------
-- Main Bar bonus-actionbar frame (DefaultBars.lua)
-------------------------------------------------------------------------

-- UPDATE_BONUS_ACTIONBAR covers bonus-page forms (Bear/Cat); PLAYER_AURAS_CHANGED catches the rest
-- (Travel/Aquatic), since UPDATE_SHAPESHIFT_FORM never fires on this client (env §4.12).
local mainBarBonusEventFrame = CreateFrame("Frame", "ACABMainBarBonusEventFrame")
mainBarBonusEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
mainBarBonusEventFrame:RegisterEvent("PLAYER_AURAS_CHANGED")

local lastDefaultBarStanceIndex = false

mainBarBonusEventFrame:SetScript("OnEvent", function()
	if event == "UPDATE_BONUS_ACTIONBAR" then
		-- must also run before login: the login sequence never hides BonusActionBarFrame itself
		ACAB:HideBonusActionBarFrame()

		-- must skip before login: ACABDB may still be another character's profile
		if ACAB.loginSequenceDone then
			ACAB:RefreshDefaultBarSlots()
		end

		lastDefaultBarStanceIndex = ACAB:GetActiveStanceIndex()
		return
	end

	-- PLAYER_AURAS_CHANGED fires on every aura change - only refresh when the active stance index changed.
	local stanceIndex = ACAB:GetActiveStanceIndex()

	if stanceIndex ~= lastDefaultBarStanceIndex then
		lastDefaultBarStanceIndex = stanceIndex

		-- must skip before login: ACABDB may still be another character's profile
		if ACAB.loginSequenceDone then
			ACAB:RefreshDefaultBarSlots()
		end
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
	if event == "UNIT_PET" and arg1 ~= "player" then return end

	-- must skip before login: ACABDB may still be another character's profile
	if not ACAB.loginSequenceDone then return end

	ACAB:RefreshPetBarVisibility()
end)

-------------------------------------------------------------------------
-- Stance/form set changes (PetStanceBars.lua)
-------------------------------------------------------------------------

-- UPDATE_SHAPESHIFT_FORMS: the available form set changed (kept registered despite env §4.12).
local stanceFormEventFrame = CreateFrame("Frame", "ACABStanceFormEventFrame")
stanceFormEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
stanceFormEventFrame:SetScript("OnEvent", function()
	-- must skip before login: ACABDB may still be another character's profile
	if not ACAB.activeProfileName then return end

	-- Native mode.
	ACAB:RebuildStanceBarContainer()

	-- Reparented native buttons only draw after the game's own refresh.
	if ACAB:IsStanceBarNativeModeEffective() then
		ShapeshiftBar_Update()
	end

	-- Styled mode: re-lay-out the pool bar if the live form count changed its shape.
	if ACAB:ApplyStanceBarLiveShape() then
		local styledBar = ACAB.bars and ACAB.bars[ACAB.STANCE_BAR_ID]

		if styledBar then
			ACAB:ApplyBarShape(styledBar)
		end

		ACAB:RefreshBarSettingsPage(ACAB.STANCE_BAR_ID)
	end

	-- Re-syncs bars 1-5's per-stance assignment rows on any already-built settings page.
	ACAB:RebuildAllDefaultBarAssignmentRows()
end)

-------------------------------------------------------------------------
-- Cast Bar position retry (NativeElements.lua)
-------------------------------------------------------------------------

-- Retries Cast Bar positioning on cast start until ACABDB.castBarPosition exists.
local castBarEventFrame = CreateFrame("Frame", "ACABCastBarEventFrame")
castBarEventFrame:RegisterEvent("UNIT_SPELLCAST_START")
castBarEventFrame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
castBarEventFrame:SetScript("OnEvent", function()
	-- must skip before login: a capture here would land in the wrong profile
	if not ACAB.loginSequenceDone then return end

	if not ACABDB or not ACABDB.castBarPosition then
		ACAB:ApplyCastBarPosition()
	end
end)

-------------------------------------------------------------------------
-- "Better Experience Bar" live updates (ExperienceBar.lua)
-------------------------------------------------------------------------

-- Always registered; no-ops until RunLoginSequence's ResolveActiveProfile sets activeProfileName.
local betterExpBarEventFrame = CreateFrame("Frame", "ACABBetterExpBarEventFrame")
betterExpBarEventFrame:RegisterEvent("PLAYER_XP_UPDATE")
betterExpBarEventFrame:RegisterEvent("UPDATE_EXHAUSTION")
betterExpBarEventFrame:RegisterEvent("PLAYER_LEVEL_UP")

-- Resting state changes (inn/city enter/leave), re-evaluating the rested overlay's GetRestState() gate.
betterExpBarEventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")

betterExpBarEventFrame:SetScript("OnEvent", function()
	if not ACAB.activeProfileName then return end

	ACAB:BetterExpBarOnEvent()
end)

-- Rested-pool calibration from the first rested kill's XP chat line (ExperienceBar.lua).
local restCalibrationFrame = CreateFrame("Frame", "ACABRestCalibrationFrame")
restCalibrationFrame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
restCalibrationFrame:SetScript("OnEvent", function()
	if not ACAB.activeProfileName then return end

	ACAB:CalibrateRestPoolFromXPMessage(arg1)
end)

-------------------------------------------------------------------------
-- Position reassert after combat / looting (DefaultBars.lua)
-------------------------------------------------------------------------

-- Native FrameXML may re-anchor wrapped native frames on its own; re-apply ours after combat.
local positionReassertFrame = CreateFrame("Frame", "ACABPositionReassertFrame")
positionReassertFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
positionReassertFrame:SetScript("OnEvent", function()
	-- must skip before login: moving native frames before the "native capture" stage stores wrong anchors
	if not ACAB.loginSequenceDone then return end

	ACAB:ReassertNativeElementPositions()
end)
