-- NativeElements.lua
-- Bag Bar, Micro Menu, Key Ring, Latency Bar, Cast Bar, Page Indicator.
-- Built on the shared chain/grid-anchored container + drag engine defined in DefaultBars.lua.
-- Must load after DefaultBars.lua: Key Ring/Latency Bar/Cast Bar make top-level InstallShowGuard/
-- InstallReanchorGuard calls below, and loading out of order throws "attempt to call nil value" on login.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Bag Bar position/enable
-------------------------------------------------------------------------

-- Applies ACABDB.bagBarPosition to the real container, and ensures its overlay exists. Assumes
-- CreateBagBarAndMicroMenu has already run and seeded bagBarPosition.
function ACAB:ApplyBagBarPosition()
	if self:ApplyGroupedIfActive("bagbar") then
		return
	end

	local pos = ACABDB.bagBarPosition
	local container = self.bagBarContainer

	if not pos or not container then
		return
	end

	container:ClearAllPoints()
	self:PixelSetPoint(
		container,
		pos.point or "TOPLEFT",
		UIParent,
		pos.relativePoint or "BOTTOMLEFT",
		pos.x or 0,
		pos.y or 0
	)

	self:EnsureContainerOverlay(container, self.StartBagBarDrag, self.StopBagBarDrag, "bagbar", self.SetBagBarScale, nil, "Bag Bar")

	self:ApplyHoverOnlyState(container, ACABDB.bagBarHoverOnly, function() return ACABDB.bagBarHoverDuration or 3 end)
end

-- Settings.lua's Bag Bar page X/Y sliders write through this.
function ACAB:SetBagBarPosition(x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB.bagBarPosition then
		return
	end

	ACABDB.bagBarPosition.x = x
	ACABDB.bagBarPosition.y = y

	self:ApplyBagBarPosition()
end

-- Settings.lua's Bag Bar page "Reset to Vanilla Layout" button.
function ACAB:ResetBagBarPosition()
	local native = ACABDB.bagBarNativeAnchor

	if not native then
		return
	end

	ACABDB.bagBarPosition = {
		point = native.point,
		relativePoint = native.relativePoint,
		x = native.x,
		y = native.y,
	}

	self:ApplyBagBarPosition()
end

-- Settings.lua's Bag Bar page enable checkbox. The container's own Show()/Hide() cascades to every
-- real child button, the sole visibility mechanism for this element.
function ACAB:SetBagBarEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.bagBarEnabled = enabled

	if self.bagBarContainer then
		if enabled then
			self.bagBarContainer:Show()
		else
			self.bagBarContainer:Hide()

			-- EnsureContainerOverlay's overlay is parented to UIParent, not this container.
			if self.bagBarContainer.ACABOverlay then
				self.bagBarContainer.ACABOverlay:Hide()
				self.bagBarContainer.ACABOverlay:EnableMouse(false)
			end
		end
	end
end

-- Settings.lua's Bag Bar page "Only show on hover" checkbox/slider.
function ACAB:SetBagBarHoverOnly(enabled)
	self:EnsureDB()

	ACABDB.bagBarHoverOnly = enabled and true or false

	self:ApplyBagBarPosition()
end

function ACAB:SetBagBarHoverDuration(duration)
	self:EnsureDB()

	duration = self:ClampHoverDuration(duration)

	if not duration then
		return
	end

	ACABDB.bagBarHoverDuration = duration

	self:ApplyBagBarPosition()
end

-- Re-lays-out the Bag Bar's real buttons from its current saved spacing/orientation/scale.
-- No-op until CreateBagBarAndMicroMenu has built the container.
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

-- Mirrors SetDefaultBarSpacing's clamp/write/reapply template - same 0-20 range as the Settings UI.
function ACAB:SetBagBarSpacing(spacing)
	self:EnsureDB()

	spacing = self:ClampSpacingSetting(spacing, 0, 20)

	if not spacing then
		return
	end

	ACABDB.bagBarSpacing = spacing

	self:ApplyBagBarShape()
end

-- Same template, rounded to the nearest 0.1 (Scale is a proportional multiplier, not a pixel quantity).
function ACAB:SetBagBarScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	local oldScale = ACABDB.bagBarScale or 1
	local pos = ACABDB.bagBarPosition

	if pos and self.bagBarContainer then
		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, "BOTTOMLEFT", nil, self.bagBarContainer:GetHeight())
	end

	ACABDB.bagBarScale = scale

	self:ApplyBagBarShape()

	if pos then
		self:ApplyBagBarPosition()
	end
end

-- Orientation is a plain boolean toggle (true = vertical/swapped) - no clamping needed.
function ACAB:SetBagBarOrientation(vertical)
	self:EnsureDB()

	ACABDB.bagBarOrientation = vertical and true or false

	self:ApplyBagBarShape()
end

-- Settings.lua's Bag Bar page reset flow calls this alongside ResetBagBarPosition - restores
-- spacing/scale/orientation to their native baseline.
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

	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = "bagBar"
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = pos.x or 0
	frame.dragStartY = pos.y or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopBagBarDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("bagbar")
	end
end

-------------------------------------------------------------------------
-- Micro Menu position/enable - mirrors the Bag Bar block above exactly.
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

	container:ClearAllPoints()
	self:PixelSetPoint(
		container,
		pos.point or "TOPLEFT",
		UIParent,
		pos.relativePoint or "BOTTOMLEFT",
		pos.x or 0,
		pos.y or 0
	)

	self:EnsureContainerOverlay(container, self.StartMicroMenuDrag, self.StopMicroMenuDrag, "micromenu", self.SetMicroMenuScale, nil, "Micro Menu")

	self:ApplyHoverOnlyState(container, ACABDB.microMenuHoverOnly, function() return ACABDB.microMenuHoverDuration or 3 end)
end

function ACAB:SetMicroMenuPosition(x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB.microMenuPosition then
		return
	end

	ACABDB.microMenuPosition.x = x
	ACABDB.microMenuPosition.y = y

	self:ApplyMicroMenuPosition()
end

function ACAB:ResetMicroMenuPosition()
	local native = ACABDB.microMenuNativeAnchor

	if not native then
		return
	end

	ACABDB.microMenuPosition = {
		point = native.point,
		relativePoint = native.relativePoint,
		x = native.x,
		y = native.y,
	}

	self:ApplyMicroMenuPosition()
end

function ACAB:SetMicroMenuEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.microMenuEnabled = enabled

	if self.microMenuContainer then
		if enabled then
			self.microMenuContainer:Show()
		else
			self.microMenuContainer:Hide()

			-- Same explicit-hide requirement as SetBagBarEnabled above.
			if self.microMenuContainer.ACABOverlay then
				self.microMenuContainer.ACABOverlay:Hide()
				self.microMenuContainer.ACABOverlay:EnableMouse(false)
			end
		end
	end
end

-- Settings.lua's Micro Menu page "Only show on hover" checkbox/slider.
function ACAB:SetMicroMenuHoverOnly(enabled)
	self:EnsureDB()

	ACABDB.microMenuHoverOnly = enabled and true or false

	self:ApplyMicroMenuPosition()
end

function ACAB:SetMicroMenuHoverDuration(duration)
	self:EnsureDB()

	duration = self:ClampHoverDuration(duration)

	if not duration then
		return
	end

	ACABDB.microMenuHoverDuration = duration

	self:ApplyMicroMenuPosition()
end

-- Unlike Bag Bar/Stance Bar, Micro Menu lays out via the fixed-grid function ApplyGridAnchoredShape.
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

	-- Actual range is [-14, 16], shifted -4 from the slider's displayed [-10, 20] range (Settings.lua's
	-- spacingUiOffset compensates for native button art padding).
	spacing = self:ClampSpacingSetting(spacing, -14, 16)

	if not spacing then
		return
	end

	ACABDB.microMenuSpacing = spacing

	self:ApplyMicroMenuShape()
