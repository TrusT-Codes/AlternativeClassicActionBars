-- SetupWizard.lua
-- Multi-step first-custom-profile setup wizard (ACAB:ShowSetupWizard), launched from Database.lua's
-- ShowFirstLoginDialog "Set up a new custom Profile" button, or - in overwrite mode - from the
-- Profiles settings page's "Run Setup Wizard" button, which reconfigures the already-active profile in
-- place instead of creating a new one and skips the name step. One lazily-created frame instance is
-- reused across opens. Nothing is written to ACABProfilesDB/ACABDB until FinishWizard runs - closing
-- the wizard early leaves self.wizardState discarded and creates/changes nothing.
-- Engine-invoked script handlers receive the frame via the global `this`, never as a `self` parameter.

local ACAB = AlternativeClassicActionBars

local WIZARD_WIDTH = 480
local WIZARD_CONTENT_WIDTH = WIZARD_WIDTH - 40
local PREVIEW_SLOT_COUNT = 5

-- Real, long-standing ability icon paths (base Blizzard icon atlas, not tied to any one class) -
-- cycled across preview slots instead of every slot showing the same "?" icon. Not pulled from the
-- player's real spellbook - these are purely cosmetic previews.
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

-- 1-based cycle through PREVIEW_ICONS for slot index `n` - no `%` on this client (Lua 5.0), so
-- wraparound is done via floor division instead.
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

-- One cosmetic slot: vanilla style overlays Interface\Buttons\UI-Quickslot2 centered with a (0,-1)
-- offset over a flush icon, sized ACAB.BORDER_RATIO times the icon (real vanilla border art is drawn
-- larger than the icon it frames); modern style backdrops a tooltip-skinned border with a 2px-inset icon.
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

-- Resizes/repositions slots already created by CreateWizardPreviewBar in place, without recreating any
-- texture - used by step 8's live slider updates. slots.container is the bar's own container frame.
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

-- Builds a preview bar from an explicit per-slot icon list (nil = empty slot) instead of
-- CreateWizardPreviewBar's auto-recycled PreviewIconForSlot - used where the exact icon per slot
-- matters. `count` is passed explicitly since a Lua 5.0 array with nil holes can't be measured reliably.
local function CreateWizardIconRow(parent, isModern, icons, count, buttonSize, spacing)
	local container = CreateFrame("Frame", nil, parent)
	container:SetHeight(buttonSize)
	container:SetWidth(ComputePreviewBarWidth(buttonSize, spacing, count))

	local slots = {}
	slots.container = container

	local i

	for i = 1, count do
		slots[i] = CreateWizardPreviewSlot(container, isModern, icons[i])
	end

	LayoutWizardPreviewSlots(slots, buttonSize, spacing)

	return container, slots
end

-------------------------------------------------------------------------
-- Step 4's example Stance Bar/Page Swap Indicator - a purely cosmetic, wizard-local live demo, not the
-- real Blizzard/ACAB frames (those are process-wide singletons already positioned elsewhere on screen).
-- "Battle/Defensive/Berserker Stance" are illustrative examples, not read from the player's real class.
-------------------------------------------------------------------------

-- stanceIcon is the stance button's own fixed icon (never changes even when its dropdown remaps which
-- stance's abilities it previews) - icons is that stance's own example ability bar.
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

-- Step 6's example Stance Bar - the same 3 example stances' icons step 4 already uses, not read from
-- the player's real class/forms.
-- Real vanilla button art always overhangs its own frame bounds by at least this much regardless of a
-- stored 0 - same value step 3's own vanillaSpacing local uses, applied here so the vanilla-bordered
-- preview doesn't render tighter than its real on-screen look.
local STEP6_VANILLA_SPACING = 4

local STEP6_STANCE_PREVIEW_COUNT = table.getn(STEP4_STANCE_ABILITIES)
local STEP6_STANCE_ICONS = {
	STEP4_STANCE_ABILITIES[1].stanceIcon,
	STEP4_STANCE_ABILITIES[2].stanceIcon,
	STEP4_STANCE_ABILITIES[3].stanceIcon,
}

-- Step 6's example Pet Bar - the real vanilla 10-slot layout (3 command buttons, one learned-ability
-- example, 3 untrained/empty slots, 3 reaction buttons). Real icons need a real pet the wizard doesn't have.
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

-- Same visual recipe as CreateWizardPreviewSlot, but clickable with a togglable selection glow - used
-- for step 4's 3 example stance buttons.
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

