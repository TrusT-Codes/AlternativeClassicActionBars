-- SettingsGeneral.lua
-- General/Profiles/Edit Mode tab panels split out of Settings.lua
-- (GetOrCreateGeneralPanel/RefreshGeneralPanel, GetOrCreateProfilesPanel/
-- RefreshProfilesPanel, GetOrCreateEditModePanel/RefreshEditModePanel), the
-- tab/view switchers (ShowBarsView/ShowGeneralView/ShowProfilesView/
-- ShowEditModeView/RefreshActiveTabHighlight), and the General tab's
-- dynamic checkbox/slider reflow helpers (ReflowStack/
-- ReflowGeneralOverrideSliders/ReflowGeneralHotkeySection).
--
-- Engine-invoked script handlers (OnClick, OnEvent, OnEnter, OnLeave, ...)
-- receive the frame via the global `this`, never as a `self` parameter.

local ACAB = AlternativeClassicActionBars

function ACAB:GetOrCreateGeneralPanel()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	if ACAB.settingsFrame.generalPanel then
		return ACAB.settingsFrame.generalPanel
	end

	-- Own dedicated scrollframe+scrollchild pair (ACAB:CreateWideContentScrollFrame)
	-- - see CreateSettingsFrame's own comment on why this doesn't share
	-- the Bars view's contentScrollFrame.
	local scrollFrame, panel = ACAB:CreateWideContentScrollFrame("ACABSettingsGeneralScrollFrame")

	ACAB.settingsFrame.generalScrollFrame = scrollFrame
	scrollFrame:Hide()

	local title = panel:CreateFontString(
		nil,
		"OVERLAY",
		"GameFontNormalLarge"
	)

	title:SetPoint(
		"TOPLEFT",
		panel,
		"TOPLEFT",
		ACAB.INDENT_SECTION,
		-14
	)

	title:SetText("General Settings")

	-- OnClick is wired separately below, since its dialog's "OK" button
	-- closes over this same `checkbox` local - inlined into the factory
	-- call's own config table, that reference would resolve before the
	-- local exists.
	local checkbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralUseDefaultLayoutCheckbox", {
		anchor = { "TOPLEFT", panel, "TOPLEFT", ACAB.INDENT_SECTION, -52 },
		label = "Force default Blizzard layout mode",
		tooltip = {
			title = "Force default Blizzard layout mode",
			lines = {
				"When enabled, default action bars keep Blizzard's native " ..
				"position, size, and layout, and can only be shown/hidden - " ..
				"dragging and resizing them is disabled.",
				"Disable this to freely reposition, resize, and drag default " ..
				"bars like custom bars.",
			},
		},
	})

	checkbox:SetScript(
		"OnClick",
		function()
			local checked = this:GetChecked() and true or false
			local wasDefault = ACABDB.useDefaultLayout == true

			-- Turning ON resets every bar to Blizzard default - warn and
			-- confirm before that cascade runs. Revert the checkbox's own
			-- visual state immediately so it stays unchecked while the
			-- dialog is open; ApplyUseDefaultLayoutChange re-checks it
			-- only if the user accepts.
			if checked and not wasDefault then
				this:SetChecked(false)

				ACAB:ShowDialog({
					title = "Force default Blizzard layout mode",
					message = "Enabling this will reset ALL bars to their " ..
						"default Blizzard position.",
					warningText = "This action cannot be undone.",
					mode = "confirm",
					buttons = {
						{
							text = "OK",
							isDefault = true,
							onClick = function()
								checkbox:SetChecked(true)
								ACAB:ApplyUseDefaultLayoutChange(true)
							end,
						},
						{
							text = "Cancel",
							danger = true,
							onClick = function() end,
						},
					},
				})

				return
			end

			ACAB:ApplyUseDefaultLayoutChange(checked)
		end
	)

	panel.useDefaultLayoutCheckbox = checkbox

	-------------------------------------------------------------------------
	-- Tint whole button on out of range: real Blizzard buttons only tint
	-- the hotkey text red, never the whole icon - this addon has always
	-- tinted the whole icon (ACABDB.tintWholeButtonOnRange, default
	-- true), so this checkbox opts into the native-accurate hotkey-only
	-- behavior.
	-------------------------------------------------------------------------

	local tintWholeButtonCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralTintWholeButtonCheckbox", {
		anchor = { "TOPLEFT", checkbox, "BOTTOMLEFT", 0, -14 },
		label = "Tint whole button on out of range",
		onClick = function()
			local checked = this:GetChecked() and true or false

			ACABDB.tintWholeButtonOnRange = checked

			-- Live: immediately re-sweeps every live button's range/
			-- usability tint rather than waiting on the next natural
			-- UpdateRange trigger (the 0.2s self-healing ticker or the
			-- next real event) - mirrors ACAB:ToggleAlwaysShowMultibars'
			-- own immediate-sweep pattern (Button.lua) rather than this
			-- toggle silently doing nothing until something else happens
			-- to re-run UpdateRange.
			ACAB:SweepAllButtonRangeTint()
		end,
	})

	panel.tintWholeButtonCheckbox = tintWholeButtonCheckbox

	-------------------------------------------------------------------------
	-- Disable Blizzard Art
	--
	-- Hides MainMenuBarArtFrame (DefaultBars.lua's
	-- ApplyBlizzardArtVisibility) - styled/positioned exactly like the two
	-- checkboxes above, anchored off tintWholeButtonCheckbox the same
	-- BOTTOMLEFT-chain way.
	-------------------------------------------------------------------------

	local disableBlizzardArtCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralDisableBlizzardArtCheckbox", {
		anchor = { "TOPLEFT", tintWholeButtonCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Disable Blizzard Art",
		onClick = function()
			local checked = this:GetChecked() and true or false

			ACABDB.disableBlizzardArt = checked

			ACAB:ApplyBlizzardArtVisibility()
		end,
	})

	panel.disableBlizzardArtCheckbox = disableBlizzardArtCheckbox

	-------------------------------------------------------------------------
	-- Main Bar pagination / stance-swap
	--
	-- Both default true (Core.lua's EnsureDB), matching real vanilla bar
	-- 1's own always-on behavior unless the user explicitly opts out here.
	-- Styled/positioned exactly like the three checkboxes above, chained
	-- off disableBlizzardArtCheckbox the same BOTTOMLEFT way.
	-------------------------------------------------------------------------

	local mainBarPaginationCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralMainBarPaginationCheckbox", {
		anchor = { "TOPLEFT", disableBlizzardArtCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Main Bar: Shift/Ctrl Page Swapping",
		tooltip = {
			title = "Main Bar: Shift/Ctrl Page Swapping",
			lines = {
				"When enabled, shows new Options inside MainBar on Bars " ..
				"Settings Page. You will be able to freely assign any Extra " ..
				"Bar to your Pageing Function of Mainbar. Enabling it will " ..
				"also enable the Paging UI Element.",
				"When disabled, your MainBar will always stay the same and " ..
				"the Paging UI Element is hidden.",
			},
		},
		onClick = function()
			local checked = this:GetChecked() and true or false

			ACAB:SetMainBarPaginationEnabled(checked)

			-- The Page Bar assignment row (only meaningful while pagination
			-- is on) and bar 1's own Page Indicator Scale slider both
			-- appear/disappear live the instant this checkbox is clicked.
			ACAB:RebuildMainBarAssignmentRows()
			ACAB:RefreshMainBarPageIndicatorControlsVisibility()
		end,
	})

	panel.mainBarPaginationCheckbox = mainBarPaginationCheckbox

	local mainBarStanceSwapCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralMainBarStanceSwapCheckbox", {
		anchor = { "TOPLEFT", mainBarPaginationCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Main Bar: Stance/Form/Stealth Swapping",
		tooltip = {
			title = "Main Bar: Stance/Form/Stealth Swapping",
			lines = {
				"When enabled, shows new Options inside MainBar on Bars " ..
				"Settings Page. You will be able to freely assign any Extra " ..
				"Bar to your different Shapes / Forms to swap the contents " ..
				"of Mainbar with automatically.",
				"When disabled, your MainBar will always stay the same.",
			},
		},
		onClick = function()
			local checked = this:GetChecked() and true or false

			ACAB:SetMainBarStanceSwapEnabled(checked)

			-- The per-stance assignment rows (bar 1's own settings page)
			-- appear/disappear live the instant this checkbox is clicked,
			-- exactly like the pagination checkbox above does for the Page
			-- Bar row.
			ACAB:RebuildMainBarAssignmentRows()
		end,
	})

	panel.mainBarStanceSwapCheckbox = mainBarStanceSwapCheckbox

	-- Stance / Page Bar Assignment rows live on bar 1's own settings page
	-- (GetOrCreateBarPage/RebuildMainBarAssignmentRows) alongside that
	-- page's Page Indicator Scale slider, since they're bar 1-specific
	-- rather than general addon-wide settings. The two checkboxes above
	-- still live on this General tab and drive those rows via
	-- ACAB:RebuildMainBarAssignmentRows.

	-------------------------------------------------------------------------
	-- Macro text toggle + font size (both bars, live)
	-------------------------------------------------------------------------

	local macroTextCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralMacroTextCheckbox", {
		anchor = { "TOPLEFT", mainBarStanceSwapCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Toggle Macro Text",
		onClick = function()
			local checked = this:GetChecked() and true or false

			ACAB:SetMacroTextEnabled(checked)
			ACAB:RefreshGeneralPanel()
		end,
	})

	panel.macroTextCheckbox = macroTextCheckbox

	local macroTitle = panel:CreateFontString(
		nil,
		"OVERLAY",
		"GameFontNormal"
	)

	macroTitle:SetPoint(
		"TOPLEFT",
		macroTextCheckbox,
		"BOTTOMLEFT",
		8,
		-10
	)

	macroTitle:SetText(
		"Macro Text Size (" .. tostring(ACAB.FONT_SIZE_MIN) ..
		" to " .. tostring(ACAB.FONT_SIZE_MAX) .. ")"
	)

	-- Exposed so ApplySettingsHeightFromCandidates' warm-up read pass can
	-- reach this static anchor - see its own comment for why.
	panel.macroTitle = macroTitle

	-- Placeholder initial text only - RefreshGeneralPanel (called by
	-- ShowGeneralView every time this view is shown) overwrites this with
	-- the real saved value before the panel is ever visible.
	local macroSlider, macroValueText = ACAB:CreateLabeledSlider(
		panel,
		"ACABGeneralMacroFontSizeSlider",
		{
			width = 260,
			anchor = { "TOPLEFT", macroTitle, "BOTTOMLEFT", ACAB.INDENT_INPUT - ACAB.INDENT_SECTION, -12 },
			min = ACAB.FONT_SIZE_MIN,
			max = ACAB.FONT_SIZE_MAX,
			step = ACAB.FONT_SIZE_STEP,
			lowText = tostring(ACAB.FONT_SIZE_MIN),
			highText = tostring(ACAB.FONT_SIZE_MAX),
			initialText = tostring(ACAB.FONT_SIZE_MIN),
			round = function(value) return math.floor(value + 0.5) end,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					ACAB:SetMacroFontSize(value)
				end
			end,
		}
	)

	panel.macroValueText = macroValueText
	panel.macroSlider = macroSlider

	local macroResetButton = ACAB:CreateResetButton(panel, {
		anchor = { "LEFT", macroSlider, "RIGHT", 16, 4 },
		minWidth = 90,
		maxWidth = 90,
		text = "Reset",
		onClick = function()
			if not ACAB.NATIVE_MACRO_FONT then
				return
			end

			local size = ACAB:ClampFontSize(ACAB.NATIVE_MACRO_FONT.size)

			ACAB:SetMacroFontSize(size)

			panel.macroSlider.suppressApply = true
			panel.macroSlider:SetValue(size)
			panel.macroValueText:SetText(tostring(size))
			panel.macroSlider.suppressApply = nil
		end,
	})

	panel.macroResetButton = macroResetButton

	-------------------------------------------------------------------------
	-- Hotkey / Count text font size (both bars, live sliders). Global, not
	-- per-button - one setting governs every button's hotkey/count text.
	-- Mirrors a bar page's Button Size slider: live value readout, integer
	-- min/max captions, immediate OnValueChanged, "Reset to Default"
	-- restores the captured native size (Button.lua's NATIVE_HOTKEY_FONT/
	-- NATIVE_COUNT_FONT).
	--
	-- Anchored via a real anchor chain off the tint-whole-button checkbox
	-- (BOTTOMLEFT -> TOPLEFT), not a computed pixel-Y offset, so it follows
	-- wherever the checkbox's real bottom edge lands.
	-------------------------------------------------------------------------

	local hotkeyTitle = panel:CreateFontString(
		nil,
		"OVERLAY",
		"GameFontNormal"
	)

	-- Placeholder anchor - ACAB:ReflowGeneralHotkeySection re-anchors this
	-- live once the macro section's Shown state is known.
	hotkeyTitle:SetPoint(
		"TOPLEFT",
		macroTextCheckbox,
		"BOTTOMLEFT",
		8,
		-22
	)

	hotkeyTitle:SetText(
		"Hotkey Text Size (" .. tostring(ACAB.FONT_SIZE_MIN) ..
		" to " .. tostring(ACAB.FONT_SIZE_MAX) .. ")"
	)

	-- Exposed so ApplySettingsHeightFromCandidates' warm-up read pass can
	-- reach this static anchor - see its own comment for why.
	panel.hotkeyTitle = hotkeyTitle

	-- Placeholder initial text only - RefreshGeneralPanel (called by
	-- ShowGeneralView every time this view is shown) overwrites this with
	-- the real saved/native value before the panel is ever visible.
	local hotkeySlider, hotkeyValueText = ACAB:CreateLabeledSlider(
		panel,
		"ACABGeneralHotkeyFontSizeSlider",
		{
			width = 260,
			anchor = { "TOPLEFT", hotkeyTitle, "BOTTOMLEFT", ACAB.INDENT_INPUT - ACAB.INDENT_SECTION, -12 },
			min = ACAB.FONT_SIZE_MIN,
			max = ACAB.FONT_SIZE_MAX,
			step = ACAB.FONT_SIZE_STEP,
			lowText = tostring(ACAB.FONT_SIZE_MIN),
			highText = tostring(ACAB.FONT_SIZE_MAX),
			initialText = tostring(ACAB.FONT_SIZE_MIN),
			round = function(value) return math.floor(value + 0.5) end,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					ACAB:SetHotkeyFontSize(value)
				end
			end,
		}
	)

	panel.hotkeyValueText = hotkeyValueText
	panel.hotkeySlider = hotkeySlider

	local hotkeyResetButton = ACAB:CreateResetButton(panel, {
		anchor = { "LEFT", hotkeySlider, "RIGHT", 16, 4 },
		minWidth = 90,
		maxWidth = 90,
		text = "Reset",
		onClick = function()
			-- Nothing captured yet (no button created this session) - no
			-- native size to restore to, so this is a no-op rather than a
			-- guessed fallback value.
			if not ACAB.NATIVE_HOTKEY_FONT then
				return
			end

			-- ClampFontSize rounds as well as clamps, so this Reset
			-- button's displayed text never shows a raw GetFont()-precision
			-- decimal.
			local size = ACAB:ClampFontSize(ACAB.NATIVE_HOTKEY_FONT.size)

			ACAB:SetHotkeyFontSize(size)

			panel.hotkeySlider.suppressApply = true
			panel.hotkeySlider:SetValue(size)
			panel.hotkeyValueText:SetText(tostring(size))
			panel.hotkeySlider.suppressApply = nil
		end,
	})

	panel.hotkeyResetButton = hotkeyResetButton

	-------------------------------------------------------------------------
	-- Count text font size - identical structure to Hotkey Text Size above,
	-- anchored off it the same anchor-chain way.
	-------------------------------------------------------------------------

	local countTitle = panel:CreateFontString(
		nil,
		"OVERLAY",
		"GameFontNormal"
	)

	-- WARNING: anchor off hotkeyTitle (fixed left edge), not hotkeyValueText
	-- - hotkeyValueText's "TOP" anchor centers under hotkeySlider, so its
	-- LEFT edge drifts with the displayed digit count/width. Y offset is
	-- computed (title -> slider -> value-text -> gap spacing) rather than
	-- hardcoded, since GameFontNormalSmall's pixel height isn't known.
	countTitle:SetPoint(
		"TOPLEFT",
		hotkeyTitle,
		"BOTTOMLEFT",
		0,
		-12 - hotkeySlider:GetHeight() - 2 - hotkeyValueText:GetHeight() - 18
	)

	countTitle:SetText(
		"Item Count Text Size (" .. tostring(ACAB.FONT_SIZE_MIN) ..
		" to " .. tostring(ACAB.FONT_SIZE_MAX) .. ")"
	)

	-- Exposed so ApplySettingsHeightFromCandidates' warm-up read pass can
	-- reach this static anchor - see its own comment for why.
	panel.countTitle = countTitle

	local countSlider, countValueText = ACAB:CreateLabeledSlider(
		panel,
		"ACABGeneralCountFontSizeSlider",
		{
			width = 260,
			anchor = { "TOPLEFT", countTitle, "BOTTOMLEFT", ACAB.INDENT_INPUT - ACAB.INDENT_SECTION, -12 },
			min = ACAB.FONT_SIZE_MIN,
			max = ACAB.FONT_SIZE_MAX,
			step = ACAB.FONT_SIZE_STEP,
			lowText = tostring(ACAB.FONT_SIZE_MIN),
			highText = tostring(ACAB.FONT_SIZE_MAX),
			initialText = tostring(ACAB.FONT_SIZE_MIN),
			round = function(value) return math.floor(value + 0.5) end,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					ACAB:SetCountFontSize(value)
				end
			end,
		}
	)

	panel.countValueText = countValueText
	panel.countSlider = countSlider

	local countResetButton = ACAB:CreateResetButton(panel, {
		anchor = { "LEFT", countSlider, "RIGHT", 16, 4 },
		minWidth = 90,
		maxWidth = 90,
		text = "Reset",
		onClick = function()
			if not ACAB.NATIVE_COUNT_FONT then
				return
			end

			-- ClampFontSize rounds as well as clamps - see the Hotkey
			-- Reset button's matching comment above.
			local size = ACAB:ClampFontSize(ACAB.NATIVE_COUNT_FONT.size)

			ACAB:SetCountFontSize(size)

			panel.countSlider.suppressApply = true
			panel.countSlider:SetValue(size)
			panel.countValueText:SetText(tostring(size))
			panel.countSlider.suppressApply = nil
		end,
	})

	panel.countResetButton = countResetButton

	-------------------------------------------------------------------------
	-- Global border/spacing style: one checkbox choosing the button border
	-- for ALL bars (default 1-5 AND extra 6-9) - "modern" (backdrop
	-- border) or "vanilla" (native Blizzard border). Also shifts every
	-- bar's button size (and spacing, opposite direction) to keep
	-- default/extra bars aligned - see ACAB:ApplyGlobalButtonStyle
	-- (Bar.lua). Locked to vanilla while "Force default Blizzard layout mode" is on.
	-------------------------------------------------------------------------

	-- Anchors off countTitle (a fixed-X FontString) with the exact offset
	-- the removed Snap to Adjacent Elements checkbox used to occupy (now
	-- on the Edit Mode tab's own panel) - same reasoning as that anchor's
	-- own comment: countValueText's "TOP" anchor shifts with the displayed
	-- digit count/width, so it can't be anchored off directly.
	local modernBorderStyleCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralModernBorderStyleCheckbox", {
		anchor = { "TOPLEFT", countTitle, "BOTTOMLEFT", 0, -12 - countSlider:GetHeight() - 2 - countValueText:GetHeight() - 18 },
		label = "Use Modern Button Style",
		tooltip = {
			title = "Use Modern Button Style",
			lines = {
				"Choose the button border style used by ALL bars. When " ..
				"enabled use a slick and thin modern rectangular Border, " ..
				"when disabled use the default vanilla UI border.",
				"Locked to vanilla UI Border while 'Force default Blizzard " ..
				"layout mode' is enabled",
			},
		},
		onClick = function()
			-- Belt-and-suspenders re-check, mirrors this addon's existing
			-- convention (e.g. Button.lua's OnMouseWheel re-checking
			-- useDefaultLayout) - RefreshGeneralPanel's own gating below
			-- is what actually prevents this OnClick from firing in the
			-- normal case (EnableMouse(false) while locked).
			if ACABDB.useDefaultLayout ~= false then
				this:SetChecked(false)
				return
			end

			ACABDB.modernBorderStyle = this:GetChecked() and true or false

			ACAB:ApplyGlobalButtonStyle()

			-- The global spacing/buttonSize overrides' last-applied real
			-- value was computed under whatever style was active at the
			-- time - re-run them now so a switch immediately recomputes
			-- for the new style's floor, instead of staying stale until
			-- the global slider itself is next touched.
			ACAB:ApplyGlobalSpacing()
			ACAB:ApplyGlobalButtonSize()

			ACAB:RefreshDefaultLayoutGatingOnAllPages()

			-- Re-syncs the global spacing slider's displayed value/range/
			-- labels to the new floor (RefreshGeneralPanel wasn't
			-- otherwise called from this handler).
			ACAB:RefreshGeneralPanel()
		end,
	})

	panel.modernBorderStyleCheckbox = modernBorderStyleCheckbox

	-------------------------------------------------------------------------
	-- Global Spacing / global ButtonSize overrides: unlike other controls
	-- in this panel, these sliders are Shown/Hidden per the checkbox's
	-- checked state. Applies to every bar (default 1-5, extra 6-9, Pet Bar,
	-- Stance Bar), never simple/native-backed pages - see
	-- ACAB:ApplyGlobalSpacing/ApplyGlobalButtonSize (Bar.lua). Both also
	-- lock (dim) whenever useDefaultLayout forces vanilla styling. Any bar
	-- can opt out individually via its own lock icon next to its Spacing/
	-- ButtonSize slider (SettingsBars.lua's per-bar lock toggle).
	-------------------------------------------------------------------------

	-- OnClick is wired further below - it closes over the slider/labels
	-- this function creates next.
	local globalSpacingCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralGlobalSpacingCheckbox", {
		anchor = { "TOPLEFT", modernBorderStyleCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Toggle global Spacing",
		tooltip = {
			title = "Toggle global Spacing",
			lines = {
				"When enabled, disables the Option to set Spacing on " ..
				"individual bars.",
				"Instead shows a new Slider to set the Spacing globally for " ..
				"every bar. Unlock a bar's own lock icon to exempt it.",
			},
		},
	})

	-- Min/max/end-labels aren't set here - RefreshGeneralPanel recomputes
	-- and applies them live, since the border-style offset they depend on
	-- can change after this panel is built.
	local globalSpacingSlider, globalSpacingValueText, globalSpacingSliderLow, globalSpacingSliderHigh = ACAB:CreateLabeledSlider(
		panel,
		"ACABGeneralGlobalSpacingSlider",
		{
			anchor = { "TOPLEFT", globalSpacingCheckbox, "BOTTOMLEFT", 20, -28 },
			step = ACAB.SPACING_STEP,
			initialText = "0",
			round = function(value) return math.floor(value + 0.5) end,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					ACABDB.globalSpacingValue = value
					ACAB:ApplyGlobalSpacing()
				end
			end,
		}
	)

	globalSpacingCheckbox:SetScript(
		"OnClick",
		function()
			if ACABDB.useDefaultLayout ~= false then
				this:SetChecked(false)
				return
			end

			local checked = this:GetChecked() and true or false

			ACABDB.globalSpacingEnabled = checked

			globalSpacingSlider:SetShown(checked)
			globalSpacingValueText:SetShown(checked)

			if checked then
				ACAB:ApplyGlobalSpacing()
			end

			ACAB:ReflowGeneralOverrideSliders(panel)
			ACAB:RefreshAllBarPagesGlobalOverrideGating()
		end
	)

	panel.globalSpacingCheckbox = globalSpacingCheckbox
	panel.globalSpacingSlider = globalSpacingSlider
	panel.globalSpacingSliderLow = globalSpacingSliderLow
	panel.globalSpacingSliderHigh = globalSpacingSliderHigh
	panel.globalSpacingValueText = globalSpacingValueText

	-- OnClick is wired further below - it closes over the slider/labels
	-- this function creates next. Anchor must target globalSpacingSlider
	-- itself (a reliable left edge), not globalSpacingValueText - that
	-- FontString only has a bare "TOP" anchor, so it auto-centers under
	-- the slider and its BOTTOMLEFT sits near the slider's horizontal
	-- center, not its left edge. The -20 x-offset cancels
	-- globalSpacingSlider's own +20 offset from its checkbox, landing
	-- this checkbox back in the same left column.
	local globalButtonSizeCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralGlobalButtonSizeCheckbox", {
		anchor = { "TOPLEFT", globalSpacingSlider, "BOTTOMLEFT", -20, -26 },
		label = "Toggle global Button size",
		tooltip = {
			title = "Toggle global Button size",
			lines = {
				"When enabled, disables the Option to set the Button size on " ..
				"individual bars.",
				"Instead shows a new Slider to set the Button size globally " ..
				"for every bar. Unlock a bar's own lock icon to exempt it.",
			},
		},
	})

	local globalButtonSizeSlider, globalButtonSizeValueText = ACAB:CreateLabeledSlider(
		panel,
		"ACABGeneralGlobalButtonSizeSlider",
		{
			anchor = { "TOPLEFT", globalButtonSizeCheckbox, "BOTTOMLEFT", 20, -28 },
			min = ACAB.BUTTON_SIZE_MIN,
			max = ACAB.BUTTON_SIZE_MAX,
			step = 1,
			lowText = tostring(ACAB.BUTTON_SIZE_MIN),
			highText = tostring(ACAB.BUTTON_SIZE_MAX),
			initialText = tostring(ACAB.BUTTON_SIZE),
			round = function(value) return math.floor(value + 0.5) end,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					ACABDB.globalButtonSizeValue = value
					ACAB:ApplyGlobalButtonSize()
				end
			end,
		}
	)

	globalButtonSizeCheckbox:SetScript(
		"OnClick",
		function()
			if ACABDB.useDefaultLayout ~= false then
				this:SetChecked(false)
				return
			end

			local checked = this:GetChecked() and true or false

			ACABDB.globalButtonSizeEnabled = checked

			globalButtonSizeSlider:SetShown(checked)
			globalButtonSizeValueText:SetShown(checked)

			if checked then
				ACAB:ApplyGlobalButtonSize()
			end

			ACAB:ReflowGeneralOverrideSliders(panel)
			ACAB:RefreshAllBarPagesGlobalOverrideGating()
		end
	)

	panel.globalButtonSizeCheckbox = globalButtonSizeCheckbox
	panel.globalButtonSizeSlider = globalButtonSizeSlider
	panel.globalButtonSizeValueText = globalButtonSizeValueText

	-- Right ActionBar 2 dependency bypass (DefaultBars.lua's
	-- SetDefaultBarEnabled/FixRightActionBar2Checkbox) - lets bar 5 toggle
	-- independent of bar 4.
	-- WARNING: anchor off globalButtonSizeSlider itself, not
	-- globalButtonSizeValueText - value-text FontStrings only have a bare
	-- "TOP" anchor and center under their slider, not sitting at its left
	-- edge. Always anchor new General-tab controls off a slider/
	-- checkbox's own edge, never a *ValueText FontString.
	local bypassBar2DepCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralBypassBar2DepCheckbox", {
		anchor = { "TOPLEFT", globalButtonSizeSlider, "BOTTOMLEFT", -20, -28 },
		label = "Allow Right ActionBar 2 independent of Right ActionBar 1",
		onClick = function()
			ACABDB.bypassRightActionBar2Dependency = this:GetChecked() and true or false

			ACAB:FixRightActionBar2Checkbox()
		end,
	})

	panel.bypassBar2DepCheckbox = bypassBar2DepCheckbox

	-- "Enable Better Experience Bar" lives on the Experience Bar's own
	-- settings page (CreateSimpleBarPage's "if key == 'expbar'" block)
	-- alongside its text-toggle checkboxes and color pickers.

	panel:Hide()

	ACAB.settingsFrame.generalPanel = panel

	return panel
end

-------------------------------------------------------------------------
-- Profiles tab panel
--
-- Built lazily on first use, exactly like GetOrCreateGeneralPanel -
-- anchored the same way, spanning the combined listPanel+contentPanel
-- area since the bar list has no meaning here either.
-------------------------------------------------------------------------

-- Sentinel dropdown entry - not a real profile name, so a normal profile
-- can never collide with it. Chosen when the user wants to open the
-- create-new-profile dialog straight from the profile dropdown.
local CREATE_NEW_PROFILE_SENTINEL = "+ Create new profile"

function ACAB:GetOrCreateProfilesPanel()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	if ACAB.settingsFrame.profilesPanel then
		return ACAB.settingsFrame.profilesPanel
	end

	-- Own dedicated scrollframe+scrollchild pair (ACAB:CreateWideContentScrollFrame)
	-- - see CreateSettingsFrame's own comment on why this doesn't share
	-- the Bars view's contentScrollFrame.
	local scrollFrame, panel = ACAB:CreateWideContentScrollFrame("ACABSettingsProfilesScrollFrame")

	ACAB.settingsFrame.profilesScrollFrame = scrollFrame
	scrollFrame:Hide()

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", ACAB.INDENT_SECTION, -14)
	title:SetText("Profiles")
	panel.title = title

	local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -20)
	label:SetText("Active Profile:")
	panel.label = label

	-- Same row as the label (label left-aligned, dropdown right-aligned) -
	-- anchored to panel's own TOPRIGHT (for the wide page's real right
	-- edge) with a Y offset computed to match label's own TOP, since a
	-- fixed-size frame can't take X from one anchor and Y from another
	-- without the two anchors' redundant axes conflicting.
	local labelRowTopY = -(14 + title:GetHeight() + 20)

	local dropdown = ACAB:CreateInlineDropdown(panel, 220, "ACABProfilesDropdown")
	dropdown:ClearAllPoints()
	dropdown:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -ACAB.INDENT_SECTION, labelRowTopY)
	panel.profileDropdown = dropdown

	dropdown.onSelect = function(value)
		if value == CREATE_NEW_PROFILE_SENTINEL then
			ACAB:ShowCreateProfileDialog(function()
				-- On validation failure the dialog already stayed on the
				-- old profile (CreateProfile/SwitchProfile only reload on
				-- success) - re-sync the dropdown text either way so it
				-- never shows the sentinel as if it were a real selection.
				ACAB:RefreshProfilesPanel()
			end)

			return
		end

		if value and value ~= ACABCharDB.activeProfile then
			ACAB:SwitchProfile(value)
		end
	end

	local PROFILE_BUTTON_GAP_X = 12

	local exportButton = CreateFrame("Button", nil, panel)
	exportButton:SetHeight(22)
	exportButton:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 16, -14)
	ACAB:StyleModernButton(exportButton, 0, 0)
	exportButton:SetText("Export Profile")
	panel.exportButton = exportButton

	exportButton:SetScript("OnClick", function()
		ACAB:ShowDialog({
			title = "Export Profile",
			message = "Copy the text below (Ctrl+C) to share this profile.",
			mode = "textarea",
			defaultText = ACAB:ExportActiveProfileString(),
			buttons = {
				{
					text = "Select all",
					isDefault = true,
					keepOpen = true,
					onClick = function()
						ACAB.activeDialog.textArea.editBox:SetFocus()
						ACAB.activeDialog.textArea.editBox:HighlightText()
					end,
				},
				{ text = "Close", onClick = function() end },
			},
		})
	end)

	local copyButton = CreateFrame("Button", nil, panel)
	copyButton:SetHeight(22)
	copyButton:SetPoint("TOPLEFT", exportButton, "TOPRIGHT", PROFILE_BUTTON_GAP_X, 0)
	ACAB:StyleModernButton(copyButton, 0, 0)
	copyButton:SetText("Copy from other profile")
	panel.copyButton = copyButton

	copyButton:SetScript("OnClick", function()
		local otherProfiles = {}
		local names = ACAB:GetProfileNames()
		local i

		for i = 1, table.getn(names) do
			if names[i] ~= ACABCharDB.activeProfile then
				table.insert(otherProfiles, names[i])
			end
		end

		ACAB:ShowDialog({
			title = "Copy From Other Profile",
			message = "Choose another profile to copy all settings from. ATTENTION: " ..
				"This action will override all settings present on the current " ..
				"profile and is not reversible.",
			mode = "dropdown",
			options = otherProfiles,
			buttons = {
				{
					text = "Accept",
					isDefault = false,
					onClick = function(value)
						if value then
							ACAB:CopyProfileInto(value, ACABCharDB.activeProfile)
							ReloadUI()
						end
					end,
				},
				{ text = "Cancel", onClick = function() end },
			},
		})
	end)

	local importButton = CreateFrame("Button", nil, panel)
	importButton:SetHeight(22)
	importButton:SetPoint("TOPLEFT", copyButton, "TOPRIGHT", PROFILE_BUTTON_GAP_X, 0)
	ACAB:StyleModernButton(importButton, 0, 0)
	importButton:SetText("Import new Profile")
	panel.importButton = importButton

	importButton:SetScript("OnClick", function()
		local function ValidateImportText(value)
			return ACAB:ParseProfileImportString(value)
		end

		ACAB:ShowDialog({
			title = "Import Profile",
			message = "You are about to Import a Profile on to your currently " ..
				"active Profile " .. tostring(ACABCharDB.activeProfile),
			warningText = "WARNING! This will override all data on your " ..
				"current Profile with the imported Data",
			mode = "textarea",
			reserveErrorBanner = true,
			liveValidate = ValidateImportText,
			buttons = {
				{
					text = "Import",
					isDefault = true,
					validate = ValidateImportText,
					onClick = function(value)
						local ok, data = ACAB:ParseProfileImportString(value)

						if ok then
							ACAB:ApplyImportedProfileData(data)
							ReloadUI()
						end
					end,
				},
				{ text = "Close", onClick = function() end },
			},
		})
	end)

	local deleteButton = CreateFrame("Button", nil, panel)
	deleteButton:SetHeight(22)
	deleteButton:SetPoint("TOPLEFT", importButton, "TOPRIGHT", PROFILE_BUTTON_GAP_X, 0)
	ACAB:StyleModernButton(deleteButton, 0, 0)
	deleteButton:SetText("Delete profile")
	ACAB:ApplyDangerButtonHighlight(deleteButton)
	panel.deleteButton = deleteButton

	-- Centers the whole 4-button row under the Active Profile row instead
	-- of left-anchoring it under the dropdown - only exportButton's own
	-- anchor needs resetting, since copy/import/delete are already chained
	-- off their left neighbor's TOPRIGHT and follow automatically. Widths
	-- are only known now that every button's SetText above has run.
	local buttonRowY = labelRowTopY - math.max(label:GetHeight(), dropdown:GetHeight()) - 14
	local totalRowWidth = exportButton:GetWidth() + copyButton:GetWidth()
		+ importButton:GetWidth() + deleteButton:GetWidth() + (PROFILE_BUTTON_GAP_X * 3)

	exportButton:ClearAllPoints()
	exportButton:SetPoint(
		"TOP", panel, "TOP",
		-(totalRowWidth / 2) + (exportButton:GetWidth() / 2),
		buttonRowY
	)

	deleteButton:SetScript("OnClick", function()
		ACAB:ShowDialog({
			title = "Delete Profile",
			message = "ATTENTION: This action will delete all settings present " ..
				"on the current profile and is not reversible.",
			mode = "confirm",
			buttons = {
				{
					text = "Accept",
					onClick = function()
						ACAB:DeleteProfile(ACABCharDB.activeProfile)
						ReloadUI()
					end,
				},
				{ text = "Cancel", onClick = function() end },
			},
		})
	end)

	panel:Hide()

	ACAB.settingsFrame.profilesPanel = panel

	return panel
