-- UIWidgets.lua
-- Reusable Mixin-based dialog/dropdown widget kit, built on ClassicAPI's
-- Mixin/CreateFromMixins primitives.
--
-- Engine-invoked script handlers (OnClick, OnShow, OnHide) receive the
-- frame via the global `this`, never as a `self` parameter.

local ACAB = AlternativeClassicActionBars

-- Shared accent/hover colors for the fade-strip treatment below.
ACAB.UI_ACCENT_COLOR = { 1, 0.82, 0 }
ACAB.UI_HOVER_COLOR = { 1, 1, 1 }

-------------------------------------------------------------------------
-- ACABInlineDropdownMixin
--
-- Wraps the native UIDropDownMenuTemplate as a persistent in-panel
-- selector instead of a transient right-click popup.
-------------------------------------------------------------------------

ACABInlineDropdownMixin = {}

-- parent: frame to anchor into. name: REQUIRED - UIDropDownMenuTemplate's
-- native FrameXML machinery builds internal sub-widget references by
-- string-concatenating this frame's own GetName() (UIDropDownMenu_
-- Initialize/SetWidth/etc.); a nameless dropdown fails with "attempt to
-- concatenate a nil value".
-- Returns the created dropdown frame with this mixin applied.
function ACAB:CreateInlineDropdown(parent, widthPixels, name)
	local dropdown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")

	-- CreateFrame only applies `parent` the first time a given global
	-- `name` is created - on reuse it keeps whatever parent it already
	-- had. Must SetParent explicitly here or a reused dropdown stays
	-- attached to an orphaned old frame and stops rendering reliably.
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

	-- Re-applied on OnShow too: a dropdown built while its page is still
	-- hidden can end up with fragmented skin pieces and a stale/blank
	-- label otherwise.
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

			-- option is either a plain string, or a { text =, value = }
			-- table when the stored value isn't a sensible display label.
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

-- options: array of strings, or { text = "...", value = ... } tables when
-- the value isn't itself a usable label.
function ACABInlineDropdownMixin:SetOptions(options)
	self.options = options or {}
end

-- displayText is optional - when omitted, `value` itself is shown (plain-
-- string options) or looked up from a matching { text=, value= } entry.
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

	-- Cached so OnShow can reapply the label after this frame becomes visible.
	self.selectedDisplayText = displayText or value

	UIDropDownMenu_SetText(self.selectedDisplayText, self)
end

function ACABInlineDropdownMixin:GetSelected()
	return self.selected
end

-------------------------------------------------------------------------
-- Modern button styling
--
-- Backdrop-based button styling (not UIPanelButtonTemplate) that scales
-- cleanly to arbitrary widths.
-------------------------------------------------------------------------

-- Turns a plain, template-less Button frame into a modern-styled one.
-- Caller still creates the frame and sets its own SetHeight/OnClick/etc
-- as normal - this applies the visuals and installs a :SetText that
-- resizes the button to fit its label (ACAB_BUTTON_PADDING_X either side),
-- clamped to [minWidth, maxWidth]. Pass 0/math.huge (or omit) for no
-- clamping on that side.
local ACAB_BUTTON_PADDING_X = 32

function ACAB:StyleModernButton(button, minWidth, maxWidth)
	button:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})

	button:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
	button:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)

	local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

	text:SetPoint("CENTER", button, "CENTER", 0, 0)
	text:SetJustifyH("CENTER")

	button.text = text
	button.minWidth = minWidth or 0
	button.maxWidth = maxWidth or 0

	-- Overrides the native Button:SetText - a template-less Button has no
	-- font region wired to it by default.
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

	-- Dims backdrop/text to match native Disable/Enable's grey-out, since
	-- this button has no UIPanelButtonTemplate texture to grey out itself.
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

-------------------------------------------------------------------------
-- Slider construction shared by every settings page builder.
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

