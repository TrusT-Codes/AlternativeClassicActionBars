-- HoverBind.lua
-- Hoverbind mode: hover a button, press a key to bind it. Mutually
-- exclusive with edit mode (Core.lua's SetEditMode/SetHoverBindMode).
--
-- Default-bar buttons (bars 1-5) bind through native binding actions
-- (ACTIONBUTTON1-12, MULTIACTIONBAR#BUTTON1-12). Custom-bar slots (bars
-- 6+) have no native per-slot binding action, so they bind through this
-- addon's own bindings.xml-declared actions: ACABBIND1-48 (one per
-- free action slot 73-120), ACABPETBIND1-10 (styled Pet Bar, keyed
-- by pet slot), ACABSTANCEBIND1-10 (styled Stance Bar, keyed by
-- shapeshift form index). The native "Use Vanilla Pet/Stance Bar"
-- containers aren't Bar.lua/Button.lua pool buttons, so they're outside
-- this system (like Bag Bar/Micro Menu) and keybind only via native
-- Blizzard Keybindings.
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
-- Bound check
-------------------------------------------------------------------------

function ACAB:IsButtonBound(ref)
	return GetBindingKey(ref.bindingId) ~= nil
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

	RefreshHoverBindTarget(hovered)
end

-- Escape deletes the hovered button's current keybind rather than binding
-- itself - it never becomes a keybind on this client.
local function ClearHoverBindKey(hovered)
	local existingKey1, existingKey2 = GetBindingKey(hovered.bindingId)

	if not existingKey1 and not existingKey2 then
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

