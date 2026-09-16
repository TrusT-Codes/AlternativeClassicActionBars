-- SetupWizard.lua
-- 4-step first-custom-profile setup wizard (ACAB:ShowSetupWizard), launched
-- from Database.lua's ShowFirstLoginDialog "Set up a new custom Profile"
-- button, or - in overwrite mode - from the Profiles settings page's "Run
-- Setup Wizard" button (SettingsGeneral.lua), which reconfigures the
-- already-active profile in place instead of creating a new one and skips
-- the name step. One lazily-created frame instance is reused across opens
-- (EnsureSetupWizardFrame, same pattern as UIWidgets.lua's EnsureDialogFrame).
-- Nothing is written to ACABProfilesDB/ACABDB until FinishWizard runs -
-- closing the wizard early (Cancel/X) leaves self.wizardState discarded and
-- creates no orphan profile / changes nothing on an existing one.
--
-- Engine-invoked script handlers (OnClick, OnEnterPressed, ...) receive the
-- frame via the global `this`, never as a `self` parameter.

local ACAB = AlternativeClassicActionBars

local WIZARD_WIDTH = 480
local WIZARD_CONTENT_WIDTH = WIZARD_WIDTH - 40
local PREVIEW_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local PREVIEW_SLOT_COUNT = 5

-------------------------------------------------------------------------
-- Cosmetic (non-interactive) preview bars used by steps 3 and 4 - built
-- per the vanilla/modern button skin recipe from Button.lua's Init.
-------------------------------------------------------------------------

local function ComputePreviewBarWidth(buttonSize, spacing, count)
	return (buttonSize * count) + (spacing * (count - 1))
end

-- One cosmetic slot: vanilla style overlays Interface\Buttons\UI-Quickslot2
-- centered with a (0,-1) offset over a flush icon; modern style backdrops a
-- tooltip-skinned border with a 2px-inset icon.
local function CreateWizardPreviewSlot(parent, isModern)
	local slot = CreateFrame("Frame", nil, parent)

	local icon = slot:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(PREVIEW_ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	if isModern then
		slot:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 8,
			edgeSize = 8,
			insets = { left = 1, right = 1, top = 1, bottom = 1 },
		})
		slot:SetBackdropColor(0, 0, 0, 1)
		slot:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)

		icon:SetPoint("TOPLEFT", slot, "TOPLEFT", 2, -2)
		icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 2)
	else
		icon:SetAllPoints(slot)

		local border = slot:CreateTexture(nil, "OVERLAY")
		border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
		border:SetPoint("CENTER", slot, "CENTER", 0, -1)
		slot.border = border
	end

	slot.icon = icon

	return slot
end

-- Resizes/repositions slots already created by CreateWizardPreviewBar in
-- place, without recreating any texture - used by step 4's live slider
-- updates. slots.container is the bar's own container frame.
local function LayoutWizardPreviewSlots(slots, buttonSize, spacing)
	local i

	for i = 1, table.getn(slots) do
		local slot = slots[i]

		slot:SetWidth(buttonSize)
		slot:SetHeight(buttonSize)

		if slot.border then
			slot.border:SetWidth(buttonSize)
			slot.border:SetHeight(buttonSize)
		end

		slot:ClearAllPoints()

		if i == 1 then
			slot:SetPoint("LEFT", slots.container, "LEFT", 0, 0)
		else
			slot:SetPoint("LEFT", slots[i - 1], "RIGHT", spacing, 0)
		end
	end
end

-- Builds a PREVIEW_SLOT_COUNT-wide preview bar as a child of `parent`.
-- Returns the container frame (caller anchors it) and the slots array.
local function CreateWizardPreviewBar(parent, isModern, count, buttonSize, spacing)
	local container = CreateFrame("Frame", nil, parent)
	container:SetHeight(buttonSize)
	container:SetWidth(ComputePreviewBarWidth(buttonSize, spacing, count))

	local slots = {}
	slots.container = container

	local i

	for i = 1, count do
		slots[i] = CreateWizardPreviewSlot(container, isModern)
	end

	LayoutWizardPreviewSlots(slots, buttonSize, spacing)

	return container, slots
