-- SettingsBars.lua
-- Bar settings pages (default/custom bars) and their refresh/gating, page-building helpers shared with
-- SettingsSimplePages.lua, the bar-list sidebar and the default bars' stance/page assignment rows.
-- Must load after Settings.lua.

local ACAB = AlternativeClassicActionBars

-- Grid Layout presets in display order; each set totals its bar's button count (12 here).
local GRID_PRESETS = {
	{ rows = 1,  cols = 12 },
	{ rows = 2,  cols = 6  },
	{ rows = 3,  cols = 4  },
	{ rows = 4,  cols = 3  },
	{ rows = 6,  cols = 2  },
	{ rows = 12, cols = 1  },
}

-- Pet Bar: 10 buttons.
local PET_BAR_GRID_PRESETS = {
	{ rows = 1,  cols = 10 },
	{ rows = 2,  cols = 5  },
	{ rows = 5,  cols = 2  },
	{ rows = 10, cols = 1  },
}

-- Micro Menu: 8 buttons.
local MICRO_MENU_GRID_PRESETS = {
	{ rows = 1, cols = 8 },
	{ rows = 2, cols = 4 },
	{ rows = 4, cols = 2 },
	{ rows = 8, cols = 1 },
}

-- Bag Bar: 5 buttons, horizontal or vertical (ACABDB.bagBarOrientation).
local BAG_BAR_GRID_PRESETS = {
	{ rows = 1, cols = 5 },
	{ rows = 5, cols = 1 },
}

-- Every exact factor pair (rows, cols) of the live stance count, e.g. 4 -> 1x4, 2x2, 4x1. Empty for <= 0.
local function GetStanceBarGridOptions(count)
	local presets = {}
	local n = 0

	if not count or count <= 0 then
		return presets
	end

	local d
	for d = 1, count do
		if count - (math.floor(count / d) * d) == 0 then
			n = n + 1
			presets[n] = { rows = d, cols = count / d }
		end
	end

	return presets
end

-- Preset list a bar's Grid Layout swatches are built from.
local function GetGridPresetsForBar(barId)
	if barId == ACAB.PET_BAR_ID then
		return PET_BAR_GRID_PRESETS
	end

	if barId == "micromenu" then
		return MICRO_MENU_GRID_PRESETS
	end

	if barId == "bagbar" then
		return BAG_BAR_GRID_PRESETS
	end

	if barId == ACAB.STANCE_BAR_ID then
		return GetStanceBarGridOptions(ACAB:GetClampedLiveStanceCount())
	end

	return GRID_PRESETS
end

-- Display names for the string-keyed simple pages; numeric ids use ACAB:GetBarDisplayName.
local SIMPLE_BAR_NAMES = {
	bagbar = "Bag Bar",
	keyring = "Key Ring",
	micromenu = "Micro Menu",
	latencybar = "Latency Bar",
	expbar = "Experience Bar",
	castbar = "Cast Bar",
	tooltip = "Tooltip",
}

-- True while the Pet Bar's stored "Use Vanilla Pet Bar" flag is on.
function ACAB:IsPetBarNativeMode()
	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[ACAB.PET_BAR_ID]
	return cfg and cfg.useNativePetBar == true
end

-- True while the Stance Bar's stored "Use Vanilla Stance Bar" flag is on.
function ACAB:IsStanceBarNativeMode()
	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[ACAB.STANCE_BAR_ID]
	return cfg and cfg.useNativeStanceBar == true
end

-- True when barId's page is a simple page: native-mode Pet/Stance Bar, or any string-keyed element.
local function UsesSimpleBarPage(barId)
	if barId == ACAB.PET_BAR_ID then
		return ACAB:IsPetBarNativeMode()
	end

	if barId == ACAB.STANCE_BAR_ID then
		return ACAB:IsStanceBarNativeMode()
	end

	return ACAB.simpleBarPageConfigs[barId] ~= nil
end

-- Hides and uncaches a Pet/Stance page whose kind (simple vs full) no longer matches its native-mode flag.
function ACAB:DropMismatchedBarPage(barId)
	if barId ~= ACAB.PET_BAR_ID and barId ~= ACAB.STANCE_BAR_ID then return end

	local pages = ACAB.settingsFrame and ACAB.settingsFrame.pages
	local page = pages and pages[barId]
	if page and (page.acabSimplePage == true) ~= UsesSimpleBarPage(barId) then
		page:Hide()
		pages[barId] = nil
	end
end

local function GetBarDisplayName(barId)
	if SIMPLE_BAR_NAMES[barId] then
		return SIMPLE_BAR_NAMES[barId]
	end

	return ACAB:GetBarDisplayName(barId)
end

-- value limited to [low, high] (low checked first).
function ACAB:Clamp(value, low, high)
	if value < low then
		value = low
	end

	if value > high then
		value = high
	end

	return value
end

-- True while the Default profile or Force Vanilla Layout Mode pins Pet/Stance Bar to native mode.
function ACAB:IsVanillaModeLocked()
	return ACAB:IsDefaultProfileActive() or ACABDB.useDefaultLayout == true
end

-- True while Force Vanilla Layout Mode forces Pet/Stance Bar native, whatever their stored flags say.
function ACAB:IsVanillaModeForced()
	return ACABDB.useDefaultLayout ~= false
end

-- Bar 5 can only be enabled while bar 4 is, unless the General tab's bypass option is on.
local function IsBar5EnableAllowed()
	local bar4Cfg = ACABDB.defaultBars[4]
	return ACABDB.bypassRightActionBar2Dependency == true
		or (bar4Cfg and bar4Cfg.enabled == true)
end

-------------------------------------------------------------------------
-- Hover-only slider show/hide reflow
-- The duration slider only takes space while its checkbox is checked; everything below shifts to match.
-------------------------------------------------------------------------

-- Registers frame at its collapsed baseline x/y for ReflowRowsBelowHoverOnly (ACAB method: 32-upvalue cap).
function ACAB:AddHoverOnlyReflowRow(page, frame, x, y)
	if not frame then return end

	if not page.hoverOnlyReflowRows then
		page.hoverOnlyReflowRows = {}
	end

	table.insert(page.hoverOnlyReflowRows, { frame = frame, x = x, y = y })
end

-- Shifts every registered row down by sliderRowHeight while the slider is shown, back to baseline while hidden.
-- page.hoverOnlyExtraReflow (optional) repositions content that isn't a registered row (grid swatches).
function ACAB:ReflowRowsBelowHoverOnly(page, sliderShown, sliderRowHeight)
	local offset = sliderShown and sliderRowHeight or 0

	if page.hoverOnlyReflowRows then
		local i
		for i = 1, table.getn(page.hoverOnlyReflowRows) do
			local row = page.hoverOnlyReflowRows[i]
			row.frame:ClearAllPoints()
			row.frame:SetPoint("TOPLEFT", page, "TOPLEFT", row.x, row.y - offset)
		end
	end

	if page.hoverOnlyExtraReflow then
		page.hoverOnlyExtraReflow(offset)
	end
end

-------------------------------------------------------------------------
-- Page-building helpers shared by GetOrCreateBarPage and CreateSimpleBarPage
-------------------------------------------------------------------------

-- TOPLEFT-anchored FontString at (x, y) on page, registered for hover-only reflow.
function ACAB:CreateReflowText(page, font, x, y, text)
	local fontString = page:CreateFontString(nil, "OVERLAY", font)
	fontString:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
	fontString:SetText(text)
	ACAB:AddHoverOnlyReflowRow(page, fontString, x, y)
	return fontString
end

-- ACAB:CreateLabeledSlider anchored at (INDENT_INPUT, y), registered for hover-only reflow. Same returns.
function ACAB:CreateReflowSlider(page, name, y, config)
	config.anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_INPUT, y }

	local slider, valueText, lowLabel, highLabel = ACAB:CreateLabeledSlider(page, name, config)
	ACAB:AddHoverOnlyReflowRow(page, slider, ACAB.INDENT_INPUT, y)
	return slider, valueText, lowLabel, highLabel
end

-- ACAB:CreateLabeledCheckbox anchored at (INDENT_SECTION, y), registered for hover-only reflow.
function ACAB:CreateReflowCheckbox(page, name, y, config)
	config.anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, y }
	local checkbox = ACAB:CreateLabeledCheckbox(page, name, config)
	ACAB:AddHoverOnlyReflowRow(page, checkbox, ACAB.INDENT_SECTION, y)
	return checkbox
end

-- 200px ACAB:CreateResetButton at (INDENT_INPUT, y), registered for hover-only reflow.
function ACAB:CreateReflowResetButton(page, y, text, onClick)
	local button = ACAB:CreateResetButton(page, {
		anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_INPUT, y },
		minWidth = 200,
		maxWidth = 200,
		text = text,
		onClick = onClick,
	})

	ACAB:AddHoverOnlyReflowRow(page, button, ACAB.INDENT_INPUT, y)
	return button
end

-- 500x32 row: 180px label + inline dropdown (row.dropdown). Anchored at (INDENT_SECTION, y) when y is given.
-- Returns row, dropdown.
function ACAB:CreateDropdownRow(parent, y, labelText, dropdownWidth, dropdownName, options)
	local row = CreateFrame("Frame", nil, parent)
	row:SetWidth(500)
	row:SetHeight(32)

	if y then
		row:SetPoint("TOPLEFT", parent, "TOPLEFT", ACAB.INDENT_SECTION, y)
	end

	local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("LEFT", row, "LEFT", 0, 0)
	label:SetWidth(180)
	label:SetJustifyH("LEFT")
	label:SetText(labelText)

	local dropdown = ACAB:CreateInlineDropdown(row, dropdownWidth, dropdownName)
	dropdown:SetPoint("LEFT", label, "RIGHT", -8, -2)
	dropdown:SetOptions(options)
	row.label = label
	row.dropdown = dropdown
	return row, dropdown
end

-- "X"/"Y" labels + position sliders starting at labelY. Returns xLabel, yLabel and the Y slider's y.
function ACAB:CreatePositionSection(page, namePrefix, labelY, minX, maxX, minY, maxY, onApplyX, onApplyY)
	local xSliderY = labelY + 4
	local yLabelY = xSliderY - 40
	local ySliderY = yLabelY + 4

	local xLabel = ACAB:CreateReflowText(page, "GameFontNormalSmall", ACAB.INDENT_CONTROL, labelY, "X")
	ACAB:CreatePositionAxisSlider(page, {
		axisKey = "x",
		namePrefix = namePrefix,
		anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_INPUT, xSliderY },
		min = minX,
		max = maxX,
		lowText = "Left",
		highText = "Right",
		onApply = onApplyX,
	})

	local yLabel = ACAB:CreateReflowText(page, "GameFontNormalSmall", ACAB.INDENT_CONTROL, yLabelY, "Y")
	ACAB:CreatePositionAxisSlider(page, {
		axisKey = "y",
		namePrefix = namePrefix,
		anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_INPUT, ySliderY },
		min = minY,
		max = maxY,
		lowText = "Down",
		highText = "Up",
		onApply = onApplyY,
	})

	return xLabel, yLabel, ySliderY
end

