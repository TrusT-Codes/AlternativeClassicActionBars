-- Button.lua
-- Single action-slot-backed button, driven through native
-- UseAction/PlaceAction/PickupAction/HasAction. Pet Bar buttons
-- (self.isPetSlot) are backed by a pet slot (1-10) instead, driven through
-- CastPetAction/GetPetActionInfo/GetPetActionCooldown/TogglePetAutocast.
--
-- Engine-invoked script handlers receive the frame via global `this`, not
-- `self`. Methods called with `:` receive `self`.

local ACAB = AlternativeClassicActionBars

-- Hotkey/Count/Macro text's inset from the button's edges, by border style.
-- Applied by ApplyButtonTextInsets, read back by SetTruncatedButtonText.
ACAB.BUTTON_TEXT_INSET_VANILLA = 0
ACAB.BUTTON_TEXT_INSET_MODERN = 2

-- Gets the quality color for an action slot holding an equipped item.
-- Matches the action slot's texture against each inventory slot's texture
-- to find which equipment slot the item is in, then reads its quality.
local EQUIP_SLOTS_TO_SCAN = {
	0,  -- ammo
	1,  -- head
	2,  -- neck
	3,  -- shoulder
	4,  -- shirt
	5,  -- chest
	6,  -- waist
	7,  -- legs
	8,  -- feet
	9,  -- wrist
	10, -- hands
	11, -- finger1
	12, -- finger2
	13, -- trinket1
	14, -- trinket2
	15, -- back
	16, -- mainhand
	17, -- offhand
	18, -- ranged
	19, -- tabard
}

function ACAB:GetActionItemQualityColor(actionSlot)
	if not GetInventoryItemQuality or not GetInventoryItemTexture or not GetActionTexture or not GetItemQualityColor then
		return nil
	end
	local actionTexture = GetActionTexture(actionSlot)
	if not actionTexture then
		return nil
	end
	-- Lowercases both sides since texture path casing varies by call site.
	local actionTexLower = string.lower(actionTexture)
	for i = 1, table.getn(EQUIP_SLOTS_TO_SCAN) do
		local invSlot = EQUIP_SLOTS_TO_SCAN[i]
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

-- ALWAYS_SHOW_MULTIBARS is Blizzard's "Always Show Action Bars" global (string "1" when checked, not a CVar).
local function IsAlwaysShowMultibars()
	return ALWAYS_SHOW_MULTIBARS == "1" or ALWAYS_SHOW_MULTIBARS == 1
end

-- Exposed as a ACAB: method too so Menu.lua's minimap-dropdown toggle can read the same check.
ACAB.IsAlwaysShowMultibars = IsAlwaysShowMultibars

-- Mirrors native ACTIONBAR_SHOWGRID/HIDEGRID state for custom-bar buttons, which don't register for those events.
ACAB.isShowingActionGrid = false

-- Calls fn(btn) for every pool button across every bar. Hot per-tick sweep, no table allocation.
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

-- Re-evaluates UpdateGridVisibility on every live custom-bar button.
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

			-- Re-flow too: Pet Bar's condensed layout suspends itself while isShowingActionGrid is true.
			ACAB:LayoutButtons(bar)
		end
	end
end

-- Re-sweeps every live button's UpdateRange.
function ACAB:SweepAllButtonRangeTint()
	ACAB:ForEachPoolButton(function(btn)
		btn:UpdateRange()
	end)
end

-- Toggles the global and forces an immediate visual refresh on default and custom bars.
function ACAB:ToggleAlwaysShowMultibars()
	local newState = not IsAlwaysShowMultibars()

	ALWAYS_SHOW_MULTIBARS = newState and "1" or nil

	-- Default bars: drives MultiActionBarButton grid visibility.
	if MultiActionBar_UpdateGridVisibility then
		MultiActionBar_UpdateGridVisibility()
	end

	-- Custom bars: no native equivalent, sweep them directly.
	ACAB:SweepCustomBarGridVisibility()
end

ACABButtonMixin = {}

-- Native hotkey/count font default (path/size/flags), captured once via GetFont() on the first button created.
local hasCapturedFontDefaults = false

-- One shared ticker covers every button's range/usability + grid-visibility refresh; started lazily, never cancelled.
local sharedRangeTicker

local function EnsureSharedRangeTicker()
	if sharedRangeTicker or not (C_Timer and C_Timer.NewTicker) then
		return
	end

	sharedRangeTicker = C_Timer.NewTicker(0.2, function()
		ACAB:ForEachPoolButton(function(btn)
			btn:UpdateRange()
			btn:UpdateGridVisibility()
		end)
	end)
end

