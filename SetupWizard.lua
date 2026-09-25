-- SetupWizard.lua
-- Multi-step profile setup wizard (ACAB:ShowSetupWizard): creates a new profile, or in overwrite mode
-- reconfigures the active one (skipping the name step). Nothing is persisted until FinishWizard.

local ACAB = AlternativeClassicActionBars

local WIZARD_WIDTH = 480
local WIZARD_CONTENT_WIDTH = WIZARD_WIDTH - 40
local PREVIEW_SLOT_COUNT = 5
-- Spacing between vanilla-bordered preview slots (the border art overhangs the slot).
local VANILLA_PREVIEW_SPACING = 4

-- Cosmetic icons cycled across preview slots.
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

-- PREVIEW_ICONS entry for 1-based slot n, wrapping around.
local function PreviewIconForSlot(n)
	local count = table.getn(PREVIEW_ICONS)
	local zeroBased = n - 1

	return PREVIEW_ICONS[(zeroBased - (math.floor(zeroBased / count) * count)) + 1]
end

-------------------------------------------------------------------------
-- Cosmetic (non-interactive) preview bars, same vanilla/modern skin recipe as Button.lua's Init
-------------------------------------------------------------------------

local function ComputePreviewBarWidth(buttonSize, spacing, count)
	return (buttonSize * count) + (spacing * (count - 1))
end

-- One cosmetic slot: vanilla = flush icon + UI-Quickslot2 border overlay; modern = backdrop + 2px-inset icon.
local function CreateWizardPreviewSlot(parent, isModern, iconTexture)
	local slot = CreateFrame("Frame", nil, parent)

	local icon = slot:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(iconTexture)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	if isModern then
		slot:SetBackdrop(ACAB.SMALL_BACKDROP)
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

-- Sizes and chains existing slots in place; slots.container is the row's container frame.
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

-- Row of count slots built by createSlot(container, i). Returns container (caller anchors it), slots.
local function CreateWizardSlotRow(parent, count, buttonSize, spacing, createSlot)
	local container = CreateFrame("Frame", nil, parent)
	container:SetHeight(buttonSize)
	container:SetWidth(ComputePreviewBarWidth(buttonSize, spacing, count))

	local slots = {}
	slots.container = container

	local i

	for i = 1, count do
		slots[i] = createSlot(container, i)
	end

	LayoutWizardPreviewSlots(slots, buttonSize, spacing)

	return container, slots
end

-- Preview bar with icons cycled from PREVIEW_ICONS.
local function CreateWizardPreviewBar(parent, isModern, count, buttonSize, spacing)
	return CreateWizardSlotRow(parent, count, buttonSize, spacing, function(container, i)
		return CreateWizardPreviewSlot(container, isModern, PreviewIconForSlot(i))
	end)
end

-- Preview bar from an explicit icon list (nil = empty slot); count is explicit since icons can have holes.
local function CreateWizardIconRow(parent, isModern, icons, count, buttonSize, spacing)
	return CreateWizardSlotRow(parent, count, buttonSize, spacing, function(container, i)
		return CreateWizardPreviewSlot(container, isModern, icons[i])
	end)
end

-------------------------------------------------------------------------
-- Step 4's cosmetic Stance Bar / Page Swap Indicator demo (example stances, not the player's class)
-------------------------------------------------------------------------

-- stanceIcon: the stance button's fixed icon; icons: that stance's example ability bar.
local STEP4_STANCE_ABILITIES = {
	{
		name = "Battle Stance",
		stanceIcon = "Interface\\Icons\\Ability_Warrior_Charge",
		icons = {
			"Interface\\Icons\\Ability_Warrior_Charge",
			"Interface\\Icons\\Ability_Rogue_Ambush",
			"Interface\\Icons\\Ability_Shockwave",
			"Interface\\Icons\\Ability_Warrior_Cleave",
		},
	},
	{
		name = "Defensive Stance",
		stanceIcon = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
		icons = {
			"Interface\\Icons\\Ability_Warrior_Charge",
			"Interface\\Icons\\Ability_Rogue_Ambush",
			"Interface\\Icons\\Ability_Warrior_Sunder",
			"Interface\\Icons\\Spell_Nature_Reincarnation",
		},
	},
	{
		name = "Berserker Stance",
		stanceIcon = "Interface\\Icons\\Ability_Racial_Avatar",
		icons = {
			"Interface\\Icons\\Ability_Rogue_Sprint",
			"Interface\\Icons\\Ability_Rogue_Ambush",
			"Interface\\Icons\\Ability_Whirlwind",
			"Interface\\Icons\\Ability_Warrior_Cleave",
		},
	},
}

local STEP4_BAR_SLOT_COUNT = 4

-- Step 6's example Stance Bar: the same 3 example stance icons as step 4.
local STEP6_STANCE_PREVIEW_COUNT = table.getn(STEP4_STANCE_ABILITIES)
local STEP6_STANCE_ICONS = {
	STEP4_STANCE_ABILITIES[1].stanceIcon,
	STEP4_STANCE_ABILITIES[2].stanceIcon,
	STEP4_STANCE_ABILITIES[3].stanceIcon,
}

-- Step 6's example Pet Bar: vanilla 10-slot layout (commands, one ability, 3 empty slots, reactions).
local STEP6_PET_PREVIEW_COUNT = 10
local STEP6_PET_ICONS = {
	"Interface\\Icons\\Ability_GhoulFrenzy",       -- Attack
	"Interface\\Icons\\Ability_Tracking",          -- Follow
	"Interface\\Icons\\Ability_Racial_BloodRage",  -- Stay
	"Interface\\Icons\\Ability_Physical_Taunt",    -- Growl
	nil, nil, nil,                                 -- untrained ability slots
	"Interface\\Icons\\Ability_Racial_BloodRage",  -- Aggressive
	"Interface\\Icons\\Ability_Defend",            -- Defensive
	"Interface\\Icons\\Ability_Seal",              -- Passive
}

-- Clickable preview slot with a toggleable selection glow.
local function CreateWizardStanceSlot(parent, isModern, iconTexture, onClick)
	local slot = CreateWizardPreviewSlot(parent, isModern, iconTexture)

	local hitArea = CreateFrame("Button", nil, slot)
	hitArea:SetAllPoints(slot)
	hitArea:SetScript("OnClick", onClick)

	local glow = slot:CreateTexture(nil, "OVERLAY")
	glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	glow:SetBlendMode("ADD")
	glow:SetAllPoints(slot)
	glow:Hide()

	slot.glow = glow

	return slot
end

-- Row of the 3 clickable example stance buttons. Returns container, slots.
local function BuildStep4StanceRow(parent, isModern, onStanceClick)
	local stanceSize = 28
	local stanceSpacing = isModern and 0 or VANILLA_PREVIEW_SPACING

	return CreateWizardSlotRow(parent, table.getn(STEP4_STANCE_ABILITIES), stanceSize, stanceSpacing, function(container, s)
		return CreateWizardStanceSlot(container, isModern, STEP4_STANCE_ABILITIES[s].stanceIcon, function()
			onStanceClick(s)
		end)
	end)
end

-- Standalone lookalike of the Page Indicator; either arrow calls onToggle (pages 1/2 only).
local function CreateWizardPageIndicator(parent, onToggle)
	local container = CreateFrame("Frame", nil, parent)
	container:SetWidth(24)
	container:SetHeight(56)

	local upButton = CreateFrame("Button", nil, container, "UIPanelScrollUpButtonTemplate")
	upButton:SetPoint("TOP", container, "TOP", 0, 0)
	upButton:SetScript("OnClick", onToggle)

	local pageText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pageText:SetPoint("TOP", upButton, "BOTTOM", 0, -4)

	local downButton = CreateFrame("Button", nil, container, "UIPanelScrollDownButtonTemplate")
	downButton:SetPoint("TOP", pageText, "BOTTOM", 0, -4)
	downButton:SetScript("OnClick", onToggle)

	container.pageText = pageText

	return container
