-- SettingsSimplePages.lua
-- Simple native-element settings pages (Bag Bar, Micro Menu, Key Ring, Latency/Cast/Exp Bar, Tooltip, native-mode
-- Pet/Stance Bar): one builder + refresh driven by ACAB.simpleBarPageConfigs, and the configs themselves.
-- Must load after Settings.lua (ACAB.simpleBarPageConfigs init) and SettingsBars.lua.

local ACAB = AlternativeClassicActionBars

-- Same value as SettingsBars.lua's SWATCH_SIZE.
local SWATCH_SIZE = 46

-------------------------------------------------------------------------
-- Experience Bar page helpers
-------------------------------------------------------------------------

-- "<label> [swatch]" row at (INDENT_CONTROL, y) opening the color picker. Returns the swatch.
local function CreateExpBarColorRow(page, y, labelText, swatchName, getter, setter)
	local label = ACAB:CreateReflowText(page, "GameFontNormalSmall", ACAB.INDENT_CONTROL, y, labelText)

	local swatch = ACAB:CreateColorSwatch(page, swatchName)
	swatch:SetPoint("LEFT", label, "RIGHT", 12, 0)
	swatch.acabLabel = label
	swatch:SetScript("OnClick", function()
		ACAB:OpenColorPicker(swatch, getter, setter, ACAB.settingsFrame)
	end)

	return swatch
end

-- One Better Experience Bar text-segment toggle writing ACABDB[dbKey].
local function CreateExpBarTextToggleCheckbox(page, name, labelText, y, dbKey)
	return ACAB:CreateLabeledCheckbox(page, "ACABSimplePageExpBar" .. name .. "Checkbox", {
		anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, y },
		label = labelText,
		onClick = function()
			local checked = this:GetChecked() and true or false
			ACABDB[dbKey] = checked
			ACAB:ApplyBetterExpBarVisual()
		end,
	})
end

-- The 5 text-segment toggles, in display order.
local EXP_BAR_TEXT_TOGGLES = {
	{ name = "ShowLevel", label = "Show Current Lvl", dbKey = "expBarShowLevel", field = "expBarShowLevelCheckbox" },
	{ name = "ShowCurrentOverMax", label = "Show Current XP / Max", dbKey = "expBarShowCurrentOverMax", field = "expBarShowCurrentOverMaxCheckbox" },
	{ name = "ShowPercent", label = "Show Current % / Max", dbKey = "expBarShowPercent", field = "expBarShowPercentCheckbox" },
	{ name = "ShowRestedPercent", label = "Show Current Rested XP %", dbKey = "expBarShowRestedPercent", field = "expBarShowRestedPercentCheckbox" },
	{ name = "ShowRestedTotal", label = "Show Current Total Rested XP", dbKey = "expBarShowRestedTotal", field = "expBarShowRestedTotalCheckbox" },
}

-- Enables (or dims + disables mouse on) every Better Experience Bar sub-control per its checkbox.
local function ApplyBetterExpBarGating(page)
	if not page or not page.betterExpBarCheckbox then return end

	local interactive = page.betterExpBarCheckbox:GetChecked() and true or false
	local alpha = interactive and 1 or 0.5
	local controls = {
		page.expBarShowLevelCheckbox,
		page.expBarShowCurrentOverMaxCheckbox,
		page.expBarShowPercentCheckbox,
		page.expBarShowRestedPercentCheckbox,
		page.expBarShowRestedTotalCheckbox,
		page.expBarFontSizeSlider,
		page.earnedColorSwatch,
		page.restedColorSwatch,
		page.expBarTextColorSwatch,
		page.resetColorsButton,
		page.expBarGlowPulseIntervalSlider,
	}

	local i
	for i = 1, table.getn(controls) do
		local control = controls[i]
		if control then
			control:EnableMouse(interactive)
			control:SetAlpha(alpha)

			if control.acabLabel then
				control.acabLabel:SetAlpha(alpha)
			end
		end
	end
end

-------------------------------------------------------------------------
-- Simple bar pages: Position + optional Enabled/hover-only/Spacing/Scale/Grid + Reset buttons
-------------------------------------------------------------------------

