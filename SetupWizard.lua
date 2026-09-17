-- SetupWizard.lua
-- 4-step first-custom-profile setup wizard (ACAB:ShowSetupWizard), launched
-- from Database.lua's ShowFirstLoginDialog "Set up a new custom Profile"
-- button, or - in overwrite mode - from the Profiles settings page's "Run
-- Setup Wizard" button (SettingsGeneral.lua), which reconfigures the
-- already-active profile in place instead of creating a new one and skips
-- the name step. One lazily-created frame instance is reused across opens
-- (EnsureSetupWizardFrame, same pattern as UIWidgets.lua's EnsureDialogFrame).
-- Nothing is written to ACABProfilesDB/ACABDB until FinishWizard runs -
-- closing the wizard early (the X button) leaves self.wizardState
-- discarded and creates no orphan profile / changes nothing on an
-- existing one.
--
-- Engine-invoked script handlers (OnClick, OnEnterPressed, ...) receive the
-- frame via the global `this`, never as a `self` parameter.

local ACAB = AlternativeClassicActionBars

local WIZARD_WIDTH = 480
local WIZARD_CONTENT_WIDTH = WIZARD_WIDTH - 40
local PREVIEW_SLOT_COUNT = 5

-- Real, long-standing ability icon paths (present in the base Blizzard
-- icon atlas since classic, not tied to any one class) - cycled across
-- preview slots instead of every slot showing the same "?" icon. Not
-- pulled from the player's own spellbook: GetSpellTexture's exact
-- index/bookType behavior on this client hasn't been live-verified, and
-- these are purely cosmetic previews, not real spell icons.
local PREVIEW_ICONS = {
	"Interface\\Icons\\Spell_Nature_Lightning",
	"Interface\\Icons\\Ability_Kick",
	"Interface\\Icons\\Spell_Fire_FlameBolt",
	"Interface\\Icons\\Spell_Holy_HolyBolt",
	"Interface\\Icons\\Ability_Warrior_Charge",
	"Interface\\Icons\\Spell_Shadow_ShadowBolt",
	"Interface\\Icons\\Spell_Frost_FrostBolt02",
	"Interface\\Icons\\Ability_Rogue_Ambush",
}

-- 1-based cycle through PREVIEW_ICONS for slot index `n` - no `%` on this
-- client (Lua 5.0), so table.getn(PREVIEW_ICONS)'s wraparound is done via
-- floor division instead.
local function PreviewIconForSlot(n)
	local count = table.getn(PREVIEW_ICONS)
	local zeroBased = n - 1

	return PREVIEW_ICONS[(zeroBased - (math.floor(zeroBased / count) * count)) + 1]
end

-------------------------------------------------------------------------
-- Cosmetic (non-interactive) preview bars used by steps 3 and 5 - built
-- per the vanilla/modern button skin recipe from Button.lua's Init.
-------------------------------------------------------------------------

local function ComputePreviewBarWidth(buttonSize, spacing, count)
	return (buttonSize * count) + (spacing * (count - 1))
end

-- One cosmetic slot: vanilla style overlays Interface\Buttons\UI-Quickslot2
-- centered with a (0,-1) offset over a flush icon, sized ACAB.BORDER_RATIO
-- times the icon (Button.lua's own ApplySize ratio - real vanilla border
-- art is drawn larger than the icon it frames); modern style backdrops a
-- tooltip-skinned border with a 2px-inset icon.
local function CreateWizardPreviewSlot(parent, isModern, iconTexture)
	local slot = CreateFrame("Frame", nil, parent)

	local icon = slot:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(iconTexture)
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
-- place, without recreating any texture - used by step 5's live slider
-- updates. slots.container is the bar's own container frame.
local function LayoutWizardPreviewSlots(slots, buttonSize, spacing)
	local i

	for i = 1, table.getn(slots) do
		local slot = slots[i]

		slot:SetWidth(buttonSize)
		slot:SetHeight(buttonSize)

		if slot.border then
			local borderSize = buttonSize * ACAB.BORDER_RATIO

			slot.border:SetWidth(borderSize)
			slot.border:SetHeight(borderSize)
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
		slots[i] = CreateWizardPreviewSlot(container, isModern, PreviewIconForSlot(i))
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
	[4] = "General Layout",
	[5] = "Spacing & Button Size",
}

-- Starting height before the first real fit (FitHeightToStep) replaces
-- it - only ever visible for one frame.
local INITIAL_HEIGHT = 200

