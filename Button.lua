-- Button.lua
-- Pool button backed by an action slot (UseAction/PlaceAction/PickupAction/HasAction), a pet slot (isPetSlot)
-- or a shapeshift form index (isStanceSlot). Script handlers use global `this`; `:` methods use `self`.

local ACAB = AlternativeClassicActionBars

-- Hotkey/count/macro text inset from the button's edges, by border style.
ACAB.BUTTON_TEXT_INSET_VANILLA = 0
ACAB.BUTTON_TEXT_INSET_MODERN = 2

-- Equipment slots scanned by GetActionItemQualityColor: 0 (ammo) through 19 (tabard).
local FIRST_EQUIP_SLOT = 0
local LAST_EQUIP_SLOT = 19

-- Quality color of the equipped item an action slot holds, found by matching its texture against each equipment slot.
function ACAB:GetActionItemQualityColor(actionSlot)
	if not GetInventoryItemQuality or not GetInventoryItemTexture or not GetActionTexture or not GetItemQualityColor then
		return nil
	end
	local actionTexture = GetActionTexture(actionSlot)
	if not actionTexture then
		return nil
	end
	-- Case-insensitive: texture path casing varies by source.
	local actionTexLower = string.lower(actionTexture)
	for invSlot = FIRST_EQUIP_SLOT, LAST_EQUIP_SLOT do
		local invTex = GetInventoryItemTexture("player", invSlot)
		if invTex and string.lower(invTex) == actionTexLower then
			local quality = GetInventoryItemQuality("player", invSlot)
			if quality then
				return GetItemQualityColor(quality)
			end
		end
	end
	return nil
end

-- Blizzard's "Always Show Action Bars" global (not a CVar).
local function IsAlwaysShowMultibars()
	return ALWAYS_SHOW_MULTIBARS == "1" or ALWAYS_SHOW_MULTIBARS == 1
end

ACAB.IsAlwaysShowMultibars = IsAlwaysShowMultibars

-- Native ACTIONBAR_SHOWGRID/HIDEGRID state (set by Events.lua), for pool buttons.
ACAB.isShowingActionGrid = false

-- Calls fn(btn) for every pool button across every bar, without allocating.
function ACAB:ForEachPoolButton(fn)
	local barId
	local bar

	for barId, bar in pairs(ACAB.bars) do
		if bar and bar.buttons then
			local i

			for i = 1, table.getn(bar.buttons) do
				local btn = bar.buttons[i]

				if btn then
					fn(btn)
				end
			end
		end
	end
end

-- Re-evaluates UpdateGridVisibility on every pool button and re-lays out each bar.
function ACAB:SweepCustomBarGridVisibility()
	local barId

	for barId, bar in pairs(ACAB.bars) do
		if bar and bar.buttons then
			local i

			for i = 1, table.getn(bar.buttons) do
				local btn = bar.buttons[i]

				if btn then
					btn:UpdateGridVisibility()
				end
			end

			-- Pet Bar's condensed layout suspends itself while isShowingActionGrid is true.
			ACAB:LayoutButtons(bar)
		end
	end
end

function ACAB:SweepAllButtonRangeTint()
	ACAB:ForEachPoolButton(function(btn)
		btn:UpdateRange()
	end)
end

-- Toggles the global and refreshes native multibars and pool buttons immediately.
function ACAB:ToggleAlwaysShowMultibars()
	local newState = not IsAlwaysShowMultibars()

	ALWAYS_SHOW_MULTIBARS = newState and "1" or nil

	if MultiActionBar_UpdateGridVisibility then
		MultiActionBar_UpdateGridVisibility()
	end

	ACAB:SweepCustomBarGridVisibility()
end

ACABButtonMixin = {}

-- Native hotkey/count/macro fonts are captured once, on the first button created.
local hasCapturedFontDefaults = false

-- One shared ticker refreshes every button's range/usability and grid visibility; started lazily, never cancelled.
local sharedRangeTicker

local function RefreshButtonRangeAndGrid(btn)
	btn:UpdateRange()
	btn:UpdateGridVisibility()
end

local function EnsureSharedRangeTicker()
	if sharedRangeTicker or not (C_Timer and C_Timer.NewTicker) then
		return
	end

	sharedRangeTicker = C_Timer.NewTicker(0.2, function()
		ACAB:ForEachPoolButton(RefreshButtonRangeAndGrid)
	end)
end

-------------------------------------------------------------------------
-- Shared event dispatcher: one frame routes each event to the pool buttons that need it
-------------------------------------------------------------------------

-- Every pool button, and the same buttons split by slot type (filled by RegisterPoolButton).
local allPoolButtons = {}
local actionPoolButtons = {}
local petPoolButtons = {}
local stancePoolButtons = {}

-- Action slot -> action pool buttons currently showing it (paging can put two buttons on one slot).
local actionSlotButtons = {}

-- PLAYER_AURAS_CHANGED: updates only stance buttons whose form changed, then every stance cooldown if any did.
local function RefreshStanceButtonsOnAuraChange()
	local anyChanged = false
	local i

	for i = 1, table.getn(stancePoolButtons) do
		if stancePoolButtons[i]:UpdateStanceFormChange() then
			anyChanged = true
		end
	end

	if anyChanged then
		for i = 1, table.getn(stancePoolButtons) do
			stancePoolButtons[i]:UpdateCooldown()
		end
	end
end

-- Event -> button list + method to call on each (or a handler); playerOnly skips events whose arg1 isn't "player".
local POOL_BUTTON_EVENT_ROUTES = {
	BAG_UPDATE = { list = actionPoolButtons, method = "UpdateBagDependents" },
	UPDATE_MACROS = { list = actionPoolButtons, method = "Refresh" },
	-- New spells shift spellbook indexes cached by ResolveMacroTarget.
	LEARNED_SPELL_IN_TAB = { list = actionPoolButtons, method = "Refresh" },
	BAG_UPDATE_COOLDOWN = { list = allPoolButtons, method = "UpdateCooldown" },
	SPELL_UPDATE_COOLDOWN = { list = allPoolButtons, method = "UpdateCooldown" },
	ACTIONBAR_UPDATE_COOLDOWN = { list = allPoolButtons, method = "UpdateCooldown" },
	PET_BAR_UPDATE_COOLDOWN = { list = petPoolButtons, method = "UpdateCooldown" },
	UPDATE_SHAPESHIFT_COOLDOWN = { list = stancePoolButtons, method = "UpdateCooldown" },
	ACTIONBAR_UPDATE_USABLE = { list = actionPoolButtons, method = "UpdateRange" },
	SPELL_UPDATE_USABLE = { list = actionPoolButtons, method = "UpdateRange" },
	PLAYER_TARGET_CHANGED = { list = actionPoolButtons, method = "UpdateRange" },
	UPDATE_SHAPESHIFT_USABLE = { list = stancePoolButtons, method = "UpdateRange" },
	ACTIONBAR_UPDATE_STATE = { list = allPoolButtons, method = "UpdateState" },
	CRAFT_SHOW = { list = allPoolButtons, method = "UpdateState" },
	CRAFT_CLOSE = { list = allPoolButtons, method = "UpdateState" },
	TRADE_SKILL_SHOW = { list = allPoolButtons, method = "UpdateState" },
	TRADE_SKILL_CLOSE = { list = allPoolButtons, method = "UpdateState" },
	-- Auto Shot / Auto Attack start and stop (target cleared or dead).
	START_AUTOREPEAT_SPELL = { list = actionPoolButtons, method = "UpdateState" },
	STOP_AUTOREPEAT_SPELL = { list = actionPoolButtons, method = "UpdateState" },
	PLAYER_ENTER_COMBAT = { list = actionPoolButtons, method = "UpdateState" },
	PLAYER_LEAVE_COMBAT = { list = actionPoolButtons, method = "UpdateState" },
	UNIT_INVENTORY_CHANGED = { list = actionPoolButtons, method = "UpdateInventoryDependents", playerOnly = true },
	UNIT_PET = { list = petPoolButtons, method = "Refresh", playerOnly = true },
	PET_BAR_UPDATE = { list = petPoolButtons, method = "Refresh" },
	PLAYER_ENTERING_WORLD = { list = allPoolButtons, method = "Refresh" },
	-- UPDATE_SHAPESHIFT_FORM/_FORMS never fire here on form toggles (kept anyway); PLAYER_AURAS_CHANGED drives refresh.
	PLAYER_AURAS_CHANGED = { handler = RefreshStanceButtonsOnAuraChange },
	UPDATE_SHAPESHIFT_FORMS = { list = stancePoolButtons, method = "Refresh" },
	UPDATE_SHAPESHIFT_FORM = { list = stancePoolButtons, method = "Refresh" },
}