local function CreateSimpleBarPage(key)
	local config = ACAB.simpleBarPageConfigs[key]
	if not config then return nil end

	local page = CreateFrame("Frame", nil, ACAB.settingsFrame.contentPanel)
	ACAB:ApplyPageBannerReserve(page, false)
	page.barId = key
	page.isDefault = true
	page.profileLockWarning = ACAB:CreateProfileLockWarning(page)

	-- Anchored to contentPanel so it stays put while the page slides down.
	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", ACAB.settingsFrame.contentPanel, "TOPLEFT", ACAB.INDENT_SECTION, -14)
	title:SetText(config.title .. " Settings (Default)")

	-- Group lock icon, top right.
	if ACAB.GROUPABLE_SIMPLE_PAGES[key] then
		page.groupLockButton = ACAB:CreateGroupLockButton(
			page,
			"ACABSimplePage" .. key .. "GroupLockButton",
			{ "TOPRIGHT", ACAB.settingsFrame.contentPanel, "TOPRIGHT", -20, -14 },
			config.title .. " Grouped with Main Bar",
			key
		)
	end

	local enableCheckboxY = -44
	local topY = -46

	if config.hasEnable then
		local enableCheckbox = ACAB:CreateLabeledCheckbox(page, "ACABSimplePage" .. key .. "EnableCheckbox", {
			anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, enableCheckboxY },
			label = "Enabled",
			onClick = function()
				local checked = this:GetChecked() and true or false
				config.setEnabled(checked)
				ACAB:RefreshBarList()
			end,
		})

		page.enableCheckbox = enableCheckbox
		topY = enableCheckboxY - 24 - 14
	end

	if config.hasHoverOnly then
		topY = topY - ACAB:CreateHoverOnlyControls(
			page,
			topY,
			config.getHoverOnly,
			config.setHoverOnly,
			config.getHoverDuration,
			config.setHoverDuration,
			key
		)
	end

	-- Native-mode Pet Bar: switch back to the styled grid from here too.
	if key == ACAB.PET_BAR_ID then
		ACAB:CreateUseVanillaBarCheckbox(page, topY, "Pet", ACAB.PET_BAR_ID, "useNativePetBar")
		topY = topY - 24 - 14
		ACAB:CreateCondenseEmptyPetSlotsCheckbox(page, topY)
		topY = topY - 24 - 14
	end

	-- Native-mode Stance Bar: same.
	if key == ACAB.STANCE_BAR_ID then
		ACAB:CreateUseVanillaBarCheckbox(page, topY, "Stance", ACAB.STANCE_BAR_ID, "useNativeStanceBar")
		topY = topY - 24 - 14
	end

	-- Tooltip Grows From: which GameTooltip corner anchors to the box's matching corner.
	if key == "tooltip" then
		local row, dropdown = ACAB:CreateDropdownRow(page, topY, "Tooltip Grows From", 180, "ACABTooltipAnchorCornerDropdown", {
			{ text = "Bottom Right (Default)", value = "BOTTOMRIGHT" },
			{ text = "Bottom Left", value = "BOTTOMLEFT" },
			{ text = "Top Right", value = "TOPRIGHT" },
			{ text = "Top Left", value = "TOPLEFT" },
		})

		local function RefreshTooltipAnchorCorner()
			dropdown:SetSelected(ACABDB.tooltipAnchorCorner or "BOTTOMRIGHT")
		end

		dropdown.onSelect = function(value)
			ACAB:SetTooltipAnchorCorner(value)
			RefreshTooltipAnchorCorner()
		end

		RefreshTooltipAnchorCorner()

		-- Listed in assignmentRows so ApplyProfileLockGating's dropdown sweep locks it too.
		page.tooltipAnchorCornerRow = row
		page.assignmentRows = { row }
		topY = topY - 32 - 14
	end

	-- Clamp range from the element's real frame size, or the generic screen range without one.
	local minX, maxX, minY, maxY

	if config.getElementFrame then
		minX, maxX, minY, maxY = ACAB:GetSimplePageCoordinateRange(config, config.getElementFrame())
	else
		minX, maxX, minY, maxY = ACAB:GetScreenCoordinateRange()
	end

	-- Position. onApply fires every drag tick, so it only refuses the value while grouped.
	local xLabel, yLabel, ySliderY = ACAB:CreatePositionSection(page, "ACABSimplePage" .. key, topY, minX, maxX, minY, maxY,
		function(applied)
			if ACAB:RevertIfGroupLocked(key) then return end

			local y = page.yAppliedValue or page.ySlider:GetValue()
			config.setPosition(applied, y)
		end,
		function(applied)
			if ACAB:RevertIfGroupLocked(key) then return end

			local x = page.xAppliedValue or page.xSlider:GetValue()
			config.setPosition(x, applied)
		end
	)

	page.xLabel = xLabel
	page.yLabel = yLabel
	local cursorY = ySliderY - 36

	-- Spacing (config.hasSpacing)
	if config.hasSpacing then
		-- config.spacingMin overrides the shared floor (Micro Menu: -10).
		local spacingMin = config.spacingMin or ACAB.SPACING_MIN
		local spacingTitleY = cursorY
		local spacingSliderY = spacingTitleY - 26
		page.spacingTitle = ACAB:CreateReflowText(page, "GameFontNormal", ACAB.INDENT_SECTION, spacingTitleY,
			"Spacing (" .. tostring(spacingMin) .. " to " .. tostring(ACAB.SPACING_MAX) .. ")"
		)

		local spacingSlider, spacingValueText = ACAB:CreateReflowSlider(
			page,
			"ACABSimplePage" .. key .. "SpacingSlider",
			spacingSliderY,
			{
				min = spacingMin,
				max = ACAB.SPACING_MAX,
				step = ACAB.SPACING_STEP,
				lowText = tostring(spacingMin),
				highText = tostring(ACAB.SPACING_MAX),
				initialText = "0",
				round = function(value) return math.floor(value + 0.5) end,
				format = tostring,
				onChange = function(value, suppressApply)
					if not suppressApply then
						if ACAB:RevertIfGroupLocked(key) then return end

						-- Stored spacing = displayed value - spacingUiOffset (Micro Menu only).
						local uiOffset = config.spacingUiOffset or 0
						config.setSpacing(value - uiOffset)
					end

					ACAB:RefreshSimplePositionSliderRange(page, key)
				end,
			}
		)

		page.spacingValueText = spacingValueText
		page.spacingSlider = spacingSlider
		cursorY = spacingSliderY - 36
	end

	-- Scale (config.hasScale)
	if config.hasScale then
		local scaleTitleY = cursorY
		local scaleSliderY = scaleTitleY - 26
		page.scaleTitle = ACAB:CreateReflowText(page, "GameFontNormal", ACAB.INDENT_SECTION, scaleTitleY, "Scale (0.5 to 2.0)")

		local scaleSlider, scaleValueText = ACAB:CreateReflowSlider(
			page,
			"ACABSimplePage" .. key .. "ScaleSlider",
			scaleSliderY,
			{
				min = 0.5,
				max = 2.0,
				step = 0.1,
				lowText = "0.5",
				highText = "2.0",
				initialText = "1.0",
				round = function(value) return math.floor((value * 10) + 0.5) / 10 end,
				format = function(value) return string.format("%.1f", value) end,
				onChange = function(value, suppressApply)
					if not suppressApply then
						if ACAB:RevertIfGroupLocked(key) then return end

						config.setScale(value)

						-- Must be a full page refresh (re-syncs X/Y before re-clamping), or the position jumps.
						ACAB:RefreshSimpleBarPage(key)
					else
						ACAB:RefreshSimplePositionSliderRange(page, key)
					end
				end,
			}
		)

		page.scaleValueText = scaleValueText
		page.scaleSlider = scaleSlider
		cursorY = scaleSliderY - 36
	end

	-- Grid Layout (config.hasGrid)
	if config.hasGrid then
		local swatchY = cursorY - 26
		ACAB:CreateGridLayoutSection(page, key, cursorY, swatchY)

		-- Swatch + caption line + gap.
		cursorY = swatchY - SWATCH_SIZE - 14 - 14
	end

	-- Better Experience Bar (Experience Bar page only), independent of Enabled
	if key == "expbar" then
		local betterExpBarCheckbox = ACAB:CreateLabeledCheckbox(page, "ACABSimplePageExpBarBetterCheckbox", {
			anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, cursorY },
			label = "Enable Better Experience Bar",
			tooltip = {
				title = "Enable Better Experience Bar",
				lines = {
					"Replaces the native percent label with a customizable text " ..
					"line, and lets you recolor the bar's own fill and rested-" ..
					"bonus fill below.",
				},
			},
			onClick = function()
				local checked = this:GetChecked() and true or false
				ACABDB.betterExpBarEnabled = checked
				ACAB:ApplyBetterExpBarVisual()

				-- Applies the saved colors when turning on (no-op when off).
				ACAB:ApplyExpBarColors()
				ApplyBetterExpBarGating(page)
			end,
		})

		page.betterExpBarCheckbox = betterExpBarCheckbox
		ACAB:AddHoverOnlyReflowRow(page, betterExpBarCheckbox, ACAB.INDENT_SECTION, cursorY)
		cursorY = cursorY - 24 - 14

		-- Overlay Text Size: same range/step as the General tab's Hotkey/Count Text Size sliders.
		local fontSizeTitleY = cursorY
		local fontSizeSliderY = fontSizeTitleY - 26
		ACAB:CreateReflowText(page, "GameFontNormal", ACAB.INDENT_SECTION, fontSizeTitleY,
			"Overlay Text Size (" .. tostring(ACAB.FONT_SIZE_MIN) ..
			" to " .. tostring(ACAB.FONT_SIZE_MAX) .. ")"
		)

		local fontSizeSlider, fontSizeValueText = ACAB:CreateReflowSlider(
			page,
			"ACABSimplePageExpBarFontSizeSlider",
			fontSizeSliderY,
			{
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
						ACAB:SetExpBarFontSize(value)
					end
				end,
			}
		)

		page.expBarFontSizeValueText = fontSizeValueText
		page.expBarFontSizeSlider = fontSizeSlider
		cursorY = fontSizeSliderY - 36
		local ti
		for ti = 1, table.getn(EXP_BAR_TEXT_TOGGLES) do
			local toggle = EXP_BAR_TEXT_TOGGLES[ti]
			local checkbox = CreateExpBarTextToggleCheckbox(page, toggle.name, toggle.label, cursorY, toggle.dbKey)
			page[toggle.field] = checkbox
			ACAB:AddHoverOnlyReflowRow(page, checkbox, ACAB.INDENT_SECTION, cursorY)
			cursorY = cursorY - 24 - 6
		end

		cursorY = cursorY - 12
		page.earnedColorSwatch = CreateExpBarColorRow(page, cursorY, "Earned XP Bar Color", "ACABSimplePageExpBarEarnedColorSwatch",
			function() return ACABDB.expBarColorEarned end,
			function(r, g, b) ACAB:SetExpBarColorEarned(r, g, b) end
		)

		cursorY = cursorY - 24 - 14
		page.restedColorSwatch = CreateExpBarColorRow(page, cursorY, "Rested XP Bar Color", "ACABSimplePageExpBarRestedColorSwatch",
			function() return ACABDB.expBarColorRested end,
			function(r, g, b) ACAB:SetExpBarColorRested(r, g, b) end
		)

		cursorY = cursorY - 24 - 14
		page.expBarTextColorSwatch = CreateExpBarColorRow(page, cursorY, "Overlay Text Color", "ACABSimplePageExpBarTextColorSwatch",
			function() return ACABDB.expBarTextColor end,
			function(r, g, b) ACAB:SetExpBarTextColor(r, g, b) end
		)

		cursorY = cursorY - 24 - 14
		page.resetColorsButton = ACAB:CreateReflowResetButton(page, cursorY, "Reset Colors to Default", function()
			ACAB:ResetExpBarColors()
			ACAB:RefreshBarSettingsPage("expbar")
		end)

		cursorY = cursorY - 22 - 26
		local pulseIntervalTitleY = cursorY
		local pulseIntervalSliderY = pulseIntervalTitleY - 26
		ACAB:CreateReflowText(page, "GameFontNormal", ACAB.INDENT_SECTION, pulseIntervalTitleY, "Rested Glow Pulse Interval (0.5 to 5.0 sec)")

		local pulseIntervalSlider, pulseIntervalValueText = ACAB:CreateReflowSlider(
			page,
			"ACABSimplePageExpBarPulseIntervalSlider",
			pulseIntervalSliderY,
			{
				min = 0.5,
				max = 5.0,
				step = 0.1,
				lowText = "0.5",
				highText = "5.0",
				initialText = "1.5",
				round = function(value) return math.floor((value * 10) + 0.5) / 10 end,
				format = function(value) return string.format("%.1f", value) end,
				onChange = function(value, suppressApply)
					if not suppressApply then
						ACAB:SetExpBarGlowPulseInterval(value)
					end
				end,
			}
		)

		page.expBarGlowPulseIntervalValueText = pulseIntervalValueText
		page.expBarGlowPulseIntervalSlider = pulseIntervalSlider
		cursorY = pulseIntervalSliderY - 36
	end

	-- Reset buttons. Must defer the page refresh one frame: the clamp range reads the element's new size.
	local resetY = cursorY
	page.resetPositionButton = ACAB:CreateReflowResetButton(page, resetY, "Reset to Vanilla Layout", function()
		config.reset()
		ACAB:DeferFit(function() ACAB:RefreshBarSettingsPage(key) end)
	end)

	if config.resetModern then
		page.resetModernButton = ACAB:CreateReflowResetButton(page, resetY - 30, "Reset to Modern Layout Default", function()
			config.resetModern()
			ACAB:DeferFit(function() ACAB:RefreshBarSettingsPage(key) end)
		end)
	end

	-- Grouped-with-Main-Bar guard on every GROUP_LOCK_CONTROL_NAMES control; must run once the Reset buttons exist.
	if ACAB.GROUPABLE_SIMPLE_PAGES[key] then
		local controlNames = config.hasSpacing and "Position/Spacing/Scale" or "Position/Scale"
		local lockedText = config.title .. " is grouped with Main Bar while Gryphons / Background Art is enabled - its own " .. controlNames .. " controls are locked."

		local function IsElementLocked()
			return ACAB:IsElementGrouped(key)
		end

		local function OnLockedClick()
			ACAB:HighlightMainBarArtModeDropdownFromElsewhere()
		end

		local i
		for i = 1, table.getn(ACAB.GROUP_LOCK_CONTROL_NAMES) do
			local control = page[ACAB.GROUP_LOCK_CONTROL_NAMES[i]]
			if control then
				ACAB:InstallGroupLockGuard(control, IsElementLocked, lockedText, OnLockedClick)
			end
		end

		ACAB:ApplySimpleElementGroupedLock(page)
	end

	page:Hide()
	page.acabSimplePage = true
	ACAB.settingsFrame.pages[key] = page
	return page