function ACABButtonMixin:Init(parent, actionSlot, slotIndex)
	self.actionSlot = actionSlot
	self.parentBar = parent
	self.slotIndex = slotIndex

	-- Pet Bar buttons: self.actionSlot holds a pet slot (1-10, GetPetActionInfo/
	-- CastPetAction/GetPetActionCooldown), not a real vanilla action slot -
	-- every action-slot-system call below branches on this flag instead.
	self.isPetSlot = parent.config and parent.config.isPetBar and true or false

	-- Stance Bar (styled mode) buttons: self.actionSlot holds a shapeshift
	-- form index (1-10, GetShapeshiftFormInfo/CastShapeshiftForm/
	-- GetShapeshiftFormCooldown), not a real vanilla action slot - every
	-- action-slot-system call below branches on this flag instead.
	self.isStanceSlot = parent.config and parent.config.isStanceBar and true or false

	-- Sets frame strata explicitly rather than relying on inheriting it
	-- from the parent bar frame, which is unconfirmed on this client.
	self:SetFrameStrata("HIGH")

	-- Default bars (1-5) show their real native keybind action name as
	-- hotkey text instead of going through the ACABBIND<n> dispatch table.
	-- A default bar's dynamic slot can land inside the 73-120 pool range, so
	-- self.nativeBindingId also excludes it from that table.
	if parent.config and (parent.config.fixedActionSlots or parent.config.dynamicDefaultBar) and slotIndex then
		local prefix = ACAB.DEFAULT_BAR_BINDING_PREFIXES and
			ACAB.DEFAULT_BAR_BINDING_PREFIXES[parent.config.id]

		if prefix then
			self.nativeBindingId = prefix .. tostring(slotIndex)
		end
	end

	-- Registers as the live target for HoverBind.lua's ACABBIND<n> dispatch (n = actionSlot - 72), keyed by action slot.
	if actionSlot >= ACAB.ACTION_SLOT_START and not self.nativeBindingId then
		ACAB.customBindTargets = ACAB.customBindTargets or {}
		ACAB.customBindTargets[actionSlot - 72] = self
	end

	-- Registers as the live target for HoverBind.lua's ACABPETBIND<n> dispatch, keyed by pet slot (1-10).
	if self.isPetSlot then
		ACAB.petBindTargets = ACAB.petBindTargets or {}
		ACAB.petBindTargets[actionSlot] = self
	end

	-- Same, for ACABSTANCEBIND<n> dispatch, keyed by shapeshift form index (1-10).
	if self.isStanceSlot then
		ACAB.stanceBindTargets = ACAB.stanceBindTargets or {}
		ACAB.stanceBindTargets[actionSlot] = self
	end

	-- Equipped-item ring, quality-colored.
	-- Must be created before ApplySize runs below, or it stays unsized/invisible until the bar next resizes.
	self.equipRing = self:CreateTexture(nil, "OVERLAY")
	self.equipRing:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	self.equipRing:SetBlendMode("ADD")
	self.equipRing:SetPoint("CENTER", self, "CENTER", 0, 0)
	self.equipRing:Hide()

	-- Native-accurate button border, default bars 1-5 only. Custom bars use the SetBackdrop-drawn border instead.
	self.hasNativeBorder = ACAB:IsVanillaBorderStyle()

	if self.hasNativeBorder then
		-- Sublevel -1, still above self.icon's "ARTWORK" layer, so the border frames the icon.
		self.border = self:CreateTexture(nil, "OVERLAY")
		self.border:SetDrawLayer("OVERLAY", -1)
		self.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
		-- Real vanilla border art is centered with a y = -1 offset.
		self.border:SetPoint("CENTER", self, "CENTER", 0, -1)
	end

	-- Initialize from the parent bar's configured size, not the global default, since bars can inherit a resized value.
	self:ApplySize((parent.config and parent.config.buttonSize) or ACAB.BUTTON_SIZE)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	self:RegisterForDrag("LeftButton")
	self:EnableMouse(true)
	self:EnableMouseWheel(true)

	-- Modern-style buttons inset the icon so the backdrop border stays visible; vanilla-style icon stays flush.
	local iconInset = self.hasNativeBorder and 0 or 2

	self.icon = self:CreateTexture(nil, "ARTWORK")
	self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", iconInset, -iconInset)
	self.icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -iconInset, iconInset)
	self.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

	-- "Current action" glow, replicating a native CheckButton's CheckedTexture.
	self.glow = self:CreateTexture(nil, "OVERLAY")
	self.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	self.glow:SetBlendMode("ADD")
	self.glow:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
	self.glow:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
	self.glow:Hide()

	-- Pet Bar autocast-enabled indicator, gold-tinted to read distinctly from the white glow above.
	self.autoCastGlow = self:CreateTexture(nil, "OVERLAY")
	self.autoCastGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	self.autoCastGlow:SetBlendMode("ADD")
	self.autoCastGlow:SetVertexColor(1, 0.82, 0)
	self.autoCastGlow:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
	self.autoCastGlow:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 0, 0)
	self.autoCastGlow:Hide()

	-- Animated autocast glow, Pet Bar only: reparents the native PetActionButton<n>AutoCast Model onto this button.
	-- A freshly created Model with SetModel+SetSequence renders as a flat white plane, so reuse the native one.
	if self.isPetSlot then
		local nativeModel = getglobal("PetActionButton" .. tostring(actionSlot) .. "AutoCast")

		if nativeModel then
			-- Native size (~27px), used to scale the glow proportionally in UpdateAutoCastGlowScale.
			self.autoCastGlowModelNativeSize = nativeModel:GetWidth() or 27

			-- Matches self.border's (0, -1) vanilla offset, or the backdrop border's inset in modern style.
			local modelInset = self.hasNativeBorder and 0 or 1
			local modelYShift = self.hasNativeBorder and -1 or 0

			nativeModel:SetParent(self)
			nativeModel:ClearAllPoints()
			nativeModel:SetPoint("TOPLEFT", self, "TOPLEFT", modelInset, -modelInset + modelYShift)
			nativeModel:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -modelInset, modelInset + modelYShift)
			nativeModel:SetFrameStrata("HIGH")
			nativeModel:SetFrameLevel(self:GetFrameLevel())

			-- Never call :SetModel() on this frame again - resets the reparented model to a blank white plane.
			-- Use SetModelScale (UpdateAutoCastGlowScale) to resize instead.
			nativeModel:Hide()

			self.autoCastGlowModel = nativeModel

			self:UpdateAutoCastGlowScale()
		end
	end

	-- Vanilla 1.12's cooldown spiral is a Model frame using CooldownFrameTemplate, not a "Cooldown" widget type.
	self.cooldown = CreateFrame("Model", nil, self, "CooldownFrameTemplate")
	self.cooldown:ClearAllPoints()
	self.cooldown:SetPoint("TOPLEFT", self, "TOPLEFT", 2, -2)
	self.cooldown:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -2, 2)

	-- Must match this button's "HIGH" strata, or the cooldown swipe defaults to "MEDIUM" and renders behind the icon.
	self.cooldown:SetFrameStrata("HIGH")
	self.cooldown:SetFrameLevel(self:GetFrameLevel() + 1)

	-- Backdrop template set once here; color/border alpha toggled later by UpdateBackdropVisibility.
	local backdropInset = self.hasNativeBorder and 0 or 1

	self:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = { left = backdropInset, right = backdropInset, top = backdropInset, bottom = backdropInset },
	})
	self:SetBackdropColor(0, 0, 0, 0)
	self:SetBackdropBorderColor(0, 0, 0, 0)

	-- Anchored by ApplyButtonTextInsets below.
	self.count = self:CreateFontString(nil, "OVERLAY", "NumberFontNormal")

	-- Keybind hotkey text, top-right.
	self.hotkey = self:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")

	-- Captures both font templates' native (path, size, flags) once.
	-- Must run after both FontStrings are created and before the SetFont calls below.
	if not hasCapturedFontDefaults then
		local hkPath, hkSize, hkFlags = self.hotkey:GetFont()
		local cntPath, cntSize, cntFlags = self.count:GetFont()

		ACAB.NATIVE_HOTKEY_FONT = { path = hkPath, size = hkSize, flags = hkFlags }
		ACAB.NATIVE_COUNT_FONT = { path = cntPath, size = cntSize, flags = cntFlags }

		-- Real vanilla macro-name font, captured from a native action button's Name region; falls back to hotkey font.
		local macroFontFrame = getglobal("ActionButton1Name")

		if macroFontFrame and macroFontFrame.GetFont then
			local mPath, mSize, mFlags = macroFontFrame:GetFont()
			ACAB.NATIVE_MACRO_FONT = { path = mPath, size = mSize, flags = mFlags }
		else
			ACAB.NATIVE_MACRO_FONT = ACAB.NATIVE_HOTKEY_FONT
		end

		-- Hotkey text's default color, used to reset the out-of-range tint back to normal.
		local hkR, hkG, hkB = self.hotkey:GetTextColor()
		ACAB.NATIVE_HOTKEY_TEXT_COLOR = { r = hkR, g = hkG, b = hkB }

		hasCapturedFontDefaults = true
	end

	-- Applies the saved font size, falling back to the captured native size.
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

	-- Macro name text, bottom-left. Anchored by ApplyButtonTextInsets below.
	self.macroText = self:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	self.macroText:SetJustifyH("LEFT")
	self.macroText:SetFont(
		ACAB.NATIVE_MACRO_FONT.path,
		(ACABDB and ACABDB.macroFontSize) or ACAB.NATIVE_MACRO_FONT.size,
		ACAB.NATIVE_MACRO_FONT.flags
	)

	-- Anchors all three now that they all exist and self.hasNativeBorder
	-- (set earlier in Init) is known.
	self:ApplyButtonTextInsets()

	self:SetScript("OnClick", ACABButtonMixin.OnClick)
	self:SetScript("OnReceiveDrag", ACABButtonMixin.OnReceiveDrag)
	self:SetScript("OnDragStart", ACABButtonMixin.OnDragStart)
	self:SetScript("OnDragStop", ACABButtonMixin.OnDragStop)
	self:SetScript("OnMouseWheel", ACABButtonMixin.OnMouseWheel)
	self:SetScript("OnEnter", ACABButtonMixin.OnEnter)
	self:SetScript("OnLeave", ACABButtonMixin.OnLeave)
	self:SetScript("OnMouseDown", ACABButtonMixin.OnMouseDown)

	self:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
	-- Drives the item stack-count text when bag count changes without a
	-- slot being re-placed (using/gaining/losing stacks of a consumable).
	self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("BAG_UPDATE_COOLDOWN")
	self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
	self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
	self:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
	self:RegisterEvent("SPELL_UPDATE_USABLE")
	self:RegisterEvent("PLAYER_TARGET_CHANGED")
	self:RegisterEvent("PLAYER_ENTERING_WORLD")
	-- Drives the equip-quality-ring, fires on equip/unequip.
	self:RegisterEvent("UNIT_INVENTORY_CHANGED")
	-- Drives the checked/glow state. CRAFT/TRADE_SKILL events cover a profession window's active action.
	self:RegisterEvent("ACTIONBAR_UPDATE_STATE")
	self:RegisterEvent("CRAFT_SHOW")
	self:RegisterEvent("CRAFT_CLOSE")
	self:RegisterEvent("TRADE_SKILL_SHOW")
	self:RegisterEvent("TRADE_SKILL_CLOSE")

	-- Pet Bar content has no ACTIONBAR_SLOT_CHANGED equivalent; these drive its refresh instead.
	if self.isPetSlot then
		self:RegisterEvent("PET_BAR_UPDATE")
		self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
		self:RegisterEvent("UNIT_PET")
	end

	-- UPDATE_SHAPESHIFT_FORM/_FORMS never fire on this client when toggling forms; PLAYER_AURAS_CHANGED drives the refresh.
	if self.isStanceSlot then
		self:RegisterEvent("UPDATE_SHAPESHIFT_FORMS")
		self:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
		self:RegisterEvent("UPDATE_SHAPESHIFT_COOLDOWN")
		self:RegisterEvent("UPDATE_SHAPESHIFT_USABLE")
		self:RegisterEvent("PLAYER_AURAS_CHANGED")
	end

	self:SetScript("OnEvent", ACABButtonMixin.OnEvent)

	self:Refresh()

	-- Covers range/usability changes with no dedicated event (e.g. walking toward/away from a target).
	EnsureSharedRangeTicker()