end

-- Choices for each stance/Page 2 row: which example stance's abilities that row previews.
local STEP4_STANCE_PREVIEW_OPTIONS = {
	{ text = "Preview Battle Stance", value = 1 },
	{ text = "Preview Defensive Stance", value = 2 },
	{ text = "Preview Berserker Stance", value = 3 },
}

local function CreateStep4StancePreviewRow(parent, labelText, dropdownName, defaultValue, onSelect)
	local row = CreateFrame("Frame", nil, parent)
	row:SetWidth(360)
	row:SetHeight(28)

	local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	label:SetPoint("LEFT", row, "LEFT", 0, 0)
	label:SetWidth(140)
	label:SetJustifyH("LEFT")
	label:SetText(labelText)

	local dropdown = ACAB:CreateInlineDropdown(row, 170, dropdownName)
	dropdown:SetPoint("LEFT", label, "RIGHT", -8, -2)
	dropdown:SetOptions(STEP4_STANCE_PREVIEW_OPTIONS)
	dropdown:SetSelected(defaultValue, STEP4_STANCE_PREVIEW_OPTIONS[defaultValue].text)
	dropdown.onSelect = onSelect

	row.dropdown = dropdown

	return row
end

-------------------------------------------------------------------------
-- Shared step-building helpers
-------------------------------------------------------------------------

-- New step frame with its centered intro message at the top. Returns step, message.
local function CreateStepFrame(wizard, text, messageHeight)
	local step = CreateFrame("Frame", nil, wizard)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)

	if messageHeight then
		message:SetHeight(messageHeight)
	end

	message:SetJustifyH("CENTER")
	message:SetText(text)

	return step, message
end

-- Modern-styled button; config = { text, height, minWidth, maxWidth, anchor, variant ("danger"|"prominent"), onClick }.
local function CreateWizardButton(parent, config)
	local button = CreateFrame("Button", nil, parent)

	button:SetHeight(config.height)
	ACAB:StyleModernButton(button, config.minWidth, config.maxWidth)
	button:SetText(config.text)
	button:SetPoint(unpack(config.anchor))

	if config.variant == "danger" then
		ACAB:ApplyDangerButtonHighlight(button)
	elseif config.variant == "prominent" then
		ACAB:ApplyProminentButtonHighlight(button)
	end

	button:SetScript("OnClick", config.onClick)

	return button
end

-- A step's Next/Finish button, pinned to the wizard's bottom-right; flagged so MeasureStepBottom skips it.
local function CreateWizardNavButton(step, wizard, text, height, width, onClick)
	local button = CreateWizardButton(step, {
		text = text,
		height = height,
		minWidth = width,
		maxWidth = width,
		anchor = { "BOTTOMRIGHT", wizard, "BOTTOMRIGHT", -20, 16 },
		variant = "prominent",
		onClick = onClick,
	})

	button.ACABNavButton = true

	return button
end

-- Checkbox onClick: stores the checked state in wizardState[key], then calls wizard[refreshMethod] if given.
local function CheckboxToState(key, refreshMethod)
	return function()
		local wizard = ACAB.setupWizard

		wizard.wizardState[key] = this:GetChecked() and true or false

		if refreshMethod then
			wizard[refreshMethod](wizard)
		end
	end
end

-- Slider onChange: stores user-driven values in wizardState[key], then calls wizard[refreshMethod] if given.
local function SliderToState(key, refreshMethod)
	return function(value, suppressApply)
		if suppressApply then
			return
		end

		local wizard = ACAB.setupWizard

		wizard.wizardState[key] = value

		if refreshMethod then
			wizard[refreshMethod](wizard)
		end
	end
end

local function RoundToInteger(value)
	return math.floor(value + 0.5)
end

-- Better Experience Bar text toggles (same keys as the settings page / ACABDB).
local EXP_BAR_TEXT_TOGGLES = {
	{ key = "expBarShowLevel", label = "Show Current Lvl" },
	{ key = "expBarShowCurrentOverMax", label = "Show Current XP / Max" },
	{ key = "expBarShowPercent", label = "Show Current % / Max" },
	{ key = "expBarShowRestedPercent", label = "Show Current Rested XP %" },
	{ key = "expBarShowRestedTotal", label = "Show Current Total Rested XP" },
}

-- Better Experience Bar fields that stay nil (unwritten) unless the user changed them.
local EXP_BAR_OPTIONAL_KEYS = {
	"expBarFontSize", "expBarColorEarned", "expBarColorRested", "expBarTextColor", "expBarGlowPulseInterval",
}

-------------------------------------------------------------------------
-- ACABSetupWizardMixin
-------------------------------------------------------------------------

ACABSetupWizardMixin = {}

local STEP_TITLES = {
	[1] = "Name Your Profile",
	[2] = "Force Vanilla Layout Mode",
	[3] = "Button Style",
	[4] = "Stance / Page Swapping",
	[5] = "General Layout",
	[6] = "Pet Bar / Stance Bar Mode",
	[7] = "Experience Bar",
	[8] = "Spacing & Button Size",
}

-- Height before the first FitHeightToStep.
local INITIAL_HEIGHT = 200