end

function ACAB:GetOrCreateSimpleBarPage(key)
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	ACAB:DropMismatchedBarPage(key)

	if ACAB.settingsFrame.pages[key] then
		return ACAB.settingsFrame.pages[key]
	end

	return CreateSimpleBarPage(key)
end

function ACAB:RefreshSimpleBarPage(key)
	if not ACAB.settingsFrame then return end

	ACAB:DropMismatchedBarPage(key)
	local page = ACAB.settingsFrame.pages[key]
	local config = ACAB.simpleBarPageConfigs[key]
	if not page or not config then return end

	-- Must suppress apply/snap first: SetMinMaxValues fires OnValueChanged like a real drag.
	page.xSlider.suppressApply = true
	page.ySlider.suppressApply = true
	page.xSlider.suppressSnap = true
	page.ySlider.suppressSnap = true

	-- Re-clamp against the element's current footprint (scale/spacing/grid changes and resets route here).
	if config.getElementFrame then
		local frame = config.getElementFrame()
		if frame then
			local rawPos = config.getPosition()
			local minX, maxX, minY, maxY = ACAB:GetSimplePageCoordinateRange(config, frame)
			page.xSlider:SetMinMaxValues(minX, maxX)
			page.ySlider:SetMinMaxValues(minY, maxY)

			-- A bigger footprint can push an edge off-screen: clamp and persist (canonical positions only).
			if rawPos and config.setPosition and ACAB:IsCanonicalPosition(rawPos) then
				local clampedX = ACAB:Clamp(rawPos.x or 0, minX, maxX)
				local clampedY = ACAB:Clamp(rawPos.y or 0, minY, maxY)
				if clampedX ~= rawPos.x or clampedY ~= rawPos.y then
					config.setPosition(clampedX, clampedY)
				end
			end
		end
	end

	local pos = config.getPosition() or { x = 0, y = 0 }
	page.xSlider:SetValue(pos.x or 0)
	page.ySlider:SetValue(pos.y or 0)

	-- Set explicitly: SetValue doesn't fire OnValueChanged when the value is unchanged.
	page.xAppliedValue = pos.x or 0
	page.yAppliedValue = pos.y or 0
	page.xValueText:SetText(string.format("%.2f", pos.x or 0))
	page.yValueText:SetText(string.format("%.2f", pos.y or 0))
	page.xSlider.suppressApply = nil
	page.ySlider.suppressApply = nil
	page.xSlider.suppressSnap = nil
	page.ySlider.suppressSnap = nil

	if page.enableCheckbox and config.getEnabled then
		page.enableCheckbox:SetChecked(config.getEnabled() ~= false)
	end

	-- While forced, the mode checkboxes show the vanilla-forced value instead of the stored preference.
	if page.useVanillaPetBarCheckbox or page.condenseEmptyPetSlotsCheckbox then
		local petLocked = ACAB:IsVanillaModeForced()
		local petCfg = ACABDB.defaultBars and ACABDB.defaultBars[ACAB.PET_BAR_ID]

		if page.useVanillaPetBarCheckbox then
			page.useVanillaPetBarCheckbox:SetChecked(petLocked or ACAB:IsPetBarNativeMode())
		end

		if page.condenseEmptyPetSlotsCheckbox then
			page.condenseEmptyPetSlotsCheckbox:SetChecked(
				(not petLocked) and petCfg and petCfg.condenseEmptyPetSlots == true
			)
		end
	end

	if page.useVanillaStanceBarCheckbox then
		page.useVanillaStanceBarCheckbox:SetChecked(ACAB:IsVanillaModeForced() or ACAB:IsStanceBarNativeMode())
	end

	if page.spacingSlider and config.getSpacing then
		-- Displayed value = stored spacing + spacingUiOffset (Micro Menu only).
		local uiOffset = config.spacingUiOffset or 0
		local spacing = ACAB:Clamp((config.getSpacing() or 0) + uiOffset, config.spacingMin or ACAB.SPACING_MIN, ACAB.SPACING_MAX)
		ACAB:SetSliderValueSilently(page.spacingSlider, spacing, page.spacingValueText)
	end

	if page.scaleSlider and config.getScale then
		local scale = ACAB:Clamp(config.getScale() or 1, 0.5, 2.0)
		ACAB:SetSliderValueSilently(page.scaleSlider, scale, page.scaleValueText, string.format("%.1f", scale))
	end

	if page.gridSwatches and config.getGridLayout then
		local cols, rows = config.getGridLayout()
		ACAB:RefreshGridSwatchSelection(page, cols, rows)
	end

	if config.hasHoverOnly then
		self:RefreshHoverOnlyControls(page, config.getHoverOnly(), config.getHoverDuration())
	end

	if page.tooltipAnchorCornerRow and page.tooltipAnchorCornerRow.dropdown then
		page.tooltipAnchorCornerRow.dropdown:SetSelected(ACABDB.tooltipAnchorCorner or "BOTTOMRIGHT")
	end

	-- Better Experience Bar controls read their ACABDB fields directly.
	if page.betterExpBarCheckbox then
		page.betterExpBarCheckbox:SetChecked(ACABDB.betterExpBarEnabled == true)
		local ti
		for ti = 1, table.getn(EXP_BAR_TEXT_TOGGLES) do
			local toggle = EXP_BAR_TEXT_TOGGLES[ti]
			if page[toggle.field] then
				page[toggle.field]:SetChecked(ACABDB[toggle.dbKey] == true)
			end
		end

		-- ACABDB.expBarFontSize stays nil until the slider is first moved; defaults to EXP_BAR_DEFAULT_FONT_SIZE.
		if page.expBarFontSizeSlider then
			ACAB:CaptureNativeExpBarFontIfNeeded()
			local fontSize = ACAB:ClampFontSize(ACABDB.expBarFontSize or ACAB.EXP_BAR_DEFAULT_FONT_SIZE)
			ACAB:SetSliderValueSilently(page.expBarFontSizeSlider, fontSize, page.expBarFontSizeValueText)
		end

		if page.earnedColorSwatch then
			ACAB:SetColorSwatchColor(page.earnedColorSwatch, ACABDB.expBarColorEarned)
		end

		if page.restedColorSwatch then
			ACAB:SetColorSwatchColor(page.restedColorSwatch, ACABDB.expBarColorRested)
		end

		if page.expBarTextColorSwatch then
			ACAB:SetColorSwatchColor(page.expBarTextColorSwatch, ACABDB.expBarTextColor)
		end

		if page.expBarGlowPulseIntervalSlider then
			local interval = ACABDB.expBarGlowPulseInterval or 1.5
			ACAB:SetSliderValueSilently(page.expBarGlowPulseIntervalSlider, interval,
				page.expBarGlowPulseIntervalValueText, string.format("%.1f", interval))
		end
	end

	-- Pet Bar/Stance Bar/Cast Bar/Tooltip stay editable under Force Vanilla Layout Mode.
	local skipLayoutLock = key == ACAB.PET_BAR_ID or key == ACAB.STANCE_BAR_ID or key == "castbar" or key == "tooltip"
	ACAB:ApplyDefaultLayoutGating(page, skipLayoutLock or ACABDB.useDefaultLayout ~= true)
	self:ApplyProfileLockGating(page, not skipLayoutLock)

	-- Must run after ApplyProfileLockGating, which re-enables the Better Experience Bar sub-controls.
	if page.betterExpBarCheckbox and not self:IsDefaultProfileActive() and
		(skipLayoutLock or ACABDB.useDefaultLayout ~= true) then
		ApplyBetterExpBarGating(page)
	end

	-- Mode checkboxes stay locked by Default Layout/Profile; must run after ApplyProfileLockGating.
	local vanillaModeLocked = ACAB:IsVanillaModeLocked()

	if page.useVanillaPetBarCheckbox then
		ACAB:LockControlKeepingTooltip(page.useVanillaPetBarCheckbox, vanillaModeLocked)
	end

	if page.condenseEmptyPetSlotsCheckbox then
		ACAB:LockControlKeepingTooltip(page.condenseEmptyPetSlotsCheckbox, vanillaModeLocked)
	end

	if page.useVanillaStanceBarCheckbox then
		ACAB:LockControlKeepingTooltip(page.useVanillaStanceBarCheckbox, vanillaModeLocked)
	end

	-- Only ever dims - must run after both gating calls above.
	ACAB:ApplySimpleElementGroupedLock(page)
