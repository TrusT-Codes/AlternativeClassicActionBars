-- SetupWizard.lua
-- Setup Wizard (ACAB:ShowSetupWizard), hosted inside the settings window. Decision steps (name, Force Vanilla
-- lock, button style, layout) only collect choices; the lock/layout choice writes the chosen built-in baseline
-- onto the target profile and reloads. Every later step shows a real settings page that edits the active
-- profile live. The current step is saved in ACABCharDB.setupWizard, so any reload resumes the wizard there.

local ACAB = AlternativeClassicActionBars

local WIZARD_CONTENT_WIDTH = 440
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
-- Cosmetic (non-interactive) preview bars for the button style step, same skin recipe as Button.lua's Init
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

-- Row of count preview slots; returns the row's container (caller anchors it).
local function CreateWizardPreviewBar(parent, isModern, count, buttonSize, spacing)
	local container = CreateFrame("Frame", nil, parent)
	container:SetHeight(buttonSize)
	container:SetWidth(ComputePreviewBarWidth(buttonSize, spacing, count))

	local previous = nil
	local i

	for i = 1, count do
		local slot = CreateWizardPreviewSlot(container, isModern, PreviewIconForSlot(i))

		slot:SetWidth(buttonSize)
		slot:SetHeight(buttonSize)

		if slot.border then
			slot.border:SetWidth(buttonSize * ACAB.BORDER_RATIO)
			slot.border:SetHeight(buttonSize * ACAB.BORDER_RATIO)
		end

		if previous then
			slot:SetPoint("LEFT", previous, "RIGHT", spacing, 0)
		else
			slot:SetPoint("LEFT", container, "LEFT", 0, 0)
		end

		previous = slot
	end

	return container
end

-------------------------------------------------------------------------
-- Steps
-------------------------------------------------------------------------

-- Extra Bars page hint per layout: where the bars sit and what enabling them moves.
local EXTRA_BARS_HINTS = {
	vanilla = "Extra Bars start disabled. Extra Bar 1/2 sit above Action Bar 1/2 and push the Stance/Pet Bar up; " ..
		"Extra Bar 3/4 sit left of Right Action Bar 2.",
	modern = "Extra Bars start disabled. Extra Bar 1 joins the right-hand vertical cluster; Extra Bar 2-4 line up " ..
		"from the left screen edge.",
}

-- kind "decision": a frame on the wizard view; kind "page": a live settings page - a real one (page = ShowBarPage
-- id, or show()) or a wizard view frame (frame = true). short = sidebar label; hint = string or function(state);
-- onFirstVisit(state)/onShow() optional.
local STEPS = {
	name = { kind = "decision", title = "Name Your Profile", short = "Profile Name" },
	lock = { kind = "decision", title = "Force Vanilla Layout Mode", short = "Vanilla Lock" },
	style = { kind = "decision", title = "Button Style", short = "Button Style" },
	layout = { kind = "decision", title = "General Layout", short = "Layout" },
	general = {
		kind = "page",
		title = "General Settings",
		short = "General",
		hint = "Set up Page and Stance/Form swapping, button text and global sizing here - " ..
			"the next steps use these settings. Every change applies to your bars right away.",
		show = function() ACAB:ShowGeneralView() end,
	},
	mainbar = {
		kind = "page",
		title = "Main Bar",
		short = "Main Bar",
		page = 1,
		hint = "Set up your Main Bar: bar art (gryphons / background), size, position and which " ..
			"bar it shows per stance and page. Changes apply right away.",
	},
	stance = {
		kind = "page",
		title = "Stance Bar",
		short = "Stance Bar",
		page = ACAB.STANCE_BAR_ID,
		hint = "Set up your Stance Bar. Switching \"Use Vanilla Stance Bar\" reloads your UI - " ..
			"the wizard continues right here afterwards.",
	},
	pet = {
		kind = "page",
		title = "Pet Bar",
		short = "Pet Bar",
		page = ACAB.PET_BAR_ID,
		hint = "Set up your Pet Bar. Switching \"Use Vanilla Pet Bar\" reloads your UI - " ..
			"the wizard continues right here afterwards.",
	},
	extrabars = {
		kind = "page",
		title = "Extra Bars",
		short = "Extra Bars",
		frame = true,
		-- Vanilla layout: re-derives each bar's default size/spot from the reference bars earlier steps may have changed.
		onFirstVisit = function(state)
			if state.layout == "vanilla" then
				local id

				for id = ACAB.EXTRA_BAR_ID_START, ACAB.EXTRA_BAR_ID_START + ACAB.EXTRA_BAR_COUNT - 1 do
					ACAB:ResetExtraBarLayout(id)
				end
			end
		end,
		onShow = function() ACAB.setupWizard:RefreshExtraBarsStep() end,
		hint = function(state)
			return EXTRA_BARS_HINTS[state.layout == "vanilla" and "vanilla" or "modern"]
		end,
	},
	bagbar = {
		kind = "page",
		title = "Bag Bar",
		short = "Bag Bar",
		page = "bagbar",
		hint = "Set up your Bag Bar: position, spacing, orientation and scale.",
	},
	keyring = {
		kind = "page",
		title = "Key Ring",
		short = "Key Ring",
		page = "keyring",
		hint = "Set up your Key Ring button.",
	},
	expbar = {
		kind = "page",
		title = "Experience Bar",
		short = "Experience Bar",
		page = "expbar",
		hint = "Set up your Experience Bar.",
	},
	tooltip = {
		kind = "page",
		title = "Tooltip",
		short = "Tooltip",
		page = "tooltip",
		hint = "Set up where your tooltip shows. Everything else can be changed any time in the Settings window.",
	},
}