end

-- Modeled on Bar.lua's SetBarLayout, simplified - Micro Menu's grid always shows all 8 named buttons.
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
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	local oldScale = ACABDB.microMenuScale or 1
	local pos = ACABDB.microMenuPosition

	if pos and self.microMenuContainer then
		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, "BOTTOMLEFT", nil, self.microMenuContainer:GetHeight())
	end

	ACABDB.microMenuScale = scale

	self:ApplyMicroMenuShape()

	if pos then
		self:ApplyMicroMenuPosition()
	end
end

-- Settings.lua's Micro Menu page reset flow calls this alongside ResetMicroMenuPosition.
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

	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = "microMenu"
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = pos.x or 0
	frame.dragStartY = pos.y or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopMicroMenuDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("micromenu")
	end
end

-------------------------------------------------------------------------
-- Build both containers (called once at PLAYER_LOGIN, Core.lua)
-- Idempotent via self.bagBarContainer/microMenuContainer nil-checks. Degrades gracefully if any real
-- button frames are missing.
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

			-- MainMenuBarBackpackButton is a real native frame that native code can re-anchor toward its
			-- default corner at any time (snapping Bag Bar back to the right edge after a drag).
			do
				local guardIndex

				for guardIndex = 1, table.getn(buttons) do
					self:InstallReanchorGuard(buttons[guardIndex], "ACABApplyingBagBarPosition")
				end
			end

			container.reanchorGuardFlag = "ACABApplyingBagBarPosition"

			-- nativeLeft/nativeTop are already the real-screen-pixel-converted values
			-- BuildChainAnchoredContainer returns, not a raw GetLeft()/GetTop() copy.
			if not ACABDB.bagBarNativeAnchor then
				ACABDB.bagBarNativeAnchor = {
					point = "TOPLEFT",
					relativePoint = "BOTTOMLEFT",
					x = nativeLeft,
					y = nativeTop,
				}
			end

			if not ACABDB.bagBarPosition then
				ACABDB.bagBarPosition = {
					point = "TOPLEFT",
					relativePoint = "BOTTOMLEFT",
					x = nativeLeft,
					y = nativeTop,
				}
			end

			-- Permanent pristine spacing snapshot, captured once via ComputeMajorityGap, never re-derived.
			if not ACABDB.bagBarNativeSpacing then
				ACABDB.bagBarNativeSpacing = nativeSpacing
			end

			if not ACABDB.bagBarSpacing then
				ACABDB.bagBarSpacing = nativeSpacing
			end

			-- Lays out the chain before ApplyBagBarPosition below, so the container's real size is already correct.
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

			-- Same external-re-anchor risk as Bag Bar above (seen live on QuestLogMicroButton) - all 8
			-- real buttons get guarded, not just the one that's been observed.
			do
				local guardIndex

				for guardIndex = 1, table.getn(buttons) do
					self:InstallReanchorGuard(buttons[guardIndex], "ACABApplyingMicroMenuPosition")
				end
			end

			-- Extra top-only overlay trim beyond the buttons' real GetHitRectInsets() (nil/0 for every
			-- other chain-anchored container).
			container.overlayTopFudge = self.MICRO_MENU_OVERLAY_TOP_FUDGE

			if not ACABDB.microMenuNativeAnchor then
				ACABDB.microMenuNativeAnchor = {
					point = "TOPLEFT",
					relativePoint = "BOTTOMLEFT",
					x = nativeLeft,
					y = nativeTop,
				}
			end

			if not ACABDB.microMenuPosition then
				ACABDB.microMenuPosition = {
					point = "TOPLEFT",
					relativePoint = "BOTTOMLEFT",
					x = nativeLeft,
					y = nativeTop,
				}
			end

			if not ACABDB.microMenuNativeSpacing then
				ACABDB.microMenuNativeSpacing = nativeSpacing
			end

			-- Fixed default of -3 (slider position 1, see the +4 display
			-- offset in simpleBarPageConfigs["micromenu"]) rather than the
			-- measured native gap - see ACAB:SetMicroMenuSpacing's own comment.
			if not ACABDB.microMenuSpacing then
				ACABDB.microMenuSpacing = -3
			end

			self:ApplyMicroMenuShape()

			self:ApplyMicroMenuPosition()
			self:SetMicroMenuEnabled(ACABDB.microMenuEnabled ~= false)
		end
	end
end

-- UpdateMicroButtons is vanilla FrameXML's own function deciding TalentMicroButton's (and others')
-- Show()/Hide() state. Hooked so ApplyMicroMenuShape's grid-compaction reacts the instant it changes.
if hooksecurefunc and UpdateMicroButtons then
	hooksecurefunc("UpdateMicroButtons", function()
		ACAB:ApplyMicroMenuShape()
	end)
end

-------------------------------------------------------------------------
-- Key Ring
-- KeyRingButton is a real global frame on this client. Deliberately not added to BAG_BAR_BUTTON_NAMES/
-- the Bag Bar's chain - independently toggleable and positionable. Repositioned directly via
-- PixelSetPoint, same single-real-frame treatment as ApplyStanceBarPosition's ShapeshiftBarFrame.
-- Every function below no-ops if KeyRingButton doesn't exist on some other client build.
-------------------------------------------------------------------------

ACAB.KEYRING_BUTTON_NAME = "KeyRingButton"

ACAB:InstallShowGuard(getglobal(ACAB.KEYRING_BUTTON_NAME), function()
	return ACABDB and ACABDB.keyRingEnabled ~= false
end)

-- Mirrors CaptureLatencyBarPositionIfNeeded below - captured lazily the first time it's needed, since
-- it can only be read from the real live frame.
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

	-- Permanent pristine snapshot (Reset to Vanilla Layout) - stores the frame's true native anchor via
	-- GetPoint(1), since native code anchors this frame relative to another real frame, not UIParent.
	-- Captured once, never rewritten.
	if not ACABDB.keyRingNativeAnchor then
		local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)

		if point and relativePoint and x and y then
			local relativeToName = "UIParent"

			if relativeTo and relativeTo.GetName and relativeTo:GetName() then
				relativeToName = relativeTo:GetName()
			end

			ACABDB.keyRingNativeAnchor = {
				point = point,
				relativeTo = relativeToName,
				relativePoint = relativePoint,
				x = x,
				y = y,
			}
		end
	end