end

-------------------------------------------------------------------------
-- Simple page configs: each page's controls mapped onto the element's ACAB:Set*/Reset*/Get* API
-------------------------------------------------------------------------

-- Stance Bar native mode (numeric STANCE_BAR_ID, reached only via IsStanceBarNativeMode). Drives the
-- native-mode ACABDB.stanceBar* fields, separate from the styled mode's defaultBars[STANCE_BAR_ID].
ACAB.simpleBarPageConfigs[ACAB.STANCE_BAR_ID] = {
	title = "Stance Bar",
	hasEnable = true,
	getPosition = function() return ACABDB.stanceBarPosition end,
	setPosition = function(x, y) ACAB:SetStanceBarPosition(x, y) end,
	getElementFrame = function() return ACAB.stanceBarContainer end,
	-- Layout before position (both resets): layout writes scale without reapplying position.
	reset = function()
		ACAB:ResetStanceBarLayout()
		ACAB:ResetStanceBarPosition()
	end,
	resetModern = function()
		ACAB:ResetStanceBarLayout()
		ACAB:ResetStanceBarPositionToModernBase()
	end,
	getEnabled = function() return ACABDB.stanceBarEnabled end,
	setEnabled = function(v) ACAB:SetStanceBarEnabled(v) end,
	hasSpacing = true,
	getSpacing = function() return ACABDB.stanceBarSpacing end,
	setSpacing = function(v) ACAB:SetStanceBarSpacing(v) end,
	hasScale = true,
	getScale = function() return ACABDB.stanceBarScale end,
	setScale = function(v) ACAB:SetStanceBarScale(v) end,
	-- Hover-only is shared with the styled Stance Bar: defaultBars[STANCE_BAR_ID].hoverOnly/hoverDuration.
	hasHoverOnly = true,
	getHoverOnly = function()
		local cfg = ACABDB.defaultBars[ACAB.STANCE_BAR_ID]
		return cfg and cfg.hoverOnly
	end,
	setHoverOnly = function(v) ACAB:SetStanceBarNativeHoverOnly(v) end,
	getHoverDuration = function()
		local cfg = ACABDB.defaultBars[ACAB.STANCE_BAR_ID]
		return (cfg and cfg.hoverDuration) or 3
	end,
	setHoverDuration = function(v) ACAB:SetStanceBarNativeHoverDuration(v) end,
}