-- Step 1: profile name.
function ACABSetupWizardMixin:BuildStep1()
	local step, message = CreateStepFrame(self,
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

	CreateWizardNavButton(step, self, "Next", 24, 120, function()
		ACAB.setupWizard:AdvanceFromStep1()
	end)

	step.editBox = editBox
	step.errorText = errorText

	return step
end

-- Step 2: locked vanilla layout (finishes) or unlocked (continues).
function ACABSetupWizardMixin:BuildStep2()
	local step, message = CreateStepFrame(self,
		"Locks your bars to their native vanilla position and style, or " ..
		"frees them.\n\n" ..
		"|cffff2626Locked: shown/hidden only - no moving, resizing, or " ..
		"restyling.|r\n\n" ..
		"|cff33ff33Unlocked: move, resize, and restyle bars, and unlock " ..
		"button style + spacing/size below.|r"
	)

	CreateWizardButton(step, {
		text = "Lock down default Elements!",
		height = 34,
		minWidth = 200,
		maxWidth = 210,
		anchor = { "TOP", message, "BOTTOM", -115, -20 },
		variant = "danger",
		onClick = function()
			ACAB.setupWizard.wizardState.useDefaultLayout = true
			ACAB.setupWizard:FinishWizard()
		end,
	})

	CreateWizardButton(step, {
		text = "Let me move everything!",
		height = 34,
		minWidth = 200,
		maxWidth = 210,
		anchor = { "TOP", message, "BOTTOM", 115, -20 },
		variant = "prominent",
		onClick = function()
			ACAB.setupWizard.wizardState.useDefaultLayout = false
			ACAB.setupWizard:ShowStep(3)
		end,
	})

	return step
end

-- Step 3: vanilla vs modern button style.
function ACABSetupWizardMixin:BuildStep3()
	local step, message = CreateStepFrame(self,
		"Choose a button style for your bars. You can change this later in Settings."
	)

	-- One style column: label, preview bar and Select button.
	local function BuildStyleColumn(offsetX, labelText, isModern, buttonSize, spacing)
		local label = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOP", message, "BOTTOM", offsetX, -26)
		label:SetText(labelText)

		local bar = CreateWizardPreviewBar(step, isModern, PREVIEW_SLOT_COUNT, buttonSize, spacing)
		bar:SetPoint("TOP", label, "BOTTOM", 0, -10)

		CreateWizardButton(step, {
			text = "Select",
			height = 24,
			minWidth = 120,
			maxWidth = 120,
			anchor = { "TOP", bar, "BOTTOM", 0, -14 },
			onClick = function()
				ACAB.setupWizard.wizardState.modernBorderStyle = isModern
				ACAB.setupWizard:ShowStep(4)
			end,
		})
	end

	-- Modern is drawn 2px larger so both styles read the same apparent size.
	local vanillaApparentSize = 30

	BuildStyleColumn(-110, "Vanilla Style", false, vanillaApparentSize, VANILLA_PREVIEW_SPACING)
	BuildStyleColumn(110, "Modern Style", true, vanillaApparentSize + 2, 0)

	return step
end

-- Step 4: page/stance swapping, with a live example bar, stance row and Page Swap Indicator.
function ACABSetupWizardMixin:BuildStep4()
	local step = CreateStepFrame(self,
		"Let each default bar (1-5) swap its own content per stance or " ..
		"Shift/Ctrl page. Try the example bar below.",
		30
	)

	local cursorY = -34

	local function OnStanceClick(stanceIndex)
		ACAB.setupWizard.wizardState.stancePreviewActive = stanceIndex
		ACAB.setupWizard:UpdateStep4Preview()
	end

	local pageSwapCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardPageSwapCheckbox", {
		anchor = { "TOP", step, "TOP", -110, cursorY },
		label = "Enable Page Bar-Changes",
		tooltip = {
			title = "Enable Page Bar-Changes",
			lines = {
				"Lets every default bar (1-5) show different content while " ..
				"Shift/Ctrl page 2 is held, and shows the Page Swap Indicator.",
			},
		},
		onClick = CheckboxToState("pageSwapEnabled", "UpdateStep4Visibility"),
	})
	cursorY = cursorY - 24 - 6

	local stanceSwapCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardStanceSwapCheckbox", {
		anchor = { "TOP", step, "TOP", -130, cursorY },
		label = "Enable Stance/Form/Stealth Bar-Changes",
		tooltip = {
			title = "Enable Stance/Form/Stealth Bar-Changes",
			lines = {
				"Lets every default bar (1-5) show different content per " ..
				"active stance/form/stealth.",
			},
		},
		onClick = CheckboxToState("stanceSwapEnabled", "UpdateStep4Visibility"),
	})
	cursorY = cursorY - 24 - 16

	local previewLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	previewLabel:SetPoint("TOP", step, "TOP", 0, cursorY)
	previewLabel:SetText("Preview - click a stance or the page arrows")
	cursorY = cursorY - 16 - 4

	local disclaimer = step:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	disclaimer:SetPoint("TOP", step, "TOP", 0, cursorY)
	disclaimer:SetWidth(WIZARD_CONTENT_WIDTH)
	disclaimer:SetJustifyH("CENTER")
	disclaimer:SetTextColor(1, 0.15, 0.15)
	disclaimer:SetText(
		"This is only a preview of the behavior. Once this setting is " ..
		"enabled, set up the real bar assignments on each default bar's " ..
		"own Settings page - or enable it later from the General tab."
	)
	-- Fixed clearance for up to 3 wrapped disclaimer lines.
	cursorY = cursorY - 40 - 10

	-- Vanilla and modern variants share each spot; UpdateStep4PreviewStyle shows the one matching step 3.
	local vanillaStanceContainer, vanillaStanceSlots = BuildStep4StanceRow(step, false, OnStanceClick)
	vanillaStanceContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	local modernStanceContainer, modernStanceSlots = BuildStep4StanceRow(step, true, OnStanceClick)
	modernStanceContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	cursorY = cursorY - 28 - 6

	local vanillaActionBarContainer, vanillaActionBarSlots = CreateWizardPreviewBar(
		step, false, STEP4_BAR_SLOT_COUNT, ACAB.BUTTON_SIZE, ACAB.VANILLA_SPACING_FLOOR
	)
	vanillaActionBarContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	local modernActionBarContainer, modernActionBarSlots = CreateWizardPreviewBar(
		step, true, STEP4_BAR_SLOT_COUNT, ACAB.BUTTON_SIZE, 0
	)
	modernActionBarContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	-- Anchored to the vanilla bar; both variants share the same width and spot.
	local pageIndicator = CreateWizardPageIndicator(step, function()
		ACAB.setupWizard.wizardState.pagePreviewActive = not ACAB.setupWizard.wizardState.pagePreviewActive
		ACAB.setupWizard:UpdateStep4Preview()
	end)
	pageIndicator:SetPoint("LEFT", vanillaActionBarContainer, "RIGHT", 14, 0)

	cursorY = cursorY - ACAB.BUTTON_SIZE - 16

	-- 3 stance-preview rows + 1 Page 2 row (preview only, never written to ACABDB).
	local stanceDropdownRows = {}
	local stanceDropdowns = {}
	local s

	for s = 1, table.getn(STEP4_STANCE_ABILITIES) do
		local stanceIndex = s

		local row = CreateStep4StancePreviewRow(
			step, STEP4_STANCE_ABILITIES[s].name .. ":",
			"ACABSetupWizardStanceAssignmentDropdown" .. tostring(s),
			s,
			function(value)
				ACAB.setupWizard.wizardState.stancePreviewAssignment[stanceIndex] = value
				ACAB.setupWizard:UpdateStep4Preview()
			end
		)
		row:SetPoint("TOP", step, "TOP", 0, cursorY)

		stanceDropdownRows[s] = row
		stanceDropdowns[s] = row.dropdown

		cursorY = cursorY - 28 - 6
	end

	local pageDropdownRow = CreateStep4StancePreviewRow(
		step, "Page 2 Content Source:", "ACABSetupWizardPageAssignmentDropdown",
		1,
		function(value)
			ACAB.setupWizard.wizardState.pagePreviewAssignment = value
			ACAB.setupWizard:UpdateStep4Preview()
		end
	)
	pageDropdownRow:SetPoint("TOP", step, "TOP", 0, cursorY)

	CreateWizardNavButton(step, self, "Next", 24, 120, function()
		ACAB.setupWizard:ShowStep(5)
	end)

	step.pageSwapCheckbox = pageSwapCheckbox
	step.stanceSwapCheckbox = stanceSwapCheckbox
	step.vanillaStanceContainer = vanillaStanceContainer
	step.vanillaStanceSlots = vanillaStanceSlots
	step.modernStanceContainer = modernStanceContainer
	step.modernStanceSlots = modernStanceSlots
	step.vanillaActionBarContainer = vanillaActionBarContainer
	step.vanillaActionBarSlots = vanillaActionBarSlots
	step.modernActionBarContainer = modernActionBarContainer
	step.modernActionBarSlots = modernActionBarSlots
	step.pageIndicator = pageIndicator
	step.stanceDropdownRows = stanceDropdownRows
	step.stanceDropdowns = stanceDropdowns
	step.pageDropdownRow = pageDropdownRow
	step.pageDropdown = pageDropdownRow.dropdown

	return step
end