end

-- Applies ACABDB.keyRingPosition to the real KeyRingButton and ensures its drag/right-click overlay
-- exists - mirrors ApplyBagBarPosition's structure against KeyRingButton itself.
function ACAB:ApplyKeyRingPosition()
	if self:ApplyGroupedIfActive("keyring") then
		return
	end

	self:CaptureKeyRingPositionIfNeeded()

	local frame = getglobal(self.KEYRING_BUTTON_NAME)

	if not frame then
		return
	end

	-- KeyRingButton has no explicit strata of its own (unlike the synthetic chain-anchored containers) -
	-- sets "HIGH" on every call so nothing can silently reset it to a lower tier.
	frame:SetFrameStrata("HIGH")

	-- KeyRingButton is natively parented to MainMenuBarArtFrame, which Main Bar's own art code scales by
	-- buttonSize/36 UNCONDITIONALLY (even with Blizzard art Fully Disabled - that only hides its regions,
	-- never touches the frame's own scale). Without this, Key Ring would visibly drift/resize any time
	-- Main Bar's buttonSize changes, regardless of whether it's grouped with Main Bar or not. Reasserted
	-- every call, same reasoning as SetFrameStrata above.
	self:SetKeyRingOwnScaleForEffective(frame, ACABDB.keyRingScale or 1)

	local pos = ACABDB.keyRingPosition

	if pos then
		frame:ClearAllPoints()
		self:PixelSetPoint(
			frame,
			pos.point or "TOPLEFT",
			UIParent,
			pos.relativePoint or "BOTTOMLEFT",
			pos.x or 0,
			pos.y or 0
		)
	end

	-- level = 150, above the 100 every other overlay uses - Key Ring's native default position overlaps
	-- the Bag Bar container's own overlay, so this guarantees Key Ring's drag surface wins the overlap.
	self:EnsureContainerOverlay(frame, self.StartKeyRingDrag, self.StopKeyRingDrag, "keyring", self.SetKeyRingScale, 150, "Key Ring")

	self:ApplyHoverOnlyState(frame, ACABDB.keyRingHoverOnly, function() return ACABDB.keyRingHoverDuration or 3 end)
end

-- Settings.lua's Key Ring page "Only show on hover" checkbox/slider.
function ACAB:SetKeyRingHoverOnly(enabled)
	self:EnsureDB()

	ACABDB.keyRingHoverOnly = enabled and true or false

	self:ApplyKeyRingPosition()
end

function ACAB:SetKeyRingHoverDuration(duration)
	self:EnsureDB()

	duration = self:ClampHoverDuration(duration)

	if not duration then
		return
	end

	ACABDB.keyRingHoverDuration = duration

	self:ApplyKeyRingPosition()
end

-- Settings.lua's Key Ring page "Enabled" checkbox - independent of the Bag Bar's own enable flag.
function ACAB:SetKeyRingEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.keyRingEnabled = enabled

	local frame = getglobal(self.KEYRING_BUTTON_NAME)

	if frame then
		if enabled then
			frame:Show()
		else
			frame:Hide()

			-- EnsureContainerOverlay's overlay is parented to UIParent, not `frame`, so hiding the real
			-- frame doesn't implicitly hide the overlay too.
			if frame.ACABOverlay then
				frame.ACABOverlay:Hide()
				frame.ACABOverlay:EnableMouse(false)
			end
		end
	end
end

function ACAB:SetKeyRingPosition(x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB.keyRingPosition then
		return
	end

	ACABDB.keyRingPosition.x = x
	ACABDB.keyRingPosition.y = y

	self:ApplyKeyRingPosition()
end

function ACAB:ResetKeyRingPosition()
	self:EnsureDB()

	local frame = getglobal(self.KEYRING_BUTTON_NAME)

	-- Direct write, not SetKeyRingScale(1) - that setter compensates the stored position using the OLD
	-- scale, which would inflate the native position resolved below. Set before resolving it.
	ACABDB.keyRingScale = 1

	if frame then
		-- TRUE effective scale 1, not just frame:SetScale(1) - see ApplyKeyRingPosition's own comment;
		-- ResolveNativeAnchorToAbsolute below needs the frame at a real effective scale of 1 to resolve
		-- correctly, which plain SetScale(1) wouldn't guarantee while Main Bar's buttonSize isn't 36.
		self:SetKeyRingOwnScaleForEffective(frame, 1)
	end

	local native = ACABDB.keyRingNativeAnchor
	local resolved = self:ResolveNativeAnchorToAbsolute(frame, native)

	if resolved then
		ACABDB.keyRingPosition = resolved
	end

	self:ApplyKeyRingPosition()
end

-- Mirrors SetLatencyBarScale's clamp/compensate/write/apply template.
function ACAB:SetKeyRingScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	local oldScale = ACABDB.keyRingScale or 1
	local pos = ACABDB.keyRingPosition
	local frame = getglobal(self.KEYRING_BUTTON_NAME)

	if pos and frame then
		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, "BOTTOMLEFT", nil, frame:GetHeight())
	end

	ACABDB.keyRingScale = scale

	if frame then
		-- Not a plain frame:SetScale(scale) - see ApplyKeyRingPosition's own comment on why Key Ring's
		-- native MainMenuBarArtFrame parentage needs this counteracted.
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

	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = "keyRing"
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = pos.x or 0
	frame.dragStartY = pos.y or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopKeyRingDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("keyring")
	end
end

-------------------------------------------------------------------------
-- Latency Bar
-- MainMenuBarPerformanceBarFrame is a direct sibling of MainMenuBarArtFrame under MainMenuBar, not a
-- child of it - ApplyBlizzardArtVisibility's region-hiding never touches it, and it needs its own fully
-- independent enable/scale/position treatment.
-------------------------------------------------------------------------

ACAB.LATENCY_BAR_FRAME_NAME = "MainMenuBarPerformanceBarFrame"

ACAB:InstallReanchorGuard(getglobal(ACAB.LATENCY_BAR_FRAME_NAME), "ACABApplyingLatencyBarPosition")

-- Mirrors CaptureKeyRingPositionIfNeeded above exactly.
function ACAB:CaptureLatencyBarPositionIfNeeded()
	self:EnsureDB()

	if ACABDB.latencyBarPosition then
		return
	end

	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)

	if not frame then
		return
	end

	-- Permanent pristine snapshot (Reset to Vanilla Layout) - stores the
	-- frame's true native anchor via GetPoint(1) rather than an absolute
	-- snapshot, since native code re-anchors this frame relative to
	-- another real frame, not UIParent (confirmed: BOTTOMRIGHT of
	-- MainMenuBar, -235,-10). Captured ONCE, never rewritten.
	if not ACABDB.latencyBarNativeAnchor then
		local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)

		if point and relativePoint and x and y then
			local relativeToName = "UIParent"

			if relativeTo and relativeTo.GetName and relativeTo:GetName() then
				relativeToName = relativeTo:GetName()
			end

			ACABDB.latencyBarNativeAnchor = {
				point = point,
				relativeTo = relativeToName,
				relativePoint = relativePoint,
				x = x,
				y = y,
			}
		end
	end

	-- Derives the initial absolute position from the relative native anchor above instead of a raw
	-- GetLeft()/GetTop() read - a raw read this early in login can catch MainMenuBar's layout before it settles.
	local resolved = self:ResolveNativeAnchorToAbsolute(frame, ACABDB.latencyBarNativeAnchor, "ACABApplyingLatencyBarPosition")

	if resolved then
		ACABDB.latencyBarPosition = resolved
	end
