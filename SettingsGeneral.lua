-- SettingsGeneral.lua
-- General / Profiles / Edit Mode settings views, their refreshers, and top-level view switching.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Shared control helpers
-------------------------------------------------------------------------

-- Slider round callback: nearest integer.
local function RoundToInteger(value)
	return math.floor(value + 0.5)
end

-- Dims a control and blocks its mouse input while locked (no Disable()).
local function SetMouseLocked(control, locked)
	control:EnableMouse(not locked)
	control:SetAlpha(locked and 0.5 or 1)
end

-- Title text "<label> Text Size (MIN to MAX)".
local function FontSizeTitleText(label)
	return label .. " Text Size (" .. tostring(ACAB.FONT_SIZE_MIN) ..
		" to " .. tostring(ACAB.FONT_SIZE_MAX) .. ")"
end

-- Creates a font-size slider under `title` plus a Reset button restoring ACAB[nativeFontKey].size;
-- applySize(size) applies a value. Returns slider, valueText, resetButton.
local function CreateFontSizeSlider(panel, title, sliderName, nativeFontKey, applySize)
	-- Placeholder initial text; RefreshGeneralPanel sets the real value before the panel is shown.
	local slider, valueText = ACAB:CreateLabeledSlider(
		panel,
		sliderName,
		{
			width = 260,
			anchor = { "TOPLEFT", title, "BOTTOMLEFT", ACAB.INDENT_INPUT - ACAB.INDENT_SECTION, -12 },
			min = ACAB.FONT_SIZE_MIN,
			max = ACAB.FONT_SIZE_MAX,
			step = ACAB.FONT_SIZE_STEP,
			lowText = tostring(ACAB.FONT_SIZE_MIN),
			highText = tostring(ACAB.FONT_SIZE_MAX),
			initialText = tostring(ACAB.FONT_SIZE_MIN),
			round = RoundToInteger,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					applySize(value)
				end
			end,
		}
	)

	local resetButton = ACAB:CreateResetButton(panel, {
		anchor = { "LEFT", slider, "RIGHT", 16, 4 },
		minWidth = 90,
		maxWidth = 90,
		text = "Reset",
		onClick = function()
			-- No-op until a native size has been captured.
			local nativeFont = ACAB[nativeFontKey]

			if not nativeFont then
				return
			end

			local size = ACAB:ClampFontSize(nativeFont.size)

			applySize(size)
			ACAB:SetSliderValueSilently(slider, size, valueText)
		end,
	})

	return slider, valueText, resetButton
end

-- OnClick for a global Spacing/Button size override checkbox: stores its flag, shows its slider
-- while checked, applies, and reflows. Blocked while Force Vanilla Layout Mode is on.
local function GlobalOverrideOnClick(panel, enabledKey, slider, valueText, apply)
	return function()
		if ACABDB.useDefaultLayout ~= false then
			this:SetChecked(false)
			return
		end

		local checked = this:GetChecked() and true or false

		ACABDB[enabledKey] = checked

		slider:SetShown(checked)
		valueText:SetShown(checked)

		if checked then
			apply()
		end

		ACAB:ReflowGeneralOverrideSliders(panel)
		ACAB:RefreshAllBarPagesGlobalOverrideGating()
	end
end

-------------------------------------------------------------------------
-- General tab panel
-------------------------------------------------------------------------