end

-- Resizes the button. icon/glow auto-track via anchors; equipRing/border are CENTER-anchored, resized explicitly.
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

-- Re-applies the current global border style to an already-created button without recreating the frame.
-- Must stay in lockstep with every self.hasNativeBorder-gated block in Init.
function ACABButtonMixin:ApplyBorderStyle()
	self.hasNativeBorder = ACAB:IsVanillaBorderStyle()

	self:ApplyButtonTextInsets()

	if self.hasNativeBorder then
		if not self.border then
			self.border = self:CreateTexture(nil, "OVERLAY")
			self.border:SetDrawLayer("OVERLAY", -1)
			self.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
			self.border:SetPoint("CENTER", self, "CENTER", 0, -1)
		end

		self.border:Show()
	elseif self.border then
		self.border:Hide()
	end

	-- Reuses ApplySize's own border-sizing math.
	self:ApplySize(self.buttonSize or ACAB.BUTTON_SIZE)

	local iconInset = self.hasNativeBorder and 0 or 2
	self.icon:ClearAllPoints()
	self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", iconInset, -iconInset)
	self.icon:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -iconInset, iconInset)

	local backdropInset = self.hasNativeBorder and 0 or 1
	self:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = { left = backdropInset, right = backdropInset, top = backdropInset, bottom = backdropInset },
	})

	-- Resets to transparent; real on/off state decided by UpdateBackdropVisibility below.
	self:SetBackdropColor(0, 0, 0, 0)
	self:SetBackdropBorderColor(0, 0, 0, 0)

	-- Matches the autocast glow Model's Init-time anchor math for the current border style.
	if self.autoCastGlowModel then
		local modelInset = self.hasNativeBorder and 0 or 1
		local modelYShift = self.hasNativeBorder and -1 or 0

		self.autoCastGlowModel:ClearAllPoints()
		self.autoCastGlowModel:SetPoint("TOPLEFT", self, "TOPLEFT", modelInset, -modelInset + modelYShift)
		self.autoCastGlowModel:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -modelInset, modelInset + modelYShift)
	end

	self:UpdateBackdropVisibility()