function ACABSetupWizardMixin:BuildStep1()
	local step = CreateFrame("Frame", nil, self)

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

	-- Bottom-right of the wizard itself, same row as the shared Back
	-- button - not anchored inline under errorText like the rest of this
	-- step's content, since every step's advance button lives in that
	-- same fixed spot.
	local nextButton = CreateFrame("Button", nil, step)
	nextButton:SetHeight(24)
	ACAB:StyleModernButton(nextButton, 120, 120)
	nextButton:SetText("Next")
	nextButton:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -20, 16)
	ACAB:ApplyProminentButtonHighlight(nextButton)
	nextButton:SetScript("OnClick", function()
		ACAB.setupWizard:AdvanceFromStep1()
	end)

	step.editBox = editBox
	step.errorText = errorText

	return step
end

function ACABSetupWizardMixin:BuildStep2()
	local step = CreateFrame("Frame", nil, self)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText(
		"Locks your bars to Blizzard's native position and style, or " ..
		"frees them.\n\n" ..
		"|cffff2626Locked: shown/hidden only - no moving, resizing, or " ..
		"restyling.|r\n\n" ..
		"|cff33ff33Unlocked: move, resize, and restyle bars, and unlock " ..
		"button style + spacing/size below.|r"
	)

	local enableButton = CreateFrame("Button", nil, step)
	enableButton:SetHeight(34)
	ACAB:StyleModernButton(enableButton, 200, 210)
	enableButton:SetText("Lock down default Elements!")
	enableButton:SetPoint("TOP", message, "BOTTOM", -115, -20)
	ACAB:ApplyDangerButtonHighlight(enableButton)
	enableButton:SetScript("OnClick", function()
		ACAB.setupWizard.wizardState.useDefaultLayout = true
		ACAB.setupWizard:FinishWizard()
	end)

	local disableButton = CreateFrame("Button", nil, step)
	disableButton:SetHeight(34)
	ACAB:StyleModernButton(disableButton, 200, 210)
	disableButton:SetText("Let me move everything!")
	disableButton:SetPoint("TOP", message, "BOTTOM", 115, -20)
	ACAB:ApplyProminentButtonHighlight(disableButton)
	disableButton:SetScript("OnClick", function()
		ACAB.setupWizard.wizardState.useDefaultLayout = false
		ACAB.setupWizard:ShowStep(3)
	end)

	return step
end

function ACABSetupWizardMixin:BuildStep3()
	local step = CreateFrame("Frame", nil, self)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText("Choose a button style for your bars. You can change this later in Settings.")

	-- Both bars are sized to the same APPARENT (outer) footprint, not the
	-- same icon size: vanilla's border renders ACAB.BORDER_RATIO times
	-- larger than the icon size fed into it (see CreateWizardPreviewSlot),
	-- so its icon is shrunk by that same ratio to make its outer border
	-- box match modern's flush icon+backdrop box.
	local previewApparentSize = 30
	local vanillaIconSize = previewApparentSize / ACAB.BORDER_RATIO
	local vanillaSpacing = 4
	local modernSpacing = 0

	local vanillaLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	vanillaLabel:SetPoint("TOP", message, "BOTTOM", -110, -26)
	vanillaLabel:SetText("Vanilla Style")

	local vanillaBar = CreateWizardPreviewBar(step, false, PREVIEW_SLOT_COUNT, vanillaIconSize, vanillaSpacing)
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

	local modernBar = CreateWizardPreviewBar(step, true, PREVIEW_SLOT_COUNT, previewApparentSize, modernSpacing)
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

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText(
		"Keep Blizzard's own bar layout, or switch to a centered modern " ..
		"layout with Blizzard's bar art turned off."
	)

	local keepButton = CreateFrame("Button", nil, step)
	keepButton:SetHeight(34)
	ACAB:StyleModernButton(keepButton, 210, 220)
	keepButton:SetText("Keep Blizzard Layout + ArtBar enabled")
	keepButton:SetPoint("TOP", message, "BOTTOM", -120, -20)
	ACAB:ApplyDangerButtonHighlight(keepButton)
	keepButton:SetScript("OnClick", function()
		ACAB.setupWizard.wizardState.generalLayoutFormat = "blizzard"
		ACAB.setupWizard:FinishWizard()
	end)

	local modernButton = CreateFrame("Button", nil, step)
	modernButton:SetHeight(34)
	ACAB:StyleModernButton(modernButton, 210, 220)
	modernButton:SetText("Modern Layout + ArtBar disabled")
	modernButton:SetPoint("TOP", message, "BOTTOM", 120, -20)
	ACAB:ApplyProminentButtonHighlight(modernButton)
	modernButton:SetScript("OnClick", function()
		ACAB.setupWizard.wizardState.generalLayoutFormat = "modern"
		ACAB.setupWizard:ShowStep(5)
	end)

	return step
