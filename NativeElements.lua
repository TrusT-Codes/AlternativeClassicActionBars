-- NativeElements.lua
-- Bag Bar, Micro Menu, Key Ring, Latency Bar, Cast Bar, Page Indicator, Tooltip, built on DefaultBars.lua's engine.
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

-- Reasserts KeyRingButton's HIGH strata and sets its effective scale, cancelling the scale inherited from MainMenuBarArtFrame.
function ACAB:ApplyKeyRingStrataAndScale(frame, scale)
	frame:SetFrameStrata("HIGH")
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
-- Page Indicator (Main Bar's page-turn arrows + page-number FontString in a synthetic container)
-- Position + Scale only; own layout (two stacked arrows, text beside them) instead of the chain engine.
-- Builds only if all three real frames exist.
-------------------------------------------------------------------------

ACAB.PAGE_INDICATOR_UP_NAME = "ActionBarUpButton"
ACAB.PAGE_INDICATOR_DOWN_NAME = "ActionBarDownButton"
ACAB.PAGE_INDICATOR_TEXT_NAME = "MainMenuBarPageNumber"

-- Settle-retry while the reparented elements' rects are unresolved (Shape), or Up's rect after login (Create).
local PAGE_INDICATOR_SHAPE_RETRY_INTERVAL = 0.1
local PAGE_INDICATOR_SHAPE_RETRY_TIMEOUT = 3
local PAGE_INDICATOR_CREATE_RETRY_TIMEOUT = 10

-- Gap between Main Bar's visual right edge and the Page Indicator's visual left edge.
local PAGE_INDICATOR_MAIN_BAR_GAP = 6

-- frame's left, top, right, bottom, or nil while any edge is unresolved.
local function RealRect(frame)
	local l, t, r, b = frame:GetLeft(), frame:GetTop(), frame:GetRight(), frame:GetBottom()
	if not (l and t and r and b) then
		return nil
	end
	return l, t, r, b
end

-- Wraps Up/Down/Text in the container; retries on a timer while Up's rect is unresolved after login.
function ACAB:CreatePageIndicatorContainer()
	self:EnsureDB()

	if self.pageIndicatorContainer then
		return
	end

	local up = getglobal(self.PAGE_INDICATOR_UP_NAME)
	local down = getglobal(self.PAGE_INDICATOR_DOWN_NAME)
	local text = getglobal(self.PAGE_INDICATOR_TEXT_NAME)

	if not up or not down or not text then
		return
	end

	-- Native anchors, read before any reparenting.
	local upPoint, upRelTo, upRelPoint, upX, upY = up:GetPoint(1)
	local downPoint, downRelTo, downRelPoint, downX, downY = down:GetPoint(1)
	local textPoint, textRelTo, textRelPoint, textX, textY = text:GetPoint(1)

	-- Container TOPLEFT = Up's native TOPLEFT, converted to UIParent units below.
	local nativeLeft = up:GetLeft()
	local nativeTop = up:GetTop()

	if not nativeLeft or not nativeTop then
		self.pageIndicatorCreateRetryElapsed = (self.pageIndicatorCreateRetryElapsed or 0)
			+ PAGE_INDICATOR_SHAPE_RETRY_INTERVAL

		if self.pageIndicatorCreateRetryElapsed >= PAGE_INDICATOR_CREATE_RETRY_TIMEOUT then
			self.pageIndicatorCreateRetryElapsed = nil
			self:Print("WARNING: Page Indicator's native position did not resolve in time - it stays at Blizzard's default spot this session.")
			return
		end

		C_Timer.After(PAGE_INDICATOR_SHAPE_RETRY_INTERVAL, function()
			ACAB:CreatePageIndicatorContainer()
		end)

		return
	end

	self.pageIndicatorCreateRetryElapsed = nil

	local upScale = up:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()

	if not upScale or not uiParentScale or uiParentScale == 0 then
		return
	end

	nativeLeft = (nativeLeft * upScale) / uiParentScale
	nativeTop = (nativeTop * upScale) / uiParentScale

	-- Down/Text anchored directly to Up/Down keep their own anchors.
	self.pageIndicatorDownFollowsUp = (downRelTo == up)
	self.pageIndicatorTextFollowsUp = (textRelTo == up)
	self.pageIndicatorTextFollowsDown = (textRelTo == down)

	-- Sharing Up's relativeTo: anchor to Up from GetPoint offsets - must not use rect reads (stale after login).
	local function SiblingAnchor(point, relTo, relPoint, x, y)
		if not relTo or relTo ~= upRelTo then
			return nil
		end

		-- Measures MainMenuBar instead of MainMenuBarArtFrame, whose own size is recalibrated by art positioning.
		local sizeFrame = relTo

		if relTo == MainMenuBarArtFrame and MainMenuBar then
			sizeFrame = MainMenuBar
		end

		local relWidth = sizeFrame.GetWidth and sizeFrame:GetWidth()
		local relHeight = sizeFrame.GetHeight and sizeFrame:GetHeight()

		if not relWidth or not relHeight then
			return nil
		end

		local fx, fy = self:GetPointFractions(relPoint)
		local upFx, upFy = self:GetPointFractions(upRelPoint)

		return {
			point = point,
			x = ((x or 0) - (upX or 0)) + ((fx - upFx) * relWidth),
			y = ((y or 0) - (upY or 0)) + ((fy - upFy) * relHeight),
		}
	end

	self.pageIndicatorDownAnchor = SiblingAnchor(downPoint, downRelTo, downRelPoint, downX, downY)
	self.pageIndicatorTextAnchor = SiblingAnchor(textPoint, textRelTo, textRelPoint, textX, textY)
	self.pageIndicatorUpPoint = upPoint

	-- Fallback for anything else: its on-screen delta from Up's corner.
	local downLeft, downTop = down:GetLeft(), down:GetTop()
	local textLeft, textTop = text:GetLeft(), text:GetTop()

	if not self.pageIndicatorDownFollowsUp and not self.pageIndicatorDownAnchor and downLeft and downTop then
		self.pageIndicatorDownDeltaX = downLeft - up:GetLeft()
		self.pageIndicatorDownDeltaY = downTop - up:GetTop()
	end

	if not (self.pageIndicatorTextFollowsUp or self.pageIndicatorTextFollowsDown or self.pageIndicatorTextAnchor)
		and textLeft and textTop then
		self.pageIndicatorTextDeltaX = textLeft - up:GetLeft()
		self.pageIndicatorTextDeltaY = textTop - up:GetTop()
	end

	local container = CreateFrame("Frame", "ACABPageIndicatorContainer", UIParent)
	container:SetFrameStrata("HIGH")

	-- Container spans the untrimmed hit-rects; the edit-mode overlay is trimmed to the visible art.
	local upInsetL, upInsetR, upInsetT, upInsetB = self:GetHitInsets(up)
	local downInsetL, downInsetR, downInsetT, downInsetB = self:GetHitInsets(down)

	container.overlayInset = {
		left = upInsetL,
		right = 0,
		top = upInsetT,
		bottom = downInsetB,
	}

	-- Placeholder size - must stay: the container's rect never resolves until it has been sized once.
	container:SetWidth(1)
	container:SetHeight(1)

	up:SetParent(container)
	down:SetParent(container)
	text:SetParent(container)

	self.pageIndicatorContainer = container
	self.pageIndicatorUp = up
	self.pageIndicatorDown = down
	self.pageIndicatorText = text

	self:ApplyPageIndicatorStrata()

	self:SeedNativePosition("mainBarPageIndicatorNativeAnchor", "mainBarPageIndicatorPosition", nativeLeft, nativeTop)

	-- Position must run before Shape: rects resolve top-down, so the container needs its point first.
	self:ApplyPageIndicatorPosition()
	self:ApplyPageIndicatorShape()
	self:ApplyPageIndicatorVisibility()
end

-- Re-anchors Up/Down/Text inside the container, then sizes it to their real on-screen bounding box.
function ACAB:ApplyPageIndicatorShape()
	local container = self.pageIndicatorContainer
	local up = self.pageIndicatorUp
	local down = self.pageIndicatorDown
	local text = self.pageIndicatorText

	if not container or not up or not down or not text then
		return
	end

	up:ClearAllPoints()
	self:PixelSetPoint(up, "TOPLEFT", container, "TOPLEFT", 0, 0)

	local downAnchor = self.pageIndicatorDownAnchor
	local textAnchor = self.pageIndicatorTextAnchor
	local upPoint = self.pageIndicatorUpPoint or "CENTER"

	if downAnchor then
		down:ClearAllPoints()
		down:SetPoint(downAnchor.point or "CENTER", up, upPoint, downAnchor.x, downAnchor.y)
	elseif not self.pageIndicatorDownFollowsUp then
		down:ClearAllPoints()
		self:PixelSetPoint(
			down,
			"TOPLEFT",
			container,
			"TOPLEFT",
			self.pageIndicatorDownDeltaX or 0,
			self.pageIndicatorDownDeltaY or 0
		)
	end

	if textAnchor then
		text:ClearAllPoints()
		text:SetPoint(textAnchor.point or "CENTER", up, upPoint, textAnchor.x, textAnchor.y)
	elseif not (self.pageIndicatorTextFollowsUp or self.pageIndicatorTextFollowsDown) then
		-- PixelSetPoint falls back to plain SetPoint for the FontString.
		text:ClearAllPoints()
		self:PixelSetPoint(
			text,
			"TOPLEFT",
			container,
			"TOPLEFT",
			self.pageIndicatorTextDeltaX or 0,
			self.pageIndicatorTextDeltaY or 0
		)
	end

	-- Top-down resolve: ancestors first, values discarded - load-bearing, keep before the reads below.
	UIParent:GetLeft()
	container:GetLeft()

	local upL, upT, upR, upB = RealRect(up)
	local downL, downT, downR, downB = RealRect(down)
	local textL, textT, textR, textB = RealRect(text)

	-- Just-reparented rects can read nil for a beat - retries on a timer instead of sizing a partial box.
	if not (upL and downL and textL) then
		self.pageIndicatorShapeRetryElapsed = (self.pageIndicatorShapeRetryElapsed or 0)
			+ PAGE_INDICATOR_SHAPE_RETRY_INTERVAL

		if self.pageIndicatorShapeRetryElapsed >= PAGE_INDICATOR_SHAPE_RETRY_TIMEOUT then
			self.pageIndicatorShapeRetryElapsed = nil
			self:Print("WARNING: Page Indicator's real position did not resolve in time - its edit-mode hitbox may be misaligned this session.")
			return
		end

		if C_Timer and C_Timer.After then
			C_Timer.After(PAGE_INDICATOR_SHAPE_RETRY_INTERVAL, function()
				ACAB:ApplyPageIndicatorShape()
			end)
		end

		return
	end

	self.pageIndicatorShapeRetryElapsed = nil

	local left, top, right, bottom = upL, upT, upR, upB

	local function Expand(l, t, r, b)
		if l < left then left = l end
		if t > top then top = t end
		if r > right then right = r end
		if b < bottom then bottom = b end
	end

	Expand(downL, downT, downR, downB)
	Expand(textL, textT, textR, textB)

	local width = right - left
	local height = top - bottom

	if width <= 0 then
		width = up:GetWidth() or 1
	end
	if height <= 0 then
		height = up:GetHeight() or 1
	end

	self:PixelSetSize(container, width, height)

	if self:ApplyGroupedIfActive("pageindicator") then
		return
	end

	container:SetScale(ACABDB.mainBarPageIndicatorScale or 1)

	-- Default position depends on the container's measured width.
	if ACABDB.mainBarPageIndicatorFollowsMainBar ~= false then
		self:ApplyPageIndicatorPosition()
	end
end

-- Up/Down above MainMenuBarArtFrame (MEDIUM) - they keep the art's strata after reparenting otherwise.
function ACAB:ApplyPageIndicatorStrata()
	local container = self.pageIndicatorContainer

	if not container then
		return
	end

	container:SetFrameStrata("HIGH")
	container:SetFrameLevel(11)

	if self.pageIndicatorUp then
		self.pageIndicatorUp:SetFrameStrata("HIGH")
		self.pageIndicatorUp:SetFrameLevel(12)
	end

	if self.pageIndicatorDown then
		self.pageIndicatorDown:SetFrameStrata("HIGH")
		self.pageIndicatorDown:SetFrameLevel(12)
	end
end

-- Canonical position vertically centered just right of Main Bar's visual edge, at the container's current width/scale.
function ACAB:GetPageIndicatorDefaultPosition()
	local bar1 = self.bars and self.bars[1]
	local container = self.pageIndicatorContainer

	if not bar1 or not bar1.config or not container then
		return nil
	end

	local barLeft, barRight, barBottom, barTop = self:GetPositionFrameRect(bar1, bar1.config, "TOPLEFT")
	local uiParentScale = UIParent:GetEffectiveScale()

	if not barLeft or not uiParentScale or uiParentScale == 0 then
		return nil
	end

	local barScale = bar1:GetEffectiveScale() / uiParentScale
	local _, barInsetR, barInsetT, barInsetB = self:GetVisualInsets(bar1)

	local visualRight = barRight - (barInsetR * barScale)
	local visualCenterY = ((barTop - (barInsetT * barScale)) + (barBottom + (barInsetB * barScale))) / 2

	local indicatorScale = container:GetEffectiveScale() / uiParentScale
	local indicatorInsetL, indicatorInsetR = self:GetVisualInsets(container)
	local indicatorWidth = ((container:GetWidth() or 0) - indicatorInsetL - indicatorInsetR) * indicatorScale

	local screenWidth, screenHeight = self:GetUIParentAnchorSize()

	return {
		point = "CENTER",
		relativePoint = "CENTER",
		visualCenter = true,
		x = visualRight + PAGE_INDICATOR_MAIN_BAR_GAP + (indicatorWidth / 2) - (screenWidth / 2),
		y = visualCenterY - (screenHeight / 2),
	}
end

-- Applies the grouped placement, else the Main-Bar-following default (follow mode) or the saved position.
function ACAB:ApplyPageIndicatorPosition()
	self:ApplyPageIndicatorStrata()

	if self:ApplyGroupedIfActive("pageindicator") then
		return
	end

	local container = self.pageIndicatorContainer

	if container and ACABDB.mainBarPageIndicatorFollowsMainBar ~= false then
		local default = self:GetPageIndicatorDefaultPosition()

		if default then
			ACABDB.mainBarPageIndicatorPosition = default
		end
	end

	local pos = ACABDB.mainBarPageIndicatorPosition

	if not pos or not container then
		return
	end

	self:ApplySavedPosition(container, pos)
	self:EnsureElementOverlayAndHover("pageindicator", container)
end

-- Main Bar page's Page Indicator Scale slider.
function ACAB:SetPageIndicatorScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	ACABDB.mainBarPageIndicatorScale = scale

	if self:ApplyGroupedIfActive("pageindicator") then
		return
	end

	if self.pageIndicatorContainer then
		self.pageIndicatorContainer:SetScale(scale)

		-- Keeps the scaled indicator flush with Main Bar's edge.
		if ACABDB.mainBarPageIndicatorFollowsMainBar ~= false then
			self:ApplyPageIndicatorPosition()
		end
	end
end

-- Restores follow mode (native anchor as fallback while Main Bar is unmeasurable), then scale 1.
function ACAB:ResetPageIndicatorLayout()
	self:EnsureDB()

	local native = ACABDB.mainBarPageIndicatorNativeAnchor

	ACABDB.mainBarPageIndicatorFollowsMainBar = true

	if native then
		ACABDB.mainBarPageIndicatorPosition = self:CopyNativePosition(native)
	end

	-- Also re-applies position (follow mode) at the final scale.
	self:SetPageIndicatorScale(1)
end

-- Modern Layout default is the same Main-Bar-following default as Vanilla Layout.
function ACAB:ResetPageIndicatorToModernBase()
	self:ResetPageIndicatorLayout()
end

-- No enable flag of its own - shown exactly while default-bar pagination is enabled.
function ACAB:ApplyPageIndicatorVisibility()
	local container = self.pageIndicatorContainer

	if not container then
		return
	end

	if ACABDB.defaultBarPaginationEnabled ~= false then
		container:Show()
	else
		container:Hide()
	end
end

function ACAB:StartPageIndicatorDrag()
	local pos = ACABDB.mainBarPageIndicatorPosition

	if not pos then
		return
	end

	-- Must clear before the drag ticks, or follow mode snaps it back to Main Bar every frame.
	self.pageIndicatorFollowedBeforeDrag = ACABDB.mainBarPageIndicatorFollowsMainBar ~= false
	ACABDB.mainBarPageIndicatorFollowsMainBar = false

	self.pageIndicatorCursorStartX, self.pageIndicatorCursorStartY = GetCursorPosition()

	self:StartSharedDrag("pageIndicator", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopPageIndicatorDrag()
	self:StopSharedDrag()

	-- Unmoved click (cursor delta under 3 px) keeps follow mode.
	local cursorX, cursorY = GetCursorPosition()
	local startX = self.pageIndicatorCursorStartX or cursorX
	local startY = self.pageIndicatorCursorStartY or cursorY

	if self.pageIndicatorFollowedBeforeDrag
		and math.abs(cursorX - startX) < 3 and math.abs(cursorY - startY) < 3 then
		ACABDB.mainBarPageIndicatorFollowsMainBar = true
		if self.ApplyPageIndicatorPosition then
			self:ApplyPageIndicatorPosition()
		end
	end

	self.pageIndicatorFollowedBeforeDrag = nil
	self.pageIndicatorCursorStartX = nil
	self.pageIndicatorCursorStartY = nil

	-- Its Scale slider lives on Main Bar's settings page (barId 1).
	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(1)
	end
end

-------------------------------------------------------------------------
-- Modern Layout bottom-right corner cluster: Bag Bar in the corner, Micro Menu on top of it, Key Ring to
-- Bag Bar's left, Latency Bar to Micro Menu's left. Every gap is flush, from the elements' live sizes.
-------------------------------------------------------------------------

-- Saved position anchored BOTTOMRIGHT to BOTTOMRIGHT at x, y.
local function ModernCornerPosition(x, y)
	return {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = x, y = y,
	}
end

-- Bag Bar's real live width/height (or a formula-based fallback before its container exists).
local function MeasureBagBarFootprint(self, buttonSize, spacing)
	local width = (self.bagBarContainer and self.bagBarContainer:GetWidth()) or (5 * (buttonSize + spacing))
	local height = (self.bagBarContainer and self.bagBarContainer:GetHeight()) or buttonSize

	return width, height
end

-- Micro Menu's overlay-hitbox top Y (stacked on bagBarHeight) and left X offset, for Latency Bar to stack against.
local function MeasureMicroMenuStackAnchors(self, buttonSize, spacing, bagBarHeight)
	local microMenuWidth = (self.microMenuContainer and self.microMenuContainer:GetWidth())
		or ((self:GetMicroMenuEffectiveGrid()) * (buttonSize + spacing))
	local microMenuHeight = (self.microMenuContainer and self.microMenuContainer:GetHeight()) or buttonSize

	local microMenuOverlayTopGap = 0
	local microMenuOverlay = self.microMenuContainer and self.microMenuContainer.ACABOverlay

	if self.microMenuContainer and microMenuOverlay then
		local containerTop = self.microMenuContainer:GetTop()
		local overlayTop = microMenuOverlay:GetTop()

		if containerTop and overlayTop then
			microMenuOverlayTopGap = containerTop - overlayTop
		end
	end

	local microMenuOverlayTop = bagBarHeight + microMenuHeight - microMenuOverlayTopGap

	local microMenuOverlayWidth = microMenuWidth
	local microMenuRightGap = 0

	if self.microMenuContainer and microMenuOverlay then
		local containerRight = self.microMenuContainer:GetRight()
		local overlayRight = microMenuOverlay:GetRight()
		local overlayLeft = microMenuOverlay:GetLeft()

		if containerRight and overlayRight then
			microMenuRightGap = containerRight - overlayRight
		end

		if overlayRight and overlayLeft then
			microMenuOverlayWidth = overlayRight - overlayLeft
		end
	end

	local microMenuOverlayLeftOffset = -(microMenuRightGap + microMenuOverlayWidth)

	return microMenuOverlayTop, microMenuOverlayLeftOffset
end

-- Latency Bar's own real height and the gap between its frame and its trimmed overlay hitbox.
local function MeasureLatencyBarOwnOverlay(self, buttonSize)
	local latencyBarFrame = getglobal(self.LATENCY_BAR_FRAME_NAME)
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

	return latencyBarHeight, latencyBarOverlayBottomGap, latencyBarOverlayRightGap
end

-- Latency Bar's Modern position: overlay flush left of Micro Menu's overlay, tops aligned, nudged down 5.
local function GetModernLatencyBarPosition(self, buttonSize, spacing, bagBarHeight)
	local microMenuOverlayTop, microMenuOverlayLeftOffset = MeasureMicroMenuStackAnchors(self, buttonSize, spacing, bagBarHeight)
	local latencyBarHeight, latencyBarOverlayBottomGap, latencyBarOverlayRightGap = MeasureLatencyBarOwnOverlay(self, buttonSize)

	return ModernCornerPosition(
		microMenuOverlayLeftOffset + latencyBarOverlayRightGap,
		((microMenuOverlayTop - latencyBarHeight) - latencyBarOverlayBottomGap) - 5
	)
end

-- Places all four together (Setup Wizard's Modern Layout choice).
function ACAB:ApplyModernCornerClusterLayout()
	self:EnsureDB()

	local buttonSize, spacing = self:GetModernLayoutSizing()

	-- Must measure everything before any Apply*Position below - a just-recreated overlay reads unsettled geometry.
	local bagBarWidth, bagBarHeight = MeasureBagBarFootprint(self, buttonSize, spacing)
	local latencyBarPosition = GetModernLatencyBarPosition(self, buttonSize, spacing, bagBarHeight)

	ACABDB.bagBarPosition = ModernCornerPosition(0, 0)
	ACABDB.keyRingPosition = ModernCornerPosition(-bagBarWidth, 0)
	ACABDB.microMenuPosition = ModernCornerPosition(0, bagBarHeight)
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

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local _, bagBarHeight = MeasureBagBarFootprint(self, buttonSize, spacing)

	ACABDB.microMenuPosition = ModernCornerPosition(0, bagBarHeight)

	self:ApplyMicroMenuPosition()
end

function ACAB:ApplyModernSingleLatencyBar()
	self:EnsureDB()

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local _, bagBarHeight = MeasureBagBarFootprint(self, buttonSize, spacing)

	ACABDB.latencyBarPosition = GetModernLatencyBarPosition(self, buttonSize, spacing, bagBarHeight)

	self:ApplyLatencyBarPosition()
end

-------------------------------------------------------------------------
-- "Reset to Modern Layout Default": reset the element's layout/scale to its Vanilla defaults, then apply
-- its Modern position. Layout first - the position measurements read the settled size.
-------------------------------------------------------------------------

function ACAB:ResetBagBarLayoutToModernBase()
	self:ResetBagBarLayout()
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

-------------------------------------------------------------------------
-- Tooltip (synthetic frame the fixed-position GameTooltip is redirected onto)
-- Only tooltips placed via GameTooltip_SetDefaultAnchor move; widget-relative tooltips stay untouched.
-------------------------------------------------------------------------

ACAB.TOOLTIP_FRAME_WIDTH = 200
ACAB.TOOLTIP_FRAME_HEIGHT = 100

-- Native GameTooltip_SetDefaultAnchor spot (BOTTOMRIGHT of UIParent, -103/125) as a TOPLEFT position.
local function GetNativeTooltipPosition()
	local screenWidth = GetScreenWidth() or 1024

	return {
		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = screenWidth - 103 - ACAB.TOOLTIP_FRAME_WIDTH,
		y = 125 + ACAB.TOOLTIP_FRAME_HEIGHT,
	}
end

-- Creates the synthetic frame once and lazily seeds ACABDB.tooltipPosition at the native spot.
function ACAB:EnsureTooltipFrame()
	self:EnsureDB()

	if self.tooltipFrame then
		return
	end

	local frame = CreateFrame("Frame", "ACABTooltipFrame", UIParent)

	self:PixelSetSize(frame, self.TOOLTIP_FRAME_WIDTH, self.TOOLTIP_FRAME_HEIGHT)

	self.tooltipFrame = frame

	if not ACABDB.tooltipPosition then
		ACABDB.tooltipPosition = GetNativeTooltipPosition()
	end
end

-- Applies ACABDB.tooltipPosition to the synthetic frame and ensures its overlay.
function ACAB:ApplyTooltipPosition()
	self:EnsureTooltipFrame()

	local pos = ACABDB.tooltipPosition
	local frame = self.tooltipFrame

	if not pos or not frame then
		return
	end

	self:ApplySavedPosition(frame, pos)
	self:EnsureContainerOverlay(frame, self.StartTooltipDrag, self.StopTooltipDrag, "tooltip", self.SetTooltipScale, nil, "Tooltip")
end

function ACAB:SetTooltipPosition(x, y)
	if self:WriteSavedPositionXY("tooltipPosition", x, y) then
		self:ApplyTooltipPosition()
	end
end

-- Keeps the tooltipAnchorCorner corner fixed while scaling (the corner GameTooltip anchors to).
function ACAB:SetTooltipScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	local oldScale = ACABDB.tooltipScale or 1
	local pos = ACABDB.tooltipPosition
	local frame = self.tooltipFrame

	if pos and frame then
		local corner = ACABDB.tooltipAnchorCorner or "BOTTOMRIGHT"

		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, corner, frame:GetWidth(), frame:GetHeight())
	end

	ACABDB.tooltipScale = scale

	if frame then
		frame:SetScale(scale)
	end

	if pos then
		self:ApplyTooltipPosition()
	end
end

-- "Grows From" corner; takes effect the next time a tooltip is shown.
function ACAB:SetTooltipAnchorCorner(corner)
	self:EnsureDB()

	if corner ~= "TOPLEFT" and corner ~= "TOPRIGHT" and corner ~= "BOTTOMLEFT" and corner ~= "BOTTOMRIGHT" then
		return
	end

	ACABDB.tooltipAnchorCorner = corner
end

function ACAB:SetTooltipEnabled(enabled)
	self:EnsureDB()

	ACABDB.tooltipEnabled = enabled and true or false

	self:ApplyDefaultLayoutEditVisual()
end

-- Restores scale 1, the BOTTOMRIGHT corner and the native position (recomputed for the current screen width).
function ACAB:ResetTooltipLayout()
	self:EnsureDB()

	-- Must write the scale directly (not via SetTooltipScale), or its compensation shifts the fresh position.
	ACABDB.tooltipScale = 1
	ACABDB.tooltipAnchorCorner = "BOTTOMRIGHT"

	if self.tooltipFrame then
		self.tooltipFrame:SetScale(1)
	end

	ACABDB.tooltipPosition = GetNativeTooltipPosition()

	self:ApplyTooltipPosition()
end

function ACAB:StartTooltipDrag()
	local pos = ACABDB.tooltipPosition

	if not pos then
		return
	end

	self:StartSharedDrag("tooltip", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopTooltipDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("tooltip")
	end
end

-- Redirects every fixed-position GameTooltip onto the synthetic frame (other tooltip objects are skipped).
function ACAB:HookGameTooltipDefaultAnchor()
	if self.tooltipDefaultAnchorHooked then
		return
	end

	self.tooltipDefaultAnchorHooked = true

	-- Every SetOwner resets scale 1; the SetDefaultAnchor post-hook below reapplies the custom scale.
	local nativeSetOwner = GameTooltip.SetOwner
	GameTooltip.SetOwner = function(tooltip, a1, a2, a3, a4)
		tooltip:SetScale(1)
		return nativeSetOwner(tooltip, a1, a2, a3, a4)
	end

	hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, owner)
		if tooltip ~= GameTooltip then
			return
		end

		if not ACABDB.tooltipEnabled then
			return
		end

		if not ACAB.tooltipFrame then
			return
		end

		local corner = ACABDB.tooltipAnchorCorner or "BOTTOMRIGHT"

		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint(corner, ACAB.tooltipFrame, corner, 0, 0)
		GameTooltip:SetScale(ACABDB.tooltipScale or 1)
	end)
end

