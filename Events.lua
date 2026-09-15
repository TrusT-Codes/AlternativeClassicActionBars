-- Events.lua
-- Addon-wide RegisterEvent watcher frames: small, self-contained units
-- that each react to one global game event and call into another file's
-- function. Loads last among the .lua files - a CreateFrame+RegisterEvent
-- call doesn't need its handler's callees to exist at parse time, only
-- when the event actually fires, long after every file has loaded.
--
-- Per-instance self-registration (e.g. Button.lua's Init(), which
-- registers ~14 events per button on that button's own frame) stays put
-- in its owning file - this file is only for frames that aren't tied to
-- a single object instance.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Login / logout (Core.lua)
-------------------------------------------------------------------------

-- PLAYER_ENTERING_WORLD (not PLAYER_LOGIN) so the native MainMenuBar
-- cluster's own layout pass has more room to finish before the settle
-- poll starts measuring. Unregistered after the first fire.
local loadFrame = CreateFrame("Frame")
loadFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
loadFrame:RegisterEvent("PLAYER_LOGOUT")

loadFrame:SetScript("OnEvent", function()
	if event == "PLAYER_LOGOUT" then
		ACAB:SaveActiveProfileData()
		return
	end

	loadFrame:UnregisterEvent("PLAYER_ENTERING_WORLD")

	-- ACAB:WaitForNativeBarSettle calls its callback as a plain function
	-- (not a colon call) - forwarded through this wrapper so
	-- ACAB:RunLoginSequence still receives `self` correctly.
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

-- UPDATE_BONUS_ACTIONBAR fires whenever the player's stance/form/stealth
-- state changes - see ACAB:HideBonusActionBarFrame's own comment
-- (DefaultBars.lua) for why BonusActionBarFrame needs independent
-- hide+neuter treatment.
local mainBarBonusEventFrame = CreateFrame("Frame", "ACABMainBarBonusEventFrame")
mainBarBonusEventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
mainBarBonusEventFrame:SetScript("OnEvent", function()
	ACAB:HideBonusActionBarFrame()
	ACAB:RefreshMainBarSlots()
end)

-------------------------------------------------------------------------
-- Pet Bar visibility (DefaultBars.lua)
-------------------------------------------------------------------------

-- Event names are the same candidates flagged in the feature's own design
-- doc as needing live confirmation on this client (PET_BAR_UPDATE, UNIT_PET,
-- PLAYER_CONTROL_LOST/GAINED) - RegisterEvent on a name that turns out not
-- to fire on this client degrades to "Pet Bar only re-checks visibility on
-- login/target-change", not an error.
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
-- Stance/form changes (PetStanceBars.lua)
-------------------------------------------------------------------------

-- UPDATE_SHAPESHIFT_FORMS is real vanilla 1.12.1's own FrameXML event
-- (stock ShapeshiftBar.lua registers it and calls ShapeshiftBar_Update()
-- in response) - fires whenever the player's available stance/form set
-- changes, e.g. a talent respec unlocking a new form, or a zone/buff
-- granting/removing one.
local stanceFormEventFrame = CreateFrame("Frame", "ACABStanceFormEventFrame")
stanceFormEventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
stanceFormEventFrame:SetScript("OnEvent", function()
	ACAB:RebuildStanceBarContainer()

	-- Styled mode: re-syncs cfg.buttonCount/cols/rows against the new live
	-- form count and re-lays-out the pool bar's grid if it actually
	-- changed - the styled-mode equivalent of RebuildStanceBarContainer
	-- above (which only affects native mode).
	if ACAB:ApplyStanceBarLiveShape() then
		local styledBar = ACAB.bars and ACAB.bars[ACAB.STANCE_BAR_ID]

		if styledBar then
			ACAB:ApplyBarShape(styledBar)
		end

		if ACAB.RefreshBarSettingsPage then
			ACAB:RefreshBarSettingsPage(ACAB.STANCE_BAR_ID)
		end
	end

	-- Stance/Page Bar Assignment feature, Part 2: the General panel's
	-- per-stance assignment rows are built from this same
	-- GetNumShapeshiftForms() count - re-sync them too if the panel
	-- already exists this session, so a mid-session talent respec that
	-- changes the player's stance count doesn't leave stale rows behind.
	if ACAB.RebuildMainBarAssignmentRows then
		ACAB:RebuildMainBarAssignmentRows()
	end
end)

-------------------------------------------------------------------------
-- Cast Bar position retry (NativeElements.lua)
-------------------------------------------------------------------------

-- Re-attempts position capture the first time CastingBarFrame becomes
-- visible this session.
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

-- All 4 events are kept unconditionally registered regardless of whether
-- "Enable Better Experience Bar" is currently on, or which of its 5
-- segment toggles are - simpler and safer than churning registration on
-- every checkbox click. ACAB:BetterExpBarOnEvent's own callees are
-- nil-safe (ACAB.betterExpBarText may not exist yet) and gate themselves
-- on ACABDB.betterExpBarEnabled, so this is a harmless no-op for
-- however long the feature stays off.
local betterExpBarEventFrame = CreateFrame("Frame", "ACABBetterExpBarEventFrame")
betterExpBarEventFrame:RegisterEvent("PLAYER_XP_UPDATE")
betterExpBarEventFrame:RegisterEvent("UPDATE_EXHAUSTION")
betterExpBarEventFrame:RegisterEvent("PLAYER_LEVEL_UP")

-- PLAYER_UPDATE_RESTING is the real vanilla event that fires when the
-- player's resting state itself changes (entering/leaving an inn or
-- city) - needed so ACAB:ApplyExpBarRestedOverlay's GetRestState() gate
-- re-evaluates the instant resting starts/stops, not just on the next
-- XP/exhaustion change.
betterExpBarEventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")

betterExpBarEventFrame:SetScript("OnEvent", function()
	ACAB:BetterExpBarOnEvent()
end)

-------------------------------------------------------------------------
-- Position reassert after combat / looting (DefaultBars.lua)
-------------------------------------------------------------------------

-- MainMenuBarPerformanceBarFrame (Latency Bar) and KeyRingButton wrap a
-- single real native Blizzard frame directly - see
-- ACAB:ReassertNativeElementPositions' own comment (DefaultBars.lua) for
-- why this reassert exists. Triggered on PLAYER_REGEN_ENABLED (leaving
-- combat) and LOOT_CLOSED (the loot window closing).
local positionReassertFrame = CreateFrame("Frame", "ACABPositionReassertFrame")
positionReassertFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
positionReassertFrame:RegisterEvent("LOOT_CLOSED")
positionReassertFrame:SetScript("OnEvent", function()
	ACAB:ReassertNativeElementPositions()
end)