end

-- Refreshes the dropdown's option list/current selection and all 4
-- action buttons' visibility (only shown while a non-Default profile is
-- active, since Default is locked/uneditable) - called whenever the
-- Profiles view is (re)shown and after any profile CRUD action that
-- doesn't already trigger a ReloadUI.
function ACAB:RefreshProfilesPanel()
	local panel = self:GetOrCreateProfilesPanel()

	ACABCharDB = ACABCharDB or { activeProfile = self.DEFAULT_PROFILE_NAME }

	local names = self:GetProfileNames()
	local dropdownOptions = {}
	local i

	for i = 1, table.getn(names) do
		dropdownOptions[i] = names[i]
	end

	table.insert(dropdownOptions, CREATE_NEW_PROFILE_SENTINEL)

	panel.profileDropdown:SetOptions(dropdownOptions)
	panel.profileDropdown:SetSelected(ACABCharDB.activeProfile)

	if ACABCharDB.activeProfile ~= self.DEFAULT_PROFILE_NAME then
		panel.exportButton:Show()
		panel.copyButton:Show()
		panel.importButton:Show()
		panel.deleteButton:Show()
	else
		panel.exportButton:Hide()
		panel.copyButton:Hide()
		panel.importButton:Hide()
		panel.deleteButton:Hide()
	end