end

-------------------------------------------------------------------------
-- ACABSetupWizardMixin
-------------------------------------------------------------------------

ACABSetupWizardMixin = {}

local STEP_TITLES = {
	[1] = "Name Your Profile",
	[2] = "Force Default Blizzard Layout",
	[3] = "Button Style",
	[4] = "Spacing & Button Size",
}

-- Fixed per-step frame height (simpler and more predictable than measuring
-- wrapped-text/reveal-state rects live) - tall enough for that step's worst
-- case (step 4 with both sliders revealed).
local STEP_HEIGHTS = {
	[1] = 230,
	[2] = 320,
	[3] = 300,
	[4] = 500,
}

function ACABSetupWizardMixin:BuildStep1()
	local step = CreateFrame("Frame", nil, self)
	step:SetWidth(WIZARD_CONTENT_WIDTH)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText(
		"This creates your own custom profile, separate from the locked " ..
		"Default profile. Give it a name - you can rename it or add more " ..
		"profiles later from the Profiles tab."
	)

	local editBox = CreateFrame("EditBox", "ACABSetupWizardNameEditBox", step, "InputBoxTemplate")
	editBox:SetWidth(280)
	editBox:SetHeight(20)
	editBox:SetAutoFocus(false)
	editBox:SetPoint("TOP", message, "BOTTOM", 0, -30)
	editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	editBox:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		ACAB.setupWizard:AdvanceFromStep1()
	end)

	local errorText = step:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	errorText:SetPoint("TOP", editBox, "BOTTOM", 0, -12)
	errorText:SetWidth(WIZARD_CONTENT_WIDTH)
	errorText:SetJustifyH("CENTER")
	errorText:SetTextColor(1, 0.15, 0.15)
	errorText:Hide()

	local nextButton = CreateFrame("Button", nil, step)
	nextButton:SetHeight(24)
	ACAB:StyleModernButton(nextButton, 120, 120)
	nextButton:SetText("Next")
	nextButton:SetPoint("TOP", errorText, "BOTTOM", 0, -18)
	nextButton:SetScript("OnClick", function()
		ACAB.setupWizard:AdvanceFromStep1()
	end)

	step.editBox = editBox
	step.errorText = errorText

	return step
end

function ACABSetupWizardMixin:BuildStep2()
	local step = CreateFrame("Frame", nil, self)
	step:SetWidth(WIZARD_CONTENT_WIDTH)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetHeight(150)
	message:SetJustifyH("CENTER")
	message:SetText(
		"\"Force default Blizzard layout mode\" decides whether ACAB " ..
		"positions and styles the real Blizzard action bars in place, or " ..
		"switches them to ACAB's own custom bar and styling system.\n\n" ..
		"When enabled, default action bars keep Blizzard's native " ..
		"position, size, and layout, and can only be shown/hidden - " ..
		"dragging and resizing them is disabled.\n\n" ..
		"Disable this to freely reposition, resize, and re-skin bars like " ..
		"custom bars, and to unlock button style and global spacing/size " ..
		"further in this wizard."
	)

	local enableButton = CreateFrame("Button", nil, step)
	enableButton:SetHeight(34)
	ACAB:StyleModernButton(enableButton, 180, 180)
	enableButton:SetText("Enable")
	enableButton:SetPoint("TOP", message, "BOTTOM", -100, -20)
	enableButton:SetScript("OnClick", function()
		ACAB.setupWizard.wizardState.useDefaultLayout = true
		ACAB.setupWizard:FinishWizard()
	end)

	local disableButton = CreateFrame("Button", nil, step)
	disableButton:SetHeight(34)
	ACAB:StyleModernButton(disableButton, 180, 180)
	disableButton:SetText("Disable")
	disableButton:SetPoint("TOP", message, "BOTTOM", 100, -20)
	disableButton:SetScript("OnClick", function()
		ACAB.setupWizard.wizardState.useDefaultLayout = false
		ACAB.setupWizard:ShowStep(3)
	end)

	return step
end