-- Bag Bar: ACAB-owned chain-anchored container, so it also gets Spacing/Scale/Grid.
ACAB.simpleBarPageConfigs["bagbar"] = {
	title = "Bag Bar",
	hasEnable = true,
	getPosition = function() return ACABDB.bagBarPosition end,
	setPosition = function(x, y) ACAB:SetBagBarPosition(x, y) end,
	getElementFrame = function() return ACAB.bagBarContainer end,
	-- Layout before position: layout writes scale without reapplying position.
	reset = function()
		ACAB:ResetBagBarLayout()
		ACAB:ResetBagBarPosition()
	end,
	resetModern = function() ACAB:ResetBagBarLayoutToModernBase() end,
	getEnabled = function() return ACABDB.bagBarEnabled end,
	setEnabled = function(v) ACAB:SetBagBarEnabled(v) end,
	hasSpacing = true,
	getSpacing = function() return ACABDB.bagBarSpacing end,
	setSpacing = function(v) ACAB:SetBagBarSpacing(v) end,
	hasScale = true,
	getScale = function() return ACABDB.bagBarScale end,
	setScale = function(v) ACAB:SetBagBarScale(v) end,
	hasGrid = true,
	-- Swatch clicks call ACAB:SetBagBarOrientation directly (GridSwatch_OnClick); this only syncs the selection.
	getGridLayout = function() return ACAB:GetBagBarEffectiveGrid() end,
	hasHoverOnly = true,
	getHoverOnly = function() return ACABDB.bagBarHoverOnly end,
	setHoverOnly = function(v) ACAB:SetBagBarHoverOnly(v) end,
	getHoverDuration = function() return ACABDB.bagBarHoverDuration or 3 end,
	setHoverDuration = function(v) ACAB:SetBagBarHoverDuration(v) end,
}

