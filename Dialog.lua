-- Dialog.lua
-- ACABDialogMixin and ACAB:ShowDialog: the shared confirm/text-input/dropdown/textarea dialog.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- ACABDialogMixin: one lazily-created dialog (ACAB.activeDialog), reconfigured per ACAB:ShowDialog
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
local DIALOG_ERROR_BANNER_HEIGHT = 78
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

	errorBanner:SetBackdrop(ACAB.BANNER_BACKDROP)
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
		local button = ACAB:CreateModernButton(self, { minWidth = DIALOG_BUTTON_MIN_WIDTH, maxWidth = DIALOG_WIDTH - 40 })

		button:Hide()

		self.buttons[i] = button
	end

	self:Hide()
end

-- Button row packing and dialog padding used by ACABDialogMixin:Init.
local BUTTON_GAP_X = 12
local BUTTON_ROW_GAP_Y = 8
local TOP_OFFSET = 18
local BOTTOM_PADDING = 20

-- Hides every input, then anchors the warning line, the mode's input and the error banner slot.
local function LayoutDialogInputs(dialog, config)
	dialog.editBox:Hide()
	dialog.dropdown:Hide()
	dialog.textArea:Hide()
	dialog.errorBanner:Hide()

	local anchorAbove = dialog.messageText

	if config.warningText then
		dialog.warningText:ClearAllPoints()
		dialog.warningText:SetPoint("TOP", dialog.messageText, "BOTTOM", 0, -8)
		dialog.warningText:SetText(config.warningText)
		dialog.warningText:Show()
		anchorAbove = dialog.warningText
	else
		dialog.warningText:Hide()
	end

	if dialog.mode == "textinput" then
		dialog.editBox:ClearAllPoints()
		dialog.editBox:SetPoint("TOP", anchorAbove, "BOTTOM", 0, -14)
		dialog.editBox:SetText(config.defaultText or "")
		dialog.editBox:HighlightText()
		dialog.editBox:Show()
		anchorAbove = dialog.editBox
	elseif dialog.mode == "dropdown" then
		dialog.dropdown:ClearAllPoints()
		dialog.dropdown:SetPoint("TOP", anchorAbove, "BOTTOM", 0, -10)
		dialog.dropdown:SetOptions(config.options or {})
		dialog.dropdown:SetSelected((config.options or {})[1])
		dialog.dropdown:Show()
		anchorAbove = dialog.dropdown
	elseif dialog.mode == "textarea" then
		dialog.textArea:ClearAllPoints()
		dialog.textArea:SetPoint("TOP", anchorAbove, "BOTTOM", 0, -10)
		dialog.textArea:SetWidth(DIALOG_WIDTH - 80)
		dialog.textArea.editBox:SetText(config.defaultText or "")
		dialog.textArea.editBox:HighlightText()

		-- UpdateScrollFrame resets the EditBox to the scrollFrame's width; narrowed again right after.
		ACAB:UpdateScrollFrame(
			dialog.textArea,
			dialog.textArea.editBox,
			DIALOG_TEXTAREA_CONTENT_HEIGHT,
			DIALOG_TEXTAREA_HEIGHT
		)
		dialog.textArea.editBox:SetWidth(DIALOG_WIDTH - 80 - DIALOG_TEXTAREA_SCROLLBAR_RESERVE)

		dialog.textArea.editBox:SetScript("OnTextChanged", function()
			if not config.liveValidate then return end

			local text = this:GetText()
			if not text or text == "" then
				ACAB.activeDialog.errorBanner:Hide()
				return
			end

			local ok, message, warning = config.liveValidate(text)
			if ok and warning then
				ACAB.activeDialog:ShowInlineError(warning, true)
			elseif ok then
				ACAB.activeDialog.errorBanner:Hide()
			else
				ACAB.activeDialog:ShowInlineError(message)
			end
		end)

		dialog.textArea:Show()
		anchorAbove = dialog.textArea
	end

	if dialog.hasErrorBannerSlot then
		dialog.errorBanner:ClearAllPoints()
		dialog.errorBanner:SetPoint("TOP", anchorAbove, "BOTTOM", 0, -8)
		dialog.errorBanner:SetWidth(DIALOG_WIDTH - 40)
		dialog.errorBanner:SetHeight(DIALOG_ERROR_BANNER_HEIGHT)
		dialog.errorBanner.text:SetWidth(DIALOG_WIDTH - 56)
	end
end