-- Step 5: keep the vanilla layout (finishes) or switch to Modern Layout (continues).
function ACABSetupWizardMixin:BuildStep5()
	local step, message = CreateStepFrame(self,
		"Keep the vanilla bar layout, or switch to a centered modern " ..
		"layout with Blizzard's bar art turned off."
	)

	CreateWizardButton(step, {
		text = "Keep Vanilla Layout + ArtBar enabled",
		height = 34,
		minWidth = 210,
		maxWidth = 220,
		anchor = { "TOP", message, "BOTTOM", -120, -20 },
		variant = "danger",
		onClick = function()
			ACAB.setupWizard.wizardState.generalLayoutFormat = "blizzard"
			ACAB.setupWizard:FinishWizard()
		end,
	})

	CreateWizardButton(step, {
		text = "Modern Layout + ArtBar disabled",
		height = 34,
		minWidth = 210,
		maxWidth = 220,
		anchor = { "TOP", message, "BOTTOM", 120, -20 },
		variant = "prominent",
		onClick = function()
			ACAB.setupWizard.wizardState.generalLayoutFormat = "modern"
			ACAB.setupWizard:ShowStep(6)
		end,
	})

	return step
end

-- Step 6 (Modern Layout only): native vs styled Stance/Pet Bar, each with a vanilla/modern preview pair.
function ACABSetupWizardMixin:BuildStep6()
	local step = CreateStepFrame(self,
		"Choose how your Stance Bar and Pet Bar are built. Vanilla uses " ..
		"the real Blizzard frame (compatible with the real Keybindings " ..
		"menu); switching to the styled/modern mode lets this addon " ..
		"resize, restyle, and Hoverbind it like a custom bar."
	)

	local cursorY = -50

	-- Title, vanilla/modern preview rows and "Use Vanilla <bar>" checkbox; returns all four row values + checkbox.
	local function BuildBarModeSection(barName, nameKey, icons, count, stateKey)
		local label = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
		label:SetPoint("TOP", step, "TOP", 0, cursorY)
		label:SetText(barName)
		cursorY = cursorY - 16 - 8

		local vanillaContainer, vanillaSlots = CreateWizardIconRow(
			step, false, icons, count, ACAB.BUTTON_SIZE, VANILLA_PREVIEW_SPACING
		)
		vanillaContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

		local modernContainer, modernSlots = CreateWizardIconRow(
			step, true, icons, count, ACAB.BUTTON_SIZE, 0
		)
		modernContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

		cursorY = cursorY - ACAB.BUTTON_SIZE - 14

		local checkbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardUseVanilla" .. nameKey .. "Checkbox", {
			anchor = { "TOP", step, "TOP", -60, cursorY },
			label = "Use Vanilla " .. barName,
			tooltip = {
				title = "Use Vanilla " .. barName,
				lines = {
					"While enabled, this addon's Hoverbind mode cannot bind keys on " ..
					"the " .. barName .. ". Use the real Blizzard Keybindings menu instead, or " ..
					"disable this option.",
				},
			},
			onClick = CheckboxToState(stateKey, "UpdateStep6PreviewStyle"),
		})

		return vanillaContainer, vanillaSlots, modernContainer, modernSlots, checkbox
	end

	step.vanillaStanceContainer, step.vanillaStanceSlots, step.modernStanceContainer,
		step.modernStanceSlots, step.stanceCheckbox =
		BuildBarModeSection("Stance Bar", "StanceBar", STEP6_STANCE_ICONS, STEP6_STANCE_PREVIEW_COUNT, "useNativeStanceBar")
	cursorY = cursorY - 24 - 30

	step.vanillaPetContainer, step.vanillaPetSlots, step.modernPetContainer,
		step.modernPetSlots, step.petCheckbox =
		BuildBarModeSection("Pet Bar", "PetBar", STEP6_PET_ICONS, STEP6_PET_PREVIEW_COUNT, "useNativePetBar")
	cursorY = cursorY - 24 - 14

	-- Styled Pet Bar mode only (see UpdateStep6PreviewStyle).
	step.condenseCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardCondensePetSlotsCheckbox", {
		anchor = { "TOP", step, "TOP", -60, cursorY },
		label = "Condense empty Button Space",
		onClick = CheckboxToState("condenseEmptyPetSlots", "UpdateStep6PetCondensePreview"),
	})

	CreateWizardNavButton(step, self, "Next", 24, 120, function()
		ACAB.setupWizard:ShowStep(7)
	end)

	return step
end

-- Step 7 (Modern Layout only): Experience Bar, same order as its settings page.
function ACABSetupWizardMixin:BuildStep7()
	local step = CreateStepFrame(self, "Set up your Experience Bar.")

	-- Every widget anchors to `step` at its own cursorY (never widget-to-widget) to stay centered.
	local cursorY = -18

	local enabledCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardExpBarEnabledCheckbox", {
		anchor = { "TOP", step, "TOP", -60, cursorY },
		label = "Enable Experience Bar",
		onClick = CheckboxToState("expBarEnabled", "UpdateStep7Visibility"),
	})
	cursorY = cursorY - 24 - 22

	local positionLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	positionLabel:SetPoint("TOP", step, "TOP", 0, cursorY)
	positionLabel:SetText("Where should your experience bar be:")
	cursorY = cursorY - 16 - 8

	local positionDropdown = ACAB:CreateInlineDropdown(step, 120, "ACABSetupWizardExpBarPositionDropdown")
	positionDropdown:ClearAllPoints()
	positionDropdown:SetPoint("TOP", step, "TOP", 0, cursorY)
	positionDropdown:SetOptions({ "Bottom", "Top" })
	positionDropdown.onSelect = function(value)
		ACAB.setupWizard.wizardState.expBarPositionChoice = value
	end
	cursorY = cursorY - 32 - 22

	local betterExpBarCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardBetterExpBarCheckbox", {
		anchor = { "TOP", step, "TOP", -80, cursorY },
		label = "Enable Better Experience Bar",
		onClick = CheckboxToState("betterExpBarEnabled", "UpdateStep7Visibility"),
	})
	cursorY = cursorY - 24 - 20

	local textToggleCheckboxes = {}
	local i

	for i = 1, table.getn(EXP_BAR_TEXT_TOGGLES) do
		local toggle = EXP_BAR_TEXT_TOGGLES[i]

		textToggleCheckboxes[i] = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardExpBar" .. toggle.key .. "Checkbox", {
			anchor = { "TOP", step, "TOP", -70, cursorY },
			label = toggle.label,
			onClick = CheckboxToState(toggle.key),
		})

		cursorY = cursorY - 24 - 6
	end

	cursorY = cursorY - 16

	-- Same range/step as the settings page's font size slider.
	local fontSizeLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	fontSizeLabel:SetPoint("TOP", step, "TOP", 0, cursorY)
	fontSizeLabel:SetText("Font Size")
	cursorY = cursorY - 16 - 8

	local fontSizeSlider, fontSizeValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardExpBarFontSizeSlider", {
		anchor = { "TOP", step, "TOP", 0, cursorY },
		width = 180,
		min = 6,
		max = 24,
		step = 1,
		lowText = "6",
		highText = "24",
		round = RoundToInteger,
		format = tostring,
		onChange = SliderToState("expBarFontSize"),
	})
	cursorY = cursorY - 20 - 14 - 22

	-- One color row: label + swatch opening the picker on wizardState[wizardKey].
	local function BuildColorRow(labelText, name, wizardKey)
		local label = step:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOP", step, "TOP", -70, cursorY)
		label:SetText(labelText)

		local swatch = ACAB:CreateColorSwatch(step, name)
		swatch:SetPoint("LEFT", label, "RIGHT", 12, 0)
		swatch:SetScript("OnClick", function()
			ACAB:OpenColorPicker(
				swatch,
				function() return ACAB.setupWizard.wizardState[wizardKey] end,
				function(r, g, b)
					ACAB.setupWizard.wizardState[wizardKey] = { r = r, g = g, b = b }
				end,
				ACAB.setupWizard
			)
		end)

		cursorY = cursorY - 24 - 14

		return label, swatch
	end

	local earnedColorLabel, earnedColorSwatch = BuildColorRow(
		"Earned XP Bar Color", "ACABSetupWizardExpBarEarnedColorSwatch", "expBarColorEarned"
	)
	local restedColorLabel, restedColorSwatch = BuildColorRow(
		"Rested XP Bar Color", "ACABSetupWizardExpBarRestedColorSwatch", "expBarColorRested"
	)
	local textColorLabel, textColorSwatch = BuildColorRow(
		"Overlay Text Color", "ACABSetupWizardExpBarTextColorSwatch", "expBarTextColor"
	)

	cursorY = cursorY - 2

	-- Same range as the settings page's rested-glow pulse slider.
	local pulseIntervalLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	pulseIntervalLabel:SetPoint("TOP", step, "TOP", 0, cursorY)
	pulseIntervalLabel:SetText("Rested Glow Pulse Interval")
	cursorY = cursorY - 16 - 8

	local pulseIntervalSlider, pulseIntervalValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardExpBarPulseIntervalSlider", {
		anchor = { "TOP", step, "TOP", 0, cursorY },
		width = 180,
		min = 0.5,
		max = 3,
		step = 0.1,
		lowText = "0.5",
		highText = "3.0",
		round = function(value) return math.floor((value * 10) + 0.5) / 10 end,
		format = function(value) return string.format("%.1f", value) end,
		onChange = SliderToState("expBarGlowPulseInterval"),
	})

	CreateWizardNavButton(step, self, "Next", 24, 120, function()
		ACAB.setupWizard:ShowStep(8)
	end)

	step.enabledCheckbox = enabledCheckbox
	step.positionLabel = positionLabel
	step.positionDropdown = positionDropdown
	step.betterExpBarCheckbox = betterExpBarCheckbox
	step.textToggleCheckboxes = textToggleCheckboxes
	step.fontSizeLabel = fontSizeLabel
	step.fontSizeSlider = fontSizeSlider
	step.fontSizeValueText = fontSizeValueText
	step.earnedColorLabel = earnedColorLabel
	step.earnedColorSwatch = earnedColorSwatch
	step.restedColorLabel = restedColorLabel
	step.restedColorSwatch = restedColorSwatch
	step.textColorLabel = textColorLabel
	step.textColorSwatch = textColorSwatch
	step.pulseIntervalLabel = pulseIntervalLabel
	step.pulseIntervalSlider = pulseIntervalSlider
	step.pulseIntervalValueText = pulseIntervalValueText

	return step
