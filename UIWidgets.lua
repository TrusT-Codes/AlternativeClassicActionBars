-- UIWidgets.lua
-- Mixin-based widget kit: shared backdrops, inline dropdowns, modern buttons, sliders, checkboxes, color
-- swatches, dialogs, fade strips and list rows. Script handlers use the global `this`; `:` methods use `self`.

local ACAB = AlternativeClassicActionBars

-- Shared accent/hover colors for fade-strip highlights.
ACAB.UI_ACCENT_COLOR = { 1, 0.82, 0 }
ACAB.UI_HOVER_COLOR = { 1, 1, 1 }

-- Shared backdrop tables, passed as-is to SetBackdrop - never mutate them.
-- Tooltip skin for modern buttons, the dialog text area and settings scrollbars.
ACAB.MODERN_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 16,
	edgeSize = 12,
	insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- Small tooltip skin for color swatches and modern preview slots.
ACAB.SMALL_BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true,
	tileSize = 8,
	edgeSize = 8,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- Dialog-box skin for the settings window, dialogs and the setup wizard.
ACAB.DIALOG_BACKDROP = {
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true,
	tileSize = 32,
	edgeSize = 32,
	insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-------------------------------------------------------------------------
-- ACABInlineDropdownMixin: UIDropDownMenuTemplate as a persistent in-panel selector
-------------------------------------------------------------------------

ACABInlineDropdownMixin = {}

-- name is required: the template's native code builds sub-widget names from GetName().
function ACAB:CreateInlineDropdown(parent, widthPixels, name)
	local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")

	-- Explicit re-parent; see known-problems.md: "Inline dropdown SetParent after CreateFrame".
	dropdown:SetParent(parent)

	Mixin(dropdown, ACABInlineDropdownMixin)
	dropdown:OnLoad(widthPixels)

	return dropdown
end

function ACABInlineDropdownMixin:OnLoad(widthPixels)
	self.options = {}
	self.selected = nil
	self.onSelect = nil
	self.widthPixels = widthPixels or 160

	UIDropDownMenu_SetWidth(self.widthPixels, self)

	-- must reapply width/label on show, or a dropdown built while hidden renders fragmented/blank
	self:SetScript("OnShow", function()
		UIDropDownMenu_SetWidth(this.widthPixels, this)

		if this.selectedDisplayText then
			UIDropDownMenu_SetText(this.selectedDisplayText, this)
		end
	end)

	local dropdown = self

	UIDropDownMenu_Initialize(self, function()
		local info
		local i

		for i = 1, table.getn(dropdown.options) do
			local option = dropdown.options[i]

			-- option is a plain string or a { text =, value = } table.
			local optionText = (type(option) == "table") and option.text or option
			local optionValue = (type(option) == "table") and option.value or option

			info = {}
			info.text = optionText
			info.notCheckable = true
			info.func = function()
				dropdown:SetSelected(optionValue, optionText)

				if dropdown.onSelect then
					dropdown.onSelect(optionValue)
				end
			end

			UIDropDownMenu_AddButton(info)
		end
	end)
end

-- options: array of strings or { text = "...", value = ... } tables.
function ACABInlineDropdownMixin:SetOptions(options)
	self.options = options or {}
end

-- Selects value; displayText defaults to the matching option's text (or value itself).
function ACABInlineDropdownMixin:SetSelected(value, displayText)
	self.selected = value

	if not displayText then
		local i

		for i = 1, table.getn(self.options) do
			local option = self.options[i]

			if type(option) == "table" then
				if option.value == value then
					displayText = option.text
					break
				end
			elseif option == value then
				displayText = option
				break
			end
		end
	end

	-- Cached for the OnShow reapply.
	self.selectedDisplayText = displayText or value

	UIDropDownMenu_SetText(self.selectedDisplayText, self)
end

function ACABInlineDropdownMixin:GetSelected()
	return self.selected
end

-------------------------------------------------------------------------
-- Modern button styling (backdrop-based, scales to any width)
-------------------------------------------------------------------------

-- Horizontal label padding added by the styled SetText.
local ACAB_BUTTON_PADDING_X = 32

-- Styles a template-less Button; SetText fits width to the label within [minWidth, maxWidth] (0/nil = none).
function ACAB:StyleModernButton(button, minWidth, maxWidth)
	button:SetBackdrop(ACAB.MODERN_BACKDROP)

	button:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
	button:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)

	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

	text:SetPoint("CENTER", button, "CENTER", 0, 0)
	text:SetJustifyH("CENTER")

	button.text = text
	button.minWidth = minWidth or 0
	button.maxWidth = maxWidth or 0

	-- Replaces native SetText (a template-less Button has no font region).
	button.SetText = function(self, value)
		text:SetText(value or "")

		local width = (text:GetStringWidth() or 0) + ACAB_BUTTON_PADDING_X

		if self.minWidth and self.minWidth > 0 and width < self.minWidth then
			width = self.minWidth
		end

		if self.maxWidth and self.maxWidth > 0 and width > self.maxWidth then
			width = self.maxWidth
		end

		self:SetWidth(width)
	end

	button:SetScript("OnEnter", function()
		this:SetBackdropBorderColor(1, 0.82, 0, 1)
	end)

	button:SetScript("OnLeave", function()
		this:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
	end)

	button:SetScript("OnMouseDown", function()
		if this:IsEnabled() ~= false then
			this.text:SetPoint("CENTER", this, "CENTER", 1, -1)
		end
	end)

	button:SetScript("OnMouseUp", function()
		this.text:SetPoint("CENTER", this, "CENTER", 0, 0)
	end)

	-- Disable/Enable also dim/restore the backdrop and label.
	local nativeDisable = button.Disable
	local nativeEnable = button.Enable

	button.Disable = function(self)
		nativeDisable(self)
		self:SetBackdropColor(0.08, 0.08, 0.08, 0.5)
		self.text:SetTextColor(0.5, 0.5, 0.5)
	end

	button.Enable = function(self)
		nativeEnable(self)
		self:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
		self.text:SetTextColor(1, 1, 1)
	end
end

local DANGER_COLOR = { 0.6, 0.08, 0.08 }