end

-- Shows/hides this pool slot without destroying it, for when buttonCount is smaller than the pool size.
function ACABButtonMixin:SetSlotVisible(visible)
	self.slotVisible = visible and true or false
	self:UpdateGridVisibility()
end

-- Final on-screen Show/Hide state, combining slotVisible (grid-shape membership) with content/ALWAYS_SHOW_MULTIBARS.
function ACABButtonMixin:UpdateGridVisibility()
	local hasContent = self:IsSlotFilled() and true or false

	-- Bar 1 never hides an empty button under Force Vanilla Layout Mode, unlike bars 2-5.
	-- Must check id == 1, not cfg.dynamicDefaultBar (true for bars 1-5 now).
	local isMainBar = self.parentBar and self.parentBar.config and self.parentBar.config.id == 1
		and ACABDB and ACABDB.useDefaultLayout ~= false

	-- Real vanilla's Pet Bar always shows all 10 slots; condensing empty slots is opt-in.
	local petBarShowEmpty = self.isPetSlot and not ACAB:ShouldCondensePetBarSlots()

	-- ALWAYS_SHOW_MULTIBARS only ever governed the real Blizzard multi
	-- bars (2-5) in native vanilla, never the Pet Bar - excluded here so
	-- that global checkbox (commonly on by default) can't override the
	-- Pet Bar's own dedicated Condense checkbox.
	local alwaysShowMultibars = (not self.isPetSlot) and IsAlwaysShowMultibars()

	-- ACAB.isShowingActionGrid makes an empty slot temporarily reappear
	-- while something is picked up to place, matching native behavior.
	-- ACAB:IsEditMode() is ORed in too so every slot is interactable
	-- (right-click-for-settings) while in edit mode, matching how default
	-- bars' overlay owns mouse interaction across the whole bar area.
	if self.slotVisible and (isMainBar or petBarShowEmpty or hasContent or alwaysShowMultibars or ACAB.isShowingActionGrid or ACAB:IsEditMode()) then
		self:Show()
	else
		self:Hide()
	end

	-- Backdrop visibility must NOT include ACAB:IsEditMode(), or every empty slot's border reappears in edit mode.
	self:UpdateBackdropVisibility()