-- Longest possible path, for the sidebar row pool.
local MAX_STEP_COUNT = 16

-- Ordered step keys for state; Stance/Pet/Bag Bar/Key Ring steps only follow the Modern layout (the default while undecided).
local function BuildStepPath(state)
	local path = {}

	if not state.overwriteExisting then
		table.insert(path, "name")
	end

	table.insert(path, "lock")
	table.insert(path, "style")
	table.insert(path, "layout")
	table.insert(path, "general")
	table.insert(path, "mainbar")
	table.insert(path, "extrabars")

	if state.layout ~= "vanilla" then
		table.insert(path, "stance")
		table.insert(path, "pet")
		table.insert(path, "bagbar")
		table.insert(path, "keyring")
	end
	table.insert(path, "expbar")
	table.insert(path, "tooltip")

	return path
end

local function IndexOfStep(path, key)
	local i

	for i = 1, table.getn(path) do
		if path[i] == key then
			return i
		end
	end

	return nil
end

-------------------------------------------------------------------------
-- Shared widget helpers
-------------------------------------------------------------------------

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

-- New hidden decision step frame on panel with its centered intro message at the top. Returns step, message.
local function CreateStepFrame(panel, text)
	local step = CreateFrame("Frame", nil, panel)

	-- must be sized: a frame with only anchors has no rect for its children to resolve against
	step:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -24)
	step:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -24)
	step:SetHeight(1)

	local message = step:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	message:SetPoint("TOP", step, "TOP", 0, 0)
	message:SetWidth(WIZARD_CONTENT_WIDTH)
	message:SetJustifyH("CENTER")
	message:SetText(text)

	step:Hide()

	return step, message
end

-------------------------------------------------------------------------
-- ACABSetupWizardMixin: the wizard controller (ACAB.setupWizard); its UI lives on ACAB.settingsFrame.
-------------------------------------------------------------------------

ACABSetupWizardMixin = {}

-- Step "name": the new profile's name (create mode only).
function ACABSetupWizardMixin:BuildNameStep(panel)
	local step, message = CreateStepFrame(panel,
		"This creates your own custom profile, separate from the locked built-in " ..
		"\"" .. ACAB.DEFAULT_PROFILE_NAME .. "\" and \"" .. ACAB.MODERN_PROFILE_NAME .. "\" profiles. " ..
		"Give it a name - you can rename it or add more profiles later from the Profiles tab."
	)

	local editBox = CreateFrame("EditBox", "ACABSetupWizardNameEditBox", step, "InputBoxTemplate")
	editBox:SetWidth(280)
	editBox:SetHeight(20)
	editBox:SetAutoFocus(false)
	editBox:SetPoint("TOP", message, "BOTTOM", 0, -30)
	editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
	editBox:SetScript("OnEnterPressed", function()
		this:ClearFocus()
		ACAB.setupWizard:AdvanceFromName()
	end)

	local errorText = step:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	errorText:SetPoint("TOP", editBox, "BOTTOM", 0, -12)
	errorText:SetWidth(WIZARD_CONTENT_WIDTH)
	errorText:SetJustifyH("CENTER")
	errorText:SetTextColor(1, 0.15, 0.15)
	errorText:Hide()

	step.editBox = editBox
	step.errorText = errorText

	return step
end

-- Step "lock": locked Default Vanilla copy (finishes) or unlocked (continues).
function ACABSetupWizardMixin:BuildLockStep(panel)
	local step, message = CreateStepFrame(panel,
		"Locks your bars to their native vanilla position and style, or " ..
		"frees them.\n\n" ..
		"|cffff2626Locked: shown/hidden only - no moving, resizing, or " ..
		"restyling. Finishes the wizard and reloads your UI.|r\n\n" ..
		"|cff33ff33Unlocked: move, resize, and restyle bars, and set them " ..
		"up in the next steps.|r"
	)

	CreateWizardButton(step, {
		text = "Lock down default Elements!",
		height = 34,
		minWidth = 200,
		maxWidth = 210,
		anchor = { "TOP", message, "BOTTOM", -115, -20 },
		variant = "danger",
		onClick = function()
			ACAB.setupWizard:ApplyBaselineAndReload("locked")
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
			ACAB.setupWizard:ShowStep("style")
		end,
	})

	return step