-- Sets an OptionsSliderTemplate slider's auto-created end labels
-- (its "$parentLow"/"$parentHigh" FontStrings).
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
-- Position slider stepper buttons + click-to-edit value readout, shared
-- by every X/Y position slider. Drag, stepper click and typed edit all
-- funnel through slider:SetValue(); its OnValueChanged applies the change.
-------------------------------------------------------------------------

-- PixelUtil.SetPoint rounds X/Y to whole physical screen pixels
-- (UIParent:GetEffectiveScale()), so a flat sub-pixel step can produce no
-- visible change. Returns position units per one real screen pixel, read
-- live so it tracks UI Scale changes without a reload.
function ACAB:GetPixelStep()
	local scale = UIParent:GetEffectiveScale()

	if not scale or scale <= 0 then
		scale = 1
	end

	return 1 / scale
end

-- Nearest multiple of `step` to `value` (round-half-up). Used only to
-- snap DRAG-driven changes onto the pixel grid - never applied to a
-- stepper-button or typed-edit value, which must move/land exactly
-- where the user asked.
function ACAB:RoundToStep(value, step)
	return math.floor(value / step + 0.5) * step
end

-- WARNING: Slider:SetValueStep(step) immediately re-snaps the slider's
-- current value to its step grid, which isn't pixel-aligned. Keep these
-- X/Y sliders at step 0 permanently; pixel snapping on drag is done
-- manually in OnValueChanged (guarded by this.suppressSnap so stepper/
-- edit-box commits keep their exact value) - or values silently drift.

-- Bumped on every call so each set of stepper buttons gets unique frame names.
local positionStepperCounter = 0

-- Sets `slider`'s value without the drag-snap-to-0.5 logic in its
-- OnValueChanged handler touching it - used by every stepper/edit-box
-- commit so their exact target value sticks.
function ACAB:SetSliderValueUnsnapped(slider, value)
	slider.suppressSnap = true
	slider:SetValue(value)
	slider.suppressSnap = nil
end