-- One vanilla/modern-skinned row of the 3 example stance buttons - returns the container and the
-- slots array, same shape as CreateWizardPreviewBar's own return.
local function BuildStep4StanceRow(parent, isModern, onStanceClick)
	local stanceSize = 28
	-- Real vanilla button art overhangs its own frame bounds - same convention step 3's preview bar uses.
	local stanceSpacing = isModern and 0 or 4
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

-- The 4 rows' (3 stances + Page 2) own dropdown choices - picks which of the 3 example stances'
-- ability set that row previews. Actually demonstrates re-assigning a stance/page's bar content
-- instead of just mirroring the real settings page's unrelated Extra Bar option labels.
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
-- Step 7's "Better Experience Bar" color pickers - a wizard-local copy of SettingsBars.lua's own color
-- swatch/picker wiring, but anchored to the wizard frame instead of ACAB.settingsFrame, and writing
-- into a caller-supplied setter instead of ACABDB directly, so this step can defer the write to
-- FinishWizard like every other wizard control.
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

-- getter/setter: getter() returns the current {r,g,b} (or nil), setter(r,g,b) stores a new one - same
-- vanilla 1.12 ColorPickerFrame API SettingsBars.lua's own picker uses.
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
	[2] = "Force Vanilla Layout Mode",
	[3] = "Button Style",
	[4] = "Stance / Page Swapping",
	[5] = "General Layout",
	[6] = "Pet Bar / Stance Bar Mode",
	[7] = "Experience Bar",
	[8] = "Spacing & Button Size",
}

-- Starting height before the first real fit (FitHeightToStep) replaces it - only ever visible for one frame.
local INITIAL_HEIGHT = 200

-- Every step's own advance button (Next/Finish) - anchored to the wizard frame itself, so it stays in
-- the same bottom-right spot, same row as the shared Back button, regardless of step content height.
local function CreateWizardNavButton(step, wizard, text, height, minWidth, maxWidth, onClick)
	local button = CreateFrame("Button", nil, step)

	button:SetHeight(height)
	ACAB:StyleModernButton(button, minWidth, maxWidth)
	button:SetText(text)
	button:SetPoint("BOTTOMRIGHT", wizard, "BOTTOMRIGHT", -20, 16)
	button.ACABNavButton = true
	ACAB:ApplyProminentButtonHighlight(button)
	button:SetScript("OnClick", onClick)

	return button