-- Sets (on = true) or clears (on = nil) suppressApply/suppressSnap on a page's X/Y sliders.
function ACAB:SetPositionSlidersSuppressed(page, on)
	page.xSlider.suppressApply = on
	page.ySlider.suppressApply = on
	page.xSlider.suppressSnap = on
	page.ySlider.suppressSnap = on
end

-- Shows x/y on a page's X/Y sliders and value texts; xAppliedValue/yAppliedValue are set explicitly,
-- since SetValue doesn't fire OnValueChanged when the value is unchanged.
function ACAB:SyncPositionSliders(page, x, y)
	page.xSlider:SetValue(x)
	page.ySlider:SetValue(y)
	page.xAppliedValue = x
	page.yAppliedValue = y
	page.xValueText:SetText(string.format("%.2f", x))
	page.yValueText:SetText(string.format("%.2f", y))
end

-------------------------------------------------------------------------
-- Pet/Stance Bar mode checkboxes
-------------------------------------------------------------------------

-- Locked tooltips for the Use Vanilla checkboxes (default profile takes priority); each ends with what its click does.
local VANILLA_MODE_LOCKED_TEXT_PROFILE =
	"Can't change while using the default profile. Set up a profile in " ..
	"Profile Settings to enable this Setting. " ..
	"|cffffd100Click to create one now.|r"

local VANILLA_MODE_LOCKED_TEXT_LAYOUT =
	"Can't change while Force Vanilla Layout Mode is enabled. " ..
	"Disable it in General Settings to enable this Setting. " ..
	"|cffffd100Click to jump to General Settings.|r"

local function GetVanillaModeLockedText()
	if ACAB:IsDefaultProfileActive() then
		return VANILLA_MODE_LOCKED_TEXT_PROFILE
	end

	return VANILLA_MODE_LOCKED_TEXT_LAYOUT
end

-- "Use Vanilla <kind> Bar" checkbox (kind "Pet"/"Stance") for both the grid page and the native page.
-- Confirms, writes defaultBars[barId][cfgKey] and reloads. Stored as page.useVanilla<kind>BarCheckbox.
function ACAB:CreateUseVanillaBarCheckbox(page, y, kind, barId, cfgKey)
	local barName = kind .. " Bar"
	local title = "Use Vanilla " .. barName

	local checkbox = ACAB:CreateReflowCheckbox(page, "ACAB" .. kind .. "BarUseVanillaCheckbox", y, {
		label = title,
		tooltip = {
			title = title,
			lines = {
				"While enabled, this addon's Hoverbind mode cannot bind keys on " ..
				"the " .. barName .. ". Use the real Blizzard Keybindings menu instead, or " ..
				"disable this option.",
			},
		},
		lockedText = GetVanillaModeLockedText,
		onLockedClick = function() ACAB:HandleLockReasonClick() end,
		onClick = function()
			local checked = this:GetChecked() and true or false
			local clickedCheckbox = this
			ACAB:ShowDialog({
				title = title,
				message = "Switching the " .. barName .. "'s style rebuilds its buttons and requires a UI reload. " ..
					"While enabled, this addon's Hoverbind mode cannot bind keys on the " .. barName .. " - use " ..
					"the real Blizzard Keybindings menu instead, or disable this option.",
				mode = "confirm",
				buttons = {
					{
						text = "Reload Now",
						isDefault = true,
						onClick = function()
							local cfg = ACABDB.defaultBars[barId]
							if cfg then
								cfg[cfgKey] = checked
							end

							if barId == ACAB.STANCE_BAR_ID then
								ACAB:CarryStanceBarPositionToMode(checked)
							end

							ReloadUI()
						end,
					},
					{
						text = "Cancel",
						onClick = function()
							clickedCheckbox:SetChecked(not checked)
						end,
					},
				},
			})
		end,
	})

	page["useVanilla" .. kind .. "BarCheckbox"] = checkbox
	return checkbox
end

-- "Condense empty Button Space" (both Pet Bar pages): applies live, re-running whichever mode's shape is active.
function ACAB:CreateCondenseEmptyPetSlotsCheckbox(page, y)
	local checkbox = ACAB:CreateReflowCheckbox(page, "ACABPetBarCondenseCheckbox", y, {
		label = "Condense empty Button Space",
		lockedText = GetVanillaModeLockedText,
		onLockedClick = function() ACAB:HandleLockReasonClick() end,
		onClick = function()
			local checked = this:GetChecked() and true or false
			local cfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
			if cfg then
				cfg.condenseEmptyPetSlots = checked
			end

			ACAB:ApplyDefaultBarShape(ACAB.PET_BAR_ID)
			ACAB:ApplyPetBarNativeShape()

			if ACAB:IsPetBarNativeMode() then
				ACAB:RefreshSimpleBarPage(ACAB.PET_BAR_ID)
			else
				ACAB:RefreshPositionSliderRange(page)
			end
		end,
	})

	page.condenseEmptyPetSlotsCheckbox = checkbox
	return checkbox
end

-- Re-applies the animated/static auto-cast glow to existing styled Pet Bar buttons.
local function RefreshPetBarAutoCastGlowState()
	local bar = ACAB.bars and ACAB.bars[ACAB.PET_BAR_ID]
	if not bar or not bar.buttons then return end

	local i
	for i = 1, table.getn(bar.buttons) do
		local btn = bar.buttons[i]
		if btn and btn.UpdateState then
			btn:UpdateState()
		end
	end
end

-- "Animate Auto-Cast Toggle" (styled Pet Bar page only).
local function CreateAnimateAutoCastGlowCheckbox(page, y)
	local checkbox = ACAB:CreateReflowCheckbox(page, "ACABPetBarAnimateAutoCastCheckbox", y, {
		label = "Animate Auto-Cast Toggle",
		onClick = function()
			local checked = this:GetChecked() and true or false
			local cfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]
			if cfg then
				cfg.animateAutoCastGlow = checked
			end

			RefreshPetBarAutoCastGlowState()
		end,
	})

	page.animateAutoCastGlowCheckbox = checkbox
	return checkbox
end

local LIST_ROW_HEIGHT = 24
local LIST_ROW_GAP    = 4

-- Bar-list row highlight spans f.listPanel's inner rectangle (140 wide, 2px insets).
local LIST_ITEM_VISUAL_OFFSET = 2
local LIST_ITEM_VISUAL_WIDTH = 140 - (LIST_ITEM_VISUAL_OFFSET * 2)
local SWATCH_SIZE = 46
local SWATCH_GAP  = 8
local SWATCH_PAD  = 4

-------------------------------------------------------------------------
-- Only show on hover - checkbox + fade-out slider, shown only while checked
-------------------------------------------------------------------------

-- Vertical space the checkbox row / slider row take in callers' layout math.
ACAB.HOVER_ONLY_CHECKBOX_ROW_HEIGHT = 24 + 14
ACAB.HOVER_ONLY_SLIDER_ROW_HEIGHT = 17 + 20

-- Per-call suffix so each checkbox/slider pair gets unique frame names.
local hoverOnlyControlsCounter = 0

-- idOrKey: the page's barId or simple-page key, refitted after a live reflow. Returns the checkbox row height.
function ACAB:CreateHoverOnlyControls(page, y, getEnabled, setEnabled, getDuration, setDuration, idOrKey)
	hoverOnlyControlsCounter = hoverOnlyControlsCounter + 1
	local suffix = tostring(hoverOnlyControlsCounter)

	-- OnClick is set below, once the slider exists.
	local checkbox = ACAB:CreateLabeledCheckbox(page, "ACABHoverOnlyCheckbox" .. suffix, {
		anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, y },
		label = "Only show on hover",
		tooltip = {
			title = "Only show on hover",
			lines = {
				"When enabled, this Element will be hidden until Mouseover.",
				"When enabled a new Slider appears to set how long the Element stays visible after a Mouseover Event until it disappears again.",
			},
		},
	})

	local sliderY = y - 24 - 14

	local fadeOutLabel = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fadeOutLabel:SetPoint("TOPLEFT", page, "TOPLEFT", ACAB.INDENT_CONTROL, sliderY)
	fadeOutLabel:SetText("Fade out time")

	local slider, valueText = ACAB:CreateLabeledSlider(page, "ACABHoverOnlyDurationSlider" .. suffix, {
		width = 225,
		anchor = { "TOPLEFT", page, "TOPLEFT", 150, sliderY + 4 },
		min = 0,
		max = 10,
		step = 0.5,
		lowText = "0s",
		highText = "10s",
		initialText = "3.0s",
		round = function(value) return math.floor((value * 2) + 0.5) / 2 end,
		format = function(value) return string.format("%.1fs", value) end,
		onChange = function(value, suppressApply)
			if not suppressApply then
				setDuration(value)
			end
		end,
	})

	checkbox:SetScript("OnClick", function()
		local checked = this:GetChecked() and true or false
		setEnabled(checked)
		fadeOutLabel:SetShown(checked)
		slider:SetShown(checked)
		valueText:SetShown(checked)
		self:ReflowRowsBelowHoverOnly(page, checked, self.HOVER_ONLY_SLIDER_ROW_HEIGHT)
		ACAB:DeferFit(function() ACAB:FitSettingsWindowToBarPage(idOrKey) end)
	end)

	local startEnabled = getEnabled() == true
	fadeOutLabel:SetShown(startEnabled)
	slider:SetShown(startEnabled)
	valueText:SetShown(startEnabled)
	page.hoverOnlyCheckbox = checkbox
	page.hoverOnlyFadeLabel = fadeOutLabel
	page.hoverDurationSlider = slider
	page.hoverDurationValueText = valueText
	return self.HOVER_ONLY_CHECKBOX_ROW_HEIGHT
end

-- Syncs the hover-only controls from saved config. No-op if the page has none.
function ACAB:RefreshHoverOnlyControls(page, enabled, duration)
	if not page.hoverOnlyCheckbox then return end

	enabled = enabled == true
	duration = self:ClampHoverDuration(duration) or 3
	page.hoverOnlyCheckbox:SetChecked(enabled)

	if page.hoverOnlyFadeLabel then
		page.hoverOnlyFadeLabel:SetShown(enabled)
	end

	if page.hoverDurationSlider then
		ACAB:SetSliderValueSilently(page.hoverDurationSlider, duration)
		page.hoverDurationSlider:SetShown(enabled)
	end

	if page.hoverDurationValueText then
		page.hoverDurationValueText:SetText(string.format("%.1fs", duration))
		page.hoverDurationValueText:SetShown(enabled)
	end

	self:ReflowRowsBelowHoverOnly(page, enabled, self.HOVER_ONLY_SLIDER_ROW_HEIGHT)
end

-------------------------------------------------------------------------
-- Grid preset swatches
-- Small WHITE8X8 cell-grid previews; clicking one applies that layout immediately.
-------------------------------------------------------------------------