end

function ACABSetupWizardMixin:BuildStep5()
	local step = CreateFrame("Frame", nil, self)

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

	local previewLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	previewLabel:SetPoint("TOP", message, "BOTTOM", 0, -10)
	previewLabel:SetText("Preview")

	-- One preview bar per style, both anchored at the same spot - only the
	-- one matching wizardState.modernBorderStyle (chosen on step 3) is
	-- ever shown (UpdateStep5PreviewStyle), so the bar the user sees here
	-- actually matches what they picked instead of always rendering
	-- vanilla-styled regardless of that choice.
	local vanillaBarContainer, vanillaBarSlots = CreateWizardPreviewBar(
		step, false, PREVIEW_SLOT_COUNT, ACAB.BUTTON_SIZE, 0
	)
	vanillaBarContainer:SetPoint("TOP", previewLabel, "BOTTOM", 0, -10)

	local modernBarContainer, modernBarSlots = CreateWizardPreviewBar(
		step, true, PREVIEW_SLOT_COUNT, ACAB.BUTTON_SIZE, 0
	)
	modernBarContainer:SetPoint("TOP", previewLabel, "BOTTOM", 0, -10)

	step.vanillaBarContainer = vanillaBarContainer
	step.vanillaBarSlots = vanillaBarSlots
	step.modernBarContainer = modernBarContainer
	step.modernBarSlots = modernBarSlots

	-- Fixed clearance below previewLabel (not anchored to either bar's own
	-- BOTTOM) so the checkbox stack doesn't jump around as the button-size
	-- slider grows the bar - BUTTON_SIZE_MAX plus the vanilla border's own
	-- BORDER_RATIO overflow past the bar's nominal edges, plus a margin.
	local PREVIEW_CLEARANCE = -(10 + (ACAB.BUTTON_SIZE_MAX * ACAB.BORDER_RATIO) + 20)

	-- Stacked vertically (not side by side like the General settings
	-- page's own pair) - side by side here runs past the wizard's width.
	local spacingCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSpacingCheckbox", {
		anchor = { "TOP", previewLabel, "BOTTOM", -60, PREVIEW_CLEARANCE },
		label = "Enable global spacing",
		onClick = function()
			ACAB.setupWizard.wizardState.globalSpacingEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep5SliderVisibility()
		end,
	})

	-- Mirrors SettingsGeneral.lua's own global-spacing slider config
	-- (step = ACAB.SPACING_STEP); the useDefaultLayout-driven display-offset
	-- that slider applies doesn't apply here since the wizard only reaches
	-- this step after useDefaultLayout has already been chosen "Disable".
	local spacingSlider, spacingValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardSpacingSlider", {
		anchor = { "TOP", spacingCheckbox, "BOTTOM", 60, -14 },
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
				ACAB.setupWizard:ReflowStep5Preview()
			end
		end,
	})
	spacingSlider:Hide()
	spacingValueText:Hide()

	local sizeCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSizeCheckbox", {
		anchor = { "TOP", spacingSlider, "BOTTOM", -60, -22 },
		label = "Enable global button size",
		onClick = function()
			ACAB.setupWizard.wizardState.globalButtonSizeEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep5SliderVisibility()
		end,
	})

	-- Mirrors SettingsGeneral.lua's own global-button-size slider config.
	local sizeSlider, sizeValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardSizeSlider", {
		anchor = { "TOP", sizeCheckbox, "BOTTOM", 60, -14 },
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
				ACAB.setupWizard:ReflowStep5Preview()
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

	-- Bottom-right of the wizard, same row/style as every other step's
	-- advance button (step 1's Next, the shared Back button).
	local finishButton = CreateFrame("Button", nil, step)
	finishButton:SetHeight(28)
	ACAB:StyleModernButton(finishButton, 140, 140)
	finishButton:SetText("Finish")
	finishButton:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -20, 16)
	ACAB:ApplyProminentButtonHighlight(finishButton)
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
	self:SetHeight(INITIAL_HEIGHT)
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

	-- Steps back to the previous step - hidden on the first step (nothing
	-- to go back to; see ShowStep). The X close button above is the only
	-- way to cancel/close outright now, on any step.
	self.backButton = CreateFrame("Button", nil, self)
	self.backButton:SetHeight(22)
	ACAB:StyleModernButton(self.backButton, 90, 90)
	self.backButton:SetText("Back")
	self.backButton:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", 20, 16)
	ACAB:ApplyDangerButtonHighlight(self.backButton)
	self.backButton:SetScript("OnClick", function()
		ACAB.setupWizard:GoToPreviousStep()
	end)

	self.steps = {
		self:BuildStep1(),
		self:BuildStep2(),
		self:BuildStep3(),
		self:BuildStep4(),
		self:BuildStep5(),
	}

	local i

	-- Dual TOPLEFT+BOTTOMRIGHT anchor, both corners off `self` directly -
	-- gives each step frame a real width AND height purely derived from
	-- self's own (already-resolved) rect, set once here and never touched
	-- again. STEP_CONTENT_TOP_OFFSET clears titleText+stepText (measured
	-- live in testing); the bottom margin clears the Back/Next button row.
	local STEP_CONTENT_TOP_OFFSET = -66
	local STEP_CONTENT_BOTTOM_MARGIN = 50

	for i = 1, table.getn(self.steps) do
		self.steps[i]:ClearAllPoints()
		self.steps[i]:SetPoint("TOPLEFT", self, "TOPLEFT", 20, STEP_CONTENT_TOP_OFFSET)
		self.steps[i]:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -20, STEP_CONTENT_BOTTOM_MARGIN)
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
		generalLayoutFormat = nil,
		globalSpacingEnabled = false,
		globalSpacingValue = 0,
		globalButtonSizeEnabled = false,
		globalButtonSizeValue = ACAB.BUTTON_SIZE,
	}

	self.titleText:SetText(overwriteExisting and "Reconfigure Your Profile" or "Set Up Your Profile")

	local step1 = self.steps[1]
	step1.editBox:SetText(self.wizardState.profileName)
	step1.errorText:Hide()

	local step5 = self.steps[5]
	step5.spacingCheckbox:SetChecked(false)
	step5.sizeCheckbox:SetChecked(false)

	step5.spacingSlider.suppressApply = true
	step5.spacingSlider:SetValue(0)
	step5.spacingSlider.suppressApply = nil

	step5.sizeSlider.suppressApply = true
	step5.sizeSlider:SetValue(ACAB.BUTTON_SIZE)
	step5.sizeSlider.suppressApply = nil

	self:UpdateStep5SliderVisibility()