end

-- Applies ACABDB.latencyBarPosition to the real frame and ensures its drag/right-click overlay exists -
-- mirrors ApplyKeyRingPosition against MainMenuBarPerformanceBarFrame instead of KeyRingButton.
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

	if pos then
		frame.ACABApplyingLatencyBarPosition = true

		frame:ClearAllPoints()
		self:PixelSetPoint(
			frame,
			pos.point or "TOPLEFT",
			UIParent,
			pos.relativePoint or "BOTTOMLEFT",
			pos.x or 0,
			pos.y or 0
		)

		frame.ACABApplyingLatencyBarPosition = nil
	end

	frame.overlayInset = self.LATENCY_BAR_OVERLAY_INSET

	self:EnsureContainerOverlay(frame, self.StartLatencyBarDrag, self.StopLatencyBarDrag, "latencybar", self.SetLatencyBarScale, nil, "Latency Bar")

	self:ApplyHoverOnlyState(frame, ACABDB.latencyBarHoverOnly, function() return ACABDB.latencyBarHoverDuration or 3 end)
end

function ACAB:SetLatencyBarPosition(x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB.latencyBarPosition then
		return
	end

	ACABDB.latencyBarPosition.x = x
	ACABDB.latencyBarPosition.y = y

	self:ApplyLatencyBarPosition()
end

function ACAB:SetLatencyBarEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.latencyBarEnabled = enabled

	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)

	if frame then
		if enabled then
			frame:Show()
		else
			frame:Hide()

			-- Same explicit-hide requirement as SetKeyRingEnabled above.
			if frame.ACABOverlay then
				frame.ACABOverlay:Hide()
				frame.ACABOverlay:EnableMouse(false)
			end
		end
	end
end

-- Mirrors SetCastBarScale's clamp/compensate/write/apply template.
function ACAB:SetLatencyBarScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	local oldScale = ACABDB.latencyBarScale or 1
	local pos = ACABDB.latencyBarPosition
	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)

	if pos and frame then
		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, "BOTTOMLEFT", nil, frame:GetHeight())
	end

	ACABDB.latencyBarScale = scale

	if frame then
		frame:SetScale(scale)
	end

	if pos then
		self:ApplyLatencyBarPosition()
	end
end

-- Settings.lua's Latency Bar page "Only show on hover" checkbox/slider.
function ACAB:SetLatencyBarHoverOnly(enabled)
	self:EnsureDB()

	ACABDB.latencyBarHoverOnly = enabled and true or false

	self:ApplyLatencyBarPosition()
end

function ACAB:SetLatencyBarHoverDuration(duration)
	self:EnsureDB()

	duration = self:ClampHoverDuration(duration)

	if not duration then
		return
	end

	ACABDB.latencyBarHoverDuration = duration

	self:ApplyLatencyBarPosition()
end

-- Settings.lua's Latency Bar page "Reset to Vanilla Layout" button - restores position AND scale in one call.
function ACAB:ResetLatencyBarLayout()
	local native = ACABDB.latencyBarNativeAnchor
	local frame = getglobal(self.LATENCY_BAR_FRAME_NAME)

	-- Direct write, not SetLatencyBarScale(1) - that setter compensates the stored position using the
	-- OLD scale, which would inflate the native position we're about to restore. Set before resolving it.
	ACABDB.latencyBarScale = 1

	if frame then
		frame:SetScale(1)
	end

	local resolved = self:ResolveNativeAnchorToAbsolute(frame, native, "ACABApplyingLatencyBarPosition")

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

	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = "latencyBar"
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = pos.x or 0
	frame.dragStartY = pos.y or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopLatencyBarDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("latencybar")
	end
end

-------------------------------------------------------------------------
-- Cast Bar (CastingBarFrame) - single native frame, no Spacing/
-- Orientation/Enable, same Position/Scale/Reset/Drag treatment as the
-- Latency Bar/Experience Bar above.
-------------------------------------------------------------------------

ACAB.CAST_BAR_FRAME_NAME = "CastingBarFrame"

ACAB:InstallReanchorGuard(getglobal(ACAB.CAST_BAR_FRAME_NAME), "ACABApplyingCastBarPosition")

-- Mirrors CaptureLatencyBarPositionIfNeeded exactly.
function ACAB:CaptureCastBarPositionIfNeeded()
	self:EnsureDB()

	if ACABDB.castBarPosition then
		return
	end

	local frame = getglobal(self.CAST_BAR_FRAME_NAME)

	if not frame then
		return
	end

	-- Permanent pristine snapshot (Reset to Vanilla Layout) - stores the frame's true native anchor via
	-- GetPoint(1) rather than an absolute snapshot. Captured once, never rewritten.
	if not ACABDB.castBarNativeAnchor then
		local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)

		if point and relativePoint and x and y then
			local relativeToName = "UIParent"

			if relativeTo and relativeTo.GetName and relativeTo:GetName() then
				relativeToName = relativeTo:GetName()
			end

			ACABDB.castBarNativeAnchor = {
				point = point,
				relativeTo = relativeToName,
				relativePoint = relativePoint,
				x = x,
				y = y,
			}
		end
	end

	-- Derives the initial absolute position from the relative native anchor above, same reasoning as
	-- CaptureLatencyBarPositionIfNeeded.
	local resolved = self:ResolveNativeAnchorToAbsolute(frame, ACABDB.castBarNativeAnchor, "ACABApplyingCastBarPosition")

	if resolved then
		ACABDB.castBarPosition = resolved
	end
end