end

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

	CreateWizardNavButton(step, self, "Next", 24, 120, 120, function()
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
		"Locks your bars to their native vanilla position and style, or " ..
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

	-- Vanilla's icon is flush to the full button frame with the decorative border texture overlaid
	-- past it, matching real vanilla action bars. Reads slightly smaller than modern's flush
	-- icon+backdrop footprint at equal icon size, so modern gets +2px to match.
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

-- Order mirrors SettingsGeneral.lua's General tab: pagination checkbox first, then stance-swap. The
-- example bar/stance row/Page Swap Indicator react live to both checkboxes and to clicking a
-- stance/the page arrows so the effect of each control is actually visible.
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
	-- No explicit SetHeight - wraps to however many lines it needs, so this clearance is generous (up
	-- to 3 lines) rather than measured, unlike every other fixed cursorY step in this wizard.
	cursorY = cursorY - 40 - 10

	-- Vanilla/modern variants of both the example stance row and action bar, built upfront - only the
	-- pair matching step 3's choice is ever shown, same technique step 8's own preview bar uses.
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

	-- Page Swap Indicator lookalike - anchored off the vanilla bar's own right edge; both bar variants
	-- share the same width/position so this stays correct either way.
	local pageIndicator = CreateWizardPageIndicator(step, function()
		ACAB.setupWizard.wizardState.pagePreviewActive = not ACAB.setupWizard.wizardState.pagePreviewActive
		ACAB.setupWizard:UpdateStep4Preview()
	end)
	pageIndicator:SetPoint("LEFT", vanillaActionBarContainer, "RIGHT", 14, 0)

	cursorY = cursorY - ACAB.BUTTON_SIZE - 16

	-- 3 stance-preview rows + 1 Page 2 row, all gated on the two checkboxes above, same
	-- CreateStep4StancePreviewRow builder so all 4 line up identically. None of this is written to
	-- ACABDB - these 3 example stances are illustrative only. The real per-class assignment rows on
	-- each default bar's own Bars Settings page are where this actually gets configured.
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

	CreateWizardNavButton(step, self, "Next", 24, 120, 120, function()
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
		"Keep the vanilla bar layout, or switch to a centered modern " ..
		"layout with Blizzard's bar art turned off."
	)

	local keepButton = CreateFrame("Button", nil, step)
	keepButton:SetHeight(34)
	ACAB:StyleModernButton(keepButton, 210, 220)
	keepButton:SetText("Keep Vanilla Layout + ArtBar enabled")
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

-- Only reached via step 5's "modern" choice (same as step 7/8 below) - lets the user preview and pick
-- Pet Bar/Stance Bar's own native-vs-styled mode before finishing. The two mode checkboxes mirror
-- SettingsBars.lua's CreateUseVanillaPetBarCheckbox/CreateUseVanillaStanceBarCheckbox (same
-- label/tooltip text), but write into wizardState instead of live ACABDB and skip their "Reload Now"
-- confirm dialog - FinishWizard's own single eventual reload covers this. Each bar gets a
-- vanilla/modern preview pair, only the one matching its own mode checkbox shown.
function ACABSetupWizardMixin:BuildStep6()
	local step = CreateFrame("Frame", nil, self)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText(
		"Choose how your Stance Bar and Pet Bar are built. Vanilla uses " ..
		"the real Blizzard frame (compatible with the real Keybindings " ..
		"menu); switching to the styled/modern mode lets this addon " ..
		"resize, restyle, and Hoverbind it like a custom bar."
	)

	local cursorY = -50

	local stanceLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	stanceLabel:SetPoint("TOP", step, "TOP", 0, cursorY)
	stanceLabel:SetText("Stance Bar")
	cursorY = cursorY - 16 - 8

	local vanillaStanceContainer, vanillaStanceSlots = CreateWizardIconRow(
		step, false, STEP6_STANCE_ICONS, STEP6_STANCE_PREVIEW_COUNT, ACAB.BUTTON_SIZE, STEP6_VANILLA_SPACING
	)
	vanillaStanceContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	local modernStanceContainer, modernStanceSlots = CreateWizardIconRow(
		step, true, STEP6_STANCE_ICONS, STEP6_STANCE_PREVIEW_COUNT, ACAB.BUTTON_SIZE, 0
	)
	modernStanceContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	cursorY = cursorY - ACAB.BUTTON_SIZE - 14

	local stanceCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardUseVanillaStanceBarCheckbox", {
		anchor = { "TOP", step, "TOP", -60, cursorY },
		label = "Use Vanilla Stance Bar",
		tooltip = {
			title = "Use Vanilla Stance Bar",
			lines = {
				"While enabled, this addon's Hoverbind mode cannot bind keys on " ..
				"the Stance Bar. Use the real Blizzard Keybindings menu instead, or " ..
				"disable this option.",
			},
		},
		onClick = function()
			ACAB.setupWizard.wizardState.useNativeStanceBar = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep6PreviewStyle()
		end,
	})
	cursorY = cursorY - 24 - 30

	local petLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	petLabel:SetPoint("TOP", step, "TOP", 0, cursorY)
	petLabel:SetText("Pet Bar")
	cursorY = cursorY - 16 - 8

	local vanillaPetContainer, vanillaPetSlots = CreateWizardIconRow(
		step, false, STEP6_PET_ICONS, STEP6_PET_PREVIEW_COUNT, ACAB.BUTTON_SIZE, STEP6_VANILLA_SPACING
	)
	vanillaPetContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	local modernPetContainer, modernPetSlots = CreateWizardIconRow(
		step, true, STEP6_PET_ICONS, STEP6_PET_PREVIEW_COUNT, ACAB.BUTTON_SIZE, 0
	)
	modernPetContainer:SetPoint("TOP", step, "TOP", 0, cursorY)

	cursorY = cursorY - ACAB.BUTTON_SIZE - 14

	local petCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardUseVanillaPetBarCheckbox", {
		anchor = { "TOP", step, "TOP", -60, cursorY },
		label = "Use Vanilla Pet Bar",
		tooltip = {
			title = "Use Vanilla Pet Bar",
			lines = {
				"While enabled, this addon's Hoverbind mode cannot bind keys on " ..
				"the Pet Bar. Use the real Blizzard Keybindings menu instead, or " ..
				"disable this option.",
			},
		},
		onClick = function()
			ACAB.setupWizard.wizardState.useNativePetBar = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep6PreviewStyle()
		end,
	})
	cursorY = cursorY - 24 - 14

	-- Only meaningful/shown in styled mode - native mode's real PetActionButtons always show all 10 regardless.
	local condenseCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardCondensePetSlotsCheckbox", {
		anchor = { "TOP", step, "TOP", -60, cursorY },
		label = "Condense empty Button Space",
		onClick = function()
			ACAB.setupWizard.wizardState.condenseEmptyPetSlots = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep6PetCondensePreview()
		end,
	})

	CreateWizardNavButton(step, self, "Next", 24, 120, 120, function()
		ACAB.setupWizard:ShowStep(7)
	end)

	step.vanillaStanceContainer = vanillaStanceContainer
	step.vanillaStanceSlots = vanillaStanceSlots
	step.modernStanceContainer = modernStanceContainer
	step.modernStanceSlots = modernStanceSlots
	step.stanceCheckbox = stanceCheckbox
	step.vanillaPetContainer = vanillaPetContainer
	step.vanillaPetSlots = vanillaPetSlots
	step.modernPetContainer = modernPetContainer
	step.modernPetSlots = modernPetSlots
	step.petCheckbox = petCheckbox
	step.condenseCheckbox = condenseCheckbox

	return step
