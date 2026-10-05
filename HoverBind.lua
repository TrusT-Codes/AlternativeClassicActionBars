-- HoverBind.lua
-- Hoverbind mode: hover a pool button, press a key to bind it (native actions on default bars, else bindings.xml's
-- ACABBIND/ACABPETBIND/ACABSTANCEBIND).
-- WARNING: SetBindingClick and SetBinding(key, "BONUSACTIONBUTTON1") never fire on this client - don't use them.

local ACAB = AlternativeClassicActionBars

-- Binding-dispatch lookups kept current by Button.lua: actionSlot - 72 (1-48), pet slot (1-10), form index (1-10).
ACAB.customBindTargets = {}
ACAB.petBindTargets = {}
ACAB.stanceBindTargets = {}

-- Must stay plain globals: bindings.xml bodies can only call a global function.
function ACAB_HoverBindFire(slotIndex)
	local btn = ACAB.customBindTargets[slotIndex]
	if btn then
		btn:Click()
	end
end

function ACAB_PetHoverBindFire(petSlot)
	local btn = ACAB.petBindTargets[petSlot]
	if btn then
		btn:Click()
	end
end

function ACAB_StanceHoverBindFire(stanceIndex)
	local btn = ACAB.stanceBindTargets[stanceIndex]
	if btn then
		btn:Click()
	end
end

-- prefix .. n binding-action names, built once per (prefix, n).
local bindingIdCache = { ACABPETBIND = {}, ACABSTANCEBIND = {}, ACABBIND = {} }

local function CachedBindingId(prefix, n)
	local cache = bindingIdCache[prefix]
	local id = cache[n]

	if not id then
		id = prefix .. tostring(n)
		cache[n] = id
	end

	return id
end

-- A button's home binding-action name: nativeBindingId, ACABPETBIND<n>, ACABSTANCEBIND<n> or ACABBIND<actionSlot - 72>.
function ACAB:GetHoverBindingId(btn)
	if btn.nativeBindingId then
		return btn.nativeBindingId
	elseif btn.isPetSlot then
		return CachedBindingId("ACABPETBIND", btn.actionSlot)
	elseif btn.isStanceSlot then
		return CachedBindingId("ACABSTANCEBIND", btn.actionSlot)
	else
		return CachedBindingId("ACABBIND", btn.actionSlot - 72)
	end
end

-- Native binding-action prefixes of default bars 1-5 (vanilla Bindings.xml names).
ACAB.DEFAULT_BAR_BINDING_PREFIXES = {
	[1] = "ACTIONBUTTON",          -- Main bar.
	[2] = "MULTIACTIONBAR1BUTTON", -- Bottom Left.
	[3] = "MULTIACTIONBAR2BUTTON", -- Bottom Right.
	[4] = "MULTIACTIONBAR3BUTTON", -- Right.
	[5] = "MULTIACTIONBAR4BUTTON", -- Right 2.
}

-- Fills ref as the hoverbind reference (frame, bindingId) for a pool button.
local function FillButtonRef(ref, btn)
	ref.frame = btn
	ref.bindingId = ACAB:GetHoverBindingId(btn)

	return ref
end

-- Reused by every ForEachButton call.
local sharedButtonRef = {}

-- Calls fn(ref) for every visible pool button. ref is one reused table: fn must not keep it.
function ACAB:ForEachButton(fn)
	local barId
	for barId, bar in pairs(self.bars) do
		if bar and bar.buttons then
			local i
			for i = 1, table.getn(bar.buttons) do
				local btn = bar.buttons[i]
				if btn and btn.slotVisible then
					fn(FillButtonRef(sharedButtonRef, btn))
				end
			end
		end
	end
end

-------------------------------------------------------------------------
-- Default-bar swap redirect: session-only key move onto ACABBIND<n> (btn.activeBindingId) while a swap shows a pool slot
-------------------------------------------------------------------------

-- Keys a default-bar swap redirect moved off their native action (key -> true).
local redirectedBindingKeys = {}

-- First key bound to bindingId that isn't a default-bar button's redirected key, or nil.
function ACAB:GetOwnBindingKey(bindingId)
	local k1, k2, k3, k4 = GetBindingKey(bindingId)

	if k1 and not redirectedBindingKeys[k1] then return k1 end
	if k2 and not redirectedBindingKeys[k2] then return k2 end
	if k3 and not redirectedBindingKeys[k3] then return k3 end
	if k4 and not redirectedBindingKeys[k4] then return k4 end

	return nil
end