-- Flat red backdrop for a modern button (destructive actions).
function ACAB:ApplyDangerButtonHighlight(button)
	button:SetBackdropColor(DANGER_COLOR[1], DANGER_COLOR[2], DANGER_COLOR[3], 0.9)
end

local PROMINENT_COLOR = { 0.12, 0.35, 0.68 }

-- Flat blue backdrop for a modern button (primary choice).
function ACAB:ApplyProminentButtonHighlight(button)
	button:SetBackdropColor(PROMINENT_COLOR[1], PROMINENT_COLOR[2], PROMINENT_COLOR[3], 0.9)
end

-------------------------------------------------------------------------
-- Sliders
-------------------------------------------------------------------------

function ACAB:CreateSettingSlider(parent, name, width)
	local slider = CreateFrame(
		"Slider",
		name,
		parent,
		"OptionsSliderTemplate"
	)

	slider:SetWidth(width or 300)
	slider:SetHeight(17)

	slider:SetOrientation("HORIZONTAL")

	return slider
end

-- Sets an OptionsSliderTemplate slider's "$parentLow"/"$parentHigh" end labels.
function ACAB:SetSliderEndLabels(slider, lowText, highText)
	local low = getglobal(slider:GetName() .. "Low")

	if low then
		low:SetText(lowText)
	end

	local high = getglobal(slider:GetName() .. "High")

	if high then
		high:SetText(highText)
	end
end

-------------------------------------------------------------------------
-- Position sliders: stepper buttons + click-to-edit readout. Drag, stepper and typed edit all go
-- through slider:SetValue(); OnValueChanged applies the change.
-------------------------------------------------------------------------

-- Position units per one physical screen pixel (read live, tracks UI Scale).
function ACAB:GetPixelStep()
	local scale = UIParent:GetEffectiveScale()

	if not scale or scale <= 0 then
		scale = 1
	end

	return 1 / scale
end

-- Nearest multiple of step (round-half-up); only used for drag-driven slider changes.
function ACAB:RoundToStep(value, step)
	return math.floor(value / step + 0.5) * step
end

-- Suffix counter; keeps every stepper button's frame name unique.
local positionStepperCounter = 0

-- Sets slider's value without the drag pixel-snap in its OnValueChanged.
function ACAB:SetSliderValueUnsnapped(slider, value)
	slider.suppressSnap = true
	slider:SetValue(value)
	slider.suppressSnap = nil
end

-- Sets slider's value without running its onChange apply; valueText (optional) gets text or tostring(value).
function ACAB:SetSliderValueSilently(slider, value, valueText, text)
	slider.suppressApply = true
	slider:SetValue(value)

	if valueText then
		valueText:SetText(text or tostring(value))
	end

	slider.suppressApply = nil
end

-- Clamps value to slider's min/max.
local function ClampToSliderRange(slider, value)
	local min, max = slider:GetMinMaxValues()

	if value < min then
		return min
	elseif value > max then
		return max
	end

	return value
end

-- Adds "--"/"-"/"+"/"++" (10/1 screen pixels) buttons around slider. Returns bigMinus, minus, plus, bigPlus.
function ACAB:CreatePositionStepperButtons(page, slider, namePrefix)
	positionStepperCounter = positionStepperCounter + 1

	local suffix = tostring(positionStepperCounter)

	-- pixels: screen pixels per click; width: fixed button width.
	local function MakeStepButton(name, label, pixels, width)
		local button = CreateFrame("Button", namePrefix .. name .. suffix, page)

		button:SetHeight(20)
		ACAB:StyleModernButton(button, width, width)
		button:SetText(label)

		button:SetScript("OnClick", function()
			local target = slider:GetValue() + (pixels * ACAB:GetPixelStep())

			ACAB:SetSliderValueUnsnapped(slider, ClampToSliderRange(slider, target))
		end)

		return button
	end

	local minus = MakeStepButton("StepperMinus", "-", -1, 20)

	minus:SetPoint("RIGHT", slider, "LEFT", -4, 0)

	local plus = MakeStepButton("StepperPlus", "+", 1, 20)

	plus:SetPoint("LEFT", slider, "RIGHT", 4, 0)

	local bigMinus = MakeStepButton("StepperBigMinus", "--", -10, 20)

	bigMinus:SetPoint("RIGHT", minus, "LEFT", -2, 0)

	local bigPlus = MakeStepButton("StepperBigPlus", "++", 10, 20)

	bigPlus:SetPoint("LEFT", plus, "RIGHT", 2, 0)

	return bigMinus, minus, plus, bigPlus
end

-- Suffix counter; keeps every value EditBox's frame name unique.
local positionEditBoxCounter = 0

-- Click-to-edit overlay for valueText (Enter commits clamped, Escape cancels). Returns clickCatcher, editBox.
function ACAB:MakePositionValueEditable(page, valueText, slider, namePrefix)
	positionEditBoxCounter = positionEditBoxCounter + 1

	local suffix = tostring(positionEditBoxCounter)

	local clickCatcher = CreateFrame(
		"Button",
		namePrefix .. "ValueClick" .. suffix,
		page
	)

	clickCatcher:SetWidth(76)
	clickCatcher:SetHeight(22)
	clickCatcher:SetPoint("CENTER", valueText, "CENTER", 0, 0)
	clickCatcher:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	-- must outrank the next axis's slider, or its overlapping hit region swallows these clicks
	clickCatcher:SetFrameLevel(slider:GetFrameLevel() + 5)

	local editBox = CreateFrame(
		"EditBox",
		namePrefix .. "ValueEditBox" .. suffix,
		page,
		"InputBoxTemplate"
	)

	editBox:SetWidth(50)
	editBox:SetHeight(14)
	editBox:SetAutoFocus(true)
	editBox:SetJustifyH("CENTER")
	editBox:SetPoint("TOP", slider, "BOTTOM", 0, -2)
	editBox:SetFrameLevel(slider:GetFrameLevel() + 5)
	editBox:Hide()

	local function HideEditBox()
		editBox:Hide()
		valueText:Show()
		clickCatcher:Show()
	end

	local function CommitEdit()
		local parsed = tonumber(editBox:GetText())

		if parsed then
			ACAB:SetSliderValueUnsnapped(slider, ClampToSliderRange(slider, parsed))
		end

		editBox:ClearFocus()
	end

	editBox:SetScript("OnEnterPressed", CommitEdit)
	editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
	editBox:SetScript("OnEditFocusLost", HideEditBox)

	clickCatcher:SetScript("OnClick", function()
		editBox:SetText(string.format("%.2f", slider:GetValue()))
		valueText:Hide()
		clickCatcher:Hide()
		editBox:Show()
		editBox:SetFocus()
		editBox:HighlightText()
	end)

	return clickCatcher, editBox