end

-- Step 8 (Modern Layout only): optional global spacing/button size with a live preview bar.
function ACABSetupWizardMixin:BuildStep8()
	local step, message = CreateStepFrame(self,
		"Optionally set a spacing and button size used by every bar. " ..
		"Leave either off to size that aspect per-bar instead - you can " ..
		"change both later in Settings.",
		44
	)

	local previewLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	previewLabel:SetPoint("TOP", message, "BOTTOM", 0, -10)
	previewLabel:SetText("Preview")

	-- Both style variants share one spot; UpdateStep8PreviewStyle shows the one matching step 3.
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

	-- Fixed clearance for the largest preview bar (BUTTON_SIZE_MAX), so rows below never shift.
	local PREVIEW_CLEARANCE = -(10 + ACAB.BUTTON_SIZE_MAX + 14)

	-- Rows anchor to previewLabel at their own cursorY; chaining off hidden siblings grows gaps on toggle.
	local CHECKBOX_HEIGHT = 24
	local SLIDER_HEIGHT = 17
	local cursorY = PREVIEW_CLEARANCE

	local spacingCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSpacingCheckbox", {
		anchor = { "TOP", previewLabel, "BOTTOM", -60, cursorY },
		label = "Enable global spacing",
		onClick = CheckboxToState("globalSpacingEnabled", "UpdateStep8SliderVisibility"),
	})
	cursorY = cursorY - CHECKBOX_HEIGHT - 14

	-- Same config as the General tab's global spacing slider.
	local spacingSlider, spacingValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardSpacingSlider", {
		anchor = { "TOP", previewLabel, "BOTTOM", 0, cursorY },
		width = 180,
		min = 0,
		max = ACAB.SPACING_MAX,
		step = ACAB.SPACING_STEP,
		initialText = "0",
		round = RoundToInteger,
		format = tostring,
		onChange = SliderToState("globalSpacingValue", "ReflowStep8Preview"),
	})
	spacingSlider:Hide()
	spacingValueText:Hide()
	cursorY = cursorY - SLIDER_HEIGHT - 22

	local sizeCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSizeCheckbox", {
		anchor = { "TOP", previewLabel, "BOTTOM", -60, cursorY },
		label = "Enable global button size",
		onClick = CheckboxToState("globalButtonSizeEnabled", "UpdateStep8SliderVisibility"),
	})
	cursorY = cursorY - CHECKBOX_HEIGHT - 14

	-- Same config as the General tab's global button size slider.
	local sizeSlider, sizeValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardSizeSlider", {
		anchor = { "TOP", previewLabel, "BOTTOM", 0, cursorY },
		width = 180,
		min = ACAB.BUTTON_SIZE_MIN,
		max = ACAB.BUTTON_SIZE_MAX,
		step = 1,
		lowText = tostring(ACAB.BUTTON_SIZE_MIN),
		highText = tostring(ACAB.BUTTON_SIZE_MAX),
		initialText = tostring(ACAB.BUTTON_SIZE),
		round = RoundToInteger,
		format = tostring,
		onChange = SliderToState("globalButtonSizeValue", "ReflowStep8Preview"),
	})
	sizeSlider:Hide()
	sizeValueText:Hide()

	step.spacingCheckbox = spacingCheckbox
	step.spacingSlider = spacingSlider
	step.spacingValueText = spacingValueText
	step.sizeCheckbox = sizeCheckbox
	step.sizeSlider = sizeSlider
	step.sizeValueText = sizeValueText

	CreateWizardNavButton(step, self, "Finish", 28, 140, function()
		ACAB.setupWizard:FinishWizard()
	end)

	return step
end

function ACABSetupWizardMixin:OnLoad()
	-- Same strata as ACABDialogMixin, above the settings window.
	self:SetFrameStrata("FULLSCREEN_DIALOG")
	self:SetWidth(WIZARD_WIDTH)
	self:SetHeight(INITIAL_HEIGHT)

	-- must stay TOP-anchored: FitHeightToStep measures from GetTop(), a CENTER anchor drifts on every resize
	self:SetPoint("TOP", UIParent, "TOP", 0, -80)

	self:SetBackdrop(ACAB.DIALOG_BACKDROP)

	self:EnableMouse(true)
	self:SetMovable(true)
	self:RegisterForDrag("LeftButton")
	self:SetScript("OnDragStart", function() this:StartMoving() end)
	self:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		this:NormalizeAnchorToTopLeft()
	end)

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

	-- Previous-step button (hidden on the first step, see ShowStep).
	self.backButton = CreateWizardButton(self, {
		text = "Back",
		height = 22,
		minWidth = 90,
		maxWidth = 90,
		anchor = { "BOTTOMLEFT", self, "BOTTOMLEFT", 20, 16 },
		variant = "danger",
		onClick = function()
			ACAB.setupWizard:GoToPreviousStep()
		end,
	})

	self.steps = {
		self:BuildStep1(),
		self:BuildStep2(),
		self:BuildStep3(),
		self:BuildStep4(),
		self:BuildStep5(),
		self:BuildStep6(),
		self:BuildStep7(),
		self:BuildStep8(),
	}

	local i

	-- Each step fills the wizard between the title/step text and the Back/Next row.
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