end

-- Toggles only the backdrop's color/border alpha; the template set in Init is never touched again.
function ACABButtonMixin:UpdateBackdropVisibility()
	local hasContent = self:IsSlotFilled() and true or false

	-- Same Main Bar exemption as UpdateGridVisibility.
	local isMainBar = self.parentBar and self.parentBar.config and self.parentBar.config.id == 1
		and ACABDB and ACABDB.useDefaultLayout ~= false

	local shown = self.slotVisible and (isMainBar or hasContent or IsAlwaysShowMultibars() or ACAB.isShowingActionGrid)

	if shown then
		self:SetBackdropColor(0, 0, 0, 0.75)

		-- Vanilla-style buttons have their own border texture; skip the backdrop's border edge to avoid doubling it.
		if not self.hasNativeBorder then
			self:SetBackdropBorderColor(1, 1, 1, 1)
		end
	else
		self:SetBackdropColor(0, 0, 0, 0)
		self:SetBackdropBorderColor(0, 0, 0, 0)
	end

	-- Guarded on hasNativeBorder too, or a leftover texture reappears after switching to modern style.
	if self.border and self.hasNativeBorder then
		if shown then
			self.border:Show()
		else
			self.border:Hide()
		end
	end
end

-- Re-points this button at a different action slot when a bar's slotStart/grid/page state changes.
-- Only ACAB.customBindTargets' old/new slot indices need updating to follow it.
function ACABButtonMixin:Rebind(newActionSlot)
	local oldActionSlot = self.actionSlot

	-- Clears the old index first so a stale entry never briefly points at a button that no longer owns that slot.
	if ACAB.customBindTargets and oldActionSlot and oldActionSlot >= ACAB.ACTION_SLOT_START and not self.nativeBindingId then
		ACAB.customBindTargets[oldActionSlot - 72] = nil
	end

	self.actionSlot = newActionSlot

	if newActionSlot >= ACAB.ACTION_SLOT_START and not self.nativeBindingId then
		ACAB.customBindTargets = ACAB.customBindTargets or {}
		ACAB.customBindTargets[newActionSlot - 72] = self
	end

	self:Refresh()
end

-- Named IsSlotFilled, not HasAction, to avoid confusion with the vanilla API function it wraps.
function ACABButtonMixin:IsSlotFilled()
	if self.isPetSlot then
		return GetPetActionInfo and GetPetActionInfo(self.actionSlot) ~= nil
	end

	-- Stance Bar has no unassigned-slot concept; every visible pool button corresponds to a real, available form.
	if self.isStanceSlot then
		return true
	end

	return HasAction and HasAction(self.actionSlot)
end

function ACABButtonMixin:UpdateState()
	-- Pet Bar: GetPetActionInfo's isActive is IsCurrentAction's equivalent.
	if self.isPetSlot then
		-- Call directly, not "X and X(...)" - and/or collapse a multi-return call to one value.
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

		-- The Model self-animates once shown - just Show/Hide, no ticker.
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

	-- GetShapeshiftForm() returns nil on this client even while a form is active; use GetShapeshiftFormInfo's isActive.
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

	-- Same logic as vanilla ActionButton_UpdateState, driving self.glow directly instead of SetChecked.
	if (IsCurrentAction and IsCurrentAction(self.actionSlot)) or (IsAutoRepeatAction and IsAutoRepeatAction(self.actionSlot)) then
		self.glow:Show()
	else
		self.glow:Hide()
	end
end

function ACABButtonMixin:UpdateEquipRing()
	-- Pet/stance actions have no equip-quality concept.
	if self.isPetSlot or self.isStanceSlot then
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
		-- Quality unresolved (item not yet cached) - stay hidden rather than show a wrongly-colored ring.
		self.equipRing:Hide()
	end
end

-- Item stack-count text. A stackable action with 1 charge still shows "1"; a non-stacking action stays blank.
function ACABButtonMixin:UpdateCount()
	if not self.count then
		return
	end

	local text = ""

	-- Pet/stance actions never stack - no count concept.
	if not self.isPetSlot and not self.isStanceSlot and GetActionCount and self:IsSlotFilled() then
		local count = GetActionCount(self.actionSlot)

		if count and count > 1 then
			text = tostring(count)
		elseif count and count == 1 and
			((IsConsumableAction and IsConsumableAction(self.actionSlot)) or
			 (IsStackableAction and IsStackableAction(self.actionSlot))) then
			text = "1"
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