end
-------------------------------------------------------------------------
-- Edit Mode panel (ACABDB.snapToAdjacentElements/showLayoutGrid/
-- snapToGrid)
--
-- Own dedicated scrollframe+scrollchild pair, same pattern as
-- GetOrCreateProfilesPanel/GetOrCreateGeneralPanel above.
-------------------------------------------------------------------------

function ACAB:GetOrCreateEditModePanel()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	if ACAB.settingsFrame.editModePanel then
		return ACAB.settingsFrame.editModePanel
	end

	local scrollFrame, panel = ACAB:CreateWideContentScrollFrame("ACABSettingsEditModeScrollFrame")

	ACAB.settingsFrame.editModeScrollFrame = scrollFrame
	scrollFrame:Hide()

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", panel, "TOPLEFT", ACAB.INDENT_SECTION, -14)
	title:SetText("Edit Mode Settings")
	panel.title = title

	-------------------------------------------------------------------------
	-- Snap to Adjacent Elements: ACABDB.snapToAdjacentElements
	-- (default true) gates both snap injection points (Bar.lua's
	-- StopBarDrag drop-time snap, DefaultBars.lua's live OnUpdate snap)
	-- via the shared ACAB:ComputeSnapAdjustment utility - only affects the
	-- NEXT drag.
	-------------------------------------------------------------------------

	local snapToAdjacentCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABEditModeSnapToAdjacentCheckbox", {
		anchor = { "TOPLEFT", title, "BOTTOMLEFT", 0, -20 },
		label = "Snap to Adjacent Elements",
		tooltip = {
			title = "Snap to Adjacent Elements",
			lines = {
				"When enabled, elements moved in Edit Layout Mode snap to nearby " ..
				"screen edges/corners and to adjacent elements' edges for pixel-" ..
				"perfect alignment and stacking.",
				"Hold shift while in Edit Layout Mode to temporarily enable / " ..
				"disable snapping, regardless of this setting.",
			},
		},
		onClick = function()
			ACABDB.snapToAdjacentElements = this:GetChecked() and true or false
		end,
	})

	panel.snapToAdjacentCheckbox = snapToAdjacentCheckbox

	-------------------------------------------------------------------------
	-- Show Layout Grid: ACABDB.showLayoutGrid (default true) - a
	-- reference grid spanning the screen in Edit Layout Mode, spaced to
	-- match the current action-button footprint (ACAB:GetLayoutGridSpacing()),
	-- with a darker line through screen center on each axis (Bar.lua's
	-- RebuildLayoutGrid). Ctrl temporarily flips this on/off.
	-------------------------------------------------------------------------

	local showLayoutGridCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABEditModeShowLayoutGridCheckbox", {
		anchor = { "TOPLEFT", snapToAdjacentCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Show Layout Grid",
		tooltip = {
			title = "Show Layout Grid",
			lines = {
				"When enabled, an evenly-spaced reference grid covers the whole " ..
				"screen while in Edit Layout Mode.",
				"Hold Ctrl while in Edit Layout Mode to temporarily show/hide " ..
				"it, regardless of this setting.",
			},
		},
		onClick = function()
			ACABDB.showLayoutGrid = this:GetChecked() and true or false

			if ACAB:IsEditMode() then
				ACAB:RefreshLayoutGridVisibility()
			end
		end,
	})

	panel.showLayoutGridCheckbox = showLayoutGridCheckbox

	-------------------------------------------------------------------------
	-- Snap to Grid
	--
	-- ACABDB.snapToGrid (default true, Core.lua's EnsureDB) - like
	-- Snap to Adjacent Elements above, only ever affects the NEXT drag
	-- (Core.lua's ACAB:ComputeGridSnapAdjustment, wired into
	-- DefaultBars.lua's ApplyDragSnap ahead of the adjacent-elements
	-- snap), so no separate Apply/refresh call is needed here.
	-------------------------------------------------------------------------

	local snapToGridCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABEditModeSnapToGridCheckbox", {
		anchor = { "TOPLEFT", showLayoutGridCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Snap to Grid",
		tooltip = {
			title = "Snap to Grid",
			lines = {
				"When enabled, elements dragged in Edit Layout Mode snap so their " ..
				"center sits exactly on a grid line intersection, independent of " ..
				"whether the grid is currently shown.",
			},
		},
		onClick = function()
			ACABDB.snapToGrid = this:GetChecked() and true or false
		end,
	})

	panel.snapToGridCheckbox = snapToGridCheckbox

	-------------------------------------------------------------------------
	-- Use custom Grid Size: ACABDB.useCustomGridSize (default false) -
	-- overrides ACAB:GetLayoutGridSpacing()'s normal behavior (tracking Main
	-- Bar's live buttonSize) with a flat ACABDB.customGridSize value.
	-- Slider is SetShown()-toggled by this checkbox, same as the General
	-- tab's Global Spacing/Button Size sliders.
	-------------------------------------------------------------------------

	-- OnClick is wired further below - it closes over the slider this
	-- function creates next.
	local useCustomGridSizeCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABEditModeUseCustomGridSizeCheckbox", {
		anchor = { "TOPLEFT", snapToGridCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Use custom Grid Size",
		tooltip = {
			title = "Use custom Grid Size",
			lines = {
				"Grid spacing normally tracks the Main Bar's current Button Size " ..
				"live (resizing it, or the General tab's Global Button Size, " ..
				"updates the grid too).",
				"When enabled, Grid size is no longer directed by Main Bar's " ..
				"Button size. A new Slider to set the Grid size statically " ..
				"appears instead.",
			},
		},
	})

	panel.useCustomGridSizeCheckbox = useCustomGridSizeCheckbox

	local customGridSizeSlider, customGridSizeValueText, customGridSizeSliderLow, customGridSizeSliderHigh = ACAB:CreateLabeledSlider(
		panel,
		"ACABEditModeCustomGridSizeSlider",
		{
			anchor = { "TOPLEFT", useCustomGridSizeCheckbox, "BOTTOMLEFT", 20, -28 },
			min = 0,
			max = 55,
			step = 1,
			lowText = "0",
			highText = "55",
			initialText = "0",
			round = function(value) return math.floor(value + 0.5) end,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					ACABDB.customGridSize = value

					if ACAB:IsEditMode() then
						ACAB:RebuildLayoutGrid()
					end
				end
			end,
		}
	)

	useCustomGridSizeCheckbox:SetScript(
		"OnClick",
		function()
			local checked = this:GetChecked() and true or false

			if checked and not ACABDB.useCustomGridSize then
				-- Seeds the slider with whatever the dynamic (Main-Bar-
				-- tracking) spacing currently evaluates to - read BEFORE
				-- flipping the flag below, since GetLayoutGridSpacing
				-- itself branches on useCustomGridSize. Rounded since the
				-- border-inset math can yield a fractional value but the
				-- slider only steps by whole numbers.
				ACABDB.customGridSize = math.floor(ACAB:GetLayoutGridSpacing() + 0.5)
			end

			ACABDB.useCustomGridSize = checked

			customGridSizeSlider:SetShown(checked)
			customGridSizeValueText:SetShown(checked)

			if checked then
				customGridSizeSlider.suppressApply = true
				customGridSizeSlider:SetValue(ACABDB.customGridSize or 0)
				customGridSizeValueText:SetText(tostring(ACABDB.customGridSize or 0))
				customGridSizeSlider.suppressApply = nil
			end

			if ACAB:IsEditMode() then
				ACAB:RebuildLayoutGrid()
			end

			if ACAB.settingsFrame.currentView == "editmode" then
				ACAB:DeferFit(function() ACAB:FitSettingsWindowToEditModeView() end)
			end
		end
	)

	panel.customGridSizeSlider = customGridSizeSlider
	panel.customGridSizeSliderLow = customGridSizeSliderLow
	panel.customGridSizeSliderHigh = customGridSizeSliderHigh
	panel.customGridSizeValueText = customGridSizeValueText

	panel:Hide()

	ACAB.settingsFrame.editModePanel = panel

	return panel
