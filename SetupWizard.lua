-- SetupWizard.lua
-- Multi-step first-custom-profile setup wizard (ACAB:ShowSetupWizard), launched
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
-- Cosmetic (non-interactive) preview bars used by steps 3 and 6 - built
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
-- place, without recreating any texture - used by step 7's live slider
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
-- Step 4's example Stance Bar/Page Swap Indicator - a purely cosmetic,
-- wizard-local live demo, not the real Blizzard/ACAB frames (those are
-- process-wide singletons already positioned elsewhere on screen, so a
-- second preview instance can't wrap them). "Battle/Defensive/Berserker
-- Stance" are illustrative examples, not read from the player's real
-- spellbook/class - this step's dropdowns are cosmetic for the same
-- reason (see BuildStep4's own comment on that).
-------------------------------------------------------------------------

-- stanceIcon is the stance BUTTON's own fixed icon (never changes, even
-- when its dropdown remaps which stance's abilities it previews) - icons
-- is that stance's own example ability bar. Kept as two separate fields
-- since they aren't always the same art (Defensive/Berserker's own
-- stance icon isn't either stance's first ability icon).
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

-- Same visual recipe as CreateWizardPreviewSlot, but clickable (an
-- overlaid Button, not a plain Frame) with a togglable selection glow -
-- used for step 4's 3 example stance buttons.
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

-- One vanilla/modern-skinned row of the 3 example stance buttons -
-- returns the container (caller anchors it) and the slots array, same
-- shape as CreateWizardPreviewBar's own return.
local function BuildStep4StanceRow(parent, isModern, onStanceClick)
	local stanceSize = 28
	local stanceSpacing = 4
	local count = table.getn(STEP4_STANCE_ABILITIES)

	local container = CreateFrame("Frame", nil, parent)
	container:SetHeight(stanceSize)
	container:SetWidth(ComputePreviewBarWidth(stanceSize, stanceSpacing, count))

	local slots = {}
	slots.container = container

	local s

	for s = 1, count do
		local stanceIndex = s

		slots[s] = CreateWizardStanceSlot(
			container, isModern, STEP4_STANCE_ABILITIES[s].stanceIcon,
			function() onStanceClick(stanceIndex) end
		)
	end

	LayoutWizardPreviewSlots(slots, stanceSize, stanceSpacing)

	return container, slots
end

-- Small cosmetic replica of the real Page Indicator (ActionBarUpButton/
-- ActionBarDownButton/MainMenuBarPageNumber, NativeElements.lua) - those
-- are real, process-wide singleton frames already positioned elsewhere on
-- screen, not something a second preview instance can wrap, so this is a
-- standalone lookalike built from the same standard scroll-arrow
-- templates instead. Clicking either arrow toggles the wizard's own
-- simulated page (there are only ever 2: Page 1/Page 2).
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

-- The 4 rows' (3 stances + Page 2) own dropdown choices - picks which of
-- the 3 example stances' ability set that row previews: for a stance row,
-- when its own button is clicked; for the Page 2 row, when Page 2 is
-- toggled active. Actually demonstrates re-assigning a stance/page's bar
-- content (the real feature this step explains) instead of just
-- mirroring the real settings page's unrelated Extra Bar option labels.
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
-- Step 6's "Better Experience Bar" color pickers - a wizard-local copy of
-- SettingsBars.lua's own CreateColorSwatchButton/SetColorSwatchColor/
-- OpenExpBarColorPicker (all file-local there): same small swatch button
-- and native ColorPickerFrame wiring, but anchored to the wizard frame
-- instead of ACAB.settingsFrame (SettingsBars.lua's version hardcodes
-- that anchor, which would be wrong - or simply absent - when opened from
-- here), and writing into a caller-supplied setter instead of ACABDB
-- directly, so this step can defer the actual write to FinishWizard like
-- every other wizard control.
-------------------------------------------------------------------------

local function CreateWizardColorSwatch(parent, name)
	local swatch = CreateFrame("Button", name, parent)

	swatch:SetWidth(24)
	swatch:SetHeight(24)

	swatch:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = { left = 1, right = 1, top = 1, bottom = 1 },
	})
	swatch:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

	local tex = swatch:CreateTexture(nil, "ARTWORK")

	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetPoint("TOPLEFT", swatch, "TOPLEFT", 2, -2)
	tex:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -2, 2)

	swatch.colorTexture = tex

	return swatch
end

local function SetWizardColorSwatchColor(swatch, color)
	if not swatch or not swatch.colorTexture or not color then
		return
	end

	swatch.colorTexture:SetVertexColor(color.r or 1, color.g or 1, color.b or 1)
end

-- getter/setter: getter() returns the current {r,g,b} (or nil), setter(r,g,b)
-- stores a new one - same vanilla 1.12 ColorPickerFrame API (SetColorRGB/
-- func/opacityFunc/cancelFunc/hasOpacity) SettingsBars.lua's own picker uses.
local function OpenWizardColorPicker(swatch, getter, setter)
	local current = getter() or { r = 1, g = 1, b = 1 }

	ColorPickerFrame.func = function()
		local r, g, b = ColorPickerFrame:GetColorRGB()

		setter(r, g, b)
		SetWizardColorSwatchColor(swatch, getter())
	end

	ColorPickerFrame.opacityFunc = function() end
	ColorPickerFrame.hasOpacity = false

	ColorPickerFrame.cancelFunc = function(previousValues)
		if previousValues then
			setter(previousValues.r, previousValues.g, previousValues.b)
			SetWizardColorSwatchColor(swatch, getter())
		end
	end

	ColorPickerFrame:SetColorRGB(current.r, current.g, current.b)

	ColorPickerFrame:ClearAllPoints()
	ColorPickerFrame:SetPoint("TOPLEFT", ACAB.setupWizard, "TOPRIGHT", 10, 0)
	ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")

	ShowUIPanel(ColorPickerFrame)
end

-------------------------------------------------------------------------
-- ACABSetupWizardMixin
-------------------------------------------------------------------------

ACABSetupWizardMixin = {}