end

-------------------------------------------------------------------------
-- ACAB:CreatePositionAxisSlider: one X or Y position column (slider, end labels, steppers,
-- click-to-edit readout), stored on page[axisKey .. "Slider"/"ValueText"/"StepperMinus"/...].
-- config = { axisKey = "x"|"y", namePrefix, anchor = {point, relativeTo, relativePoint, x, y},
--   min, max, lowText, highText, onApply = function(appliedValue) end }
-- Registers with ACAB:AddHoverOnlyReflowRow. Returns the slider.
-------------------------------------------------------------------------

function ACAB:CreatePositionAxisSlider(page, config)
	local axisKey = config.axisKey
	local axisSuffix = (axisKey == "x") and "X" or "Y"

	local slider = ACAB:CreateSettingSlider(page, config.namePrefix .. axisSuffix .. "Slider", 290)

	slider:SetPoint(unpack(config.anchor))
	slider:SetMinMaxValues(config.min, config.max)

	-- must stay 0: SetValueStep re-snaps the value to a non-pixel grid and positions drift
	slider:SetValueStep(0)

	ACAB:SetSliderEndLabels(slider, config.lowText, config.highText)

	local stepperBigMinus, stepperMinus, stepperPlus, stepperBigPlus =
		ACAB:CreatePositionStepperButtons(page, slider, config.namePrefix .. axisSuffix)

	page[axisKey .. "StepperBigMinus"] = stepperBigMinus
	page[axisKey .. "StepperMinus"] = stepperMinus
	page[axisKey .. "StepperPlus"] = stepperPlus
	page[axisKey .. "StepperBigPlus"] = stepperBigPlus

	local valueText = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

	valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
	valueText:SetText(string.format("%.2f", 0))

	page[axisKey .. "ValueText"] = valueText

	page[axisKey .. "ValueClick"], page[axisKey .. "ValueEditBox"] =
		ACAB:MakePositionValueEditable(page, valueText, slider, config.namePrefix .. axisSuffix)

	slider:SetScript("OnValueChanged", function()
		local value = this:GetValue()

		if not value then
			return
		end

		-- Drag values snap to the pixel grid; stepper/edit commits set suppressSnap to keep theirs exact.
		local applied = value

		if not this.suppressSnap then
			applied = ACAB:RoundToStep(value, ACAB:GetPixelStep())
		end

		page[axisKey .. "AppliedValue"] = applied

		valueText:SetText(string.format("%.2f", applied))

		if not this.suppressApply and config.onApply then
			config.onApply(applied)
		end
	end)

	page[axisKey .. "Slider"] = slider

	ACAB:AddHoverOnlyReflowRow(page, slider, config.anchor[4], config.anchor[5])

	return slider
end

-------------------------------------------------------------------------
-- ACAB:CreateLabeledSlider: title-less slider + centered live-value readout.
-- config = { width (300), anchor = {point, relativeTo, relativePoint, x, y} (required), min, max,
--   step (0), lowText, highText, initialText (""), round = function(value) end,
--   format = function(value) end, onChange = function(value, suppressApply) end }
-- Returns slider, valueText, lowLabel, highLabel.
-------------------------------------------------------------------------

function ACAB:CreateLabeledSlider(parent, name, config)
	config = config or {}

	local slider = ACAB:CreateSettingSlider(parent, name, config.width)

	slider:SetPoint(unpack(config.anchor))

	if config.min and config.max then
		slider:SetMinMaxValues(config.min, config.max)
	end

	slider:SetValueStep(config.step or 0)

	if config.lowText or config.highText then
		ACAB:SetSliderEndLabels(slider, config.lowText, config.highText)
	end

	local lowLabel = getglobal(slider:GetName() .. "Low")
	local highLabel = getglobal(slider:GetName() .. "High")

	local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

	valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
	valueText:SetText(config.initialText or "")

	slider:SetScript("OnValueChanged", function()
		local value = this:GetValue()

		if not value then
			return
		end

		if config.round then
			value = config.round(value)
		end

		valueText:SetText(config.format and config.format(value) or tostring(value))

		if config.onChange then
			config.onChange(value, this.suppressApply and true or false)
		end
	end)

	return slider, valueText, lowLabel, highLabel
end

-------------------------------------------------------------------------
-- ACAB:CreateLabeledCheckbox: UICheckButtonTemplate checkbox with label/anchor/OnClick/tooltip.
-- config = { width (24), height (24), anchor = {point, relativeTo, relativePoint, x, y} (required),
--   label, onClick = function() end, onLockedClick = function() end,
--   tooltip = { title, lines = {...} },
--   lockedText (string or function; red tooltip shown instead while checkbox.ACABLocked) }
-- Returns the checkbox.
-------------------------------------------------------------------------