function ACAB:GetOrCreateGeneralPanel()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	if ACAB.settingsFrame.generalPanel then
		return ACAB.settingsFrame.generalPanel
	end

	local scrollFrame, panel = ACAB:CreateWideContentScrollFrame("ACABSettingsGeneralScrollFrame")

	ACAB.settingsFrame.generalScrollFrame = scrollFrame
	scrollFrame:Hide()

	local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

	title:SetPoint("TOPLEFT", panel, "TOPLEFT", ACAB.INDENT_SECTION, -14)
	title:SetText("General Settings")

	-------------------------------------------------------------------------
	-- Force Vanilla Layout Mode
	-------------------------------------------------------------------------

	-- OnClick is set below: its confirm dialog's OK button closes over this `checkbox` local.
	local checkbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralUseDefaultLayoutCheckbox", {
		anchor = { "TOPLEFT", panel, "TOPLEFT", ACAB.INDENT_SECTION, -52 },
		label = "Force Vanilla Layout Mode",
		tooltip = {
			title = "Force Vanilla Layout Mode",
			lines = {
				"When enabled, default action bars keep their native vanilla " ..
				"position, size, and layout, and can only be shown/hidden - " ..
				"dragging and resizing them is disabled.",
				"Disable this to freely reposition, resize, and drag default " ..
				"bars like custom bars.",
			},
		},
	})

	checkbox:SetScript("OnClick", function()
		local checked = this:GetChecked() and true or false
		local wasDefault = ACABDB.useDefaultLayout == true

		-- Turning on resets every bar: stays unchecked until the confirm dialog's OK re-checks it.
		if checked and not wasDefault then
			this:SetChecked(false)

			ACAB:ShowDialog({
				title = "Force Vanilla Layout Mode",
				message = "Enabling this will reset ALL bars to their " ..
					"default Vanilla Layout position.",
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
	end)

	panel.useDefaultLayoutCheckbox = checkbox

	-------------------------------------------------------------------------
	-- Tint whole button on out of range (off: tint only the hotkey text, like native buttons)
	-------------------------------------------------------------------------

	local tintWholeButtonCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralTintWholeButtonCheckbox", {
		anchor = { "TOPLEFT", checkbox, "BOTTOMLEFT", 0, -14 },
		label = "Tint whole button on out of range",
		onClick = function()
			local checked = this:GetChecked() and true or false

			ACABDB.tintWholeButtonOnRange = checked

			-- Re-tints every live button immediately.
			ACAB:SweepAllButtonRangeTint()
		end,
	})

	panel.tintWholeButtonCheckbox = tintWholeButtonCheckbox

	-------------------------------------------------------------------------
	-- Default bar (1-5) pagination / stance-swap toggles
	-------------------------------------------------------------------------

	local mainBarPaginationCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralMainBarPaginationCheckbox", {
		anchor = { "TOPLEFT", tintWholeButtonCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Enable Page Bar-Changes",
		tooltip = {
			title = "Enable Page Bar-Changes",
			lines = {
				"When enabled, shows a Page 2 Content Source option on every " ..
				"default bar's (1-5) own Bars Settings Page. You will be " ..
				"able to freely assign any Extra Bar as that bar's content " ..
				"while Shift/Ctrl page 2 is held. Enabling it will also " ..
				"enable the Paging UI Element.",
				"When disabled, every default bar will always stay the same " ..
				"and the Paging UI Element is hidden.",
			},
		},
		onClick = function()
			local checked = this:GetChecked() and true or false

			ACAB:SetDefaultBarPaginationEnabled(checked)

			-- Shows/hides the Page assignment rows and Page Indicator controls on every default bar page.
			ACAB:RebuildAllDefaultBarAssignmentRows()
			ACAB:RefreshMainBarPageIndicatorControlsVisibility()
		end,
	})

	panel.mainBarPaginationCheckbox = mainBarPaginationCheckbox

	local mainBarStanceSwapCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralMainBarStanceSwapCheckbox", {
		anchor = { "TOPLEFT", mainBarPaginationCheckbox, "BOTTOMLEFT", 0, -14 },
		label = "Enable Stance/Form/Stealth Bar-Changes",
		tooltip = {
			title = "Enable Stance/Form/Stealth Bar-Changes",
			lines = {
				"When enabled, shows a stance-assignment option per active " ..
				"form on every default bar's (1-5) own Bars Settings Page. " ..
				"You will be able to freely assign any Extra Bar to any of " ..
				"your different Shapes / Forms to swap that bar's contents " ..
				"with automatically.",
				"When disabled, every default bar will always stay the same.",
			},
		},
		onClick = function()
			local checked = this:GetChecked() and true or false

			ACAB:SetDefaultBarStanceSwapEnabled(checked)

			-- Shows/hides the per-stance assignment rows.
			ACAB:RebuildAllDefaultBarAssignmentRows()
		end,
	})

	panel.mainBarStanceSwapCheckbox = mainBarStanceSwapCheckbox

	-------------------------------------------------------------------------
	-- Macro text toggle + font size
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

	local macroTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")

	macroTitle:SetPoint("TOPLEFT", macroTextCheckbox, "BOTTOMLEFT", 8, -10)
	macroTitle:SetText(FontSizeTitleText("Macro"))

	-- The *Title fields must stay on panel: ApplySettingsHeightFromCandidates' resolve pass reads them.
	panel.macroTitle = macroTitle

	panel.macroSlider, panel.macroValueText, panel.macroResetButton = CreateFontSizeSlider(
		panel, macroTitle, "ACABGeneralMacroFontSizeSlider", "NATIVE_MACRO_FONT",
		function(size) ACAB:SetMacroFontSize(size) end
	)

	-------------------------------------------------------------------------
	-- Hotkey / Item Count text font size (global, live)
	-------------------------------------------------------------------------

	local hotkeyTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")

	-- Placeholder anchor; ReflowGeneralHotkeySection re-anchors it.
	hotkeyTitle:SetPoint("TOPLEFT", macroTextCheckbox, "BOTTOMLEFT", 8, -22)
	hotkeyTitle:SetText(FontSizeTitleText("Hotkey"))

	panel.hotkeyTitle = hotkeyTitle

	local hotkeySlider, hotkeyValueText, hotkeyResetButton = CreateFontSizeSlider(
		panel, hotkeyTitle, "ACABGeneralHotkeyFontSizeSlider", "NATIVE_HOTKEY_FONT",
		function(size) ACAB:SetHotkeyFontSize(size) end
	)

	panel.hotkeyValueText = hotkeyValueText
	panel.hotkeySlider = hotkeySlider
	panel.hotkeyResetButton = hotkeyResetButton

	local countTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")

	-- must anchor off hotkeyTitle, not hotkeyValueText: a value text's left edge drifts with its digit count.
	countTitle:SetPoint(
		"TOPLEFT",
		hotkeyTitle,
		"BOTTOMLEFT",
		0,
		-12 - hotkeySlider:GetHeight() - 2 - hotkeyValueText:GetHeight() - 18
	)

	countTitle:SetText(FontSizeTitleText("Item Count"))

	panel.countTitle = countTitle

	local countSlider, countValueText, countResetButton = CreateFontSizeSlider(
		panel, countTitle, "ACABGeneralCountFontSizeSlider", "NATIVE_COUNT_FONT",
		function(size) ACAB:SetCountFontSize(size) end
	)

	panel.countValueText = countValueText
	panel.countSlider = countSlider
	panel.countResetButton = countResetButton

	-------------------------------------------------------------------------
	-- Global button border style (modern / vanilla); locked to vanilla under Force Vanilla Layout Mode
	-------------------------------------------------------------------------

	-- Anchored off countTitle (fixed X), not countValueText.
	local modernBorderStyleCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralModernBorderStyleCheckbox", {
		anchor = { "TOPLEFT", countTitle, "BOTTOMLEFT", 0, -12 - countSlider:GetHeight() - 2 - countValueText:GetHeight() - 18 },
		label = "Use Modern Button Style",
		tooltip = {
			title = "Use Modern Button Style",
			lines = {
				"Choose the button border style used by ALL bars. When " ..
				"enabled use a slick and thin modern rectangular Border, " ..
				"when disabled use the default vanilla UI border.",
				"Locked to vanilla UI Border while 'Force Vanilla Layout " ..
				"Mode' is enabled",
			},
		},
		onClick = function()
			-- Re-checks the Force Vanilla lock (RefreshGeneralPanel also blocks mouse input).
			if ACABDB.useDefaultLayout ~= false then
				this:SetChecked(false)
				return
			end

			ACABDB.modernBorderStyle = this:GetChecked() and true or false

			ACAB:ApplyGlobalButtonStyle()

			-- Re-applies the global spacing/size overrides for the new style's floor.
			ACAB:ApplyGlobalSpacing()
			ACAB:ApplyGlobalButtonSize()

			ACAB:RefreshDefaultLayoutGatingOnAllPages()

			-- Re-syncs the global spacing slider's range/labels to the new floor.
			ACAB:RefreshGeneralPanel()
		end,
	})

	panel.modernBorderStyleCheckbox = modernBorderStyleCheckbox

	-------------------------------------------------------------------------
	-- Global Spacing / Button size overrides: each slider is shown only while its checkbox is on.
	-- Applies to every bar (not simple pages); a bar opts out via its own lock icon.
	-------------------------------------------------------------------------

	-- OnClick is set below, once its slider exists.
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

	-- Range and end labels are set by RefreshGeneralPanel (they depend on the border style).
	local globalSpacingSlider, globalSpacingValueText, globalSpacingSliderLow, globalSpacingSliderHigh = ACAB:CreateLabeledSlider(
		panel,
		"ACABGeneralGlobalSpacingSlider",
		{
			anchor = { "TOPLEFT", globalSpacingCheckbox, "BOTTOMLEFT", 20, -28 },
			step = ACAB.SPACING_STEP,
			initialText = "0",
			round = RoundToInteger,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					ACABDB.globalSpacingValue = value
					ACAB:ApplyGlobalSpacing()
				end
			end,
		}
	)

	globalSpacingCheckbox:SetScript("OnClick", GlobalOverrideOnClick(
		panel, "globalSpacingEnabled", globalSpacingSlider, globalSpacingValueText,
		function() ACAB:ApplyGlobalSpacing() end
	))

	panel.globalSpacingCheckbox = globalSpacingCheckbox
	panel.globalSpacingSlider = globalSpacingSlider
	panel.globalSpacingSliderLow = globalSpacingSliderLow
	panel.globalSpacingSliderHigh = globalSpacingSliderHigh
	panel.globalSpacingValueText = globalSpacingValueText

	-- Anchored off the slider itself (-20 cancels its +20 indent), never its value text.
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
			round = RoundToInteger,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					ACABDB.globalButtonSizeValue = value
					ACAB:ApplyGlobalButtonSize()
				end
			end,
		}
	)

	globalButtonSizeCheckbox:SetScript("OnClick", GlobalOverrideOnClick(
		panel, "globalButtonSizeEnabled", globalButtonSizeSlider, globalButtonSizeValueText,
		function() ACAB:ApplyGlobalButtonSize() end
	))

	panel.globalButtonSizeCheckbox = globalButtonSizeCheckbox
	panel.globalButtonSizeSlider = globalButtonSizeSlider
	panel.globalButtonSizeValueText = globalButtonSizeValueText

	-- Lets bar 5 (Right ActionBar 2) toggle independently of bar 4.
	-- must anchor off a slider/checkbox edge, never a *ValueText FontString (centered under its slider).
	local bypassBar2DepCheckbox = ACAB:CreateLabeledCheckbox(panel, "ACABGeneralBypassBar2DepCheckbox", {
		anchor = { "TOPLEFT", globalButtonSizeSlider, "BOTTOMLEFT", -20, -28 },
		label = "Allow Right ActionBar 2 independent of Right ActionBar 1",
		onClick = function()
			ACABDB.bypassRightActionBar2Dependency = this:GetChecked() and true or false

			ACAB:FixRightActionBar2Checkbox()
		end,
	})

	panel.bypassBar2DepCheckbox = bypassBar2DepCheckbox

	panel:Hide()

	ACAB.settingsFrame.generalPanel = panel

	return panel