-- Resets wizard state/widgets for a fresh run; config.overwriteExisting edits config.profileName in place.
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
		pageSwapEnabled = true,
		stanceSwapEnabled = true,
		stancePreviewActive = 1,
		stancePreviewAssignment = { 1, 2, 3 },
		pagePreviewActive = false,
		pagePreviewAssignment = 1,
		generalLayoutFormat = nil,
		useNativeStanceBar = false,
		useNativePetBar = false,
		condenseEmptyPetSlots = false,
		expBarEnabled = true,
		expBarPositionChoice = "Bottom",
		betterExpBarEnabled = false,
		expBarShowLevel = true,
		expBarShowCurrentOverMax = true,
		expBarShowPercent = true,
		expBarShowRestedPercent = true,
		expBarShowRestedTotal = true,
		expBarFontSize = nil,
		expBarColorEarned = nil,
		expBarColorRested = nil,
		expBarTextColor = nil,
		expBarGlowPulseInterval = nil,
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
	local i

	step4.pageSwapCheckbox:SetChecked(true)
	step4.stanceSwapCheckbox:SetChecked(true)

	for i = 1, table.getn(step4.stanceDropdowns) do
		step4.stanceDropdowns[i]:SetSelected(i, STEP4_STANCE_PREVIEW_OPTIONS[i].text)
	end

	step4.pageDropdown:SetSelected(1, STEP4_STANCE_PREVIEW_OPTIONS[1].text)

	self:UpdateStep4Visibility()

	local step6 = self.steps[6]

	step6.stanceCheckbox:SetChecked(false)
	step6.petCheckbox:SetChecked(false)
	step6.condenseCheckbox:SetChecked(false)

	self:UpdateStep6PreviewStyle()

	local step7 = self.steps[7]

	step7.enabledCheckbox:SetChecked(true)
	step7.positionDropdown:SetOptions({ "Bottom", "Top" })
	step7.positionDropdown:SetSelected("Bottom")
	step7.betterExpBarCheckbox:SetChecked(false)

	for i = 1, table.getn(step7.textToggleCheckboxes) do
		step7.textToggleCheckboxes[i]:SetChecked(true)
	end

	-- Font size/pulse sliders display the current values; wizardState keeps nil unless the user moves them.
	ACAB:CaptureNativeExpBarFontIfNeeded()

	local nativeFontSize = ACAB.NATIVE_EXPBAR_FONT and (ACAB.NATIVE_EXPBAR_FONT.size - 1)

	local fontSize = ACAB:ClampFontSize(ACABDB.expBarFontSize or nativeFontSize or 12)
	local pulseInterval = ACABDB.expBarGlowPulseInterval or 1.5
	ACAB:SetSliderValueSilently(step7.fontSizeSlider, fontSize, step7.fontSizeValueText, tostring(fontSize))
	ACAB:SetSliderValueSilently(step7.pulseIntervalSlider, pulseInterval, step7.pulseIntervalValueText, string.format("%.1f", pulseInterval))

	ACAB:SetColorSwatchColor(step7.earnedColorSwatch, ACABDB.expBarColorEarned or { r = 0, g = 1, b = 0 })
	ACAB:SetColorSwatchColor(step7.restedColorSwatch, ACABDB.expBarColorRested or { r = 0.6, g = 0.2, b = 1 })
	ACAB:SetColorSwatchColor(step7.textColorSwatch, ACABDB.expBarTextColor or { r = 1, g = 0.82, b = 0 })

	self:UpdateStep7Visibility()

	local step8 = self.steps[8]
	step8.spacingCheckbox:SetChecked(false)
	step8.sizeCheckbox:SetChecked(false)

	ACAB:SetSliderValueSilently(step8.spacingSlider, 0, step8.spacingValueText, "0")
	ACAB:SetSliderValueSilently(step8.sizeSlider, ACAB.BUTTON_SIZE, step8.sizeValueText, tostring(ACAB.BUTTON_SIZE))

	self:UpdateStep8SliderVisibility()
end

function ACABSetupWizardMixin:ShowStep(n)
	local i

	for i = 1, table.getn(self.steps) do
		self.steps[i]:Hide()
	end

	self.currentStep = n

	-- Overwrite mode skips step 1, so steps display renumbered as "N of 7".
	local firstStep = self.wizardState.overwriteExisting and 2 or 1
	local totalSteps = self.wizardState.overwriteExisting and 7 or 8
	local displayStep = self.wizardState.overwriteExisting and (n - 1) or n

	self.stepText:SetText("Step " .. tostring(displayStep) .. " of " .. tostring(totalSteps) .. " - " .. (STEP_TITLES[n] or ""))
	self.backButton:SetShown(n > firstStep)

	local step = self.steps[n]

	if n == 4 then
		self:UpdateStep4PreviewStyle()
		self:UpdateStep4Preview()
	end

	if n == 6 then
		self:UpdateStep6PreviewStyle()
	end

	if n == 8 then
		self:UpdateStep8PreviewStyle()
	end

	step:Show()

	if n == 1 then
		step.editBox:SetFocus()
		step.editBox:HighlightText()
	end

	self:FitHeightToStep(n)
end

-- Every path through the wizard is linear, so Back is always currentStep - 1.
function ACABSetupWizardMixin:GoToPreviousStep()
	self:ShowStep(self.currentStep - 1)
end

-- Lowest GetBottom() among step's shown direct children/regions.
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

		-- must skip nav buttons: they anchor to the wizard, and counting them grows the wizard every fit
		if widget:IsShown() and not widget.ACABNavButton then
			local bottom = widget:GetBottom()

			if bottom and (not deepest or bottom < deepest) then
				deepest = bottom
			end
		end
	end

	return deepest
end

-- Re-anchors TOPLEFT at the wizard's current screen position after a drag.
-- must stay drag-end-only: a per-resize reanchor reads a stale GetTop() and compounds the height
function ACABSetupWizardMixin:NormalizeAnchorToTopLeft()
	local left = self:GetLeft()
	local top = self:GetTop()

	if left and top then
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
end

-- Resizes the wizard to fit step n's shown content, measured one frame later (skipped if the step changed).
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

-- Validates step 1's profile name and advances to step 2.
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

-- Shows step 4's stance rows / Page Swap Indicator / page row per the two checkboxes, then refreshes the preview.
function ACABSetupWizardMixin:UpdateStep4Visibility()
	local step = self.steps[4]
	local state = self.wizardState
	local i

	for i = 1, table.getn(step.stanceDropdownRows) do
		step.stanceDropdownRows[i]:SetShown(state.stanceSwapEnabled and true or false)
	end

	step.pageDropdownRow:SetShown(state.pageSwapEnabled and true or false)
	step.pageIndicator:SetShown(state.pageSwapEnabled and true or false)

	self:UpdateStep4Preview()

	if self.currentStep == 4 then
		self:FitHeightToStep(4)
	end
end

-- Shows step 4's vanilla or modern stance row + action bar, per step 3's choice.
function ACABSetupWizardMixin:UpdateStep4PreviewStyle()
	local step = self.steps[4]
	local isModern = self.wizardState.modernBorderStyle and true or false

	step.vanillaStanceContainer:SetShown(not isModern)
	step.modernStanceContainer:SetShown(isModern)
	step.vanillaActionBarContainer:SetShown(not isModern)
	step.modernActionBarContainer:SetShown(isModern)