-- Key Ring: the single real KeyRingButton frame, independent of Bag Bar.
ACAB.simpleBarPageConfigs["keyring"] = {
	title = "Key Ring",
	hasEnable = true,
	getPosition = function() return ACABDB.keyRingPosition end,
	setPosition = function(x, y) ACAB:SetKeyRingPosition(x, y) end,
	getElementFrame = function() return getglobal(ACAB.KEYRING_BUTTON_NAME) end,
	reset = function() ACAB:ResetKeyRingPosition() end,
	resetModern = function() ACAB:ResetKeyRingLayoutToModernBase() end,
	getEnabled = function() return ACABDB.keyRingEnabled end,
	setEnabled = function(v) ACAB:SetKeyRingEnabled(v) end,
	hasScale = true,
	getScale = function() return ACABDB.keyRingScale end,
	setScale = function(v) ACAB:SetKeyRingScale(v) end,
	hasHoverOnly = true,
	getHoverOnly = function() return ACABDB.keyRingHoverOnly end,
	setHoverOnly = function(v) ACAB:SetKeyRingHoverOnly(v) end,
	getHoverDuration = function() return ACABDB.keyRingHoverDuration or 3 end,
	setHoverDuration = function(v) ACAB:SetKeyRingHoverDuration(v) end,
}