-- Compacts mouse-button bindings ("BUTTON5") to "MB5" so they fit the button; other tokens pass through unchanged.
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

	-- Lua 5.0 has no string.gmatch; string.gfind is the 5.0 equivalent.
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

-- Keybind hotkey text; see HoverBind.lua's ACAB:GetHoverBindingId for binding-action name resolution.
function ACABButtonMixin:UpdateHotkeyText()
	if not self.hotkey then
		return
	end

	local key = self.actionSlot and GetBindingKey(ACAB:GetHoverBindingId(self))

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

-- Shared by hotkey/count/macro text: hides fontString for blank text, otherwise truncates to the button's width and shows it.
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

-- Shows the macro name for a macro action, truncated to fit, while ACABDB.showMacroText is on.
function ACABButtonMixin:UpdateMacroText()
	if not self.macroText then
		return
	end

	-- Pet/stance actions have no macro/name-text concept shown on this button.
	if self.isPetSlot or self.isStanceSlot or not (ACABDB and ACABDB.showMacroText) then
		self.macroText:Hide()
		return
	end

	local text = self:IsSlotFilled() and GetActionText and GetActionText(self.actionSlot)

	self:SetTruncatedButtonText(self.macroText, text or "")
end

function ACABButtonMixin:Refresh()
	if self.isPetSlot then
		-- Call directly, not "X and X(...)" - subtext (2nd) must stay captured or texture (3rd) shifts position.
		local name, texture, isToken

		if GetPetActionInfo then
			name, _, texture, isToken = GetPetActionInfo(self.actionSlot)
		end

		if name then
			-- Special command slots return a global-name token instead of a real texture; getglobal resolves it.
			if isToken then
				texture = getglobal(texture) or texture
			end
			self.icon:SetTexture(texture)
		else
			self.icon:SetTexture(nil)
		end

		self.equipRing:Hide()
	elseif self.isStanceSlot then
		-- GetShapeshiftFormInfo(index) = texture, name, isActive, isCastable.
		local texture

		if GetShapeshiftFormInfo then
			texture = GetShapeshiftFormInfo(self.actionSlot)
		end

		self.icon:SetTexture(texture)
		self.equipRing:Hide()
	elseif self:IsSlotFilled() then
		local texture = GetActionTexture(self.actionSlot)
		self.icon:SetTexture(texture)
	else
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

	-- Re-evaluates final Show/Hide state now that content may have changed.
	self:UpdateGridVisibility()

	-- Pet Bar condense mode: content change can change which slots are filled, so recompute the compacted layout.
	if self.isPetSlot and self.parentBar then
		ACAB:LayoutButtons(self.parentBar)
	end
end

function ACABButtonMixin:UpdateCooldown()
	if not self.actionSlot or not CooldownFrame_SetTimer then
		return
	end

	if self.isPetSlot then
		if not GetPetActionCooldown then
			return
		end

		local start, duration, enable = GetPetActionCooldown(self.actionSlot)
		CooldownFrame_SetTimer(self.cooldown, start or 0, duration or 0, enable or 0)
		return
	end

	-- GetShapeshiftFormCooldown returns a plain (start, duration, enable) triple.
	if self.isStanceSlot then
		if not GetShapeshiftFormCooldown then
			return
		end

		local start, duration, enable = GetShapeshiftFormCooldown(self.actionSlot)
		CooldownFrame_SetTimer(self.cooldown, start or 0, duration or 0, enable or 0)
		return
	end

	if not GetActionCooldown then
		return
	end

	local start, duration, enable = GetActionCooldown(self.actionSlot)
	CooldownFrame_SetTimer(self.cooldown, start or 0, duration or 0, enable or 0)
end

function ACABButtonMixin:UpdateRange()
	-- Hoverbind mode owns icon tinting outright while active (HoverBind.lua's
	-- ApplyHoverBindVisual/tint pass) - short-circuit here so range/usability
	-- tinting can't fight it. Normal tinting resumes as soon as hoverbind
	-- mode turns off, since events keep calling UpdateRange throughout.
	if ACAB:IsHoverBindMode() then
		return
	end

	-- Pet actions have no range/usability concept - icon stays plain white.
	if self.isPetSlot then
		self.icon:SetVertexColor(1, 1, 1)
		self:ResetHotkeyRangeColor()
		return
	end

	-- Stance actions: no range concept; usability tinting deferred, icon stays plain white.
	if self.isStanceSlot then
		self.icon:SetVertexColor(1, 1, 1)
		self:ResetHotkeyRangeColor()
		return
	end

	if not self:IsSlotFilled() then
		self.icon:SetVertexColor(1, 1, 1)
		self:ResetHotkeyRangeColor()
		return
	end

	local inRange = nil
	if IsActionInRange then
		inRange = IsActionInRange(self.actionSlot)
	end

	-- Defaults to "usable" when IsUsableAction isn't present.
	local usable, noMana = 1, nil
	if IsUsableAction then
		usable, noMana = IsUsableAction(self.actionSlot)
	end

	-- Real Blizzard buttons only tint the hotkey text red on out-of-range; ACABDB.tintWholeButtonOnRange opts into whole-icon tint.
	local outOfRange = (inRange == 0)
	local tintWholeButton = ACABDB == nil or ACABDB.tintWholeButtonOnRange ~= false

	-- Matches vanilla ActionButton_UpdateUsable's priority: out-of-range wins, then usable/no-mana/unusable.
	if outOfRange and tintWholeButton then
		self.icon:SetVertexColor(1.0, 0.15, 0.15)
	elseif usable and usable ~= 0 then
		self.icon:SetVertexColor(1.0, 1.0, 1.0)
	elseif noMana and noMana ~= 0 then
		self.icon:SetVertexColor(0.35, 0.35, 1.0)
	else
		self.icon:SetVertexColor(0.4, 0.4, 0.4)
	end

	-- Hotkey-text-only tint mode; resets to native color otherwise so a stale red hotkey never lingers.
	if outOfRange and not tintWholeButton then
		self.hotkey:SetTextColor(1, 0, 0)
	else
		self:ResetHotkeyRangeColor()
	end