end

-- Step "style": vanilla vs modern button style.
function ACABSetupWizardMixin:BuildStyleStep(panel)
	local step, message = CreateStepFrame(panel,
		"Choose a button style for your bars. You can change this later in the General settings."
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
				ACAB.setupWizard:ShowStep("layout")
			end,
		})
	end

	-- Modern is drawn 2px larger so both styles read the same apparent size.
	local vanillaApparentSize = 30

	BuildStyleColumn(-110, "Vanilla Style", false, vanillaApparentSize, VANILLA_PREVIEW_SPACING)
	BuildStyleColumn(110, "Modern Style", true, vanillaApparentSize + 2, 0)

	return step
end

-- Step "layout": Default Vanilla or Default Modern baseline; both reload and continue with the settings pages.
function ACABSetupWizardMixin:BuildLayoutStep(panel)
	local step, message = CreateStepFrame(panel,
		"Keep the vanilla bar layout with Blizzard's bar art, or start from the centered " ..
		"\"" .. ACAB.MODERN_PROFILE_NAME .. "\" layout with the bar art turned off.\n\n" ..
		"Your UI reloads once to load the chosen layout - the wizard then continues with " ..
		"your real settings pages, and every change shows up live on your bars."
	)

	CreateWizardButton(step, {
		text = "Keep Vanilla Layout + ArtBar enabled",
		height = 34,
		minWidth = 210,
		maxWidth = 220,
		anchor = { "TOP", message, "BOTTOM", -120, -20 },
		variant = "danger",
		onClick = function()
			ACAB.setupWizard:ApplyBaselineAndReload("vanilla")
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
			ACAB.setupWizard:ApplyBaselineAndReload("modern")
		end,
	})

	return step
end

-- Step "extrabars": enable, Only show on hover and Grid Layout for each Extra Bar, all applied live.
function ACABSetupWizardMixin:BuildExtraBarsStep(panel)
	local step = CreateFrame("Frame", nil, panel)

	-- must be sized: a frame with only anchors has no rect for its children to resolve against
	step:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -14)
	step:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -14)
	step:SetHeight(1)
	step:Hide()

	step.sections = {}

	local SECTION_HEIGHT = 124
	local n

	for n = 1, ACAB.EXTRA_BAR_COUNT do
		local barId = ACAB.EXTRA_BAR_ID_START + n - 1
		local y = -((n - 1) * SECTION_HEIGHT)
		local section = {}

		local title = step:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", step, "TOPLEFT", ACAB.INDENT_SECTION, y)
		title:SetText("Extra Bar " .. tostring(n))

		section.enableCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardExtraBar" .. tostring(n) .. "EnableCheckbox", {
			anchor = { "TOPLEFT", step, "TOPLEFT", ACAB.INDENT_SECTION, y - 22 },
			label = "Enable",
			onClick = function()
				ACAB:SetExtraBarEnabled(barId, this:GetChecked() and true or false)
			end,
		})

		section.hoverCheckbox = ACAB:CreateLabeledCheckbox(step, "ACABSetupWizardExtraBar" .. tostring(n) .. "HoverCheckbox", {
			anchor = { "TOPLEFT", step, "TOPLEFT", 200, y - 22 },
			label = "Only show on hover",
			onClick = function()
				local bar = ACAB.bars and ACAB.bars[barId]

				if bar then
					ACAB:SetBarHoverOnly(bar, this:GetChecked() and true or false)
				end
			end,
		})

		section.swatches = ACAB:CreateGridSwatchRow(step, barId, ACAB.INDENT_CONTROL, y - 52, function(cols, rows)
			local bar = ACAB.bars and ACAB.bars[barId]

			if bar then
				ACAB:SetBarLayout(bar, cols, rows)
			end

			ACAB.setupWizard:RefreshExtraBarsStep()
		end)

		section.barId = barId
		step.sections[n] = section
	end

	return step
end

-- Syncs the Extra Bars step's controls from each bar's saved config.
function ACABSetupWizardMixin:RefreshExtraBarsStep()
	local step = self.steps.extrabars
	local i

	for i = 1, table.getn(step.sections) do
		local section = step.sections[i]
		local cfg = ACAB:GetBarConfig(section.barId)

		if cfg then
			section.enableCheckbox:SetChecked(cfg.enabled == true)
			section.hoverCheckbox:SetChecked(cfg.hoverOnly == true)
			ACAB:SelectGridSwatch(section.swatches, ACAB:GetEffectiveBarGrid(cfg))
		end
	end