function ACAB:CreateLabeledCheckbox(parent, name, config)
	config = config or {}

	local checkbox = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")

	checkbox:SetWidth(config.width or 24)
	checkbox:SetHeight(config.height or 24)

	checkbox:SetPoint(unpack(config.anchor))

	if config.onClick then
		local onClick = config.onClick

		-- While ACABLocked: revert the engine's check flip and run onLockedClick instead of onClick.
		checkbox:SetScript("OnClick", function()
			if this.ACABLocked then
				this:SetChecked(not this:GetChecked())

				if config.onLockedClick then
					config.onLockedClick()
				end

				return
			end

			onClick()
		end)
	end

	if config.label then
		local label = getglobal(checkbox:GetName() .. "Text")

		if label then
			label:SetText(config.label)
		end
	end

	if config.tooltip or config.lockedText then
		local tooltip = config.tooltip
		local lockedText = config.lockedText

		-- ACABLocked is read live, so the tooltip always reflects the current lock state.
		checkbox:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")

			if this.ACABLocked and lockedText then
				local resolvedText = lockedText

				if type(lockedText) == "function" then
					resolvedText = lockedText()
				end

				GameTooltip:SetText(resolvedText, 1, 0.15, 0.15, 1, true)
			elseif tooltip then
				GameTooltip:SetText(tooltip.title or "", 1, 1, 1)

				local i

				for i = 1, table.getn(tooltip.lines or {}) do
					GameTooltip:AddLine(tooltip.lines[i], 1, 0.82, 0, true)
				end
			end

			GameTooltip:Show()
		end)

		checkbox:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	return checkbox
end

-------------------------------------------------------------------------
-- ACAB:CreateResetButton: modern-styled "Reset ..." button.
-- config = { name, text ("Reset"), height (22), minWidth (90), maxWidth (90),
--   anchor = {point, relativeTo, relativePoint, x, y}, onClick = function() end }
-- Returns the button.
-------------------------------------------------------------------------

function ACAB:CreateResetButton(parent, config)
	config = config or {}

	local button = CreateFrame("Button", config.name, parent)

	button:SetHeight(config.height or 22)

	if config.anchor then
		button:SetPoint(unpack(config.anchor))
	end

	ACAB:StyleModernButton(button, config.minWidth or 90, config.maxWidth or 90)
	button:SetText(config.text or "Reset")

	if config.onClick then
		button:SetScript("OnClick", config.onClick)
	end

	return button
end

-------------------------------------------------------------------------
-- ACAB:CreateLockToggleButton: 16x16 padlock button; caller drives it via button:SetLocked(bool).
-- config = { anchor = {point, relativeTo, relativePoint, x, y} (required),
--   tooltipTitle, lockedLine, unlockedLine, onClick = function() end }
-- Returns the button.
-------------------------------------------------------------------------

function ACAB:CreateLockToggleButton(parent, name, config)
	config = config or {}

	local button = CreateFrame("Button", name, parent)

	button:SetWidth(16)
	button:SetHeight(16)

	if config.anchor then
		button:SetPoint(unpack(config.anchor))
	end

	local texture = button:CreateTexture(nil, "ARTWORK")
	texture:SetAllPoints(button)
	button.texture = texture

	button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

	function button:SetLocked(locked)
		self.locked = locked and true or false

		self.texture:SetTexture(
			self.locked
				and "Interface\\AddOns\\AlternativeClassicActionBars\\Textures\\LockIcon-Locked"
				or "Interface\\AddOns\\AlternativeClassicActionBars\\Textures\\LockIcon-Unlocked"
		)
	end

	button:SetScript("OnClick", function()
		if config.onClick then
			config.onClick()
		end
	end)

	button:SetScript("OnEnter", function()
		GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
		GameTooltip:SetText(config.tooltipTitle or "", 1, 1, 1)
		GameTooltip:AddLine(
			this.locked and (config.lockedLine or "") or (config.unlockedLine or ""),
			1, 0.82, 0, true
		)
		GameTooltip:Show()
	end)

	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return button
end

-------------------------------------------------------------------------
-- Color swatches + the native ColorPickerFrame
-------------------------------------------------------------------------

-- 24x24 bordered button with a solid WHITE8X8 fill tinted to the color it represents.
function ACAB:CreateColorSwatch(parent, name)
	local swatch = CreateFrame("Button", name, parent)

	swatch:SetWidth(24)
	swatch:SetHeight(24)

	swatch:SetBackdrop(ACAB.SMALL_BACKDROP)
	swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

	local tex = swatch:CreateTexture(nil, "ARTWORK")

	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
	tex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)

	swatch.colorTexture = tex

	return swatch
end

-- Tints swatch to color ({ r, g, b }, missing channels = 1); no-op without a color.
function ACAB:SetColorSwatchColor(swatch, color)
	if not swatch or not swatch.colorTexture or not color then
		return
	end

	swatch.colorTexture:SetVertexColor(color.r or 1, color.g or 1, color.b or 1)
end

-- Opens the native ColorPickerFrame on getter()'s color, beside anchorFrame; setter(r, g, b) gets live
-- drags and Cancel's restore, and swatch follows along.
function ACAB:OpenColorPicker(swatch, getter, setter, anchorFrame)
	local current = getter() or { r = 1, g = 1, b = 1 }

	ColorPickerFrame.func = function()
		local r, g, b = ColorPickerFrame:GetColorRGB()

		setter(r, g, b)
		ACAB:SetColorSwatchColor(swatch, getter())
	end

	-- No alpha channel; opacityFunc is still a no-op in case the client calls it anyway.
	ColorPickerFrame.opacityFunc = function() end
	ColorPickerFrame.hasOpacity = false

	ColorPickerFrame.cancelFunc = function(previousValues)
		if previousValues then
			setter(previousValues.r, previousValues.g, previousValues.b)
			ACAB:SetColorSwatchColor(swatch, getter())
		end
	end

	ColorPickerFrame:SetColorRGB(current.r, current.g, current.b)

	-- One strata above the DIALOG-strata settings window.
	ColorPickerFrame:ClearAllPoints()
	ColorPickerFrame:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", 10, 0)
	ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")

	ShowUIPanel(ColorPickerFrame)
end

-------------------------------------------------------------------------
-- ACABDialogMixin: one lazily-created dialog (ACAB.activeDialog), reconfigured per ACAB:ShowDialog.
-- mode = "confirm" | "textinput" (EditBox) | "dropdown" (inline dropdown) | "textarea" (scrolling EditBox)
-------------------------------------------------------------------------

ACABDialogMixin = {}