end

-------------------------------------------------------------------------
-- Profiles tab panel
-------------------------------------------------------------------------

-- Dropdown entry that opens the create-profile dialog (never a real profile name).
local CREATE_NEW_PROFILE_SENTINEL = "+ Create new profile"

-- Import dialog validator (returns ok, data-or-error).
local function ValidateImportText(value)
	return ACAB:ParseProfileImportString(value)
end

-- Profile dialogs shared by the Profiles tab and /acab profile.

-- Shows the active profile's export string in a selectable textarea.
function ACAB:ShowExportProfileDialog()
	self:ShowDialog({
		title = "Export Profile",
		message = "Copy the text below (Ctrl+C) to share this profile.",
		mode = "textarea",
		defaultText = self:ExportActiveProfileString(),
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
end

-- Pasted-string import onto the active profile (validated live), then reload.
function ACAB:ShowImportProfileDialog()
	self:ShowDialog({
		title = "Import Profile",
		message = "You are about to Import a Profile on to your currently " ..
			"active Profile " .. tostring(ACABCharDB and ACABCharDB.activeProfile),
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
end

-- Copy-into-targetName dialog, then reload: confirms sourceName if given, else a dropdown of the others.
function ACAB:ShowCopyProfileDialog(targetName, sourceName)
	local message = "Choose another profile to copy all settings from. ATTENTION: " ..
		"This action will override all settings present on the current " ..
		"profile and is not reversible."

	if sourceName then
		self:ShowDialog({
			title = "Copy From Other Profile",
			message = message,
			mode = "confirm",
			buttons = {
				{
					text = "Accept",
					onClick = function()
						ACAB:CopyProfileInto(sourceName, targetName)
						ReloadUI()
					end,
				},
				{ text = "Cancel", onClick = function() end },
			},
		})

		return
	end

	local otherProfiles = {}
	local names = self:GetProfileNames()
	local i

	for i = 1, table.getn(names) do
		if names[i] ~= targetName then
			table.insert(otherProfiles, names[i])
		end
	end

	self:ShowDialog({
		title = "Copy From Other Profile",
		message = message,
		mode = "dropdown",
		options = otherProfiles,
		buttons = {
			{
				text = "Accept",
				isDefault = false,
				onClick = function(value)
					if value then
						ACAB:CopyProfileInto(value, targetName)
						ReloadUI()
					end
				end,
			},
			{ text = "Cancel", onClick = function() end },
		},
	})
end

-- Creates a 22px StyleModernButton-styled button sized to its label.
local function CreateProfileButton(panel, text, point, relativeTo, relativePoint, x, y)
	local button = CreateFrame("Button", nil, panel)

	button:SetHeight(22)
	button:SetPoint(point, relativeTo, relativePoint, x, y)
	ACAB:StyleModernButton(button, 0, 0)
	button:SetText(text)

	return button
end

function ACAB:GetOrCreateProfilesPanel()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	if ACAB.settingsFrame.profilesPanel then
		return ACAB.settingsFrame.profilesPanel
	end

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

	-- Right-aligned on the label's row; Y is computed to match the label's top.
	local labelRowTopY = -(14 + title:GetHeight() + 20)

	local dropdown = ACAB:CreateInlineDropdown(panel, 220, "ACABProfilesDropdown")
	dropdown:ClearAllPoints()
	dropdown:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -ACAB.INDENT_SECTION, labelRowTopY)
	panel.profileDropdown = dropdown

	dropdown.onSelect = function(value)
		if value == CREATE_NEW_PROFILE_SENTINEL then
			ACAB:ShowCreateProfileDialog(function()
				-- Re-syncs the dropdown text so the sentinel never stays selected.
				ACAB:RefreshProfilesPanel()
			end)

			return
		end

		if value and value ~= ACABCharDB.activeProfile then
			ACAB:SwitchProfile(value)
		end
	end

	local PROFILE_BUTTON_GAP_X = 12

	local wizardButton = CreateProfileButton(panel, "Run Setup Wizard", "TOPLEFT", dropdown, "BOTTOMLEFT", 16, -14)
	ACAB:ApplyProminentButtonHighlight(wizardButton)
	panel.wizardButton = wizardButton

	-- On the Default profile this starts the create-new-profile wizard instead of overwriting Default.
	wizardButton:SetScript("OnClick", function()
		if ACABCharDB and ACABCharDB.activeProfile == ACAB.DEFAULT_PROFILE_NAME then
			ACAB:ShowSetupWizard()
			return
		end

		ACAB:ShowDialog({
			title = "Run Setup Wizard",
			message = "This walks you back through the initial setup choices " ..
				"(Force Vanilla Layout Mode, button style, global spacing/size).",
			warningText = "ATTENTION: Continuing will overwrite these settings " ..
				"on your current profile and is not reversible.",
			mode = "confirm",
			buttons = {
				{
					text = "Continue",
					onClick = function()
						ACAB:ShowSetupWizard({
							overwriteExisting = true,
							profileName = ACABCharDB.activeProfile,
						})
					end,
				},
				{ text = "Cancel", onClick = function() end },
			},
		})
	end)

	local exportButton = CreateProfileButton(panel, "Export Profile", "TOPLEFT", wizardButton, "TOPRIGHT", PROFILE_BUTTON_GAP_X, 0)
	panel.exportButton = exportButton

	exportButton:SetScript("OnClick", function()
		ACAB:ShowExportProfileDialog()
	end)

	local copyButton = CreateProfileButton(panel, "Copy from other profile", "TOPLEFT", exportButton, "TOPRIGHT", PROFILE_BUTTON_GAP_X, 0)
	panel.copyButton = copyButton

	copyButton:SetScript("OnClick", function()
		ACAB:ShowCopyProfileDialog(ACABCharDB.activeProfile)
	end)

	local importButton = CreateProfileButton(panel, "Import new Profile", "TOPLEFT", copyButton, "TOPRIGHT", PROFILE_BUTTON_GAP_X, 0)
	panel.importButton = importButton

	importButton:SetScript("OnClick", function()
		ACAB:ShowImportProfileDialog()
	end)

	local deleteButton = CreateProfileButton(panel, "Delete profile", "TOPLEFT", importButton, "TOPRIGHT", PROFILE_BUTTON_GAP_X, 0)
	ACAB:ApplyDangerButtonHighlight(deleteButton)
	panel.deleteButton = deleteButton

	-- Centers the 5-button row under the Active Profile row; the other buttons chain off wizardButton.
	local buttonRowY = labelRowTopY - math.max(label:GetHeight(), dropdown:GetHeight()) - 14
	local totalRowWidth = wizardButton:GetWidth() + exportButton:GetWidth() + copyButton:GetWidth()
		+ importButton:GetWidth() + deleteButton:GetWidth() + (PROFILE_BUTTON_GAP_X * 4)

	wizardButton:ClearAllPoints()
	wizardButton:SetPoint(
		"TOP", panel, "TOP",
		-(totalRowWidth / 2) + (wizardButton:GetWidth() / 2),
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

-- Syncs the profile dropdown; export/copy/import/delete are shown only on non-Default profiles.
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

	panel.wizardButton:Show()

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
-- Edit Mode panel (ACABDB.snapToAdjacentElements/showLayoutGrid/snapToGrid/useCustomGridSize)
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

	-- Snap to Adjacent Elements: read on the next drag, no apply needed.
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

	-- Show Layout Grid: refreshes the grid live while in Edit Layout Mode.
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

	-- Snap to Grid: read on the next drag, no apply needed.
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

	-- Use custom Grid Size: flat ACABDB.customGridSize instead of the Main-Bar-tracking spacing.
	-- OnClick is set below, once its slider exists.
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
			round = RoundToInteger,
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

	useCustomGridSizeCheckbox:SetScript("OnClick", function()
		local checked = this:GetChecked() and true or false

		if checked and not ACABDB.useCustomGridSize then
			-- Seeds the slider from the dynamic spacing; must read before the flag flips below.
			ACABDB.customGridSize = math.floor(ACAB:GetLayoutGridSpacing() + 0.5)
		end

		ACABDB.useCustomGridSize = checked

		customGridSizeSlider:SetShown(checked)
		customGridSizeValueText:SetShown(checked)

		if checked then
			ACAB:SetSliderValueSilently(customGridSizeSlider, ACABDB.customGridSize or 0, customGridSizeValueText)
		end

		if ACAB:IsEditMode() then
			ACAB:RebuildLayoutGrid()
		end

		if ACAB.settingsFrame.currentView == "editmode" then
			ACAB:DeferFit(function() ACAB:FitSettingsWindowToEditModeView() end)
		end
	end)

	panel.customGridSizeSlider = customGridSizeSlider
	panel.customGridSizeSliderLow = customGridSizeSliderLow
	panel.customGridSizeSliderHigh = customGridSizeSliderHigh
	panel.customGridSizeValueText = customGridSizeValueText

	panel:Hide()

	ACAB.settingsFrame.editModePanel = panel

	return panel
end

function ACAB:RefreshEditModePanel()
	local panel = self:GetOrCreateEditModePanel()

	panel.snapToAdjacentCheckbox:SetChecked(ACABDB.snapToAdjacentElements == true)
	panel.showLayoutGridCheckbox:SetChecked(ACABDB.showLayoutGrid == true)
	panel.snapToGridCheckbox:SetChecked(ACABDB.snapToGrid == true)

	local useCustomGridSize = ACABDB.useCustomGridSize == true

	panel.useCustomGridSizeCheckbox:SetChecked(useCustomGridSize)
	panel.customGridSizeSlider:SetShown(useCustomGridSize)
	panel.customGridSizeValueText:SetShown(useCustomGridSize)

	if useCustomGridSize then
		ACAB:SetSliderValueSilently(panel.customGridSizeSlider, ACABDB.customGridSize or 0, panel.customGridSizeValueText)
	end
end

-------------------------------------------------------------------------
-- General panel reflow: re-anchors the checkbox/slider stack so hidden optional sliders leave no gap
-- (Hide() alone keeps a frame's slot in its neighbors' anchor chain).
-------------------------------------------------------------------------

-- Stack columns (x indent) and vertical gaps between entry kinds.
local REFLOW_COLUMN_CHECKBOX = 0
local REFLOW_COLUMN_SLIDER = 20
local REFLOW_GAP_CHECKBOX_TO_SLIDER = -28
local REFLOW_GAP_SLIDER_TO_CHECKBOX = -26
local REFLOW_GAP_CHECKBOX_TO_CHECKBOX = -14

-- entries: ordered { frame, column = REFLOW_COLUMN_*, isOptional }. The first entry's anchor is never
-- touched; a hidden isOptional entry is skipped entirely, collapsing its slot.
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

-- Deferred refit of the General view, only while it is the view on screen.
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

	RefitGeneralViewSoon()
end

-- Re-anchors hotkeyTitle below the macro section (off macroTitle, not the drifting macroValueText).
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
		panel.hotkeyTitle:SetPoint("TOPLEFT", panel.macroTextCheckbox, "BOTTOMLEFT", 8, -22)
	end

	RefitGeneralViewSoon()
end

function ACAB:RefreshGeneralPanel()
	local panel = self:GetOrCreateGeneralPanel()

	panel.useDefaultLayoutCheckbox:SetChecked(ACABDB.useDefaultLayout == true)

	-- Style and global override controls lock while Force Vanilla Layout Mode forces vanilla styling.
	local vanillaBorderStyleLocked = ACABDB.useDefaultLayout ~= false

	panel.modernBorderStyleCheckbox:SetChecked(
		(not vanillaBorderStyleLocked) and ACABDB.modernBorderStyle == true
	)
	SetMouseLocked(panel.modernBorderStyleCheckbox, vanillaBorderStyleLocked)

	local spacingDisplayed = ACABDB.globalSpacingEnabled == true and
		not vanillaBorderStyleLocked

	panel.globalSpacingCheckbox:SetChecked(spacingDisplayed)
	SetMouseLocked(panel.globalSpacingCheckbox, vanillaBorderStyleLocked)

	local spacingOffset = ACAB:GetSpacingDisplayOffset()

	panel.globalSpacingSlider:SetMinMaxValues(0, ACAB.SPACING_MAX)

	if panel.globalSpacingSliderLow then
		panel.globalSpacingSliderLow:SetText("0")
	end

	if panel.globalSpacingSliderHigh then
		panel.globalSpacingSliderHigh:SetText(tostring(ACAB.SPACING_MAX))
	end

	-- Clamps the saved global spacing to the current style's max and reapplies it.
	local spacingMaxDisplayed = ACAB.SPACING_MAX
	if (ACABDB.globalSpacingValue or 0) > spacingMaxDisplayed then
		ACABDB.globalSpacingValue = spacingMaxDisplayed
		ACAB:ApplyGlobalSpacing()
	end

	ACAB:SetSliderValueSilently(panel.globalSpacingSlider, ACABDB.globalSpacingValue or 0, panel.globalSpacingValueText)

	panel.globalSpacingSlider:SetShown(spacingDisplayed)
	panel.globalSpacingValueText:SetShown(spacingDisplayed)
	SetMouseLocked(panel.globalSpacingSlider, vanillaBorderStyleLocked)

	local buttonSizeDisplayed = ACABDB.globalButtonSizeEnabled == true and
		not vanillaBorderStyleLocked

	panel.globalButtonSizeCheckbox:SetChecked(buttonSizeDisplayed)
	SetMouseLocked(panel.globalButtonSizeCheckbox, vanillaBorderStyleLocked)

	ACAB:SetSliderValueSilently(panel.globalButtonSizeSlider, ACABDB.globalButtonSizeValue or ACAB.BUTTON_SIZE, panel.globalButtonSizeValueText)

	panel.globalButtonSizeSlider:SetShown(buttonSizeDisplayed)
	panel.globalButtonSizeValueText:SetShown(buttonSizeDisplayed)
	SetMouseLocked(panel.globalButtonSizeSlider, vanillaBorderStyleLocked)

	-- Both sliders' shown state is final here - collapse/restore their gaps.
	ACAB:ReflowGeneralOverrideSliders(panel)

	panel.bypassBar2DepCheckbox:SetChecked(ACABDB.bypassRightActionBar2Dependency == true)
	panel.tintWholeButtonCheckbox:SetChecked(ACABDB.tintWholeButtonOnRange ~= false)
	panel.mainBarPaginationCheckbox:SetChecked(ACABDB.defaultBarPaginationEnabled ~= false)
	panel.mainBarStanceSwapCheckbox:SetChecked(ACABDB.defaultBarStanceSwapEnabled ~= false)

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

	ACAB:SetSliderValueSilently(panel.macroSlider, macroSize, panel.macroValueText)

	ACAB:ReflowGeneralHotkeySection(panel)

	-------------------------------------------------------------------------
	-- Hotkey / Count text font size (unset falls back to the captured native size)
	-------------------------------------------------------------------------

	local hotkeyDefault = ACAB.NATIVE_HOTKEY_FONT and ACAB.NATIVE_HOTKEY_FONT.size
	local hotkeySize = ACAB:ClampFontSize(ACABDB.hotkeyFontSize or hotkeyDefault)

	ACAB:SetSliderValueSilently(panel.hotkeySlider, hotkeySize, panel.hotkeyValueText)

	local countDefault = ACAB.NATIVE_COUNT_FONT and ACAB.NATIVE_COUNT_FONT.size
	local countSize = ACAB:ClampFontSize(ACABDB.countFontSize or countDefault)

	ACAB:SetSliderValueSilently(panel.countSlider, countSize, panel.countValueText)
end

-------------------------------------------------------------------------
-- View switching
-------------------------------------------------------------------------

-- Shows the gold select strip only on the tab matching settingsFrame.currentView.
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

-- Full-width views in hide order: settingsFrame keys and the ACAB methods that build/refresh/fit each.
local WIDE_VIEW_ORDER = { "general", "profiles", "editmode" }

local WIDE_VIEWS = {
	general = {
		scrollFrame = "generalScrollFrame",
		panel = "generalPanel",
		getOrCreate = "GetOrCreateGeneralPanel",
		refresh = "RefreshGeneralPanel",
		fit = "FitSettingsWindowToGeneralView",
	},
	profiles = {
		scrollFrame = "profilesScrollFrame",
		panel = "profilesPanel",
		getOrCreate = "GetOrCreateProfilesPanel",
		refresh = "RefreshProfilesPanel",
		fit = "FitSettingsWindowToProfilesView",
	},
	editmode = {
		scrollFrame = "editModeScrollFrame",
		panel = "editModePanel",
		getOrCreate = "GetOrCreateEditModePanel",
		refresh = "RefreshEditModePanel",
		fit = "FitSettingsWindowToEditModeView",
	},
}

-- Hides every built wide view's scrollframe and panel, in WIDE_VIEW_ORDER, except exceptKey's (optional).
function ACAB:HideWideViews(exceptKey)
	local frame = ACAB.settingsFrame
	local i

	for i = 1, table.getn(WIDE_VIEW_ORDER) do
		local key = WIDE_VIEW_ORDER[i]

		if key ~= exceptKey then
			local view = WIDE_VIEWS[key]

			if frame[view.scrollFrame] then
				frame[view.scrollFrame]:Hide()
			end

			if frame[view.panel] then
				frame[view.panel]:Hide()
			end
		end
	end
end

-- Hides the Bars view and the other wide views, then refreshes, shows and (next frame) fits this one.
local function ShowWideView(viewKey)
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	local frame = ACAB.settingsFrame
	local view = WIDE_VIEWS[viewKey]
	local id
	local page

	for id, page in pairs(frame.pages) do
		page:Hide()
	end

	frame.listPanel:Hide()
	frame.contentScrollFrame:Hide()
	frame.contentPanel:Hide()
	frame.currentView = viewKey
	ACAB:RefreshActiveTabHighlight()

	-- Builds the panel and its scrollframe before they are shown below.
	ACAB[view.getOrCreate](ACAB)

	ACAB:HideWideViews(viewKey)

	frame[view.scrollFrame]:Show()

	ACAB[view.refresh](ACAB)
	ACAB[view.getOrCreate](ACAB):Show()

	-- Fit runs after Show() so the measured rects are real.
	ACAB:DeferFit(function() ACAB[view.fit](ACAB) end)
end

function ACAB:ShowGeneralView()
	ShowWideView("general")
end

-- Pulses a gold highlight behind the Force Vanilla Layout Mode checkbox (lock-banner click target).
function ACAB:HighlightGeneralLayoutCheckbox()
	local panel = ACAB.settingsFrame and ACAB.settingsFrame.generalPanel
	local checkbox = panel and panel.useDefaultLayoutCheckbox

	if not checkbox then
		return
	end

	if not checkbox.acabHighlightStrip then
		local label = getglobal(checkbox:GetName() .. "Text")
		local labelWidth = (label and label:GetStringWidth()) or 200
		local strip = ACAB:CreateFadeStrip(panel, checkbox:GetWidth() + labelWidth + 16, checkbox:GetHeight() + 10, { edgeFraction = 0.15 })

		strip:SetPoint("LEFT", checkbox, "LEFT", -8, 0)
		strip:SetFadeColor(ACAB.UI_ACCENT_COLOR[1], ACAB.UI_ACCENT_COLOR[2], ACAB.UI_ACCENT_COLOR[3])
		strip:SetPeakAlpha(0.55)
		strip:Hide()

		checkbox.acabHighlightStrip = strip
	end

	local strip = checkbox.acabHighlightStrip

	strip:Show()

	-- Three pulses.
	if C_Timer then
		C_Timer.After(0.45, function() strip:Hide() end)
		C_Timer.After(0.75, function() strip:Show() end)
		C_Timer.After(1.2, function() strip:Hide() end)
		C_Timer.After(1.5, function() strip:Show() end)
		C_Timer.After(1.95, function() strip:Hide() end)
	end
end

function ACAB:ShowProfilesView()
	ShowWideView("profiles")
end

function ACAB:ShowEditModeView()
	ShowWideView("editmode")
end