end

-- First three default true, useCustomGridSize defaults false (Core.lua's
-- EnsureDB).
function ACAB:RefreshEditModePanel()
	local panel = self:GetOrCreateEditModePanel()

	panel.snapToAdjacentCheckbox:SetChecked(
		ACABDB.snapToAdjacentElements == true
	)

	panel.showLayoutGridCheckbox:SetChecked(
		ACABDB.showLayoutGrid == true
	)

	panel.snapToGridCheckbox:SetChecked(
		ACABDB.snapToGrid == true
	)

	local useCustomGridSize = ACABDB.useCustomGridSize == true

	panel.useCustomGridSizeCheckbox:SetChecked(useCustomGridSize)
	panel.customGridSizeSlider:SetShown(useCustomGridSize)
	panel.customGridSizeValueText:SetShown(useCustomGridSize)

	if useCustomGridSize then
		panel.customGridSizeSlider.suppressApply = true
		panel.customGridSizeSlider:SetValue(ACABDB.customGridSize or 0)
		panel.customGridSizeValueText:SetText(tostring(ACABDB.customGridSize or 0))
		panel.customGridSizeSlider.suppressApply = nil
	end
end
-------------------------------------------------------------------------
-- General panel: dynamic reflow for the Global Spacing / Global
-- ButtonSize sliders. Both are SetShown()-toggled by their own checkbox,
-- but Hide() doesn't remove a frame from its neighbors' fixed-offset
-- anchor math, so the gap stays reserved while hidden. This walks the
-- checkbox/slider stack and re-anchors each entry to sit flush against
-- whichever entry above it is actually SHOWN, collapsing/restoring the
-- gap live. Column = the stack's two indent levels (checkboxes at base
-- indent, sliders 20px further right - hand-tuned offsets below).
-------------------------------------------------------------------------