end

-- Order mirrors SettingsBars.lua's own Experience Bar settings page: Enabled, then (if enabled) a
-- position choice, then "Better Experience Bar" and everything it unlocks. Every control here writes
-- into wizardState only; nothing is applied live or to ACABDB until FinishWizard.
function ACABSetupWizardMixin:BuildStep7()
	local step = CreateFrame("Frame", nil, self)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText("Set up your Experience Bar.")

	-- Every widget below anchors to `step` directly at its own computed cursorY, never widget-to-widget
	-- - a chained anchor drifts off-center with each link.
	local cursorY = -18

	local enabledCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardExpBarEnabledCheckbox", {
		anchor = { "TOP", step, "TOP", -60, cursorY },
		label = "Enable Experience Bar",
		onClick = function()
			ACAB.setupWizard.wizardState.expBarEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep7Visibility()
		end,
	})
	cursorY = cursorY - 24 - 22

	local positionLabel = step:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	positionLabel:SetPoint("TOP", step, "TOP", 0, cursorY)
	positionLabel:SetText("Where should your experience bar be:")
	cursorY = cursorY - 16 - 8

	-- Centered under its own label instead of beside it - beside it ran past the wizard's right edge.
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
			ACAB.setupWizard:UpdateStep7Visibility()
		end,
	})
	cursorY = cursorY - 24 - 20

	-- 5 independently toggleable text segments - same dbKey names as the real settings page.
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

	-- Font size slider - mirrors SettingsBars.lua's own range/step for this same control.
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

	-- 3 color swatches: Earned XP Bar Color, Rested XP Bar Color, Overlay Text Color - same
	-- order/labels as the real settings page.
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

	CreateWizardNavButton(step, self, "Next", 24, 120, 120, function()
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

function ACABSetupWizardMixin:BuildStep8()
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

	-- One preview bar per style, both anchored at the same spot - only the one matching
	-- wizardState.modernBorderStyle (chosen on step 3) is ever shown.
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

	-- Fixed clearance below previewLabel (not anchored to either bar's own BOTTOM) so the checkbox
	-- stack doesn't jump as the button-size slider grows the bar - BUTTON_SIZE_MAX plus a margin.
	local PREVIEW_CLEARANCE = -(10 + ACAB.BUTTON_SIZE_MAX + 14)

	-- Every row below anchors directly to previewLabel at its own computed cursorY, never
	-- widget-to-widget - chaining off a Hide()'n sibling's unresolved rect grows the gap on toggle.
	local CHECKBOX_HEIGHT = 24
	local SLIDER_HEIGHT = 17
	local cursorY = PREVIEW_CLEARANCE

	-- Stacked vertically (not side by side like the General settings page's own pair) - side by side
	-- here runs past the wizard's width.
	local spacingCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardSpacingCheckbox", {
		anchor = { "TOP", previewLabel, "BOTTOM", -60, cursorY },
		label = "Enable global spacing",
		onClick = function()
			ACAB.setupWizard.wizardState.globalSpacingEnabled = this:GetChecked() and true or false
			ACAB.setupWizard:UpdateStep8SliderVisibility()
		end,
	})
	cursorY = cursorY - CHECKBOX_HEIGHT - 14

	-- Mirrors SettingsGeneral.lua's own global-spacing slider config; the useDefaultLayout-driven
	-- display-offset that slider applies doesn't apply here since the wizard only reaches this step
	-- after useDefaultLayout has already been chosen "Disable".
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
				ACAB.setupWizard:ReflowStep8Preview()
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
			ACAB.setupWizard:UpdateStep8SliderVisibility()
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
				ACAB.setupWizard:ReflowStep8Preview()
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

	CreateWizardNavButton(step, self, "Finish", 28, 140, 140, function()
		ACAB.setupWizard:FinishWizard()
	end)

	return step
end

function ACABSetupWizardMixin:OnLoad()
	-- FULLSCREEN_DIALOG: same strata as ACABDialogMixin, above the settings window and any other addon UI.
	self:SetFrameStrata("FULLSCREEN_DIALOG")
	self:SetWidth(WIZARD_WIDTH)
	self:SetHeight(INITIAL_HEIGHT)

	-- Anchored by TOP, not CENTER - FitHeightToStep reads this same TOP edge as its measurement
	-- reference, and a CENTER anchor moves it on every resize, compounding across resizes.
	self:SetPoint("TOP", UIParent, "TOP", 0, -80)

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
		self:BuildStep8(),
	}

	local i

	-- Dual TOPLEFT+BOTTOMRIGHT anchor, both corners off `self` directly - gives each step frame a real
	-- width AND height derived from self's own rect, set once here. STEP_CONTENT_TOP_OFFSET clears
	-- titleText+stepText; the bottom margin clears the Back/Next button row.
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