-- Mirrors ACAB:ApplyLatencyBarPosition exactly, minus the Enable branch.
function ACAB:ApplyCastBarPosition()
	self:CaptureCastBarPositionIfNeeded()

	local frame = getglobal(self.CAST_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local pos = ACABDB.castBarPosition

	if pos then
		frame.ACABApplyingCastBarPosition = true

		frame:ClearAllPoints()
		self:PixelSetPoint(
			frame,
			pos.point or "TOPLEFT",
			UIParent,
			pos.relativePoint or "BOTTOMLEFT",
			pos.x or 0,
			pos.y or 0
		)

		frame.ACABApplyingCastBarPosition = nil
	end

	self:EnsureContainerOverlay(frame, self.StartCastBarDrag, self.StopCastBarDrag, "castbar", self.SetCastBarScale, nil, "Cast Bar")
end

function ACAB:SetCastBarPosition(x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB.castBarPosition then
		return
	end

	ACABDB.castBarPosition.x = x
	ACABDB.castBarPosition.y = y

	-- User is now positioning this element by hand - stop auto-stacking its Y off Action Bar 1/2/Extra Bar 1/2/Pet Bar.
	ACABDB.castBarUsesDefaultPosition = false

	self:ApplyCastBarPosition()
end

-- Mirrors SetLatencyBarScale's clamp/write/apply template.
function ACAB:SetCastBarScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	local oldScale = ACABDB.castBarScale or 1
	local pos = ACABDB.castBarPosition
	local frame = getglobal(self.CAST_BAR_FRAME_NAME)

	if pos and frame then
		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, "BOTTOMLEFT", nil, frame:GetHeight())
	end

	ACABDB.castBarScale = scale

	if frame then
		frame:SetScale(scale)
	end

	if pos then
		self:ApplyCastBarPosition()
	end
end

-- Mirrors ResetLatencyBarLayout's position+scale bundling.
function ACAB:ResetCastBarLayout()
	local native = ACABDB.castBarNativeAnchor
	local frame = getglobal(self.CAST_BAR_FRAME_NAME)

	-- Direct write, not SetCastBarScale(1) - that setter compensates the stored position using the OLD
	-- scale, which would inflate the native position we're about to restore. Set before resolving it.
	ACABDB.castBarScale = 1

	if frame then
		frame:SetScale(1)
	end

	local resolved = self:ResolveNativeAnchorToAbsolute(frame, native, "ACABApplyingCastBarPosition")

	if resolved then
		ACABDB.castBarPosition = resolved

		-- Re-capture the floor fresh from the just-restored native spot, or it would keep stacking off the pre-reset position.
		ACABDB.castBarStackBaseY = resolved.y
	end

	ACABDB.castBarUsesDefaultPosition = true

	self:ApplyCastBarPosition()

	-- Prefer the computed baseline (stacked off Action Bar 1/2/Extra Bar 1/2/Pet Bar when active) over the raw restored native position.
	self:ReflowCastBarForStackToggle()
end

-------------------------------------------------------------------------
-- Cast Bar dynamic stacking (Default Layout mode only)
-- Cast Bar starts at its default Vanilla Layout position (the floor below) and moves up by,
-- independently: Action Bar 1/2's buttonSize if active, Extra Bar 1/2's buttonSize if active, and
-- Pet Bar's own size if active.
-------------------------------------------------------------------------

-- Permanent floor Y for the dynamic stack offset below, captured once. Never itself touched by
-- ReflowCastBarForStackToggle - only that function's output moves, always recomputed off this floor.
function ACAB:CaptureCastBarStackBaseYIfNeeded()
	self:EnsureDB()

	if ACABDB.castBarStackBaseY then
		return
	end

	self:CaptureCastBarPositionIfNeeded()

	local pos = ACABDB.castBarPosition

	if pos and pos.y then
		ACABDB.castBarStackBaseY = pos.y
	end
end

-- baselineY = floor + Action Bar 1/2's buttonSize (max of the two if both active) + Extra Bar 1/2's
-- buttonSize (same rule) + Pet Bar's own live height if shown. Uses max, not sum, since each pair sits
-- side-by-side at the same tier.
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

	-- usesDefaultPosition == false: the user dragged/slider-moved that Extra Bar away from its seeded slot, so it no longer counts here.
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

-- Only called while useDefaultLayout ~= false, so this never fights a manually dragged position once
-- the user switches to a custom layout. No-op once ACABDB.castBarUsesDefaultPosition is false.
function ACAB:ReflowCastBarForStackToggle()
	self:EnsureDB()

	if ACABDB.castBarUsesDefaultPosition == false then
		return
	end

	local pos = ACABDB.castBarPosition
	local y = self:GetCastBarBaselineY()

	if not pos or not y then
		return
	end

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

	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = "castBar"
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = pos.x or 0
	frame.dragStartY = pos.y or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopCastBarDrag()
	self:StopSharedDrag()

	-- User just moved this element by hand - stop auto-stacking its Y.
	ACABDB.castBarUsesDefaultPosition = false

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("castbar")
	end
end


-------------------------------------------------------------------------
-- Page Indicator (chain-anchored container)
-- Wraps the Main Bar's native page-turn arrows/page-number FontString the same way Bag Bar/Micro
-- Menu/Stance Bar wrap real Blizzard frames above. MainMenuBarPageNumber supports GetLeft/GetTop/
-- GetWidth/GetHeight/SetParent/IsShown/SetPoint like a Frame/Button region, except GetEffectiveScale.
-- CreatePageIndicatorContainer requires all three real frame names to resolve, or it silently never builds.
-- Position + Scale only. Orientation is fixed vertical; spacing is fixed at 0 as a cosmetic
-- simplification (ComputeMajorityGap only measures a horizontal gap).
-------------------------------------------------------------------------

ACAB.PAGE_INDICATOR_UP_NAME = "ActionBarUpButton"
ACAB.PAGE_INDICATOR_DOWN_NAME = "ActionBarDownButton"
ACAB.PAGE_INDICATOR_TEXT_NAME = "MainMenuBarPageNumber"

-- ApplyPageIndicatorShape's own settle-retry - same interval/timeout scale as Core.lua's WaitForNativeBarSettle.
local PAGE_INDICATOR_SHAPE_RETRY_INTERVAL = 0.1
local PAGE_INDICATOR_SHAPE_RETRY_TIMEOUT = 3

-- This container isn't a single row/column of same-size elements chained edge-to-edge - it's two
-- stacked arrow buttons plus a text label to their right, vertically centered, so it has its own
-- dedicated layout (CreatePageIndicatorContainer/ApplyPageIndicatorShape below).
function ACAB:CreatePageIndicatorContainer()
	self:EnsureDB()

	if self.pageIndicatorContainer then
		return
	end

	local up = getglobal(self.PAGE_INDICATOR_UP_NAME)
	local down = getglobal(self.PAGE_INDICATOR_DOWN_NAME)
	local text = getglobal(self.PAGE_INDICATOR_TEXT_NAME)

	-- Requires every element or skips the whole feature - a partial page indicator would be visually broken.
	if not up or not down or not text then
		return
	end

	-- Reads each element's real native anchor point (GetPoint(1), which the FontString supports unlike
	-- GetEffectiveScale) before reparenting anything - SetParent never rewrites another frame's own anchor points.
	local upPoint, upRelTo, upRelPoint, upX, upY = up:GetPoint(1)
	local downPoint, downRelTo, downRelPoint, downX, downY = down:GetPoint(1)
	local textPoint, textRelTo, textRelPoint, textX, textY = text:GetPoint(1)

	-- The container's own TOPLEFT is defined to equal Up's real native
	-- TOPLEFT (GetLeft()/GetTop()), converted through real screen pixels
	-- via each frame's own GetEffectiveScale, the same conversion as
	-- ACAB:CaptureNativeAnchor (Database.lua) (this container, like every default
	-- bar, is anchored directly to UIParent, and is a bare
	-- CreateFrame(..., UIParent) with no SetScale of its own, so its
	-- effective scale always equals UIParent's exactly).
	local nativeLeft = up:GetLeft()
	local nativeTop = up:GetTop()

	if not nativeLeft or not nativeTop then
		return
	end

	local upScale = up:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()

	if not upScale or not uiParentScale or uiParentScale == 0 then
		return
	end

	nativeLeft = (nativeLeft * upScale) / uiParentScale
	nativeTop = (nativeTop * upScale) / uiParentScale

	-- Down/Text's relationship to Up (or to each other) - read from the
	-- captured GetPoint() data, not assumed. If a captured relativeTo
	-- isn't one of the other two elements in this trio, falls back to
	-- reproducing the real on-screen delta from Up's own native corner
	-- (same-family measurement, no GetEffectiveScale correction needed,
	-- unlike nativeLeft/nativeTop above).
	self.pageIndicatorDownFollowsUp = (downRelTo == up)
	self.pageIndicatorTextFollowsUp = (textRelTo == up)
	self.pageIndicatorTextFollowsDown = (textRelTo == down)

	local downLeft, downTop = down:GetLeft(), down:GetTop()
	local textLeft, textTop = text:GetLeft(), text:GetTop()

	if not self.pageIndicatorDownFollowsUp and downLeft and downTop then
		self.pageIndicatorDownDeltaX = downLeft - up:GetLeft()
		self.pageIndicatorDownDeltaY = downTop - up:GetTop()
	end

	if not (self.pageIndicatorTextFollowsUp or self.pageIndicatorTextFollowsDown)
		and textLeft and textTop then
		self.pageIndicatorTextDeltaX = textLeft - up:GetLeft()
		self.pageIndicatorTextDeltaY = textTop - up:GetTop()
	end

	local container = CreateFrame("Frame", "ACABPageIndicatorContainer", UIParent)
	container:SetFrameStrata("HIGH")

	-- Container spans Up/Down/Text's real, untrimmed hit-rects (Up pinned exactly to container's
	-- TOPLEFT below). The edit-mode overlay is trimmed to the true visible art instead, via the
	-- existing overlayInset mechanism (same one Latency Bar uses for its own bigger-than-art frame).
	local upInsetL, upInsetR, upInsetT, upInsetB = self:GetHitInsets(up)
	local downInsetL, downInsetR, downInsetT, downInsetB = self:GetHitInsets(down)

	container.overlayInset = {
		left = upInsetL,
		right = 0,
		top = upInsetT,
		bottom = downInsetB,
	}

	-- Placeholder size, overwritten by ApplyPageIndicatorShape's real measurement below - this client
	-- never resolves a frame's GetLeft/Top/Right/Bottom until it's been given an explicit SetWidth/
	-- SetHeight at least once, even with a valid SetPoint already applied.
	container:SetWidth(1)
	container:SetHeight(1)

	up:SetParent(container)
	down:SetParent(container)
	text:SetParent(container)

	self.pageIndicatorContainer = container
	self.pageIndicatorUp = up
	self.pageIndicatorDown = down
	self.pageIndicatorText = text

	if not ACABDB.mainBarPageIndicatorNativeAnchor then
		ACABDB.mainBarPageIndicatorNativeAnchor = {
			point = "TOPLEFT",
			relativePoint = "BOTTOMLEFT",
			x = nativeLeft,
			y = nativeTop,
		}
	end

	if not ACABDB.mainBarPageIndicatorPosition then
		ACABDB.mainBarPageIndicatorPosition = {
			point = "TOPLEFT",
			relativePoint = "BOTTOMLEFT",
			x = nativeLeft,
			y = nativeTop,
		}
	end

	-- Position must run before Shape, so container has a resolved real screen point before Shape reads
	-- its now-reparented children's rects (frame rects resolve top-down on this client).
	self:ApplyPageIndicatorPosition()
	self:ApplyPageIndicatorShape()
	self:ApplyPageIndicatorVisibility()
