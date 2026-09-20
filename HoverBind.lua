-- HoverBind.lua
-- Hoverbind mode: hover a button, press a key to bind it. Mutually
-- exclusive with edit mode (Core.lua's SetEditMode/SetHoverBindMode).
--
-- Default-bar buttons (bars 1-5) bind through native binding actions
-- (ACTIONBUTTON1-12, MULTIACTIONBAR#BUTTON1-12) - their saved keybind always
-- lives under this nativeBindingId. Custom-bar slots (bars 6+) have no native
-- per-slot binding action, so they bind through this addon's own
-- bindings.xml-declared actions: ACABBIND1-48 (one per free action slot
-- 73-120), ACABPETBIND1-10 (styled Pet Bar, keyed by pet slot),
-- ACABSTANCEBIND1-10 (styled Stance Bar, keyed by shapeshift form index).
-- The native "Use Vanilla Pet/Stance Bar" containers aren't Bar.lua/
-- Button.lua pool buttons, so they're outside this system (like Bag Bar/
-- Micro Menu) and keybind only via native Blizzard Keybindings.
--
-- When DefaultBars.lua's stance/page-swap moves a default-bar button's
-- actionSlot into the 73-120 pool range, its native binding action would
-- still fire its own fixed vanilla slot, not this button's current one -
-- see SyncDefaultBarBindingRedirect below, which moves the physical key onto
-- that button's own ACABBIND<n> for as long as it stays swapped.
--
-- WARNING: SetBindingClick and SetBinding(key, "BONUSACTIONBUTTON1") are
-- both dead ends for custom slots on this client - they record in the
-- binding system but the input dispatcher never fires them.

local ACAB = AlternativeClassicActionBars

-- Custom-bar slot -> button lookup, keyed by actionSlot - 72 (1-48,
-- matching bindings.xml's ACABBIND1-48). Kept in sync by Button.lua
-- wherever a custom-bar button's actionSlot is set.
ACAB.customBindTargets = {}

-- Pet Bar slot -> button lookup, keyed by pet slot 1-10 directly (matching
-- bindings.xml's ACABPETBIND1-10). Styled Pet Bar only - see the
-- file header.
ACAB.petBindTargets = {}

-- Same, for the styled Stance Bar - keyed by shapeshift form index 1-10
-- directly (matching bindings.xml's ACABSTANCEBIND1-10).
ACAB.stanceBindTargets = {}

-- Must be a bare global function, not a ACAB: method - bindings.xml's
-- ACABBIND1-48 bodies can only invoke a plain global function name.
function ACAB_HoverBindFire(slotIndex)
	local btn = ACAB.customBindTargets and ACAB.customBindTargets[slotIndex]
	if btn then
		btn:Click()
	end
end

-- Same as ACAB_HoverBindFire, for bindings.xml's ACABPETBIND1-10.
function ACAB_PetHoverBindFire(petSlot)
	local btn = ACAB.petBindTargets and ACAB.petBindTargets[petSlot]
	if btn then
		btn:Click()
	end
end

-- Same as ACAB_HoverBindFire, for bindings.xml's ACABSTANCEBIND1-10.
function ACAB_StanceHoverBindFire(stanceIndex)
	local btn = ACAB.stanceBindTargets and ACAB.stanceBindTargets[stanceIndex]
	if btn then
		btn:Click()
	end
end

-- Resolves a button's real binding-action name: default-bar buttons use
-- their precomputed native name, styled Pet/Stance Bar slots use
-- ACABPETBIND<petSlot>/ACABSTANCEBIND<formIndex>, custom bars
-- (6+) use ACABBIND<actionSlot-72>.
function ACAB:GetHoverBindingId(btn)
	if btn.nativeBindingId then
		return btn.nativeBindingId
	elseif btn.isPetSlot then
		return "ACABPETBIND" .. tostring(btn.actionSlot)
	elseif btn.isStanceSlot then
		return "ACABSTANCEBIND" .. tostring(btn.actionSlot)
	else
		return "ACABBIND" .. tostring(btn.actionSlot - 72)
	end
end

-- Default-bar binding-action-name mapping: vanilla 1.12.1's own
-- Bindings.xml convention (MULTIACTIONBAR1BUTTON# for MultiBarBottomLeft,
-- MULTIACTIONBAR2BUTTON# for MultiBarBottomRight, MULTIACTIONBAR3BUTTON#
-- for MultiBarRight, MULTIACTIONBAR4BUTTON# for MultiBarLeft). Mirrors
-- DefaultBars.lua's DEFAULT_BAR_FRAME_PREFIXES.
ACAB.DEFAULT_BAR_BINDING_PREFIXES = {
	[1] = "ACTIONBUTTON",          -- Main bar.
	[2] = "MULTIACTIONBAR1BUTTON", -- Bottom Left.
	[3] = "MULTIACTIONBAR2BUTTON", -- Bottom Right.
	[4] = "MULTIACTIONBAR3BUTTON", -- Right.
	[5] = "MULTIACTIONBAR4BUTTON", -- Right 2.
}

-- Calls fn(ref) for every visible button on bars 1-5 and 6+ (both are
-- Bar.lua/Button.lua pool buttons). ref = { kind = "custom", frame,
-- bindingId, actionSlot, barId, slotIndex, fixedSlotBar (true if
-- btn.nativeBindingId is set, i.e. a default-bar button) }.

function ACAB:ForEachButton(fn)
	local barId
	for barId, bar in pairs(self.bars) do
		if bar and bar.buttons then
			local i
			for i = 1, table.getn(bar.buttons) do
				local btn = bar.buttons[i]
				if btn and btn.slotVisible then
					local bindingId = self:GetHoverBindingId(btn)

					fn({
						kind = "custom",
						frame = btn,
						bindingId = bindingId,
						actionSlot = btn.actionSlot,
						barId = barId,
						slotIndex = i,
						fixedSlotBar = btn.nativeBindingId and true or nil,
					})
				end
			end
		end
	end
end

-------------------------------------------------------------------------
-- Default-bar swap redirect
--
-- A default-bar button's saved keybind always lives under its nativeBindingId
-- (e.g. MULTIACTIONBAR1BUTTON1) - that's the one Blizzard's key-binding UI and
-- SaveBindings know about. But when DefaultBars.lua's stance/page-swap
-- assigns an Extra Bar to that button, the button's actionSlot moves into the
-- 73-120 pool range, and native binding actions always fire their own fixed
-- vanilla slot - never this button's current one. So while swapped, the key
-- is moved (session-only, never saved) onto this button's own ACABBIND<n>
-- action instead, which does dispatch through the button's current actionSlot.
-- btn.activeBindingId tracks which identity the key currently lives under.
-------------------------------------------------------------------------

-- Moves the key back onto btn.nativeBindingId if a previous sync redirected it away.
-- Called before reading/writing a default-bar button's binding directly (hoverbind edit/clear),
-- so those operations always see the true current key.
function ACAB:RehomeDefaultBarBinding(btn)
	if not btn or not btn.nativeBindingId then
		return
	end

	local liveId = btn.activeBindingId or btn.nativeBindingId

	if liveId ~= btn.nativeBindingId then
		local k1, k2 = GetBindingKey(liveId)

		if k1 then SetBinding(k1); SetBinding(k1, btn.nativeBindingId) end
		if k2 then SetBinding(k2); SetBinding(k2, btn.nativeBindingId) end
	end

	btn.activeBindingId = btn.nativeBindingId
end

-- Moves the key from btn.nativeBindingId onto ACABBIND<n> if btn.actionSlot is
-- currently swapped into the pool range, or back home if it isn't. Idempotent -
-- safe to call on every Rebind/Init even when nothing actually changed.
function ACAB:SyncDefaultBarBindingRedirect(btn)
	if not btn or not btn.nativeBindingId then
		return
	end

	local targetId = btn.nativeBindingId

	if btn.actionSlot and btn.actionSlot >= ACAB.ACTION_SLOT_START then
		targetId = "ACABBIND" .. tostring(btn.actionSlot - 72)
	end

	local liveId = btn.activeBindingId or btn.nativeBindingId

	if liveId == targetId then
		btn.activeBindingId = targetId
		return
	end

	-- Funnels through nativeBindingId so a chained swap (Extra Bar A -> Extra Bar B) always
	-- reads the key off one stable source instead of one custom id directly to another.
	if liveId ~= btn.nativeBindingId then
		local k1, k2 = GetBindingKey(liveId)

		if k1 then SetBinding(k1); SetBinding(k1, btn.nativeBindingId) end
		if k2 then SetBinding(k2); SetBinding(k2, btn.nativeBindingId) end
	end

	if targetId ~= btn.nativeBindingId then
		local k1, k2 = GetBindingKey(btn.nativeBindingId)

		if k1 then SetBinding(k1); SetBinding(k1, targetId) end
		if k2 then SetBinding(k2); SetBinding(k2, targetId) end
	end

	btn.activeBindingId = targetId
end

-------------------------------------------------------------------------
-- Bound check
-------------------------------------------------------------------------

function ACAB:IsButtonBound(ref)
	local id = (ref.frame and ref.frame.activeBindingId) or ref.bindingId
	return GetBindingKey(id) ~= nil
end

-------------------------------------------------------------------------
-- Tinting
--
-- Overrides Button.lua's normal range/usability tint while hoverbind mode
-- is active (UpdateRange short-circuits on ACAB:IsHoverBindMode()).
-------------------------------------------------------------------------

local HOVERBIND_BOUND_COLOR   = { 0.2, 1.0, 0.2 }
local HOVERBIND_UNBOUND_COLOR = { 1.0, 0.25, 0.25 }

function ACAB:TintHoverBindButton(ref)
	local icon = ref.frame.icon
	if not icon then
		return
	end

	local color = self:IsButtonBound(ref)
		and HOVERBIND_BOUND_COLOR
		or HOVERBIND_UNBOUND_COLOR

	icon:SetVertexColor(color[1], color[2], color[3])
end

-- Lets the button's own normal logic recompute range/usability tint
-- immediately rather than waiting on the next event/ticker tick.
local function RestoreButtonIconTint(ref)
	ref.frame:UpdateRange()
end

-- Called from Core.lua's SetHoverBindMode. Re-asserts tint on a repeating
-- ticker, not a one-shot pass - MultiBarRight/MultiBarLeft revert to white
-- shortly after a one-shot tint, so keep this on a ticker.
local HOVERBIND_TINT_INTERVAL = 0.25

function ACAB:ApplyHoverBindVisual(enabled)
	if self.hoverBindTintTicker then
		self.hoverBindTintTicker:Cancel()
		self.hoverBindTintTicker = nil
	end

	if enabled then
		self:ForEachButton(function(ref) self:TintHoverBindButton(ref) end)
		if C_Timer and C_Timer.NewTicker then
			self.hoverBindTintTicker = C_Timer.NewTicker(HOVERBIND_TINT_INTERVAL, function()
				-- Guards against hoverbind mode changing again before this
				-- already-queued tick fires.
				if ACAB:IsHoverBindMode() then
					ACAB:ForEachButton(function(ref) ACAB:TintHoverBindButton(ref) end)
				end
			end)
		end
	else
		self:ForEachButton(function(ref) RestoreButtonIconTint(ref) end)
	end

	local captureFrame = self.hoverBindCaptureFrame
	if captureFrame then
		if enabled then
			captureFrame:Show()
			captureFrame:EnableKeyboard(true)
		else
			captureFrame:EnableKeyboard(false)
			captureFrame:Hide()
			captureFrame.hoveredButton = nil
		end
	end
end

-------------------------------------------------------------------------
-- Hover tracking
--
-- Button.lua's OnEnter/OnLeave call SetHoverBindHoveredCustomButton /
-- ClearHoverBindHoveredButton directly while hoverbind mode is on,
-- covering both default and custom bars through one entry point.
-------------------------------------------------------------------------

function ACAB:SetHoverBindHoveredCustomButton(btn)
	if not self.hoverBindCaptureFrame or not btn or not btn.parentBar or not btn.parentBar.config then
		return
	end

	local bindingId = self:GetHoverBindingId(btn)

	self.hoverBindCaptureFrame.hoveredButton = {
		kind = "custom",
		frame = btn,
		bindingId = bindingId,
		actionSlot = btn.actionSlot,
		barId = btn.parentBar.config.id,
		slotIndex = btn.slotIndex,
		fixedSlotBar = btn.nativeBindingId and true or nil,
	}
end

function ACAB:ClearHoverBindHoveredButton(frame)
	if not self.hoverBindCaptureFrame then
		return
	end
	local hovered = self.hoverBindCaptureFrame.hoveredButton
	if hovered and hovered.frame == frame then
		self.hoverBindCaptureFrame.hoveredButton = nil
	end
end

-------------------------------------------------------------------------
-- Capture frame + key handling
-------------------------------------------------------------------------

local MODIFIER_KEYS = {
	LSHIFT = true, RSHIFT = true,
	LCTRL = true, RCTRL = true,
	LALT = true, RALT = true,
}

-- Mouse-button OnMouseDown arg1 name -> SetBinding/GetBindingKey key string.
-- OnMouseDown reports "MiddleButton"/"Button4"/"Button5", but the binding
-- system only recognizes "BUTTON3"/"BUTTON4"/"BUTTON5". LeftButton/
-- RightButton are deliberately absent - reserved for normal button use.
local MOUSE_BUTTON_BINDING_KEYS = {
	MiddleButton = "BUTTON3",
	Button4 = "BUTTON4",
	Button5 = "BUTTON5",
}

local function BuildComboString(key)
	local combo = ""
	if IsShiftKeyDown() then combo = combo .. "SHIFT-" end
	if IsControlKeyDown() then combo = combo .. "CTRL-" end
	if IsAltKeyDown() then combo = combo .. "ALT-" end
	return combo .. key
end

-- Refreshes tint/hotkey text for hovered after its binding changed.
local function RefreshHoverBindTarget(hovered)
	ACAB:TintHoverBindButton(hovered)
	if hovered.frame.UpdateHotkeyText then
		hovered.frame:UpdateHotkeyText()
	end
end

local function ApplyHoverBindKey(hovered, combo)
	-- Default-bar buttons: a prior swap may have moved the live key onto ACABBIND<n> -
	-- pull it back onto hovered.bindingId (nativeBindingId) first so the read/write below sees it.
	if hovered.fixedSlotBar then
		ACAB:RehomeDefaultBarBinding(hovered.frame)
	end

	local previousAction = GetBindingAction(combo)
	if previousAction and previousAction ~= "" and previousAction ~= hovered.bindingId then
		ACAB:Print("Rebound " .. combo .. " (was: " .. previousAction .. ")")
	end

	-- SetBinding only adds a key, it never clears old keys for an action.
	-- Clear any existing key(s) bound to hovered.bindingId first (SetBinding
	-- with no action unbinds it), or the old key keeps showing until reload.
	local existingKey1, existingKey2 = GetBindingKey(hovered.bindingId)

	if existingKey1 and existingKey1 ~= combo then
		SetBinding(existingKey1)
	end

	if existingKey2 and existingKey2 ~= combo then
		SetBinding(existingKey2)
	end

	SetBinding(combo, hovered.bindingId)

	SaveBindings(GetCurrentBindingSet())

	-- Pushes the freshly-saved key back out to ACABBIND<n> if the button is currently swapped.
	if hovered.fixedSlotBar then
		ACAB:SyncDefaultBarBindingRedirect(hovered.frame)
	end

	RefreshHoverBindTarget(hovered)
end

-- Escape deletes the hovered button's current keybind rather than binding
-- itself - it never becomes a keybind on this client.
local function ClearHoverBindKey(hovered)
	if hovered.fixedSlotBar then
		ACAB:RehomeDefaultBarBinding(hovered.frame)
	end

	local existingKey1, existingKey2 = GetBindingKey(hovered.bindingId)

	if not existingKey1 and not existingKey2 then
		if hovered.fixedSlotBar then
			ACAB:SyncDefaultBarBindingRedirect(hovered.frame)
		end
		return
	end

	if existingKey1 then
		SetBinding(existingKey1)
	end
	if existingKey2 then
		SetBinding(existingKey2)
	end

	SaveBindings(GetCurrentBindingSet())

	ACAB:Print("Cleared keybind for " .. hovered.bindingId)

	if hovered.fixedSlotBar then
		ACAB:SyncDefaultBarBindingRedirect(hovered.frame)
	end

	RefreshHoverBindTarget(hovered)
end

local function HoverBindCaptureFrame_OnKeyDown()
	local key = arg1
	if not key or MODIFIER_KEYS[key] then
		return
	end

	local hovered = this.hoveredButton
	if not hovered then
		return
	end

	if key == "ESCAPE" then
		ClearHoverBindKey(hovered)
		return
	end

	ApplyHoverBindKey(hovered, BuildComboString(key))
end

-- Called from Button.lua's OnMouseDown while hoverbind mode is active, for
-- any mouse button besides Left/Right (those never reach here - see the
-- guard in Button.lua). arg1's OnMouseDown name is looked up against
-- MOUSE_BUTTON_BINDING_KEYS since it isn't the string SetBinding expects.
function ACAB:HandleHoverBindMouseButton(frame, buttonName)
	local captureFrame = self.hoverBindCaptureFrame
	local hovered = captureFrame and captureFrame.hoveredButton
	if not hovered or hovered.frame ~= frame then
		return
	end

	local key = MOUSE_BUTTON_BINDING_KEYS[buttonName]
	if not key then
		return
	end

	ApplyHoverBindKey(hovered, BuildComboString(key))
end

local function CreateHoverBindCaptureFrame()
	local f = CreateFrame("Frame", "ACABHoverBindCaptureFrame", UIParent)
	f:EnableKeyboard(false)
	f:Hide()
	f:SetScript("OnKeyDown", HoverBindCaptureFrame_OnKeyDown)
	ACAB.hoverBindCaptureFrame = f
	return f
end

CreateHoverBindCaptureFrame()