local REFLOW_COLUMN_CHECKBOX = 0
local REFLOW_COLUMN_SLIDER = 20
local REFLOW_GAP_CHECKBOX_TO_SLIDER = -28
local REFLOW_GAP_SLIDER_TO_CHECKBOX = -26
local REFLOW_GAP_CHECKBOX_TO_CHECKBOX = -14

-- entries: ordered array of { frame = <Frame>, column = REFLOW_COLUMN_*,
-- isOptional = true|nil }. The first entry's own anchor is never touched -
-- callers set that once, outside this list, to whatever fixed frame it
-- should follow. An `isOptional` entry that's currently Hidden is skipped
-- entirely (neither re-anchored nor used as the next entry's anchor
-- source), so hiding it collapses its slot rather than leaving a gap.
local function ReflowStack(entries)
	local prev = entries[1].frame
	local prevColumn = entries[1].column
	local i

	for i = 2, table.getn(entries) do
		local entry = entries[i]

		if (not entry.isOptional) or entry.frame:IsShown() then
			local gap

			if prevColumn == REFLOW_COLUMN_SLIDER and entry.column == REFLOW_COLUMN_CHECKBOX then
				gap = REFLOW_GAP_SLIDER_TO_CHECKBOX
			elseif prevColumn == REFLOW_COLUMN_CHECKBOX and entry.column == REFLOW_COLUMN_SLIDER then
				gap = REFLOW_GAP_CHECKBOX_TO_SLIDER
			else
				gap = REFLOW_GAP_CHECKBOX_TO_CHECKBOX
			end

			entry.frame:ClearAllPoints()
			entry.frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", entry.column - prevColumn, gap)

			prev = entry.frame
			prevColumn = entry.column
		end
	end