local DIALOG_WIDTH = 360
local DIALOG_BUTTON_HEIGHT = 22
local DIALOG_BUTTON_MIN_WIDTH = 100
-- Sizes for buttonConfig.variant "prominent" (primary choice) and "minor" (de-emphasized).
local DIALOG_BUTTON_HEIGHT_PROMINENT = 34
local DIALOG_BUTTON_MIN_WIDTH_PROMINENT = 220
local DIALOG_BUTTON_HEIGHT_MINOR = 18
local DIALOG_BUTTON_MIN_WIDTH_MINOR = 80
local DIALOG_TEXTAREA_HEIGHT = 160
local DIALOG_ERROR_BANNER_HEIGHT = 54
local DIALOG_TEXTAREA_SCROLLBAR_RESERVE = 28
-- Fixed text-area scroll-child height (not measured from the text).
local DIALOG_TEXTAREA_CONTENT_HEIGHT = 4000

-- Creates the scrolling multi-line EditBox used by mode == "textarea".
local function CreateDialogTextArea(dialog)
	local scrollFrame = ACAB:CreateScrollFrame(dialog, "ACABDialogTextAreaScrollFrame")

	scrollFrame:SetBackdrop(ACAB.MODERN_BACKDROP)
	scrollFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

	local editBox = CreateFrame("EditBox", "ACABDialogTextAreaEditBox", scrollFrame)

	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetMaxLetters(0)
	-- Keeps text off the backdrop border (no template padding).
	editBox:SetTextInsets(6, 6, 4, 4)
	editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)

	scrollFrame:SetScrollChild(editBox)
	scrollFrame.editBox = editBox

	return scrollFrame
end

local function EnsureDialogFrame()
	if ACAB.activeDialog then
		return ACAB.activeDialog
	end

	local dialog = CreateFrame("Frame", "ACABDialog", UIParent)

	Mixin(dialog, ACABDialogMixin)
	dialog:OnLoad()

	ACAB.activeDialog = dialog

	return dialog
end

function ACABDialogMixin:OnLoad()
	-- Above the DIALOG-strata settings window.
	self:SetFrameStrata("FULLSCREEN_DIALOG")
	self:SetWidth(DIALOG_WIDTH)
	self:SetHeight(160)
	self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

	self:SetBackdrop(ACAB.DIALOG_BACKDROP)

	self:EnableMouse(true)
	self:SetMovable(true)
	self:RegisterForDrag("LeftButton")
	self:SetScript("OnDragStart", function() this:StartMoving() end)
	self:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

	self.titleText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	self.titleText:SetPoint("TOP", self, "TOP", 0, -18)
	self.titleText:SetWidth(DIALOG_WIDTH - 40)

	self.messageText = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.messageText:SetPoint("TOP", self.titleText, "BOTTOM", 0, -10)
	self.messageText:SetWidth(DIALOG_WIDTH - 40)
	self.messageText:SetJustifyH("CENTER")

	-- Optional red line under the message (config.warningText).
	self.warningText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.warningText:SetWidth(DIALOG_WIDTH - 40)
	self.warningText:SetJustifyH("CENTER")
	self.warningText:SetTextColor(1, 0.15, 0.15)
	self.warningText:Hide()

	self.textArea = CreateDialogTextArea(self)
	self.textArea:Hide()

	-- Inline validation-error banner (red backdrop).
	local errorBanner = CreateFrame("Frame", nil, self)

	errorBanner:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})
	errorBanner:SetBackdropColor(0.35, 0, 0, 0.9)

	local errorBannerText = errorBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	errorBannerText:SetPoint("TOPLEFT", errorBanner, "TOPLEFT", 8, -6)
	errorBannerText:SetPoint("TOPRIGHT", errorBanner, "TOPRIGHT", -8, -6)
	errorBannerText:SetJustifyH("LEFT")
	errorBannerText:SetJustifyV("TOP")
	errorBannerText:SetTextColor(1, 0.15, 0.15)

	errorBanner.text = errorBannerText
	errorBanner:Hide()

	self.errorBanner = errorBanner

	-- Single-line input for mode == "textinput".
	self.editBox = CreateFrame("EditBox", "ACABDialogEditBox", self, "InputBoxTemplate")
	self.editBox:SetWidth(DIALOG_WIDTH - 80)
	self.editBox:SetHeight(20)
	self.editBox:SetAutoFocus(true)
	self.editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	self.editBox:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		ACAB.activeDialog:ClickDefaultButton()
	end)
	self.editBox:Hide()

	self.dropdown = ACAB:CreateInlineDropdown(self, DIALOG_WIDTH - 80, "ACABDialogDropdown")
	self.dropdown:Hide()

	-- Fixed pool of 4 buttons; height/minWidth are set per variant in Init.
	self.buttons = {}

	local i

	for i = 1, 4 do
		local button = CreateFrame("Button", nil, self)

		ACAB:StyleModernButton(button, DIALOG_BUTTON_MIN_WIDTH, DIALOG_WIDTH - 40)
		button:Hide()

		self.buttons[i] = button
	end

	self:Hide()
end