function ACABSetupWizardMixin:BuildStep3()
	local step = CreateFrame("Frame", nil, self)
	step:SetWidth(WIZARD_CONTENT_WIDTH)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText("Choose a button style for your bars. You can change this later in Settings.")

	local previewSize = 30
	local previewSpacing = 4

	local vanillaLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	vanillaLabel:SetPoint("TOP", message, "BOTTOM", -110, -26)
	vanillaLabel:SetText("Vanilla Style")

	local vanillaBar = CreateWizardPreviewBar(step, false, PREVIEW_SLOT_COUNT, previewSize, previewSpacing)
	vanillaBar:SetPoint("TOP", vanillaLabel, "BOTTOM", 0, -10)

	local selectVanilla = CreateFrame("Button", nil, step)
	selectVanilla:SetHeight(24)
	ACAB:StyleModernButton(selectVanilla, 120, 120)
	selectVanilla:SetText("Select")
	selectVanilla:SetPoint("TOP", vanillaBar, "BOTTOM", 0, -14)
	selectVanilla:SetScript("OnClick", function()
		ACAB.setupWizard.wizardState.modernBorderStyle = false
		ACAB.setupWizard:ShowStep(4)
	end)

	local modernLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	modernLabel:SetPoint("TOP", message, "BOTTOM", 110, -26)
	modernLabel:SetText("Modern Style")

	local modernBar = CreateWizardPreviewBar(step, true, PREVIEW_SLOT_COUNT, previewSize, previewSpacing)
	modernBar:SetPoint("TOP", modernLabel, "BOTTOM", 0, -10)

	local selectModern = CreateFrame("Button", nil, step)
	selectModern:SetHeight(24)
	ACAB:StyleModernButton(selectModern, 120, 120)
	selectModern:SetText("Select")
	selectModern:SetPoint("TOP", modernBar, "BOTTOM", 0, -14)
	selectModern:SetScript("OnClick", function()
		ACAB.setupWizard.wizardState.modernBorderStyle = true
		ACAB.setupWizard:ShowStep(4)
	end)

	return step
end