-- Resets all transient wizard state/widgets to their starting point - run once per
-- ACAB:ShowSetupWizard open, so a previous partial run (closed via Cancel/X) never leaks into the next.
-- config.overwriteExisting: reconfigures the given (already-active) config.profileName in place
-- instead of creating a new profile. Skips step 1 (the name is fixed to the current profile).
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

	-- Font size/pulse interval sliders show a real current-session default purely for display;
	-- wizardState's own field stays nil (no write at Finish) unless the user actually moves one.
	ACAB:CaptureNativeExpBarFontIfNeeded()

	local nativeFontSize = ACAB.NATIVE_EXPBAR_FONT and (ACAB.NATIVE_EXPBAR_FONT.size - 1)

	step7.fontSizeSlider.suppressApply = true
	step7.fontSizeSlider:SetValue(ACAB:ClampFontSize(ACABDB.expBarFontSize or nativeFontSize or 12))
	step7.fontSizeSlider.suppressApply = nil

	step7.pulseIntervalSlider.suppressApply = true
	step7.pulseIntervalSlider:SetValue(ACABDB.expBarGlowPulseInterval or 1.5)
	step7.pulseIntervalSlider.suppressApply = nil

	SetWizardColorSwatchColor(step7.earnedColorSwatch, ACABDB.expBarColorEarned or { r = 0, g = 1, b = 0 })
	SetWizardColorSwatchColor(step7.restedColorSwatch, ACABDB.expBarColorRested or { r = 0.6, g = 0.2, b = 1 })
	SetWizardColorSwatchColor(step7.textColorSwatch, ACABDB.expBarTextColor or { r = 1, g = 0.82, b = 0 })

	self:UpdateStep7Visibility()

	local step8 = self.steps[8]
	step8.spacingCheckbox:SetChecked(false)
	step8.sizeCheckbox:SetChecked(false)

	step8.spacingSlider.suppressApply = true
	step8.spacingSlider:SetValue(0)
	step8.spacingSlider.suppressApply = nil

	step8.sizeSlider.suppressApply = true
	step8.sizeSlider:SetValue(ACAB.BUTTON_SIZE)
	step8.sizeSlider.suppressApply = nil

	self:UpdateStep8SliderVisibility()
end

function ACABSetupWizardMixin:ShowStep(n)
	local i

	for i = 1, table.getn(self.steps) do
		self.steps[i]:Hide()
	end

	self.currentStep = n

	-- Overwrite mode skips step 1, so the displayed count is renumbered to "of 7" starting at 1 instead
	-- of showing a step the user never saw, and Back has nothing to go back to until step 3. Total is
	-- the max reachable step regardless of mode - some paths finish early without visiting every step.
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