local poolButtonDispatcher

local function CallOnPoolButtons(list, method)
	local i

	for i = 1, table.getn(list) do
		local btn = list[i]

		btn[method](btn)
	end
end

local function AddToActionSlotMap(btn, slot)
	local list = actionSlotButtons[slot]

	if not list then
		list = {}
		actionSlotButtons[slot] = list
	end

	table.insert(list, btn)
end

local function RemoveFromActionSlotMap(btn, slot)
	local list = actionSlotButtons[slot]

	if not list then
		return
	end

	local i

	for i = table.getn(list), 1, -1 do
		if list[i] == btn then
			table.remove(list, i)
		end
	end
end

-- Refreshes the action pool buttons showing slot.
local function RefreshActionSlotButtons(slot)
	local list = actionSlotButtons[slot]

	if not list then
		return
	end

	local i

	for i = 1, table.getn(list) do
		local btn = list[i]

		if btn and btn.actionSlot == slot then
			btn:Refresh()
		end
	end
end

local function PoolButtonDispatcher_OnEvent()
	-- Copied first: per-button code can clobber the event/arg1 globals mid-loop.
	local ev = event
	local changedArg = arg1

	-- ACTIONBAR_SLOT_CHANGED arg1 0/nil means every slot.
	if ev == "ACTIONBAR_SLOT_CHANGED" then
		if not changedArg or changedArg == 0 then
			CallOnPoolButtons(allPoolButtons, "Refresh")
		else
			RefreshActionSlotButtons(changedArg)
		end

		return
	end

	local route = POOL_BUTTON_EVENT_ROUTES[ev]

	if not route or (route.playerOnly and changedArg ~= "player") then
		return
	end

	if route.handler then
		route.handler()
		return
	end

	CallOnPoolButtons(route.list, route.method)
end

-- Creates the dispatcher on the first pool button, so it registers after Events.lua's frames like the old per-button registration.
local function EnsurePoolButtonDispatcher()
	if poolButtonDispatcher then
		return
	end

	poolButtonDispatcher = CreateFrame("Frame")
	poolButtonDispatcher:RegisterEvent("ACTIONBAR_SLOT_CHANGED")

	local ev

	for ev in pairs(POOL_BUTTON_EVENT_ROUTES) do
		poolButtonDispatcher:RegisterEvent(ev)
	end

	poolButtonDispatcher:SetScript("OnEvent", PoolButtonDispatcher_OnEvent)
end

-- Adds a new pool button to the dispatcher's lists and slot map.
local function RegisterPoolButton(btn)
	table.insert(allPoolButtons, btn)

	if btn.isPetSlot then
		table.insert(petPoolButtons, btn)
	elseif btn.isStanceSlot then
		table.insert(stancePoolButtons, btn)
	else
		table.insert(actionPoolButtons, btn)
		AddToActionSlotMap(btn, btn.actionSlot)
	end

	EnsurePoolButtonDispatcher()
end

-- Moves an action pool button's slot-map entry after Rebind changed its slot.
local function MovePoolButtonActionSlot(btn, oldSlot, newSlot)
	if btn.isPetSlot or btn.isStanceSlot or oldSlot == newSlot then
		return
	end

	if oldSlot then
		RemoveFromActionSlotMap(btn, oldSlot)
	end

	AddToActionSlotMap(btn, newSlot)
end

-- Creates the vanilla-style border texture (UI-Quickslot2, centered with native 0/-1 offset, below other overlays).
local function CreateNativeBorder(btn)
	btn.border = btn:CreateTexture(nil, "OVERLAY")
	btn.border:SetDrawLayer("OVERLAY", -1)
	btn.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	btn.border:SetPoint("CENTER", btn, "CENTER", 0, -1)
end

-- Anchors the icon: inset 2px in modern style so the backdrop border shows, flush in vanilla style.
local function AnchorIcon(btn)
	local iconInset = btn.hasNativeBorder and 0 or 2

	btn.icon:SetPoint("TOPLEFT", btn, "TOPLEFT", iconInset, -iconInset)
	btn.icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -iconInset, iconInset)
end

-- Anchors the autocast Model to match the vanilla border's 0/-1 offset, or the modern backdrop's 1px inset.
local function AnchorAutoCastModel(btn, model)
	local modelInset = btn.hasNativeBorder and 0 or 1
	local modelYShift = btn.hasNativeBorder and -1 or 0

	model:ClearAllPoints()
	model:SetPoint("TOPLEFT", btn, "TOPLEFT", modelInset, -modelInset + modelYShift)
	model:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -modelInset, modelInset + modelYShift)
end

-- Sets the backdrop template for the current border style, fully transparent; UpdateBackdropVisibility colors it.
local function ApplyButtonBackdrop(btn)
	local backdropInset = btn.hasNativeBorder and 0 or 1

	btn:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = { left = backdropInset, right = backdropInset, top = backdropInset, bottom = backdropInset },
	})
	btn:SetBackdropColor(0, 0, 0, 0)
	btn:SetBackdropBorderColor(0, 0, 0, 0)

	-- Drop the cached backdrop state so UpdateBackdropVisibility rewrites it.
	btn.backdropShown = nil
end

-- Bar 1 keeps empty slots shown/bordered while useDefaultLayout is on, like native vanilla.
-- Must check id == 1, not dynamicDefaultBar (set for bars 1-5).
local function IsMainBarShowingEmpty(btn)
	return btn.parentBar and btn.parentBar.config and btn.parentBar.config.id == 1
		and ACABDB and ACABDB.useDefaultLayout ~= false
end