end

-- Refreshes both variants' bar icons (Page 2 > stance assignment > stance 1) and active stance glow.
function ACABSetupWizardMixin:UpdateStep4Preview()
	local step = self.steps[4]
	local state = self.wizardState

	local activeStance = state.stancePreviewActive
	local showPage2 = (state.pageSwapEnabled and state.pagePreviewActive) and true or false

	step.pageIndicator.pageText:SetText(showPage2 and "2" or "1")

	local barStance = 1

	if showPage2 then
		barStance = state.pagePreviewAssignment
	elseif state.stanceSwapEnabled then
		barStance = state.stancePreviewAssignment[activeStance] or activeStance
	end

	local icons = STEP4_STANCE_ABILITIES[barStance].icons
	local i

	for i = 1, STEP4_BAR_SLOT_COUNT do
		step.vanillaActionBarSlots[i].icon:SetTexture(icons[i])
		step.modernActionBarSlots[i].icon:SetTexture(icons[i])
	end

	for i = 1, table.getn(step.vanillaStanceSlots) do
		local active = i == activeStance

		step.vanillaStanceSlots[i].glow:SetShown(active)
		step.modernStanceSlots[i].glow:SetShown(active)
	end
end

-- Shows step 6's previews per bar mode (native = vanilla art); Condense is shown for styled Pet Bar only.
function ACABSetupWizardMixin:UpdateStep6PreviewStyle()
	local step = self.steps[6]
	local state = self.wizardState

	local stanceModernBorder = (not state.useNativeStanceBar) and state.modernBorderStyle and true or false
	step.vanillaStanceContainer:SetShown(not stanceModernBorder)
	step.modernStanceContainer:SetShown(stanceModernBorder)

	local petStyled = not state.useNativePetBar
	local petModernBorder = petStyled and state.modernBorderStyle and true or false
	step.vanillaPetContainer:SetShown(not petModernBorder)
	step.modernPetContainer:SetShown(petModernBorder)

	step.condenseCheckbox:SetShown(petStyled)

	self:UpdateStep6PetCondensePreview()

	if self.currentStep == 6 then
		self:FitHeightToStep(6)
	end
end

-- Lays out both Pet Bar previews full width, then condenses the active one when Condense applies.
function ACABSetupWizardMixin:UpdateStep6PetCondensePreview()
	local step = self.steps[6]
	local state = self.wizardState

	local petStyled = not state.useNativePetBar
	local condensed = petStyled and state.condenseEmptyPetSlots and true or false
	local useModernBorder = petStyled and state.modernBorderStyle and true or false

	local activeSlots = useModernBorder and step.modernPetSlots or step.vanillaPetSlots
	local activeContainer = useModernBorder and step.modernPetContainer or step.vanillaPetContainer
	local activeSpacing = useModernBorder and 0 or VANILLA_PREVIEW_SPACING
	local inactiveSlots = useModernBorder and step.vanillaPetSlots or step.modernPetSlots
	local inactiveContainer = useModernBorder and step.vanillaPetContainer or step.modernPetContainer
	local inactiveSpacing = useModernBorder and VANILLA_PREVIEW_SPACING or 0

	local i

	for i = 1, STEP6_PET_PREVIEW_COUNT do
		activeSlots[i]:Show()
		inactiveSlots[i]:Show()
	end

	LayoutWizardPreviewSlots(inactiveSlots, ACAB.BUTTON_SIZE, inactiveSpacing)
	inactiveContainer:SetWidth(ComputePreviewBarWidth(ACAB.BUTTON_SIZE, inactiveSpacing, STEP6_PET_PREVIEW_COUNT))

	if not condensed then
		LayoutWizardPreviewSlots(activeSlots, ACAB.BUTTON_SIZE, activeSpacing)
		activeContainer:SetWidth(ComputePreviewBarWidth(ACAB.BUTTON_SIZE, activeSpacing, STEP6_PET_PREVIEW_COUNT))
		return
	end

	local visible = {}
	local n = 0

	for i = 1, STEP6_PET_PREVIEW_COUNT do
		if STEP6_PET_ICONS[i] then
			n = n + 1
			visible[n] = activeSlots[i]
		else
			activeSlots[i]:Hide()
		end
	end

	visible.container = activeSlots.container

	LayoutWizardPreviewSlots(visible, ACAB.BUTTON_SIZE, activeSpacing)
	activeContainer:SetWidth(ComputePreviewBarWidth(ACAB.BUTTON_SIZE, activeSpacing, n))
end

-- Shows step 7's controls per Enable Experience Bar, and the Better Experience Bar options per that checkbox.
function ACABSetupWizardMixin:UpdateStep7Visibility()
	local step = self.steps[7]
	local state = self.wizardState

	local enabled = state.expBarEnabled and true or false
	local betterShown = enabled and state.betterExpBarEnabled and true or false

	step.positionLabel:SetShown(enabled)
	step.positionDropdown:SetShown(enabled)
	step.betterExpBarCheckbox:SetShown(enabled)

	local i

	for i = 1, table.getn(step.textToggleCheckboxes) do
		step.textToggleCheckboxes[i]:SetShown(betterShown)
	end

	step.fontSizeLabel:SetShown(betterShown)
	step.fontSizeSlider:SetShown(betterShown)
	step.fontSizeValueText:SetShown(betterShown)
	step.earnedColorLabel:SetShown(betterShown)
	step.earnedColorSwatch:SetShown(betterShown)
	step.restedColorLabel:SetShown(betterShown)
	step.restedColorSwatch:SetShown(betterShown)
	step.textColorLabel:SetShown(betterShown)
	step.textColorSwatch:SetShown(betterShown)
	step.pulseIntervalLabel:SetShown(betterShown)
	step.pulseIntervalSlider:SetShown(betterShown)
	step.pulseIntervalValueText:SetShown(betterShown)

	if self.currentStep == 7 then
		self:FitHeightToStep(7)
	end
end

function ACABSetupWizardMixin:UpdateStep8SliderVisibility()
	local step = self.steps[8]
	local state = self.wizardState

	step.spacingSlider:SetShown(state.globalSpacingEnabled and true or false)
	step.spacingValueText:SetShown(state.globalSpacingEnabled and true or false)

	step.sizeSlider:SetShown(state.globalButtonSizeEnabled and true or false)
	step.sizeValueText:SetShown(state.globalButtonSizeEnabled and true or false)

	self:ReflowStep8Preview()

	if self.currentStep == 8 then
		self:FitHeightToStep(8)
	end
end

-- Shows step 8's vanilla or modern preview bar, per step 3's choice.
function ACABSetupWizardMixin:UpdateStep8PreviewStyle()
	local step = self.steps[8]
	local isModern = self.wizardState.modernBorderStyle and true or false

	step.vanillaBarContainer:SetShown(not isModern)
	step.modernBarContainer:SetShown(isModern)
end

-- Re-lays out both step 8 preview bars from the current spacing/size values.
function ACABSetupWizardMixin:ReflowStep8Preview()
	local step = self.steps[8]
	local state = self.wizardState

	local buttonSize = (state.globalButtonSizeEnabled and state.globalButtonSizeValue) or ACAB.BUTTON_SIZE
	local sliderSpacing = (state.globalSpacingEnabled and state.globalSpacingValue) or 0

	-- Same as Bar.lua's ApplyGlobalSpacingToBar: vanilla adds VANILLA_SPACING_FLOOR, modern has no floor.
	local vanillaSpacing = ACAB.VANILLA_SPACING_FLOOR + sliderSpacing
	local modernSpacing = sliderSpacing

	local vanillaWidth = ComputePreviewBarWidth(buttonSize, vanillaSpacing, PREVIEW_SLOT_COUNT)
	local modernWidth = ComputePreviewBarWidth(buttonSize, modernSpacing, PREVIEW_SLOT_COUNT)

	LayoutWizardPreviewSlots(step.vanillaBarSlots, buttonSize, vanillaSpacing)
	step.vanillaBarContainer:SetHeight(buttonSize)
	step.vanillaBarContainer:SetWidth(vanillaWidth)

	LayoutWizardPreviewSlots(step.modernBarSlots, buttonSize, modernSpacing)
	step.modernBarContainer:SetHeight(buttonSize)
	step.modernBarContainer:SetWidth(modernWidth)