function ACABSetupWizardMixin:BuildStep4()
	local step = CreateFrame("Frame", nil, self)
	step:SetWidth(WIZARD_CONTENT_WIDTH)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetHeight(44)
	message:SetJustifyH("CENTER")
	message:SetText(
		"Optionally set a spacing and button size used by every bar. " ..
		"Leave either off to size that aspect per-bar instead - you can " ..
		"change both later in Settings."
	)

	-- Reflects the spacing slider at a fixed default button size.
	local spacingLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	spacingLabel:SetPoint("TOP", message, "BOTTOM", 0, -10)
	spacingLabel:SetText("Spacing Preview")

	local spacingBarContainer, spacingBarSlots = CreateWizardPreviewBar(
		step, false, PREVIEW_SLOT_COUNT, ACAB.BUTTON_SIZE, 0
	)
	spacingBarContainer:SetPoint("TOP", spacingLabel, "BOTTOM", 0, -8)

	-- Reflects the button-size slider at a fixed default (no) spacing.
	local sizeLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	sizeLabel:SetPoint("TOP", spacingBarContainer, "BOTTOM", 0, -22)
	sizeLabel:SetText("Button Size Preview")

	local sizeBarContainer, sizeBarSlots = CreateWizardPreviewBar(
		step, false, PREVIEW_SLOT_COUNT, ACAB.BUTTON_SIZE, 0
	)
	sizeBarContainer:SetPoint("TOP", sizeLabel, "BOTTOM", 0, -8)

	step.spacingBarContainer = spacingBarContainer
	step.spacingBarSlots = spacingBarSlots
	step.sizeBarContainer = sizeBarContainer
	step.sizeBarSlots = sizeBarSlots

	local spacingCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSpacingCheckbox", {
		anchor = { "TOP", sizeBarContainer, "BOTTOM", -110, -26 },
		label = "Enable global spacing",
		onClick = function()
			ACAB.setupWizard.wizardState.globalSpacingEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep4SliderVisibility()
		end,
	})

	-- Mirrors SettingsGeneral.lua's own global-spacing slider config
	-- (step = ACAB.SPACING_STEP); the useDefaultLayout-driven display-offset
	-- that slider applies doesn't apply here since the wizard only reaches
	-- this step after useDefaultLayout has already been chosen "Disable".
	local spacingSlider, spacingValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardSpacingSlider", {
		anchor = { "TOPLEFT", spacingCheckbox, "BOTTOMLEFT", 20, -14 },
		width = 180,
		min = 0,
		max = ACAB.SPACING_MAX,
		step = ACAB.SPACING_STEP,
		initialText = "0",
		round = function(value) return math.floor(value + 0.5) end,
		format = tostring,
		onChange = function(value, suppressApply)
			if not suppressApply then
				ACAB.setupWizard.wizardState.globalSpacingValue = value
				ACAB.setupWizard:ReflowStep4Preview("spacing")
			end
		end,
	})
	spacingSlider:Hide()
	spacingValueText:Hide()

	local sizeCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSizeCheckbox", {
		anchor = { "TOP", sizeBarContainer, "BOTTOM", 110, -26 },
		label = "Enable global button size",
		onClick = function()
			ACAB.setupWizard.wizardState.globalButtonSizeEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep4SliderVisibility()
		end,
	})

	-- Mirrors SettingsGeneral.lua's own global-button-size slider config.
	local sizeSlider, sizeValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardSizeSlider", {
		anchor = { "TOPLEFT", sizeCheckbox, "BOTTOMLEFT", 20, -14 },
		width = 180,
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
				ACAB.setupWizard.wizardState.globalButtonSizeValue = value
				ACAB.setupWizard:ReflowStep4Preview("size")
			end
		end,
	})
	sizeSlider:Hide()
	sizeValueText:Hide()

	step.spacingCheckbox = spacingCheckbox
	step.spacingSlider = spacingSlider
	step.spacingValueText = spacingValueText
	step.sizeCheckbox = sizeCheckbox
	step.sizeSlider = sizeSlider
	step.sizeValueText = sizeValueText

	local finishButton = CreateFrame("Button", nil, step)
	finishButton:SetHeight(28)
	ACAB:StyleModernButton(finishButton, 140, 140)
	finishButton:SetText("Finish")
	finishButton:SetPoint("TOP", sizeSlider, "BOTTOM", 0, -34)
	finishButton:SetScript("OnClick", function()
		ACAB.setupWizard:FinishWizard()
	end)

	step.finishButton = finishButton

	return step
end

function ACABSetupWizardMixin:OnLoad()
	-- FULLSCREEN_DIALOG: same strata as ACABDialogMixin, above the settings
	-- window and any other addon UI.
	self:SetFrameStrata("FULLSCREEN_DIALOG")
	self:SetWidth(WIZARD_WIDTH)
	self:SetHeight(STEP_HEIGHTS[1])
	self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

	-- Matches ACABDialogMixin/Settings.lua's own window backdrop.
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
	self.titleText:SetPoint("TOP", self, "TOP", 0, -16)
	self.titleText:SetText("Set Up Your Profile")

	self.stepText = self:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	self.stepText:SetPoint("TOP", self.titleText, "BOTTOM", 0, -4)
	self.stepText:SetTextColor(0.7, 0.7, 0.7)

	local closeButton = CreateFrame("Button", "ACABSetupWizardCloseButton", self, "UIPanelCloseButton")
	closeButton:SetPoint("TOPRIGHT", self, "TOPRIGHT", -4, -4)
	closeButton:SetScript("OnClick", function()
		ACAB.setupWizard:Hide()
	end)

	-- Always-visible cancel affordance - closing here discards wizardState,
	-- no profile is created.
	self.cancelButton = CreateFrame("Button", nil, self)
	self.cancelButton:SetHeight(22)
	ACAB:StyleModernButton(self.cancelButton, 90, 90)
	self.cancelButton:SetText("Cancel")
	self.cancelButton:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 20, 16)
	self.cancelButton:SetScript("OnClick", function()
		ACAB.setupWizard:Hide()
	end)

	self.steps = {
		self:BuildStep1(),
		self:BuildStep2(),
		self:BuildStep3(),
		self:BuildStep4(),
	}

	local i

	for i = 1, table.getn(self.steps) do
		self.steps[i]:Hide()
	end

	self:Hide()