function ACABButtonMixin:Init(parent, actionSlot, slotIndex)
	self.actionSlot = actionSlot
	self.parentBar = parent
	self.slotIndex = slotIndex

	-- Pet Bar: actionSlot is a pet slot (1-10), not a vanilla action slot.
	self.isPetSlot = parent.config and parent.config.isPetBar and true or false

	-- Styled Stance Bar: actionSlot is a shapeshift form index (1-10), not a vanilla action slot.
	self.isStanceSlot = parent.config and parent.config.isStanceBar and true or false

	-- Set explicitly; strata inheritance from the parent bar isn't relied on.
	self:SetFrameStrata("LOW")

	-- Default bars (1-5): native binding action name (e.g. ACTIONBUTTON1) is the button's home binding identity.
	if parent.config and (parent.config.fixedActionSlots or parent.config.dynamicDefaultBar) and slotIndex then
		local prefix = ACAB.DEFAULT_BAR_BINDING_PREFIXES[parent.config.id]

		if prefix then
			self.nativeBindingId = prefix .. tostring(slotIndex)
		end
	end

	-- Live target for HoverBind.lua's ACABBIND<actionSlot - 72> dispatch.
	if actionSlot >= ACAB.ACTION_SLOT_START then
		ACAB.customBindTargets[actionSlot - 72] = self
	end

	if self.nativeBindingId then
		ACAB:SyncDefaultBarBindingRedirect(self)
	end

	-- Live target for ACABPETBIND<petSlot> / ACABSTANCEBIND<formIndex> dispatch.
	if self.isPetSlot then
		ACAB.petBindTargets[actionSlot] = self
	end

	if self.isStanceSlot then
		ACAB.stanceBindTargets[actionSlot] = self
	end

	-- Quality-colored equipped-item ring. Must exist before ApplySize below, or it stays unsized.
	self.equipRing = self:CreateTexture(nil, "OVERLAY")
	self.equipRing:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	self.equipRing:SetBlendMode("ADD")
	self.equipRing:SetPoint("CENTER", self, "CENTER", 0, 0)
	self.equipRing:Hide()

	-- Vanilla style draws a native border texture; modern style uses the backdrop border.
	self.hasNativeBorder = ACAB:IsVanillaBorderStyle()

	if self.hasNativeBorder then
		CreateNativeBorder(self)
	end

	self:ApplySize((parent.config and parent.config.buttonSize) or ACAB.BUTTON_SIZE)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	self:RegisterForDrag("LeftButton")
	self:EnableMouse(true)
	self:EnableMouseWheel(true)

	self.icon = self:CreateTexture(nil, "ARTWORK")
	AnchorIcon(self)
	self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- "Current action" glow, replicating a native CheckButton's CheckedTexture.
	self.glow = self:CreateTexture(nil, "OVERLAY")
	self.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	self.glow:SetBlendMode("ADD")
	self.glow:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
	self.glow:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
	self.glow:Hide()

	-- Static gold autocast indicator (Pet Bar).
	self.autoCastGlow = self:CreateTexture(nil, "OVERLAY")
	self.autoCastGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	self.autoCastGlow:SetBlendMode("ADD")
	self.autoCastGlow:SetVertexColor(1, 0.82, 0)
	self.autoCastGlow:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
	self.autoCastGlow:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
	self.autoCastGlow:Hide()

	-- Animated autocast glow (Pet Bar): reparents the native PetActionButton<n>AutoCast Model onto this button.
	-- A fresh Model with SetModel renders a flat white plane, so the native one is reused.
	if self.isPetSlot then
		local nativeModel = getglobal("PetActionButton" .. tostring(actionSlot) .. "AutoCast")

		if nativeModel then
			-- Native size, the base for UpdateAutoCastGlowScale.
			self.autoCastGlowModelNativeSize = nativeModel:GetWidth() or 27

			nativeModel:SetParent(self)
			AnchorAutoCastModel(self, nativeModel)
			nativeModel:SetFrameStrata("LOW")
			nativeModel:SetFrameLevel(self:GetFrameLevel())

			-- Never call :SetModel() on this frame again (resets it to a blank white plane); resize via SetModelScale.
			nativeModel:Hide()

			self.autoCastGlowModel = nativeModel

			self:UpdateAutoCastGlowScale()
		end
	end

	-- Cooldown spiral: a Model frame from CooldownFrameTemplate (no "Cooldown" widget type on 1.12).
	self.cooldown = CreateFrame("Model", nil, self, "CooldownFrameTemplate")
	self.cooldown:ClearAllPoints()
	self.cooldown:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -2)
	self.cooldown:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -2, 2)

	-- Must match the button's LOW strata, or the swipe defaults to MEDIUM and covers bags.
	self.cooldown:SetFrameStrata("LOW")
	self.cooldown:SetFrameLevel(self:GetFrameLevel() + 1)

	ApplyButtonBackdrop(self)

	self.count = self:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	self.hotkey = self:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")

	-- Captures the native fonts once. Must run after both FontStrings exist and before the SetFont calls below.
	if not hasCapturedFontDefaults then
		local hkPath, hkSize, hkFlags = self.hotkey:GetFont()
		local cntPath, cntSize, cntFlags = self.count:GetFont()

		ACAB.NATIVE_HOTKEY_FONT = { path = hkPath, size = hkSize, flags = hkFlags }
		ACAB.NATIVE_COUNT_FONT = { path = cntPath, size = cntSize, flags = cntFlags }

		-- Macro-name font from a native action button's Name region; falls back to the hotkey font.
		local macroFontFrame = getglobal("ActionButton1Name")

		if macroFontFrame and macroFontFrame.GetFont then
			local mPath, mSize, mFlags = macroFontFrame:GetFont()
			ACAB.NATIVE_MACRO_FONT = { path = mPath, size = mSize, flags = mFlags }
		else
			ACAB.NATIVE_MACRO_FONT = ACAB.NATIVE_HOTKEY_FONT
		end

		-- Default hotkey color, restored after an out-of-range tint.
		local hkR, hkG, hkB = self.hotkey:GetTextColor()
		ACAB.NATIVE_HOTKEY_TEXT_COLOR = { r = hkR, g = hkG, b = hkB }

		hasCapturedFontDefaults = true
	end

	-- Saved font sizes, falling back to the native size.
	self.hotkey:SetFont(
		ACAB.NATIVE_HOTKEY_FONT.path,
		(ACABDB and ACABDB.hotkeyFontSize) or ACAB.NATIVE_HOTKEY_FONT.size,
		ACAB.NATIVE_HOTKEY_FONT.flags
	)

	self.count:SetFont(
		ACAB.NATIVE_COUNT_FONT.path,
		(ACABDB and ACABDB.countFontSize) or ACAB.NATIVE_COUNT_FONT.size,
		ACAB.NATIVE_COUNT_FONT.flags
	)

	self.macroText = self:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	self.macroText:SetJustifyH("LEFT")
	self.macroText:SetFont(
		ACAB.NATIVE_MACRO_FONT.path,
		(ACABDB and ACABDB.macroFontSize) or ACAB.NATIVE_MACRO_FONT.size,
		ACAB.NATIVE_MACRO_FONT.flags
	)

	-- Anchors hotkey (top-right), count (bottom-right) and macro text (bottom-left).
	self:ApplyButtonTextInsets()

	self:SetScript("OnClick", ACABButtonMixin.OnClick)
	self:SetScript("OnReceiveDrag", ACABButtonMixin.OnReceiveDrag)
	self:SetScript("OnDragStart", ACABButtonMixin.OnDragStart)
	self:SetScript("OnDragStop", ACABButtonMixin.OnDragStop)
	self:SetScript("OnMouseWheel", ACABButtonMixin.OnMouseWheel)
	self:SetScript("OnEnter", ACABButtonMixin.OnEnter)
	self:SetScript("OnLeave", ACABButtonMixin.OnLeave)
	self:SetScript("OnMouseDown", ACABButtonMixin.OnMouseDown)

	-- Events reach this button through the shared dispatcher.
	RegisterPoolButton(self)

	self:Refresh()

	-- Covers range/usability changes with no event (e.g. moving relative to the target).
	EnsureSharedRangeTicker()
end

-- Resizes the button; CENTER-anchored equipRing/border are sized explicitly, the rest follow via anchors.
function ACABButtonMixin:ApplySize(size)
	self.buttonSize = size
	self:SetWidth(size)
	self:SetHeight(size)
	if self.equipRing then
		local ringSize = size * ACAB.EQUIP_RING_RATIO
		self.equipRing:SetWidth(ringSize)
		self.equipRing:SetHeight(ringSize)
	end
	if self.border then
		local borderSize = size * ACAB.BORDER_RATIO
		self.border:SetWidth(borderSize)
		self.border:SetHeight(borderSize)
	end

	self:UpdateAutoCastGlowScale()

	-- Re-checks hotkey/count/macro truncation width against the new size.
	if self.hotkey then
		self:UpdateHotkeyText()
	end
	if self.count then
		self:UpdateCount()
	end
	if self.macroText then
		self:UpdateMacroText()
	end