end

-- Up is always reanchored to the container's own TOPLEFT. Down and the page-number text use the real
-- native relationship CreatePageIndicatorContainer captured via GetPoint(): left untouched if natively
-- anchored directly to Up/Down (SetParent never rewrote that anchor), otherwise reproduced as a
-- TOPLEFT-of-container offset using the real screen-space delta captured at the same time.
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

	if not self.pageIndicatorDownFollowsUp then
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

	if not (self.pageIndicatorTextFollowsUp or self.pageIndicatorTextFollowsDown) then
		-- PixelSetPoint safely falls back to plain SetPoint here (text is a FontString, no GetEffectiveScale).
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

	-- Container bounding box derived from the three real elements' actual current on-screen extents,
	-- rather than a formula assuming any particular chain topology. Untrimmed (Up's own hit-rect) since
	-- Up is pinned exactly to container's TOPLEFT with a 0 offset. Edit-mode hitbox is trimmed
	-- separately via container.overlayInset.
	local function RealRect(frame)
		local l, t, r, b = frame:GetLeft(), frame:GetTop(), frame:GetRight(), frame:GetBottom()
		if not (l and t and r and b) then
			return nil
		end
		return l, t, r, b
	end

	local upL, upT, upR, upB = RealRect(up)
	local downL, downT, downR, downB = RealRect(down)
	local textL, textT, textR, textB = RealRect(text)

	-- Up/Down/Text were just reparented/re-anchored above - on this client a frame's GetLeft/Top/
	-- Right/Bottom reads back nil for a beat after that. Retries on a short timer instead of baking in
	-- a bogus zero/partial-sized box.
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
end

function ACAB:ApplyPageIndicatorPosition()
	if self:ApplyGroupedIfActive("pageindicator") then
		return
	end

	local pos = ACABDB.mainBarPageIndicatorPosition
	local container = self.pageIndicatorContainer

	if not pos or not container then
		return
	end

	container:ClearAllPoints()
	self:PixelSetPoint(
		container,
		pos.point or "TOPLEFT",
		UIParent,
		pos.relativePoint or "BOTTOMLEFT",
		pos.x or 0,
		pos.y or 0
	)

	-- settingsKey = 1: this element has no page of its own; its Scale slider lives on bar 1's own
	-- settings page, so a right-click opens that page instead.
	self:EnsureContainerOverlay(
		container,
		self.StartPageIndicatorDrag,
		self.StopPageIndicatorDrag,
		1,
		self.SetPageIndicatorScale,
		nil,
		"Page Indicator"
	)
end

-- Settings.lua's Main Bar page Scale slider writes through this - mirrors SetStanceBarScale's
-- clamp/write/apply template.
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
	end
end

-- Mirrors ResetKeyRingPosition's structure: restore position from the permanent
-- mainBarPageIndicatorNativeAnchor snapshot, then reset scale to 1.
function ACAB:ResetPageIndicatorLayout()
	self:EnsureDB()

	local native = ACABDB.mainBarPageIndicatorNativeAnchor

	if native then
		ACABDB.mainBarPageIndicatorPosition = {
			point = native.point,
			relativePoint = native.relativePoint,
			x = native.x,
			y = native.y,
		}

		self:ApplyPageIndicatorPosition()
	end

	self:SetPageIndicatorScale(1)
end

-- Settings.lua's Main Bar "Reset to Modern Layout Default" button - Page Indicator has no fixed target
-- spot, so this reads Main Bar's real rendered edge live and sits flush to it, vertically centered.
function ACAB:ResetPageIndicatorToModernBase()
	self:EnsureDB()

	if ACABDB.defaultBarPaginationEnabled == false then
		return
	end

	local bar1 = self.bars and self.bars[1]
	local container = self.pageIndicatorContainer

	if not bar1 or not container then
		return
	end

	local _, mainBarRight, mainBarTop, mainBarBottom = self:GetElementRealEdges(bar1)

	if not mainBarRight then
		return
	end

	local overlay = container.ACABOverlay
	local indicatorHeight = container:GetHeight() or ACAB.BUTTON_SIZE
	local indicatorLeftGap = 0
	local indicatorBottomGap = 0

	if overlay then
		local containerLeft = container:GetLeft()
		local containerBottom = container:GetBottom()
		local overlayLeft = overlay:GetLeft()
		local overlayTop = overlay:GetTop()
		local overlayBottom = overlay:GetBottom()

		if containerLeft and overlayLeft then
			indicatorLeftGap = overlayLeft - containerLeft
		end

		if containerBottom and overlayBottom then
			indicatorBottomGap = overlayBottom - containerBottom
		end

		if overlayTop and overlayBottom then
			indicatorHeight = overlayTop - overlayBottom
		end
	end

	local mainBarCenterY = (mainBarTop + mainBarBottom) / 2

	ACABDB.mainBarPageIndicatorPosition = {
		point = "BOTTOMLEFT", relativePoint = "BOTTOMLEFT",
		x = (mainBarRight + 6) - indicatorLeftGap,
		y = (mainBarCenterY - (indicatorHeight / 2)) - indicatorBottomGap,
	}

	self:ApplyPageIndicatorPosition()
	self:SetPageIndicatorScale(1)
end

-- Bag Bar's real live width/height (or a formula-based fallback before its container exists).
local function MeasureBagBarFootprint(self, buttonSize, spacing)
	local width = (self.bagBarContainer and self.bagBarContainer:GetWidth()) or (5 * (buttonSize + spacing))
	local height = (self.bagBarContainer and self.bagBarContainer:GetHeight()) or buttonSize

	return width, height
end

-- Micro Menu's stack anchors: microMenuOverlayTop (Y to stack Latency Bar's own top against, given
-- bagBarHeight) and microMenuOverlayLeftOffset (X to stack Latency Bar's own right against), both
-- netting out the gap between Micro Menu's container and its trimmed overlay hitbox.
local function MeasureMicroMenuStackAnchors(self, buttonSize, spacing, bagBarHeight)
	local microMenuWidth = (self.microMenuContainer and self.microMenuContainer:GetWidth())
		or ((ACABDB.microMenuCols or 8) * (buttonSize + spacing))
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

-- Modern Layout's bottom-right corner cluster: Bag Bar flush in the corner, Micro Menu stacked on top
-- of it, Key Ring to Bag Bar's left, Latency Bar to Micro Menu's left (top-aligned). Used by the Setup
-- Wizard's Modern Layout choice to set up all 4 together - each element's own "Reset to Modern Layout
-- Default" button instead calls its own ApplyModernSingle* below, so resetting one never moves the
-- others. Every gap is flush (0), reading each container's real live GetWidth()/GetHeight().
function ACAB:ApplyModernCornerClusterLayout()
	self:EnsureDB()

	local buttonSize, spacing = self:GetModernLayoutSizing()

	-- Every measurement below reads each element's CURRENT container/overlay, before writing any new
	-- position - measuring right after an ApplyXPosition() call can read a just-recreated overlay before
	-- its geometry has settled on this client.
	local bagBarWidth, bagBarHeight = MeasureBagBarFootprint(self, buttonSize, spacing)
	local microMenuOverlayTop, microMenuOverlayLeftOffset = MeasureMicroMenuStackAnchors(self, buttonSize, spacing, bagBarHeight)
	local latencyBarHeight, latencyBarOverlayBottomGap, latencyBarOverlayRightGap = MeasureLatencyBarOwnOverlay(self, buttonSize)

	-- All measurements taken - now write every target position and apply them in one final pass, so
	-- nothing above ever reads a frame this same call already repositioned.
	ACABDB.bagBarPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = 0, y = 0,
	}

	-- Key Ring: directly to Bag Bar's left, same row, flush.
	ACABDB.keyRingPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = -bagBarWidth, y = 0,
	}

	-- Micro Menu: stacked directly on top of Bag Bar, same right edge, flush.
	ACABDB.microMenuPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = 0, y = bagBarHeight,
	}

	-- Latency Bar: its own overlay hitbox flush against Micro Menu's overlay hitbox on the left, top
	-- edges aligned (nudged down 5 units to read slightly better against Micro Menu's icon row).
	ACABDB.latencyBarPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = microMenuOverlayLeftOffset + latencyBarOverlayRightGap,
		y = ((microMenuOverlayTop - latencyBarHeight) - latencyBarOverlayBottomGap) - 5,
	}

	self:ApplyBagBarPosition()
	self:ApplyKeyRingPosition()
	self:ApplyMicroMenuPosition()
	self:ApplyLatencyBarPosition()