end

function ACABSetupWizardMixin:ShowStep(n)
	local i

	for i = 1, table.getn(self.steps) do
		self.steps[i]:Hide()
	end

	self.currentStep = n

	-- Overwrite mode skips step 1 (name is fixed to the current profile),
	-- so the displayed count is renumbered to "of 4" starting at 1 instead
	-- of showing a step 1 the user never saw, and Back has nothing to go
	-- back to until step 3. Total is the max reachable step regardless of
	-- mode - choosing "Keep Blizzard Layout" on step 4 or "Lock down
	-- default Elements!" on step 2 finishes without ever visiting step 5,
	-- same as this counter already not visiting every number in order.
	local firstStep = self.wizardState.overwriteExisting and 2 or 1
	local totalSteps = self.wizardState.overwriteExisting and 4 or 5
	local displayStep = self.wizardState.overwriteExisting and (n - 1) or n

	self.stepText:SetText("Step " .. tostring(displayStep) .. " of " .. tostring(totalSteps) .. " - " .. (STEP_TITLES[n] or ""))
	self.backButton:SetShown(n > firstStep)

	local step = self.steps[n]

	if n == 5 then
		self:UpdateStep5PreviewStyle()
	end

	step:Show()

	if n == 1 then
		step.editBox:SetFocus()
		step.editBox:HighlightText()
	end

	self:FitHeightToStep(n)
end

-- Back always steps to currentStep-1 - every reachable path through the
-- wizard is a straight line (step 2's "Lock down default Elements!" and
-- step 4's "Keep Blizzard Layout + ArtBar enabled" both finish immediately
-- rather than skipping ahead), so there's no case where the previous step
-- isn't the one the user actually saw.
function ACABSetupWizardMixin:GoToPreviousStep()
	self:ShowStep(self.currentStep - 1)