end

-- Rescales the reparented autocast glow Model via SetModelScale, which doesn't reset the model like SetModel does.
function ACABButtonMixin:UpdateAutoCastGlowScale()
	if not self.autoCastGlowModel or not self.autoCastGlowModelNativeSize
		or self.autoCastGlowModelNativeSize == 0
		or not self.autoCastGlowModel.SetModelScale
	then
		return
	end

	self.autoCastGlowModel:SetModelScale((self.buttonSize or ACAB.BUTTON_SIZE) / self.autoCastGlowModelNativeSize)
end

-- Re-anchors hotkey/count/macro text for the current border style; stores the inset for SetTruncatedButtonText.
function ACABButtonMixin:ApplyButtonTextInsets()
	local inset = self.hasNativeBorder and ACAB.BUTTON_TEXT_INSET_VANILLA or ACAB.BUTTON_TEXT_INSET_MODERN

	self.buttonTextInset = inset

	if self.hotkey then
		self.hotkey:ClearAllPoints()
		self.hotkey:SetPoint("TOPRIGHT", self, "TOPRIGHT", -inset, -inset)
	end

	if self.count then
		self.count:ClearAllPoints()
		self.count:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -inset, inset)
	end

	if self.macroText then
		self.macroText:ClearAllPoints()
		self.macroText:SetPoint("BOTTOMLEFT", self, "BOTTOMLEFT", inset, inset)
	end
end

-- Re-applies the current global border style to an existing button (same helpers as Init).
function ACABButtonMixin:ApplyBorderStyle()
	self.hasNativeBorder = ACAB:IsVanillaBorderStyle()

	self:ApplyButtonTextInsets()

	if self.hasNativeBorder then
		if not self.border then
			CreateNativeBorder(self)
		end

		self.border:Show()
	elseif self.border then
		self.border:Hide()
	end

	-- Re-sizes the border too.
	self:ApplySize(self.buttonSize or ACAB.BUTTON_SIZE)

	self.icon:ClearAllPoints()
	AnchorIcon(self)

	ApplyButtonBackdrop(self)

	if self.autoCastGlowModel then
		AnchorAutoCastModel(self, self.autoCastGlowModel)
	end

	self:UpdateBackdropVisibility()
end

-- Shows/hides this pool slot without destroying it (buttonCount below pool size).
function ACABButtonMixin:SetSlotVisible(visible)
	self.slotVisible = visible and true or false
	self:UpdateGridVisibility()
end

-- Final Show/Hide state: slotVisible combined with content, always-show rules, action-grid preview and edit mode.
function ACABButtonMixin:UpdateGridVisibility()
	local hasContent = self:IsSlotFilled() and true or false

	local isMainBar = IsMainBarShowingEmpty(self)

	-- Pet Bar shows all 10 slots like vanilla unless condensing is on.
	local petBarShowEmpty = self.isPetSlot and not ACAB:ShouldCondensePetBarSlots()

	-- ALWAYS_SHOW_MULTIBARS never applies to the Pet Bar, so it can't override the Condense option.
	local alwaysShowMultibars = (not self.isPetSlot) and IsAlwaysShowMultibars()

	-- Empty slots reappear while placing an action (action grid) and in edit mode.
	if self.slotVisible and (isMainBar or petBarShowEmpty or hasContent or alwaysShowMultibars or ACAB.isShowingActionGrid or ACAB:IsEditMode() or ACAB:IsHoverBindMode()) then
		if not self:IsShown() then
			self:Show()
		end
	elseif self:IsShown() then
		self:Hide()
	end

	-- Backdrop visibility must NOT include edit mode, or every empty slot's border reappears in edit mode.
	self:UpdateBackdropVisibility(hasContent, isMainBar)
end

-- Toggles the backdrop's color/border alpha and the native border texture; hasContent/isMainBar are optional precomputed values.
function ACABButtonMixin:UpdateBackdropVisibility(hasContent, isMainBar)
	if hasContent == nil then
		hasContent = self:IsSlotFilled() and true or false
	end

	if isMainBar == nil then
		isMainBar = IsMainBarShowingEmpty(self)
	end

	local shown = self.slotVisible and (isMainBar or hasContent or IsAlwaysShowMultibars() or ACAB.isShowingActionGrid or ACAB:IsHoverBindMode()) and true or false

	-- Skip the writes when neither the state nor the border style changed.
	if self.backdropShown == shown and self.backdropNativeBorder == self.hasNativeBorder then
		return
	end

	self.backdropShown = shown
	self.backdropNativeBorder = self.hasNativeBorder

	if shown then
		self:SetBackdropColor(0, 0, 0, 0.75)

		-- Vanilla style has its own border texture; don't double it with the backdrop edge.
		if not self.hasNativeBorder then
			self:SetBackdropBorderColor(1, 1, 1, 1)
		end
	else
		self:SetBackdropColor(0, 0, 0, 0)
		self:SetBackdropBorderColor(0, 0, 0, 0)
	end

	-- Guarded on hasNativeBorder, or a leftover texture reappears after switching to modern style.
	if self.border and self.hasNativeBorder then
		if shown then
			self.border:Show()
		else
			self.border:Hide()
		end
	end
end

-- Re-points this button at a different slot (bar slotStart/grid/page change) and moves its bind-target entry.
function ACABButtonMixin:Rebind(newActionSlot)
	local oldActionSlot = self.actionSlot

	-- Must clear the old entry before setting the new one (both can be the same slot).
	if oldActionSlot and oldActionSlot >= ACAB.ACTION_SLOT_START then
		ACAB.customBindTargets[oldActionSlot - 72] = nil
	end

	self.actionSlot = newActionSlot

	MovePoolButtonActionSlot(self, oldActionSlot, newActionSlot)

	if newActionSlot >= ACAB.ACTION_SLOT_START then
		ACAB.customBindTargets[newActionSlot - 72] = self
	end

	-- Default-bar buttons: the physical key follows whichever bar this slot now shows.
	if self.nativeBindingId then
		ACAB:SyncDefaultBarBindingRedirect(self)
	end

	self:Refresh()
end

-- True when the slot holds content (HasAction for action slots).
function ACABButtonMixin:IsSlotFilled()
	if self.isPetSlot then
		return GetPetActionInfo and GetPetActionInfo(self.actionSlot) ~= nil
	end

	-- Every stance pool button maps to a real, available form.
	if self.isStanceSlot then
		return true
	end

	return HasAction and HasAction(self.actionSlot)
end