end

-- Builds the wizard's chrome on the settings window once: step header, step list sidebar, Back/Next row.
function ACABSetupWizardMixin:EnsureChrome()
	local f = ACAB.settingsFrame

	if f.wizardStepList then
		return
	end

	local stepText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	stepText:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -40)
	stepText:Hide()
	f.wizardStepText = stepText

	local profileText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profileText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -41)
	profileText:SetJustifyH("RIGHT")
	profileText:Hide()
	f.wizardProfileText = profileText

	-- Same spot and size as the bar list it replaces.
	local stepList = CreateFrame("Frame", nil, f)
	stepList:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -64)
	stepList:SetWidth(ACAB.SETTINGS_SIDEBAR_WIDTH)
	stepList:SetHeight(400)
	ACAB:ApplySettingsPanelBackdrop(stepList)
	stepList:Hide()
	f.wizardStepList = stepList

	local listTitle = stepList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	listTitle:SetPoint("TOP", stepList, "TOP", 0, -8)
	listTitle:SetText("Setup Steps")

	local ROW_HEIGHT = 20
	local ROW_GAP = 2
	local ROW_VISUAL_OFFSET = 2

	stepList.rows = {}
	stepList.rowPitch = ROW_HEIGHT + ROW_GAP

	local i

	for i = 1, MAX_STEP_COUNT do
		local row = ACAB:CreateListRow(stepList, nil)

		row:SetWidth(ACAB.SETTINGS_SIDEBAR_WIDTH - 10)
		row:SetHeight(ROW_HEIGHT)
		row:SetVisualWidth(ACAB.SETTINGS_SIDEBAR_WIDTH - (ROW_VISUAL_OFFSET * 2), ROW_VISUAL_OFFSET)
		row:SetPoint("TOPLEFT", stepList, "TOPLEFT", 0, -24 - ((i - 1) * (ROW_HEIGHT + ROW_GAP)))

		-- ACABListRowMixin passes the row explicitly (not via `this`).
		row:SetOnClick(function(clickedRow)
			ACAB.setupWizard:JumpToStep(clickedRow.stepKey)
		end)

		row:Hide()

		stepList.rows[i] = row
	end

	f.wizardBackButton = CreateWizardButton(f, {
		text = "Back",
		height = 24,
		minWidth = 100,
		maxWidth = 100,
		anchor = { "BOTTOMLEFT", f, "BOTTOMLEFT", 18, 18 },
		variant = "danger",
		onClick = function()
			ACAB.setupWizard:GoBack()
		end,
	})
	f.wizardBackButton:Hide()

	f.wizardNextButton = CreateWizardButton(f, {
		text = "Next",
		height = 24,
		minWidth = 120,
		maxWidth = 120,
		anchor = { "BOTTOMRIGHT", f, "BOTTOMRIGHT", -18, 18 },
		variant = "prominent",
		onClick = function()
			ACAB.setupWizard:GoNext()
		end,
	})
	f.wizardNextButton:Hide()

	f.wizardDragButton = CreateWizardButton(f, {
		text = "Drag Elements with Mouse",
		height = 24,
		minWidth = 260,
		maxWidth = 260,
		anchor = { "TOP", f, "TOP", 0, -36 },
		variant = "prominent",
		onClick = function()
			ACAB.setupWizard:StartDragMode()
		end,
	})
	f.wizardDragButton:Hide()

	local hintText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	hintText:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
	hintText:SetWidth(f:GetWidth() - (2 * (18 + 120 + 16)))
	hintText:SetHeight(30)
	hintText:SetJustifyH("CENTER")
	hintText:SetJustifyV("MIDDLE")
	hintText:Hide()
	f.wizardHintText = hintText
end

-- Switches the settings window between its normal chrome and the wizard's.
function ACABSetupWizardMixin:SetChromeShown(shown)
	local f = ACAB.settingsFrame

	f.wizardMode = shown and true or false

	local view, button

	for view, button in pairs(f.tabButtonsByView) do
		button:SetShown(not shown)
	end

	f.wizardStepText:SetShown(shown)
	f.wizardProfileText:SetShown(shown)
	f.wizardStepList:SetShown(shown)
	f.wizardBackButton:SetShown(shown)
	f.wizardNextButton:SetShown(shown)
	f.wizardHintText:SetShown(shown)
	f.wizardDragButton:SetShown(shown and self.wizardState.live and true or false)

	if shown then
		f.titleText:SetText(self.wizardState.overwriteExisting and "Reconfigure Your Profile" or "Set Up Your Profile")
		f.listPanel:Hide()
	else
		f.titleText:SetText("AlternativeClassicActionBars Settings")
	end

	f.applyBarsViewScrollbarReserves()