-- config = {
--   title, message, mode = "confirm"|"textinput"|"dropdown"|"textarea",
--   defaultText,                -- textinput/textarea starting value
--   options = {...},            -- dropdown values
--   warningText,                -- optional red line under the message
--   reserveErrorBanner = true,  -- reserves space for :ShowInlineError
--   liveValidate = function(value) return ok, errorMessage end, -- textarea only
--   buttons = { { text, isDefault, danger, keepOpen,
--     variant = "prominent"|"minor",  -- prominent = larger + blue, minor = smaller + red
--     validate = function(value) return ok, errorMessage end,
--     onClick = function(value) end }, ... },
-- }
function ACABDialogMixin:Init(config)
	config = config or {}

	self.mode = config.mode or "confirm"
	self.buttonConfigs = config.buttons or {}
	self.hasErrorBannerSlot = config.reserveErrorBanner and true or false

	self.titleText:SetText(config.title or "")
	self.messageText:SetText(config.message or "")

	self.editBox:Hide()
	self.dropdown:Hide()
	self.textArea:Hide()
	self.errorBanner:Hide()

	local anchorAbove = self.messageText

	if config.warningText then
		self.warningText:ClearAllPoints()
		self.warningText:SetPoint("TOP", self.messageText, "BOTTOM", 0, -8)
		self.warningText:SetText(config.warningText)
		self.warningText:Show()
		anchorAbove = self.warningText
	else
		self.warningText:Hide()
	end

	if self.mode == "textinput" then
		self.editBox:ClearAllPoints()
		self.editBox:SetPoint("TOP", anchorAbove, "BOTTOM", 0, -14)
		self.editBox:SetText(config.defaultText or "")
		self.editBox:HighlightText()
		self.editBox:Show()
		anchorAbove = self.editBox
	elseif self.mode == "dropdown" then
		self.dropdown:ClearAllPoints()
		self.dropdown:SetPoint("TOP", anchorAbove, "BOTTOM", 0, -10)
		self.dropdown:SetOptions(config.options or {})
		self.dropdown:SetSelected((config.options or {})[1])
		self.dropdown:Show()
		anchorAbove = self.dropdown
	elseif self.mode == "textarea" then
		self.textArea:ClearAllPoints()
		self.textArea:SetPoint("TOP", anchorAbove, "BOTTOM", 0, -10)
		self.textArea:SetWidth(DIALOG_WIDTH - 80)
		self.textArea.editBox:SetText(config.defaultText or "")
		self.textArea.editBox:HighlightText()

		-- UpdateScrollFrame resets the EditBox to the scrollFrame's width; narrowed again right after.
		ACAB:UpdateScrollFrame(
			self.textArea,
			self.textArea.editBox,
			DIALOG_TEXTAREA_CONTENT_HEIGHT,
			DIALOG_TEXTAREA_HEIGHT
		)
		self.textArea.editBox:SetWidth(DIALOG_WIDTH - 80 - DIALOG_TEXTAREA_SCROLLBAR_RESERVE)

		self.textArea.editBox:SetScript("OnTextChanged", function()
			if not config.liveValidate then
				return
			end

			local text = this:GetText()

			if not text or text == "" then
				ACAB.activeDialog.errorBanner:Hide()
				return
			end

			local ok, message = config.liveValidate(text)

			if ok then
				ACAB.activeDialog.errorBanner:Hide()
			else
				ACAB.activeDialog:ShowInlineError(message)
			end
		end)

		self.textArea:Show()
		anchorAbove = self.textArea
	end

	if self.hasErrorBannerSlot then
		self.errorBanner:ClearAllPoints()
		self.errorBanner:SetPoint("TOP", anchorAbove, "BOTTOM", 0, -8)
		self.errorBanner:SetWidth(DIALOG_WIDTH - 40)
		self.errorBanner:SetHeight(DIALOG_ERROR_BANNER_HEIGHT)
		self.errorBanner.text:SetWidth(DIALOG_WIDTH - 56)
	end

	-- Buttons wrap into rows, each row centered on the dialog.
	local BUTTON_GAP_X = 12
	local BUTTON_ROW_GAP_Y = 8
	local availableWidth = DIALOG_WIDTH - 40

	local i
	local count = table.getn(self.buttonConfigs)
	self.defaultButtonIndex = nil

	-- Pass 1: configure each button so its label-fit width is known before row packing.
	for i = 1, 4 do
		local button = self.buttons[i]
		local buttonConfig = self.buttonConfigs[i]

		if buttonConfig then
			local variant = buttonConfig.variant

			-- Pooled buttons: size and color are reset every Init.
			if variant == "prominent" then
				button:SetHeight(DIALOG_BUTTON_HEIGHT_PROMINENT)
				button.minWidth = DIALOG_BUTTON_MIN_WIDTH_PROMINENT
			elseif variant == "minor" then
				button:SetHeight(DIALOG_BUTTON_HEIGHT_MINOR)
				button.minWidth = DIALOG_BUTTON_MIN_WIDTH_MINOR
			else
				button:SetHeight(DIALOG_BUTTON_HEIGHT)
				button.minWidth = DIALOG_BUTTON_MIN_WIDTH
			end

			button.maxWidth = DIALOG_WIDTH - 40

			button:SetText(buttonConfig.text or "")

			if buttonConfig.danger or variant == "minor" then
				ACAB:ApplyDangerButtonHighlight(button)
			elseif variant == "prominent" then
				ACAB:ApplyProminentButtonHighlight(button)
			else
				button:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
			end

			button:SetScript("OnClick", function()
				local value = ACAB.activeDialog:GetValue()

				if buttonConfig.validate then
					local ok, message = buttonConfig.validate(value)

					if not ok then
						ACAB.activeDialog:ShowInlineError(message)
						return
					end
				end

				if not buttonConfig.keepOpen then
					ACAB.activeDialog:Hide()
				end

				if buttonConfig.onClick then
					buttonConfig.onClick(value)
				end
			end)

			if buttonConfig.isDefault then
				self.defaultButtonIndex = i
			end

			button:Show()
		else
			button:Hide()
		end
	end

	if not self.defaultButtonIndex and count > 0 then
		self.defaultButtonIndex = 1
	end

	-- Pass 2: greedily pack buttons into rows (button indices, total width, tallest height per row).
	local rows = {}
	local rowWidths = {}
	local rowHeights = {}
	local rowCount = 0

	for i = 1, count do
		local button = self.buttons[i]
		local width = button:GetWidth()
		local height = button:GetHeight()
		local addWidth = BUTTON_GAP_X + width

		if rowCount == 0 or (rowWidths[rowCount] + addWidth) > availableWidth then
			rowCount = rowCount + 1
			rows[rowCount] = {}
			rowWidths[rowCount] = 0
			rowHeights[rowCount] = 0
			addWidth = width
		end

		table.insert(rows[rowCount], i)
		rowWidths[rowCount] = rowWidths[rowCount] + addWidth

		if height > rowHeights[rowCount] then
			rowHeights[rowCount] = height
		end
	end

	-- Rows anchor off the dialog's TOP at offsets summed from the content above.
	local TOP_OFFSET = 18
	local BOTTOM_PADDING = 20

	local contentBottomY = TOP_OFFSET
	contentBottomY = contentBottomY + (self.titleText:GetHeight() or 0)
	contentBottomY = contentBottomY + 10 + (self.messageText:GetHeight() or 0)

	if config.warningText then
		contentBottomY = contentBottomY + 8 + (self.warningText:GetHeight() or 0)
	end

	if self.mode == "textinput" then
		contentBottomY = contentBottomY + 14 + (self.editBox:GetHeight() or 0)
	elseif self.mode == "dropdown" then
		contentBottomY = contentBottomY + 10 + (self.dropdown:GetHeight() or 0)
	elseif self.mode == "textarea" then
		contentBottomY = contentBottomY + 10 + DIALOG_TEXTAREA_HEIGHT
	end

	if self.hasErrorBannerSlot then
		contentBottomY = contentBottomY + 8 + DIALOG_ERROR_BANNER_HEIGHT
	end

	local rowY = contentBottomY
	local r

	for r = 1, rowCount do
		local rowGap = (r == 1) and 14 or BUTTON_ROW_GAP_Y

		rowY = rowY + rowGap

		local row = rows[r]
		local cursorX = -(rowWidths[r] / 2)
		local j

		for j = 1, table.getn(row) do
			local button = self.buttons[row[j]]
			local width = button:GetWidth()
			local centerX = cursorX + (width / 2)

			button:ClearAllPoints()
			button:SetPoint("TOP", self, "TOP", centerX, -rowY)

			cursorX = cursorX + width + BUTTON_GAP_X
		end

		rowY = rowY + rowHeights[r]
	end

	self:SetHeight(rowY + BOTTOM_PADDING)