-- Pet Bar native mode (numeric PET_BAR_ID, reached only via IsPetBarNativeMode). Shares
-- defaultBars[PET_BAR_ID] with the styled mode, so x/y/spacing never drift between modes.
ACAB.simpleBarPageConfigs[ACAB.PET_BAR_ID] = {
	title = "Pet Bar",
	hasEnable = true,
	getPosition = function() return ACABDB.defaultBars[ACAB.PET_BAR_ID] end,
	setPosition = function(x, y) ACAB:SetPetBarNativePosition(x, y) end,
	getElementFrame = function() return ACAB.petBarNativeContainer end,
	reset = function() ACAB:ResetPetBarNativeLayout() end,
	resetModern = function() ACAB:ResetPetBarLayoutToModernBase() end,
	getEnabled = function()
		local cfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
		return cfg and cfg.enabled
	end,
	setEnabled = function(v) ACAB:SetDefaultBarEnabled(ACAB.PET_BAR_ID, v) end,
	hasSpacing = true,
	getSpacing = function()
		local cfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
		return cfg and cfg.spacing
	end,
	setSpacing = function(v) ACAB:SetPetBarNativeSpacing(v) end,
	hasScale = true,
	getScale = function()
		local cfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
		return cfg and cfg.scale
	end,
	setScale = function(v) ACAB:SetPetBarNativeScale(v) end,
	-- Hover-only shared with the styled Pet Bar, like the Stance Bar's.
	hasHoverOnly = true,
	getHoverOnly = function()
		local cfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
		return cfg and cfg.hoverOnly
	end,
	setHoverOnly = function(v) ACAB:SetPetBarNativeHoverOnly(v) end,
	getHoverDuration = function()
		local cfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
		return (cfg and cfg.hoverDuration) or 3
	end,
	setHoverDuration = function(v) ACAB:SetPetBarNativeHoverDuration(v) end,
}

-- Latency Bar: Scale only - Blizzard owns MainMenuBarPerformanceBarFrame's internal layout.
ACAB.simpleBarPageConfigs["latencybar"] = {
	title = "Latency Bar",
	hasEnable = true,
	getPosition = function() return ACABDB.latencyBarPosition end,
	setPosition = function(x, y) ACAB:SetLatencyBarPosition(x, y) end,
	getElementFrame = function() return getglobal(ACAB.LATENCY_BAR_FRAME_NAME) end,
	reset = function()
		ACAB:ResetLatencyBarLayout()
	end,
	resetModern = function() ACAB:ResetLatencyBarLayoutToModernBase() end,
	getEnabled = function() return ACABDB.latencyBarEnabled end,
	setEnabled = function(v) ACAB:SetLatencyBarEnabled(v) end,
	hasScale = true,
	getScale = function() return ACABDB.latencyBarScale end,
	setScale = function(v) ACAB:SetLatencyBarScale(v) end,
	hasHoverOnly = true,
	getHoverOnly = function() return ACABDB.latencyBarHoverOnly end,
	setHoverOnly = function(v) ACAB:SetLatencyBarHoverOnly(v) end,
	getHoverDuration = function() return ACABDB.latencyBarHoverDuration or 3 end,
	setHoverDuration = function(v) ACAB:SetLatencyBarHoverDuration(v) end,
}