end

-- Restores self.hotkey to its captured native default color, or plain white if none captured yet.
function ACABButtonMixin:ResetHotkeyRangeColor()
	local c = ACAB.NATIVE_HOTKEY_TEXT_COLOR

	if c then
		self.hotkey:SetTextColor(c.r, c.g, c.b)
	else
		self.hotkey:SetTextColor(1, 1, 1)
	end
end

function ACABButtonMixin:PlaceCursor()
	-- Pet/Stance Bar slots are fixed by the game; dropping a cursor onto one is a no-op.
	if self.isPetSlot or self.isStanceSlot then
		return
	end

	if PlaceAction then
		PlaceAction(self.actionSlot)
		self:Refresh()
	end
end

-- Plain functions from here down: engine-invoked script handlers, using global `this`.

function ACABButtonMixin.OnEvent()
	if event == "ACTIONBAR_SLOT_CHANGED" then
		local changedSlot = arg1
		if not changedSlot or changedSlot == 0 or changedSlot == this.actionSlot then
			this:Refresh()
		end
	elseif event == "BAG_UPDATE" then
		this:UpdateCount()
	elseif event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "SPELL_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN" then
		this:UpdateCooldown()
	elseif event == "ACTIONBAR_UPDATE_USABLE" or event == "SPELL_UPDATE_USABLE" or event == "PLAYER_TARGET_CHANGED" then
		this:UpdateRange()
	elseif event == "ACTIONBAR_UPDATE_STATE" or event == "CRAFT_SHOW" or event == "CRAFT_CLOSE" or event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_CLOSE" then
		this:UpdateState()
	elseif event == "UNIT_INVENTORY_CHANGED" then
		if arg1 == "player" then
			this:UpdateEquipRing()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		this:Refresh()
	elseif event == "PET_BAR_UPDATE" then
		this:Refresh()
	elseif event == "PET_BAR_UPDATE_COOLDOWN" then
		this:UpdateCooldown()
	elseif event == "UNIT_PET" then
		if arg1 == "player" then
			this:Refresh()
		end
	elseif event == "UPDATE_SHAPESHIFT_FORMS" then
		this:Refresh()
	elseif event == "UPDATE_SHAPESHIFT_FORM" then
		-- Full Refresh, not just UpdateState - some forms swap their icon art on activation, not just the glow overlay.
		this:Refresh()
	elseif event == "UPDATE_SHAPESHIFT_COOLDOWN" then
		this:UpdateCooldown()
	elseif event == "UPDATE_SHAPESHIFT_USABLE" then
		this:UpdateRange()
	elseif event == "PLAYER_AURAS_CHANGED" then
		this:Refresh()
	end
end

function ACABButtonMixin.OnClick()
	-- Edit-mode interaction is owned by Bar.lua's per-bar overlay (TOOLTIP strata above this button), so never fires while editing.
	if ACAB:ButtonHasCursor() then
		this:PlaceCursor()
	elseif this.isPetSlot then
		-- Matches vanilla PetActionButton_OnClick: left click casts, right click toggles autocast.
		if arg1 == "RightButton" then
			-- Call directly, not "X and X(...)" - autoCastAllowed is the 6th return value.
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
		-- Matches real ActionButtonUp: update the glow immediately instead of waiting on ACTIONBAR_UPDATE_STATE.
		this:UpdateState()
	end
end

-- OnClick only fires for LeftButton/RightButton; Middle/Button4/5 still reach OnMouseDown, which hoverbind mode uses to capture them.
function ACABButtonMixin.OnMouseDown()
	if not ACAB:IsHoverBindMode() then
		return
	end
	if arg1 == "LeftButton" or arg1 == "RightButton" then
		return
	end
	if ACAB.HandleHoverBindMouseButton then
		ACAB:HandleHoverBindMouseButton(this, arg1)
	end
end

-- No edit-mode guard needed below: Bar.lua's per-bar overlay wins every hit-test within the bar while editing.
function ACABButtonMixin.OnReceiveDrag()
	this:PlaceCursor()
end