-- Back always steps to currentStep-1 - every reachable path through the wizard is a straight line, so
-- there's no case where the previous step isn't the one the user actually saw.
function ACABSetupWizardMixin:GoToPreviousStep()
	self:ShowStep(self.currentStep - 1)
end

-- Deepest (lowest-on-screen) GetBottom() among `step`'s own direct child frames/regions that are
-- currently shown - container frames are measured as one unit, not recursed into. Skips any widget
-- flagged .ACABNavButton: it's anchored to the wizard frame, not `step`, so counting it as step
-- content would feed back into a taller wizard on every fit call.
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

-- Re-anchors TOPLEFT off UIParent's own BOTTOMLEFT at the wizard's current on-screen position - called
-- once, right after a drag ends, not on every resize. Dragging replaces OnLoad's TOP anchor with an
-- engine-derived one that's no longer guaranteed TOP-anchored, so this restores that invariant.
-- Must stay drag-end-only: GetTop() read immediately after a ClearAllPoints/SetPoint pair doesn't
-- reliably reflect the new anchor yet on this client, so a per-call reanchor compounds height on toggle.
function ACABSetupWizardMixin:NormalizeAnchorToTopLeft()
	local left = self:GetLeft()
	local top = self:GetTop()

	if left and top then
		self:ClearAllPoints()
		self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
	end
end

-- Resizes the wizard to fit step `n`'s actual current content instead of a guessed-at fixed height.
-- GetBottom() on content just Show()'n this tick hasn't resolved yet, so measurement is deferred one
-- frame. Guarded on currentStep still matching `n` in case the user already moved on.
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

-- Validates step 1's profile-name entry and advances to step 2 - reused by both the Next button and
-- the edit box's OnEnterPressed.
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

-- Gates step 4's 3 stance-assignment rows/Page Swap Indicator/page-assignment row on the Stance/Page
-- checkboxes - then refreshes the preview, since toggling either checkbox changes what the example bar shows.
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

-- Shows whichever of step 4's vanilla/modern stance row + action bar pairs matches step 3's choice and
-- hides the other - called from ShowStep whenever step 4 becomes visible.
function ACABSetupWizardMixin:UpdateStep4PreviewStyle()
	local step = self.steps[4]
	local isModern = self.wizardState.modernBorderStyle and true or false

	step.vanillaStanceContainer:SetShown(not isModern)
	step.modernStanceContainer:SetShown(isModern)
	step.vanillaActionBarContainer:SetShown(not isModern)
	step.modernActionBarContainer:SetShown(isModern)
end