-- Experience Bar: the container's Position/Scale/Enable/Reset (Better Experience Bar controls are separate).
ACAB.simpleBarPageConfigs["expbar"] = {
	title = "Experience Bar",
	hasEnable = true,
	getPosition = function() return ACABDB.expBarPosition end,
	setPosition = function(x, y) ACAB:SetExpBarPosition(x, y) end,
	getElementFrame = function() return getglobal(ACAB.EXP_BAR_FRAME_NAME) end,
	-- Extra Y-max headroom in real screen pixels (lets the top sliver go off-screen).
	extraMaxYPixels = 2,
	reset = function()
		ACAB:ResetExpBarLayout()
	end,
	resetModern = function()
		ACAB:ResetExpBarLayoutToModernBase()
	end,
	getEnabled = function() return ACABDB.expBarEnabled end,
	setEnabled = function(v) ACAB:SetExpBarEnabled(v) end,
	hasScale = true,
	getScale = function() return ACABDB.expBarScale end,
	setScale = function(v) ACAB:SetExpBarScale(v) end,
	hasHoverOnly = true,
	getHoverOnly = function() return ACABDB.expBarHoverOnly end,
	setHoverOnly = function(v) ACAB:SetExpBarHoverOnly(v) end,
	getHoverDuration = function() return ACABDB.expBarHoverDuration or 3 end,
	setHoverDuration = function(v) ACAB:SetExpBarHoverDuration(v) end,
}

-- Cast Bar: Position + Scale only, no Enable checkbox.
ACAB.simpleBarPageConfigs["castbar"] = {
	title = "Cast Bar",
	getPosition = function() return ACABDB.castBarPosition end,
	setPosition = function(x, y) ACAB:SetCastBarPosition(x, y) end,
	getElementFrame = function() return getglobal(ACAB.CAST_BAR_FRAME_NAME) end,
	reset = function()
		ACAB:ResetCastBarLayout()
	end,
	-- No Modern Layout position of its own (it stacks off the default bars) - same as the vanilla reset.
	resetModern = function()
		ACAB:ResetCastBarLayout()
	end,
	hasScale = true,
	getScale = function() return ACABDB.castBarScale end,
	setScale = function(v) ACAB:SetCastBarScale(v) end,
}

-- Tooltip: repositions only the fixed-position GameTooltip; widget-relative tooltips are untouched.
ACAB.simpleBarPageConfigs["tooltip"] = {
	title = "Tooltip",
	hasEnable = true,
	getPosition = function() return ACABDB.tooltipPosition end,
	setPosition = function(x, y) ACAB:SetTooltipPosition(x, y) end,
	getElementFrame = function() return ACAB.tooltipFrame end,
	reset = function()
		ACAB:ResetTooltipLayout()
	end,
	-- No Modern Layout position of its own - same as the vanilla reset.
	resetModern = function()
		ACAB:ResetTooltipLayout()
	end,
	getEnabled = function() return ACABDB.tooltipEnabled end,
	setEnabled = function(v) ACAB:SetTooltipEnabled(v) end,
	hasScale = true,
	getScale = function() return ACABDB.tooltipScale end,
	setScale = function(v) ACAB:SetTooltipScale(v) end,
}

ACAB.simpleBarPageConfigs["micromenu"] = {
	title = "Micro Menu",
	hasEnable = true,
	getPosition = function() return ACABDB.microMenuPosition end,
	setPosition = function(x, y) ACAB:SetMicroMenuPosition(x, y) end,
	getElementFrame = function() return ACAB.microMenuContainer end,
	extraMaxYPixels = 4,
	-- Layout before position: layout writes scale without reapplying position.
	reset = function()
		ACAB:ResetMicroMenuLayout()
		ACAB:ResetMicroMenuPosition()
	end,
	resetModern = function() ACAB:ResetMicroMenuLayoutToModernBase() end,
	getEnabled = function() return ACABDB.microMenuEnabled end,
	setEnabled = function(v) ACAB:SetMicroMenuEnabled(v) end,
	hasSpacing = true,
	-- -10 floor instead of ACAB.SPACING_MIN, so the native buttons can overlap slightly.
	spacingMin = -10,
	-- Displayed = stored spacing + 4 (the native button art's padding makes 0 look like a gap).
	spacingUiOffset = 4,
	getSpacing = function() return ACABDB.microMenuSpacing end,
	setSpacing = function(v) ACAB:SetMicroMenuSpacing(v) end,
	hasScale = true,
	getScale = function() return ACABDB.microMenuScale end,
	setScale = function(v) ACAB:SetMicroMenuScale(v) end,
	hasGrid = true,
	-- Swatch clicks call ACAB:SetMicroMenuLayout directly (GridSwatch_OnClick); this only syncs the selection.
	getGridLayout = function() return ACAB:GetMicroMenuEffectiveGrid() end,
	hasHoverOnly = true,
	getHoverOnly = function() return ACABDB.microMenuHoverOnly end,
	setHoverOnly = function(v) ACAB:SetMicroMenuHoverOnly(v) end,
	getHoverDuration = function() return ACABDB.microMenuHoverDuration or 3 end,
	setHoverDuration = function(v) ACAB:SetMicroMenuHoverDuration(v) end,
}