-- Moves btn's own native keys onto targetId and remembers them in btn.redirectedKeys.
local function RedirectOwnKeys(btn, targetId)
	local keys = btn.redirectedKeys or {}
	local i

	keys[1], keys[2] = GetBindingKey(btn.nativeBindingId)
	btn.redirectedKeys = keys

	for i = 1, 2 do
		local key = keys[i]

		if key then
			redirectedBindingKeys[key] = true
			SetBinding(key)
			SetBinding(key, targetId)
		end
	end
end

-- Moves only the keys RedirectOwnKeys moved back onto btn.nativeBindingId (other keys of the target stay).
local function RestoreOwnKeys(btn)
	local keys = btn.redirectedKeys
	if not keys then return end

	local i

	for i = 1, 2 do
		local key = keys[i]

		if key then
			redirectedBindingKeys[key] = nil
			keys[i] = nil

			if GetBindingAction(key) == btn.activeBindingId then
				SetBinding(key)
				SetBinding(key, btn.nativeBindingId)
			end
		end
	end
end

-- Moves the key back onto btn.nativeBindingId; called before a hoverbind edit/clear reads or writes it.
function ACAB:RehomeDefaultBarBinding(btn)
	if not btn or not btn.nativeBindingId then return end

	local liveId = btn.activeBindingId or btn.nativeBindingId
	if liveId ~= btn.nativeBindingId then
		RestoreOwnKeys(btn)
	end

	btn.activeBindingId = btn.nativeBindingId
end

-- Moves the key onto ACABBIND<n> while btn.actionSlot is in the pool range, else back home. Idempotent.
function ACAB:SyncDefaultBarBindingRedirect(btn)
	if not btn or not btn.nativeBindingId then return end

	local targetId = btn.nativeBindingId

	if btn.actionSlot and btn.actionSlot >= ACAB.ACTION_SLOT_START then
		targetId = CachedBindingId("ACABBIND", btn.actionSlot - 72)
	end

	local liveId = btn.activeBindingId or btn.nativeBindingId
	if liveId == targetId then
		btn.activeBindingId = targetId
		return
	end

	-- Always funnels through nativeBindingId, so chained swaps read the key from one stable source.
	if liveId ~= btn.nativeBindingId then
		RestoreOwnKeys(btn)
	end

	if targetId ~= btn.nativeBindingId then
		RedirectOwnKeys(btn, targetId)
	end

	btn.activeBindingId = targetId
end

-- Calls fn(btn) for every default-bar pool button, hidden ones included.
local function ForEachDefaultBarButton(fn)
	local barId
	for barId, bar in pairs(ACAB.bars) do
		if bar and bar.buttons then
			local i
			for i = 1, table.getn(bar.buttons) do
				local btn = bar.buttons[i]
				if btn and btn.nativeBindingId then
					fn(btn)
				end
			end
		end
	end
end

-- Rehomes every default-bar button's key onto its native action.
local function RehomeAllDefaultBarBindings()
	ForEachDefaultBarButton(function(btn) ACAB:RehomeDefaultBarBinding(btn) end)
end

-- Re-applies every default-bar button's swap redirect.
local function SyncAllDefaultBarBindingRedirects()
	ForEachDefaultBarButton(function(btn) ACAB:SyncDefaultBarBindingRedirect(btn) end)
end

-------------------------------------------------------------------------
-- Bound check
-------------------------------------------------------------------------

function ACAB:IsButtonBound(ref)
	local id = (ref.frame and ref.frame.activeBindingId) or ref.bindingId
	return GetBindingKey(id) ~= nil
end

-------------------------------------------------------------------------
-- Tinting: bound/unbound icon tint while hoverbind mode is on
-------------------------------------------------------------------------

local HOVERBIND_BOUND_COLOR   = { 0.2, 1.0, 0.2 }
local HOVERBIND_UNBOUND_COLOR = { 1.0, 0.25, 0.25 }

function ACAB:TintHoverBindButton(ref)
	local icon = ref.frame.icon
	if not icon then return end

	local color = self:IsButtonBound(ref)
		and HOVERBIND_BOUND_COLOR
		or HOVERBIND_UNBOUND_COLOR

	icon:SetVertexColor(color[1], color[2], color[3])

	-- Forces UpdateRange to repaint once hoverbind ends.
	ref.frame.rangeKey = nil
end

-- Recomputes the button's normal range/usability tint immediately.
local function RestoreButtonIconTint(ref)
	ref.frame:UpdateRange()
end