local function CreateGridSwatch(parent, preset)
	local swatch = CreateFrame("Button", nil, parent)
	swatch:SetWidth(SWATCH_SIZE)
	swatch:SetHeight(SWATCH_SIZE)
	swatch:SetBackdrop(ACAB.PANEL_BACKDROP)

	swatch:SetBackdropColor(0, 0, 0, 0.35)
	swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	swatch.rows = preset.rows
	swatch.cols = preset.cols
	local maxDim = preset.rows
	if preset.cols > maxDim then
		maxDim = preset.cols
	end

	local avail = SWATCH_SIZE - (SWATCH_PAD * 2)
	local cellSize = math.floor(avail / maxDim)
	if cellSize < 1 then
		cellSize = 1
	end

	local r
	local c
	for r = 0, preset.rows - 1 do
		for c = 0, preset.cols - 1 do
			local tex = swatch:CreateTexture(nil, "ARTWORK")
			tex:SetTexture("Interface\\Buttons\\WHITE8X8")
			tex:SetVertexColor(0.8, 0.8, 0.8, 0.9)
			tex:SetWidth(cellSize - 1)
			tex:SetHeight(cellSize - 1)
			tex:SetPoint("TOPLEFT", swatch, "TOPLEFT", SWATCH_PAD + (c * cellSize), -(SWATCH_PAD + (r * cellSize)))
		end
	end

	local caption = swatch:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	caption:SetPoint("TOP", swatch, "BOTTOM", 0, -2)
	caption:SetText(tostring(preset.cols) .. "x" .. tostring(preset.rows))
	swatch.caption = caption
	return swatch
end

local function GridSwatch_OnClick()
	local page = this.page
	if not page then return end

	local barId = page.barId

	-- Must be checked before page.isDefault, which is true on every simple page.
	if barId == "micromenu" then
		ACAB:SetMicroMenuLayout(this.cols, this.rows)
	elseif barId == "bagbar" then
		ACAB:SetBagBarOrientation(this.cols == 1)
	elseif page.isDefault then
		ACAB:SetDefaultBarLayout(barId, this.cols, this.rows)
	else
		local bar = ACAB.bars[barId]
		if bar then
			ACAB:SetBarLayout(bar, this.cols, this.rows)
		end
	end

	ACAB:RefreshBarSettingsPage(barId)
end

-- Red "why is this locked" line plus the gold "Click to highlight the Setting" line.
function ACAB:ShowGroupLockedTooltip(ownerFrame, mainText)
	GameTooltip:SetOwner(ownerFrame, "ANCHOR_RIGHT")
	GameTooltip:SetText(mainText, 1, 0.15, 0.15, 1, true)
	GameTooltip:AddLine("Click to highlight the Setting", 1, 0.82, 0, true)
	GameTooltip:Show()
end

-- Wraps OnEnter/OnLeave/OnClick (sliders: OnMouseDown): while isLocked(), shows lockedText and runs onLockedClick.
-- Must be installed after the control's own OnClick is set - it wraps the existing handler.
function ACAB:InstallGroupLockGuard(control, isLocked, lockedText, onLockedClick)
	local originalEnter = control:GetScript("OnEnter")
	local originalLeave = control:GetScript("OnLeave")
	control:SetScript("OnEnter", function()
		if originalEnter then
			originalEnter()
		end

		if isLocked() then
			ACAB:ShowGroupLockedTooltip(this, lockedText)
		end
	end)

	control:SetScript("OnLeave", function()
		if originalLeave then
			originalLeave()
		end

		GameTooltip:Hide()
	end)

	if control:GetObjectType() == "Slider" then
		local originalMouseDown = control:GetScript("OnMouseDown")
		control:SetScript("OnMouseDown", function()
			if originalMouseDown then
				originalMouseDown()
			end

			if isLocked() then
				onLockedClick()
			end
		end)
	else
		local originalClick = control:GetScript("OnClick")
		control:SetScript("OnClick", function()
			if isLocked() then
				onLockedClick()
				return
			end

			if originalClick then
				originalClick()
			end
		end)
	end
end

-- Hidden, locked "<title>" lock icon right of slider, toggling the bar's cfg[unlockedKey] opt-out of the General
-- tab's global override; re-locking runs ACAB:<applyMethod>(bar). Shown/synced by RefreshBarPageGlobalOverrideGating.
local function CreateGlobalOverrideLockButton(page, name, slider, title, unlockedKey, applyMethod)
	local button = ACAB:CreateLockToggleButton(page, name, {
		anchor = { "LEFT", slider, "RIGHT", 4, 0 },
		tooltipTitle = title,
		lockedLine = "Locked to the General tab's global " .. title .. ". Click to unlock and set an independent value for this bar.",
		unlockedLine = "Unlocked - independent of the General tab's global " .. title .. ". Click to re-lock and sync it.",
		onClick = function()
			local cfg = ACAB:GetBarConfig(page.barId)
			if not cfg then return end

			cfg[unlockedKey] = not (cfg[unlockedKey] == true)

			if not cfg[unlockedKey] then
				local bar = ACAB.bars[page.barId]
				if bar then
					ACAB[applyMethod](ACAB, bar)
				end
			end

			ACAB:RefreshBarSettingsPage(page.barId)
		end,
	})

	button:SetLocked(true)
	button:Hide()
	return button
end

-- True on Main Bar's page while its art is enabled (controls that would move buttons off the art are pinned).
local function IsMainBarArtLocked(page)
	return page.barId == 1 and ACAB:IsMainBarArtEnabled()
end

-- Locked tooltip + same-page art-mode dropdown pulse for a Main Bar control pinned by IsMainBarArtLocked.
local function InstallMainBarArtGuard(page, control, lockedText)
	ACAB:InstallGroupLockGuard(
		control,
		function() return IsMainBarArtLocked(page) end,
		lockedText,
		function() ACAB:HighlightMainBarArtModeDropdown() end
	)
end

-- Grid Layout locks by page barId: Main Bar's while its art is enabled, Micro Menu's/Bag Bar's while grouped.
local GRID_LAYOUT_LOCKS = {
	[1] = {
		isLocked = function() return ACAB:IsMainBarArtEnabled() end,
		text = "Grid Layout cant be changed while Gryphons / Background Art is enabled.",
		onLockedClick = function() ACAB:HighlightMainBarArtModeDropdown() end,
	},
	micromenu = {
		isLocked = function() return ACAB:IsElementGrouped("micromenu") end,
		text = "Grid Layout cant be changed while Micro Menu is grouped with Main Bar.",
		onLockedClick = function() ACAB:HighlightMainBarArtModeDropdownFromElsewhere() end,
	},
	bagbar = {
		isLocked = function() return ACAB:IsElementGrouped("bagbar") end,
		text = "Grid Layout cant be changed while Bag Bar is grouped with Main Bar.",
		onLockedClick = function() ACAB:HighlightMainBarArtModeDropdownFromElsewhere() end,
	},
}

-- (Re)builds a page's swatch row at swatchY from GetGridPresetsForBar(barId). Stance Bar's presets are live,
-- so its row is rebuilt on every page refresh. Swatches are pooled per page by preset and only created once.
local function RebuildGridSwatches(page, barId, swatchY)
	local i

	if page.gridSwatches then
		for i = 1, table.getn(page.gridSwatches) do
			page.gridSwatches[i]:Hide()
			page.gridSwatches[i]:ClearAllPoints()
		end
	end

	if page.noStancesText then
		page.noStancesText:Hide()
		page.noStancesText = nil
	end

	page.gridSwatches = {}

	if not page.gridSwatchPool then
		page.gridSwatchPool = {}
	end

	local gridPresets = GetGridPresetsForBar(barId)

	-- page.noStancesText is set only while shown (hover reflow and height fit read it); the FontString is pooled.
	if barId == ACAB.STANCE_BAR_ID and table.getn(gridPresets) == 0 then
		local noStancesText = page.noStancesTextPooled
		if not noStancesText then
			noStancesText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
			noStancesText:SetText("No stances currently available.")
			page.noStancesTextPooled = noStancesText
		end

		noStancesText:ClearAllPoints()
		noStancesText:SetPoint("TOPLEFT", page, "TOPLEFT", ACAB.INDENT_CONTROL, swatchY)
		noStancesText:Show()
		page.noStancesText = noStancesText
	end

	local xOffset = ACAB.INDENT_CONTROL
	local lock = GRID_LAYOUT_LOCKS[barId]

	for i = 1, table.getn(gridPresets) do
		local preset = gridPresets[i]
		local poolKey = tostring(preset.cols) .. "x" .. tostring(preset.rows)
		local swatch = page.gridSwatchPool[poolKey]
		if swatch then
			-- Back to a new swatch's state.
			ACAB:LockControl(swatch, false)
			swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
			swatch:Show()
		else
			swatch = CreateGridSwatch(page, preset)
			swatch.page = page
			swatch:SetScript("OnClick", GridSwatch_OnClick)

			-- Once per swatch: a second guard would wrap the first.
			if lock then
				ACAB:InstallGroupLockGuard(swatch, lock.isLocked, lock.text, lock.onLockedClick)
			end

			page.gridSwatchPool[poolKey] = swatch
		end

		swatch:SetPoint("TOPLEFT", page, "TOPLEFT", xOffset, swatchY)
		page.gridSwatches[i] = swatch
		xOffset = xOffset + SWATCH_SIZE + SWATCH_GAP
	end
end

