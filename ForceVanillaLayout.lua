-- ForceVanillaLayout.lua
-- Force Vanilla Layout Mode: applying the toggle and the reset-everything-to-vanilla cascade (also run by the
-- layout baseline pass). Runtime only.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Force Vanilla Layout Mode
-------------------------------------------------------------------------

-- Applies a "Force Vanilla Layout Mode" change: persists it, re-gates every built page, and (only when
-- switching on) runs the full reset-to-Vanilla-Layout cascade.
function ACAB:ApplyUseDefaultLayoutChange(checked)
	local wasDefault = ACABDB.useDefaultLayout == true
	ACABDB.useDefaultLayout = checked
	ACAB:RefreshDefaultLayoutGatingOnAllPages()
	ACAB:ApplyAllDefaultBars()

	-- Draggability depends on useDefaultLayout, so the edit-mode overlays refresh too.
	ACAB:ApplyDefaultLayoutEditVisual()

	local styledPetOrStance = false

	if (not wasDefault) and checked then
		local petCfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
		local stanceCfg = ACABDB.defaultBars[ACAB.STANCE_BAR_ID]
		styledPetOrStance = (petCfg and petCfg.useNativePetBar ~= true) or
			(stanceCfg and stanceCfg.useNativeStanceBar ~= true) or false

		ACAB:ResetAllElementsToVanillaLayout()

		-- Clears the modern-style/global-override flags (the Setup Wizard's shared cascade keeps them).
		ACABDB.modernBorderStyle = false
		ACABDB.globalSpacingEnabled = false
		ACABDB.globalButtonSizeEnabled = false

		-- Re-syncs built pages from the values the resets just wrote.
		ACAB:RefreshDefaultLayoutGatingOnAllPages()
	end

	-- Runs after the reset cascade: on forces vanilla styling, off re-applies the stored modernBorderStyle.
	ACAB:ApplyGlobalButtonStyle()

	-- Both no-op while useDefaultLayout is on; re-running them restores a locked-out override when off.
	ACAB:ApplyGlobalSpacing()
	ACAB:ApplyGlobalButtonSize()
	ACAB:RefreshGeneralPanel()
	ACAB:RefreshAllBarPagesGlobalOverrideGating()

	-- Styled-to-native Pet/Stance switch only takes effect after a reload, same as the Use Vanilla checkbox.
	if styledPetOrStance then
		ACAB:ShowDialog({
			title = "Force Vanilla Layout",
			message = "The Pet Bar and Stance Bar switch to their vanilla style, which rebuilds their " ..
				"buttons and requires a UI reload.",
			mode = "confirm",
			buttons = {
				{
					text = "Reload Now",
					isDefault = true,
					onClick = function()
						ReloadUI()
					end,
				},
				{
					text = "Later",
					onClick = function() end,
				},
			},
		})
	end
end

-- Resets every default-bar-family id and native element to its captured native layout and disables the
-- Extra Bars. Shared with the Setup Wizard's "Keep Vanilla Layout" choice, so it leaves
-- modernBorderStyle/globalSpacingEnabled/globalButtonSizeEnabled alone.
function ACAB:ResetAllElementsToVanillaLayout()
	local i
	for i = 1, table.getn(ACAB.DEFAULT_BAR_IDS) do
		ACAB:ResetDefaultBarLayout(ACAB.DEFAULT_BAR_IDS[i])
	end

	-- Bars 2-5's enabled state follows the native "Show ... Action Bar" checkboxes.
	if ACAB.ReconcileDefaultBarEnabledFromNative then
		ACAB:ReconcileDefaultBarEnabledFromNative()
	end

	-- Extra Bars (6-9) have no vanilla equivalent: disabled and reset.
	local extraId
	for extraId = ACAB.EXTRA_BAR_ID_START, ACAB.EXTRA_BAR_ID_START + ACAB.EXTRA_BAR_COUNT - 1 do
		ACAB:SetExtraBarEnabled(extraId, false)
		ACAB:ResetExtraBarLayout(extraId)

		if ACAB.settingsFrame and ACAB.settingsFrame.pages[extraId] then
			ACAB:RefreshBarSettingsPage(extraId)
		end
	end

	ACAB:RefreshBarList()

	-- Layout before position for each element: position converts to canonical at the final size/scale.
	if ACAB.ResetBagBarLayout then
		ACAB:ResetBagBarLayout()
	end

	if ACAB.ResetBagBarPosition then
		ACAB:ResetBagBarPosition()
	end

	if ACAB.ResetMicroMenuLayout then
		ACAB:ResetMicroMenuLayout()
	end

	if ACAB.ResetMicroMenuPosition then
		ACAB:ResetMicroMenuPosition()
	end

	-- Must set the native-mode flags before the containers below are built/reset, or Pet/Stance Bar
	-- overlap Action Bar 1/2 on the Setup Wizard's path.
	do
		local petCfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
		if petCfg then
			petCfg.useNativePetBar = true
			petCfg.condenseEmptyPetSlots = false
		end

		local stanceCfg = ACABDB.defaultBars[ACAB.STANCE_BAR_ID]
		if stanceCfg then
			stanceCfg.useNativeStanceBar = true
		end
	end

	-- The native containers may not exist yet this session (it can boot styled).
	if ACAB.CreatePetBarNativeContainer then
		ACAB:CreatePetBarNativeContainer()
	end

	if ACAB.CreateStanceBarContainer then
		ACAB:CreateStanceBarContainer()
	end

	if ACAB.ResetStanceBarLayout then
		ACAB:ResetStanceBarLayout()
	end

	if ACAB.ResetStanceBarPosition then
		ACAB:ResetStanceBarPosition()
	end

	if ACAB.ResetLatencyBarLayout then
		ACAB:ResetLatencyBarLayout()
	end

	-- Also restores castBarUsesDefaultPosition (dynamic stacking).
	if ACAB.ResetCastBarLayout then
		ACAB:ResetCastBarLayout()
	end

	if ACAB.ResetKeyRingPosition then
		ACAB:ResetKeyRingPosition()
	end

	-- Key Ring ships visible on vanilla.
	if ACAB.SetKeyRingEnabled then
		ACAB:SetKeyRingEnabled(true)
	end

	-- Vanilla always shows Blizzard's bar art.
	ACABDB.mainBarArtMode = ACAB.MAIN_BAR_ART_MODE_FULL

	if ACAB.ApplyBlizzardArtVisibility then
		ACAB:ApplyBlizzardArtVisibility()
	end

	-- Paging and stance swap ship on in vanilla.
	if ACAB.SetDefaultBarPaginationEnabled then
		ACAB:SetDefaultBarPaginationEnabled(true)
	end

	if ACAB.SetDefaultBarStanceSwapEnabled then
		ACAB:SetDefaultBarStanceSwapEnabled(true)
	end

	if ACAB.ResetExpBarLayout then
		ACAB:ResetExpBarLayout()
	end

	if ACAB.ResetPageIndicatorLayout then
		ACAB:ResetPageIndicatorLayout()
	end

	-- Native-mode Pet Bar (ResetDefaultBarLayout above can't act without ACAB.bars[PET_BAR_ID]).
	if ACAB.ResetPetBarNativeLayout then
		ACAB:ResetPetBarNativeLayout()
	end

	-- Must run dead last: Stance Bar's Y depends on bar 2's final state, or it can land behind Bar 1.
	if ACAB.ReflowStanceBarForBar2Toggle then
		local bar2Cfg = ACABDB.defaultBars and ACABDB.defaultBars[2]
		ACAB:ReflowStanceBarForBar2Toggle(bar2Cfg and bar2Cfg.enabled)
	end
end
