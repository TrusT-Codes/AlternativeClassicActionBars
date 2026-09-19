-- PetStanceBars.lua
-- Pet Bar (native mode) and Stance Bar (native mode) - kept in one file
-- since they cross-call each other's Reflow*ForBar*Toggle functions.
-- Built on the shared chain-anchored container engine defined in
-- DefaultBars.lua - this file must load after DefaultBars.lua.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Pet Bar (native container - opt-in alternative to the custom-styled pool-button Pet Bar, cfg.useNativePetBar)
-- Same BuildChainAnchoredContainer/ApplyChainAnchoredShape/EnsureContainerOverlay machinery as Bag
-- Bar/Micro Menu, applied to the real PetActionButton1-10 frames - keeps native icon/cooldown/
-- drag-to-reorder/autocast-glow rendering intact.
-- Position/spacing read/write straight from ACABDB.defaultBars[PET_BAR_ID] (the same cfg the
-- custom-styled mode uses), so toggling modes never desyncs placement - only cfg.scale is new.
-------------------------------------------------------------------------

-- Fixed vertical clearance between Pet Bar and whichever default bar (1 or 3) is topmost -
-- PetActionBarFrame's own GetBottom() is unreliable on this client.
ACAB.PET_BAR_NATIVE_GAP = 14

-- referenceY is bar 3's nativeAnchor.y if bar 3 is enabled, else bar 1's - mirrors
-- GetStanceBarBaselineY for Bar 3 instead of Bar 2. baselineY = referenceBar.top + gap + height.
function ACAB:GetPetBarBaselineY(bar3Enabled)
	local defaults = ACABDB and ACABDB.defaultBars
	local cfg1 = defaults and defaults[1]
	local cfg3 = defaults and defaults[3]

	local referenceY = cfg1 and cfg1.nativeAnchor and cfg1.nativeAnchor.y

	if bar3Enabled and cfg3 and cfg3.nativeAnchor then
		referenceY = cfg3.nativeAnchor.y

		-- Extra Bar 2 sits above Bar 3 - stack Pet Bar above it too when both are enabled.
		referenceY = referenceY + self:GetExtraBarStackPitch(self.EXTRA_BAR_ID_START + 1)
	end

	if not referenceY then
		return nil
	end

	local container = self.petBarNativeContainer

	if not container then
		return nil
	end

	return referenceY + self.PET_BAR_NATIVE_GAP + container:GetHeight()
end

-- Re-stacks Pet Bar vertically off Bar 3's toggle state - mirrors ReflowStanceBarForBar2Toggle for Bar 3
-- instead of Bar 2. Only call while useDefaultLayout ~= false, or this fights a manually dragged
-- position. No-op once cfg.usesDefaultPosition is false.
function ACAB:ReflowPetBarForBar3Toggle(bar3Enabled)
	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]
	local container = self.petBarNativeContainer

	if not cfg or not container or cfg.usesDefaultPosition == false then
		return
	end

	local y = self:GetPetBarBaselineY(bar3Enabled)

	if not y then
		return
	end

	cfg.y = y

	if cfg.nativeAnchor then
		cfg.nativeAnchor.y = y
	end

	self:ApplyPetBarNativePosition()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(self.PET_BAR_ID)
	end
end

function ACAB:CreatePetBarNativeContainer()
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg or not self:IsPetBarNativeModeEffective() or self.petBarNativeContainer then
		return
	end

	local buttons = self:GetDefaultBarButtons(self.PET_BAR_ID)

	if not buttons then
		return
	end

	self:SortButtonsByNativeLeft(buttons)

	local container = self:BuildChainAnchoredContainer("ACABPetBarNativeContainer", buttons)

	self.petBarNativeContainer = container
	self.petBarNativeButtons = buttons

	self:ApplyPetBarNativeShape()
	self:ApplyPetBarNativePosition()
	self:SetDefaultBarEnabled(self.PET_BAR_ID, cfg.enabled)
end