local STEP_TITLES = {
	[1] = "Name Your Profile",
	[2] = "Force Default Blizzard Layout",
	[3] = "Button Style",
	[4] = "Stance / Page Swapping",
	[5] = "General Layout",
	[6] = "Experience Bar",
	[7] = "Spacing & Button Size",
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
	nextButton.ACABNavButton = true
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

	-- Vanilla's icon is flush to the full button frame (Button.lua's own
	-- Init) with the decorative border texture overlaid/overflowing past
	-- it, matching real vanilla action bars - shrinking the icon (a
	-- previous version of this) made it look tiny next to modern's. Still
	-- visually reads slightly smaller than modern's flush icon+backdrop
	-- footprint even at equal icon size, so modern gets +2px to match.
	local vanillaApparentSize = 30
	local modernApparentSize = vanillaApparentSize + 2
	local vanillaSpacing = 4
	local modernSpacing = 0

	local vanillaLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	vanillaLabel:SetPoint("TOP", message, "BOTTOM", -110, -26)
	vanillaLabel:SetText("Vanilla Style")

	local vanillaBar = CreateWizardPreviewBar(step, false, PREVIEW_SLOT_COUNT, vanillaApparentSize, vanillaSpacing)
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

	local modernBar = CreateWizardPreviewBar(step, true, PREVIEW_SLOT_COUNT, modernApparentSize, modernSpacing)
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