-- "Grid Layout" title + swatch row. Swatches are a dynamic array, so page.hoverOnlyExtraReflow repositions
-- them (and the title) in place instead of registering them as reflow rows.
function ACAB:CreateGridLayoutSection(page, barId, gridTitleY, swatchY)
	local gridTitle = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	gridTitle:SetPoint("TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, gridTitleY)
	gridTitle:SetText("Grid Layout")
	page.gridSwatchY = swatchY
	RebuildGridSwatches(page, barId, swatchY)
	page.hoverOnlyExtraReflow = function(offset)
		gridTitle:ClearAllPoints()
		gridTitle:SetPoint("TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, gridTitleY - offset)
		page.gridSwatchY = swatchY - offset

		if page.noStancesText then
			page.noStancesText:ClearAllPoints()
			page.noStancesText:SetPoint("TOPLEFT", page, "TOPLEFT", ACAB.INDENT_CONTROL, page.gridSwatchY)
		end

		if page.gridSwatches then
			local xOffset = ACAB.INDENT_CONTROL
			local i
			for i = 1, table.getn(page.gridSwatches) do
				local swatch = page.gridSwatches[i]
				swatch:ClearAllPoints()
				swatch:SetPoint("TOPLEFT", page, "TOPLEFT", xOffset, page.gridSwatchY)
				xOffset = xOffset + SWATCH_SIZE + SWATCH_GAP
			end
		end
	end
end

-- Gold border on the swatch matching the bar's current cols/rows.
function ACAB:RefreshGridSwatchSelection(page, cols, rows)
	local i
	for i = 1, table.getn(page.gridSwatches) do
		local swatch = page.gridSwatches[i]
		if swatch.cols == cols and swatch.rows == rows then
			swatch:SetBackdropBorderColor(1, 0.82, 0, 1)
		else
			swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
		end
	end
end

-- Standalone Grid Layout swatch row for barId at (x, y) on parent (Setup Wizard's Extra Bars page);
-- onPick(cols, rows) runs on click. Returns the swatches.
function ACAB:CreateGridSwatchRow(parent, barId, x, y, onPick)
	local presets = GetGridPresetsForBar(barId)
	local swatches = {}
	local i
	for i = 1, table.getn(presets) do
		local swatch = CreateGridSwatch(parent, presets[i])
		swatch:SetPoint("TOPLEFT", parent, "TOPLEFT", x + ((i - 1) * (SWATCH_SIZE + SWATCH_GAP)), y)
		swatch:SetScript("OnClick", function()
			onPick(this.cols, this.rows)
		end)

		swatches[i] = swatch
	end

	return swatches
end

-- Gold border on the swatch in swatches matching cols x rows.
function ACAB:SelectGridSwatch(swatches, cols, rows)
	ACAB:RefreshGridSwatchSelection({ gridSwatches = swatches }, cols, rows)
end

-- Dims the page's swatches while GRID_LAYOUT_LOCKS locks them (alpha only, so the locked tooltip still shows).
-- Only ever dims: must run after ApplyProfileLockGating, which owns the undimmed state.
local function ApplyGridLayoutLock(page)
	local lock = GRID_LAYOUT_LOCKS[page.barId]
	if not lock or not page.gridSwatches or not lock.isLocked() then return end

	local i
	for i = 1, table.getn(page.gridSwatches) do
		page.gridSwatches[i]:SetAlpha(0.5)
	end
end

-------------------------------------------------------------------------
-- Grouped-with-Main-Bar locks
-------------------------------------------------------------------------

-- Simple pages whose element can be grouped with Main Bar (lock icon, guarded controls).
ACAB.GROUPABLE_SIMPLE_PAGES = {
	bagbar = true,
	keyring = true,
	micromenu = true,
	latencybar = true,
}

-- Controls on a groupable simple page that lock while its element is grouped.
ACAB.GROUP_LOCK_CONTROL_NAMES = {
	"xSlider", "xStepperBigMinus", "xStepperMinus", "xStepperPlus", "xStepperBigPlus", "xValueClick",
	"ySlider", "yStepperBigMinus", "yStepperMinus", "yStepperPlus", "yStepperBigPlus", "yValueClick",
	"spacingSlider", "scaleSlider",
	"resetPositionButton", "resetModernButton",
}

-- Titles/labels/value readouts dimmed alongside those controls.
local GROUP_LOCK_TEXT_NAMES = {
	"xLabel", "xValueText", "yLabel", "yValueText",
	"spacingTitle", "spacingValueText", "scaleTitle", "scaleValueText",
}

-- Settings-page lock icon toggling elementKey's grouping with Main Bar. Starts locked.
function ACAB:CreateGroupLockButton(page, name, anchor, tooltipTitle, elementKey)
	local button = ACAB:CreateLockToggleButton(page, name, {
		anchor = anchor,
		tooltipTitle = tooltipTitle,
		lockedLine = "Anchored to Main Bar while Gryphons / Background Art is enabled. Click to unlock and move/scale it independently.",
		unlockedLine = "Unlocked - independent of Main Bar. Click to re-lock and snap back to its anchored position.",
		onClick = function()
			ACAB:ToggleElementGroupLock(elementKey)
		end,
	})

	button:SetLocked(true)
	return button
end

-- Syncs a lock icon: shown while Main Bar art is enabled, extraShow isn't false, and the page isn't
-- Default-profile/layout locked.
local function RefreshGroupLockButton(button, elementKey, extraShow)
	if not button then return end

	button:SetShown(
		ACAB:IsMainBarArtEnabled()
			and extraShow ~= false
			and not ACAB:IsDefaultProfileActive()
			and ACABDB.useDefaultLayout ~= true
	)
	button:SetLocked(not ACAB:IsElementGroupUnlocked(elementKey))
end

-- While key's element is grouped, snaps its simple page back to the saved values and returns true (drop the edit).
function ACAB:RevertIfGroupLocked(key)
	if ACAB.GROUPABLE_SIMPLE_PAGES[key] and ACAB:IsElementGrouped(key) then
		ACAB:RefreshSimpleBarPage(key)
		return true
	end

	return false
end

-- Dims a groupable simple page's locked controls (alpha only - clicks go through InstallGroupLockGuard) and
-- syncs its lock icon. Only ever dims: must run after ApplyDefaultLayoutGating/ApplyProfileLockGating.
function ACAB:ApplySimpleElementGroupedLock(page)
	if not page or not ACAB.GROUPABLE_SIMPLE_PAGES[page.barId] then return end

	local barId = page.barId
	local locked = ACAB:IsElementGrouped(barId)
	local i

	if locked then
		for i = 1, table.getn(ACAB.GROUP_LOCK_CONTROL_NAMES) do
			local control = page[ACAB.GROUP_LOCK_CONTROL_NAMES[i]]
			if control then
				control:SetAlpha(0.5)
			end
		end
	end

	-- Micro Menu's/Bag Bar's Grid Layout swatches.
	ApplyGridLayoutLock(page)

	for i = 1, table.getn(GROUP_LOCK_TEXT_NAMES) do
		local text = page[GROUP_LOCK_TEXT_NAMES[i]]
		if text then
			text:SetAlpha(locked and 0.5 or 1)
		end
	end

	RefreshGroupLockButton(page.groupLockButton, barId)
end

-- Main Bar page's Page Indicator Scale slider - same dim-only rule as ApplySimpleElementGroupedLock.
function ACAB:ApplyPageIndicatorGroupedLock(page)
	if not page or not page.pageIndicatorSlider then return end

	local locked = ACAB:IsElementGrouped("pageindicator")
	if locked then
		page.pageIndicatorSlider:SetAlpha(0.5)
	end

	page.pageIndicatorTitle:SetAlpha(locked and 0.5 or 1)
	page.pageIndicatorValueText:SetAlpha(locked and 0.5 or 1)
	RefreshGroupLockButton(page.pageIndicatorGroupLockButton, "pageindicator", ACABDB.defaultBarPaginationEnabled ~= false)
end

-- Pulses a gold highlight behind Main Bar's "Gryphons / Background Art" dropdown row, if that page is built.
function ACAB:HighlightMainBarArtModeDropdown()
	local page = ACAB.settingsFrame and ACAB.settingsFrame.pages and ACAB.settingsFrame.pages[1]
	local row = page and page.mainBarArtModeRow
	if not row then return end

	if not row.acabHighlightStrip then
		local strip = ACAB:CreateFadeStrip(page, row:GetWidth() + 16, row:GetHeight() + 10, { edgeFraction = 0.15 })
		strip:SetPoint("LEFT", row, "LEFT", -8, 0)
		strip:SetFadeColor(ACAB.UI_ACCENT_COLOR[1], ACAB.UI_ACCENT_COLOR[2], ACAB.UI_ACCENT_COLOR[3])
		strip:SetPeakAlpha(0.55)
		strip:Hide()
		row.acabHighlightStrip = strip
	end

	local strip = row.acabHighlightStrip
	strip.pulseGeneration = (strip.pulseGeneration or 0) + 1
	strip:Show()

	-- Three on/off pulses; steps from an older call are skipped.
	local generation = strip.pulseGeneration
	local function Step(show)
		return function()
			if strip.pulseGeneration ~= generation then return end

			if show then
				strip:Show()
			else
				strip:Hide()
			end
		end
	end

	C_Timer.After(0.45, Step(false))
	C_Timer.After(0.75, Step(true))
	C_Timer.After(1.2, Step(false))
	C_Timer.After(1.5, Step(true))
	C_Timer.After(1.95, Step(false))
end

-- Opens Main Bar's page, then pulses its art-mode dropdown - for locked controls on other pages.
function ACAB:HighlightMainBarArtModeDropdownFromElsewhere()
	ACAB:ShowBarPage(1)
	ACAB:HighlightMainBarArtModeDropdown()
end

-------------------------------------------------------------------------
-- Bar settings page: default bars (1-5, styled Pet/Stance Bar) and Extra Bars (6+)
-------------------------------------------------------------------------

function ACAB:GetOrCreateBarPage(barId)
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	ACAB:DropMismatchedBarPage(barId)

	if UsesSimpleBarPage(barId) then
		return self:GetOrCreateSimpleBarPage(barId)
	end

	if ACAB.settingsFrame.pages[barId] then
		return ACAB.settingsFrame.pages[barId]
	end

	local isDefault = ACAB:IsDefaultBarFamilyId(barId)

	local page = CreateFrame("Frame", nil, ACAB.settingsFrame.contentPanel)

	-- Starts flush; ApplyProfileLockGating slides it down while the lock banner is shown.
	ACAB:ApplyPageBannerReserve(page, false)
	page.barId = barId
	page.isDefault = isDefault
	page.profileLockWarning = self:CreateProfileLockWarning(page)

	-- Title (anchored to contentPanel so it stays put while the page slides down)
	local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", ACAB.settingsFrame.contentPanel, "TOPLEFT", ACAB.INDENT_SECTION, -14)
	local titleText = GetBarDisplayName(barId) .. " Settings"

	if isDefault then
		titleText = titleText .. " (Default)"
	end

	title:SetText(titleText)

	-- Default bars 2-5 and Extra Bars get an "Enabled" checkbox.
	local isExtraBar = ACAB:IsExtraBarId(barId)
	local hasEnableCheckbox = (isDefault and barId ~= 1) or isExtraBar

	-- Vertical layout cursor: every section's Y derives from the one above it.
	local checkboxY = -44

	-- Position section starts under the title, or under the Enabled checkbox.
	local positionStartY = -46

	if hasEnableCheckbox then
		positionStartY = checkboxY - 24 - 14
	end

	local hoverOnlyCheckboxY = positionStartY
	positionStartY = positionStartY - self.HOVER_ONLY_CHECKBOX_ROW_HEIGHT

	-- Pet Bar: three more checkbox rows.
	local isPetBarPage = barId == ACAB.PET_BAR_ID
	local useVanillaPetBarY = positionStartY
	local condenseEmptyPetSlotsY = useVanillaPetBarY - 24 - 14
	local animateAutoCastGlowY = condenseEmptyPetSlotsY - 24 - 14

	if isPetBarPage then
		positionStartY = positionStartY - (24 + 14) * 3
	end

	-- Stance Bar: one more checkbox row.
	local isStanceBarPage = barId == ACAB.STANCE_BAR_ID
	local useVanillaStanceBarY = positionStartY

	if isStanceBarPage then
		positionStartY = positionStartY - (24 + 14)
	end

	-- Main Bar: the art-mode dropdown row.
	local isMainBarPage = barId == 1
	local mainBarArtModeY = positionStartY

	if isMainBarPage then
		positionStartY = positionStartY - (32 + 14)
	end

	-- Enabled checkbox
	if hasEnableCheckbox then
		local enableCheckbox = ACAB:CreateLabeledCheckbox(page, "ACABDefaultBar" .. tostring(barId) .. "EnableCheckbox", {
			anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, checkboxY },
			label = "Enabled",
			onClick = function()
				local checked = this:GetChecked() and true or false

				if isDefault then
					ACAB:SetDefaultBarEnabled(this.barId, checked)
				else
					ACAB:SetExtraBarEnabled(this.barId, checked)
				end

				ACAB:RefreshBarList()
			end,
		})

		enableCheckbox.barId = barId
		page.enableCheckbox = enableCheckbox
	end

	-- Only show on hover
	self:CreateHoverOnlyControls(
		page,
		hoverOnlyCheckboxY,
		function()
			local cfg = ACAB:GetBarConfig(barId)
			return cfg and cfg.hoverOnly
		end,
		function(v)
			local bar = ACAB.bars[barId]
			if bar then
				ACAB:SetBarHoverOnly(bar, v)
			end
		end,
		function()
			local cfg = ACAB:GetBarConfig(barId)
			return (cfg and cfg.hoverDuration) or 3
		end,
		function(v)
			local bar = ACAB.bars[barId]
			if bar then
				ACAB:SetBarHoverDuration(bar, v)
			end
		end,
		barId
	)

	-- Gryphons / Background Art (Main Bar only)
	if isMainBarPage then
		local row, dropdown = ACAB:CreateDropdownRow(page, mainBarArtModeY, "Gryphons / Background Art:", 180, "ACABMainBarArtModeDropdown", {
			{ text = "Fully Disabled", value = ACAB.MAIN_BAR_ART_MODE_DISABLED },
			{ text = "Disable Gryphons", value = ACAB.MAIN_BAR_ART_MODE_NO_GRYPHONS },
			{ text = "Fully Enabled", value = ACAB.MAIN_BAR_ART_MODE_FULL },
		})

		local function RefreshMainBarArtModeDropdown()
			dropdown:SetSelected(ACABDB.mainBarArtMode or ACAB.MAIN_BAR_ART_MODE_FULL)
		end

		dropdown.onSelect = function(value)
			local mainCfg = ACABDB.defaultBars and ACABDB.defaultBars[1]

			-- Art off -> on: remembers Main Bar's spacing for RestoreMainBarSpacingAfterArt.
			if mainCfg and not ACAB:IsMainBarArtEnabled() and value ~= ACAB.MAIN_BAR_ART_MODE_DISABLED then
				mainCfg.spacingBeforeArt = mainCfg.spacing
			end

			ACABDB.mainBarArtMode = value
			ACAB:ApplyBlizzardArtVisibility()

			-- Any visible art lays Main Bar out 12x1 (saved grid kept) with the spacing the art assumes.
			if value ~= ACAB.MAIN_BAR_ART_MODE_DISABLED then
				ACAB:EnforceMainBarArtSpacing()
			else
				ACAB:RestoreMainBarSpacingAfterArt()
			end

			if ACAB.bars and ACAB.bars[1] then
				ACAB:ApplyBarShape(ACAB.bars[1])
			end

			-- Groups/ungroups the Main Bar elements and swaps their edit-mode overlays/lock icons.
			ACAB:ApplyMainBarGroupedElements()
			ACAB:ApplyDefaultLayoutEditVisual()
			ACAB:RefreshBarSettingsPage(1)
		end

		RefreshMainBarArtModeDropdown()
		page.mainBarArtModeRow = row
		page.RefreshMainBarArtModeDropdown = RefreshMainBarArtModeDropdown
		self:AddHoverOnlyReflowRow(page, row, ACAB.INDENT_SECTION, mainBarArtModeY)
	end

	-- Pet Bar / Stance Bar mode checkboxes
	if isPetBarPage then
		ACAB:CreateUseVanillaBarCheckbox(page, useVanillaPetBarY, "Pet", ACAB.PET_BAR_ID, "useNativePetBar")
		ACAB:CreateCondenseEmptyPetSlotsCheckbox(page, condenseEmptyPetSlotsY)
		CreateAnimateAutoCastGlowCheckbox(page, animateAutoCastGlowY)
	end

	if isStanceBarPage then
		ACAB:CreateUseVanillaBarCheckbox(page, useVanillaStanceBarY, "Stance", ACAB.STANCE_BAR_ID, "useNativeStanceBar")
	end

	-- Position: clamp range kept live by RefreshPositionSliderRange
	local minX, maxX, minY, maxY =
		ACAB:GetActionBarCoordinateRange(ACAB:GetBarConfig(barId))

	local function ApplyPosition()
		ACAB:ApplyLiveBarPosition(page)
	end

	local _, _, ySliderY = ACAB:CreatePositionSection(page, "ACABBar" .. tostring(barId), positionStartY,
		minX, maxX, minY, maxY, ApplyPosition, ApplyPosition)

	-- Button Size
	local sizeLayoutTitleY = ySliderY - 36
	local buttonSizeSliderY = sizeLayoutTitleY - 26
	ACAB:CreateReflowText(page, "GameFontNormal", ACAB.INDENT_SECTION, sizeLayoutTitleY,
		"Button Size (" .. tostring(ACAB.BUTTON_SIZE_MIN) ..
		" to " .. tostring(ACAB.BUTTON_SIZE_MAX) .. ")"
	)

	local buttonSizeSlider, buttonSizeValueText = ACAB:CreateReflowSlider(
		page,
		"ACABBar" .. tostring(barId) .. "ButtonSizeSlider",
		buttonSizeSliderY,
		{
			min = ACAB.BUTTON_SIZE_MIN,
			max = ACAB.BUTTON_SIZE_MAX,
			step = ACAB.BUTTON_SIZE_STEP,
			lowText = tostring(ACAB.BUTTON_SIZE_MIN),
			highText = tostring(ACAB.BUTTON_SIZE_MAX),
			initialText = tostring(ACAB.BUTTON_SIZE),
			round = function(value) return math.floor((value / ACAB.BUTTON_SIZE_STEP) + 0.5) * ACAB.BUTTON_SIZE_STEP end,
			format = tostring,
			onChange = function(value, suppressApply)
				if not suppressApply then
					if page.isDefault then
						ACAB:SetDefaultBarButtonSize(page.barId, value)
					else
						local bar = ACAB.bars[page.barId]
						if bar then
							ACAB:SetBarButtonSize(bar, value)
						end
					end
				end

				ACAB:RefreshPositionSliderRange(page)
			end,
		}
	)

	page.buttonSizeValueText = buttonSizeValueText
	page.buttonSizeSlider = buttonSizeSlider

	page.buttonSizeLockButton = CreateGlobalOverrideLockButton(page, "ACABBar" .. tostring(barId) .. "ButtonSizeLockButton",
		buttonSizeSlider, "Button Size", "buttonSizeUnlocked", "ApplyGlobalButtonSizeToBar")

	-- Spacing + Reset buttons
	local gridTitleY
	local swatchY

	do
		local spacingTitleY = buttonSizeSliderY - 36
		local spacingSliderY = spacingTitleY - 26
		page.spacingTitle = ACAB:CreateReflowText(page, "GameFontNormal", ACAB.INDENT_SECTION, spacingTitleY,
			"Spacing (" .. tostring(ACAB.SPACING_MIN) ..
			" to " .. tostring(ACAB.SPACING_MAX) .. ")"
		)

		-- Displayed range is 0-based (real = displayed + GetSpacingDisplayOffset).
		local spacingSlider, spacingValueText, spacingSliderLow, spacingSliderHigh = ACAB:CreateReflowSlider(
			page,
			"ACABBar" .. tostring(barId) .. "SpacingSlider",
			spacingSliderY,
			{
				min = 0,
				max = ACAB.SPACING_MAX,
				step = ACAB.SPACING_STEP,
				lowText = "0",
				highText = tostring(ACAB.SPACING_MAX),
				initialText = "0",
				round = function(value) return math.floor(value + 0.5) end,
				format = tostring,
				onChange = function(value, suppressApply)
					if not suppressApply then
						-- Pinned while Main Bar's art is enabled; the guard's OnMouseDown runs the pulse.
						if IsMainBarArtLocked(page) then
							ACAB:RefreshBarSettingsPage(1)
							return
						end

						local real = value + ACAB:GetSpacingDisplayOffset()

						if page.isDefault then
							ACAB:SetDefaultBarSpacing(page.barId, real)
						else
							local bar = ACAB.bars[page.barId]
							if bar then
								ACAB:SetBarSpacing(bar, real)
							end
						end
					end

					ACAB:RefreshPositionSliderRange(page)
				end,
			}
		)

		page.spacingSliderLow = spacingSliderLow
		page.spacingSliderHigh = spacingSliderHigh
		page.spacingValueText = spacingValueText
		page.spacingSlider = spacingSlider

		if barId == 1 then
			InstallMainBarArtGuard(page, spacingSlider, "Spacing cant be changed while Gryphons / Background Art is enabled.")
		end

		page.spacingLockButton = CreateGlobalOverrideLockButton(page, "ACABBar" .. tostring(barId) .. "SpacingLockButton",
			spacingSlider, "Spacing", "spacingUnlocked", "ApplyGlobalSpacingToBar")

		if isDefault then
			local resetButtonY = spacingSliderY - 36
			page.resetPositionButton = ACAB:CreateReflowResetButton(page, resetButtonY, "Reset to Vanilla Layout", function()
				ACAB:ResetDefaultBarLayout(page.barId)

				-- Page Indicator anchors off Main Bar, so it resets alongside it.
				if page.barId == 1 then
					ACAB:ResetPageIndicatorLayout()
				end

				ACAB:RefreshBarSettingsPage(page.barId)
			end)

			local nextY = resetButtonY

			-- Modern reset: bars 1-5 (ResetBarLayoutToModernBase dispatches each id) and styled Pet/Stance Bar.
			if (barId >= 1 and barId <= 5) or barId == ACAB.PET_BAR_ID or barId == ACAB.STANCE_BAR_ID then
				local resetModernY = resetButtonY - 30
				page.resetModernButton = ACAB:CreateReflowResetButton(page, resetModernY, "Reset to Modern Layout Default", function()
					if page.barId == ACAB.PET_BAR_ID then
						ACAB:ResetPetBarLayoutToModernBase()
					elseif page.barId == ACAB.STANCE_BAR_ID then
						ACAB:ResetStanceBarPositionToModernBase()
					else
						ACAB:ResetBarLayoutToModernBase(page.barId)
					end

					if page.barId == 1 then
						ACAB:ResetPageIndicatorToModernBase()
					end

					ACAB:RefreshBarSettingsPage(page.barId)
				end)

				if barId == 1 then
					InstallMainBarArtGuard(page, page.resetModernButton, "Reset to Modern Layout cant be used while Gryphons / Background Art is enabled.")
				end

				nextY = resetModernY
			end

			gridTitleY = nextY - 34
		elseif isExtraBar then
			local resetButtonY = spacingSliderY - 36
			page.resetPositionButton = ACAB:CreateReflowResetButton(page, resetButtonY, "Reset to Default", function()
				ACAB:ResetExtraBarLayout(page.barId)
				ACAB:RefreshBarSettingsPage(page.barId)
			end)

			local resetModernY = resetButtonY - 30
			page.resetModernButton = ACAB:CreateReflowResetButton(page, resetModernY, "Reset to Modern Layout Default", function()
				ACAB:ResetExtraBarLayoutToModernBase(page.barId)
				ACAB:RefreshBarSettingsPage(page.barId)
			end)

			gridTitleY = resetModernY - 34
		else
			gridTitleY = spacingSliderY - 36
		end

		swatchY = gridTitleY - 26
	end

	-- Grid Layout
	ACAB:CreateGridLayoutSection(page, barId, gridTitleY, swatchY)
	ApplyGridLayoutLock(page)

	-- Buttons Shown stepper (custom bars only)
	if not isDefault then
		-- Below the swatch row: swatch + caption line + gap, then the label-to-row gap.
		local buttonCountLabelY = swatchY - SWATCH_SIZE - 14 - 14
		local buttonCountRowY = buttonCountLabelY - 28
		ACAB:CreateReflowText(page, "GameFontNormal", ACAB.INDENT_SECTION, buttonCountLabelY, "Buttons Shown")

		local buttonCountMinus = ACAB:CreateModernButton(page, {
			name = "ACABBar" .. tostring(barId) .. "ButtonCountMinus",
			height = 22,
			minWidth = 24,
			maxWidth = 24,
			text = "-",
			anchor = { "TOPLEFT", page, "TOPLEFT", ACAB.INDENT_INPUT, buttonCountRowY },
		})
		self:AddHoverOnlyReflowRow(page, buttonCountMinus, ACAB.INDENT_INPUT, buttonCountRowY)

		local buttonCountValueText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		buttonCountValueText:SetPoint("LEFT", buttonCountMinus, "RIGHT", 8, 0)
		buttonCountValueText:SetWidth(24)
		buttonCountValueText:SetJustifyH("CENTER")
		buttonCountValueText:SetText("12")

		local buttonCountPlus = ACAB:CreateModernButton(page, {
			name = "ACABBar" .. tostring(barId) .. "ButtonCountPlus",
			height = 22,
			minWidth = 24,
			maxWidth = 24,
			text = "+",
			anchor = { "LEFT", buttonCountValueText, "RIGHT", 8, 0 },
		})

		-- Shows cfg.buttonCount and disables -/+ at 1 and at cols*rows.
		local function RefreshButtonCountStepperVisual()
			local cfg = ACAB:FindCustomBarConfig(page.barId)
			if not cfg then return end

			local maxButtons = (cfg.cols or 1) * (cfg.rows or 1)
			local count = cfg.buttonCount or maxButtons
			buttonCountValueText:SetText(tostring(count))

			if count <= 1 then
				buttonCountMinus:Disable()
			else
				buttonCountMinus:Enable()
			end

			if count >= maxButtons then
				buttonCountPlus:Disable()
			else
				buttonCountPlus:Enable()
			end
		end

		-- Changes the bar's button count by delta; the count feeds the X/Y clamp range.
		local function StepButtonCount(delta)
			local cfg = ACAB:FindCustomBarConfig(page.barId)
			local bar = ACAB.bars[page.barId]
			if not cfg or not bar then return end

			ACAB:SetBarButtonCount(bar, (cfg.buttonCount or (cfg.cols * cfg.rows)) + delta)
			RefreshButtonCountStepperVisual()
			ACAB:RefreshPositionSliderRange(page)
		end

		buttonCountMinus:SetScript("OnClick", function() StepButtonCount(-1) end)
		buttonCountPlus:SetScript("OnClick", function() StepButtonCount(1) end)
		page.buttonCountMinus = buttonCountMinus
		page.buttonCountPlus = buttonCountPlus
		page.buttonCountValueText = buttonCountValueText
		page.RefreshButtonCountStepperVisual = RefreshButtonCountStepperVisual
	end

	-- Page Indicator Scale (Main Bar) + Stance/Page Bar Assignment (default bars 1-5)
	if barId >= 1 and barId <= 5 then
		local assignmentAnchorY = swatchY - SWATCH_SIZE - 14 - 14

		-- Page Indicator: Scale only (position is drag-only).
		if barId == 1 then
			local pageIndicatorTitleY = assignmentAnchorY
			local pageIndicatorSliderY = pageIndicatorTitleY - 28

			local pageIndicatorTitle = ACAB:CreateReflowText(page, "GameFontNormal", ACAB.INDENT_SECTION, pageIndicatorTitleY, "Page Indicator Scale")

			local pageIndicatorSlider, pageIndicatorValueText = ACAB:CreateReflowSlider(
				page,
				"ACABMainBarPageIndicatorScaleSlider",
				pageIndicatorSliderY,
				{
					min = 0.5,
					max = 2.0,
					step = 0.1,
					initialText = "1.0",
					round = function(value) return math.floor((value * 10) + 0.5) / 10 end,
					format = function(value) return string.format("%.1f", value) end,
					onChange = function(value, suppressApply)
						if not suppressApply then
							-- Refuses the value while grouped; the guard below handles the click.
							if ACAB:IsElementGrouped("pageindicator") then
								ACAB:RefreshBarSettingsPage(1)
								return
							end

							ACAB:SetPageIndicatorScale(value)
						end
					end,
				}
			)

			page.pageIndicatorTitle = pageIndicatorTitle
			page.pageIndicatorSlider = pageIndicatorSlider
			page.pageIndicatorValueText = pageIndicatorValueText

			-- The art-mode dropdown is on this page, so the pulse needs no page switch.
			ACAB:InstallGroupLockGuard(
				pageIndicatorSlider,
				function() return ACAB:IsElementGrouped("pageindicator") end,
				"Page Indicator is grouped with Main Bar while Gryphons / Background Art is enabled - its own Scale control is locked.",
				function() ACAB:HighlightMainBarArtModeDropdown() end
			)

			-- Beside the slider, since Page Indicator has no page of its own.
			page.pageIndicatorGroupLockButton = ACAB:CreateGroupLockButton(
				page,
				"ACABMainBarPageIndicatorGroupLockButton",
				{ "LEFT", pageIndicatorSlider, "RIGHT", 4, 0 },
				"Grouped with Main Bar",
				"pageindicator"
			)

			assignmentAnchorY = pageIndicatorSliderY - 44
		end

		-- Empty container, populated by RebuildDefaultBarAssignmentRows.
		local assignmentContainer = CreateFrame("Frame", nil, page)
		assignmentContainer:SetPoint("TOPLEFT", page, "TOPLEFT", ACAB.INDENT_SECTION, assignmentAnchorY)
		assignmentContainer:SetWidth(500)
		assignmentContainer:SetHeight(1)
		page.assignmentContainer = assignmentContainer
		page.assignmentRows = {}

		-- Rows anchor to the container, so reflowing it carries them along.
		self:AddHoverOnlyReflowRow(page, assignmentContainer, ACAB.INDENT_SECTION, assignmentAnchorY)
	end

	page:Hide()
	ACAB.settingsFrame.pages[barId] = page
	return page
end

-- Writes a bar page's X/Y sliders to the bar (default or custom setter).
function ACAB:ApplyLiveBarPosition(page)
	-- Reads the pixel-snapped cached values; never SetValue() from OnValueChanged (breaks the drag mid-gesture).
	local x = page.xAppliedValue or page.xSlider:GetValue()
	local y = page.yAppliedValue or page.ySlider:GetValue()
	if not x or not y then return end

	if page.isDefault then
		self:SetDefaultBarPosition(page.barId, x, y)
	else
		local bar = self.bars[page.barId]
		if bar then
			self:SetBarPosition(bar, x, y)
		end
	end
end

-- Right-click-to-settings entry point for any page key (used by DefaultBars.lua's overlays).
function ACAB:OpenBarSettingsByKey(key)
	self:ShowSettingsFrame()

	-- The running Setup Wizard owns the settings window's page.
	if self:IsSetupWizardActive() then return end

	self:ShowBarPage(key)
end

-------------------------------------------------------------------------
-- Refresh values shown by a bar page
-------------------------------------------------------------------------

function ACAB:RefreshBarSettingsPage(barId)
	if not ACAB.settingsFrame then return end

	ACAB:DropMismatchedBarPage(barId)

	if UsesSimpleBarPage(barId) then
		self:RefreshSimpleBarPage(barId)
		return
	end

	local page = ACAB.settingsFrame.pages[barId]
	if not page then return end

	local cfg, isDefault = ACAB:GetBarConfig(barId)
	if not cfg then return end

	self:RefreshHoverOnlyControls(page, cfg.hoverOnly, cfg.hoverDuration)

	-- Must suppress apply/snap first: SetMinMaxValues fires OnValueChanged like a real drag.
	ACAB:SetPositionSlidersSuppressed(page, true)
	page.buttonSizeSlider.suppressApply = true

	-- X/Y clamp range from the current buttonSize/buttonCount/grid; SetValue below re-syncs from cfg.
	do
		local minX, maxX, minY, maxY = ACAB:GetActionBarCoordinateRange(cfg)
		page.xSlider:SetMinMaxValues(minX, maxX)
		page.ySlider:SetMinMaxValues(minY, maxY)
	end

	if page.spacingSlider then
		page.spacingSlider.suppressApply = true
	end

	ACAB:SyncPositionSliders(page, cfg.x or 0, cfg.y or 0)
	page.buttonSizeSlider:SetValue(ACAB:Clamp(cfg.buttonSize or ACAB.BUTTON_SIZE, ACAB.BUTTON_SIZE_MIN, ACAB.BUTTON_SIZE_MAX))

	if page.spacingSlider then
		local offset = ACAB:GetSpacingDisplayOffset()
		page.spacingSlider:SetMinMaxValues(0, ACAB.SPACING_MAX)

		if page.spacingSliderLow then
			page.spacingSliderLow:SetText("0")
		end

		if page.spacingSliderHigh then
			page.spacingSliderHigh:SetText(tostring(ACAB.SPACING_MAX))
		end

		local displayed = ACAB:Clamp(cfg.spacing or 0, ACAB.SPACING_MIN, ACAB:GetSpacingMax()) - offset
		if displayed < 0 then
			displayed = 0
		end

		page.spacingSlider:SetValue(displayed)

		if page.spacingValueText then
			page.spacingValueText:SetText(tostring(displayed))
		end
	end

	ACAB:SetPositionSlidersSuppressed(page, nil)
	page.buttonSizeSlider.suppressApply = nil

	if page.spacingSlider then
		page.spacingSlider.suppressApply = nil
	end

	-- Stance Bar's preset list is live, so its swatch row is rebuilt on every refresh.
	if barId == ACAB.STANCE_BAR_ID and page.gridSwatchY then
		RebuildGridSwatches(page, barId, page.gridSwatchY)
	end

	local selectedCols, selectedRows = ACAB:GetEffectiveBarGrid(cfg)
	ACAB:RefreshGridSwatchSelection(page, selectedCols or 12, selectedRows or 1)

	if page.RefreshMainBarArtModeDropdown then
		page.RefreshMainBarArtModeDropdown()
	end

	if page.RefreshButtonCountStepperVisual then
		page.RefreshButtonCountStepperVisual()
	end

	-- cfg.enabled is the sole source of truth (the real Blizzard buttons of bars 2-5 stay hidden).
	if page.enableCheckbox and ((isDefault and barId ~= 1) or ACAB:IsExtraBarId(barId)) then
		page.enableCheckbox:SetChecked(cfg.enabled == true)
	end

	-- While forced, the mode checkboxes show the vanilla-forced value instead of the stored preference.
	local vanillaForced = ACAB:IsVanillaModeForced()

	if page.useVanillaPetBarCheckbox then
		page.useVanillaPetBarCheckbox:SetChecked(vanillaForced or cfg.useNativePetBar == true)
	end

	if page.condenseEmptyPetSlotsCheckbox then
		page.condenseEmptyPetSlotsCheckbox:SetChecked((not vanillaForced) and cfg.condenseEmptyPetSlots == true)
	end

	if page.useVanillaStanceBarCheckbox then
		page.useVanillaStanceBarCheckbox:SetChecked(vanillaForced or cfg.useNativeStanceBar == true)
	end

	if page.animateAutoCastGlowCheckbox then
		page.animateAutoCastGlowCheckbox:SetChecked(cfg.animateAutoCastGlow == true)
	end

	if barId == 1 and page.pageIndicatorSlider then
		local scale = ACABDB.mainBarPageIndicatorScale or 1
		ACAB:SetSliderValueSilently(page.pageIndicatorSlider, scale, page.pageIndicatorValueText, string.format("%.1f", scale))
		ACAB:RefreshMainBarPageIndicatorControlsVisibility()
	end

	if page.assignmentContainer then
		ACAB:RebuildDefaultBarAssignmentRows(barId)
	end

	-- Default-profile lock on every bar page; numbered default bars also get the Force Vanilla Layout lock.
	self:ApplyProfileLockGating(page, page.isDefault)

	-- Global Spacing/Button Size override locks.
	ACAB:RefreshBarPageGlobalOverrideGating(page)

	-- Only ever dim - must run after ApplyProfileLockGating, which resets alpha to 1.
	ApplyGridLayoutLock(page)
	ACAB:ApplyPageIndicatorGroupedLock(page)

	if page.resetModernButton and IsMainBarArtLocked(page) then
		page.resetModernButton:SetAlpha(0.5)
	end

	-- Must run after ApplyProfileLockGating, which unconditionally unlocks enableCheckbox otherwise.
	if page.enableCheckbox and barId == 5 then
		ACAB:LockControl(page.enableCheckbox, not IsBar5EnableAllowed())
	end
end

-- Locks a full bar page's Spacing/Button Size sliders while the matching global override is on and this bar
-- isn't unlocked via its lock icon (full bar pages only).
function ACAB:RefreshBarPageGlobalOverrideGating(page)
	if not page then return end

	local cfg = ACAB:GetBarConfig(page.barId)

	-- Must respect the Default-profile/layout lock too, or this re-enables sliders it just locked.
	local alsoLocked = self:IsDefaultProfileActive()
		or (page.isDefault and ACABDB.useDefaultLayout == true)

	if page.spacingSlider then
		local globalOn = ACABDB.globalSpacingEnabled == true
		local unlocked = cfg and cfg.spacingUnlocked == true
		local artLocked = IsMainBarArtLocked(page)
		local locked = alsoLocked or artLocked or (globalOn and not unlocked)

		-- The art lock keeps the mouse on so its tooltip and click-to-highlight still work.
		page.spacingSlider:EnableMouse(not locked or (artLocked and not alsoLocked))
		page.spacingSlider:SetAlpha(locked and 0.5 or 1)

		if page.spacingTitle then
			page.spacingTitle:SetAlpha(artLocked and 0.5 or 1)
		end

		if page.spacingValueText then
			page.spacingValueText:SetAlpha(artLocked and 0.5 or 1)
		end

		if page.spacingLockButton then
			page.spacingLockButton:SetShown(globalOn and not alsoLocked and not artLocked)
			page.spacingLockButton:SetLocked(not unlocked)
		end
	end

	if page.buttonSizeSlider then
		local globalOn = ACABDB.globalButtonSizeEnabled == true
		local unlocked = cfg and cfg.buttonSizeUnlocked == true
		local locked = alsoLocked or (globalOn and not unlocked)
		page.buttonSizeSlider:EnableMouse(not locked)
		page.buttonSizeSlider:SetAlpha(locked and 0.5 or 1)

		if page.buttonSizeLockButton then
			page.buttonSizeLockButton:SetShown(globalOn and not alsoLocked)
			page.buttonSizeLockButton:SetLocked(not unlocked)
		end
	end
end

-- Re-runs RefreshBarPageGlobalOverrideGating on every built full bar page (numeric ids with a live bar).
function ACAB:RefreshAllBarPagesGlobalOverrideGating()
	if not ACAB.settingsFrame then return end

	local id
	local page
	for id, page in pairs(ACAB.settingsFrame.pages) do
		if type(id) == "number" and ACAB.bars and ACAB.bars[id] then
			self:RefreshBarPageGlobalOverrideGating(page)
		end
	end
end

-- Shows/hides the Main Bar page's Page Indicator Scale controls per ACABDB.defaultBarPaginationEnabled.
function ACAB:RefreshMainBarPageIndicatorControlsVisibility()
	if not ACAB.settingsFrame then return end

	local page = ACAB.settingsFrame.pages[1]
	if not page or not page.pageIndicatorSlider then return end

	local show = ACABDB.defaultBarPaginationEnabled ~= false
	if show then
		page.pageIndicatorTitle:Show()
		page.pageIndicatorSlider:Show()
		page.pageIndicatorValueText:Show()
	else
		page.pageIndicatorTitle:Hide()
		page.pageIndicatorSlider:Hide()
		page.pageIndicatorValueText:Hide()
	end
end

-------------------------------------------------------------------------
-- Show a specific bar page
-------------------------------------------------------------------------

-- Switches to the Bars view and shows barId's page (building it if needed).
function ACAB:ShowBarPage(barId)
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	ACAB.settingsFrame.currentView = "bars"
	ACAB:RefreshActiveTabHighlight()

	-- The Setup Wizard shows its step list in the bar list's place.
	ACAB.settingsFrame.listPanel:SetShown(not ACAB.settingsFrame.wizardMode)
	ACAB.settingsFrame.contentScrollFrame:Show()
	ACAB.settingsFrame.contentPanel:Show()
	ACAB:HideWideViews()
	local id
	local page
	for id, page in pairs(ACAB.settingsFrame.pages) do
		page:Hide()
	end

	local target = self:GetOrCreateBarPage(barId)
	self:RefreshBarSettingsPage(barId)
	target:Show()
	ACAB.settingsFrame.activeBarId = barId

	-- Moves the sidebar's gold selection highlight to this page's row (either row may not exist).
	if ACAB.settingsFrame.selectedBarId ~= nil and ACAB.settingsFrame.selectedBarId ~= barId then
		local oldRow = ACAB.settingsFrame.barButtonsByBarId[ACAB.settingsFrame.selectedBarId]
		if oldRow then
			oldRow:SetSelected(false)
		end
	end

	local newRow = ACAB.settingsFrame.barButtonsByBarId[barId]
	if newRow then
		newRow:SetSelected(true)
	end

	ACAB.settingsFrame.selectedBarId = barId

	-- Must run after target:Show() (only shown frames have real rects), deferred one frame.
	ACAB:DeferFit(function() ACAB:FitSettingsWindowToBarPage(barId) end)
end

-------------------------------------------------------------------------
-- Stance / Page Bar Assignment rows
-------------------------------------------------------------------------

-- Dropdown values: 0 = "No Pageswap" (stored as nil), -1 = "Default", 6-9 = Extra Bar 1-4.
local EXTRA_BAR_ASSIGNMENT_CYCLE = { 0, -1, 6, 7, 8, 9 }

local function ExtraBarAssignmentLabel(assignedId)
	if not assignedId or assignedId == 0 then
		return "No Pageswap"
	end

	if assignedId == -1 then
		return "Default"
	end

	return "Extra Bar " .. tostring(assignedId - ACAB.EXTRA_BAR_ID_START + 1)
end

-- The 6 dropdown choices, built once.
local function BuildExtraBarAssignmentDropdownOptions()
	local options = {}
	local i
	for i = 1, table.getn(EXTRA_BAR_ASSIGNMENT_CYCLE) do
		local rawValue = EXTRA_BAR_ASSIGNMENT_CYCLE[i]
		options[i] = {
			text = ExtraBarAssignmentLabel(rawValue ~= 0 and rawValue or nil),
			value = rawValue,
		}
	end

	return options
end

local EXTRA_BAR_ASSIGNMENT_DROPDOWN_OPTIONS = BuildExtraBarAssignmentDropdownOptions()

-- One unanchored assignment row. getFn/setFn use the raw ACABDB value (6-9, -1 or nil), never 0.
-- dropdownName must be unique per pool slot; each slot is created once.
local function CreateExtraBarAssignmentRow(parent, labelText, getFn, setFn, dropdownName)
	local row, dropdown = ACAB:CreateDropdownRow(parent, nil, labelText, 140, dropdownName, EXTRA_BAR_ASSIGNMENT_DROPDOWN_OPTIONS)

	local function RefreshValue()
		local current = getFn() or 0
		dropdown:SetSelected(current, ExtraBarAssignmentLabel(current ~= 0 and current or nil))
	end

	dropdown.onSelect = function(value)
		setFn(value ~= 0 and value or nil)
		RefreshValue()
	end

	row.RefreshValue = RefreshValue
	RefreshValue()
	return row
end

-- Re-shows a pooled assignment row with a new label: unlocked like a new row, width and value re-applied.
local function ReuseExtraBarAssignmentRow(row, labelText)
	local dropdown = row.dropdown
	row.label:SetText(labelText)

	-- Same lookup as ApplyProfileLockGating; it re-locks after RefreshBarSettingsPage's rebuild.
	local dropdownButton = getglobal(dropdown:GetName() .. "Button")
	if dropdownButton then
		ACAB:LockControl(dropdownButton, false)
	else
		ACAB:LockControl(dropdown, false)
	end

	UIDropDownMenu_SetWidth(dropdown.widthPixels, dropdown)
	row.RefreshValue()
	row:Show()
end

-- Stance row for form s on default bar barId, created once per page pool slot.
local function CreateStanceAssignmentRow(container, barId, s, labelText)
	return CreateExtraBarAssignmentRow(
		container,
		labelText,
		function()
			return ACABDB.defaultBarStanceBarAssignment
				and ACABDB.defaultBarStanceBarAssignment[barId]
				and ACABDB.defaultBarStanceBarAssignment[barId][s]
		end,
		function(value)
			if not ACABDB.defaultBarStanceBarAssignment then
				ACABDB.defaultBarStanceBarAssignment = {}
			end

			if not ACABDB.defaultBarStanceBarAssignment[barId] then
				ACABDB.defaultBarStanceBarAssignment[barId] = {}
			end

			ACABDB.defaultBarStanceBarAssignment[barId][s] = value
			ACAB:RefreshDefaultBarSlots()
		end,
		"ACABDefaultBarStanceAssignmentDropdown" .. tostring(barId) .. "_" .. tostring(s)
	)
end

-- "Page 2 Content Source" row for default bar barId, created once per page.
local function CreatePageAssignmentRow(container, barId)
	return CreateExtraBarAssignmentRow(
		container,
		"Page 2 Content Source:",
		function()
			return ACABDB.defaultBarPageBarAssignment
				and ACABDB.defaultBarPageBarAssignment[barId]
		end,
		function(value)
			if not ACABDB.defaultBarPageBarAssignment then
				ACABDB.defaultBarPageBarAssignment = {}
			end

			ACABDB.defaultBarPageBarAssignment[barId] = value
			ACAB:RefreshDefaultBarSlots()
		end,
		"ACABDefaultBarPageBarAssignmentDropdown" .. tostring(barId)
	)
end

-- Rebuilds default bar barId's (1-5) assignment rows: one per stance (stance swap on) plus the Page 2 row
-- (pagination on). Rows are pooled per page (by form index, "page") and created once. No-op if unbuilt.
function ACAB:RebuildDefaultBarAssignmentRows(barId)
	local page = ACAB.settingsFrame and ACAB.settingsFrame.pages[barId]
	if not page or not page.assignmentContainer then return end

	-- DropDownList1 is one shared popout; close it before re-pointing its owner.
	if CloseDropDownMenus then
		CloseDropDownMenus()
	end

	-- Must create each pooled dropdown name only once (see known-problems.md: same-name CreateFrame).
	if not page.assignmentRowPool then
		page.assignmentRowPool = {}
	end

	local pool = page.assignmentRowPool
	local container = page.assignmentContainer
	local i
	for i = 1, table.getn(page.assignmentRows) do
		page.assignmentRows[i]:Hide()
	end

	page.assignmentRows = {}
	local rowIndex = 0
	local y = 0
	local stanceSwapOn = ACABDB.defaultBarStanceSwapEnabled ~= false
	local count = stanceSwapOn and ACAB:GetClampedLiveStanceCount() or 0
	if count and count > 0 then
		local s
		for s = 1, count do
			local icon, name = GetShapeshiftFormInfo(s)
			local label = ((name and name ~= "" and name) or ("Stance " .. tostring(s))) .. ":"
			local row = pool[s]
			if row then
				ReuseExtraBarAssignmentRow(row, label)
			else
				row = CreateStanceAssignmentRow(container, barId, s, label)
				pool[s] = row
			end

			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y)
			rowIndex = rowIndex + 1
			page.assignmentRows[rowIndex] = row
			y = y - 34
		end
	end

	if ACABDB.defaultBarPaginationEnabled ~= false then
		local row = pool.page
		if row then
			ReuseExtraBarAssignmentRow(row, "Page 2 Content Source:")
		else
			row = CreatePageAssignmentRow(container, barId)
			pool.page = row
		end

		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", container, "TOPLEFT", 0, y)
		rowIndex = rowIndex + 1
		page.assignmentRows[rowIndex] = row
		y = y - 34
	end

	-- At least 1 tall, even with no rows.
	local height = -y
	if height < 1 then
		height = 1
	end

	container:SetHeight(height)
end

-- Refreshes every default bar (1-5) page built this session, so its assignment rows are rebuilt and re-gated.
function ACAB:RebuildAllDefaultBarAssignmentRows()
	if not ACAB.settingsFrame then return end

	local id
	for id = 1, 5 do
		if ACAB.settingsFrame.pages[id] then
			self:RefreshBarSettingsPage(id)
		end
	end
end

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

-------------------------------------------------------------------------
-- Bar list (sidebar)
-------------------------------------------------------------------------

-- One sidebar row (default bar, simple page or Extra Bar) with an inline enable checkbox where togglable.
-- Rows and checkboxes are pooled per barId and reconfigured on every refresh.
local function CreateBarListRow(barId, isDefault, cfg)
	local rowPool = ACAB.settingsFrame.barRowPool
	local row = rowPool[barId]
	if row then
		row:Show()
		row:SetSelected(false)
	else
		row = ACAB:CreateListRow(ACAB.settingsFrame.listContent, nil)
		rowPool[barId] = row
	end

	-- Fits the longest name ("Right Action Bar 2") plus the inline checkbox.
	row:SetWidth(110)
	row:SetHeight(LIST_ROW_HEIGHT)

	-- Every row's highlight spans the list panel's full inner width, checkbox or not.
	row:SetVisualWidth(LIST_ITEM_VISUAL_WIDTH, LIST_ITEM_VISUAL_OFFSET)
	row:SetLabel(GetBarDisplayName(barId))
	row.barId = barId

	-- ACABListRowMixin passes the row explicitly (not via `this`).
	row:SetOnClick(function(clickedRow)
		ACAB:ShowBarPage(clickedRow.barId)
	end)

	local simpleConfig = ACAB.simpleBarPageConfigs[barId]
	local wantsCheckbox = false
	local checkedState = false
	local onToggle = nil

	-- Native Stance Bar first: its enabled flag is separate from the styled one.
	if barId == ACAB.STANCE_BAR_ID and ACAB:IsStanceBarNativeMode() then
		local stanceConfig = ACAB.simpleBarPageConfigs[ACAB.STANCE_BAR_ID]
		wantsCheckbox = true
		checkedState = stanceConfig.getEnabled and stanceConfig.getEnabled() ~= false
		onToggle = function(checked)
			stanceConfig.setEnabled(checked)
		end
	elseif isDefault and type(barId) == "number" and barId ~= 1 then
		wantsCheckbox = true
		checkedState = cfg and cfg.enabled == true
		onToggle = function(checked)
			ACAB:SetDefaultBarEnabled(barId, checked)
		end
	elseif simpleConfig and simpleConfig.hasEnable then
		wantsCheckbox = true
		checkedState = simpleConfig.getEnabled and simpleConfig.getEnabled() ~= false
		onToggle = function(checked)
			simpleConfig.setEnabled(checked)
		end
	elseif not isDefault and type(barId) == "number" and ACAB:IsExtraBarId(barId) then
		wantsCheckbox = true
		checkedState = cfg and cfg.enabled == true
		onToggle = function(checked)
			ACAB:SetExtraBarEnabled(barId, checked)
		end
	end

	if not wantsCheckbox and row.checkbox then
		row.checkbox:Hide()
	end

	if wantsCheckbox then
		-- One named frame per barId for the whole session (see known-problems.md: same-name CreateFrame).
		local checkbox = row.checkbox or CreateFrame(
			"CheckButton",
			"ACABBarList" .. tostring(barId) .. "Checkbox",
			ACAB.settingsFrame.listContent,
			"UICheckButtonTemplate"
		)

		checkbox:Show()
		checkbox:SetWidth(20)
		checkbox:SetHeight(20)
		checkbox:ClearAllPoints()
		checkbox:SetPoint("LEFT", row, "RIGHT", 2, 0)
		checkbox:SetChecked(checkedState)
		checkbox.barId = barId

		-- Hovering the checkbox drives the row's shared highlight.
		checkbox:SetScript("OnEnter", function() row:OnRowEnter() end)
		checkbox:SetScript("OnLeave", function() row:OnRowLeave() end)
		checkbox:SetScript(
			"OnClick",
			function()
				local checked = this:GetChecked() and true or false
				onToggle(checked)

				-- Keeps the page's own checkbox (if built) in sync.
				ACAB:RefreshBarSettingsPage(this.barId)
			end
		)

		row.checkbox = checkbox

		-- Numbered default bars are exempt from the Default-profile lock (like page.enableCheckbox).
		local isNumberedDefaultBar = isDefault and type(barId) == "number" and barId ~= 1
		if not isNumberedDefaultBar then
			ACAB:LockControl(checkbox, ACAB:IsDefaultProfileActive())
		elseif barId == 5 then
			-- Bar 5's checkbox mirrors its page's enableCheckbox lock.
			ACAB:LockControl(checkbox, not IsBar5EnableAllowed())
		else
			ACAB:LockControl(checkbox, false)
		end
	end

	-- Greys out (and blocks) bar 5's row itself while it can't be enabled.
	row:SetDisabled(isDefault and barId == 5 and not IsBar5EnableAllowed())
	return row
end

-- Rebuilds the sidebar: default-bar family, simple pages whose element exists, a divider, then Extra Bars 6-9.
function ACAB:RefreshBarList()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	local i
	for i = 1, table.getn(ACAB.settingsFrame.barButtons) do
		local widget = ACAB.settingsFrame.barButtons[i]
		widget:Hide()

		if widget.checkbox then
			widget.checkbox:Hide()
		end
	end

	ACAB.settingsFrame.barButtons = {}
	ACAB.settingsFrame.barButtonsByBarId = {}

	if not ACAB.settingsFrame.barRowPool then
		ACAB.settingsFrame.barRowPool = {}
	end

	local yOffset = -24
	local rowIndex = 0

	-- Anchors row at the running offset and records it under key.
	local function PlaceRow(row, key)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", ACAB.settingsFrame.listContent, "TOPLEFT", 0, yOffset)
		rowIndex = rowIndex + 1
		ACAB.settingsFrame.barButtons[rowIndex] = row
		ACAB.settingsFrame.barButtonsByBarId[key] = row
		yOffset = yOffset - (LIST_ROW_HEIGHT + LIST_ROW_GAP)
	end

	-- Default bars 1-5 plus Pet/Stance Bar (ACAB.DEFAULT_BAR_IDS).
	local dbi
	for dbi = 1, table.getn(ACAB.DEFAULT_BAR_IDS) do
		local id = ACAB.DEFAULT_BAR_IDS[dbi]
		local cfg = ACABDB.defaultBars[id]
		if cfg then
			PlaceRow(CreateBarListRow(id, true, cfg), id)
		end
	end

	-- String-keyed simple pages, each once its element frame exists.
	local specialKeys = ACAB.SIMPLE_PAGE_KEYS
	local si
	for si = 1, table.getn(specialKeys) do
		local key = specialKeys[si]
		local config = ACAB.simpleBarPageConfigs[key]
		local exists = true

		if config and config.getElementFrame then
			exists = config.getElementFrame() ~= nil
		end

		if exists then
			PlaceRow(CreateBarListRow(key, true, nil), key)
		end
	end

	-- Divider between default and custom bars, tracked in barButtons so it's hidden with the rows.
	local divider = ACAB.settingsFrame.barListDivider
	if not divider then
		divider = ACAB.settingsFrame.listContent:CreateTexture(nil, "ARTWORK")
		divider:SetTexture("Interface\\Buttons\\WHITE8X8")
		divider:SetVertexColor(0.5, 0.5, 0.5, 0.6)
		divider:SetWidth(120)
		divider:SetHeight(2)
		ACAB.settingsFrame.barListDivider = divider
	end

	divider:Show()
	divider:ClearAllPoints()
	divider:SetPoint("TOPLEFT", ACAB.settingsFrame.listContent, "TOPLEFT", 2, yOffset + 2)
	rowIndex = rowIndex + 1
	ACAB.settingsFrame.barButtons[rowIndex] = divider
	yOffset = yOffset - 14

	-- Extra Bars 6-9, each toggled by its inline checkbox.
	for i = 1, table.getn(ACABDB.bars) do
		local cfg = ACABDB.bars[i]
		if cfg then
			PlaceRow(CreateBarListRow(cfg.id, false, cfg), cfg.id)
		end
	end

	-- Selection lives on the row instance, so the fresh row for the selected bar is re-selected here.
	if ACAB.settingsFrame.selectedBarId ~= nil then
		local selectedRow = ACAB.settingsFrame.barButtonsByBarId[ACAB.settingsFrame.selectedBarId]
		if selectedRow then
			selectedRow:SetSelected(true)
		end
	end
end

-- Opens a custom bar's page (Button.lua's right-click-to-configure on a live custom-bar button).
function ACAB:OpenBarSettings(bar)
	if not bar or not bar.config then return end

	self:ShowSettingsFrame()

	if self:IsSetupWizardActive() then return end

	self:ShowBarPage(bar.config.id)
end