local function TintHoverBindRef(ref)
	ACAB:TintHoverBindButton(ref)
end

local function HoverBindTintTick()
	-- Skips a tick queued before hoverbind mode turned off.
	if ACAB:IsHoverBindMode() then
		ACAB:ForEachButton(TintHoverBindRef)
	end
end

-- Must re-tint on a ticker, not once: MultiBarRight/MultiBarLeft buttons revert to white after a one-shot tint.
local HOVERBIND_TINT_INTERVAL = 0.25

-- Starts/stops hoverbind tinting and the key-capture frame (called by Core.lua's SetHoverBindMode).
function ACAB:ApplyHoverBindVisual(enabled)
	if self.hoverBindTintTicker then
		self.hoverBindTintTicker:Cancel()
		self.hoverBindTintTicker = nil
	end

	if enabled then
		self:ForEachButton(TintHoverBindRef)
		self.hoverBindTintTicker = C_Timer.NewTicker(HOVERBIND_TINT_INTERVAL, HoverBindTintTick)
	else
		self:ForEachButton(RestoreButtonIconTint)
	end

	-- Empty slots show while binding and revert to their normal visibility afterwards.
	self:SweepCustomBarGridVisibility()

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
-- Hover tracking (called from Button.lua's OnEnter/OnLeave in hoverbind mode)
-------------------------------------------------------------------------

function ACAB:SetHoverBindHoveredCustomButton(btn)
	if not self.hoverBindCaptureFrame or not btn or not btn.parentBar or not btn.parentBar.config then return end

	self.hoverBindCaptureFrame.hoveredButton = FillButtonRef({}, btn)
end

function ACAB:ClearHoverBindHoveredButton(frame)
	if not self.hoverBindCaptureFrame then return end
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

-- OnMouseDown button name -> binding key name; Left/Right are reserved for normal clicks.
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
	-- A key moved off another button must clear that button's hotkey text too.
	ACAB:ForEachPoolButton(function(btn)
		btn:UpdateHotkeyText()
	end)
end

-- Binds combo to the hovered button's action (replacing its old keys), saves, and refreshes it.
local function ApplyHoverBindKey(hovered, combo)
	-- Must rehome all first, or SaveBindings persists session-only ACABBIND<n> redirects.
	RehomeAllDefaultBarBindings()

	local previousAction = GetBindingAction(combo)
	if previousAction and previousAction ~= "" and previousAction ~= hovered.bindingId then
		ACAB:Print("Rebound " .. combo .. " (was: " .. previousAction .. ")")
	end

	-- SetBinding only adds keys; unbind the action's old keys first.
	local existingKey1, existingKey2 = GetBindingKey(hovered.bindingId)

	if existingKey1 and existingKey1 ~= combo then
		SetBinding(existingKey1)
	end

	if existingKey2 and existingKey2 ~= combo then
		SetBinding(existingKey2)
	end

	SetBinding(combo, hovered.bindingId)

	SaveBindings(GetCurrentBindingSet())

	SyncAllDefaultBarBindingRedirects()

	RefreshHoverBindTarget(hovered)
end

-- Removes the hovered button's keybinds (Escape).
local function ClearHoverBindKey(hovered)
	-- Must rehome all first, or SaveBindings persists session-only ACABBIND<n> redirects.
	RehomeAllDefaultBarBindings()

	local existingKey1, existingKey2 = GetBindingKey(hovered.bindingId)

	if not existingKey1 and not existingKey2 then
		SyncAllDefaultBarBindingRedirects()
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

	SyncAllDefaultBarBindingRedirects()

	RefreshHoverBindTarget(hovered)
end

-- Escape clears the hovered button's binding instead of being bound.
local function HoverBindCaptureFrame_OnKeyDown()
	local key = arg1
	if not key or MODIFIER_KEYS[key] then return end

	local hovered = this.hoveredButton
	if not hovered then return end

	if key == "ESCAPE" then
		ClearHoverBindKey(hovered)
		return
	end

	ApplyHoverBindKey(hovered, BuildComboString(key))
end

-- Binds Middle/Button4/Button5 (from Button.lua's OnMouseDown) to the hovered button.
function ACAB:HandleHoverBindMouseButton(frame, buttonName)
	local captureFrame = self.hoverBindCaptureFrame
	local hovered = captureFrame and captureFrame.hoveredButton
	if not hovered or hovered.frame ~= frame then return end

	local key = MOUSE_BUTTON_BINDING_KEYS[buttonName]
	if not key then return end

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