end

-- Deepest (lowest-on-screen) GetBottom() among `step`'s own direct child
-- frames/regions that are currently shown - container frames (e.g. a
-- preview bar) are measured as one unit via their own GetBottom(), not
-- recursed into, since their own height already spans their children.
local function MeasureStepBottom(step)
	local deepest = nil
	local widgets = { step:GetChildren() }
	local regions = { step:GetRegions() }
	local i

	for i = 1, table.getn(regions) do
		widgets[table.getn(widgets) + 1] = regions[i]
	end

	for i = 1, table.getn(widgets) do
		local widget = widgets[i]

		if widget:IsShown() then
			local bottom = widget:GetBottom()

			if bottom and (not deepest or bottom < deepest) then
				deepest = bottom
			end
		end
	end

	return deepest
end

-- Resizes the wizard to fit step `n`'s actual current content instead of a
-- guessed-at fixed height - GetBottom() on content just Show()'n/re-shown
-- this same tick hasn't resolved on this client yet (confirmed live while
-- fixing the step 1 editBox/Next button not appearing at all - see this
-- branch's commit history), so the measurement is deferred one frame via
-- ACAB:DeferFit. Guarded on currentStep still matching `n` in case the
-- user already moved on by the time the deferred callback runs.
function ACABSetupWizardMixin:FitHeightToStep(n)
	local step = self.steps[n]

	if not step then
		return
	end

	local NAV_ROW_CLEARANCE = 50
	local BOTTOM_PADDING = 20

	ACAB:DeferFit(function()
		local wizard = ACAB.setupWizard

		if not wizard or wizard.currentStep ~= n then
			return
		end

		local top = wizard:GetTop()
		local bottom = MeasureStepBottom(step)

		if not top or not bottom then
			return
		end

		wizard:SetHeight((top - bottom) + NAV_ROW_CLEARANCE + BOTTOM_PADDING)
	end)
end

-- Validates step 1's profile-name entry and advances to step 2 - reused by
-- both the Next button and the edit box's OnEnterPressed.
function ACABSetupWizardMixin:AdvanceFromStep1()
	local step = self.steps[1]
	local name = step.editBox:GetText()

	if not name or name == "" then
		step.errorText:SetText("Profile name cannot be empty.")
		step.errorText:Show()
		self:FitHeightToStep(1)
		return
	end

	if ACAB:ProfileNameTaken(name) then
		step.errorText:SetText("A profile named \"" .. name .. "\" already exists.")
		step.errorText:Show()
		self:FitHeightToStep(1)
		return
	end

	step.errorText:Hide()
	self.wizardState.profileName = name

	self:ShowStep(2)
end

function ACABSetupWizardMixin:UpdateStep5SliderVisibility()
	local step = self.steps[5]
	local state = self.wizardState

	step.spacingSlider:SetShown(state.globalSpacingEnabled and true or false)
	step.spacingValueText:SetShown(state.globalSpacingEnabled and true or false)

	step.sizeSlider:SetShown(state.globalButtonSizeEnabled and true or false)
	step.sizeValueText:SetShown(state.globalButtonSizeEnabled and true or false)

	self:ReflowStep5Preview()

	if self.currentStep == 5 then
		self:FitHeightToStep(5)
	end
end

-- Shows whichever of step 5's two preview bars matches step 3's choice
-- (wizardState.modernBorderStyle) and hides the other - called from
-- ShowStep whenever step 5 becomes visible, so the bar shown here always
-- matches what the user actually picked.
function ACABSetupWizardMixin:UpdateStep5PreviewStyle()
	local step = self.steps[5]
	local isModern = self.wizardState.modernBorderStyle and true or false

	step.vanillaBarContainer:SetShown(not isModern)
	step.modernBarContainer:SetShown(isModern)
end