end

-- Resets all transient wizard state/widgets to their starting point - run
-- once per ACAB:ShowSetupWizard open, so a previous partial run (closed via
-- Cancel/X) never leaks into the next.
--
-- config.overwriteExisting: reconfigures the given (already-active)
-- config.profileName in place instead of creating a new profile - used by
-- the Profiles settings page's "Run Setup Wizard" button. Skips step 1
-- (the name is fixed to the current profile, not chosen).
function ACABSetupWizardMixin:Reset(config)
	config = config or {}

	local overwriteExisting = config.overwriteExisting and true or false
	local profileName = overwriteExisting
		and (config.profileName or (ACABCharDB and ACABCharDB.activeProfile) or ACAB.DEFAULT_PROFILE_NAME)
		or ((UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown"))

	self.wizardState = {
		overwriteExisting = overwriteExisting,
		profileName = profileName,
		useDefaultLayout = nil,
		modernBorderStyle = nil,
		globalSpacingEnabled = false,
		globalSpacingValue = 0,
		globalButtonSizeEnabled = false,
		globalButtonSizeValue = ACAB.BUTTON_SIZE,
	}

	self.titleText:SetText(overwriteExisting and "Reconfigure Your Profile" or "Set Up Your Profile")

	local step1 = self.steps[1]
	step1.editBox:SetText(self.wizardState.profileName)
	step1.errorText:Hide()

	local step4 = self.steps[4]
	step4.spacingCheckbox:SetChecked(false)
	step4.sizeCheckbox:SetChecked(false)

	step4.spacingSlider.suppressApply = true
	step4.spacingSlider:SetValue(0)
	step4.spacingSlider.suppressApply = nil

	step4.sizeSlider.suppressApply = true
	step4.sizeSlider:SetValue(ACAB.BUTTON_SIZE)
	step4.sizeSlider.suppressApply = nil

	self:UpdateStep4SliderVisibility()
end

function ACABSetupWizardMixin:ShowStep(n)
	local i

	for i = 1, table.getn(self.steps) do
		self.steps[i]:Hide()
	end

	self.currentStep = n

	-- Overwrite mode skips step 1 (name is fixed to the current profile),
	-- so the displayed count is renumbered to "of 3" starting at 1 instead
	-- of showing a step 1 the user never saw.
	local totalSteps = self.wizardState.overwriteExisting and 3 or 4
	local displayStep = self.wizardState.overwriteExisting and (n - 1) or n

	self.stepText:SetText("Step " .. tostring(displayStep) .. " of " .. tostring(totalSteps) .. " - " .. (STEP_TITLES[n] or ""))
	self:SetHeight(STEP_HEIGHTS[n] or STEP_HEIGHTS[1])

	local step = self.steps[n]

	step:ClearAllPoints()
	step:SetPoint("TOP", self.stepText, "BOTTOM", 0, -20)
	step:Show()

	if n == 1 then
		step.editBox:SetFocus()
		step.editBox:HighlightText()
	end
end

-- Validates step 1's profile-name entry and advances to step 2 - reused by
-- both the Next button and the edit box's OnEnterPressed.
function ACABSetupWizardMixin:AdvanceFromStep1()
	local step = self.steps[1]
	local name = step.editBox:GetText()

	if not name or name == "" then
		step.errorText:SetText("Profile name cannot be empty.")
		step.errorText:Show()
		return
	end

	if ACABProfilesDB and ACABProfilesDB[name] then
		step.errorText:SetText("A profile named \"" .. name .. "\" already exists.")
		step.errorText:Show()
		return
	end

	step.errorText:Hide()
	self.wizardState.profileName = name

	self:ShowStep(2)
end

function ACABSetupWizardMixin:UpdateStep4SliderVisibility()
	local step = self.steps[4]
	local state = self.wizardState

	step.spacingSlider:SetShown(state.globalSpacingEnabled and true or false)
	step.spacingValueText:SetShown(state.globalSpacingEnabled and true or false)

	step.sizeSlider:SetShown(state.globalButtonSizeEnabled and true or false)
	step.sizeValueText:SetShown(state.globalButtonSizeEnabled and true or false)

	self:ReflowStep4Preview("spacing")
	self:ReflowStep4Preview("size")
end

-- which: "spacing" or "size" - only that preview bar's slot layout is
-- recomputed, the other stays at its own fixed default.
function ACABSetupWizardMixin:ReflowStep4Preview(which)
	local step = self.steps[4]
	local state = self.wizardState

	if which == "spacing" then
		local spacing = (state.globalSpacingEnabled and state.globalSpacingValue) or 0

		LayoutWizardPreviewSlots(step.spacingBarSlots, ACAB.BUTTON_SIZE, spacing)
		step.spacingBarContainer:SetWidth(
			ComputePreviewBarWidth(ACAB.BUTTON_SIZE, spacing, PREVIEW_SLOT_COUNT)
		)
	else
		local size = (state.globalButtonSizeEnabled and state.globalButtonSizeValue) or ACAB.BUTTON_SIZE

		LayoutWizardPreviewSlots(step.sizeBarSlots, size, 0)
		step.sizeBarContainer:SetHeight(size)
		step.sizeBarContainer:SetWidth(ComputePreviewBarWidth(size, 0, PREVIEW_SLOT_COUNT))
	end
end

-- Applies wizardState.useDefaultLayout/modernBorderStyle/global spacing+size
-- onto `data` - shared by FinishWizard's create and overwrite branches.
local function ApplyWizardStateToProfileData(state, data)
	data.useDefaultLayout = state.useDefaultLayout

	if state.modernBorderStyle ~= nil then
		data.modernBorderStyle = state.modernBorderStyle
	end

	if state.globalSpacingEnabled ~= nil then
		data.globalSpacingEnabled = state.globalSpacingEnabled
		data.globalSpacingValue = state.globalSpacingValue
	end

	if state.globalButtonSizeEnabled ~= nil then
		data.globalButtonSizeEnabled = state.globalButtonSizeEnabled
		data.globalButtonSizeValue = state.globalButtonSizeValue
	end
end

-- Creates the profile from wizardState and switches to it (reloads the UI),
-- or - in overwrite mode (Profiles settings page's "Run Setup Wizard") -
-- applies wizardState directly onto the already-active profile and reloads.
-- On a name race in create mode (e.g. the name got taken between step 1 and
-- here), sends the user back to step 1 with the rejection message shown
-- instead of silently failing.
function ACABSetupWizardMixin:FinishWizard()
	local state = self.wizardState

	if state.overwriteExisting then
		ACABDB = ACABDB or {}
		ApplyWizardStateToProfileData(state, ACABDB)
		ACAB:SaveActiveProfileData()

		-- Reloads the UI - nothing after this point runs.
		ReloadUI()
		return
	end

	local ok, reason = ACAB:CreateProfile(state.profileName)

	if not ok then
		local step1 = self.steps[1]

		step1.errorText:SetText(reason or "Could not create profile.")
		step1.errorText:Show()

		self:ShowStep(1)
		return
	end

	ApplyWizardStateToProfileData(state, ACABProfilesDB[state.profileName])

	-- Reloads the UI - nothing after this point runs.
	ACAB:SwitchProfile(state.profileName)
end

local function EnsureSetupWizardFrame()
	if ACAB.setupWizard then
		return ACAB.setupWizard
	end

	local wizard = CreateFrame("Frame", "ACABSetupWizard", UIParent)

	Mixin(wizard, ACABSetupWizardMixin)
	wizard:OnLoad()

	ACAB.setupWizard = wizard

	return wizard
end

-- The one entry point every caller uses to open the wizard - reuses the
-- lazily-created frame and resets it to a fresh starting state every time.
--
-- config (optional): { overwriteExisting = true, profileName = "..." } -
-- see ACABSetupWizardMixin:Reset. Omit for the normal first-login "create a
-- new profile" flow, which starts at step 1.
function ACAB:ShowSetupWizard(config)
	local wizard = EnsureSetupWizardFrame()

	wizard:Reset(config)
	wizard:Show()
	wizard:ShowStep(wizard.wizardState.overwriteExisting and 2 or 1)

	return wizard
end