end

function ACABDialogMixin:GetValue()
	if self.mode == "textinput" then
		return self.editBox:GetText()
	elseif self.mode == "dropdown" then
		return self.dropdown:GetSelected()
	elseif self.mode == "textarea" then
		return self.textArea.editBox:GetText()
	end

	return nil
end

-- Shows message in the reserved error banner; no-op without config.reserveErrorBanner.
function ACABDialogMixin:ShowInlineError(message)
	if not self.hasErrorBannerSlot then
		return
	end

	self.errorBanner.text:SetText(message or "")
	self.errorBanner:Show()
end

-- Calls the default button's OnClick handler directly.
function ACABDialogMixin:ClickDefaultButton()
	local index = self.defaultButtonIndex
	local button = index and self.buttons[index]

	if button and button:IsShown() then
		local handler = button:GetScript("OnClick")

		if handler then
			handler()
		end
	end
end

-- must not be named Show: Mixin copies it onto the frame and would shadow the native Show
function ACABDialogMixin:Display()
	self:Show()

	if self.mode == "textinput" then
		self.editBox:SetFocus()
	elseif self.mode == "textarea" then
		self.textArea.editBox:SetFocus()
	end
end

-- Opens the shared dialog configured by config (see ACABDialogMixin:Init). Returns the dialog.
function ACAB:ShowDialog(config)
	local dialog = EnsureDialogFrame()

	dialog:Init(config)
	dialog:Display()

	return dialog
end

-------------------------------------------------------------------------
-- ACABFadeStripMixin / ACAB:CreateFadeStrip: horizontal fade highlight built from ARTWORK textures
-- owned by `parent` itself (see known-problems.md: "Fade strip textures live on the parent").
-- Normal: clear -> solid -> clear (3 textures); options.inverted: solid -> clear -> solid (4).
-- options.edgeFraction: each edge's share of the width (default 0.1).
-------------------------------------------------------------------------

ACABFadeStripMixin = {}

local function CreateStripTexture(parent)
	local texture = parent:CreateTexture(nil, "ARTWORK")

	texture:SetTexture("Interface\\Buttons\\WHITE8X8")

	return texture
end

-- Anchors texture to the right of previous and sizes it.
local function ChainStripTexture(texture, previous, width, height)
	texture:ClearAllPoints()
	texture:SetPoint("TOPLEFT", previous, "TOPRIGHT", 0, 0)
	texture:SetWidth(width)
	texture:SetHeight(height)
end

-- width/height: initial strip size (resize later via SetStripWidth/SetStripHeight).
function ACAB:CreateFadeStrip(parent, width, height, options)
	options = options or {}

	local strip = {}

	Mixin(strip, ACABFadeStripMixin)

	strip.r, strip.g, strip.b = 1, 1, 1
	strip.peakAlpha = 1
	strip.height = height or 0
	strip.edgeFraction = options.edgeFraction or 0.1
	strip.inverted = options.inverted and true or false

	strip.leftTex = CreateStripTexture(parent)
	strip.midTex = CreateStripTexture(parent)
	strip.rightTex = CreateStripTexture(parent)

	if strip.inverted then
		strip.midRightTex = CreateStripTexture(parent)
	end

	strip:SetStripWidth(width)
	strip:ApplyFadeColors()

	return strip
end

-- Region-like API; every other texture chains off leftTex's anchor.
function ACABFadeStripMixin:SetPoint(...)
	self.leftTex:SetPoint(unpack(arg))
end

function ACABFadeStripMixin:ClearAllPoints()
	self.leftTex:ClearAllPoints()
end

function ACABFadeStripMixin:Show()
	self.leftTex:Show()
	self.midTex:Show()
	self.rightTex:Show()

	if self.midRightTex then
		self.midRightTex:Show()
	end
end

function ACABFadeStripMixin:Hide()
	self.leftTex:Hide()
	self.midTex:Hide()
	self.rightTex:Hide()

	if self.midRightTex then
		self.midRightTex:Hide()
	end
end

function ACABFadeStripMixin:IsShown()
	return self.leftTex:IsShown()
end

function ACABFadeStripMixin:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end

-- Recomputes the texture split for width (color untouched).
function ACABFadeStripMixin:SetStripWidth(width)
	self.width = width

	local height = self.height or 0
	local edgeWidth = width * self.edgeFraction
	local midWidth = width - (edgeWidth * 2)

	if self.inverted then
		midWidth = midWidth / 2
	end

	self.leftTex:SetWidth(edgeWidth)
	self.leftTex:SetHeight(height)

	ChainStripTexture(self.midTex, self.leftTex, midWidth, height)

	local previous = self.midTex

	if self.inverted then
		ChainStripTexture(self.midRightTex, self.midTex, midWidth, height)
		previous = self.midRightTex
	end

	ChainStripTexture(self.rightTex, previous, edgeWidth, height)
end