-- Recomputes the single active preview bar's slot layout from the current
-- spacing/size slider values (both aspects on the same bar, per whichever
-- step 3 picked) - updates both style variants' slots so either is
-- already correct whenever UpdateStep5PreviewStyle switches which is shown.
function ACABSetupWizardMixin:ReflowStep5Preview()
	local step = self.steps[5]
	local state = self.wizardState

	local buttonSize = (state.globalButtonSizeEnabled and state.globalButtonSizeValue) or ACAB.BUTTON_SIZE
	local spacing = (state.globalSpacingEnabled and state.globalSpacingValue) or 0
	local width = ComputePreviewBarWidth(buttonSize, spacing, PREVIEW_SLOT_COUNT)

	LayoutWizardPreviewSlots(step.vanillaBarSlots, buttonSize, spacing)
	step.vanillaBarContainer:SetHeight(buttonSize)
	step.vanillaBarContainer:SetWidth(width)

	LayoutWizardPreviewSlots(step.modernBarSlots, buttonSize, spacing)
	step.modernBarContainer:SetHeight(buttonSize)
	step.modernBarContainer:SetWidth(width)
end

-- Applies the "Modern Layout" preset (step 4's second choice) onto `data`
-- - disables Blizzard's bar art, centers the Main Bar (default bar id 1),
-- stacks Action Bar 1/2 (ids 2/3, enabling them) directly above it, and
-- clusters Bag Bar/Micro Menu/Latency Bar in the bottom-right corner.
--
-- Every position is expressed relative to UIParent's own corners/center,
-- the same coordinate space ACAB:CaptureNativeAnchor and
-- ACAB:ApplyBarPosition/ApplyBagBarPosition/ApplyLatencyBarPosition
-- already use (Database.lua/Bar.lua/NativeElements.lua) - UIParent's own
-- dimensions are already resolution/UI-scale-corrected, so a CENTER or
-- BOTTOMRIGHT anchor with a small fixed offset lands in the same relative
-- spot on any screen/scale, with no GetScreenWidth()/uiScale math needed.
--
-- Bag Bar's own rendered width/height isn't known until after this
-- profile's ReloadUI (it depends on the live client's actual bag count),
-- so Micro Menu/Latency Bar's clearance from it is a fixed estimate sized
-- for a full 5-slot bag bar at the chosen button size - close for the
-- common case, but a live-client round of calibration (or the reference
-- profile you offered) would tighten this up if it looks off.
local function ApplyModernLayoutPreset(data)
	data.disableBlizzardArt = true

	local buttonSize = (data.globalButtonSizeEnabled and data.globalButtonSizeValue) or ACAB.BUTTON_SIZE
	local rowGap = 6

	data.defaultBars = data.defaultBars or {}

	local mainBarCfg = data.defaultBars[1] or {}
	mainBarCfg.point = "CENTER"
	mainBarCfg.relativePoint = "CENTER"
	mainBarCfg.x = 0
	mainBarCfg.y = 0
	data.defaultBars[1] = mainBarCfg

	local actionBar1Cfg = data.defaultBars[2] or {}
	actionBar1Cfg.enabled = true
	actionBar1Cfg.point = "CENTER"
	actionBar1Cfg.relativePoint = "CENTER"
	actionBar1Cfg.x = 0
	actionBar1Cfg.y = buttonSize + rowGap
	data.defaultBars[2] = actionBar1Cfg

	local actionBar2Cfg = data.defaultBars[3] or {}
	actionBar2Cfg.enabled = true
	actionBar2Cfg.point = "CENTER"
	actionBar2Cfg.relativePoint = "CENTER"
	actionBar2Cfg.x = 0
	actionBar2Cfg.y = (buttonSize + rowGap) * 2
	data.defaultBars[3] = actionBar2Cfg

	local cornerMargin = 8
	local bagBarWidthEstimate = 5 * (buttonSize + (data.globalSpacingEnabled and data.globalSpacingValue or 0))
	local bagBarHeightEstimate = buttonSize

	data.bagBarPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = -cornerMargin, y = cornerMargin,
	}
	data.microMenuPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = -cornerMargin, y = cornerMargin + bagBarHeightEstimate + rowGap,
	}
	data.latencyBarPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = -(cornerMargin + bagBarWidthEstimate + cornerMargin), y = cornerMargin,
	}
end

-- Applies wizardState.useDefaultLayout/modernBorderStyle/general layout
-- format/global spacing+size onto `data` - shared by FinishWizard's create
-- and overwrite branches.
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

	-- "blizzard" (Keep Blizzard Layout + ArtBar enabled) is a deliberate
	-- no-op here - the profile keeps whatever it already has (copied from
	-- Default, or the active profile's own current layout in overwrite
	-- mode) exactly as is.
	if state.generalLayoutFormat == "modern" then
		ApplyModernLayoutPreset(data)
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