end

-- Settings.lua's Bag Bar page "Reset to Modern Layout Default" button - flush in the bottom-right corner.
function ACAB:ApplyModernSingleBagBar()
	self:EnsureDB()

	ACABDB.bagBarPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = 0, y = 0,
	}

	self:ApplyBagBarPosition()
end

-- Settings.lua's Key Ring page "Reset to Modern Layout Default" button - left of Bag Bar's Modern Layout
-- spot, without moving Bag Bar itself.
function ACAB:ApplyModernSingleKeyRing()
	self:EnsureDB()

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local bagBarWidth = MeasureBagBarFootprint(self, buttonSize, spacing)

	ACABDB.keyRingPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = -bagBarWidth, y = 0,
	}

	self:ApplyKeyRingPosition()
end

-- Settings.lua's Micro Menu page "Reset to Modern Layout Default" button - stacks on Bag Bar's current
-- real height without moving Bag Bar itself, independent of Latency Bar.
function ACAB:ApplyModernSingleMicroMenu()
	self:EnsureDB()

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local _, bagBarHeight = MeasureBagBarFootprint(self, buttonSize, spacing)

	ACABDB.microMenuPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = 0, y = bagBarHeight,
	}

	self:ApplyMicroMenuPosition()
end

-- Settings.lua's Latency Bar page "Reset to Modern Layout Default" button - stacks against Micro
-- Menu's/Bag Bar's current real geometry without moving either, independent of them.
function ACAB:ApplyModernSingleLatencyBar()
	self:EnsureDB()

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local _, bagBarHeight = MeasureBagBarFootprint(self, buttonSize, spacing)
	local microMenuOverlayTop, microMenuOverlayLeftOffset = MeasureMicroMenuStackAnchors(self, buttonSize, spacing, bagBarHeight)
	local latencyBarHeight, latencyBarOverlayBottomGap, latencyBarOverlayRightGap = MeasureLatencyBarOwnOverlay(self, buttonSize)

	ACABDB.latencyBarPosition = {
		point = "BOTTOMRIGHT", relativePoint = "BOTTOMRIGHT",
		x = microMenuOverlayLeftOffset + latencyBarOverlayRightGap,
		y = ((microMenuOverlayTop - latencyBarHeight) - latencyBarOverlayBottomGap) - 5,
	}

	self:ApplyLatencyBarPosition()