-- Checked glow and (Pet Bar) autocast indicators.
function ACABButtonMixin:UpdateState()
	if self.isPetSlot then
		-- Must not use "X and X(...)": and/or truncate a multi-return call to one value.
		local isActive, autoCastEnabled

		if GetPetActionInfo then
			local _, _, _, _, activeVal, _, autoCastVal = GetPetActionInfo(self.actionSlot)
			isActive = activeVal
			autoCastEnabled = autoCastVal
		end

		if isActive then
			self.glow:Show()
		else
			self.glow:Hide()
		end

		local petCfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[ACAB.PET_BAR_ID]
		local animate = petCfg and petCfg.animateAutoCastGlow == true

		-- The Model animates by itself while shown.
		if autoCastEnabled and animate and self.autoCastGlowModel then
			self.autoCastGlow:Hide()
			self.autoCastGlowModel:Show()
		elseif autoCastEnabled then
			if self.autoCastGlowModel then
				self.autoCastGlowModel:Hide()
			end
			self.autoCastGlow:Show()
		else
			if self.autoCastGlowModel then
				self.autoCastGlowModel:Hide()
			end
			self.autoCastGlow:Hide()
		end

		return
	end

	-- Must use GetShapeshiftFormInfo's isActive: GetShapeshiftForm() returns nil here even while a form is active.
	if self.isStanceSlot then
		local isActive

		if GetShapeshiftFormInfo then
			local _, _, activeVal = GetShapeshiftFormInfo(self.actionSlot)
			isActive = activeVal
		end

		if isActive then
			self.glow:Show()
		else
			self.glow:Hide()
		end

		return
	end

	-- Vanilla ActionButton_UpdateState, driving self.glow instead of SetChecked.
	local slot = self.actionSlot
	local isCurrent = IsCurrentAction and IsCurrentAction(slot)
	local isAutoRepeat = IsAutoRepeatAction and IsAutoRepeatAction(slot)

	-- Macros (slots with action text) never glow for Auto Shot / Auto Attack, only for their own current cast.
	if GetActionText and GetActionText(slot) then
		if isAutoRepeat or (IsAttackAction and IsAttackAction(slot)) then
			isCurrent = nil
		end

		isAutoRepeat = nil
	end

	if isCurrent or isAutoRepeat then
		self.glow:Show()
	else
		self.glow:Hide()
	end
end

-------------------------------------------------------------------------
-- Macro target: the spell/item a macro's #showtooltip, /cast or /use names, skipping Auto Shot / Attack / Shoot
-------------------------------------------------------------------------

-- Auto-repeat/auto-attack spells never pick a macro's tooltip or icon.
local MACRO_SKIPPED_TARGETS = {
	["auto shot"] = true,
	["attack"] = true,
	["shoot"] = true,
}

-- The macro icon the client replaces with its own pick.
local MACRO_DYNAMIC_ICON = "interface\\icons\\inv_misc_questionmark"

-- '[cond] ?!"Name_X"; other' -> "name x": lower case, first alternative only, [conditions], "?"/"!"/"~"
-- prefixes, quotes and "_" (CleveRoid syntax) stripped; nil if empty or numeric.
-- Second return: true when the prefixes include CleveRoid's "?" (skip this action for icon/tooltip).
local function CleanMacroTargetName(text)
	local name = string.gsub(text, ";.*$", "")
	name = string.gsub(name, "%b[]", "")

	local found, foundEnd, prefix = string.find(name, "^([%s%?!~]*)")
	local skipForIcon = string.find(prefix, "?", 1, true) and true or false

	name = string.sub(name, foundEnd + 1)
	name = string.gsub(name, "%s+$", "")
	name = string.gsub(name, '^"(.*)"$', "%1")
	name = string.gsub(name, "_", " ")

	if name == "" or string.find(name, "^%d") then
		return nil
	end

	return string.lower(name), skipForIcon
end

-- Target name from a macro body: "#showtooltip <name>" first, else the first /cast or /use that isn't skipped
-- (Auto Shot / Attack / Shoot, or a "?" prefix), else the first Auto Shot / Attack / Shoot (an Auto-Shot-only macro
-- shows Auto Shot); "?" lines never count.
local function GetMacroTargetName(body)
	if not body then
		return nil
	end

	local firstCast
	local firstSkipped
	local line

	for line in string.gfind(body, "[^\r\n]+") do
		local found, foundEnd, command, rest = string.find(line, "^%s*([/#]%a+)%s*(.*)$")

		if command then
			command = string.lower(command)

			if command == "#showtooltip" or command == "#show" then
				local showName = CleanMacroTargetName(rest)

				if showName then
					return showName
				end
			elseif (command == "/cast" or command == "/use") and not firstCast then
				local castName, skipForIcon = CleanMacroTargetName(rest)

				if castName and not skipForIcon and not MACRO_SKIPPED_TARGETS[castName] then
					firstCast = castName
				elseif castName and not skipForIcon and not firstSkipped then
					firstSkipped = castName
				end
			end
		end
	end

	return firstCast or firstSkipped
end

-- Spellbook index for a lower-case name: the given "(Rank n)" if named, else the highest rank; nil if not known.
local function FindSpellIdByName(name)
	local found, foundEnd, baseName, rankText = string.find(name, "^(.-)%s*%((.-)%)%s*$")
	local spellName = baseName or name
	local match
	local i = 1

	while true do
		local bookName, bookRank = GetSpellName(i, "spell")

		if not bookName then
			break
		end

		if string.lower(bookName) == spellName
			and (not rankText or (bookRank and string.lower(bookRank) == rankText)) then
			match = i
		end

		i = i + 1
	end

	return match
end

-- Lower-case item name from an item link, or nil.
local function GetLinkItemName(link)
	if not link then
		return nil
	end

	local found, foundEnd, itemName = string.find(link, "%[(.-)%]")

	return itemName and string.lower(itemName)
end

