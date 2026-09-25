-- HoverBind.lua
-- Hoverbind mode: hover a pool button, press a key to bind it. Default bars bind their native actions
-- (ACTIONBUTTON#, MULTIACTIONBAR#BUTTON#); custom/styled Pet/Stance slots bind bindings.xml's ACABBIND/ACABPETBIND/ACABSTANCEBIND.
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

-- A button's home binding-action name: nativeBindingId, ACABPETBIND<n>, ACABSTANCEBIND<n> or ACABBIND<actionSlot - 72>.
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

-- Native binding-action prefixes of default bars 1-5 (vanilla Bindings.xml names).
ACAB.DEFAULT_BAR_BINDING_PREFIXES = {
	[1] = "ACTIONBUTTON",          -- Main bar.
	[2] = "MULTIACTIONBAR1BUTTON", -- Bottom Left.
	[3] = "MULTIACTIONBAR2BUTTON", -- Bottom Right.
	[4] = "MULTIACTIONBAR3BUTTON", -- Right.
	[5] = "MULTIACTIONBAR4BUTTON", -- Right 2.
}

-- Hoverbind reference for a pool button (fixedSlotBar = default-bar button with a nativeBindingId).
local function MakeButtonRef(btn, barId, slotIndex)
	return {
		kind = "custom",
		frame = btn,
		bindingId = ACAB:GetHoverBindingId(btn),
		actionSlot = btn.actionSlot,
		barId = barId,
		slotIndex = slotIndex,
		fixedSlotBar = btn.nativeBindingId and true or nil,
	}
end

-- Calls fn(ref) for every visible pool button.
function ACAB:ForEachButton(fn)
	local barId
	for barId, bar in pairs(self.bars) do
		if bar and bar.buttons then
			local i
			for i = 1, table.getn(bar.buttons) do
				local btn = bar.buttons[i]
				if btn and btn.slotVisible then
					fn(MakeButtonRef(btn, barId, i))
				end
			end
		end
	end
end

-------------------------------------------------------------------------
-- Default-bar swap redirect: while a stance/page swap puts a default-bar
-- button's actionSlot in the pool range, its key is moved (session-only,
-- never saved) from nativeBindingId onto ACABBIND<n>, since native actions
-- always fire their fixed vanilla slot. btn.activeBindingId tracks where it is.
-------------------------------------------------------------------------

-- Rebinds every key of fromId onto toId.
local function MoveBindingKeys(fromId, toId)
	local k1, k2 = GetBindingKey(fromId)

	if k1 then SetBinding(k1); SetBinding(k1, toId) end
	if k2 then SetBinding(k2); SetBinding(k2, toId) end
end

-- Moves the key back onto btn.nativeBindingId; called before a hoverbind edit/clear reads or writes it.
function ACAB:RehomeDefaultBarBinding(btn)
	if not btn or not btn.nativeBindingId then
		return
	end

	local liveId = btn.activeBindingId or btn.nativeBindingId

	if liveId ~= btn.nativeBindingId then
		MoveBindingKeys(liveId, btn.nativeBindingId)
	end

	btn.activeBindingId = btn.nativeBindingId
end

-- Moves the key onto ACABBIND<n> while btn.actionSlot is in the pool range, else back home. Idempotent.
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

	-- Always funnels through nativeBindingId, so chained swaps read the key from one stable source.
	if liveId ~= btn.nativeBindingId then
		MoveBindingKeys(liveId, btn.nativeBindingId)
	end

	if targetId ~= btn.nativeBindingId then
		MoveBindingKeys(btn.nativeBindingId, targetId)
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
-- Tinting: bound/unbound icon tint while hoverbind mode is on (UpdateRange
-- skips its own tint then).
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

-- Recomputes the button's normal range/usability tint immediately.
local function RestoreButtonIconTint(ref)
	ref.frame:UpdateRange()
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
		self:ForEachButton(function(ref) self:TintHoverBindButton(ref) end)
		if C_Timer and C_Timer.NewTicker then
			self.hoverBindTintTicker = C_Timer.NewTicker(HOVERBIND_TINT_INTERVAL, function()
				-- Skips a tick queued before hoverbind mode turned off.
				if ACAB:IsHoverBindMode() then
					ACAB:ForEachButton(function(ref) ACAB:TintHoverBindButton(ref) end)
				end
			end)
		end
	else
		self:ForEachButton(RestoreButtonIconTint)
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
-- Hover tracking (called from Button.lua's OnEnter/OnLeave in hoverbind mode)
-------------------------------------------------------------------------

function ACAB:SetHoverBindHoveredCustomButton(btn)
	if not self.hoverBindCaptureFrame or not btn or not btn.parentBar or not btn.parentBar.config then
		return
	end

	self.hoverBindCaptureFrame.hoveredButton = MakeButtonRef(btn, btn.parentBar.config.id, btn.slotIndex)
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
	if hovered.frame.UpdateHotkeyText then
		hovered.frame:UpdateHotkeyText()
	end
end

-- Binds combo to the hovered button's action (replacing its old keys), saves, and refreshes it.
local function ApplyHoverBindKey(hovered, combo)
	-- Must rehome first: a swap may have moved the live key onto ACABBIND<n>.
	if hovered.fixedSlotBar then
		ACAB:RehomeDefaultBarBinding(hovered.frame)
	end

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

	-- Re-applies the swap redirect after saving.
	if hovered.fixedSlotBar then
		ACAB:SyncDefaultBarBindingRedirect(hovered.frame)
	end

	RefreshHoverBindTarget(hovered)
end

-- Removes the hovered button's keybinds (Escape).
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

-- Escape clears the hovered button's binding instead of being bound.
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

-- Binds Middle/Button4/Button5 (from Button.lua's OnMouseDown) to the hovered button.
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