end

-- No independent enable flag - this element's visibility is entirely derived from ACABDB.defaultBarPaginationEnabled.
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

	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = "pageIndicator"
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = pos.x or 0
	frame.dragStartY = pos.y or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopPageIndicatorDrag()
	self:StopSharedDrag()

	-- The Scale slider lives on the Main Bar's own settings page (barId 1) - this element has no
	-- "simple bar page" of its own.
	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(1)
	end
end

-------------------------------------------------------------------------
-- Tooltip (synthetic container, redirects the fixed-position GameTooltip)
-- No real Blizzard frame to wrap - a bare CreateFrame moved/scaled through the same position/scale/
-- enable/drag family every other native element uses. Repositions only the fixed-position GameTooltip
-- (quest log rows, NPC hover, etc.) via a hooksecurefunc on GameTooltip_SetDefaultAnchor; widget-relative
-- tooltips never call that function and stay untouched.
-------------------------------------------------------------------------

ACAB.TOOLTIP_FRAME_WIDTH = 200
ACAB.TOOLTIP_FRAME_HEIGHT = 100

-- Creates the synthetic frame once and lazily seeds ACABDB.tooltipPosition from the real native corner
-- GameTooltip_SetDefaultAnchor always ends up at (BOTTOMRIGHT of UIParent, -103/125).
function ACAB:EnsureTooltipFrame()
	self:EnsureDB()

	if self.tooltipFrame then
		return
	end

	local frame = CreateFrame("Frame", "ACABTooltipFrame", UIParent)

	self:PixelSetSize(frame, self.TOOLTIP_FRAME_WIDTH, self.TOOLTIP_FRAME_HEIGHT)

	self.tooltipFrame = frame

	if not ACABDB.tooltipPosition then
		local screenWidth = GetScreenWidth() or 1024

		ACABDB.tooltipPosition = {
			point = "TOPLEFT",
			relativePoint = "BOTTOMLEFT",
			x = screenWidth - 103 - self.TOOLTIP_FRAME_WIDTH,
			y = 125 + self.TOOLTIP_FRAME_HEIGHT,
		}
	end
end

-- Applies ACABDB.tooltipPosition to the synthetic frame and ensures its
-- drag/right-click overlay exists.
function ACAB:ApplyTooltipPosition()
	self:EnsureTooltipFrame()

	local pos = ACABDB.tooltipPosition
	local frame = self.tooltipFrame

	if not pos or not frame then
		return
	end

	frame:ClearAllPoints()
	self:PixelSetPoint(
		frame,
		pos.point or "TOPLEFT",
		UIParent,
		pos.relativePoint or "BOTTOMLEFT",
		pos.x or 0,
		pos.y or 0
	)

	self:EnsureContainerOverlay(frame, self.StartTooltipDrag, self.StopTooltipDrag, "tooltip", self.SetTooltipScale, nil, "Tooltip")
end

-- Settings.lua's Tooltip page X/Y sliders write through this.
function ACAB:SetTooltipPosition(x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB.tooltipPosition then
		return
	end

	ACABDB.tooltipPosition.x = x
	ACABDB.tooltipPosition.y = y

	self:ApplyTooltipPosition()
end

-- Mirrors SetLatencyBarScale's template, but compensates whichever corner ACABDB.tooltipAnchorCorner
-- currently selects - that's the corner GameTooltip actually anchors to, so it must stay fixed while scaling.
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

-- Settings.lua's Tooltip page "Grows From" dropdown. Display preference
-- only - takes effect the next time a tooltip is shown, no reposition here.
function ACAB:SetTooltipAnchorCorner(corner)
	self:EnsureDB()

	if corner ~= "TOPLEFT" and corner ~= "TOPRIGHT" and corner ~= "BOTTOMLEFT" and corner ~= "BOTTOMRIGHT" then
		return
	end

	ACABDB.tooltipAnchorCorner = corner
end

-- Settings.lua's Tooltip page enable checkbox (and its bar-list inline
-- checkbox).
function ACAB:SetTooltipEnabled(enabled)
	self:EnsureDB()

	ACABDB.tooltipEnabled = enabled and true or false

	self:ApplyDefaultLayoutEditVisual()
end

-- Settings.lua's Tooltip page "Reset to Vanilla Layout" button - recomputes the same native-default
-- conversion EnsureTooltipFrame's lazy seed uses (screen width may have changed since login).
function ACAB:ResetTooltipLayout()
	self:EnsureDB()

	-- Direct write, not SetTooltipScale(1) - that setter compensates the stored position using the OLD
	-- scale, which would shift the fresh default position below. Mirrors ResetLatencyBarLayout's pattern.
	ACABDB.tooltipScale = 1
	ACABDB.tooltipAnchorCorner = "BOTTOMRIGHT"

	if self.tooltipFrame then
		self.tooltipFrame:SetScale(1)
	end

	local screenWidth = GetScreenWidth() or 1024

	ACABDB.tooltipPosition = {
		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = screenWidth - 103 - self.TOOLTIP_FRAME_WIDTH,
		y = 125 + self.TOOLTIP_FRAME_HEIGHT,
	}

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

-- Redirects every fixed-position GameTooltip call onto this addon's own frame. hooksecurefunc on a
-- plain global function fires for any tooltip object calling it (e.g. ItemRefTooltip), hence the
-- identity guard below.
function ACAB:HookGameTooltipDefaultAnchor()
	if self.tooltipDefaultAnchorHooked then
		return
	end

	self.tooltipDefaultAnchorHooked = true

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