-- Refreshes the example action bar's 4 icons and which stance button glows, from the current
-- stance/page selection. The 3 stance buttons are always clickable and always update which one glows,
-- regardless of the Stance/Form checkbox - that checkbox only gates whether the action bar reacts to
-- the click. Toggling Page 2 doesn't block stance selection either - clicking a stance still moves the
-- glow, it just doesn't change the bar while Page 2's content is showing (matching a real Shift/Ctrl
-- page hold's priority over the active stance). Both style variants' slots are always updated.
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

-- Shows whichever of step 6's two Stance Bar/Pet Bar preview pairs matches each bar's own mode
-- checkbox - called from both checkboxes' onClick and from ShowStep whenever step 6 becomes visible.
-- A real native frame's look is fixed (always vanilla Blizzard button art) - only the styled case
-- reflects wizardState.modernBorderStyle. Also gates the Condense checkbox (styled Pet Bar mode only)
-- and refreshes its own preview.
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

-- Re-flows whichever container currently represents the styled Pet Bar tight, hiding the 3
-- untrained-ability slots, when Condense is checked (native mode never condenses). Always resets both
-- containers to their normal full 10-wide grid first, so neither is left mid-condensed from a
-- previous state once it becomes active again.
function ACABSetupWizardMixin:UpdateStep6PetCondensePreview()
	local step = self.steps[6]
	local state = self.wizardState

	local petStyled = not state.useNativePetBar
	local condensed = petStyled and state.condenseEmptyPetSlots and true or false
	local useModernBorder = petStyled and state.modernBorderStyle and true or false

	local activeSlots = useModernBorder and step.modernPetSlots or step.vanillaPetSlots
	local activeContainer = useModernBorder and step.modernPetContainer or step.vanillaPetContainer
	local activeSpacing = useModernBorder and 0 or STEP6_VANILLA_SPACING
	local inactiveSlots = useModernBorder and step.vanillaPetSlots or step.modernPetSlots
	local inactiveContainer = useModernBorder and step.vanillaPetContainer or step.modernPetContainer
	local inactiveSpacing = useModernBorder and STEP6_VANILLA_SPACING or 0

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

-- Gates step 7's position dropdown/"Better Experience Bar" checkbox on Enable Experience Bar, and its
-- 5 text toggles/font size/3 color swatches/pulse interval on Better Experience Bar itself - same
-- two-level gating as the real settings page's ApplyBetterExpBarGating, but Show/Hide instead of dim.
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

-- Shows whichever of step 8's two preview bars matches step 3's choice and hides the other - called
-- from ShowStep whenever step 8 becomes visible.
function ACABSetupWizardMixin:UpdateStep8PreviewStyle()
	local step = self.steps[8]
	local isModern = self.wizardState.modernBorderStyle and true or false

	step.vanillaBarContainer:SetShown(not isModern)
	step.modernBarContainer:SetShown(isModern)
end

-- Recomputes the single active preview bar's slot layout from the current spacing/size slider values -
-- updates both style variants' slots so either is already correct when UpdateStep8PreviewStyle switches.
function ACABSetupWizardMixin:ReflowStep8Preview()
	local step = self.steps[8]
	local state = self.wizardState

	local buttonSize = (state.globalButtonSizeEnabled and state.globalButtonSizeValue) or ACAB.BUTTON_SIZE
	local sliderSpacing = (state.globalSpacingEnabled and state.globalSpacingValue) or 0

	-- Mirrors Bar.lua's ApplyGlobalSpacingToBar formula: vanilla border style adds VANILLA_SPACING_FLOOR
	-- on top of the slider's displayed value; modern style has no floor.
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

-- Applies step 7's Experience Bar choices onto `data`: Enabled, and (if enabled) position - centered
-- at the bottom or top of the screen, via the same min/max Y the real settings page's slider allows.
-- "Better Experience Bar" and everything it unlocks is only written when enabled - untouched fields
-- are left alone, so the profile keeps whatever it already had for anything the user didn't touch.
local function ApplyExpBarWizardState(state, data)
	if state.expBarEnabled ~= nil then
		data.expBarEnabled = state.expBarEnabled
	end

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

-- Applies the "Modern Layout" preset's non-geometry flags onto `data` - disables Blizzard's bar art
-- and turns off Snap to Grid/Snap to Adjacent Elements, which would otherwise fight later manual
-- adjustments. Actual positions are computed separately, live, by ApplyModernLayoutGeometry below -
-- `data` isn't yet the live ACABDB at this point, so real frame geometry can't be measured against it.
local function ApplyModernLayoutPreset(state, data)
	data.mainBarArtMode = ACAB.MAIN_BAR_ART_MODE_DISABLED

	-- Bag Bar sits exactly flush with the screen's corner - a natural target for Snap to Grid/Snap to
	-- Adjacent Elements, which would fight any attempt to manually drag it away again afterward.
	data.snapToGrid = false
	data.snapToAdjacentElements = false
end

-- Applies the full Modern Layout preset's geometry directly onto the live ACABDB - stacks Main Bar/
-- Action Bar 1/Action Bar 2 (zero gap), the right/left vertical bar clusters, Stance/Pet Bar, the Page
-- Indicator, and the bottom-right corner cluster - the same per-element functions every individual
-- "Reset to Modern Layout Default" button calls, so the wizard and those buttons can never drift apart.
-- Must run against a live ACABDB that already points at the target profile (FinishWizard below).
function ACAB:ApplyModernLayoutGeometry()
	self:ApplyModernMainActionBarsLayout()
	self:ApplyModernVerticalBarClusterLayout()

	self:ResetPetBarLayoutToModernBase()
	self:ResetStanceBarPositionToModernBase()

	self:ResetPageIndicatorToModernBase()

	self:ApplyModernCornerClusterLayout()
end

-- Applies wizardState.useDefaultLayout/modernBorderStyle/general layout format/global spacing+size
-- onto `data` - shared by FinishWizard's create and overwrite branches.
local function ApplyWizardStateToProfileData(state, data)
	data.useDefaultLayout = state.useDefaultLayout

	if state.modernBorderStyle ~= nil then
		data.modernBorderStyle = state.modernBorderStyle

		-- WARNING: must set lastAppliedVanillaStyle to match, or Bar.lua's ApplyGlobalButtonStyle
		-- treats this as a live style switch on next login and shifts every default bar's
		-- buttonSize/position/spacing to compensate, perturbing Action Bar 2 and Stance/Pet Bar's alignment.
		data.lastAppliedVanillaStyle = not state.modernBorderStyle
	end

	-- Step 4 (Stance/Page Swapping) is only ever reached via step 2's "unlocked" path - the
	-- locked-default path finishes immediately from step 2, so these checkboxes were never
	-- shown/confirmed and the profile keeps whatever it already had.
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

	-- "blizzard" (Keep Vanilla Layout + ArtBar enabled) writes nothing onto `data` here - steps 6-8 are
	-- never visited on that path. The actual reset to vanilla happens separately in FinishWizard below,
	-- against the live ACABDB once it points at the target profile.
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
		ApplyModernLayoutPreset(state, data)
	end
end

-- Creates the profile from wizardState and switches to it (reloads the UI), or - in overwrite mode -
-- applies wizardState directly onto the already-active profile and reloads. On a name race in create
-- mode, sends the user back to step 1 with the rejection message shown instead of silently failing.
function ACABSetupWizardMixin:FinishWizard()
	local state = self.wizardState

	if state.overwriteExisting then
		ACABDB = ACABDB or {}
		ApplyWizardStateToProfileData(state, ACABDB)

		-- ACABDB already is the live active profile in overwrite mode - Modern Layout's geometry can
		-- apply/measure against real bars right here, no profile switch needed first.
		if state.generalLayoutFormat == "modern" then
			ACAB:ApplyModernLayoutGeometry()
		elseif state.generalLayoutFormat == "blizzard" then
			-- In overwrite mode the prior data can already be a Modern Layout profile from an earlier
			-- wizard run - runs the same reset cascade "Force Vanilla Layout Mode" uses, so this choice
			-- always lands on the real vanilla baseline regardless of what the profile had before.
			ACAB:ResetAllElementsToVanillaLayout()
		end

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

	-- Persists whatever the OLD active profile's live ACABDB currently holds before switching away
	-- from it - same first step ACAB:SwitchProfile itself takes.
	ACAB:SaveActiveProfileData()

	-- Points live ACABDB at the just-created profile without reloading yet - Modern Layout's geometry
	-- needs live bars 1-5 to actually apply/measure against, and the ReloadUI() this ends with
	-- discards this session's now-unused in-memory state anyway.
	ACAB.activeProfileName = state.profileName
	ACABDB = ACAB:DeepCopyTable(ACABProfilesDB[state.profileName])

	-- WARNING: every already-created bar's own bar.config field still points at the OLD ACABDB's
	-- tables after the reassignment above - must re-point it here or Modern Layout's geometry writes
	-- land in an orphaned table SaveActiveProfileData never reads from, silently discarding the layout.
	if ACAB.bars then
		local barId, bar

		for barId, bar in pairs(ACAB.bars) do
			local cfg = ACAB:GetBarConfig(barId)

			if cfg then
				bar.config = cfg
			end
		end
	end

	if state.generalLayoutFormat == "modern" then
		ACAB:ApplyModernLayoutGeometry()
	elseif state.generalLayoutFormat == "blizzard" then
		-- Same reasoning as the overwrite branch above - a brand-new profile can still have inherited
		-- Modern Layout data, so this choice always resets to the real vanilla baseline.
		ACAB:ResetAllElementsToVanillaLayout()
	end

	ACABCharDB = ACABCharDB or {}
	ACABCharDB.activeProfile = state.profileName
	ACABCharDB.hasSelectedProfileBefore = true

	ACAB:SaveActiveProfileData()

	-- Reloads the UI - nothing after this point runs.
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

-- The one entry point every caller uses to open the wizard - reuses the lazily-created frame and
-- resets it to a fresh starting state every time.
-- config (optional): { overwriteExisting = true, profileName = "..." }. Omit for the normal
-- first-login "create a new profile" flow, which starts at step 1.
function ACAB:ShowSetupWizard(config)
	local wizard = EnsureSetupWizardFrame()

	wizard:Reset(config)
	wizard:Show()
	wizard:ShowStep(wizard.wizardState.overwriteExisting and 2 or 1)

	return wizard
end