end

-- Starts (or resumes) a run with state and shows the settings window in wizard mode.
function ACABSetupWizardMixin:Begin(state)
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	-- Builds the decision steps (they live on the wizard view's panel).
	ACAB:GetOrCreateWizardPanel()

	self:EnsureChrome()

	state.visited = state.visited or {}

	self.wizardState = state
	self.path = BuildStepPath(state)
	self.currentStep = nil

	local nameStep = self.steps.name

	nameStep.editBox:SetText(state.profileName or "")
	nameStep.errorText:Hide()

	self:SetChromeShown(true)

	ACAB.settingsFrame:Show()
end

-- Persists the live-phase state so a reload resumes at the current step.
function ACABSetupWizardMixin:SaveResumeState()
	local state = self.wizardState
	local visited = {}
	local key, value

	for key, value in pairs(state.visited) do
		visited[key] = value
	end

	ACABCharDB = ACABCharDB or {}
	ACABCharDB.setupWizard = {
		profileName = state.profileName,
		overwriteExisting = state.overwriteExisting,
		layout = state.layout,
		step = self.currentStep,
		visited = visited,
	}
end

-- True if key is reachable from the sidebar: an earlier decision step before the reload, a visited page after it.
function ACABSetupWizardMixin:CanJumpToStep(key)
	local def = STEPS[key]

	if not def or key == self.currentStep then
		return false
	end

	if self.wizardState.live then
		return def.kind == "page" and self.wizardState.visited[key] == true
	end

	local index = IndexOfStep(self.path, key)
	local currentIndex = IndexOfStep(self.path, self.currentStep)

	return def.kind == "decision" and index ~= nil and currentIndex ~= nil and index < currentIndex
end

function ACABSetupWizardMixin:JumpToStep(key)
	if self:CanJumpToStep(key) then
		self:ShowStep(key)
	end
end

-- Step header, sidebar rows and Back/Next/hint for the current step.
function ACABSetupWizardMixin:RefreshChrome()
	local f = ACAB.settingsFrame
	local key = self.currentStep
	local def = STEPS[key]
	local path = self.path
	local count = table.getn(path)
	local index = IndexOfStep(path, key) or 1

	f.wizardStepText:SetText("Step " .. tostring(index) .. " of " .. tostring(count) .. " - " .. def.title)
	f.wizardProfileText:SetText("Profile: " .. tostring(self.wizardState.profileName))

	local rows = f.wizardStepList.rows
	local i

	-- Title + rows + bottom padding; read by the settings height fit.
	f.wizardStepList.requiredHeight = 24 + (count * f.wizardStepList.rowPitch) + 12

	for i = 1, table.getn(rows) do
		local row = rows[i]
		local rowKey = path[i]

		if rowKey then
			row.stepKey = rowKey
			row:SetLabel(tostring(i) .. ". " .. STEPS[rowKey].short)
			row:SetSelected(rowKey == key)
			row:SetDisabled(rowKey ~= key and not self:CanJumpToStep(rowKey))
			row:Show()
		else
			row:Hide()
		end
	end

	local previousKey = path[index - 1]

	f.wizardBackButton:SetShown(previousKey ~= nil and STEPS[previousKey].kind == def.kind)

	-- Decision steps with their own choice buttons advance by those; only the name step uses Next.
	local showNext = def.kind == "page" or key == "name"

	f.wizardNextButton:SetShown(showNext)
	f.wizardNextButton:SetText(index == count and "Finish" or "Next")

	-- Edit Layout mode needs the target profile, which only exists after the layout reload.
	f.wizardDragButton:SetShown(self.wizardState.live and true or false)

	local hint = def.hint

	if type(hint) == "function" then
		hint = hint(self.wizardState)
	end

	f.wizardHintText:SetText(hint or "")
end

-- Shows step key: a decision frame on the wizard view, or the real settings page.
function ACABSetupWizardMixin:ShowStep(key)
	local def = STEPS[key]

	if not def then
		return
	end

	-- DropDownList1 is one shared popout; close it before switching pages.
	if CloseDropDownMenus then
		CloseDropDownMenus()
	end

	self.currentStep = key

	if def.kind == "page" then
		if def.onFirstVisit and not self.wizardState.visited[key] then
			def.onFirstVisit(self.wizardState)
		end

		self.wizardState.visited[key] = true
		self:SaveResumeState()
	end

	self:RefreshChrome()

	if def.kind == "decision" or def.frame then
		ACAB.settingsFrame.wizardPanel.activeStep = self.steps[key]
		ACAB:ShowSetupWizardView()

		if key == "name" then
			self.steps.name.editBox:SetFocus()
			self.steps.name.editBox:HighlightText()
		end
	elseif def.page then
		ACAB:ShowBarPage(def.page)
	else
		def.show()
	end

	if def.onShow then
		def.onShow()
	end
end

-- Hides the settings window and turns on Edit Layout mode; SetEditMode(false) reopens the wizard.
function ACABSetupWizardMixin:StartDragMode()
	ACAB:SetEditMode(true)

	if not ACAB:IsEditMode() then
		return
	end

	ACAB.reopenSetupWizardAfterEditMode = true
	ACAB.settingsFrame:Hide()
end

function ACABSetupWizardMixin:GoNext()
	if self.currentStep == "name" then
		self:AdvanceFromName()
		return
	end

	local index = IndexOfStep(self.path, self.currentStep)
	local nextKey = index and self.path[index + 1]

	if nextKey then
		self:ShowStep(nextKey)
	else
		self:Finish()
	end
end

function ACABSetupWizardMixin:GoBack()
	local index = IndexOfStep(self.path, self.currentStep)
	local previousKey = index and self.path[index - 1]

	if previousKey and STEPS[previousKey].kind == STEPS[self.currentStep].kind then
		self:ShowStep(previousKey)
	end
end

-- Validates the name step and advances to the lock step.
function ACABSetupWizardMixin:AdvanceFromName()
	local step = self.steps.name
	local name = step.editBox:GetText()

	if not name or name == "" then
		step.errorText:SetText("Profile name cannot be empty.")
		step.errorText:Show()
		ACAB:DeferFit(function() ACAB:FitSettingsWindowToWizardView() end)
		return
	end

	if ACAB:ProfileNameTaken(name) then
		step.errorText:SetText("A profile named \"" .. name .. "\" already exists.")
		step.errorText:Show()
		ACAB:DeferFit(function() ACAB:FitSettingsWindowToWizardView() end)
		return
	end

	step.errorText:Hide()
	self.wizardState.profileName = name

	self:ShowStep("lock")
end

-------------------------------------------------------------------------
-- Baselines: the lock/layout choice copies a built-in profile onto the target profile, then reloads.
-------------------------------------------------------------------------

-- Target profile data for kind "locked" (Default Vanilla), "vanilla" (Default Vanilla, unlocked) or "modern"
-- (Default Modern), with the button style step's choice applied.
local function BuildBaselineData(state, kind)
	local vanillaData = ACAB:GetDefaultVanillaData()
	local data = nil

	if kind == "modern" then
		data = ACAB:BuildModernBaseProfileData()

		if not data then
			data = ACAB:DeepCopyTable(vanillaData)
			ACAB:ApplyModernBaselineFlags(data)
		end
	else
		data = ACAB:DeepCopyTable(vanillaData)
		data.useDefaultLayout = (kind == "locked")
		data.pendingLayoutBaseline = (kind == "vanilla") and "vanilla" or nil

		-- Stance/Pet/Cast Bar keep restacking on Extra Bar 1/2 toggles, as under Force Vanilla Layout Mode.
		data.vanillaLayoutStacking = (kind == "vanilla") or nil
	end

	-- The wizard's Extra Bar steps start every Extra Bar disabled (the Vanilla reset already disables them).
	if kind == "modern" then
		data.pendingDisableExtraBars = true
	end

	data.builtInModernProfile = nil

	-- Better Experience Bar starts enabled on every wizard-built unlocked profile.
	if kind ~= "locked" then
		data.betterExpBarEnabled = true
	end

	if kind == "locked" then
		data.modernBorderStyle = false
	elseif state.modernBorderStyle ~= nil then
		data.modernBorderStyle = state.modernBorderStyle
	end

	-- must match modernBorderStyle, or the next login treats it as a live style switch and shifts every bar
	data.lastAppliedVanillaStyle = not data.modernBorderStyle

	return data
end

-- Creates (or overwrites) the target profile with data and makes it this character's active profile.
-- A name clash returns to the name step.
function ACABSetupWizardMixin:WriteTargetProfile(data)
	local state = self.wizardState
	local name = state.profileName

	if not state.overwriteExisting then
		local ok, reason = ACAB:CreateProfile(name)

		if not ok then
			self.steps.name.errorText:SetText(reason or "Could not create profile.")
			self.steps.name.errorText:Show()
			self:ShowStep("name")
			return false
		end

		-- Saves the old active profile before switching away (same as ACAB:SwitchProfile).
		ACAB:SaveActiveProfileData()
	end

	ACABProfilesDB[name] = ACAB:DeepCopyTable(data)

	-- must repoint the live ACABDB too, or the logout save before ReloadUI writes the old data over it
	ACAB.activeProfileName = name
	ACABDB = ACAB:DeepCopyTable(data)

	ACABCharDB = ACABCharDB or {}
	ACABCharDB.activeProfile = name
	ACABCharDB.hasSelectedProfileBefore = true

	return true
end

-- Writes the chosen baseline onto the target profile and reloads; "vanilla"/"modern" resume at the first page step.
function ACABSetupWizardMixin:ApplyBaselineAndReload(kind)
	local state = self.wizardState

	if not self:WriteTargetProfile(BuildBaselineData(state, kind)) then
		return
	end

	if kind == "locked" then
		ACABCharDB.setupWizard = nil
	else
		state.layout = kind
		state.live = true
		state.visited = {}

		self.path = BuildStepPath(state)
		self.currentStep = "general"
		self:SaveResumeState()
	end

	ReloadUI()
end

-- Ends the run: restores the normal settings window chrome and hides it.
function ACABSetupWizardMixin:Exit()
	local f = ACAB.settingsFrame

	if CloseDropDownMenus then
		CloseDropDownMenus()
	end

	self:SetChromeShown(false)

	ACAB:HideWideViews()

	local id, page

	for id, page in pairs(f.pages) do
		page:Hide()
	end

	-- Next ShowSettingsFrame opens fresh on the Main Bar page.
	f.currentView = "bars"
	f.activeBarId = nil
	f:Hide()

	ACAB.reopenSetupWizardAfterEditMode = nil
	self.currentStep = nil
end

function ACABSetupWizardMixin:Finish()
	ACABCharDB.setupWizard = nil
	ACAB:SaveActiveProfileData()

	self:Exit()

	ACAB:Print("Setup complete! Click the minimap button or use /acab to change any setting later.")
end

-- X button: before the reload nothing was applied; afterwards the changes so far stay on the profile.
function ACABSetupWizardMixin:Cancel()
	if not self.wizardState.live then
		self:Exit()
		return
	end

	ACAB:ShowDialog({
		title = "Exit Setup Wizard",
		message = "Exit the Setup Wizard? Everything you changed so far stays on your profile.",
		mode = "confirm",
		buttons = {
			{
				text = "Exit Wizard",
				danger = true,
				onClick = function()
					ACABCharDB.setupWizard = nil
					ACAB.setupWizard:Exit()
				end,
			},
			{ text = "Keep going", isDefault = true, onClick = function() end },
		},
	})
end

-------------------------------------------------------------------------
-- Wizard view (the settings window's "wizard" wide view, holding the decision steps)
-------------------------------------------------------------------------

local function EnsureSetupWizard()
	if ACAB.setupWizard then
		return ACAB.setupWizard
	end

	local wizard = {}

	Mixin(wizard, ACABSetupWizardMixin)
	wizard.steps = {}

	ACAB.setupWizard = wizard

	return wizard
end

-- Builds the wizard view's scroll pair and decision step frames once (fixed names: build-once singleton).
function ACAB:GetOrCreateWizardPanel()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	if ACAB.settingsFrame.wizardPanel then
		return ACAB.settingsFrame.wizardPanel
	end

	local scrollFrame, panel = ACAB:CreateWideContentScrollFrame("ACABSetupWizardScrollFrame")

	ACAB.settingsFrame.wizardScrollFrame = scrollFrame
	scrollFrame:Hide()

	local wizard = EnsureSetupWizard()

	wizard.steps.name = wizard:BuildNameStep(panel)
	wizard.steps.lock = wizard:BuildLockStep(panel)
	wizard.steps.style = wizard:BuildStyleStep(panel)
	wizard.steps.layout = wizard:BuildLayoutStep(panel)
	wizard.steps.extrabars = wizard:BuildExtraBarsStep(panel)

	panel:Hide()

	ACAB.settingsFrame.wizardPanel = panel

	return panel
end

-- Shows only the wizard view's active decision step.
function ACAB:RefreshWizardPanel()
	local panel = self:GetOrCreateWizardPanel()
	local key, step

	for key, step in pairs(self.setupWizard.steps) do
		step:SetShown(step == panel.activeStep)
	end
end

-------------------------------------------------------------------------
-- Public entry points
-------------------------------------------------------------------------

-- True while the settings window is in wizard mode.
function ACAB:IsSetupWizardActive()
	return (ACAB.settingsFrame and ACAB.settingsFrame.wizardMode) and true or false
end

-- Re-shows the running wizard's current step (settings window re-opened mid-run).
function ACAB:ShowSetupWizardCurrentStep()
	if self.setupWizard and self.setupWizard.currentStep then
		self.setupWizard:ShowStep(self.setupWizard.currentStep)
	end
end

function ACAB:CancelSetupWizard()
	if self.setupWizard then
		self.setupWizard:Cancel()
	end
end

-- Login: reopens a wizard run saved before a reload, if it belongs to the active profile. Returns true if resumed.
function ACAB:ResumeSetupWizardIfPending()
	local saved = ACABCharDB and ACABCharDB.setupWizard

	if not saved then
		return false
	end

	if saved.profileName ~= ACABCharDB.activeProfile or not STEPS[saved.step] or STEPS[saved.step].kind ~= "page" then
		ACABCharDB.setupWizard = nil
		return false
	end

	local wizard = EnsureSetupWizard()

	wizard:Begin({
		profileName = saved.profileName,
		overwriteExisting = saved.overwriteExisting and true or false,
		layout = saved.layout,
		live = true,
		visited = saved.visited,
	})

	wizard:ShowStep(saved.step)

	return true
end

-- Opens the wizard fresh; config (optional) = { overwriteExisting = true, profileName = "..." }.
function ACAB:ShowSetupWizard(config)
	config = config or {}

	local overwriteExisting = config.overwriteExisting and true or false
	local profileName = overwriteExisting
		and (config.profileName or (ACABCharDB and ACABCharDB.activeProfile))
		or ((UnitName("player") or "Unknown") .. " - " .. (GetRealmName() or "Unknown"))

	-- A fresh run replaces any unfinished one.
	if ACABCharDB then
		ACABCharDB.setupWizard = nil
	end

	local wizard = EnsureSetupWizard()

	wizard:Begin({
		overwriteExisting = overwriteExisting,
		profileName = profileName,
	})

	wizard:ShowStep(overwriteExisting and "lock" or "name")

	return wizard
end

-------------------------------------------------------------------------
-- Baseline geometry for a profile carrying pendingLayoutBaseline: applied once the UI settled after login,
-- then saved and reloaded, so the final layout always loads from saved data (RunLoginSequence).
-------------------------------------------------------------------------

-- Seconds after login before the baseline pass measures live frames, and before the follow-up reload.
local BASELINE_SETTLE_DELAY = 2
local BASELINE_RELOAD_DELAY = 0.5

-- Applies Modern Layout geometry to the live ACABDB via the per-element reset functions.
function ACAB:ApplyModernLayoutGeometry()
	self:ApplyModernMainActionBarsLayout()
	self:ApplyModernVerticalBarClusterLayout()

	self:ResetPetBarLayoutToModernBase()
	self:ResetStanceBarPositionToModernBase()

	self:ResetPageIndicatorToModernBase()

	self:ApplyModernCornerClusterLayout()
end

-- Centers the Experience Bar at the bottom of its settings page's Y range.
local function PlaceExpBarAtBottom()
	local frame = getglobal(ACAB.EXP_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local _, _, minY = ACAB:GetSimpleElementCoordinateRange(frame, 2)

	if not minY then
		return
	end

	ACABDB.expBarPosition = {
		point = "CENTER", relativePoint = "CENTER", visualCenter = true,
		x = 0,
		y = minY,
	}

	ACAB:ApplyExpBarPosition()
end

-- Applies the pending baseline ("modern" geometry or the "vanilla" reset) to the live bars.
local function RunLayoutBaselinePass(self, layout)
	if layout == "modern" then
		-- must place the Exp Bar first: GetModernBaseExpBarClearance reads its saved position
		PlaceExpBarAtBottom()
		self:ApplyModernLayoutGeometry()
	elseif layout == "vanilla" then
		self:ResetAllElementsToVanillaLayout()
	end

	if ACABDB.pendingDisableExtraBars then
		ACABDB.pendingDisableExtraBars = nil

		local id

		for id = self.EXTRA_BAR_ID_START, self.EXTRA_BAR_ID_START + self.EXTRA_BAR_COUNT - 1 do
			self:SetExtraBarEnabled(id, false)
		end
	end

	-- Must run after Main Bar's final position.
	self:ApplyMainBarGroupedElements()
end

-- Schedules the loaded profile's pending baseline pass and the reload after it. Returns true if one is pending.
function ACAB:ApplyPendingLayoutBaseline()
	local layout = ACABDB.pendingLayoutBaseline

	if not layout then
		return false
	end

	self:Print("Applying the " .. (layout == "modern" and "Modern" or "Vanilla") .. " layout - your UI reloads in a moment.")

	C_Timer.After(BASELINE_SETTLE_DELAY, function()
		ACABDB.pendingLayoutBaseline = nil

		RunLayoutBaselinePass(ACAB, layout)

		ACAB:SaveActiveProfileData()

		C_Timer.After(BASELINE_RELOAD_DELAY, function()
			ReloadUI()
		end)
	end)

	return true
end