-- Sizes, colors and wires each pooled button from dialog.buttonConfigs; sets dialog.defaultButtonIndex.
local function ConfigureDialogButtons(dialog, count)
	local i

	-- Pass 1: configure each button so its label-fit width is known before row packing.
	for i = 1, 4 do
		local button = dialog.buttons[i]
		local buttonConfig = dialog.buttonConfigs[i]
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
				dialog.defaultButtonIndex = i
			end

			button:Show()
		else
			button:Hide()
		end
	end

	if not dialog.defaultButtonIndex and count > 0 then
		dialog.defaultButtonIndex = 1
	end
end

-- Pass 2: greedily packs the first count buttons into rows. Returns rows (button indices), rowWidths, rowHeights, rowCount.
local function PackDialogButtonRows(dialog, count)
	local availableWidth = DIALOG_WIDTH - 40
	local rows = {}
	local rowWidths = {}
	local rowHeights = {}
	local rowCount = 0
	local i

	for i = 1, count do
		local button = dialog.buttons[i]
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

	return rows, rowWidths, rowHeights, rowCount
end

-- Offset from the dialog's TOP to the bottom of the content above the button rows.
local function GetDialogContentBottom(dialog, config)
	local contentBottomY = TOP_OFFSET
	contentBottomY = contentBottomY + (dialog.titleText:GetHeight() or 0)
	contentBottomY = contentBottomY + 10 + (dialog.messageText:GetHeight() or 0)

	if config.warningText then
		contentBottomY = contentBottomY + 8 + (dialog.warningText:GetHeight() or 0)
	end

	if dialog.mode == "textinput" then
		contentBottomY = contentBottomY + 14 + (dialog.editBox:GetHeight() or 0)
	elseif dialog.mode == "dropdown" then
		contentBottomY = contentBottomY + 10 + (dialog.dropdown:GetHeight() or 0)
	elseif dialog.mode == "textarea" then
		contentBottomY = contentBottomY + 10 + DIALOG_TEXTAREA_HEIGHT
	end

	if dialog.hasErrorBannerSlot then
		contentBottomY = contentBottomY + 8 + DIALOG_ERROR_BANNER_HEIGHT
	end

	return contentBottomY
end

-- Anchors each row centered on the dialog below contentBottomY. Returns the last row's bottom offset.
local function PlaceDialogButtonRows(dialog, rows, rowWidths, rowHeights, rowCount, contentBottomY)
	local rowY = contentBottomY
	local r

	for r = 1, rowCount do
		local rowGap = (r == 1) and 14 or BUTTON_ROW_GAP_Y

		rowY = rowY + rowGap

		local row = rows[r]
		local cursorX = -(rowWidths[r] / 2)
		local j

		for j = 1, table.getn(row) do
			local button = dialog.buttons[row[j]]
			local width = button:GetWidth()
			local centerX = cursorX + (width / 2)

			button:ClearAllPoints()
			button:SetPoint("TOP", dialog, "TOP", centerX, -rowY)

			cursorX = cursorX + width + BUTTON_GAP_X
		end

		rowY = rowY + rowHeights[r]
	end

	return rowY
end

-- config = { title, message, mode = "confirm"|"textinput"|"dropdown"|"textarea", defaultText, options, warningText,
--   reserveErrorBanner, liveValidate(text) (textarea only), buttons = { { text, isDefault, danger, keepOpen,
--   variant = "prominent" (larger, blue)|"minor" (smaller, red), validate(value), onClick(value) }, ... } }
function ACABDialogMixin:Init(config)
	config = config or {}

	self.mode = config.mode or "confirm"
	self.buttonConfigs = config.buttons or {}
	self.hasErrorBannerSlot = config.reserveErrorBanner and true or false

	self.titleText:SetText(config.title or "")
	self.messageText:SetText(config.message or "")

	LayoutDialogInputs(self, config)

	-- Buttons wrap into rows, each row centered on the dialog.
	local count = table.getn(self.buttonConfigs)
	self.defaultButtonIndex = nil

	ConfigureDialogButtons(self, count)

	-- Row anchors are offsets summed from the content above.
	local rows, rowWidths, rowHeights, rowCount = PackDialogButtonRows(self, count)
	local rowY = PlaceDialogButtonRows(self, rows, rowWidths, rowHeights, rowCount, GetDialogContentBottom(self, config))

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

-- Shows message in the reserved error banner (yellow when isWarning); no-op without config.reserveErrorBanner.
function ACABDialogMixin:ShowInlineError(message, isWarning)
	if not self.hasErrorBannerSlot then return end

	if isWarning then
		self.errorBanner.text:SetTextColor(1, 0.82, 0)
	else
		self.errorBanner.text:SetTextColor(1, 0.15, 0.15)
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
