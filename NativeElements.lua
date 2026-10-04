-- NativeElements.lua
-- Bag Bar, Micro Menu, Key Ring, Latency Bar, Cast Bar, built on DefaultBars.lua's engine, plus the Modern Layout
-- corner cluster and Reset-to-Modern-Base resets for them.
-- Must load after DefaultBars.lua: the top-level InstallShowGuard/InstallReanchorGuard calls below need it.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Local helpers (shared single-frame helpers live in DefaultBars.lua)
-------------------------------------------------------------------------

-- Installs InstallReanchorGuard(flagName) on every button in `buttons`.
local function InstallReanchorGuards(self, buttons, flagName)
	local i

	for i = 1, table.getn(buttons) do
		self:InstallReanchorGuard(buttons[i], flagName)
	end
end

-------------------------------------------------------------------------
-- Bag Bar position/enable
-------------------------------------------------------------------------

-- Applies the grouped placement or ACABDB.bagBarPosition and ensures the overlay. No-op until the container exists.
function ACAB:ApplyBagBarPosition()
	if self:ApplyGroupedIfActive("bagbar") then
		return
	end

	local pos = ACABDB.bagBarPosition
	local container = self.bagBarContainer

	if not pos or not container then
		return
	end

	self:ApplySavedPosition(container, pos)
	self:EnsureElementOverlayAndHover("bagbar", container)
end

function ACAB:SetBagBarPosition(x, y)
	if self:WriteSavedPositionXY("bagBarPosition", x, y) then
		self:ApplyBagBarPosition()
	end
end

-- Restores the saved native (Vanilla Layout) position.
function ACAB:ResetBagBarPosition()
	local native = ACABDB.bagBarNativeAnchor

	if not native then
		return
	end

	ACABDB.bagBarPosition = self:CopyNativePosition(native)

	self:ApplyBagBarPosition()
end

-- The container's Show()/Hide() cascades to every real child button.
function ACAB:SetBagBarEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.bagBarEnabled = enabled

	self:SetElementShown(self.bagBarContainer, enabled)
end

function ACAB:SetBagBarHoverOnly(enabled)
	self:SetHoverOnlySetting("bagBarHoverOnly", enabled, self.ApplyBagBarPosition)
end

function ACAB:SetBagBarHoverDuration(duration)
	self:SetHoverDurationSetting("bagBarHoverDuration", duration, self.ApplyBagBarPosition)
end

-- Bag Bar's orientation: horizontal while grouped with Main Bar, else its saved orientation.
function ACAB:GetBagBarEffectiveVertical()
	if self:IsElementGrouped("bagbar") then
		return false
	end

	return ACABDB.bagBarOrientation == true
end

-- Bag Bar's grid as cols, rows (5x1 or 1x5) for the settings page's Grid Layout swatches.
function ACAB:GetBagBarEffectiveGrid()
	if self:GetBagBarEffectiveVertical() then
		return 1, 5
	end

	return 5, 1
end

-- Re-lays-out the Bag Bar's real buttons from its saved spacing/orientation/scale. No-op until the container exists.
function ACAB:ApplyBagBarShape()
	self:EnsureDB()

	if self:ApplyGroupedIfActive("bagbar") then
		return
	end

	self:ApplyChainAnchoredShape(
		self.bagBarContainer,
		ACABDB.bagBarSpacing or 0,
		ACABDB.bagBarOrientation == true,
		ACABDB.bagBarScale or 1
	)
end

function ACAB:SetBagBarSpacing(spacing)
	self:EnsureDB()

	spacing = self:ClampSpacingSetting(spacing, 0, 20)

	if not spacing then
		return
	end

	ACABDB.bagBarSpacing = spacing

	self:ApplyBagBarShape()
end

function ACAB:SetBagBarScale(scale)
	local pos

	scale, pos = self:StoreCompensatedScale("bagBarScale", "bagBarPosition", self.bagBarContainer, scale)

	if not scale then
		return
	end

	self:ApplyBagBarShape()

	if pos then
		self:ApplyBagBarPosition()
	end
end

-- true = vertical.
function ACAB:SetBagBarOrientation(vertical)
	self:EnsureDB()

	ACABDB.bagBarOrientation = vertical and true or false

	self:ApplyBagBarShape()
end

-- Restores spacing/scale/orientation to their native baseline (position: ResetBagBarPosition).
function ACAB:ResetBagBarLayout()
	self:EnsureDB()

	ACABDB.bagBarSpacing = ACABDB.bagBarNativeSpacing or 0
	ACABDB.bagBarScale = 1
	ACABDB.bagBarOrientation = false

	self:ApplyBagBarShape()