-- Uses cfg.point/cfg.relativePoint directly (same defaults as Bar.lua's ApplyBarPosition) rather than
-- Bag Bar's hardcoded TOPLEFT/BOTTOMLEFT - this cfg is shared with the custom-styled mode.
function ACAB:ApplyPetBarNativePosition()
	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[self.PET_BAR_ID]
	local container = self.petBarNativeContainer

	if not cfg or not container then
		return
	end

	container:ClearAllPoints()
	self:PixelSetPoint(
		container,
		cfg.point or "TOPLEFT",
		UIParent,
		cfg.relativePoint or "TOPLEFT",
		cfg.x or 0,
		cfg.y or 0
	)

	self:EnsureContainerOverlay(container, self.StartPetBarNativeDrag, self.StopPetBarNativeDrag, self.PET_BAR_ID, self.SetPetBarNativeScale, nil, "Pet Bar", not self:ShouldCondensePetBarSlots())

	-- Same cfg the custom-styled Pet Bar's grid reads, so toggling display mode preserves the hover preference.
	self:ApplyHoverOnlyState(container, cfg.hoverOnly, function() return cfg.hoverDuration or 3 end)
end

-- Settings.lua's Pet Bar page X/Y sliders (native mode) write through this.
function ACAB:SetPetBarNativePosition(x, y)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	x = tonumber(x)
	y = tonumber(y)

	if not cfg or not x or not y then
		return
	end

	cfg.x = x
	cfg.y = y

	-- User is now positioning this element by hand - stop auto-stacking its Y off Bar 3/Extra Bar 2.
	cfg.usesDefaultPosition = false

	self:ApplyPetBarNativePosition()
end

-- Re-lays-out the real PetActionButton1-10 frames from cfg.spacing/cfg.scale - orientation is always
-- horizontal (real native Pet Bar has no vertical layout option).
function ACAB:ApplyPetBarNativeShape()
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg then
		return
	end

	self:ApplyChainAnchoredShape(
		self.petBarNativeContainer,
		cfg.spacing or 0,
		false,
		cfg.scale or 1,
		not self:ShouldCondensePetBarSlots()
	)
end

-- Mirrors SetDefaultBarSpacing's clamp/write/reapply template, writing the same cfg.spacing field the
-- custom-styled Pet Bar's grid uses.
function ACAB:SetPetBarNativeSpacing(spacing)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	spacing = self:ClampSpacingSetting(spacing, 0, 20)

	if not cfg or not spacing then
		return
	end

	cfg.spacing = spacing

	self:ApplyPetBarNativeShape()
end

-- Mirrors SetBagBarScale's clamp/write/reapply template.
function ACAB:SetPetBarNativeScale(scale)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	scale = self:ClampScaleSetting(scale)

	if not cfg or not scale then
		return
	end

	local oldScale = cfg.scale or 1

	if self.petBarNativeContainer then
		self:CompensateScaleKeepingCornerFixed(cfg, oldScale, scale, "BOTTOMLEFT", nil, self.petBarNativeContainer:GetHeight())
	end

	cfg.scale = scale

	self:ApplyPetBarNativeShape()
	self:ApplyPetBarNativePosition()
end

-- Settings.lua's Pet Bar native page "Only show on hover" checkbox/slider - writes the same cfg.hoverOnly/cfg.hoverDuration fields the styled grid uses.
function ACAB:SetPetBarNativeHoverOnly(enabled)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg then
		return
	end

	cfg.hoverOnly = enabled and true or false

	self:ApplyPetBarNativePosition()
end

function ACAB:SetPetBarNativeHoverDuration(duration)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	duration = self:ClampHoverDuration(duration)

	if not cfg or not duration then
		return
	end

	cfg.hoverDuration = duration

	self:ApplyPetBarNativePosition()
end

-- Restores position/spacing (cfg.nativeAnchor/cfg.nativeSpacing) and scale, mirroring ResetBagBarLayout's own reset template.
function ACAB:ResetPetBarNativeLayout()
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg or not cfg.nativeAnchor then
		return
	end

	cfg.point = cfg.nativeAnchor.point
	cfg.relativePoint = cfg.nativeAnchor.relativePoint
	cfg.x = cfg.nativeAnchor.x
	cfg.y = cfg.nativeAnchor.y

	-- Prefer the computed baseline over the raw captured nativeAnchor - PetActionButton1's live position
	-- only reflects whichever bar native layout had it stacked against at capture time, which can be stale.
	local bar3Cfg = ACABDB.defaultBars[3]
	local computedY = self:GetPetBarBaselineY(bar3Cfg and bar3Cfg.enabled)

	if computedY then
		cfg.y = computedY
	end

	if cfg.nativeSpacing then
		cfg.spacing = cfg.nativeSpacing
	end

	cfg.scale = 1

	cfg.usesDefaultPosition = true

	self:ApplyPetBarNativePosition()
	self:ApplyPetBarNativeShape()
end

-- Settings.lua's Pet Bar page "Reset to Modern Layout Default" button -
-- positions Pet Bar directly flush above Action Bar 2 (bar 3), zero gap,
-- right edges aligned, reading bar 3's REAL rendered edge
-- (ACAB:GetElementRealEdges) rather than a buttonSize*N formula, so it
-- stays correct regardless of bar 3's own current buttonSize/border
-- style. Branches on native vs styled mode (ACAB:IsPetBarNativeModeEffective) -
-- native mode has no self.bars[PET_BAR_ID] pool bar to position, styled
-- mode has no petBarNativeContainer.
function ACAB:ResetPetBarLayoutToModernBase()
	self:EnsureDB()

	local bar3 = self.bars and self.bars[3]

	if not bar3 then
		return
	end

	local _, bar3Right, bar3Top = self:GetElementRealEdges(bar3)

	if not bar3Right then
		return
	end

	if self:IsPetBarNativeModeEffective() then
		local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

		-- Built on demand - a mode switch mid-session can want native when this session's boot built styled instead.
		self:CreatePetBarNativeContainer()

		local container = self.petBarNativeContainer

		if not cfg or not container then
			return
		end

		-- Layout first: PixelSetPoint reads the container's live GetEffectiveScale to stay pixel-perfect,
		-- so applying position while a stale scale is still live lands it at the wrong X/Y.
		cfg.scale = self:GetModernPetStanceScale()
		self:ApplyPetBarNativeShape()

		local containerLeft, containerRight = self:GetElementRealEdges(container)
		local containerWidth = (containerLeft and containerRight and (containerRight - containerLeft)) or container:GetWidth() or 0
		local _, _, _, insetBottom = self:GetElementVisualInset(container)

		cfg.point = "BOTTOMLEFT"
		cfg.relativePoint = "BOTTOMLEFT"
		cfg.x = self:ConvertUIParentOffsetToOwnScale(container, bar3Right - containerWidth)
		cfg.y = self:ConvertUIParentOffsetToOwnScale(container, bar3Top + insetBottom)

		cfg.usesDefaultPosition = false

		self:ApplyPetBarNativePosition()
		return
	end

	-- Styled mode: a regular Bar.lua pool bar - styled buttons already respect cfg.buttonSize directly,
	-- so no scale-compensation trick is needed. Built on demand - a fresh profile's first login always
	-- boots native, so the styled bar this mode switch needs may not exist yet this session.
	self:EnsureFixedSlotBarCreated(self.PET_BAR_ID)

	local petBar = self.bars[self.PET_BAR_ID]

	if not petBar then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local cfg = petBar.config

	cfg.buttonSize = buttonSize
	cfg.spacing = spacing
	cfg.cols = 10
	cfg.rows = 1
	cfg.buttonCount = 10

	local barWidth = (buttonSize * 10) + (spacing * 9)
	local _, insetRight, _, insetBottom = self:GetElementVisualInset(petBar)

	cfg.point = "BOTTOMLEFT"
	cfg.relativePoint = "BOTTOMLEFT"
	cfg.x = bar3Right - insetRight - barWidth
	cfg.y = bar3Top + insetBottom

	self:ApplyBarPosition(petBar)
	self:SetBarLayout(petBar, cfg.cols, cfg.rows)
	self:SetBarButtonSize(petBar, buttonSize)
	self:ApplyBarShape(petBar)
	self:SetDefaultBarEnabled(self.PET_BAR_ID, true)
end

function ACAB:StartPetBarNativeDrag()
	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg then
		return
	end

	self:StartSharedDrag("petBarNative", nil, cfg.x or 0, cfg.y or 0)
end

function ACAB:StopPetBarNativeDrag()
	self:StopSharedDrag()

	-- User just moved this element by hand - stop auto-stacking its Y.
	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if cfg then
		cfg.usesDefaultPosition = false
	end

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(self.PET_BAR_ID)
	end
end

-------------------------------------------------------------------------
-- Stance Bar (chain-anchored container)
-- Uses the same chain-anchored-container technique as Bag Bar/Micro Menu: real ShapeshiftButton#
-- frames are reparented into our own synthetic container, keeping native shapeshift-form rendering intact.
-- Unlike Bag Bar/Micro Menu, the Stance Bar's button count is class/talent-driven (GetNumShapeshiftForms()),
-- not fixed - RebuildStanceBarContainer below re-enumerates and updates the chain in place when it changes.
-------------------------------------------------------------------------

-- Captures the real, permanent vertical clearance vanilla leaves between whichever default bar (1 or 2)
-- is topmost and ShapeshiftBarFrame's own true native position. Lazy-capture-once, guarded on
-- ACABDB.stanceBarNativeGap already being present.
-- Must run before ACAB:CreateFixedSlotDefaultBars() - that function permanently hides bar 2's real
-- buttons, which collapses ShapeshiftBarFrame's native anchor before this capture can read it. The call
-- from CreateStanceBarContainer below is a harmless no-op safety net if the early call hasn't run yet.
function ACAB:CaptureStanceBarNativeGap()
	if ACABDB.stanceBarNativeGap then
		return
	end

	local frame = ShapeshiftBarFrame

	if not frame then
		return
	end

	local bottom = frame:GetBottom()

	if not bottom then
		return
	end

	local frameScale = frame:GetEffectiveScale()
	local targetScale = UIParent:GetEffectiveScale()

	if not frameScale or not targetScale or targetScale == 0 then
		return
	end

	local screenBottom = (bottom * frameScale) / targetScale

	local defaults = ACABDB.defaultBars
	local cfg1 = defaults and defaults[1]
	local cfg2 = defaults and defaults[2]

	local referenceY = cfg1 and cfg1.nativeAnchor and cfg1.nativeAnchor.y

	if cfg2 and cfg2.enabled and cfg2.nativeAnchor then
		referenceY = cfg2.nativeAnchor.y
	end

	if not referenceY then
		return
	end

	local gap = screenBottom - referenceY

	-- A real inter-row gap is never negative or anywhere near a full button's size (real value is ~5).
	-- A value outside this range means the read hit a corrupted/unreflowed frame - never persist it.
	if gap <= 0 or gap >= self.BUTTON_SIZE then
		self:Print(
			"WARNING: Stance Bar native gap capture produced an implausible " ..
			"value (" .. tostring(gap) .. ") and was discarded - falling back " ..
			"to a default clearance until a later capture succeeds."
		)
		return
	end

	ACABDB.stanceBarNativeGap = gap
end

-- ShapeshiftBarFrame keeps its own native end-cap/middle background textures even after every
-- ShapeshiftButtonN is reparented out of it. Hidden and Show()-neutered unconditionally, since
-- UPDATE_SHAPESHIFT_FORMS runs vanilla's own ShapeshiftBar_Update() (which re-Shows this frame).
local function HideShapeshiftBarFrame()
	ACAB:NeuterFrameShow(ShapeshiftBarFrame)
end

-- Builds the Stance Bar's synthetic container the first time there are active stance/form buttons to
-- show - mirrors CreateBagBarAndMicroMenu's structure (native anchor/spacing captured once). No-op if
-- GetNumShapeshiftForms() is 0 right now - RebuildStanceBarContainer calls this again once forms become available.
function ACAB:CreateStanceBarContainer()
	self:EnsureDB()

	-- Styled mode: the real ShapeshiftButtonN frames are hidden+neutered and driven by Button.lua's own
	-- isStanceSlot pool instead - this native container must not build over them.
	if not self:IsStanceBarNativeModeEffective() then
		return
	end

	if self.stanceBarContainer then
		return
	end

	local buttons = self:GetStanceBarButtons()

	if not buttons then
		return
	end

	-- The real capture happens earlier, from Core.lua's RunLoginSequence - this call is a harmless
	-- no-op safety net, guarded on stanceBarNativeGap already being set.
	self:CaptureStanceBarNativeGap()

	self:SortButtonsByNativeLeft(buttons)

	local container, nativeLeft, nativeTop, nativeSpacing =
		self:BuildChainAnchoredContainer("ACABStanceBarContainer", buttons)

	self.stanceBarContainer = container
	self.stanceBarButtons = buttons

	if not ACABDB.stanceBarNativeAnchor then
		ACABDB.stanceBarNativeAnchor = {
			point = "TOPLEFT",
			relativePoint = "BOTTOMLEFT",
			x = nativeLeft,
			y = nativeTop,
		}
	end

	if not ACABDB.stanceBarPosition then
		ACABDB.stanceBarPosition = {
			point = "TOPLEFT",
			relativePoint = "BOTTOMLEFT",
			x = nativeLeft,
			y = nativeTop,
		}
	end

	if not ACABDB.stanceBarNativeSpacing then
		ACABDB.stanceBarNativeSpacing = nativeSpacing
	end

	-- Routed through the setter (not a direct write) so a fresh install's first default spacing still
	-- gets floored to the real measured border overhang in vanilla style.
	if not ACABDB.stanceBarSpacing then
		self:SetStanceBarSpacing(nativeSpacing)
	end

	self:ApplyStanceBarShape()
	self:ApplyStanceBarBorderStyle()

	self:ApplyStanceBarPosition()
	self:SetStanceBarEnabled(ACABDB.stanceBarEnabled ~= false)

	HideShapeshiftBarFrame()
end

-- Called from UPDATE_SHAPESHIFT_FORMS any time the set of available forms
-- can have changed. If the container doesn't exist yet, defers to
-- CreateStanceBarContainer. If it already exists, updates its chain IN
-- PLACE (re-enumerates active buttons, reparents newly-active ones,
-- re-runs ApplyChainAnchoredShape) rather than tearing down and
-- recreating it, so saved position/spacing/scale/orientation survive.
function ACAB:RebuildStanceBarContainer()
	self:EnsureDB()

	-- Styled mode: this native rebuild must not run - see
	-- CreateStanceBarContainer's own guard above for why.
	if not self:IsStanceBarNativeModeEffective() then
		return
	end

	-- Vanilla's own ShapeshiftBar_Update() also runs off this same
	-- UPDATE_SHAPESHIFT_FORMS event and re-Shows ShapeshiftBarFrame - see
	-- HideShapeshiftBarFrame's own comment above.
	HideShapeshiftBarFrame()

	local buttons = self:GetStanceBarButtons()

	if not buttons then
		-- A class that had forms and lost every one of them (rare, but
		-- possible via a talent respec) - hide rather than destroy the
		-- container, since it may become active again later this session.
		if self.stanceBarContainer then
			self.stanceBarContainer:Hide()
			self.stanceBarContainer.chainButtons = {}
			self.stanceBarContainer.chainWidths = {}
			self.stanceBarContainer.chainHeights = {}
		end

		return
	end

	local container = self.stanceBarContainer

	if not container then
		self:CreateStanceBarContainer()
		return
	end

	local widths, heights = {}, {}
	local i

	for i = 1, table.getn(buttons) do
		if buttons[i]:GetParent() ~= container then
			buttons[i]:SetParent(container)
		end

		widths[i] = buttons[i]:GetWidth() or 36
		heights[i] = buttons[i]:GetHeight() or 36
	end

	container.chainButtons = buttons
	container.chainWidths = widths
	container.chainHeights = heights

	self.stanceBarButtons = buttons

	self:ApplyStanceBarShape()
	self:ApplyStanceBarBorderStyle()

	if ACABDB.stanceBarEnabled ~= false then
		container:Show()
	end
end

-- Applies ACABDB.stanceBarPosition to the container, and ensures its
-- drag/right-click overlay exists - mirrors ApplyBagBarPosition exactly.
function ACAB:ApplyStanceBarPosition()
	local pos = ACABDB.stanceBarPosition
	local container = self.stanceBarContainer

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

	self:EnsureContainerOverlay(container, self.StartStanceBarDrag, self.StopStanceBarDrag, self.STANCE_BAR_ID, self.SetStanceBarScale, nil, "Stance Bar")

	-- Same cfg the custom-styled Stance Bar's grid reads, so toggling display mode preserves the hover preference.
	local cfg = ACABDB.defaultBars[self.STANCE_BAR_ID]

	if cfg then
		self:ApplyHoverOnlyState(container, cfg.hoverOnly, function() return cfg.hoverDuration or 3 end)
	end
end

-- Settings.lua's Stance Bar page X/Y sliders write through this.
function ACAB:SetStanceBarPosition(x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB.stanceBarPosition then
		return
	end

	ACABDB.stanceBarPosition.x = x
	ACABDB.stanceBarPosition.y = y

	-- User is now positioning this element by hand - stop auto-stacking its Y off Bar 2/Extra Bar 1.
	ACABDB.stanceBarUsesDefaultPosition = false

	self:ApplyStanceBarPosition()
end

-- Settings.lua's Stance Bar page "Reset to Vanilla Layout" button.
function ACAB:ResetStanceBarPosition()
	local native = ACABDB.stanceBarNativeAnchor

	if not native then
		return
	end

	ACABDB.stanceBarPosition = {
		point = native.point,
		relativePoint = native.relativePoint,
		x = native.x,
		y = native.y,
	}

	-- Prefer the computed baseline over the raw captured nativeAnchor - mirrors ResetPetBarNativeLayout.
	local bar2Cfg = ACABDB.defaultBars[2]
	local computedY = self:GetStanceBarBaselineY(bar2Cfg and bar2Cfg.enabled)

	if computedY then
		ACABDB.stanceBarPosition.y = computedY
	end

	ACABDB.stanceBarUsesDefaultPosition = true

	self:ApplyStanceBarPosition()
end

-- Settings.lua's Stance Bar page "Reset to Modern Layout Default" button.
-- Native mode: positions Stance Bar directly above Action Bar 2 (bar 3), left edges aligned, reading
-- bar 3's real rendered edge rather than a buttonSize*N formula.
-- Styled mode is handled entirely differently, in ResetStanceBarShapeToModernBase below - a vertical
-- grid to the left of Main Bar, not above Action Bar 2.
function ACAB:ResetStanceBarPositionToModernBase()
	self:EnsureDB()

	if not self:IsStanceBarNativeModeEffective() then
		self:ResetStanceBarShapeToModernBase()
		return
	end

	-- Built on demand, same mode-switched-mid-session gap as ResetPetBarLayoutToModernBase.
	self:CreateStanceBarContainer()

	local bar3 = self.bars and self.bars[3]
	local container = self.stanceBarContainer

	if not bar3 or not container then
		return
	end

	-- Layout first, same reason as Pet Bar's own reset above - settle scale before repositioning.
	ACABDB.stanceBarScale = self:GetModernPetStanceScale()
	self:ApplyStanceBarShape()

	local bar3Left, _, bar3Top = self:GetElementRealEdges(bar3)

	if not bar3Left then
		return
	end

	ACABDB.stanceBarPosition = {
		point = "BOTTOMLEFT",
		relativePoint = "BOTTOMLEFT",
		x = self:ConvertUIParentOffsetToOwnScale(container, bar3Left),
		-- Same 6px row gap Pet Bar's own reset above keeps between Action Bar 2 and the Stance/Pet Bar row.
		y = self:ConvertUIParentOffsetToOwnScale(container, bar3Top + 6),
	}

	ACABDB.stanceBarUsesDefaultPosition = false

	self:ApplyStanceBarPosition()
end

-- Styled-mode-only half of ResetStanceBarPositionToModernBase above - Stance Bar becomes a vertical
-- grid (1 col) immediately to Main Bar's left, zero gap, bottom edge matching Main Bar's bottom edge
-- (not stacked above Action Bar 2 like native mode). Styled buttons respect cfg.buttonSize directly,
-- so no scale-compensation trick is needed.
function ACAB:ResetStanceBarShapeToModernBase()
	self:EnsureDB()

	-- Built on demand, same first-login-boots-native gap as EnsureFixedSlotBarCreated elsewhere.
	self:EnsureFixedSlotBarCreated(self.STANCE_BAR_ID)

	local mainBar = self.bars and self.bars[1]
	local stanceBar = self.bars and self.bars[self.STANCE_BAR_ID]

	if not mainBar or not stanceBar then
		return
	end

	local mainBarLeft, _, _, mainBarBottom = self:GetElementRealEdges(mainBar)

	if not mainBarLeft then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local cfg = stanceBar.config

	-- Vertical grid - one button per available stance/form; falls back to the existing row count (or 4)
	-- if the live count can't be read.
	local rows = (GetNumShapeshiftForms and GetNumShapeshiftForms()) or 0

	if rows < 1 then
		rows = cfg.rows or 4
	end

	cfg.buttonSize = buttonSize
	cfg.spacing = spacing
	cfg.cols = 1
	cfg.rows = rows
	cfg.buttonCount = rows

	local _, insetRight, _, insetBottom = self:GetElementVisualInset(stanceBar)

	cfg.point = "BOTTOMLEFT"
	cfg.relativePoint = "BOTTOMLEFT"
	cfg.x = mainBarLeft - insetRight - buttonSize
	cfg.y = mainBarBottom + insetBottom

	self:ApplyBarPosition(stanceBar)
	self:SetBarLayout(stanceBar, cfg.cols, cfg.rows)
	self:SetBarButtonSize(stanceBar, buttonSize)
	self:ApplyBarShape(stanceBar)
end

-- Settings.lua's Stance Bar page enable checkbox. The container's own Show()/Hide() cascades to every
-- real child stance button, same as SetBagBarEnabled/SetMicroMenuEnabled.
function ACAB:SetStanceBarEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.stanceBarEnabled = enabled

	if self.stanceBarContainer then
		if enabled then
			self.stanceBarContainer:Show()
		else
			self.stanceBarContainer:Hide()

			-- Same explicit-hide requirement as SetBagBarEnabled above.
			if self.stanceBarContainer.ACABOverlay then
				self.stanceBarContainer.ACABOverlay:Hide()
				self.stanceBarContainer.ACABOverlay:EnableMouse(false)
			end
		end
	end
end

-- Computes the absolute Stance Bar top-edge Y for a given bar-2 enabled state, computed fresh from
-- live-captured native baselines every time - never derived from ACABDB.stanceBarPosition.y.
-- baselineY = referenceBar.top + gap + height (height read live so this stays correct if the user
-- scales the Stance Bar). referenceY is bar 2's nativeAnchor.y if bar 2 is enabled, else bar 1's.
function ACAB:GetStanceBarBaselineY(bar2Enabled)
	local defaults = ACABDB and ACABDB.defaultBars
	local cfg1 = defaults and defaults[1]
	local cfg2 = defaults and defaults[2]

	local referenceY = cfg1 and cfg1.nativeAnchor and cfg1.nativeAnchor.y

	if bar2Enabled and cfg2 and cfg2.nativeAnchor then
		referenceY = cfg2.nativeAnchor.y

		-- Extra Bar 1 sits above Bar 2 - stack Stance Bar above it too when both are enabled.
		referenceY = referenceY + self:GetExtraBarStackPitch(self.EXTRA_BAR_ID_START)
	end

	if not referenceY then
		return nil
	end

	local container = self.stanceBarContainer

	if not container then
		return nil
	end

	-- Same fixed clearance Pet Bar uses (PET_BAR_NATIVE_GAP) rather than the smaller captured
	-- stanceBarNativeGap - the real captured gap sat the Stance Bar too low.
	return referenceY + self.PET_BAR_NATIVE_GAP + container:GetHeight()
end

-- Replicates real vanilla's ShapeshiftBar_UpdatePosition side effect against the Stance Bar's own
-- synthetic container, since the native call against the real ShapeshiftBarFrame no longer does
-- anything post-migration. Always an absolute, self-correcting recompute (pos.y overwritten fresh, so
-- this never accumulates drift). Only called while useDefaultLayout ~= false and
-- ACABDB.stanceBarUsesDefaultPosition is true, or this fights the user's own manual positioning.
function ACAB:ReflowStanceBarForBar2Toggle(bar2Enabled)
	if ACABDB.stanceBarUsesDefaultPosition == false then
		return
	end

	local pos = ACABDB.stanceBarPosition
	local container = self.stanceBarContainer

	if not pos or not container then
		return
	end

	local y = self:GetStanceBarBaselineY(bar2Enabled)

	if not y then
		return
	end

	pos.y = y

	self:ApplyStanceBarPosition()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(self.STANCE_BAR_ID)
	end
end

-- Re-lays-out the Stance Bar's real buttons from its current saved spacing/orientation/scale - mirrors
-- ApplyBagBarShape. No-op until CreateStanceBarContainer has built the container.
function ACAB:ApplyStanceBarShape()
	self:EnsureDB()

	self:ApplyChainAnchoredShape(
		self.stanceBarContainer,
		ACABDB.stanceBarSpacing or 0,
		ACABDB.stanceBarOrientation == true,
		ACABDB.stanceBarScale or 1
	)
end

-- Applies the current global border style to the Stance Bar's real ShapeshiftButtonN frames - mirrors
-- Button.lua's ApplyBorderStyle against a real Blizzard button. Vanilla mode leaves the native
-- NormalTexture alone; modern mode hides it and draws the flat dark-backdrop/inset-icon look.
-- Do NOT draw the backdrop via btn:SetBackdrop() directly - on this native template it renders above
-- ShapeshiftButtonNIcon, washing the icon out grey. Uses a separate child frame at a lower FrameLevel instead.
function ACAB:ApplyStanceBarBorderStyle()
	local buttons = self.stanceBarButtons

	if not buttons then
		return
	end

	local vanilla = self:IsVanillaBorderStyle()
	local i

	for i = 1, table.getn(buttons) do
		local btn = buttons[i]

		if btn then
			local name = btn:GetName()
			local icon = name and getglobal(name .. "Icon")
			local normalTex = btn:GetNormalTexture()

			-- One-time cleanup for a button that already picked up the old btn:SetBackdrop() treatment.
			if btn.ACABBackdropApplied then
				btn:SetBackdrop(nil)
				btn.ACABBackdropApplied = nil
			end

			if vanilla then
				if normalTex then
					normalTex:Show()
				end

				if icon then
					icon:ClearAllPoints()
					icon:SetAllPoints(btn)
				end

				if btn.ACABModernBackdrop then
					btn.ACABModernBackdrop:Hide()
				end
			else
				if normalTex then
					normalTex:Hide()
				end

				if icon then
					icon:ClearAllPoints()
					icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
					icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
				end

				if not btn.ACABModernBackdrop then
					local backdrop = CreateFrame("Frame", nil, btn:GetParent())

					backdrop:SetFrameStrata(btn:GetFrameStrata())
					backdrop:SetFrameLevel(math.max((btn:GetFrameLevel() or 1) - 1, 0))
					backdrop:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
					backdrop:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
					backdrop:SetBackdrop({
						bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
						edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
						tile = true,
						tileSize = 8,
						edgeSize = 8,
						insets = { left = 1, right = 1, top = 1, bottom = 1 },
					})
					backdrop:SetBackdropColor(0, 0, 0, 0.75)
					backdrop:SetBackdropBorderColor(1, 1, 1, 1)

					btn.ACABModernBackdrop = backdrop
				end

				btn.ACABModernBackdrop:Show()
			end
		end
	end
end

-- Mirrors SetPetBarNativeSpacing's clamp/write/reapply template - plain 0 to 20, same as Pet Bar.
-- No vanilla-border-style floor: the border never actually overlaps at spacing 0 in either style.
function ACAB:SetStanceBarSpacing(spacing)
	self:EnsureDB()

	spacing = self:ClampSpacingSetting(spacing, 0, 20)

	if not spacing then
		return
	end

	ACABDB.stanceBarSpacing = spacing

	self:ApplyStanceBarShape()
end

-- Mirrors SetBagBarScale's clamp/write/reapply template.
function ACAB:SetStanceBarScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	local oldScale = ACABDB.stanceBarScale or 1
	local pos = ACABDB.stanceBarPosition

	if pos and self.stanceBarContainer then
		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, "BOTTOMLEFT", nil, self.stanceBarContainer:GetHeight())
	end

	ACABDB.stanceBarScale = scale

	self:ApplyStanceBarShape()

	if pos then
		self:ApplyStanceBarPosition()
	end
end

-- Orientation is a plain boolean toggle (true = vertical/swapped) - mirrors SetBagBarOrientation.
function ACAB:SetStanceBarOrientation(vertical)
	self:EnsureDB()

	ACABDB.stanceBarOrientation = vertical and true or false

	self:ApplyStanceBarShape()
end

-- Settings.lua's Stance Bar native page "Only show on hover" checkbox/slider - writes the same cfg.hoverOnly/cfg.hoverDuration fields the styled grid uses.
function ACAB:SetStanceBarNativeHoverOnly(enabled)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.STANCE_BAR_ID]

	if not cfg then
		return
	end

	cfg.hoverOnly = enabled and true or false

	self:ApplyStanceBarPosition()