-- Max stack size of the item in a link (GetItemInfo's 7th return), or nil.
local function GetLinkMaxStack(link)
	local found, foundEnd, itemId = string.find(link, "item:(%d+)")

	if not itemId then
		return nil
	end

	local itemName, itemLink, quality, minLevel, itemType, subType, maxStack = GetItemInfo(tonumber(itemId))

	return maxStack
end

-- Named item in the bags: first bag, slot, texture, then the total count over all stacks and the max stack size
-- (nil if none).
local function FindBagItemByName(name)
	local firstBag, firstSlot, firstTexture, firstLink
	local total = 0
	local bag

	for bag = 0, 4 do
		local slot

		for slot = 1, GetContainerNumSlots(bag) do
			local link = GetContainerItemLink(bag, slot)

			if GetLinkItemName(link) == name then
				local texture, itemCount = GetContainerItemInfo(bag, slot)

				total = total + (itemCount or 1)

				if not firstBag then
					firstBag, firstSlot, firstTexture, firstLink = bag, slot, texture, link
				end
			end
		end
	end

	if not firstBag then
		return nil
	end

	return firstBag, firstSlot, firstTexture, total, GetLinkMaxStack(firstLink)
end

-- Equipment slot holding the named item: invSlot, texture (nil if none).
local function FindEquippedItemByName(name)
	local invSlot

	for invSlot = FIRST_EQUIP_SLOT, LAST_EQUIP_SLOT do
		if GetLinkItemName(GetInventoryItemLink("player", invSlot)) == name then
			return invSlot, GetInventoryItemTexture("player", invSlot)
		end
	end

	return nil
end

-- Resolves this macro slot's target into macroTargetKind ("spell"/"bag"/"equip"/nil) + macroTargetA/B.
-- Returns the icon to show instead of GetActionTexture: always an item's own icon, a spell's only on the "?" macro icon.
-- Parsed name and spell index are cached per macro body; Refresh clears the cache (macroBody = nil).
function ACABButtonMixin:ResolveMacroTarget()
	self.macroTargetKind = nil

	local index = GetMacroIndexByName(self.macroName)

	if not index or index == 0 then
		return nil
	end

	local macroName, macroTexture, body = GetMacroInfo(index)

	if body ~= self.macroBody then
		self.macroBody = body
		self.macroTargetName = GetMacroTargetName(body)
		self.macroSpellId = self.macroTargetName and FindSpellIdByName(self.macroTargetName)

		-- Spellbook spelling, for nampower's name-based IsSpellUsable/IsSpellInRange.
		self.macroSpellName = self.macroSpellId and GetSpellName(self.macroSpellId, "spell")
	end

	local targetName = self.macroTargetName

	if not targetName then
		return nil
	end

	local spellId = self.macroSpellId

	if spellId then
		self.macroTargetKind = "spell"
		self.macroTargetA = spellId

		if macroTexture and string.lower(macroTexture) == MACRO_DYNAMIC_ICON then
			return GetSpellTexture(spellId, "spell")
		end

		return nil
	end

	local bag, bagSlot, bagTexture, bagTotal, maxStack = FindBagItemByName(targetName)

	if bag then
		self.macroTargetKind = "bag"
		self.macroTargetA = bag
		self.macroTargetB = bagSlot
		self.macroItemCount = bagTotal
		self.macroItemMaxStack = maxStack

		return bagTexture
	end

	local invSlot, invTexture = FindEquippedItemByName(targetName)

	if invSlot then
		self.macroTargetKind = "equip"
		self.macroTargetA = invSlot

		return invTexture
	end

	return nil
end

-- Icon for a filled action slot: the macro target's icon when ResolveMacroTarget picks one, else GetActionTexture.
function ACABButtonMixin:UpdateMacroIcon()
	local texture = self.macroName and self:ResolveMacroTarget()

	self.icon:SetTexture(texture or GetActionTexture(self.actionSlot))
end

-- Shows the macro target's tooltip on GameTooltip; false when the macro has no resolvable target.
function ACABButtonMixin:SetMacroTargetTooltip()
	self:ResolveMacroTarget()

	local kind = self.macroTargetKind

	if kind == "spell" then
		GameTooltip:SetSpell(self.macroTargetA, "spell")
	elseif kind == "bag" then
		GameTooltip:SetBagItem(self.macroTargetA, self.macroTargetB)
	elseif kind == "equip" then
		GameTooltip:SetInventoryItem("player", self.macroTargetA)
	else
		return false
	end

	return true
end

-- macroTargetKind of the last ResolveMacroTarget, or nil when this slot isn't a macro.
function ACABButtonMixin:GetMacroTargetKind()
	return self.macroName and self.macroTargetKind
end

-- BAG_UPDATE: a macro's target first (its item can appear, move or run out), then count, ring and cooldown.
function ACABButtonMixin:UpdateBagDependents()
	if self.macroName then
		self:UpdateMacroIcon()
	end

	self:UpdateCount()

	if self.macroName then
		self:UpdateEquipRing()
		self:UpdateCooldown()
	end
end

-- UNIT_INVENTORY_CHANGED: equip ring, plus a macro's re-resolved target (its item can move between bags and gear).
function ACABButtonMixin:UpdateInventoryDependents()
	if self.macroName then
		self:UpdateMacroIcon()
		self:UpdateCount()
		self:UpdateCooldown()
	end

	self:UpdateEquipRing()
end

function ACABButtonMixin:UpdateEquipRing()
	if self.isPetSlot or self.isStanceSlot then
		self.equipRing:Hide()
		return
	end

	-- Macro naming an equipped item: that item's quality.
	if self:GetMacroTargetKind() == "equip" then
		local quality = GetInventoryItemQuality("player", self.macroTargetA)

		if quality then
			local r, g, b = GetItemQualityColor(quality)

			self.equipRing:SetVertexColor(r, g, b)
			self.equipRing:Show()
		else
			self.equipRing:Hide()
		end

		return
	end

	if self.macroName and self.macroTargetKind then
		self.equipRing:Hide()
		return
	end

	if not self.actionSlot or not IsEquippedAction or not IsEquippedAction(self.actionSlot) then
		self.equipRing:Hide()
		return
	end

	local r, g, b = ACAB:GetActionItemQualityColor(self.actionSlot)
	if r then
		self.equipRing:SetVertexColor(r, g, b)
		self.equipRing:Show()
	else
		-- Quality unresolved (item not cached yet).
		self.equipRing:Hide()
	end
end

-- Stack-count text, only for consumable/stackable actions; equippable items (rings, trinkets) stay blank.
function ACABButtonMixin:UpdateCount()
	if not self.count then
		return
	end

	local text = ""
	local macroKind = self:GetMacroTargetKind()

	if macroKind == "bag" then
		-- Macro naming a bag item: total over all stacks, only for items that stack.
		if self.macroItemMaxStack and self.macroItemMaxStack > 1 then
			text = tostring(self.macroItemCount)
		end
	elseif macroKind then
		-- Macro naming a spell or an equipped item: no count.
		text = ""
	elseif not self.isPetSlot and not self.isStanceSlot and GetActionCount and self:IsSlotFilled()
		and ((IsConsumableAction and IsConsumableAction(self.actionSlot))
			or (IsStackableAction and IsStackableAction(self.actionSlot))) then
		local count = GetActionCount(self.actionSlot)

		if count and count > 0 then
			text = tostring(count)
		end
	end

	self:SetTruncatedButtonText(self.count, text)
end

-- Compact modifier abbreviation for hotkey text (e.g. "ALT-SHIFT-F" -> "a-s-F").
local HOTKEY_MODIFIER_ABBREVIATIONS = {
	ALT = "a",
	SHIFT = "s",
	CTRL = "c",
}

-- Compacts mouse-button keys ("BUTTON5" -> "MB5"); other tokens pass through.
local function CompactFinalKeyToken(finalToken)
	local _, _, mouseButtonNumber = string.find(finalToken, "^BUTTON(%d+)$")

	if mouseButtonNumber then
		return "MB" .. mouseButtonNumber
	end

	return finalToken
end

local function CompactBindingKeyText(key)
	if not key then
		return ""
	end

	local tokens = {}
	local n = 0
	local token

	for token in string.gfind(key, "[^%-]+") do
		n = n + 1
		tokens[n] = token
	end

	if n == 0 then
		return key
	end

	local parts = {}
	local i

	for i = 1, n - 1 do
		parts[i] = HOTKEY_MODIFIER_ABBREVIATIONS[tokens[i]] or tokens[i]
	end

	parts[n] = CompactFinalKeyToken(tokens[n])

	return table.concat(parts, "-")
end

-- Hotkey text for the button's live binding action (activeBindingId or GetHoverBindingId).
function ACABButtonMixin:UpdateHotkeyText()
	if not self.hotkey then
		return
	end

	local key = self.actionSlot and GetBindingKey(self.activeBindingId or ACAB:GetHoverBindingId(self))

	self:SetTruncatedButtonText(self.hotkey, key and CompactBindingKeyText(key) or "")
end

-- Truncates text to fit maxWidth, appending ".." when it doesn't.
local function SetTruncatedText(fontString, text, maxWidth)
	fontString:SetText(text)

	if maxWidth <= 0 or fontString:GetStringWidth() <= maxWidth then
		return
	end

	local truncated = text

	while string.len(truncated) > 1 and fontString:GetStringWidth() > maxWidth do
		truncated = string.sub(truncated, 1, string.len(truncated) - 1)
		fontString:SetText(truncated .. "..")
	end
end

-- Hides fontString for blank text, otherwise truncates it to the button's inner width and shows it.
function ACABButtonMixin:SetTruncatedButtonText(fontString, text)
	if not text or text == "" then
		fontString:Hide()
		return
	end

	local inset = self.buttonTextInset or 0
	local maxWidth = (self.buttonSize or ACAB.BUTTON_SIZE) - (2 * inset)

	SetTruncatedText(fontString, text, maxWidth)
	fontString:Show()
end

-- Macro name text for action slots, while ACABDB.showMacroText is on.
function ACABButtonMixin:UpdateMacroText()
	if not self.macroText then
		return
	end

	if self.isPetSlot or self.isStanceSlot or not (ACABDB and ACABDB.showMacroText) then
		self.macroText:Hide()
		return
	end

	local text = self:IsSlotFilled() and GetActionText and GetActionText(self.actionSlot)

	self:SetTruncatedButtonText(self.macroText, text or "")
end

function ACABButtonMixin:Refresh()
	if self.isPetSlot then
		-- Must not use "X and X(...)", and must keep the subtext (2nd) position or texture shifts.
		local name, texture, isToken

		if GetPetActionInfo then
			name, _, texture, isToken = GetPetActionInfo(self.actionSlot)
		end

		if name then
			-- Command slots (isToken) return a global name instead of a texture path.
			if isToken then
				texture = getglobal(texture) or texture
			end
			self.icon:SetTexture(texture)
		else
			self.icon:SetTexture(nil)
		end

		self.equipRing:Hide()
	elseif self.isStanceSlot then
		-- GetShapeshiftFormInfo(index) returns texture, name, isActive, isCastable.
		local texture, isActive, isCastable

		if GetShapeshiftFormInfo then
			local textureVal, nameVal, activeVal, castableVal = GetShapeshiftFormInfo(self.actionSlot)
			texture = textureVal
			isActive = activeVal
			isCastable = castableVal
		end

		-- Cache compared by UpdateStanceFormChange.
		self.stanceFormTexture = texture
		self.stanceFormActive = isActive
		self.stanceFormCastable = isCastable

		self.icon:SetTexture(texture)
		self.equipRing:Hide()
	elseif self:IsSlotFilled() then
		-- Macros carry their name as action text.
		self.macroName = GetActionText and GetActionText(self.actionSlot)
		self.macroBody = nil

		self:UpdateMacroIcon()
	else
		self.macroName = nil
		self.icon:SetTexture(nil)
		self.equipRing:Hide()
	end

	self:UpdateCount()
	self:UpdateCooldown()
	self:UpdateRange()
	self:UpdateState()
	self:UpdateEquipRing()
	self:UpdateHotkeyText()
	self:UpdateMacroText()

	self:UpdateGridVisibility()

	-- Pet Bar condense layout depends on which slots are filled.
	if self.isPetSlot and self.parentBar then
		local bar = self.parentBar

		-- One layout per bar per frame, however many pet buttons refresh together.
		if not bar.petLayoutPending then
			bar.petLayoutPending = true

			C_Timer.After(0, function()
				bar.petLayoutPending = nil
				ACAB:LayoutButtons(bar)
			end)
		end
	end
end

-- Stance slot: re-reads the form and updates icon + glow only if texture/isActive/isCastable changed; true on change.
function ACABButtonMixin:UpdateStanceFormChange()
	if not GetShapeshiftFormInfo then
		return false
	end

	-- Texture re-read too: some forms swap their icon on activation.
	local texture, nameVal, isActive, isCastable = GetShapeshiftFormInfo(self.actionSlot)

	if texture == self.stanceFormTexture and isActive == self.stanceFormActive and isCastable == self.stanceFormCastable then
		return false
	end

	self.stanceFormTexture = texture
	self.stanceFormActive = isActive
	self.stanceFormCastable = isCastable

	self.icon:SetTexture(texture)
	self:UpdateState()

	return true
end

-- Cooldown spiral from the pet, shapeshift or action cooldown (all plain start, duration, enable).
function ACABButtonMixin:UpdateCooldown()
	if not self.actionSlot or not CooldownFrame_SetTimer then
		return
	end

	local start, duration, enable

	if self.isPetSlot then
		if not GetPetActionCooldown then
			return
		end

		start, duration, enable = GetPetActionCooldown(self.actionSlot)
	elseif self.isStanceSlot then
		if not GetShapeshiftFormCooldown then
			return
		end

		start, duration, enable = GetShapeshiftFormCooldown(self.actionSlot)
	elseif self:GetMacroTargetKind() == "spell" then
		start, duration, enable = GetSpellCooldown(self.macroTargetA, "spell")
	elseif self:GetMacroTargetKind() == "bag" then
		start, duration, enable = GetContainerItemCooldown(self.macroTargetA, self.macroTargetB)
	elseif self:GetMacroTargetKind() == "equip" then
		start, duration, enable = GetInventoryItemCooldown("player", self.macroTargetA)
	else
		if not GetActionCooldown then
			return
		end

		start, duration, enable = GetActionCooldown(self.actionSlot)
	end

	CooldownFrame_SetTimer(self.cooldown, start or 0, duration or 0, enable or 0)
end

-- Range/usability icon tint (or hotkey-only red tint); untinted for pet/stance/empty slots.
function ACABButtonMixin:UpdateRange()
	-- Hoverbind mode owns icon tinting while active.
	if ACAB:IsHoverBindMode() then
		self.rangeKey = nil
		return
	end

	if self.isPetSlot or self.isStanceSlot or not self:IsSlotFilled() then
		if self.rangeKey ~= "none" then
			self.rangeKey = "none"
			self.icon:SetVertexColor(1, 1, 1)
			self:ResetHotkeyRangeColor()
		end
		return
	end

	local inRange = nil

	-- Defaults to "usable" when IsUsableAction isn't present.
	local usable, noMana = 1, nil

	local macroKind = self:GetMacroTargetKind()

	if macroKind == "spell" then
		-- Macro naming a spell: nampower's checks for that spell, by spellbook name.
		if IsSpellInRange and UnitExists("target") then
			inRange = IsSpellInRange(self.macroSpellName, "target")
		end

		if IsSpellUsable then
			usable, noMana = IsSpellUsable(self.macroSpellName)
		end
	elseif not macroKind then
		if IsActionInRange then
			inRange = IsActionInRange(self.actionSlot)
		end

		if IsUsableAction then
			usable, noMana = IsUsableAction(self.actionSlot)
		end
	end

	-- tintWholeButtonOnRange (default on) tints the icon; off tints only the hotkey red, like Blizzard buttons.
	local outOfRange = (inRange == 0)
	local tintWholeButton = ACABDB == nil or ACABDB.tintWholeButtonOnRange ~= false

	-- Matches vanilla ActionButton_UpdateUsable's priority: out-of-range wins, then usable/no-mana/unusable.
	local state
	if outOfRange and tintWholeButton then
		state = 1
	elseif usable and usable ~= 0 then
		state = 2
	elseif noMana and noMana ~= 0 then
		state = 3
	else
		state = 4
	end

	local redHotkey = outOfRange and not tintWholeButton
	local key = redHotkey and (state + 10) or state

	-- Skip every write while the tint state is unchanged.
	if self.rangeKey == key then
		return
	end

	self.rangeKey = key

	if state == 1 then
		self.icon:SetVertexColor(1.0, 0.15, 0.15)
	elseif state == 2 then
		self.icon:SetVertexColor(1.0, 1.0, 1.0)
	elseif state == 3 then
		self.icon:SetVertexColor(0.35, 0.35, 1.0)
	else
		self.icon:SetVertexColor(0.4, 0.4, 0.4)
	end

	-- Hotkey-text-only tint mode; resets to native color otherwise so a stale red hotkey never lingers.
	if redHotkey then
		self.hotkey:SetTextColor(1, 0, 0)
	else
		self:ResetHotkeyRangeColor()
	end
end

-- Restores the hotkey's native color (white if not captured yet).
function ACABButtonMixin:ResetHotkeyRangeColor()
	local c = ACAB.NATIVE_HOTKEY_TEXT_COLOR

	if c then
		self.hotkey:SetTextColor(c.r, c.g, c.b)
	else
		self.hotkey:SetTextColor(1, 1, 1)
	end
end

function ACABButtonMixin:PlaceCursor()
	-- Pet slots take a dropped pet spell/command via PickupPetAction; stance slots are fixed by the game.
	if self.isPetSlot then
		if PickupPetAction then
			PickupPetAction(self.actionSlot)
			self:Refresh()
		end

		return
	end

	if self.isStanceSlot then
		return
	end

	if PlaceAction then
		PlaceAction(self.actionSlot)
		self:Refresh()
	end
end

-- Script handlers below use global `this`.

-- Uses/casts the slot, or places the cursor's action. Edit mode never reaches here (bar overlay covers the button).
function ACABButtonMixin.OnClick()
	if ACAB:ButtonHasCursor() then
		this:PlaceCursor()
	elseif this.isPetSlot then
		-- Like vanilla PetActionButton_OnClick: left click casts, right click toggles autocast.
		if arg1 == "RightButton" then
			-- Must not use "X and X(...)": autoCastAllowed is the 6th return value.
			local autoCastAllowed

			if GetPetActionInfo then
				local _, _, _, _, _, allowedVal = GetPetActionInfo(this.actionSlot)
				autoCastAllowed = allowedVal
			end

			if autoCastAllowed and TogglePetAutocast then
				TogglePetAutocast(this.actionSlot)
			end
		elseif CastPetAction then
			CastPetAction(this.actionSlot)
		end

		this:UpdateState()
	elseif this.isStanceSlot then
		if CastShapeshiftForm then
			CastShapeshiftForm(this.actionSlot)
		end

		this:UpdateState()
	elseif this:IsSlotFilled() and UseAction then
		UseAction(this.actionSlot, 0, 0)

		-- Like ActionButtonUp: update the glow now instead of waiting on ACTIONBAR_UPDATE_STATE.
		-- Not for macros, or a "/cast Auto Shot" toggle leaves the glow stuck on.
		if not (GetActionText and GetActionText(this.actionSlot)) then
			this:UpdateState()
		end
	end
end

-- Hoverbind capture for Middle/Button4/Button5, which never reach OnClick.
function ACABButtonMixin.OnMouseDown()
	if not ACAB:IsHoverBindMode() then
		return
	end
	if arg1 == "LeftButton" or arg1 == "RightButton" then
		return
	end
	ACAB:HandleHoverBindMouseButton(this, arg1)
end

-- Drag handlers need no edit-mode guard: the bar overlay covers the buttons while editing.
function ACABButtonMixin.OnReceiveDrag()
	this:PlaceCursor()
end

-- Picks up the slot's action (pet slots via PickupPetAction; never stance slots) unless Lock Action Bars (LOCK_ACTIONBAR) is on.
function ACABButtonMixin.OnDragStart()
	if this.isStanceSlot then
		return
	end

	if ACAB:IsLockActionBars() then
		return
	end

	if this.isPetSlot then
		if this:IsSlotFilled() and PickupPetAction then
			PickupPetAction(this.actionSlot)
			this:Refresh()
		end

		return
	end

	if this:IsSlotFilled() and PickupAction then
		PickupAction(this.actionSlot)
		this:Refresh()
	end
end

function ACABButtonMixin.OnDragStop()
end

function ACABButtonMixin.OnMouseWheel()
	ACAB:ResizeBarFromWheel(this.parentBar, arg1)
end

function ACABButtonMixin.OnEnter()
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	if this.isPetSlot then
		-- Command slots (isToken) aren't real pet spells; SetPetAction can't show them, so the tooltip is built by hand.
		local name, subtext, isToken

		if GetPetActionInfo then
			name, subtext, _, isToken = GetPetActionInfo(this.actionSlot)
		end

		if isToken then
			GameTooltip:SetText(getglobal(name) or name, 1, 1, 1)

			if subtext then
				GameTooltip:AddLine(getglobal(subtext) or subtext, 0.5, 0.5, 0.5)
			end
		elseif this:IsSlotFilled() and GameTooltip.SetPetAction then
			GameTooltip:SetPetAction(this.actionSlot)
		else
			GameTooltip:SetText("AlternativeClassicActionBars")
		end
	elseif this.isStanceSlot then
		if GameTooltip.SetShapeshift then
			GameTooltip:SetShapeshift(this.actionSlot)
		else
			local name

			if GetShapeshiftFormInfo then
				local _, nameVal = GetShapeshiftFormInfo(this.actionSlot)
				name = nameVal
			end

			GameTooltip:SetText(name or "AlternativeClassicActionBars", 1, 1, 1)
		end
	elseif this.macroName and this:SetMacroTargetTooltip() then
		-- Tooltip of the macro's own /cast or /use target.
	elseif this:IsSlotFilled() and GameTooltip.SetAction then
		GameTooltip:SetAction(this.actionSlot)
	else
		GameTooltip:SetText("AlternativeClassicActionBars")
		GameTooltip:AddLine("Drag a spell, item, or macro here.", 1, 1, 1)
	end
	GameTooltip:Show()

	if ACAB:IsHoverBindMode() then
		ACAB:SetHoverBindHoveredCustomButton(this)
	end
end

function ACABButtonMixin.OnLeave()
	GameTooltip:Hide()

	if ACAB:IsHoverBindMode() then
		ACAB:ClearHoverBindHoveredButton(this)
	end
end

-- True when the cursor holds a spell, item or macro.
function ACAB:ButtonHasCursor()
	if GetCursorInfo then
		local cursorType = GetCursorInfo()
		if cursorType == "spell" or cursorType == "item" or cursorType == "macro" then
			return true
		end
	end
	if CursorHasSpell and CursorHasSpell() then
		return true
	end
	if CursorHasItem and CursorHasItem() then
		return true
	end
	if CursorHasMacro and CursorHasMacro() then
		return true
	end
	return false
end

-- Creates one pool button; its frame name is fixed per bar/slot index since each pool slot is created once.
function ACAB:CreateActionButton(parent, actionSlot, slotIndex)
	local frameName =
		"ACABButton" ..
		tostring(parent.config.id) ..
		"_" ..
		tostring(slotIndex or 1)

	local button = CreateFrame(
		"Button",
		frameName,
		parent
	)

	Mixin(button, ACABButtonMixin)

	button:Init(parent, actionSlot, slotIndex)

	return button
end

-------------------------------------------------------------------------
-- Global hotkey/count/macro font size and macro text toggle
-------------------------------------------------------------------------

-- Saves a rounded font size, then re-applies it (and re-truncates) on every pool button's regionKey FontString.
-- Before the native font is captured, the saved value is picked up by the next button Init.
local function SetPoolButtonFontSize(dbKey, nativeFontKey, regionKey, refreshMethod, size)
	ACAB:EnsureDB()

	-- GetFont() can return a float size.
	size = math.floor(size + 0.5)

	ACABDB[dbKey] = size

	local nativeFont = ACAB[nativeFontKey]

	if not nativeFont then
		return
	end

	local path = nativeFont.path
	local flags = nativeFont.flags

	ACAB:ForEachPoolButton(function(btn)
		local fontString = btn[regionKey]

		if fontString then
			fontString:SetFont(path, size, flags)
			btn[refreshMethod](btn)
		end
	end)
end

function ACAB:SetHotkeyFontSize(size)
	SetPoolButtonFontSize("hotkeyFontSize", "NATIVE_HOTKEY_FONT", "hotkey", "UpdateHotkeyText", size)
end

function ACAB:SetCountFontSize(size)
	SetPoolButtonFontSize("countFontSize", "NATIVE_COUNT_FONT", "count", "UpdateCount", size)
end

function ACAB:SetMacroFontSize(size)
	SetPoolButtonFontSize("macroFontSize", "NATIVE_MACRO_FONT", "macroText", "UpdateMacroText", size)
end

function ACAB:SetMacroTextEnabled(enabled)
	self:EnsureDB()

	ACABDB.showMacroText = enabled and true or false

	ACAB:ForEachPoolButton(function(btn)
		btn:UpdateMacroText()
	end)
end