end

function ACAB:StartBagBarDrag()
	local pos = ACABDB.bagBarPosition

	if not pos then
		return
	end

	self:StartSharedDrag("bagBar", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopBagBarDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("bagbar")
	end
end

-------------------------------------------------------------------------
-- Micro Menu position/enable (same shape as the Bag Bar block above)
-------------------------------------------------------------------------

function ACAB:ApplyMicroMenuPosition()
	if self:ApplyGroupedIfActive("micromenu") then
		return
	end

	local pos = ACABDB.microMenuPosition
	local container = self.microMenuContainer

	if not pos or not container then
		return
	end

	self:ApplySavedPosition(container, pos)
	self:EnsureElementOverlayAndHover("micromenu", container)
end

function ACAB:SetMicroMenuPosition(x, y)
	if self:WriteSavedPositionXY("microMenuPosition", x, y) then
		self:ApplyMicroMenuPosition()
	end
end

function ACAB:ResetMicroMenuPosition()
	local native = ACABDB.microMenuNativeAnchor

	if not native then
		return
	end

	ACABDB.microMenuPosition = self:CopyNativePosition(native)

	self:ApplyMicroMenuPosition()
end

function ACAB:SetMicroMenuEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.microMenuEnabled = enabled

	self:SetElementShown(self.microMenuContainer, enabled)
end

function ACAB:SetMicroMenuHoverOnly(enabled)
	self:SetHoverOnlySetting("microMenuHoverOnly", enabled, self.ApplyMicroMenuPosition)
end

function ACAB:SetMicroMenuHoverDuration(duration)
	self:SetHoverDurationSetting("microMenuHoverDuration", duration, self.ApplyMicroMenuPosition)
end

-- Micro Menu's cols, rows: 8x1 while grouped with Main Bar, else its saved grid.
function ACAB:GetMicroMenuEffectiveGrid()
	if self:IsElementGrouped("micromenu") then
		return 8, 1
	end

	return ACABDB.microMenuCols or 8, ACABDB.microMenuRows or 1
end

-- Lays out the Micro Menu on a fixed cols x rows grid (not a chain like Bag Bar/Stance Bar).
function ACAB:ApplyMicroMenuShape()
	self:EnsureDB()

	if self:ApplyGroupedIfActive("micromenu") then
		return
	end

	self:ApplyGridAnchoredShape(
		self.microMenuContainer,
		ACABDB.microMenuCols or 8,
		ACABDB.microMenuRows or 1,
		ACABDB.microMenuSpacing or 0,
		ACABDB.microMenuScale or 1
	)
end

function ACAB:SetMicroMenuSpacing(spacing)
	self:EnsureDB()

	-- Stored range; the slider displays it shifted +4 (spacingUiOffset) as [-10, 20].
	spacing = self:ClampSpacingSetting(spacing, -14, 16)

	if not spacing then
		return
	end

	ACABDB.microMenuSpacing = spacing

	self:ApplyMicroMenuShape()
end

-- Sets the Micro Menu grid. Returns false (and changes nothing) for invalid or too-large grids.
function ACAB:SetMicroMenuLayout(cols, rows)
	self:EnsureDB()

	cols = tonumber(cols)
	rows = tonumber(rows)

	if not cols or not rows then
		return false
	end

	cols = math.floor(cols)
	rows = math.floor(rows)

	if cols < 1 or rows < 1 then
		return false
	end

	if cols * rows > table.getn(self.MICRO_MENU_BUTTON_NAMES) then
		self:Print("Micro Menu layout cannot exceed " ..
			tostring(table.getn(self.MICRO_MENU_BUTTON_NAMES)) .. " buttons.")
		return false
	end

	ACABDB.microMenuCols = cols
	ACABDB.microMenuRows = rows

	self:ApplyMicroMenuShape()

	return true
end

function ACAB:SetMicroMenuScale(scale)
	local pos

	scale, pos = self:StoreCompensatedScale("microMenuScale", "microMenuPosition", self.microMenuContainer, scale)

	if not scale then
		return
	end

	self:ApplyMicroMenuShape()

	if pos then
		self:ApplyMicroMenuPosition()
	end
end

-- Restores spacing/scale/grid to their defaults (position: ResetMicroMenuPosition).
function ACAB:ResetMicroMenuLayout()
	self:EnsureDB()

	ACABDB.microMenuSpacing = -3
	ACABDB.microMenuScale = 1
	ACABDB.microMenuCols = 8
	ACABDB.microMenuRows = 1

	self:ApplyMicroMenuShape()
end

function ACAB:StartMicroMenuDrag()
	local pos = ACABDB.microMenuPosition

	if not pos then
		return
	end

	self:StartSharedDrag("microMenu", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopMicroMenuDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("micromenu")
	end
end

-------------------------------------------------------------------------
-- Build both containers (once at login; idempotent, skips an element whose real buttons are missing)
-------------------------------------------------------------------------

function ACAB:CreateBagBarAndMicroMenu()
	self:EnsureDB()

	if not self.bagBarContainer then
		local buttons = self:GetButtonsByName(self.BAG_BAR_BUTTON_NAMES)

		if buttons then
			self:SortButtonsByNativeLeft(buttons)

			local container, nativeLeft, nativeTop, nativeSpacing =
				self:BuildChainAnchoredContainer("ACABBagBarContainer", buttons)

			self.bagBarContainer = container
			self.bagBarButtons = buttons

			-- Native code can re-anchor these buttons at any time (snapping Bag Bar back after a drag).
			InstallReanchorGuards(self, buttons, "ACABApplyingBagBarPosition")

			container.reanchorGuardFlag = "ACABApplyingBagBarPosition"

			self:SeedNativePosition("bagBarNativeAnchor", "bagBarPosition", nativeLeft, nativeTop)

			if not ACABDB.bagBarNativeSpacing then
				ACABDB.bagBarNativeSpacing = nativeSpacing
			end

			if not ACABDB.bagBarSpacing then
				ACABDB.bagBarSpacing = nativeSpacing
			end

			-- Shape before position, so the container's real size is already correct.
			self:ApplyBagBarShape()

			self:ApplyBagBarPosition()
			self:SetBagBarEnabled(ACABDB.bagBarEnabled ~= false)
		end
	end

	if not self.microMenuContainer then
		local buttons = self:GetButtonsByName(self.MICRO_MENU_BUTTON_NAMES)

		if buttons then
			self:SortButtonsByNativeLeft(buttons)

			local container, nativeLeft, nativeTop, nativeSpacing =
				self:BuildChainAnchoredContainer("ACABMicroMenuContainer", buttons)

			self.microMenuContainer = container
			self.microMenuButtons = buttons

			InstallReanchorGuards(self, buttons, "ACABApplyingMicroMenuPosition")

			-- Extra top-only overlay trim beyond the buttons' hit-rect insets.
			container.overlayTopFudge = self.MICRO_MENU_OVERLAY_TOP_FUDGE

			self:SeedNativePosition("microMenuNativeAnchor", "microMenuPosition", nativeLeft, nativeTop)

			if not ACABDB.microMenuNativeSpacing then
				ACABDB.microMenuNativeSpacing = nativeSpacing
			end

			-- Fixed default (slider position 1), not the measured native gap.
			if not ACABDB.microMenuSpacing then
				ACABDB.microMenuSpacing = -3
			end

			self:ApplyMicroMenuShape()

			self:ApplyMicroMenuPosition()
			self:SetMicroMenuEnabled(ACABDB.microMenuEnabled ~= false)
		end
	end
end

-- Re-lays-out the Micro Menu whenever vanilla's UpdateMicroButtons changes which micro buttons are shown.
if hooksecurefunc and UpdateMicroButtons then
	hooksecurefunc("UpdateMicroButtons", function()
		ACAB:ApplyMicroMenuShape()
	end)
end

-------------------------------------------------------------------------
-- Key Ring (the real KeyRingButton, positioned on its own - not part of the Bag Bar chain)
-- Every function below no-ops if KeyRingButton doesn't exist.
-------------------------------------------------------------------------

ACAB.KEYRING_BUTTON_NAME = "KeyRingButton"

ACAB:InstallShowGuard(getglobal(ACAB.KEYRING_BUTTON_NAME), function()
	return ACABDB and ACABDB.keyRingEnabled ~= false
end)

-- Lazily seeds keyRingPosition (absolute) and keyRingNativeAnchor (GetPoint(1)) from the live frame.
function ACAB:CaptureKeyRingPositionIfNeeded()
	self:EnsureDB()

	if ACABDB.keyRingPosition then
		return
	end

	local frame = getglobal(self.KEYRING_BUTTON_NAME)

	if not frame then
		return
	end

	local left = frame:GetLeft()
	local top = frame:GetTop()

	if not left or not top then
		return
	end

	local frameScale = frame:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()

	local x, y = left, top

	if frameScale and uiParentScale and uiParentScale ~= 0 then
		x = (left * frameScale) / uiParentScale
		y = (top * frameScale) / uiParentScale
	end

	local anchor = {
		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = x,
		y = y,
	}

	ACABDB.keyRingPosition = anchor

	-- Reset to Vanilla Layout snapshot, captured once (relative to another real frame, not UIParent).
	if not ACABDB.keyRingNativeAnchor then
		ACABDB.keyRingNativeAnchor = self:ReadNativeAnchor(frame)
	end
end

-- Session snapshot of KeyRingButton's native TOPLEFT (UIParent units) for its grouped placement.
-- must run at login before anything moves the Bag Bar or Main Bar's art (RunLoginSequence)
function ACAB:CaptureKeyRingNativeTopLeft()
	local frame = getglobal(self.KEYRING_BUTTON_NAME)

	if not frame then
		return
	end

	-- must read UIParent first or the frame can resolve against a stale ancestor (env §4.6)
	UIParent:GetLeft()

	local left = frame:GetLeft()
	local top = frame:GetTop()
	local frameScale = frame:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()

	if not left or not top or not frameScale or not uiParentScale or uiParentScale == 0 then
		return
	end

	self.keyRingNativeTopLeft = {
		x = (left * frameScale) / uiParentScale,
		y = (top * frameScale) / uiParentScale,
	}
end

-- Reasserts KeyRingButton's LOW strata/level (above art frame) and sets its effective scale, cancelling the scale inherited from MainMenuBarArtFrame.
function ACAB:ApplyKeyRingStrataAndScale(frame, scale)
	frame:SetFrameStrata("LOW")
	frame:SetFrameLevel(10)
	self:SetKeyRingOwnScaleForEffective(frame, scale)
end

-- Applies the grouped placement or ACABDB.keyRingPosition to KeyRingButton and ensures its overlay.
function ACAB:ApplyKeyRingPosition()
	if self:ApplyGroupedIfActive("keyring") then
		return
	end

	self:CaptureKeyRingPositionIfNeeded()

	local frame = getglobal(self.KEYRING_BUTTON_NAME)

	if not frame then
		return
	end

	self:ApplyKeyRingStrataAndScale(frame, ACABDB.keyRingScale or 1)

	local pos = ACABDB.keyRingPosition

	if pos then
		self:ApplySavedPosition(frame, pos)
	end

	self:EnsureElementOverlayAndHover("keyring", frame)
end

function ACAB:SetKeyRingHoverOnly(enabled)
	self:SetHoverOnlySetting("keyRingHoverOnly", enabled, self.ApplyKeyRingPosition)
end

function ACAB:SetKeyRingHoverDuration(duration)
	self:SetHoverDurationSetting("keyRingHoverDuration", duration, self.ApplyKeyRingPosition)
end

-- Independent of the Bag Bar's own enable flag.
function ACAB:SetKeyRingEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.keyRingEnabled = enabled

	self:SetElementShown(getglobal(self.KEYRING_BUTTON_NAME), enabled)
end

function ACAB:SetKeyRingPosition(x, y)
	if self:WriteSavedPositionXY("keyRingPosition", x, y) then
		self:ApplyKeyRingPosition()
	end
end

-- Restores scale 1 and the native (Vanilla Layout) position.
function ACAB:ResetKeyRingPosition()
	self:EnsureDB()

	local frame = getglobal(self.KEYRING_BUTTON_NAME)

	-- Must write the scale directly (not via SetKeyRingScale), before resolving, or the native position inflates.
	ACABDB.keyRingScale = 1

	if frame then
		-- Effective scale 1, not SetScale(1) - the native anchor below must resolve at true size.
		self:SetKeyRingOwnScaleForEffective(frame, 1)
	end

	local native = ACABDB.keyRingNativeAnchor
	local resolved = self:ResolveNativeAnchorToAbsolute(frame, native)

	if resolved then
		ACABDB.keyRingPosition = resolved
	end

	self:ApplyKeyRingPosition()
end

function ACAB:SetKeyRingScale(scale)
	local frame = getglobal(self.KEYRING_BUTTON_NAME)
	local pos

	scale, pos = self:StoreCompensatedScale("keyRingScale", "keyRingPosition", frame, scale)

	if not scale then
		return
	end

	if frame then
		self:SetKeyRingOwnScaleForEffective(frame, scale)
	end

	if pos then
		self:ApplyKeyRingPosition()
	end
end

function ACAB:StartKeyRingDrag()
	self:CaptureKeyRingPositionIfNeeded()

	local pos = ACABDB.keyRingPosition

	if not pos then
		return
	end

	self:StartSharedDrag("keyRing", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopKeyRingDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("keyring")
	end
end

-------------------------------------------------------------------------
-- Latency Bar (MainMenuBarPerformanceBarFrame - a sibling of MainMenuBarArtFrame, so art hiding never touches it)
-------------------------------------------------------------------------

ACAB.LATENCY_BAR_FRAME_NAME = "MainMenuBarPerformanceBarFrame"

ACAB:InstallReanchorGuard(getglobal(ACAB.LATENCY_BAR_FRAME_NAME), "ACABApplyingLatencyBarPosition")

-- Lazily seeds latencyBarNativeAnchor (GetPoint(1)) and latencyBarPosition resolved from it.
function ACAB:CaptureLatencyBarPositionIfNeeded()
	self:EnsureDB()

	if ACABDB.latencyBarPosition then
		return
	end

	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)

	if not frame then
		return
	end

	-- Reset to Vanilla Layout snapshot, captured once (natively BOTTOMRIGHT of MainMenuBar).
	if not ACABDB.latencyBarNativeAnchor then
		ACABDB.latencyBarNativeAnchor = self:ReadNativeAnchor(frame)
	end

	-- Resolved from the native anchor, not GetLeft()/GetTop(), which can read MainMenuBar before it settles.
	local resolved = self:ResolveNativeAnchorToAbsolute(frame, ACABDB.latencyBarNativeAnchor, "ACABApplyingLatencyBarPosition")

	if resolved then
		ACABDB.latencyBarPosition = resolved
	end
end

-- Applies the grouped placement or ACABDB.latencyBarPosition to the real frame and ensures its overlay.
function ACAB:ApplyLatencyBarPosition()
	if self:ApplyGroupedIfActive("latencybar") then
		return
	end

	self:CaptureLatencyBarPositionIfNeeded()

	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local pos = ACABDB.latencyBarPosition

	-- Must be set before the first apply - the visual-center conversion reads it.
	frame.overlayInset = self.LATENCY_BAR_OVERLAY_INSET

	if pos then
		self:ApplySavedPosition(frame, pos, "ACABApplyingLatencyBarPosition")
	end

	self:EnsureElementOverlayAndHover("latencybar", frame)
end

function ACAB:SetLatencyBarPosition(x, y)
	if self:WriteSavedPositionXY("latencyBarPosition", x, y) then
		self:ApplyLatencyBarPosition()
	end
end

function ACAB:SetLatencyBarEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.latencyBarEnabled = enabled

	self:SetElementShown(getglobal(self.LATENCY_BAR_FRAME_NAME), enabled)
end

function ACAB:SetLatencyBarScale(scale)
	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)
	local pos

	scale, pos = self:StoreCompensatedScale("latencyBarScale", "latencyBarPosition", frame, scale)

	if not scale then
		return
	end

	if frame then
		frame:SetScale(scale)
	end

	if pos then
		self:ApplyLatencyBarPosition()
	end
end

function ACAB:SetLatencyBarHoverOnly(enabled)
	self:SetHoverOnlySetting("latencyBarHoverOnly", enabled, self.ApplyLatencyBarPosition)
end

function ACAB:SetLatencyBarHoverDuration(duration)
	self:SetHoverDurationSetting("latencyBarHoverDuration", duration, self.ApplyLatencyBarPosition)
end

-- Restores the native (Vanilla Layout) position and scale 1.
function ACAB:ResetLatencyBarLayout()
	local native = ACABDB.latencyBarNativeAnchor
	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)
	local resolved = self:ResetScaleAndResolveNative(frame, "latencyBarScale", native, "ACABApplyingLatencyBarPosition")

	if resolved then
		ACABDB.latencyBarPosition = resolved
	end

	self:ApplyLatencyBarPosition()