end

-- Re-fits the General view after its own content height changed. Deferred
-- one frame so the reflowed controls' positions have settled before
-- anything measures them (same reason ShowGeneralView defers its own
-- fit), and guarded on the General view actually being the one on screen -
-- RefreshGeneralPanel can run while another view is showing, and fitting
-- the window to a hidden panel would resize it to the wrong thing.
local function RefitGeneralViewSoon()
	if not ACAB.settingsFrame or ACAB.settingsFrame.currentView ~= "general" then
		return
	end

	ACAB:DeferFit(function() ACAB:FitSettingsWindowToGeneralView() end)
end

function ACAB:ReflowGeneralOverrideSliders(panel)
	ReflowStack({
		{ frame = panel.globalSpacingCheckbox, column = REFLOW_COLUMN_CHECKBOX },
		{ frame = panel.globalSpacingSlider, column = REFLOW_COLUMN_SLIDER, isOptional = true },
		{ frame = panel.globalButtonSizeCheckbox, column = REFLOW_COLUMN_CHECKBOX },
		{ frame = panel.globalButtonSizeSlider, column = REFLOW_COLUMN_SLIDER, isOptional = true },
		{ frame = panel.bypassBar2DepCheckbox, column = REFLOW_COLUMN_CHECKBOX },
	})

	-- Revealing/hiding either slider changes how tall this panel's content
	-- is, so the window (and its scrollchild) has to be re-measured -
	-- otherwise turning a toggle ON grows the content past the viewport
	-- with no matching scroll range, leaving the bottom unreachable.
	RefitGeneralViewSoon()