end

function ACAB:SetStanceBarNativeHoverDuration(duration)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.STANCE_BAR_ID]

	duration = self:ClampHoverDuration(duration)

	if not cfg or not duration then
		return
	end

	cfg.hoverDuration = duration

	self:ApplyStanceBarPosition()
end

-- Settings.lua's Stance Bar page reset flow calls this alongside ResetStanceBarPosition - restores
-- spacing/scale/orientation to their native baseline, mirroring ResetBagBarLayout.
function ACAB:ResetStanceBarLayout()
	self:EnsureDB()

	self:SetStanceBarSpacing(ACABDB.stanceBarNativeSpacing or 0)
	ACABDB.stanceBarScale = 1
	ACABDB.stanceBarOrientation = false

	self:ApplyStanceBarShape()
end

function ACAB:StartStanceBarDrag()
	local pos = ACABDB.stanceBarPosition

	if not pos then
		return
	end

	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = "stanceBar"
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = pos.x or 0
	frame.dragStartY = pos.y or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopStanceBarDrag()
	self:StopSharedDrag()

	-- User just moved this element by hand - stop auto-stacking its Y.
	ACABDB.stanceBarUsesDefaultPosition = false

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(self.STANCE_BAR_ID)
	end
end

-------------------------------------------------------------------------
-- Stance bar buttons
-- GetNumShapeshiftForms() is the authoritative source for how many ShapeshiftButton# frames are
-- "active" - not :IsShown(), which isn't reliable before the native stance bar has ever been touched.
-- Returns 0 for a class with no stance/form mechanic.
-------------------------------------------------------------------------

-- Returns an ordered table of the currently-active real Blizzard stance button frames, capped at
-- MAX_STANCE_BUTTONS, or nil if there are none right now.
function ACAB:GetStanceBarButtons()
	local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0

	if not count or count <= 0 then
		return nil
	end

	if count > self.MAX_STANCE_BUTTONS then
		count = self.MAX_STANCE_BUTTONS
	end

	local buttons = {}
	local i

	for i = 1, count do
		local frame = getglobal("ShapeshiftButton" .. tostring(i))

		if not frame then
			-- Missing frames beyond this point aren't collected (same tolerance as GetDefaultBarButtons).
			break
		end

		buttons[i] = frame
	end

	if table.getn(buttons) == 0 then
		return nil
	end

	return buttons
end