end

function ACAB:StartLatencyBarDrag()
	self:CaptureLatencyBarPositionIfNeeded()

	local pos = ACABDB.latencyBarPosition

	if not pos then
		return
	end

	self:StartSharedDrag("latencyBar", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopLatencyBarDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("latencybar")
	end
end

-------------------------------------------------------------------------
-- Cast Bar (CastingBarFrame - position/scale/reset/drag only, no spacing/orientation/enable)
-------------------------------------------------------------------------

ACAB.CAST_BAR_FRAME_NAME = "CastingBarFrame"

ACAB:InstallReanchorGuard(getglobal(ACAB.CAST_BAR_FRAME_NAME), "ACABApplyingCastBarPosition")

-- Lazily seeds castBarNativeAnchor (GetPoint(1)) and castBarPosition resolved from it.
function ACAB:CaptureCastBarPositionIfNeeded()
	self:EnsureDB()

	if ACABDB.castBarPosition then
		return
	end

	local frame = getglobal(self.CAST_BAR_FRAME_NAME)

	if not frame then
		return
	end

	-- Reset to Vanilla Layout snapshot, captured once.
	if not ACABDB.castBarNativeAnchor then
		ACABDB.castBarNativeAnchor = self:ReadNativeAnchor(frame)
	end

	local resolved = self:ResolveNativeAnchorToAbsolute(frame, ACABDB.castBarNativeAnchor, "ACABApplyingCastBarPosition")

	if resolved then
		ACABDB.castBarPosition = resolved
	end
end

-- Applies ACABDB.castBarPosition to CastingBarFrame and ensures its overlay (not groupable, no hover-only).
function ACAB:ApplyCastBarPosition()
	self:CaptureCastBarPositionIfNeeded()

	local frame = getglobal(self.CAST_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local pos = ACABDB.castBarPosition

	if pos then
		self:ApplySavedPosition(frame, pos, "ACABApplyingCastBarPosition")
	end

	self:EnsureContainerOverlay(frame, self.StartCastBarDrag, self.StopCastBarDrag, "castbar", self.SetCastBarScale, nil, "Cast Bar")
end

function ACAB:SetCastBarPosition(x, y)
	if not self:WriteSavedPositionXY("castBarPosition", x, y) then
		return
	end

	-- Manually positioned - stop auto-stacking its Y.
	ACABDB.castBarUsesDefaultPosition = false

	self:ApplyCastBarPosition()
end

function ACAB:SetCastBarScale(scale)
	local frame = getglobal(self.CAST_BAR_FRAME_NAME)
	local pos

	scale, pos = self:StoreCompensatedScale("castBarScale", "castBarPosition", frame, scale)

	if not scale then
		return
	end

	if frame then
		frame:SetScale(scale)
	end

	if pos then
		self:ApplyCastBarPosition()
	end
end

-- Restores the native (Vanilla Layout) position and scale 1, then re-enables default stacking.
function ACAB:ResetCastBarLayout()
	local native = ACABDB.castBarNativeAnchor
	local frame = getglobal(self.CAST_BAR_FRAME_NAME)
	local resolved = self:ResetScaleAndResolveNative(frame, "castBarScale", native, "ACABApplyingCastBarPosition")

	if resolved then
		ACABDB.castBarPosition = resolved

		-- Re-captures the stacking floor from the restored native spot.
		ACABDB.castBarStackBaseY = resolved.y
	end

	ACABDB.castBarUsesDefaultPosition = true

	self:ApplyCastBarPosition()

	-- Moves it onto the computed stacking baseline.
	self:ReflowCastBarForStackToggle()
end

-------------------------------------------------------------------------
-- Cast Bar dynamic stacking (Default Layout only): floor Y + Action Bar 1/2's buttonSize + Extra Bar 1/2's
-- buttonSize + Pet Bar's height, each only while active.
-------------------------------------------------------------------------

-- Captures the stacking floor Y once; reflows only ever recompute off it.
function ACAB:CaptureCastBarStackBaseYIfNeeded()
	self:EnsureDB()

	if ACABDB.castBarStackBaseY then
		return
	end

	self:CaptureCastBarPositionIfNeeded()

	local pos = ACABDB.castBarPosition
	local frame = getglobal(self.CAST_BAR_FRAME_NAME)

	-- Floor is a TOPLEFT/BOTTOMLEFT top-edge y, whatever format the saved position is in.
	if pos and pos.y and frame then
		ACABDB.castBarStackBaseY = self:GetPositionInAnchor(frame, pos, "TOPLEFT", "BOTTOMLEFT").y
	end
end

-- Floor + max buttonSize per side-by-side pair (Action Bar 1/2, default-positioned Extra Bar 1/2) + shown Pet Bar height.
function ACAB:GetCastBarBaselineY()
	self:CaptureCastBarStackBaseYIfNeeded()

	local baseY = ACABDB.castBarStackBaseY

	if not baseY then
		return nil
	end

	local bar2Cfg = ACABDB.defaultBars and ACABDB.defaultBars[2]
	local bar3Cfg = ACABDB.defaultBars and ACABDB.defaultBars[3]
	local actionBarPitch = 0

	if bar2Cfg and bar2Cfg.enabled and (bar2Cfg.buttonSize or 0) > actionBarPitch then
		actionBarPitch = bar2Cfg.buttonSize
	end

	if bar3Cfg and bar3Cfg.enabled and (bar3Cfg.buttonSize or 0) > actionBarPitch then
		actionBarPitch = bar3Cfg.buttonSize
	end

	local extra1 = self.bars and self.bars[self.EXTRA_BAR_ID_START]
	local extra2 = self.bars and self.bars[self.EXTRA_BAR_ID_START + 1]
	local extraBarPitch = 0

	-- An Extra Bar moved away from its seeded slot (usesDefaultPosition == false) doesn't count.
	if extra1 and extra1.config and extra1.config.enabled
		and extra1.config.usesDefaultPosition ~= false
		and (extra1.config.buttonSize or 0) > extraBarPitch then
		extraBarPitch = extra1.config.buttonSize
	end

	if extra2 and extra2.config and extra2.config.enabled
		and extra2.config.usesDefaultPosition ~= false
		and (extra2.config.buttonSize or 0) > extraBarPitch then
		extraBarPitch = extra2.config.buttonSize
	end

	local petPitch = 0
	local petContainer = self.petBarNativeContainer

	if petContainer and petContainer:IsShown() then
		petPitch = petContainer:GetHeight() or 0
	end

	return baseY + actionBarPitch + extraBarPitch + petPitch
end

-- Moves Cast Bar's Y onto its stack baseline (Default Layout only). No-op once castBarUsesDefaultPosition is false.
function ACAB:ReflowCastBarForStackToggle()
	self:EnsureDB()

	if ACABDB.castBarUsesDefaultPosition == false then
		return
	end

	local pos = ACABDB.castBarPosition
	local y = self:GetCastBarBaselineY()
	local frame = getglobal(self.CAST_BAR_FRAME_NAME)

	if not pos or not y or not frame then
		return
	end

	-- y is a top edge - written in TOPLEFT/BOTTOMLEFT terms, ApplyCastBarPosition converts back.
	self:ConvertPositionAnchor(frame, pos, "TOPLEFT", "BOTTOMLEFT")

	pos.y = y

	self:ApplyCastBarPosition()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("castbar")
	end
end

function ACAB:StartCastBarDrag()
	self:CaptureCastBarPositionIfNeeded()

	local pos = ACABDB.castBarPosition

	if not pos then
		return
	end

	self:StartSharedDrag("castBar", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopCastBarDrag()
	self:StopSharedDrag()

	-- Manually moved - stop auto-stacking its Y.
	ACABDB.castBarUsesDefaultPosition = false

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("castbar")
	end
end

-------------------------------------------------------------------------
-- Modern Layout corners: Bag Bar in the bottom-right corner with Key Ring to its left; Latency Bar in the
-- bottom-left corner with Micro Menu to its right, Latency Bar's overlay top level with Micro Menu's.
-- Every gap is flush, from the elements' live sizes.
-------------------------------------------------------------------------

-- Saved position anchored BOTTOMRIGHT to BOTTOMRIGHT at x, y.
local function ModernCornerPosition(x, y)
	return {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = x, y = y,
	}
end

-- Saved position anchored BOTTOMLEFT to BOTTOMLEFT at x, y.
local function ModernLeftCornerPosition(x, y)
	return {
		point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT",
		x = x, y = y,
	}
end

-- Bag Bar's real live width/height (or a formula-based fallback before its container exists).
local function MeasureBagBarFootprint(self, buttonSize, spacing)
	local width = (self.bagBarContainer and self.bagBarContainer:GetWidth()) or (5 * (buttonSize + spacing))
	local height = (self.bagBarContainer and self.bagBarContainer:GetHeight()) or buttonSize

	return width, height
end

-- frame's overlay hitbox inside its rect: left/top/bottom gaps (inward positive), overlay width/height.
local function MeasureOverlayGaps(frame)
	local width = (frame and frame:GetWidth()) or 0
	local height = (frame and frame:GetHeight()) or 0
	local overlay = frame and frame.ACABOverlay

	if not overlay then
		return 0, 0, 0, width, height
	end

	local frameLeft, frameTop, frameBottom = frame:GetLeft(), frame:GetTop(), frame:GetBottom()
	local overlayLeft, overlayRight = overlay:GetLeft(), overlay:GetRight()
	local overlayTop, overlayBottom = overlay:GetTop(), overlay:GetBottom()

	local leftGap = (frameLeft and overlayLeft) and (overlayLeft - frameLeft) or 0
	local topGap = (frameTop and overlayTop) and (frameTop - overlayTop) or 0
	local bottomGap = (frameBottom and overlayBottom) and (overlayBottom - frameBottom) or 0

	if overlayLeft and overlayRight then
		width = overlayRight - overlayLeft
	end

	if overlayTop and overlayBottom then
		height = overlayTop - overlayBottom
	end

	return leftGap, topGap, bottomGap, width, height
end

-- Latency Bar's and Micro Menu's Modern positions (bottom-left corner), measured together.
local function GetModernBottomLeftPositions(self)
	local latencyBarFrame = getglobal(self.LATENCY_BAR_FRAME_NAME)
	local microMenu = self.microMenuContainer

	local latencyLeftGap, _, latencyBottomGap, latencyWidth, latencyHeight = MeasureOverlayGaps(latencyBarFrame)
	local microLeftGap, microTopGap = MeasureOverlayGaps(microMenu)
	local microOverlayTop = ((microMenu and microMenu:GetHeight()) or 0) - microTopGap

	local latencyBarPosition = ModernLeftCornerPosition(-latencyLeftGap, microOverlayTop - latencyHeight - latencyBottomGap)
	local microMenuPosition = ModernLeftCornerPosition(latencyWidth - microLeftGap, 0)

	return latencyBarPosition, microMenuPosition
end

-- Places all four together (Setup Wizard's Modern Layout choice).
function ACAB:ApplyModernCornerClusterLayout()
	self:EnsureDB()

	local buttonSize, spacing = self:GetModernLayoutSizing()

	-- Must measure everything before any Apply*Position below - a just-recreated overlay reads unsettled geometry.
	local bagBarWidth = MeasureBagBarFootprint(self, buttonSize, spacing)
	local latencyBarPosition, microMenuPosition = GetModernBottomLeftPositions(self)

	ACABDB.bagBarPosition = ModernCornerPosition(0, 0)
	ACABDB.keyRingPosition = ModernCornerPosition(-bagBarWidth, 0)
	ACABDB.microMenuPosition = microMenuPosition
	ACABDB.latencyBarPosition = latencyBarPosition

	self:ApplyBagBarPosition()
	self:ApplyKeyRingPosition()
	self:ApplyMicroMenuPosition()
	self:ApplyLatencyBarPosition()
end

-- The ApplyModernSingle* functions place one element against the others' current geometry without moving them.
function ACAB:ApplyModernSingleBagBar()
	self:EnsureDB()

	ACABDB.bagBarPosition = ModernCornerPosition(0, 0)

	self:ApplyBagBarPosition()
end

function ACAB:ApplyModernSingleKeyRing()
	self:EnsureDB()

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local bagBarWidth = MeasureBagBarFootprint(self, buttonSize, spacing)

	ACABDB.keyRingPosition = ModernCornerPosition(-bagBarWidth, 0)

	self:ApplyKeyRingPosition()
end

function ACAB:ApplyModernSingleMicroMenu()
	self:EnsureDB()

	local _, microMenuPosition = GetModernBottomLeftPositions(self)

	ACABDB.microMenuPosition = microMenuPosition

	self:ApplyMicroMenuPosition()
end

function ACAB:ApplyModernSingleLatencyBar()
	self:EnsureDB()

	local latencyBarPosition = GetModernBottomLeftPositions(self)

	ACABDB.latencyBarPosition = latencyBarPosition

	self:ApplyLatencyBarPosition()
end

-------------------------------------------------------------------------
-- "Reset to Modern Layout Default": reset the element's layout/scale to its Vanilla defaults, then apply
-- its Modern position. Layout first - the position measurements read the settled size.
-------------------------------------------------------------------------

-- Modern Layout's Bag Bar is flush (spacing 0).
function ACAB:ResetBagBarLayoutToModernBase()
	self:ResetBagBarLayout()
	self:SetBagBarSpacing(0)
	self:ApplyModernSingleBagBar()
end

function ACAB:ResetKeyRingLayoutToModernBase()
	self:EnsureDB()

	ACABDB.keyRingScale = 1

	self:ApplyModernSingleKeyRing()
end

function ACAB:ResetMicroMenuLayoutToModernBase()
	self:ResetMicroMenuLayout()
	self:ApplyModernSingleMicroMenu()
end

-- Measured one frame after the scale reset - the overlay rects don't reflect a new SetScale until then.
function ACAB:ResetLatencyBarLayoutToModernBase()
	self:EnsureDB()

	ACABDB.latencyBarScale = 1

	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)

	if frame then
		frame:SetScale(1)
	end

	C_Timer.After(0, function()
		ACAB:ApplyModernSingleLatencyBar()
	end)
end