end

-- Re-anchors hotkeyTitle below the macro text section's real bottom edge.
-- Anchors off macroTitle, not macroValueText - macroValueText uses a "TOP"
-- anchor, so its LEFT edge drifts with the displayed digit count/width.
function ACAB:ReflowGeneralHotkeySection(panel)
	panel.hotkeyTitle:ClearAllPoints()

	if panel.macroSlider:IsShown() then
		panel.hotkeyTitle:SetPoint(
			"TOPLEFT",
			panel.macroTitle,
			"BOTTOMLEFT",
			0,
			-12 - panel.macroSlider:GetHeight() - 2 - panel.macroValueText:GetHeight() - 18
		)
	else
		panel.hotkeyTitle:SetPoint(
			"TOPLEFT",
			panel.macroTextCheckbox,
			"BOTTOMLEFT",
			8,
			-22
		)
	end

	RefitGeneralViewSoon()
end

function ACAB:RefreshGeneralPanel()
	local panel = self:GetOrCreateGeneralPanel()

	panel.useDefaultLayoutCheckbox:SetChecked(
		ACABDB.useDefaultLayout == true
	)

	-- Locked to unchecked+non-interactive while useDefaultLayout forces
	-- vanilla styling (ACAB:IsVanillaBorderStyle, Core.lua) - reuses the
	-- established EnableMouse(false)+SetAlpha(0.5) gating idiom
	-- (ApplyDefaultLayoutGating) rather than :Disable(), matching every
	-- other gated control in this file.
	local vanillaBorderStyleLocked = ACABDB.useDefaultLayout ~= false

	panel.modernBorderStyleCheckbox:SetChecked(
		(not vanillaBorderStyleLocked) and ACABDB.modernBorderStyle == true
	)
	panel.modernBorderStyleCheckbox:EnableMouse(not vanillaBorderStyleLocked)
	panel.modernBorderStyleCheckbox:SetAlpha(vanillaBorderStyleLocked and 0.5 or 1)

	-- Global Spacing / global ButtonSize overrides: same
	-- vanillaBorderStyleLocked lock as modernBorderStyleCheckbox above,
	-- plus their own checked/value sync and the Show/Hide reveal of their
	-- sliders. The displayed range (spacing only) is recomputed here too,
	-- same reason as the per-bar slider.
	local spacingDisplayed = ACABDB.globalSpacingEnabled == true and
		not vanillaBorderStyleLocked

	panel.globalSpacingCheckbox:SetChecked(spacingDisplayed)
	panel.globalSpacingCheckbox:EnableMouse(not vanillaBorderStyleLocked)
	panel.globalSpacingCheckbox:SetAlpha(vanillaBorderStyleLocked and 0.5 or 1)

	local spacingOffset = ACAB:GetSpacingDisplayOffset()

	panel.globalSpacingSlider:SetMinMaxValues(0, ACAB.SPACING_MAX - spacingOffset)

	if panel.globalSpacingSliderLow then
		panel.globalSpacingSliderLow:SetText("0")
	end

	if panel.globalSpacingSliderHigh then
		panel.globalSpacingSliderHigh:SetText(tostring(ACAB.SPACING_MAX - spacingOffset))
	end

	panel.globalSpacingSlider.suppressApply = true
	panel.globalSpacingSlider:SetValue(ACABDB.globalSpacingValue or 0)
	panel.globalSpacingSlider.suppressApply = nil
	panel.globalSpacingValueText:SetText(tostring(ACABDB.globalSpacingValue or 0))

	panel.globalSpacingSlider:SetShown(spacingDisplayed)
	panel.globalSpacingValueText:SetShown(spacingDisplayed)
	panel.globalSpacingSlider:EnableMouse(not vanillaBorderStyleLocked)
	panel.globalSpacingSlider:SetAlpha(vanillaBorderStyleLocked and 0.5 or 1)

	local buttonSizeDisplayed = ACABDB.globalButtonSizeEnabled == true and
		not vanillaBorderStyleLocked

	panel.globalButtonSizeCheckbox:SetChecked(buttonSizeDisplayed)
	panel.globalButtonSizeCheckbox:EnableMouse(not vanillaBorderStyleLocked)
	panel.globalButtonSizeCheckbox:SetAlpha(vanillaBorderStyleLocked and 0.5 or 1)

	panel.globalButtonSizeSlider.suppressApply = true
	panel.globalButtonSizeSlider:SetValue(ACABDB.globalButtonSizeValue or ACAB.BUTTON_SIZE)
	panel.globalButtonSizeSlider.suppressApply = nil
	panel.globalButtonSizeValueText:SetText(
		tostring(ACABDB.globalButtonSizeValue or ACAB.BUTTON_SIZE)
	)

	panel.globalButtonSizeSlider:SetShown(buttonSizeDisplayed)
	panel.globalButtonSizeValueText:SetShown(buttonSizeDisplayed)
	panel.globalButtonSizeSlider:EnableMouse(not vanillaBorderStyleLocked)
	panel.globalButtonSizeSlider:SetAlpha(vanillaBorderStyleLocked and 0.5 or 1)

	-- Both sliders' Shown state is now final for this refresh - collapse/
	-- restore the gap below each one accordingly.
	ACAB:ReflowGeneralOverrideSliders(panel)

	panel.bypassBar2DepCheckbox:SetChecked(ACABDB.bypassRightActionBar2Dependency == true)

	-- Default true (Core.lua's EnsureDB) - only an explicit false ever
	-- unchecks this.
	panel.tintWholeButtonCheckbox:SetChecked(
		ACABDB.tintWholeButtonOnRange ~= false
	)

	-- Default false (Core.lua's EnsureDB) - only an explicit true ever
	-- checks this.
	panel.disableBlizzardArtCheckbox:SetChecked(
		ACABDB.disableBlizzardArt == true
	)

	-- Both default true (Core.lua's EnsureDB) - only an explicit false
	-- ever unchecks either.
	panel.mainBarPaginationCheckbox:SetChecked(
		ACABDB.mainBarPaginationEnabled ~= false
	)

	-- Stance/Page Bar Assignment rows themselves live on bar 1's own
	-- settings page; refreshed from RefreshBarSettingsPage(1).

	panel.mainBarStanceSwapCheckbox:SetChecked(
		ACABDB.mainBarStanceSwapEnabled ~= false
	)

	-------------------------------------------------------------------------
	-- Macro text toggle + font size
	-------------------------------------------------------------------------

	local macroTextEnabled = ACABDB.showMacroText == true

	panel.macroTextCheckbox:SetChecked(macroTextEnabled)

	panel.macroTitle:SetShown(macroTextEnabled)
	panel.macroSlider:SetShown(macroTextEnabled)
	panel.macroValueText:SetShown(macroTextEnabled)
	panel.macroResetButton:SetShown(macroTextEnabled)

	local macroDefault = ACAB.NATIVE_MACRO_FONT and ACAB.NATIVE_MACRO_FONT.size
	local macroSize = ACAB:ClampFontSize(ACABDB.macroFontSize or macroDefault)

	panel.macroSlider.suppressApply = true
	panel.macroSlider:SetValue(macroSize)
	panel.macroValueText:SetText(tostring(macroSize))
	panel.macroSlider.suppressApply = nil

	ACAB:ReflowGeneralHotkeySection(panel)

	-------------------------------------------------------------------------
	-- Hotkey / Count text font size
	--
	-- nil (never yet touched by the user) falls back to the captured
	-- native default - see Core.lua's EnsureDB comment on why these two
	-- fields are deliberately left unseeded.
	-------------------------------------------------------------------------

	local hotkeyDefault = ACAB.NATIVE_HOTKEY_FONT and ACAB.NATIVE_HOTKEY_FONT.size
	local hotkeySize = ACAB:ClampFontSize(ACABDB.hotkeyFontSize or hotkeyDefault)

	panel.hotkeySlider.suppressApply = true
	panel.hotkeySlider:SetValue(hotkeySize)
	panel.hotkeyValueText:SetText(tostring(hotkeySize))
	panel.hotkeySlider.suppressApply = nil

	local countDefault = ACAB.NATIVE_COUNT_FONT and ACAB.NATIVE_COUNT_FONT.size
	local countSize = ACAB:ClampFontSize(ACABDB.countFontSize or countDefault)

	panel.countSlider.suppressApply = true
	panel.countSlider:SetValue(countSize)
	panel.countValueText:SetText(tostring(countSize))
	panel.countSlider.suppressApply = nil

	-- "Enable Better Experience Bar" lives on the Experience Bar's own
	-- settings page; refreshed from RefreshSimpleBarPage("expbar").
end

-------------------------------------------------------------------------
-- View switching ("Bars" / "General" tabs)
-------------------------------------------------------------------------

-- Syncs each top nav tab's persistent gold selectStrip (CreateSettingsFrame's
-- ApplyTabFadeHighlight) to ACAB.settingsFrame.currentView - called after every
-- place that assigns ACAB.settingsFrame.currentView, so whichever tab matches
-- the now-active view is the only one highlighted.
function ACAB:RefreshActiveTabHighlight()
	if not ACAB.settingsFrame or not ACAB.settingsFrame.tabButtonsByView then
		return
	end

	local view
	local button

	for view, button in pairs(ACAB.settingsFrame.tabButtonsByView) do
		if button.tabSelectStrip then
			button.tabSelectStrip:SetShown(ACAB.settingsFrame.currentView == view)
		end

		if button.UpdateFadeBorderColor then
			button:UpdateFadeBorderColor()
		end
	end
end

function ACAB:ShowBarsView()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	self:ShowBarPage(ACAB.settingsFrame.activeBarId or 1)
end

function ACAB:ShowGeneralView()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	local id
	local page

	for id, page in pairs(ACAB.settingsFrame.pages) do
		page:Hide()
	end

	ACAB.settingsFrame.listPanel:Hide()
	ACAB.settingsFrame.contentScrollFrame:Hide()
	ACAB.settingsFrame.contentPanel:Hide()
	ACAB.settingsFrame.currentView = "general"
	ACAB:RefreshActiveTabHighlight()

	-- Ensure the General panel (and its own dedicated scrollframe) exist
	-- before trying to Show() the scrollframe below.
	self:GetOrCreateGeneralPanel()

	if ACAB.settingsFrame.profilesScrollFrame then
		ACAB.settingsFrame.profilesScrollFrame:Hide()
	end

	if ACAB.settingsFrame.profilesPanel then
		ACAB.settingsFrame.profilesPanel:Hide()
	end

	if ACAB.settingsFrame.editModeScrollFrame then
		ACAB.settingsFrame.editModeScrollFrame:Hide()
	end

	if ACAB.settingsFrame.editModePanel then
		ACAB.settingsFrame.editModePanel:Hide()
	end

	ACAB.settingsFrame.generalScrollFrame:Show()

	self:RefreshGeneralPanel()
	self:GetOrCreateGeneralPanel():Show()

	-- Same reasoning as ShowBarPage's call - has to run after
	-- :Show() so GetBottom() reads real values. Deferred one frame
	-- (DeferFit) so its own candidates' positions have settled before
	-- anything measures them.
	ACAB:DeferFit(function() ACAB:FitSettingsWindowToGeneralView() end)
end

function ACAB:ShowProfilesView()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	local id
	local page

	for id, page in pairs(ACAB.settingsFrame.pages) do
		page:Hide()
	end

	ACAB.settingsFrame.listPanel:Hide()
	ACAB.settingsFrame.contentScrollFrame:Hide()
	ACAB.settingsFrame.contentPanel:Hide()
	ACAB.settingsFrame.currentView = "profiles"
	ACAB:RefreshActiveTabHighlight()

	-- Ensure the Profiles panel (and its own dedicated scrollframe) exist
	-- before trying to Show() the scrollframe below.
	self:GetOrCreateProfilesPanel()

	if ACAB.settingsFrame.generalScrollFrame then
		ACAB.settingsFrame.generalScrollFrame:Hide()
	end

	if ACAB.settingsFrame.generalPanel then
		ACAB.settingsFrame.generalPanel:Hide()
	end

	if ACAB.settingsFrame.editModeScrollFrame then
		ACAB.settingsFrame.editModeScrollFrame:Hide()
	end

	if ACAB.settingsFrame.editModePanel then
		ACAB.settingsFrame.editModePanel:Hide()
	end

	ACAB.settingsFrame.profilesScrollFrame:Show()

	self:RefreshProfilesPanel()
	self:GetOrCreateProfilesPanel():Show()

	-- Same reasoning as ShowBarPage's call - has to run after
	-- :Show() so GetBottom() reads real values. Deferred one frame
	-- (DeferFit) so its own candidates' positions have settled before
	-- anything measures them.
	ACAB:DeferFit(function() ACAB:FitSettingsWindowToProfilesView() end)
end

function ACAB:ShowEditModeView()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	local id
	local page

	for id, page in pairs(ACAB.settingsFrame.pages) do
		page:Hide()
	end

	ACAB.settingsFrame.listPanel:Hide()
	ACAB.settingsFrame.contentScrollFrame:Hide()
	ACAB.settingsFrame.contentPanel:Hide()
	ACAB.settingsFrame.currentView = "editmode"
	ACAB:RefreshActiveTabHighlight()

	-- Ensure the Edit Mode panel (and its own dedicated scrollframe) exist
	-- before trying to Show() the scrollframe below.
	self:GetOrCreateEditModePanel()

	if ACAB.settingsFrame.generalScrollFrame then
		ACAB.settingsFrame.generalScrollFrame:Hide()
	end

	if ACAB.settingsFrame.generalPanel then
		ACAB.settingsFrame.generalPanel:Hide()
	end

	if ACAB.settingsFrame.profilesScrollFrame then
		ACAB.settingsFrame.profilesScrollFrame:Hide()
	end

	if ACAB.settingsFrame.profilesPanel then
		ACAB.settingsFrame.profilesPanel:Hide()
	end

	ACAB.settingsFrame.editModeScrollFrame:Show()

	self:RefreshEditModePanel()
	self:GetOrCreateEditModePanel():Show()

	-- Same reasoning as ShowBarPage's call - has to run after
	-- :Show() so GetBottom() reads real values. Deferred one frame
	-- (DeferFit) so its own candidates' positions have settled before
	-- anything measures them.
	ACAB:DeferFit(function() ACAB:FitSettingsWindowToEditModeView() end)
end