-- Order mirrors SettingsGeneral.lua's General tab: pagination checkbox
-- first, then stance-swap. The example bar/stance row/Page Swap Indicator
-- react live to both checkboxes and to clicking a stance/the page arrows
-- (UpdateStep4Preview) so the effect of each control is actually visible
-- before the user ever opens the real Bars Settings pages.
function ACABSetupWizardMixin:BuildStep4()
	local step = CreateFrame("Frame", nil, self)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetHeight(30)
	message:SetJustifyH("CENTER")
	message:SetText(
		"Let each default bar (1-5) swap its own content per stance or " ..
		"Shift/Ctrl page. Try the example bar below."
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
		onClick = function()
			ACAB.setupWizard.wizardState.pageSwapEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep4Visibility()
		end,
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
		onClick = function()
			ACAB.setupWizard.wizardState.stanceSwapEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep4Visibility()
		end,
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
	-- No explicit SetHeight - wraps to however many lines it needs at
	-- WIZARD_CONTENT_WIDTH, so this clearance is generous (up to 3 lines)
	-- rather than measured, unlike every other fixed cursorY step in this
	-- wizard.
	cursorY = cursorY - 40 - 10

	-- Vanilla/modern variants of both the example stance row and action
	-- bar, built upfront - only the pair matching step 3's choice is ever
	-- shown (UpdateStep4PreviewStyle), same technique step 7's own
	-- preview bar already uses.
	local vanillaStanceContainer, vanillaStanceSlots = BuildStep4StanceRow(step, false, OnStanceClick)
	vanillaStanceContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	local modernStanceContainer, modernStanceSlots = BuildStep4StanceRow(step, true, OnStanceClick)
	modernStanceContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	cursorY = cursorY - 28 - 6

	local vanillaActionBarContainer, vanillaActionBarSlots = CreateWizardPreviewBar(
		step, false, STEP4_BAR_SLOT_COUNT, ACAB.BUTTON_SIZE, 0
	)
	vanillaActionBarContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	local modernActionBarContainer, modernActionBarSlots = CreateWizardPreviewBar(
		step, true, STEP4_BAR_SLOT_COUNT, ACAB.BUTTON_SIZE, 0
	)
	modernActionBarContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	-- Page Swap Indicator lookalike (CreateWizardPageIndicator) - anchored
	-- off the vanilla bar's own right edge; both bar variants share the
	-- same width/position so this stays correct either way.
	local pageIndicator = CreateWizardPageIndicator(step, function()
		ACAB.setupWizard.wizardState.pagePreviewActive = not ACAB.setupWizard.wizardState.pagePreviewActive
		ACAB.setupWizard:UpdateStep4Preview()
	end)
	pageIndicator:SetPoint("LEFT", vanillaActionBarContainer, "RIGHT", 14, 0)

	cursorY = cursorY - ACAB.BUTTON_SIZE - 16

	-- 3 stance-preview rows (each picks which of the 3 example stances'
	-- ability set that row's own stance button shows when clicked) + 1
	-- Page 2 row (picks which example stance's ability set Page 2 shows
	-- when toggled active) - see STEP4_STANCE_PREVIEW_OPTIONS. All 4 are
	-- gated on the two checkboxes above (UpdateStep4Visibility), same
	-- CreateStep4StancePreviewRow builder so all 4 line up identically.
	-- None of this is written to ACABDB, since these 3 example stances
	-- are illustrative only and don't correspond to any particular
	-- class's real stance/form indices (a Rogue's stance 1 isn't "Battle
	-- Stance"). The real per-class assignment rows on each default bar's
	-- own Bars Settings page are where this actually gets configured,
	-- after the wizard finishes (see the disclaimer text above).
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

	-- Bottom-right of the wizard, same row/style as every other step's
	-- advance button.
	local nextButton = CreateFrame("Button", nil, step)
	nextButton:SetHeight(24)
	ACAB:StyleModernButton(nextButton, 120, 120)
	nextButton:SetText("Next")
	nextButton:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -20, 16)
	nextButton.ACABNavButton = true
	ACAB:ApplyProminentButtonHighlight(nextButton)
	nextButton:SetScript("OnClick", function()
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

function ACABSetupWizardMixin:BuildStep5()
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
		ACAB.setupWizard:ShowStep(6)
	end)

	return step
end

-- Order mirrors ExperienceBar.lua/SettingsBars.lua's own Experience Bar
-- settings page: Enabled, then (if enabled) a position choice, then
-- "Better Experience Bar" and (if enabled) everything it unlocks there -
-- 5 text-segment checkboxes, a font size slider, 3 color swatches, and a
-- rested-glow pulse interval slider. Every control here writes into
-- wizardState only; nothing is applied live or to ACABDB until
-- FinishWizard (see ApplyExpBarWizardState).
function ACABSetupWizardMixin:BuildStep6()
	local step = CreateFrame("Frame", nil, self)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText("Set up your Experience Bar.")

	-- Every widget below is anchored directly to `step` (a fixed, stable
	-- reference) at its own computed cursorY, never chained widget-to-
	-- widget - a long relative-anchor chain drifted further off-center
	-- with each additional link (confirmed live: each successive text-
	-- toggle checkbox below crept further left than the last). Mirrors
	-- SettingsBars.lua's own cursorY-decrementing pattern for its real
	-- Experience Bar settings page.
	local cursorY = -18

	local enabledCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardExpBarEnabledCheckbox", {
		anchor = { "TOP", step, "TOP", -60, cursorY },
		label = "Enable Experience Bar",
		onClick = function()
			ACAB.setupWizard.wizardState.expBarEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep6Visibility()
		end,
	})
	cursorY = cursorY - 24 - 22

	local positionLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	positionLabel:SetPoint("TOP", step, "TOP", 0, cursorY)
	positionLabel:SetText("Where should your experience bar be:")
	cursorY = cursorY - 16 - 8

	-- Centered under its own label instead of beside it - beside it ran
	-- past the wizard's right edge.
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
		onClick = function()
			ACAB.setupWizard.wizardState.betterExpBarEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep6Visibility()
		end,
	})
	cursorY = cursorY - 24 - 20

	-- 5 independently toggleable text segments - same dbKey names as the
	-- real settings page, stacked in the same order.
	local TEXT_TOGGLES = {
		{ key = "expBarShowLevel", label = "Show Current Lvl" },
		{ key = "expBarShowCurrentOverMax", label = "Show Current XP / Max" },
		{ key = "expBarShowPercent", label = "Show Current % / Max" },
		{ key = "expBarShowRestedPercent", label = "Show Current Rested XP %" },
		{ key = "expBarShowRestedTotal", label = "Show Current Total Rested XP" },
	}

	local textToggleCheckboxes = {}
	local i

	for i = 1, table.getn(TEXT_TOGGLES) do
		local toggle = TEXT_TOGGLES[i]

		local checkbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardExpBar" .. toggle.key .. "Checkbox", {
			anchor = { "TOP", step, "TOP", -70, cursorY },
			label = toggle.label,
			onClick = function()
				ACAB.setupWizard.wizardState[toggle.key] = this:GetChecked() and true or false
			end,
		})

		textToggleCheckboxes[i] = checkbox
		cursorY = cursorY - 24 - 6
	end

	cursorY = cursorY - 16

	-- Font size slider - mirrors SettingsBars.lua's own range/step for
	-- this same control.
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
		round = function(value) return math.floor(value + 0.5) end,
		format = tostring,
		onChange = function(value, suppressApply)
			if not suppressApply then
				ACAB.setupWizard.wizardState.expBarFontSize = value
			end
		end,
	})
	cursorY = cursorY - 20 - 14 - 22

	-- 3 color swatches: Earned XP Bar Color, Rested XP Bar Color, Overlay
	-- Text Color - same order/labels as the real settings page.
	local function BuildColorRow(labelText, name, wizardKey)
		local label = step:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		label:SetPoint("TOP", step, "TOP", -70, cursorY)
		label:SetText(labelText)

		local swatch = CreateWizardColorSwatch(step, name)
		swatch:SetPoint("LEFT", label, "RIGHT", 12, 0)
		swatch:SetScript("OnClick", function()
			OpenWizardColorPicker(
				swatch,
				function() return ACAB.setupWizard.wizardState[wizardKey] end,
				function(r, g, b)
					ACAB.setupWizard.wizardState[wizardKey] = { r = r, g = g, b = b }
				end
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

	-- Rested-glow pulse interval - mirrors SettingsBars.lua's own range.
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
		onChange = function(value, suppressApply)
			if not suppressApply then
				ACAB.setupWizard.wizardState.expBarGlowPulseInterval = value
			end
		end,
	})

	-- Bottom-right of the wizard, same row/style as every other step's
	-- advance button.
	local nextButton = CreateFrame("Button", nil, step)
	nextButton:SetHeight(24)
	ACAB:StyleModernButton(nextButton, 120, 120)
	nextButton:SetText("Next")
	nextButton:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -20, 16)
	nextButton.ACABNavButton = true
	ACAB:ApplyProminentButtonHighlight(nextButton)
	nextButton:SetScript("OnClick", function()
		ACAB.setupWizard:ShowStep(7)
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

function ACABSetupWizardMixin:BuildStep7()
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
	-- ever shown (UpdateStep7PreviewStyle), so the bar the user sees here
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
	-- slider grows the bar - BUTTON_SIZE_MAX plus a margin. The vanilla
	-- border texture visually overflows past the slot (see
	-- CreateWizardPreviewSlot), but that's a texture on the SLOT, not the
	-- CONTAINER MeasureStepBottom actually measures - the container's own
	-- height is plain buttonSize (LayoutWizardPreviewSlots' own
	-- container:SetHeight), so reserving BORDER_RATIO's overflow on top of
	-- BUTTON_SIZE_MAX here was dead space this never needed.
	local PREVIEW_CLEARANCE = -(10 + ACAB.BUTTON_SIZE_MAX + 14)

	-- Every row below anchors directly to previewLabel (a fixed, always-
	-- shown reference) at its own computed cursorY, never chained widget-
	-- to-widget like this step used to - chaining sizeCheckbox off
	-- spacingSlider's BOTTOM (spacingSlider starts Hide()'n) fed a hidden
	-- sibling's own not-yet-resolved rect into the next row's anchor,
	-- growing further off on every show/hide toggle. Mirrors step 6's own
	-- cursorY-anchored-to-step fix for the identical bug there.
	-- CHECKBOX_HEIGHT/SLIDER_HEIGHT match CreateLabeledCheckbox/
	-- CreateSettingSlider's own fixed sizes.
	local CHECKBOX_HEIGHT = 24
	local SLIDER_HEIGHT = 17
	local cursorY = PREVIEW_CLEARANCE

	-- Stacked vertically (not side by side like the General settings
	-- page's own pair) - side by side here runs past the wizard's width.
	local spacingCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSpacingCheckbox", {
		anchor = { "TOP", previewLabel, "BOTTOM", -60, cursorY },
		label = "Enable global spacing",
		onClick = function()
			ACAB.setupWizard.wizardState.globalSpacingEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep7SliderVisibility()
		end,
	})
	cursorY = cursorY - CHECKBOX_HEIGHT - 14

	-- Mirrors SettingsGeneral.lua's own global-spacing slider config
	-- (step = ACAB.SPACING_STEP); the useDefaultLayout-driven display-offset
	-- that slider applies doesn't apply here since the wizard only reaches
	-- this step after useDefaultLayout has already been chosen "Disable".
	local spacingSlider, spacingValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardSpacingSlider", {
		anchor = { "TOP", previewLabel, "BOTTOM", 0, cursorY },
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
				ACAB.setupWizard:ReflowStep7Preview()
			end
		end,
	})
	spacingSlider:Hide()
	spacingValueText:Hide()
	cursorY = cursorY - SLIDER_HEIGHT - 22

	local sizeCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSizeCheckbox", {
		anchor = { "TOP", previewLabel, "BOTTOM", -60, cursorY },
		label = "Enable global button size",
		onClick = function()
			ACAB.setupWizard.wizardState.globalButtonSizeEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep7SliderVisibility()
		end,
	})
	cursorY = cursorY - CHECKBOX_HEIGHT - 14

	-- Mirrors SettingsGeneral.lua's own global-button-size slider config.
	local sizeSlider, sizeValueText = ACAB:CreateLabeledSlider(step, "ACABSetupWizardSizeSlider", {
		anchor = { "TOP", previewLabel, "BOTTOM", 0, cursorY },
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
				ACAB.setupWizard:ReflowStep7Preview()
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
	finishButton.ACABNavButton = true
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

	-- Anchored by TOP, not CENTER - a CENTER anchor moves the frame's own
	-- TOP edge every time FitHeightToStep resizes it (top = center +
	-- height/2), and FitHeightToStep's own measurement reads that same
	-- TOP edge as its reference point. Confirmed live as the cause of step
	-- 6 never shrinking back down after a checkbox reveal-then-hide: each
	-- resize's "top" reading could reflect the previous resize's own
	-- moved position before it had resolved, compounding upward. Anchoring
	-- by TOP instead keeps that edge fixed regardless of height, making it
	-- a stable measurement reference.
	self:SetPoint("TOP", UIParent, "TOP", 0, -80)

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
		self:BuildStep6(),
		self:BuildStep7(),
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
		pageSwapEnabled = true,
		stanceSwapEnabled = true,
		stancePreviewActive = 1,
		stancePreviewAssignment = { 1, 2, 3 },
		pagePreviewActive = false,
		pagePreviewAssignment = 1,
		generalLayoutFormat = nil,
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

	step6.enabledCheckbox:SetChecked(true)
	step6.positionDropdown:SetOptions({ "Bottom", "Top" })
	step6.positionDropdown:SetSelected("Bottom")
	step6.betterExpBarCheckbox:SetChecked(false)

	for i = 1, table.getn(step6.textToggleCheckboxes) do
		step6.textToggleCheckboxes[i]:SetChecked(true)
	end

	-- Font size/pulse interval sliders show a real current-session default
	-- (same lazy-nil idiom as the real settings page - ACAB.NATIVE_EXPBAR_FONT/
	-- the 1.5s pulse default) purely for display; wizardState's own field
	-- stays nil (no write at Finish) unless the user actually moves one.
	ACAB:CaptureNativeExpBarFontIfNeeded()

	local nativeFontSize = ACAB.NATIVE_EXPBAR_FONT and (ACAB.NATIVE_EXPBAR_FONT.size - 1)

	step6.fontSizeSlider.suppressApply = true
	step6.fontSizeSlider:SetValue(ACAB:ClampFontSize(ACABDB.expBarFontSize or nativeFontSize or 12))
	step6.fontSizeSlider.suppressApply = nil

	step6.pulseIntervalSlider.suppressApply = true
	step6.pulseIntervalSlider:SetValue(ACABDB.expBarGlowPulseInterval or 1.5)
	step6.pulseIntervalSlider.suppressApply = nil

	SetWizardColorSwatchColor(step6.earnedColorSwatch, ACABDB.expBarColorEarned or { r = 0, g = 1, b = 0 })
	SetWizardColorSwatchColor(step6.restedColorSwatch, ACABDB.expBarColorRested or { r = 0.6, g = 0.2, b = 1 })
	SetWizardColorSwatchColor(step6.textColorSwatch, ACABDB.expBarTextColor or { r = 1, g = 0.82, b = 0 })

	self:UpdateStep6Visibility()

	local step7 = self.steps[7]
	step7.spacingCheckbox:SetChecked(false)
	step7.sizeCheckbox:SetChecked(false)

	step7.spacingSlider.suppressApply = true
	step7.spacingSlider:SetValue(0)
	step7.spacingSlider.suppressApply = nil

	step7.sizeSlider.suppressApply = true
	step7.sizeSlider:SetValue(ACAB.BUTTON_SIZE)
	step7.sizeSlider.suppressApply = nil

	self:UpdateStep7SliderVisibility()
end

function ACABSetupWizardMixin:ShowStep(n)
	local i

	for i = 1, table.getn(self.steps) do
		self.steps[i]:Hide()
	end

	self.currentStep = n

	-- Overwrite mode skips step 1 (name is fixed to the current profile),
	-- so the displayed count is renumbered to "of 6" starting at 1 instead
	-- of showing a step 1 the user never saw, and Back has nothing to go
	-- back to until step 3. Total is the max reachable step regardless of
	-- mode - choosing "Keep Blizzard Layout" on step 5 or "Lock down
	-- default Elements!" on step 2 finishes without ever visiting step 6/7,
	-- same as this counter already not visiting every number in order.
	local firstStep = self.wizardState.overwriteExisting and 2 or 1
	local totalSteps = self.wizardState.overwriteExisting and 6 or 7
	local displayStep = self.wizardState.overwriteExisting and (n - 1) or n

	self.stepText:SetText("Step " .. tostring(displayStep) .. " of " .. tostring(totalSteps) .. " - " .. (STEP_TITLES[n] or ""))
	self.backButton:SetShown(n > firstStep)

	local step = self.steps[n]

	if n == 4 then
		self:UpdateStep4PreviewStyle()
		self:UpdateStep4Preview()
	end

	if n == 7 then
		self:UpdateStep7PreviewStyle()
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
-- Skips any widget flagged .ACABNavButton (each step's own Next/Finish
-- button) - that button is a child of `step` (so it shows/hides with it)
-- but is anchored to the WIZARD frame itself, not to `step`, so its own
-- position is a function of the wizard's current height. Counting it as
-- step content created a feedback loop: a taller wizard pushes the button
-- lower, which reads as "deeper" content, which computes an even taller
-- wizard - confirmed live as the exact cause of step 7's height growing
-- by a fixed amount on every single fit call.
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

		if widget:IsShown() and not widget.ACABNavButton then
			local bottom = widget:GetBottom()

			if bottom and (not deepest or bottom < deepest) then
				deepest = bottom
			end
		end
	end

	return deepest
end

-- Re-anchors TOPLEFT off UIParent's own BOTTOMLEFT at the wizard's current
-- on-screen position - called once, right after a drag ends (OnLoad's
-- OnDragStop), not on every resize. OnLoad's default TOP anchor alone kept
-- the top edge fixed across a plain SetHeight - but dragging the wizard
-- (StartMoving/StopMovingOrSizing) overwrites that anchor with one the
-- engine derives from the drop position, no longer guaranteed to be TOP-
-- anchored, which broke that assumption (confirmed live: the step 7
-- height-never-shrinks bug came back after dragging the wizard mid-
-- wizard). An earlier version of this fix re-ran this same capture-and-
-- reanchor on every single FitHeightToStep call instead of just once per
-- drag - confirmed live to itself be the cause of step 7's height
-- compounding larger on every checkbox toggle: GetTop() read right after a
-- ClearAllPoints/SetPoint pair doesn't reliably reflect the new anchor
-- yet on this client (the same "rects resolve lazily" quirk FitHeightToStep
-- already works around for step content), so each toggle's re-anchor could
-- read a still-stale, taller "top" and bake it in as the new anchor.
-- Confining the reanchor to drag-end only removes that repeated read/
-- write cycle entirely for the common (never-dragged) case.
function ACABSetupWizardMixin:NormalizeAnchorToTopLeft()
	local left = self:GetLeft()
	local top = self:GetTop()

	if left and top then
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
end

-- Resizes the wizard to fit step `n`'s actual current content instead of a
-- guessed-at fixed height - GetBottom() on content just Show()'n/re-shown
-- this same tick hasn't resolved on this client yet (confirmed live while
-- fixing the step 1 editBox/Next button not appearing at all - see this
-- branch's commit history), so the measurement is deferred one frame via
-- ACAB:DeferFit. Guarded on currentStep still matching `n` in case the
-- user already moved on by the time the deferred callback runs. Relies on
-- whatever anchor is already set (OnLoad's TOP anchor, or
-- NormalizeAnchorToTopLeft's TOPLEFT one post-drag) keeping the top edge
-- fixed on its own - see NormalizeAnchorToTopLeft's comment for why this
-- no longer re-touches the anchor itself.
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

-- Gates step 4's 3 stance-assignment rows/Page Swap Indicator/page-
-- assignment row on the Stance/Page checkboxes, same Show/Hide-on-
-- checkbox pattern as every other reveal-on-checkbox control in this
-- wizard - then refreshes the preview, since toggling either checkbox
-- also changes what the example bar should be showing.
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

-- Shows whichever of step 4's vanilla/modern stance row + action bar
-- pairs matches step 3's choice (wizardState.modernBorderStyle) and hides
-- the other - called from ShowStep whenever step 4 becomes visible, same
-- technique as step 7's own UpdateStep7PreviewStyle.
function ACABSetupWizardMixin:UpdateStep4PreviewStyle()
	local step = self.steps[4]
	local isModern = self.wizardState.modernBorderStyle and true or false

	step.vanillaStanceContainer:SetShown(not isModern)
	step.modernStanceContainer:SetShown(isModern)
	step.vanillaActionBarContainer:SetShown(not isModern)
	step.modernActionBarContainer:SetShown(isModern)
end

-- Refreshes the example action bar's 4 icons and which stance button
-- glows, from the current stance/page selection. The 3 stance buttons
-- are always clickable and always update which one glows, regardless of
-- the Stance/Form checkbox - that checkbox only gates whether the ACTION
-- BAR actually reacts to the click (off: always shows Battle Stance's
-- own content, same as a real bar that never swaps), matching what the
-- checkbox actually controls instead of disabling the buttons outright.
-- Toggling Page 2 doesn't block stance selection either - clicking a
-- stance still moves the glow and updates stancePreviewAssignment's
-- target, it just doesn't change the bar while Page 2's own content is
-- what's showing (same content-priority a real Shift/Ctrl page hold has
-- over the active stance). Both style variants' slots are updated
-- regardless of which is currently shown (see UpdateStep4PreviewStyle),
-- so either is already correct the moment the user switches which one
-- that shows.
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

-- Gates step 6's position dropdown/"Better Experience Bar" checkbox on
-- Enable Experience Bar, and its 5 text toggles/font size/3 color swatches/
-- pulse interval on Better Experience Bar itself - same two-level gating
-- as the real settings page's ApplyBetterExpBarGating, but Show/Hide
-- instead of dim, matching every other reveal-on-checkbox control already
-- in this wizard (step 7's spacing/size sliders).
function ACABSetupWizardMixin:UpdateStep6Visibility()
	local step = self.steps[6]
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

	if self.currentStep == 6 then
		self:FitHeightToStep(6)
	end
end

function ACABSetupWizardMixin:UpdateStep7SliderVisibility()
	local step = self.steps[7]
	local state = self.wizardState

	step.spacingSlider:SetShown(state.globalSpacingEnabled and true or false)
	step.spacingValueText:SetShown(state.globalSpacingEnabled and true or false)

	step.sizeSlider:SetShown(state.globalButtonSizeEnabled and true or false)
	step.sizeValueText:SetShown(state.globalButtonSizeEnabled and true or false)

	self:ReflowStep7Preview()

	if self.currentStep == 7 then
		self:FitHeightToStep(7)
	end
end

-- Shows whichever of step 7's two preview bars matches step 3's choice
-- (wizardState.modernBorderStyle) and hides the other - called from
-- ShowStep whenever step 7 becomes visible, so the bar shown here always
-- matches what the user actually picked.
function ACABSetupWizardMixin:UpdateStep7PreviewStyle()
	local step = self.steps[7]
	local isModern = self.wizardState.modernBorderStyle and true or false

	step.vanillaBarContainer:SetShown(not isModern)
	step.modernBarContainer:SetShown(isModern)
end

-- Recomputes the single active preview bar's slot layout from the current
-- spacing/size slider values (both aspects on the same bar, per whichever
-- step 3 picked) - updates both style variants' slots so either is
-- already correct whenever UpdateStep7PreviewStyle switches which is shown.
function ACABSetupWizardMixin:ReflowStep7Preview()
	local step = self.steps[7]
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

-- Applies step 6's Experience Bar choices onto `data`: Enabled, and (if
-- enabled) position - centered at the bottom or top of the screen, via
-- the exact same min/max Y the real Experience Bar settings page's own
-- slider would allow (ACAB:GetSimpleElementCoordinateRange, called live
-- against the real frame - safe to do before this profile's ReloadUI,
-- since the range only depends on screen size/scale and the exp bar
-- frame's own size, neither of which this wizard changes). "Better
-- Experience Bar" and everything it unlocks on that same page (5 text
-- toggles, font size, 3 colors, rested-glow pulse interval) is only
-- written when enabled - untouched fields are left alone, so the profile
-- just keeps whatever it already had for anything the user didn't touch.
local function ApplyExpBarWizardState(state, data)
	if state.expBarEnabled ~= nil then
		data.expBarEnabled = state.expBarEnabled
	end

	if state.expBarEnabled and state.expBarPositionChoice then
		local frame = getglobal(ACAB.EXP_BAR_FRAME_NAME)
		local minX, maxX, minY, maxY = ACAB:GetSimpleElementCoordinateRange(frame, 2)

		if minX and maxX and minY and maxY then
			data.expBarPosition = {
				point = "TOPLEFT", relativePoint = "BOTTOMLEFT",
				x = (minX + maxX) / 2,
				y = (state.expBarPositionChoice == "Top") and maxY or minY,
			}
		end
	end

	data.betterExpBarEnabled = state.betterExpBarEnabled and true or false

	if state.betterExpBarEnabled then
		data.expBarShowLevel = state.expBarShowLevel
		data.expBarShowCurrentOverMax = state.expBarShowCurrentOverMax
		data.expBarShowPercent = state.expBarShowPercent
		data.expBarShowRestedPercent = state.expBarShowRestedPercent
		data.expBarShowRestedTotal = state.expBarShowRestedTotal

		if state.expBarFontSize then
			data.expBarFontSize = state.expBarFontSize
		end

		if state.expBarColorEarned then
			data.expBarColorEarned = state.expBarColorEarned
		end

		if state.expBarColorRested then
			data.expBarColorRested = state.expBarColorRested
		end

		if state.expBarTextColor then
			data.expBarTextColor = state.expBarTextColor
		end

		if state.expBarGlowPulseInterval then
			data.expBarGlowPulseInterval = state.expBarGlowPulseInterval
		end
	end
end

-- Applies the "Modern Layout" preset (step 4's second choice) onto `data`
-- - disables Blizzard's bar art, stacks the Main Bar + Action Bar 1/2
-- (default bar ids 1/2/3, enabling 2/3) centered at the bottom of the
-- screen (shifted up to clear the Experience Bar if step 6 put it there
-- too - state.expBarEnabled/expBarPositionChoice, decided before this
-- runs), aligns the Stance Bar/Pet Bar directly above Action Bar 2 (left/
-- right edges respectively), and clusters Bag Bar (flush in the corner)/
-- Micro Menu (stacked on top of it)/Key Ring (to its left)/Latency Bar
-- (to Micro Menu's left, top-aligned with it) in the bottom-right corner.
--
-- Every position is expressed relative to UIParent's own corners, the
-- same coordinate space ACAB:CaptureNativeAnchor and
-- ACAB:ApplyBarPosition/ApplyBagBarPosition/ApplyLatencyBarPosition/
-- ApplyKeyRingPosition/ApplyStanceBarPosition/ApplyPetBarNativePosition
-- already use (Database.lua/Bar.lua/NativeElements.lua/PetStanceBars.lua)
-- - UIParent's own dimensions are already resolution/UI-scale-corrected,
-- so a BOTTOM or BOTTOMRIGHT anchor with a small fixed offset lands in
-- the same relative spot on any screen/scale, with no
-- GetScreenWidth()/uiScale math needed.
--
-- Bag Bar/Micro Menu/Key Ring/Latency Bar's real rendered size (bag
-- count, native icon size) isn't something this addon controls or knows
-- in advance, but their live containers already exist THIS session
-- (built at this login, before any of this runs) - reading their current
-- real GetWidth()/GetHeight() here is safe (size doesn't depend on the
-- position this function is about to set) and exact, unlike guessing a
-- size from cols/buttonSize. Every gap in this corner cluster is flush
-- (0) - confirmed against a reference profile export of a live-built
-- Modern Layout.
local function ApplyModernLayoutPreset(state, data)
	data.disableBlizzardArt = true

	-- Bag Bar sits exactly flush with the screen's corner below - a
	-- natural target for the Edit Mode "Snap to Grid"/"Snap to Adjacent
	-- Elements" features (DefaultBars.lua's ApplyDragSnap, on by default),
	-- which fight any attempt to manually drag it away again afterward.
	-- Off here so this profile doesn't fight your own later adjustments.
	data.snapToGrid = false
	data.snapToAdjacentElements = false

	local buttonSize = (data.globalButtonSizeEnabled and data.globalButtonSizeValue) or ACAB.BUTTON_SIZE
	local spacing = (data.globalSpacingEnabled and data.globalSpacingValue) or 0
	local rowGap = 6
	local bottomMargin = 4

	local expBarClearance = 0

	if state.expBarEnabled and state.expBarPositionChoice == "Bottom" then
		local expBarFrame = getglobal(ACAB.EXP_BAR_FRAME_NAME)
		local expBarHeight = (expBarFrame and expBarFrame:GetHeight()) or 20

		expBarClearance = expBarHeight + rowGap
	end

	data.defaultBars = data.defaultBars or {}

	-- buttonSize/spacing pinned explicitly onto all 3 stacked bars' own
	-- cfg, not left at whatever CreateProfile's deep-copy of the Default
	-- profile happened to carry (the real native-captured size, which
	-- isn't ACAB.BUTTON_SIZE) - every width/height below assumes all 3
	-- bars render at exactly `buttonSize`/`spacing`, so this makes that
	-- true instead of just hoping it already is. Harmless even when the
	-- global spacing/size toggle is also on, since it's the same value
	-- that toggle would apply anyway.
	local mainBarCfg = data.defaultBars[1] or {}
	mainBarCfg.point = "BOTTOM"
	mainBarCfg.relativePoint = "BOTTOM"
	mainBarCfg.x = 0
	mainBarCfg.y = bottomMargin + expBarClearance
	mainBarCfg.buttonSize = buttonSize
	mainBarCfg.spacing = spacing
	data.defaultBars[1] = mainBarCfg

	local actionBar1Cfg = data.defaultBars[2] or {}
	actionBar1Cfg.enabled = true
	actionBar1Cfg.point = "BOTTOM"
	actionBar1Cfg.relativePoint = "BOTTOM"
	actionBar1Cfg.x = 0
	actionBar1Cfg.y = bottomMargin + expBarClearance + buttonSize + rowGap
	actionBar1Cfg.buttonSize = buttonSize
	actionBar1Cfg.spacing = spacing
	data.defaultBars[2] = actionBar1Cfg

	local actionBar2Y = bottomMargin + expBarClearance + ((buttonSize + rowGap) * 2)
	local actionBar2Cfg = data.defaultBars[3] or {}
	actionBar2Cfg.enabled = true
	actionBar2Cfg.point = "BOTTOM"
	actionBar2Cfg.relativePoint = "BOTTOM"
	actionBar2Cfg.x = 0
	actionBar2Cfg.y = actionBar2Y
	actionBar2Cfg.buttonSize = buttonSize
	actionBar2Cfg.spacing = spacing
	data.defaultBars[3] = actionBar2Cfg

	-- Action Bar 2 is a 12-column, 1-row grid (Core.lua's DEFAULT_BAR_GRID),
	-- centered (x=0/point=BOTTOM above), so its left/right edges sit this
	-- far either side of screen center.
	local actionBar2Width = (buttonSize * 12) + (spacing * 11)
	local actionBar2Top = actionBar2Y + buttonSize

	-- Stance Bar: directly above Action Bar 2, left edges aligned.
	data.stanceBarUsesDefaultPosition = false
	data.stanceBarPosition = {
		point = "BOTTOMLEFT", relativePoint = "BOTTOM",
		x = -(actionBar2Width / 2),
		y = actionBar2Top + rowGap,
	}

	-- Pet Bar: directly above Action Bar 2, right edges aligned. Its own
	-- position lives on defaultBars[PET_BAR_ID] (not a separate top-level
	-- field like Stance Bar) - see CLAUDE.md's architecture notes.
	local petBarCfg = data.defaultBars[ACAB.PET_BAR_ID] or {}
	petBarCfg.usesDefaultPosition = false
	petBarCfg.point = "BOTTOMRIGHT"
	petBarCfg.relativePoint = "BOTTOM"
	petBarCfg.x = actionBar2Width / 2
	petBarCfg.y = actionBar2Top + rowGap
	data.defaultBars[ACAB.PET_BAR_ID] = petBarCfg

	-- Page Swap Indicator: only positioned here when Page Bar-Changes is
	-- actually on (step 4) - flush to Main Bar's own right edge, vertically
	-- centered on it, same relationship the wizard's own step 4 preview
	-- shows (indicator anchored off the example bar's right edge). Main
	-- Bar (id 1) shares Action Bar 2's exact grid (12 cols, same
	-- buttonSize/spacing here), so actionBar2Width doubles as its width
	-- too. Container height read live the same way Bag Bar/Micro Menu's
	-- is - CreatePageIndicatorContainer's own overlay has no inset (unlike
	-- Latency Bar's), so the container's own GetHeight already matches its
	-- real hitbox with no gap correction needed.
	if state.pageSwapEnabled then
		local indicatorContainer = ACAB.pageIndicatorContainer
		local indicatorHeight = (indicatorContainer and indicatorContainer:GetHeight()) or buttonSize

		local mainBarCenterY = mainBarCfg.y + (buttonSize / 2)

		data.mainBarPageIndicatorPosition = {
			point = "BOTTOMLEFT", relativePoint = "BOTTOM",
			x = (actionBar2Width / 2) + rowGap,
			y = mainBarCenterY - (indicatorHeight / 2),
		}
	end

	-- Bag Bar: flush against the screen's bottom-right corner - no
	-- measurement needed, this is exact regardless of its real size.
	data.bagBarPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = 0, y = 0,
	}

	local bagBarWidth = (ACAB.bagBarContainer and ACAB.bagBarContainer:GetWidth()) or (5 * (buttonSize + spacing))
	local bagBarHeight = (ACAB.bagBarContainer and ACAB.bagBarContainer:GetHeight()) or buttonSize

	-- Key Ring: directly to Bag Bar's left, same row, flush. Anchored by
	-- its own right edge, so its own width doesn't factor into this.
	data.keyRingPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = -bagBarWidth, y = 0,
	}

	-- Micro Menu: stacked directly on top of Bag Bar, same right edge, flush.
	data.microMenuPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = 0, y = bagBarHeight,
	}

	local microMenuWidth = (ACAB.microMenuContainer and ACAB.microMenuContainer:GetWidth())
		or ((data.microMenuCols or 8) * (buttonSize + spacing))
	local microMenuHeight = (ACAB.microMenuContainer and ACAB.microMenuContainer:GetHeight()) or buttonSize

	-- microMenuPosition above stacks the CONTAINER (bagBarHeight above Bag
	-- Bar), but Micro Menu's own overlay hitbox - what "top" should
	-- actually mean here per the reference layout - sits inset from that
	-- container by a fixed pixel gap (chain-anchored containers trim their
	-- overlay to the real buttons' own hit-rects). That gap is a pure
	-- pixel offset, unaffected by where the container itself later moves
	-- to, so it's safe to read live right now and net it out of the
	-- target top used below.
	local microMenuOverlayTopGap = 0
	local microMenuOverlay = ACAB.microMenuContainer and ACAB.microMenuContainer.ACABOverlay

	if ACAB.microMenuContainer and microMenuOverlay then
		local containerTop = ACAB.microMenuContainer:GetTop()
		local overlayTop = microMenuOverlay:GetTop()

		if containerTop and overlayTop then
			microMenuOverlayTopGap = containerTop - overlayTop
		end
	end

	local microMenuOverlayTop = bagBarHeight + microMenuHeight - microMenuOverlayTopGap

	-- Same trimmed-hitbox reasoning as microMenuOverlayTopGap above, but
	-- for the right edge - Micro Menu's container right edge sits flush
	-- with the screen corner (microMenuPosition's own x=0 above), but its
	-- overlay's right edge is inset from that by its own fixed gap, and
	-- the overlay itself is narrower than the container.
	--
	-- Width comes from GetRight()-GetLeft(), never GetWidth() - confirmed
	-- live the overlay's own effective scale (inherited from the buttons
	-- it wraps, via EnsureContainerOverlay's ScaleRatio conversion) isn't
	-- always 1, so GetWidth() (the frame's raw, unscaled size) disagreed
	-- with GetRight()/GetLeft() (already scale-corrected, the same units
	-- microMenuRightGap and the x offset below are both in) by that scale
	-- factor - exactly why this addon's own PixelSetPoint/ScaleRatio exist
	-- elsewhere; this mixed them without going through either.
	local microMenuOverlayWidth = microMenuWidth
	local microMenuRightGap = 0

	if ACAB.microMenuContainer and microMenuOverlay then
		local containerRight = ACAB.microMenuContainer:GetRight()
		local overlayRight = microMenuOverlay:GetRight()
		local overlayLeft = microMenuOverlay:GetLeft()

		if containerRight and overlayRight then
			microMenuRightGap = containerRight - overlayRight
		end

		if overlayRight and overlayLeft then
			microMenuOverlayWidth = overlayRight - overlayLeft
		end
	end

	-- Micro Menu's overlay left edge, expressed as an offset from the
	-- screen's own right edge (same coordinate space latencyBarPosition.x
	-- below is set in, since both use a BOTTOMRIGHT/BOTTOMRIGHT anchor).
	local microMenuOverlayLeftOffset = -(microMenuRightGap + microMenuOverlayWidth)

	-- Latency Bar's real frame (MainMenuBarPerformanceBarFrame) is bigger
	-- than its visible art - NativeElements.lua trims that down with its
	-- own overlayInset when building the frame's hover/drag overlay
	-- (EnsureContainerOverlay), so that overlay's own GetTop()-GetBottom()
	-- is the true visual footprint, not the raw frame's. Uses Top/Bottom
	-- rather than GetHeight() for the same reason microMenuOverlayWidth
	-- does above - keeps every measurement in the same scale-corrected
	-- units the gaps below are computed in.
	local latencyBarFrame = getglobal(ACAB.LATENCY_BAR_FRAME_NAME)
	local latencyBarOverlay = latencyBarFrame and latencyBarFrame.ACABOverlay
	local latencyBarHeight = (latencyBarFrame and latencyBarFrame:GetHeight()) or (buttonSize * 0.5)

	local latencyBarOverlayBottomGap = 0
	local latencyBarOverlayRightGap = 0

	if latencyBarFrame and latencyBarOverlay then
		local frameBottom = latencyBarFrame:GetBottom()
		local overlayBottom = latencyBarOverlay:GetBottom()
		local overlayTop = latencyBarOverlay:GetTop()

		if frameBottom and overlayBottom then
			latencyBarOverlayBottomGap = overlayBottom - frameBottom
		end

		if overlayTop and overlayBottom then
			latencyBarHeight = overlayTop - overlayBottom
		end

		local frameRight = latencyBarFrame:GetRight()
		local overlayRight = latencyBarOverlay:GetRight()

		if frameRight and overlayRight then
			latencyBarOverlayRightGap = frameRight - overlayRight
		end
	end

	-- Latency Bar: its own overlay hitbox flush against Micro Menu's
	-- overlay hitbox on the left, top edges aligned (nudged down 5 units
	-- to read slightly better against Micro Menu's own icon row). x/y
	-- anchor the real frame's BOTTOMRIGHT (point/relativePoint above), not
	-- the overlay's, so both bars' own frame-to-overlay gaps are netted
	-- out to land the two overlay hitboxes flush/aligned, not the two
	-- underlying frames.
	data.latencyBarPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = microMenuOverlayLeftOffset + latencyBarOverlayRightGap,
		y = ((microMenuOverlayTop - latencyBarHeight) - latencyBarOverlayBottomGap) - 5,
	}
end

-- Applies wizardState.useDefaultLayout/modernBorderStyle/general layout
-- format/global spacing+size onto `data` - shared by FinishWizard's create
-- and overwrite branches.
local function ApplyWizardStateToProfileData(state, data)
	data.useDefaultLayout = state.useDefaultLayout

	if state.modernBorderStyle ~= nil then
		data.modernBorderStyle = state.modernBorderStyle

		-- Bar.lua's ApplyGlobalButtonStyle compares ACABDB.lastAppliedVanillaStyle
		-- against the CURRENT style every login, and silently shifts every
		-- default bar's buttonSize (+/-MODERN_BUTTON_SIZE_DELTA), position
		-- and spacing to compensate for a style switch - meant for a user
		-- flipping the style on an already-live profile mid-session, not a
		-- brand-new profile that never had a previous style. Left unset (or
		-- copied from whatever profile this data came from), it doesn't
		-- match the style this wizard just chose, so that compensation
		-- fired on the very next login and perturbed Action Bar 2 (and
		-- everything anchored off it below) by that same delta - confirmed
		-- live as the actual cause of Stance/Pet Bar's alignment being off,
		-- not the width/spacing math itself. Setting this to match now
		-- tells it nothing changed.
		data.lastAppliedVanillaStyle = not state.modernBorderStyle
	end

	-- Step 4 (Stance/Page Swapping) is only ever reached via step 2's
	-- "unlocked" path (useDefaultLayout false) - the locked-default path
	-- finishes immediately from step 2, so these checkboxes were never
	-- shown/confirmed there and the profile keeps whatever it already
	-- had, same deliberate no-op as generalLayoutFormat below. The 3
	-- stance dropdowns/1 page dropdown on that step are cosmetic-only
	-- (see BuildStep4's own comment) and never written here.
	if state.useDefaultLayout == false then
		data.defaultBarPaginationEnabled = state.pageSwapEnabled
		data.defaultBarStanceSwapEnabled = state.stanceSwapEnabled
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
	-- mode) exactly as is, and step 6 (Experience Bar) is never visited
	-- on that path so there's nothing from it to apply either.
	if state.generalLayoutFormat == "modern" then
		ApplyExpBarWizardState(state, data)
		ApplyModernLayoutPreset(state, data)
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