-- Adds "--"/"-"/"+"/"++" buttons flanking `slider` (stepping by 10 and 1
-- real screen pixels respectively - see GetPixelStep), anchored to it
-- directly so they track any later reflow of the slider itself without
-- separate registration. namePrefix should already be unique to the
-- owning page. Returns bigMinus, minus, plus, bigPlus.
function ACAB:CreatePositionStepperButtons(page, slider, namePrefix)
	positionStepperCounter = positionStepperCounter + 1

	local suffix = tostring(positionStepperCounter)

	-- pixels: how many real screen pixels this button shifts the
	-- slider's current value by, per click (converted to position units
	-- live via GetPixelStep, so it stays correct if UI Scale changes),
	-- clamped to the slider's own min/max. width: forced button width -
	-- "++"/"--" need more room than "+"/"-" to render centered rather
	-- than clipped/overflowing a width sized for a single character.
	local function MakeStepButton(name, label, pixels, width)
		local button = CreateFrame("Button", namePrefix .. name .. suffix, page)

		button:SetHeight(20)
		ACAB:StyleModernButton(button, width, width)
		button:SetText(label)

		button:SetScript("OnClick", function()
			local min, max = slider:GetMinMaxValues()
			local target = slider:GetValue() + (pixels * ACAB:GetPixelStep())

			if target < min then
				target = min
			elseif target > max then
				target = max
			end

			ACAB:SetSliderValueUnsnapped(slider, target)
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

-- Bumped on every call so each EditBox gets a unique frame name.
local positionEditBoxCounter = 0

-- Turns `valueText` into a click-to-edit control: an invisible click-
-- catcher Button overlays the FontString (which can't receive clicks
-- itself) and swaps in an EditBox on click. Enter applies the typed value
-- (clamped to the slider's min/max), Escape/focus-loss cancels. Returns
-- the click-catcher (for lock-gating) and the EditBox.
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

	-- The next axis's slider sits close below this readout and defaults to
	-- the same frame level (both are plain children of `page`) - without
	-- outranking it explicitly, that neighboring slider's hit region can
	-- win the mouse hit-test over this one whenever they're close enough
	-- to overlap, silently swallowing clicks meant for this button.
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
			local min, max = slider:GetMinMaxValues()

			if parsed < min then
				parsed = min
			elseif parsed > max then
				parsed = max
			end

			ACAB:SetSliderValueUnsnapped(slider, parsed)
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
-- ACAB:CreatePositionAxisSlider
--
-- One X or Y position-slider column (slider, end labels, steppers,
-- click-to-edit readout). Stores each widget onto page[axisKey.."Slider"/
-- "ValueText"/"StepperBigMinus"/...] for RefreshBarSettingsPage/
-- RefreshSimpleBarPage/RefreshPositionSliderRange to read.
--
-- config = { axisKey = "x"|"y", namePrefix, anchor = {point, relativeTo,
--   relativePoint, x, y}, min, max, lowText, highText,
--   onApply = function(appliedValue) end }
-- Also registers with ACAB:AddHoverOnlyReflowRow. Returns the slider.
-------------------------------------------------------------------------

function ACAB:CreatePositionAxisSlider(page, config)
	local axisKey = config.axisKey
	local axisSuffix = (axisKey == "x") and "X" or "Y"

	local slider = ACAB:CreateSettingSlider(page, config.namePrefix .. axisSuffix .. "Slider", 290)

	slider:SetPoint(unpack(config.anchor))
	slider:SetMinMaxValues(config.min, config.max)

	-- Continuous, not stepped - see GetPixelStep/RoundToStep's own comment above.
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

		-- Only a real mouse drag reaches this un-snapped - every
		-- stepper/edit-box commit sets suppressSnap around its own
		-- SetValue() so its exact value passes through untouched.
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
-- ACAB:CreateLabeledSlider
--
-- One title-less slider + centered live-value readout, for non-position
-- sliders (Button Size, Spacing, Scale, font-size, etc). Caller owns the
-- section title above it.
--
-- config = { width (default 300), anchor = {point, relativeTo,
--   relativePoint, x, y} (required), min, max, step (default 0),
--   lowText, highText, initialText (default ""),
--   round = function(value) end, format = function(value) end,
--   onChange = function(value, suppressApply) end }
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
-- ACAB:CreateLabeledCheckbox
--
-- UICheckButtonTemplate CheckButton with label/anchor/OnClick/tooltip
-- wired from `config`, for on/off toggles across the settings window.
--
-- config = { width (24), height (24), anchor = {point, relativeTo,
--   relativePoint, x, y} (required), label, onClick = function() end,
--   tooltip = { title, lines = {...} },
--   lockedText (single red line shown instead of `tooltip` whenever the
--   checkbox's own .ACABLocked field is true - see
--   ACAB:LockControlKeepingTooltip, Settings.lua) }
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

		-- The engine already flips this CheckButton's own checked state
		-- before OnClick fires - while ACABLocked (ACAB:LockControlKeepingTooltip),
		-- revert that flip and never call through to `onClick`, instead of
		-- the usual :Disable() (confirmed live on this client to also
		-- swallow OnEnter/OnLeave, killing the locked-reason tooltip).
		checkbox:SetScript("OnClick", function()
			if this.ACABLocked then
				this:SetChecked(not this:GetChecked())
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

		-- checkbox.ACABLocked is read live (not captured here) - a caller
		-- like ACAB:LockControlKeepingTooltip stamps it whenever the lock
		-- state changes, so this always shows the CURRENT reason without
		-- needing to re-wire the tooltip script on every refresh.
		checkbox:SetScript("OnEnter", function()
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")

			if this.ACABLocked and lockedText then
				GameTooltip:SetText(lockedText, 1, 0.15, 0.15, 1, true)
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
-- ACAB:CreateResetButton
--
-- StyleModernButton-styled "Reset ..." button. Caller positions it via
-- config.anchor.
--
-- config = { text ("Reset"), height (22), minWidth (90), maxWidth (90),
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
-- ACABDialogMixin
--
-- Reusable dialog frame: mode = "confirm" (title/message + buttons),
-- "textinput" (adds EditBox), "dropdown" (adds inline dropdown), or
-- "textarea" (scrollable multi-line EditBox). One frame instance is
-- created lazily (ACAB.activeDialog) and reconfigured per ACAB:ShowDialog
-- call; only one dialog is ever open at a time.
-------------------------------------------------------------------------

ACABDialogMixin = {}

local DIALOG_WIDTH = 360
local DIALOG_BUTTON_HEIGHT = 22
local DIALOG_BUTTON_MIN_WIDTH = 100
local DIALOG_TEXTAREA_HEIGHT = 160
local DIALOG_ERROR_BANNER_HEIGHT = 54
local DIALOG_TEXTAREA_SCROLLBAR_RESERVE = 28
-- Fixed scroll-child height rather than measuring wrapped line count -
-- covers any export size, at the cost of the scrollbar thumb not
-- reflecting short texts proportionally.
local DIALOG_TEXTAREA_CONTENT_HEIGHT = 4000

-- Creates the scrollable multi-line EditBox backing mode == "textarea"
-- (profile export/import). Built once and reused, same as the dialog
-- frame itself - see EnsureDialogFrame's own header comment.
local function CreateDialogTextArea(dialog)
	local scrollFrame = ACAB:CreateScrollFrame(dialog, "ACABDialogTextAreaScrollFrame")

	scrollFrame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	scrollFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)

	local editBox = CreateFrame("EditBox", "ACABDialogTextAreaEditBox", scrollFrame)

	editBox:SetMultiLine(true)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject(ChatFontNormal)
	editBox:SetMaxLetters(0)
	-- No template (unlike InputBoxTemplate) means no built-in text padding -
	-- without this the text starts flush at the scroll child's raw left
	-- edge, underneath the scrollFrame backdrop's own left border inset.
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
	-- FULLSCREEN_DIALOG: renders above Settings.lua's DIALOG-strata window.
	self:SetFrameStrata("FULLSCREEN_DIALOG")
	self:SetWidth(DIALOG_WIDTH)
	self:SetHeight(160)
	self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

	-- Matches CreateSettingsFrame's own backdrop (Settings.lua).
	self:SetBackdrop({
		bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = { left = 11, right = 12, top = 12, bottom = 11 },
	})

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

	-- Optional red warning line (e.g. profile import's override warning),
	-- shown only when config.warningText is set.
	self.warningText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.warningText:SetWidth(DIALOG_WIDTH - 40)
	self.warningText:SetJustifyH("CENTER")
	self.warningText:SetTextColor(1, 0.15, 0.15)
	self.warningText:Hide()

	self.textArea = CreateDialogTextArea(self)
	self.textArea:Hide()

	-- Inline validation-error banner - same red backdrop treatment as
	-- Settings.lua's profile-lock banner (ACAB:CreateProfileLockWarning).
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

	-- InputBoxTemplate: standard vanilla FrameXML EditBox. Created hidden;
	-- shown only for mode == "textinput".
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

	-- Up to 4 buttons - the first-login dialog needs 3 plus a conditional
	-- 4th ("use existing profile").
	self.buttons = {}

	local i

	for i = 1, 4 do
		local button = CreateFrame("Button", nil, self)

		button:SetHeight(DIALOG_BUTTON_HEIGHT)

		-- minWidth avoids short labels looking like a tiny nub; maxWidth
		-- matches the dialog's usable text width.
		ACAB:StyleModernButton(button, DIALOG_BUTTON_MIN_WIDTH, DIALOG_WIDTH - 40)
		button:Hide()

		self.buttons[i] = button
	end

	self:Hide()
end

-- config = {
--   title, message, mode = "confirm"|"textinput"|"dropdown"|"textarea",
--   defaultText,       -- textinput/textarea starting value
--   options = {...},   -- dropdown selectable values
--   warningText,       -- optional red line under the message
--   reserveErrorBanner = true,  -- reserves space for :ShowInlineError
--   liveValidate = function(value) return ok, errorMessage end, -- textarea only
--   buttons = { { text, isDefault, danger, keepOpen,
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

		-- Sets up the scrollbar's range/visibility (ACAB:UpdateScrollFrame,
		-- Settings.lua) - it also resets the scroll child's width to the
		-- scrollFrame's own, so the EditBox is narrowed back down after.
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

	-- Buttons wrap into as many centered rows as needed, each row centered
	-- on the dialog's own horizontal center.
	local BUTTON_GAP_X = 12
	local BUTTON_ROW_GAP_Y = 8
	local availableWidth = DIALOG_WIDTH - 40

	local i
	local count = table.getn(self.buttonConfigs)
	self.defaultButtonIndex = nil

	-- Pass 1: configure each visible button so its content-fit width
	-- (ACAB:StyleModernButton's SetText override) is known before
	-- row-packing below.
	for i = 1, 4 do
		local button = self.buttons[i]
		local buttonConfig = self.buttonConfigs[i]

		if buttonConfig then
			button:SetText(buttonConfig.text or "")

			-- Buttons are reused across dialogs (self.buttons is a fixed
			-- pool), so a non-danger button must reset its color here or
			-- it can inherit red from a previous dialog's danger button.
			if buttonConfig.danger then
				ACAB:ApplyDangerButtonHighlight(button)
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

				if buttonConfig.keepOpen then
					if buttonConfig.onClick then
						buttonConfig.onClick(value)
					end

					return
				end

				ACAB.activeDialog:Hide()

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

	-- Pass 2: greedily wrap buttons 1..count into rows - rows[r] is an
	-- array of button indices, rowWidths[r] that row's total width.
	local rows = {}
	local rowWidths = {}
	local rowCount = 0

	for i = 1, count do
		local button = self.buttons[i]
		local width = button:GetWidth()
		local addWidth = width

		if rowCount > 0 and table.getn(rows[rowCount]) > 0 then
			addWidth = BUTTON_GAP_X + width

			if (rowWidths[rowCount] + addWidth) > availableWidth then
				rowCount = rowCount + 1
				rows[rowCount] = {}
				rowWidths[rowCount] = 0
				addWidth = width
			end
		else
			rowCount = rowCount + 1
			rows[rowCount] = {}
			rowWidths[rowCount] = 0
		end

		table.insert(rows[rowCount], i)
		rowWidths[rowCount] = rowWidths[rowCount] + addWidth
	end

	-- Each row is anchored off self's own TOP with a precomputed offset,
	-- independent of vertical stacking order.
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

		rowY = rowY + DIALOG_BUTTON_HEIGHT
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

-- Shows the reserved inline red error banner (config.reserveErrorBanner)
-- with `message`. No-op if the current dialog didn't reserve one.
function ACABDialogMixin:ShowInlineError(message)
	if not self.hasErrorBannerSlot then
		return
	end

	self.errorBanner.text:SetText(message or "")
	self.errorBanner:Show()
end

-- Invokes the default button's own OnClick handler directly rather than
-- via :Click().
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

-- Named Display, not Show - Mixin() copies this directly onto the frame's
-- table, which would shadow the native :Show() and make it unreachable if
-- this were named Show.
function ACABDialogMixin:Display()
	self:Show()

	if self.mode == "textinput" then
		self.editBox:SetFocus()
	elseif self.mode == "textarea" then
		self.textArea.editBox:SetFocus()
	end
end

-- The one entry point every caller uses for every dialog need. Reuses the
-- lazily-created dialog frame (EnsureDialogFrame above).
function ACAB:ShowDialog(config)
	local dialog = EnsureDialogFrame()

	dialog:Init(config)
	dialog:Display()

	return dialog
end

-------------------------------------------------------------------------
-- ACABFadeStripMixin / ACAB:CreateFadeStrip
--
-- Horizontal fade highlight. Textures are owned directly by `parent`
-- (not a child frame) and drawn on ARTWORK, so they render behind
-- `parent`'s own OVERLAY text - draw order between different frames is by
-- frame level, not layer, so a child frame's ARTWORK would still cover it.
--
-- Two shapes via options.inverted: normal (default) fades transparent ->
-- solid -> transparent (3 textures); inverted fades solid -> transparent
-- -> solid (4 textures, since SetGradientAlpha only does 2-stop gradients).
-- options.edgeFraction: each edge's share of total width (default 0.1).
-------------------------------------------------------------------------

ACABFadeStripMixin = {}

-- parent: frame to own the strip's textures. width/height: the strip's
-- initial pixel size (see :SetStripWidth to resize later without
-- recreating textures).
function ACAB:CreateFadeStrip(parent, width, height, options)
	options = options or {}

	local strip = {}

	Mixin(strip, ACABFadeStripMixin)

	strip.r, strip.g, strip.b = 1, 1, 1
	strip.peakAlpha = 1
	strip.height = height or 0
	strip.edgeFraction = options.edgeFraction or 0.1
	strip.inverted = options.inverted and true or false

	strip.leftTex = parent:CreateTexture(nil, "ARTWORK")
	strip.leftTex:SetTexture("Interface\\Buttons\\WHITE8X8")

	strip.midTex = parent:CreateTexture(nil, "ARTWORK")
	strip.midTex:SetTexture("Interface\\Buttons\\WHITE8X8")

	strip.rightTex = parent:CreateTexture(nil, "ARTWORK")
	strip.rightTex:SetTexture("Interface\\Buttons\\WHITE8X8")

	if strip.inverted then
		strip.midRightTex = parent:CreateTexture(nil, "ARTWORK")
		strip.midRightTex:SetTexture("Interface\\Buttons\\WHITE8X8")
	end

	strip:SetStripWidth(width)
	strip:ApplyFadeColors()

	return strip
end

-- strip isn't a real Frame/Region (its textures are owned by `parent`
-- instead), so SetPoint/ClearAllPoints/Show/Hide/IsShown are reimplemented
-- here rather than inherited - all operate on leftTex, whose own anchor is
-- what every other texture in the strip chains off of.
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

-- Recomputes the texture split for the strip's current width - kept
-- separate from color/alpha updates so ACABListRowMixin:SetVisualWidth can
-- resize an already-colored strip without touching its color.
function ACABFadeStripMixin:SetStripWidth(width)
	self.width = width

	local height = self.height or 0
	local edgeWidth = width * self.edgeFraction

	self.leftTex:SetWidth(edgeWidth)
	self.leftTex:SetHeight(height)

	if self.inverted then
		local midWidth = (width - (edgeWidth * 2)) / 2

		self.midTex:ClearAllPoints()
		self.midTex:SetPoint("TOPLEFT", self.leftTex, "TOPRIGHT", 0, 0)
		self.midTex:SetWidth(midWidth)
		self.midTex:SetHeight(height)

		self.midRightTex:ClearAllPoints()
		self.midRightTex:SetPoint("TOPLEFT", self.midTex, "TOPRIGHT", 0, 0)
		self.midRightTex:SetWidth(midWidth)
		self.midRightTex:SetHeight(height)

		self.rightTex:ClearAllPoints()
		self.rightTex:SetPoint("TOPLEFT", self.midRightTex, "TOPRIGHT", 0, 0)
		self.rightTex:SetWidth(edgeWidth)
		self.rightTex:SetHeight(height)
	else
		local midWidth = width - (edgeWidth * 2)

		self.midTex:ClearAllPoints()
		self.midTex:SetPoint("TOPLEFT", self.leftTex, "TOPRIGHT", 0, 0)
		self.midTex:SetWidth(midWidth)
		self.midTex:SetHeight(height)

		self.rightTex:ClearAllPoints()
		self.rightTex:SetPoint("TOPLEFT", self.midTex, "TOPRIGHT", 0, 0)
		self.rightTex:SetWidth(edgeWidth)
		self.rightTex:SetHeight(height)
	end
end

-- Resizes just the height - SetStripWidth recomputes height too, but
-- nothing re-runs it when only the strip's height changes.
function ACABFadeStripMixin:SetStripHeight(height)
	self.height = height

	self.leftTex:SetHeight(height)
	self.midTex:SetHeight(height)
	self.rightTex:SetHeight(height)

	if self.midRightTex then
		self.midRightTex:SetHeight(height)
	end
end

-- Re-runs the gradient/solid-color calls with the current r/g/b/peakAlpha -
-- shared by SetFadeColor and SetPeakAlpha so each only has to update the
-- one field it owns before calling this.
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

-- Gives a ACAB:StyleModernButton-styled button a plain solid red "danger"
-- background (destructive actions, e.g. Delete Profile) - just a flat
-- backdrop color swap; StyleModernButton's own gold hover-border behavior
-- is left untouched.
local DANGER_COLOR = { 0.6, 0.08, 0.08 }

function ACAB:ApplyDangerButtonHighlight(button)
	button:SetBackdropColor(DANGER_COLOR[1], DANGER_COLOR[2], DANGER_COLOR[3], 0.9)
end

-------------------------------------------------------------------------
-- ACABListRowMixin
--
-- Generic list-row widget: two ACABFadeStripMixin layers (selectStrip,
-- hoverStrip) for rest/hover/selected/selected+hover/disabled states.
-- Disabled always wins - hides both strips and blocks onClick.
-------------------------------------------------------------------------

ACABListRowMixin = {}

-- parent: frame to anchor into. name: optional.
function ACAB:CreateListRow(parent, name)
	local row = CreateFrame("Button", name, parent)

	-- Must capture BEFORE Mixin below overwrites row.SetWidth/SetHeight
	-- with ACABListRowMixin's own overrides - capturing after Mixin grabs
	-- the mixin's own override instead of the native method, causing
	-- infinite recursion the moment SetWidth/SetHeight is called.
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

	-- Created after selectStrip so it draws on top when both are shown.
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

function ACABListRowMixin:IsRowSelected()
	return self.isSelected
end

-- Disabled overrides hover/selected visuals and blocks onClick; OnEnter/
-- OnLeave still fire so a disabled row can still show a tooltip.
function ACABListRowMixin:SetDisabled(disabled)
	self.isDisabled = disabled and true or false
	self:UpdateVisualState()
end

-- Resizes/repositions only the fade strips, not the row's own hit-box -
-- lets the highlight extend across a sibling checkbox or align to a wider
-- container without changing what area responds to clicks. offsetX
-- shifts both strips' LEFT anchor relative to the row.
function ACABListRowMixin:SetVisualWidth(width, offsetX)
	offsetX = offsetX or 0

	self.selectStrip:ClearAllPoints()
	self.selectStrip:SetPoint("LEFT", self, "LEFT", offsetX, 0)
	self.selectStrip:SetStripWidth(width)

	self.hoverStrip:ClearAllPoints()
	self.hoverStrip:SetPoint("LEFT", self, "LEFT", offsetX, 0)
	self.hoverStrip:SetStripWidth(width)
end

-- Overrides the native Button:SetWidth (captured as self.nativeSetWidth in
-- ACAB:CreateListRow) so a row with no inline checkbox keeps its strips
-- sized to match without a separate SetVisualWidth call.
function ACABListRowMixin:SetWidth(width)
	self.nativeSetWidth(self, width)

	if self.selectStrip then
		self.selectStrip:SetStripWidth(width)
		self.hoverStrip:SetStripWidth(width)
	end
end

-- Same technique as SetWidth, for height - without this the strips stay
-- stuck at whatever height OnLoad captured (typically 0, since OnLoad
-- runs before the caller ever calls SetHeight), rendering invisible.
function ACABListRowMixin:SetHeight(height)
	self.nativeSetHeight(self, height)

	if self.selectStrip then
		self.selectStrip:SetStripHeight(height)
		self.hoverStrip:SetStripHeight(height)
	end
end

-- Factored out of OnEnter/OnLeave (see OnLoad) so another frame - e.g. a
-- sibling checkbox sharing this row's hover fade - can call it directly
-- without needing `this` to be the row itself.
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