end

-------------------------------------------------------------------------
-- Applying wizard state
-------------------------------------------------------------------------

-- Writes step 7's Experience Bar choices onto data; Better Experience Bar fields only when enabled.
local function ApplyExpBarWizardState(state, data)
	if state.expBarEnabled ~= nil then
		data.expBarEnabled = state.expBarEnabled
	end

	-- Centered at the bottom or top of the settings page's own Y range.
	if state.expBarEnabled and state.expBarPositionChoice then
		local frame = getglobal(ACAB.EXP_BAR_FRAME_NAME)
		local minX, maxX, minY, maxY = ACAB:GetSimpleElementCoordinateRange(frame, 2)

		if minX and maxX and minY and maxY then
			data.expBarPosition = {
				point = "CENTER", relativePoint = "CENTER", visualCenter = true,
				x = 0,
				y = (state.expBarPositionChoice == "Top") and maxY or minY,
			}
		end
	end

	data.betterExpBarEnabled = state.betterExpBarEnabled and true or false

	if state.betterExpBarEnabled then
		local i

		for i = 1, table.getn(EXP_BAR_TEXT_TOGGLES) do
			local key = EXP_BAR_TEXT_TOGGLES[i].key

			data[key] = state[key]
		end

		for i = 1, table.getn(EXP_BAR_OPTIONAL_KEYS) do
			local key = EXP_BAR_OPTIONAL_KEYS[i]

			if state[key] then
				data[key] = state[key]
			end
		end
	end
end

-- Modern Layout's non-geometry flags: bar art off, Snap to Grid/Adjacent Elements off.
local function ApplyModernLayoutPreset(data)
	data.mainBarArtMode = ACAB.MAIN_BAR_ART_MODE_DISABLED
	data.snapToGrid = false
	data.snapToAdjacentElements = false
end

-- Applies Modern Layout geometry to the live ACABDB (the target profile) via the per-element reset functions.
function ACAB:ApplyModernLayoutGeometry()
	self:ApplyModernMainActionBarsLayout()
	self:ApplyModernVerticalBarClusterLayout()

	self:ResetPetBarLayoutToModernBase()
	self:ResetStanceBarPositionToModernBase()

	self:ResetPageIndicatorToModernBase()

	self:ApplyModernCornerClusterLayout()
end

-- Writes every wizard choice onto profile data (shared by FinishWizard's create and overwrite paths).
local function ApplyWizardStateToProfileData(state, data)
	data.useDefaultLayout = state.useDefaultLayout

	if state.modernBorderStyle ~= nil then
		data.modernBorderStyle = state.modernBorderStyle

		-- must match modernBorderStyle, or next login treats it as a live style switch and shifts every default bar
		data.lastAppliedVanillaStyle = not state.modernBorderStyle
	end

	-- Step 4 is only visited on the unlocked path.
	if state.useDefaultLayout == false then
		data.defaultBarPaginationEnabled = state.pageSwapEnabled
		data.defaultBarStanceSwapEnabled = state.stanceSwapEnabled
	end

	-- Step 8 writes the chosen global spacing/size; earlier finishes force the defaults.
	if state.finishedFromStep8 then
		data.globalSpacingEnabled = state.globalSpacingEnabled
		data.globalSpacingValue = state.globalSpacingValue
		data.globalButtonSizeEnabled = state.globalButtonSizeEnabled
		data.globalButtonSizeValue = state.globalButtonSizeValue
	else
		data.globalSpacingEnabled = false
		data.globalSpacingValue = 0
		data.globalButtonSizeEnabled = false
		data.globalButtonSizeValue = ACAB.BUTTON_SIZE
	end

	-- Steps 6-7 only apply to Modern Layout; "blizzard" is reset live in ApplyGeneralLayoutFormat.
	if state.generalLayoutFormat == "modern" then
		data.defaultBars = data.defaultBars or {}

		local stanceCfg = data.defaultBars[ACAB.STANCE_BAR_ID]

		if stanceCfg then
			stanceCfg.useNativeStanceBar = state.useNativeStanceBar
		end

		local petCfg = data.defaultBars[ACAB.PET_BAR_ID]

		if petCfg then
			petCfg.useNativePetBar = state.useNativePetBar
			petCfg.condenseEmptyPetSlots = state.condenseEmptyPetSlots
		end

		ApplyExpBarWizardState(state, data)
		ApplyModernLayoutPreset(data)
	end
end

-- Applies step 5's layout choice onto the live ACABDB (must already be the target profile).
local function ApplyGeneralLayoutFormat(state)
	if state.generalLayoutFormat == "modern" then
		ACAB:ApplyModernLayoutGeometry()
	elseif state.generalLayoutFormat == "blizzard" then
		-- Resets any inherited Modern Layout data to the vanilla baseline.
		ACAB:ResetAllElementsToVanillaLayout()

		-- must run after the reset above, which forces page/stance swap back on
		if state.useDefaultLayout == false then
			ACAB:SetDefaultBarPaginationEnabled(state.pageSwapEnabled)
			ACAB:SetDefaultBarStanceSwapEnabled(state.stanceSwapEnabled)
		end
	end
end

-- Creates (or overwrites) the profile from wizardState and reloads; a name clash returns to step 1.
function ACABSetupWizardMixin:FinishWizard()
	local state = self.wizardState
	state.finishedFromStep8 = (self.currentStep == 8)

	if state.overwriteExisting then
		ACABDB = ACABDB or {}
		ApplyWizardStateToProfileData(state, ACABDB)
		ApplyGeneralLayoutFormat(state)

		ACAB:SaveActiveProfileData()

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

	-- Saves the old active profile before switching away (same as ACAB:SwitchProfile).
	ACAB:SaveActiveProfileData()

	-- Points live ACABDB at the new profile without reloading, so layout geometry can apply to live bars.
	ACAB.activeProfileName = state.profileName
	ACABDB = ACAB:DeepCopyTable(ACABProfilesDB[state.profileName])

	-- must re-point every bar.config at the new ACABDB, or layout writes land in orphaned tables
	if ACAB.bars then
		local barId, bar

		for barId, bar in pairs(ACAB.bars) do
			local cfg = ACAB:GetBarConfig(barId)

			if cfg then
				bar.config = cfg
			end
		end
	end

	ApplyGeneralLayoutFormat(state)

	ACABCharDB = ACABCharDB or {}
	ACABCharDB.activeProfile = state.profileName
	ACABCharDB.hasSelectedProfileBefore = true

	ACAB:SaveActiveProfileData()

	ReloadUI()
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

-- Opens the wizard fresh; config (optional) = { overwriteExisting = true, profileName = "..." }.
function ACAB:ShowSetupWizard(config)
	local wizard = EnsureSetupWizardFrame()

	wizard:Reset(config)
	wizard:Show()
	wizard:ShowStep(wizard.wizardState.overwriteExisting and 2 or 1)

	return wizard
end