function ACABButtonMixin.OnDragStart()
	-- Pet/Stance Bar slots are fixed by the game, not drag-reassignable.
	if this.isPetSlot or this.isStanceSlot then
		return
	end

	-- Lock Action Bars gates whether dragging a filled button picks up its
	-- action, backed by the real Blizzard global LOCK_ACTIONBAR.
	if ACAB:IsLockActionBars() then
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
	if not ACAB:IsEditMode() then
		return
	end
	-- arg1 is the scroll delta: positive = scroll up, negative = scroll down.
	local delta = arg1 or 0
	local bar = this.parentBar
	if not bar or not bar.config then
		return
	end

	-- Default-bar-family bars (1-5, Pet Bar) respect useDefaultLayout's resize lock; custom bars never gated here.
	local barId = bar.config.id

	if ACAB:IsDefaultBarFamilyId(barId) and
		ACABDB and ACABDB.useDefaultLayout ~= false then
		return
	end

	local step = 2
	local newSize = bar.config.buttonSize + (delta * step)
	ACAB:SetBarButtonSize(bar, newSize)
end

function ACABButtonMixin.OnEnter()
	GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
	if this.isPetSlot then
		-- Special command slots are isToken actions, not real pet spells; SetPetAction can't tooltip those, build by hand.
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
		-- SetShapeshift exists on this client; hand-built fallback covers the case where it doesn't.
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
	elseif this:IsSlotFilled() and GameTooltip.SetAction then
		GameTooltip:SetAction(this.actionSlot)
	else
		GameTooltip:SetText("AlternativeClassicActionBars")
		GameTooltip:AddLine("Drag a spell, item, or macro here.", 1, 1, 1)
	end
	GameTooltip:Show()

	-- No-op unless hoverbind mode is on.
	if ACAB:IsHoverBindMode() and ACAB.SetHoverBindHoveredCustomButton then
		ACAB:SetHoverBindHoveredCustomButton(this)
	end
end

function ACABButtonMixin.OnLeave()
	GameTooltip:Hide()

	if ACAB:IsHoverBindMode() and ACAB.ClearHoverBindHoveredButton then
		ACAB:ClearHoverBindHoveredButton(this)
	end
end

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

function ACAB:CreateActionButton(parent, actionSlot, slotIndex)
	-- Frame names are stable for the bar's lifetime: one button object per pool slot, created exactly once.
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

	if Mixin then
		Mixin(button, ACABButtonMixin)
	else
		for k, v in pairs(ACABButtonMixin) do
			button[k] = v
		end
	end

	button:Init(parent, actionSlot, slotIndex)

	return button
end

-------------------------------------------------------------------------
-- Global hotkey/count font size (Settings.lua's General tab)
--
-- Sweeps every live button in ACAB.bars.
-------------------------------------------------------------------------

function ACAB:SetHotkeyFontSize(size)
	self:EnsureDB()

	-- Rounds to an integer since GetFont() can return a float size.
	size = math.floor(size + 0.5)

	ACABDB.hotkeyFontSize = size

	-- Nothing captured yet this session - the write above is enough, the next button Init picks it up.
	if not ACAB.NATIVE_HOTKEY_FONT then
		return
	end

	local path = ACAB.NATIVE_HOTKEY_FONT.path
	local flags = ACAB.NATIVE_HOTKEY_FONT.flags

	ACAB:ForEachPoolButton(function(btn)
		if btn.hotkey then
			btn.hotkey:SetFont(path, size, flags)

			-- SetFont alone doesn't re-run truncation.
			btn:UpdateHotkeyText()
		end
	end)
end

function ACAB:SetCountFontSize(size)
	self:EnsureDB()

	-- Rounds to an integer since GetFont() can return a float size.
	size = math.floor(size + 0.5)

	ACABDB.countFontSize = size

	if not ACAB.NATIVE_COUNT_FONT then
		return
	end

	local path = ACAB.NATIVE_COUNT_FONT.path
	local flags = ACAB.NATIVE_COUNT_FONT.flags

	ACAB:ForEachPoolButton(function(btn)
		if btn.count then
			btn.count:SetFont(path, size, flags)
			btn:UpdateCount()
		end
	end)
end

function ACAB:SetMacroFontSize(size)
	self:EnsureDB()

	-- Rounds to an integer since GetFont() can return a float size.
	size = math.floor(size + 0.5)

	ACABDB.macroFontSize = size

	-- Nothing captured yet this session - the write above is enough, the next button Init picks it up.
	if not ACAB.NATIVE_MACRO_FONT then
		return
	end

	local path = ACAB.NATIVE_MACRO_FONT.path
	local flags = ACAB.NATIVE_MACRO_FONT.flags

	ACAB:ForEachPoolButton(function(btn)
		if btn.macroText then
			btn.macroText:SetFont(path, size, flags)

			-- SetFont alone doesn't re-run truncation.
			btn:UpdateMacroText()
		end
	end)
end

function ACAB:SetMacroTextEnabled(enabled)
	self:EnsureDB()

	ACABDB.showMacroText = enabled and true or false

	ACAB:ForEachPoolButton(function(btn)
		btn:UpdateMacroText()
	end)
end