-- Resizes only the height.
function ACABFadeStripMixin:SetStripHeight(height)
	self.height = height

	self.leftTex:SetHeight(height)
	self.midTex:SetHeight(height)
	self.rightTex:SetHeight(height)

	if self.midRightTex then
		self.midRightTex:SetHeight(height)
	end
end

-- Reapplies gradients/solid colors from r/g/b/peakAlpha.
function ACABFadeStripMixin:ApplyFadeColors()
	local r, g, b, a = self.r, self.g, self.b, self.peakAlpha

	if self.inverted then
		self.leftTex:SetVertexColor(r, g, b, a)
		self.midTex:SetGradientAlpha("HORIZONTAL", r, g, b, a, r, g, b, 0)
		self.midRightTex:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, a)
		self.rightTex:SetVertexColor(r, g, b, a)
	else
		self.leftTex:SetGradientAlpha("HORIZONTAL", r, g, b, 0, r, g, b, a)
		self.midTex:SetVertexColor(r, g, b, a)
		self.rightTex:SetGradientAlpha("HORIZONTAL", r, g, b, a, r, g, b, 0)
	end
end

function ACABFadeStripMixin:SetFadeColor(r, g, b)
	self.r, self.g, self.b = r, g, b
	self:ApplyFadeColors()
end

function ACABFadeStripMixin:SetPeakAlpha(a)
	self.peakAlpha = a
	self:ApplyFadeColors()
end

-------------------------------------------------------------------------
-- ACABListRowMixin: list row with select/hover fade strips; disabled hides both and blocks onClick.
-------------------------------------------------------------------------

ACABListRowMixin = {}

-- name is optional.
function ACAB:CreateListRow(parent, name)
	local row = CreateFrame("Button", name, parent)

	-- must capture native SetWidth/SetHeight BEFORE Mixin, or the overrides recurse infinitely
	row.nativeSetWidth = row.SetWidth
	row.nativeSetHeight = row.SetHeight

	Mixin(row, ACABListRowMixin)

	row:OnLoad()

	return row
end

function ACABListRowMixin:OnLoad()
	self.isSelected = false
	self.isDisabled = false
	self.isHovering = false
	self.onClick = nil

	local width, height = self:GetWidth(), self:GetHeight()

	self.selectStrip = ACAB:CreateFadeStrip(self, width, height)
	self.selectStrip:SetPoint("LEFT", self, "LEFT", 0, 0)
	self.selectStrip:SetFadeColor(ACAB.UI_ACCENT_COLOR[1], ACAB.UI_ACCENT_COLOR[2], ACAB.UI_ACCENT_COLOR[3])
	self.selectStrip:SetPeakAlpha(0.35)
	self.selectStrip:Hide()

	-- Created after selectStrip so it draws on top.
	self.hoverStrip = ACAB:CreateFadeStrip(self, width, height)
	self.hoverStrip:SetPoint("LEFT", self, "LEFT", 0, 0)
	self.hoverStrip:SetFadeColor(ACAB.UI_HOVER_COLOR[1], ACAB.UI_HOVER_COLOR[2], ACAB.UI_HOVER_COLOR[3])
	self.hoverStrip:SetPeakAlpha(0.25)
	self.hoverStrip:Hide()

	self.label = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	self.label:SetPoint("LEFT", self, "LEFT", 8, 0)
	self.label:SetJustifyH("LEFT")

	self:SetScript("OnEnter", function()
		this:OnRowEnter()
	end)

	self:SetScript("OnLeave", function()
		this:OnRowLeave()
	end)

	self:SetScript("OnClick", function()
		if (not this.isDisabled) and this.onClick then
			this.onClick(this)
		end
	end)

	self:UpdateVisualState()
end

function ACABListRowMixin:SetLabel(text)
	self.label:SetText(text or "")
end

function ACABListRowMixin:SetOnClick(onClick)
	self.onClick = onClick
end

function ACABListRowMixin:SetSelected(selected)
	self.isSelected = selected and true or false
	self:UpdateVisualState()
end

-- Disabled overrides hover/selected visuals and blocks onClick (OnEnter/OnLeave still fire).
function ACABListRowMixin:SetDisabled(disabled)
	self.isDisabled = disabled and true or false
	self:UpdateVisualState()
end

-- Resizes/offsets only the fade strips, not the row's hit box.
function ACABListRowMixin:SetVisualWidth(width, offsetX)
	offsetX = offsetX or 0

	self.selectStrip:ClearAllPoints()
	self.selectStrip:SetPoint("LEFT", self, "LEFT", offsetX, 0)
	self.selectStrip:SetStripWidth(width)

	self.hoverStrip:ClearAllPoints()
	self.hoverStrip:SetPoint("LEFT", self, "LEFT", offsetX, 0)
	self.hoverStrip:SetStripWidth(width)
end

-- Native SetWidth plus strip width sync.
function ACABListRowMixin:SetWidth(width)
	self.nativeSetWidth(self, width)

	if self.selectStrip then
		self.selectStrip:SetStripWidth(width)
		self.hoverStrip:SetStripWidth(width)
	end
end

-- Native SetHeight plus strip height sync.
function ACABListRowMixin:SetHeight(height)
	self.nativeSetHeight(self, height)

	if self.selectStrip then
		self.selectStrip:SetStripHeight(height)
		self.hoverStrip:SetStripHeight(height)
	end
end

-- Hover enter/leave; also called by sibling frames that share this row's hover highlight.
function ACABListRowMixin:OnRowEnter()
	self.isHovering = true
	self:UpdateVisualState()
end

function ACABListRowMixin:OnRowLeave()
	self.isHovering = false
	self:UpdateVisualState()
end

function ACABListRowMixin:UpdateVisualState()
	if self.isDisabled then
		self.selectStrip:Hide()
		self.hoverStrip:Hide()
		self.label:SetTextColor(0.5, 0.5, 0.5)
		return
	end

	self.label:SetTextColor(1, 1, 1)

	if self.isSelected then
		self.selectStrip:Show()
	else
		self.selectStrip:Hide()
	end

	if self.isHovering then
		self.hoverStrip:Show()
	else
		self.hoverStrip:Hide()
	end
end
