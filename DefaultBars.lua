-- DefaultBars.lua
-- Owns bars 1-5 (wraps Blizzard's MainMenuBar/MultiBar* frames; repositions/reflows/resizes/shows-hides only, never touches action-slot bindings).
-- Also owns the shared chain/grid-anchored container + drag engine used by NativeElements.lua/PetStanceBars.lua/ExperienceBar.lua.
-- Must load before those 3 files - they call these functions at file-load time, or login throws "attempt to call nil value".

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Frame name mapping for the 5 default action bars (12 buttons each,
-- numbered 1-12), centralized here since exact FrameXML names aren't
-- guaranteed on this client fork.
-------------------------------------------------------------------------

ACAB.DEFAULT_BAR_FRAME_PREFIXES = {
	[1] = "ActionButton",             -- Main bar (MainMenuBar).
	[2] = "MultiBarBottomLeftButton", -- Bottom Left.
	[3] = "MultiBarBottomRightButton",-- Bottom Right.
	[4] = "MultiBarRightButton",      -- Right.
	[5] = "MultiBarLeftButton",       -- Right 2.
	[ACAB.PET_BAR_ID] = "PetActionButton", -- Pet Bar (only 10 real frames).
	[ACAB.STANCE_BAR_ID] = "ShapeshiftButton", -- Stance Bar, styled mode: hide+neuter and anchor capture only.
}

-- Real vanilla stance bars top out at 10 slots (ShapeshiftButton1-10).
ACAB.MAX_STANCE_BUTTONS = 10

-- Returns ordered table of real Blizzard button frames for a default bar id, or nil if unknown/not yet loaded.
function ACAB:GetDefaultBarButtons(id)
	local prefix = self.DEFAULT_BAR_FRAME_PREFIXES[id]

	if not prefix then
		return nil
	end

	local buttons = {}
	local i

	for i = 1, self.MAX_BAR_BUTTONS do
		local frame = getglobal(prefix .. tostring(i))

		if not frame then
			-- Stops collecting rather than producing a sparse table.
			break
		end

		buttons[i] = frame
	end

	if table.getn(buttons) == 0 then
		return nil
	end

	return buttons
end

-------------------------------------------------------------------------
-- Default bars (1-5) dynamic content-source redirect
-- Buttons resolve their action slot from the effective page (GetDefaultBarEffectivePage);
-- paging: actionSlot = buttonID + (page-1)*12, bonus bar offset maps to page 6+offset.
-- Bars 2-5 redirect page/stance signal to an assigned Extra Bar instead (GetDefaultBarSlotForIndex).
-------------------------------------------------------------------------

-- Page every default bar's buttons currently read from. Pagination toggle locks to page 1; stance-swap only applies on page 1.
function ACAB:GetDefaultBarEffectivePage()
	self:EnsureDB()

	local page = 1

	if ACABDB.defaultBarPaginationEnabled ~= false then
		page = CURRENT_ACTIONBAR_PAGE or 1
	end

	if ACABDB.defaultBarStanceSwapEnabled ~= false and page == 1 then
		local offset = GetBonusBarOffset and GetBonusBarOffset() or 0

		if offset and offset > 0 then
			page = 6 + offset
		end
	end

	return page
end

-- Resolves which of the player's stance slots is currently active (GetBonusBarOffset alone isn't a 1:1 mapping to stance index).
function ACAB:GetActiveStanceIndex()
	local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0

	if not count or count <= 0 then
		return nil
	end

	local i

	for i = 1, count do
		local icon, name, isActive = GetShapeshiftFormInfo(i)

		if isActive then
			return i
		end
	end

	return nil
end

-- Resolves the action slot for pool button `slotIndex` of default bar `id`
-- (1-5) on the effective page. Per stance index (page == 1 or page 7-9) or
-- page-bar (any other page):
--   nil (No Pageswap) -> static slot, never redirects.
--   -1  (Default)     -> vanilla paging math (bar 1 only; same as static
--                         for bars 2-5, which have none of their own).
--   Extra Bar id      -> that bar's live slot, else static slot.
-- page == 1 with no stance active (or stance-swap disabled) uses the static slot.
function ACAB:GetDefaultBarSlotForIndex(id, slotIndex)
	local page = self:GetDefaultBarEffectivePage()

	local function StaticSlot()
		if id == 1 then
			return slotIndex
		end

		local cfg = ACABDB.defaultBars[id]

		return cfg and cfg.fixedActionSlots and cfg.fixedActionSlots[slotIndex]
	end

	-- Bars 2-5 have no native page/stance-swap math - "Default" equals
	-- "No Pageswap" for them.
	local function VanillaDefaultSlot()
		if id == 1 then
			return slotIndex + ((page - 1) * 12)
		end

		return StaticSlot()
	end

	local assignedId

	if page == 1 or (page >= 7 and page <= 9) then
		-- GetActiveStanceIndex, not the page number, is the real signal a stance/form is active.
		-- Vanilla only grants a bonus-bar page (page 7-9) to forms with extra spells (e.g. Bear/Cat) -
		-- page stays 1 for forms without one (e.g. Travel/Aquatic Form) even while shapeshifted, so
		-- page == 1 must still check for an active stance rather than assuming "no stance".
		local stanceIndex = nil

		if ACABDB.defaultBarStanceSwapEnabled ~= false then
			stanceIndex = self:GetActiveStanceIndex()
		end

		assignedId = stanceIndex
			and ACABDB.defaultBarStanceBarAssignment
			and ACABDB.defaultBarStanceBarAssignment[id]
			and ACABDB.defaultBarStanceBarAssignment[id][stanceIndex]
	else
		assignedId = ACABDB.defaultBarPageBarAssignment
			and ACABDB.defaultBarPageBarAssignment[id]
	end

	if assignedId == nil then
		return StaticSlot()
	elseif assignedId == -1 then
		return VanillaDefaultSlot()
	end

	local slot = self:GetExtraBarSlotForIndex(assignedId, slotIndex)

	if slot then
		return slot
	end

	return StaticSlot()
end

-- Re-resolves every default bar's pool button slots from current page/bonus-bar state.
function ACAB:RefreshDefaultBarSlots()
	local id

	for id = 1, 5 do
		local bar = self.bars and self.bars[id]

		if bar then
			self:ApplyBarShape(bar)
		end
	end
end

-- Written by Settings.lua General tab checkboxes; only changes which action slots buttons read from, not visibility.
function ACAB:SetDefaultBarPaginationEnabled(enabled)
	self:EnsureDB()

	ACABDB.defaultBarPaginationEnabled = enabled and true or false

	self:RefreshDefaultBarSlots()

	-- Page Indicator visibility derives from this toggle (bar-1-only).
	if self.ApplyPageIndicatorVisibility then
		self:ApplyPageIndicatorVisibility()
	end
end

function ACAB:SetDefaultBarStanceSwapEnabled(enabled)
	self:EnsureDB()

	ACABDB.defaultBarStanceSwapEnabled = enabled and true or false

	self:RefreshDefaultBarSlots()
end

-- Hooks vanilla's ChangeActionBarPage so RefreshDefaultBarSlots reruns after CURRENT_ACTIONBAR_PAGE updates.
if hooksecurefunc and ChangeActionBarPage then
	hooksecurefunc("ChangeActionBarPage", function()
		ACAB:RefreshDefaultBarSlots()
	end)
end

-- BonusActionBarFrame is a separate overlay frame shown on stance/bonus-bar changes; hidden+neutered unconditionally.
function ACAB:HideBonusActionBarFrame()
	self:NeuterFrameShow(BonusActionBarFrame)
end

-------------------------------------------------------------------------
-- "Disable Blizzard Art" (General tab checkbox)
--
-- Hides/shows MainMenuBarArtFrame's own regions (GetRegions(), not the
-- frame itself - that would take ActionButton1-12, its real children,
-- down with it) so bar 1's replica buttons show against the user's UI.
--
-- MainMenuBarArtFrame stays pinned at strata "MEDIUM" level 5 regardless
-- of the checkbox - must stay strictly between MainMenuExpBar's level 2
-- (XP bar fill would bleed past the art) and ACAB bars' level 10
-- (bars would render behind the art). Do not change without
-- re-verifying both those frames' levels.
--
-- Bars 2-5 have no equivalent art frame in vanilla FrameXML.
function ACAB:ApplyBlizzardArtVisibility()
	local artFrame = MainMenuBarArtFrame

	if not artFrame then
		return
	end

	self:EnsureDB()

	artFrame:SetFrameStrata("MEDIUM")
	artFrame:SetFrameLevel(5)

	local hide = ACABDB.disableBlizzardArt

	local regions = { artFrame:GetRegions() }
	local i

	for i = 1, table.getn(regions) do
		local region = regions[i]

		if region and region.GetObjectType and region:GetObjectType() == "Texture" then
			if hide then
				region:Hide()
			else
				region:Show()
			end
		end
	end
end

-------------------------------------------------------------------------
-- Position + grid reflow: mirrors Bar.lua's ButtonIndexToGridPos math for real Blizzard frames.
-------------------------------------------------------------------------

local function ButtonIndexToGridPos(index, cols)
	local i = index - 1
	local row = math.floor(i / cols)
	local col = i - (row * cols)
	return col, row
end

-- Falls back to plain SetPoint when region/relativeTo lacks GetEffectiveScale (FontString/Texture regions).
function ACAB:PixelSetPoint(region, ...)
	local relativeTo = arg[2]
	local canPixelSnap = region and region.GetEffectiveScale
		and (not relativeTo or relativeTo.GetEffectiveScale)

	if PixelUtil and PixelUtil.SetPoint and canPixelSnap then
		PixelUtil.SetPoint(region, unpack(arg))
	else
		region:SetPoint(unpack(arg))
	end
end

function ACAB:PixelSetSize(region, width, height)
	if PixelUtil and PixelUtil.SetSize then
		PixelUtil.SetSize(region, width, height)
	else
		region:SetWidth(width)
		region:SetHeight(height)
	end
end

-- Bars 1-5 share Bar.lua's EnsureBarOverlay for edit-mode overlay; Stance Bar uses the chain-anchored-container technique instead (see below).

-- Positions and grid-reflows default bar `id`'s real buttons per its saved config, via Bar.lua's ApplyBarPosition/ApplyBarShape.
function ACAB:ApplyDefaultBarShape(id)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg then
		return
	end

	local bar = self.bars and self.bars[id]

	if bar then
		self:ApplyBarPosition(bar)
		self:ApplyBarShape(bar)
	end
end

-- Resizes default bar `id`'s real buttons via Bar.lua's SetBarButtonSize.
function ACAB:SetDefaultBarButtonSize(id, size)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg then
		return
	end

	local bar = self.bars and self.bars[id]

	if bar then
		self:SetBarButtonSize(bar, size)
	end
end

-- Spacing slider equivalent of SetDefaultBarButtonSize; writes cfg.spacing then reapplies via ApplyBarShape.
function ACAB:SetDefaultBarSpacing(id, spacing)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg then
		return
	end

	-- Vanilla-only minimum spacing clamp, mirrors Bar.lua's SetBarSpacing.
	local minSpacing = self:IsVanillaBorderStyle() and self.VANILLA_SPACING_FLOOR or 0

	spacing = self:ClampSpacingSetting(spacing, minSpacing, 20)

	if not spacing then
		return
	end

	cfg.spacing = spacing

	local bar = self.bars and self.bars[id]

	if bar then
		self:ApplyBarShape(bar)
	end

	-- Vanilla-style grid spacing includes Main Bar's configured spacing, not just buttonSize (Core.lua GetLayoutGridSpacing).
	if id == 1 and self:IsEditMode() then
		self:RebuildLayoutGrid()
	end
end

-------------------------------------------------------------------------
-- Position (live). Default bars move via x/y only - dragging unsupported (real Blizzard frames, not ACAB's own).
-------------------------------------------------------------------------

-- Delegates to Bar.lua's own SetBarPosition.
function ACAB:SetDefaultBarPosition(id, x, y)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg then
		return
	end

	local bar = self.bars and self.bars[id]

	if bar then
		self:SetBarPosition(bar, x, y)
	end
end

-------------------------------------------------------------------------
-- Reset to Vanilla Layout (position, spacing, grid shape, size)
-- Restores position/spacing from cfg.nativeAnchor/nativeSpacing (pristine snapshot from Core.lua's seedDefaultBars).
-- Grid shape/button size restore from ACAB.DEFAULT_BAR_GRID/BUTTON_SIZE constants.
-------------------------------------------------------------------------

-- Restores position/grid shape/button size for default bar `id` via Bar.lua's Apply/Set functions.
function ACAB:ResetDefaultBarLayout(id)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg or not cfg.nativeAnchor then
		return
	end

	cfg.point = cfg.nativeAnchor.point
	cfg.relativePoint = cfg.nativeAnchor.relativePoint
	cfg.x = cfg.nativeAnchor.x
	cfg.y = cfg.nativeAnchor.y

	local grid = self.DEFAULT_BAR_GRID[id]

	local bar = self.bars and self.bars[id]

	if not bar then
		return
	end

	if cfg.nativeSpacing then
		cfg.spacing = cfg.nativeSpacing
	end

	self:ApplyBarPosition(bar)

	if grid then
		self:SetBarLayout(bar, grid.cols, grid.rows)
	end

	self:SetBarButtonSize(bar, self.BUTTON_SIZE)

	-- Ensures restored spacing applies even if SetBarLayout was skipped.
	self:ApplyBarShape(bar)
end

-------------------------------------------------------------------------
-- Modern Layout geometry - live sequential measurement
-- Shared by the Setup Wizard's Modern Layout choice and every "Reset to Modern Layout Default" button.
-- Positions are read off the real rendered edge of the referenced bar (ACAB:GetElementRealEdges) after
-- applying it for real - never computed via a buttonSize*N formula, or border-style insets go stale.
-------------------------------------------------------------------------

-- Effective button size/spacing Modern Layout uses everywhere, via the same global size/spacing overrides every bar respects.
function ACAB:GetModernLayoutSizing()
	self:EnsureDB()

	local buttonSize = (ACABDB.globalButtonSizeEnabled and ACABDB.globalButtonSizeValue) or self.BUTTON_SIZE

	-- Mirrors Bar.lua's ApplyGlobalSpacingToBar formula: vanilla border floor is ADDED to the slider value, not clamped.
	local floor = self:IsVanillaBorderStyle() and self.VANILLA_SPACING_FLOOR or 0
	local spacing = floor + ((ACABDB.globalSpacingEnabled and ACABDB.globalSpacingValue) or 0)

	return buttonSize, spacing
end

-- Pet Bar/Stance Bar's real buttons render at their own native size
-- (~36px) regardless of the Modern Layout buttonSize above - below 36 the
-- native buttons would visibly outsize Action Bar 2's own smaller
-- buttons, so Modern Layout scales them down to 0.9 to compensate; at 36
-- or above they stay at their native 1.0 scale.
function ACAB:GetModernPetStanceScale()
	local buttonSize = self:GetModernLayoutSizing()

	if buttonSize < 36 then
		return 0.9
	end

	return 1
end

-- Height to clear above the Experience Bar for Main Bar's own Y, when it
-- sits at the screen's bottom - reads ACABDB.expBarEnabled/expBarPosition
-- (the stored/intended position), NOT the live MainMenuExpBar frame's
-- CURRENT on-screen spot. During the Setup Wizard's Modern Layout flow
-- this runs before the live frame has actually been moved to match the
-- profile being built (that only happens on the next real login) - but
-- ACABDB.expBarPosition is already correct by the time this runs
-- (SetupWizard.lua's ApplyExpBarWizardState writes it into the target
-- profile before ApplyModernLayoutGeometry does), so reading the stored
-- value works for both the wizard and the standalone "Reset to Modern
-- Layout Default" buttons alike, where it's simply wherever the user last
-- put it.
function ACAB:GetModernBaseExpBarClearance()
	self:EnsureDB()

	if ACABDB.expBarEnabled == false then
		return 0
	end

	local pos = ACABDB.expBarPosition

	-- Same TOPLEFT/BOTTOMLEFT-of-UIParent convention as every other
	-- captured anchor (ACAB:CaptureNativeAnchor) - y is the frame's own
	-- top edge's height above the screen's bottom edge, so under 20px
	-- means it's genuinely sitting at the bottom.
	if not pos or not pos.y or pos.y >= 20 then
		return 0
	end

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)
	local height = (frame and frame:GetHeight()) or 20

	-- Same rowGap Modern Layout's own preset uses between stacked rows.
	return height + 6
end

-- Stacks Main Bar (1) -> Action Bar 1 (2) -> Action Bar 2 (3) with zero gap - each bar's Y is read off
-- the real rendered top edge of the bar below it (ACAB:GetElementRealEdges), not a buttonSize*N formula.
-- Shared by the Setup Wizard's Modern Layout choice and each bar's own "Reset to Modern Layout Default" button.
function ACAB:ApplyModernMainActionBarsLayout()
	self:EnsureDB()

	local bar1 = self.bars and self.bars[1]
	local bar2 = self.bars and self.bars[2]
	local bar3 = self.bars and self.bars[3]

	if not bar1 or not bar2 or not bar3 then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()

	local function PrepareShape(bar)
		bar.config.buttonSize = buttonSize
		bar.config.spacing = spacing
		bar.config.cols = 12
		bar.config.rows = 1
		bar.config.buttonCount = 12
	end

	local function ApplyStackedPosition(bar, y)
		bar.config.point = "BOTTOM"
		bar.config.relativePoint = "BOTTOM"
		bar.config.x = 0
		bar.config.y = y

		self:ApplyBarPosition(bar)
		self:SetBarLayout(bar, bar.config.cols, bar.config.rows)
		self:SetBarButtonSize(bar, bar.config.buttonSize)
		self:ApplyBarShape(bar)
	end

	PrepareShape(bar1)
	ApplyStackedPosition(bar1, 4 + self:GetModernBaseExpBarClearance())

	local _, _, bar1RealTop = self:GetElementRealEdges(bar1)

	PrepareShape(bar2)

	local _, _, _, bar2InsetBottom = self:GetElementVisualInset(bar2)

	ApplyStackedPosition(bar2, (bar1RealTop or 0) + bar2InsetBottom)
	self:SetDefaultBarEnabled(2, true)

	local _, _, bar2RealTop = self:GetElementRealEdges(bar2)

	PrepareShape(bar3)

	local _, _, _, bar3InsetBottom = self:GetElementVisualInset(bar3)

	ApplyStackedPosition(bar3, (bar2RealTop or 0) + bar3InsetBottom)
	self:SetDefaultBarEnabled(3, true)
end

-- The Y that vertically centers a 12-row, 1-col Modern Layout vertical bar on screen.
-- Shared by Right Action Bar 1/2 and Extra Bar 1-4 so the six-bar cluster centers as one row.
function ACAB:GetModernVerticalBarCenteredY(buttonSize, spacing)
	local screenHeight = UIParent:GetHeight() or 0
	local clusterHeight = (buttonSize * 12) + (spacing * 11)

	return (screenHeight - clusterHeight) / 2
end

-- Reshapes an Extra Bar to a 1-col/12-row vertical grid for Modern Layout's vertical clusters, and
-- positions its real edge flush against `anchorRealEdge` (UIParent-relative units).
-- anchorSide "left": `bar` sits left of anchorRealEdge (its right edge touches it). "right": vice versa.
-- Measures the resulting real edge off the bar frame itself after positioning (not the edit-mode overlay,
-- whose rect hasn't resolved yet on this client's lazy frame layout).
-- Returns bar's own resulting real right edge, so the next bar in the same cluster can chain off it.
function ACAB:ApplyModernVerticalExtraBarSlot(bar, buttonSize, spacing, anchorRealEdge, y, anchorSide)
	if not bar or not bar.config then
		return anchorRealEdge
	end

	local cfg = bar.config

	cfg.buttonSize = buttonSize
	cfg.spacing = spacing

	self:SetBarLayout(bar, 1, 12)
	self:SetBarButtonCount(bar, 12)

	local insetLeft, insetRight = self:GetElementVisualInset(bar)

	cfg.point = "BOTTOMLEFT"
	cfg.relativePoint = "BOTTOMLEFT"
	cfg.y = y
	cfg.usesDefaultPosition = false

	if anchorSide == "right" then
		cfg.x = anchorRealEdge + insetLeft
	else
		cfg.x = anchorRealEdge - insetRight - buttonSize
	end

	self:ApplyBarPosition(bar)
	self:SetBarButtonSize(bar, buttonSize)
	self:ApplyBarShape(bar)
	self:SetExtraBarEnabled(cfg.id, true)

	if anchorSide ~= "right" then
		return anchorRealEdge
	end

	local _, realRight = self:GetElementRealEdges(bar)

	return realRight or (cfg.x + buttonSize + insetRight)
end

-- Modern Layout's right/left vertical bar clusters: Right Action Bar 1/2 (id 4/5) plus Extra Bar 1
-- (right cluster, flush against the screen's right edge), mirrored by Extra Bar 2/3/4 (left cluster).
-- id 4 (outermost right) and Extra Bar 2 (outermost left) anchor off UIParent's width; every other
-- bar in each cluster chains zero-gap off the real rendered edge of the bar just outside it.
function ACAB:ApplyModernVerticalBarClusterLayout()
	self:EnsureDB()

	local bar4 = self.bars and self.bars[4]
	local bar5 = self.bars and self.bars[5]

	if not bar4 or not bar5 then
		return
	end

	local extraStart = self.EXTRA_BAR_ID_START
	local extra1 = self.bars[extraStart]
	local extra2 = self.bars[extraStart + 1]
	local extra3 = self.bars[extraStart + 2]
	local extra4 = self.bars[extraStart + 3]

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local cfg5 = bar5.config
	local cfg4 = bar4.config

	cfg5.buttonSize = buttonSize
	cfg5.spacing = spacing
	cfg4.buttonSize = buttonSize
	cfg4.spacing = spacing

	-- Shared row Y for the whole six-bar cluster.
	local rowY = self:GetModernVerticalBarCenteredY(buttonSize, spacing)

	local _, insetRight4 = self:GetElementVisualInset(bar4)

	-- id 4: outermost, flush against the screen's right edge - BOTTOMRIGHT/BOTTOMRIGHT (same as every
	-- other flush-corner element in this file: Bag Bar/Key Ring/Micro Menu/Latency Bar).
	cfg4.point = "BOTTOMRIGHT"
	cfg4.relativePoint = "BOTTOMRIGHT"
	cfg4.x = -insetRight4
	cfg4.y = rowY

	self:ApplyBarPosition(bar4)
	self:SetBarButtonSize(bar4, buttonSize)
	self:SetDefaultBarEnabled(4, true)

	local bar4Left = self:GetElementRealEdges(bar4)
	local _, insetRight5 = self:GetElementVisualInset(bar5)

	-- id 5: immediate left of id 4, zero gap.
	cfg5.point = "BOTTOMLEFT"
	cfg5.relativePoint = "BOTTOMLEFT"
	cfg5.x = (bar4Left or cfg4.x) - insetRight5 - buttonSize
	cfg5.y = rowY

	self:ApplyBarPosition(bar5)
	self:SetBarButtonSize(bar5, buttonSize)
	self:SetDefaultBarEnabled(5, true)

	local bar5Left = self:GetElementRealEdges(bar5)

	if extra1 then
		self:ApplyModernVerticalExtraBarSlot(extra1, buttonSize, spacing, bar5Left or cfg5.x, rowY, "left")
	end

	if extra2 then
		local extra2Right = self:ApplyModernVerticalExtraBarSlot(extra2, buttonSize, spacing, 0, rowY, "right")

		if extra3 then
			local extra3Right = self:ApplyModernVerticalExtraBarSlot(extra3, buttonSize, spacing, extra2Right, rowY, "right")

			if extra4 then
				self:ApplyModernVerticalExtraBarSlot(extra4, buttonSize, spacing, extra3Right, rowY, "right")
			end
		end
	end
end

-- Applies bar 1's own modern position/shape only - independent of Action
-- Bar 1/Action Bar 2, so resetting Main Bar alone never moves them.
function ACAB:ApplyModernSingleMainBar()
	self:EnsureDB()

	local bar1 = self.bars and self.bars[1]

	if not bar1 then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()

	bar1.config.buttonSize = buttonSize
	bar1.config.spacing = spacing
	bar1.config.cols = 12
	bar1.config.rows = 1
	bar1.config.buttonCount = 12
	bar1.config.point = "BOTTOM"
	bar1.config.relativePoint = "BOTTOM"
	bar1.config.x = 0
	bar1.config.y = 4 + self:GetModernBaseExpBarClearance()

	self:ApplyBarPosition(bar1)
	self:SetBarLayout(bar1, 12, 1)
	self:SetBarButtonSize(bar1, buttonSize)
	self:ApplyBarShape(bar1)
end

-- Applies `bar`'s own modern position/shape only, stacked zero-gap above `belowBar`'s current real top
-- edge - never touches belowBar itself, so resetting one bar in the 1-2-3 stack doesn't move its neighbor.
function ACAB:ApplyModernSingleStackedActionBar(bar, belowBar)
	if not bar or not belowBar then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()

	bar.config.buttonSize = buttonSize
	bar.config.spacing = spacing
	bar.config.cols = 12
	bar.config.rows = 1
	bar.config.buttonCount = 12

	local _, _, belowRealTop = self:GetElementRealEdges(belowBar)
	local _, _, _, insetBottom = self:GetElementVisualInset(bar)

	bar.config.point = "BOTTOM"
	bar.config.relativePoint = "BOTTOM"
	bar.config.x = 0
	bar.config.y = (belowRealTop or 0) + insetBottom

	self:ApplyBarPosition(bar)
	self:SetBarLayout(bar, 12, 1)
	self:SetBarButtonSize(bar, buttonSize)
	self:ApplyBarShape(bar)
end

-- Applies bar `id`'s (4 or 5) own modern position/shape only - never moves its neighbor.
-- id 4 is independent (flush against the screen's right edge); id 5 reads id 4's current real left edge.
function ACAB:ApplyModernSingleVerticalBar(id)
	self:EnsureDB()

	local bar = self.bars and self.bars[id]

	if not bar then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local cfg = bar.config

	cfg.buttonSize = buttonSize
	cfg.spacing = spacing
	cfg.y = self:GetModernVerticalBarCenteredY(buttonSize, spacing)

	if id == 4 then
		-- Flush against the screen's right edge - same BOTTOMRIGHT/BOTTOMRIGHT anchor as other flush-corner elements.
		local _, insetRight = self:GetElementVisualInset(bar)

		cfg.point = "BOTTOMRIGHT"
		cfg.relativePoint = "BOTTOMRIGHT"
		cfg.x = -insetRight
	else
		local bar4 = self.bars[4]

		if not bar4 then
			return
		end

		local bar4Left = self:GetElementRealEdges(bar4)
		local _, insetRight = self:GetElementVisualInset(bar)

		cfg.point = "BOTTOMLEFT"
		cfg.relativePoint = "BOTTOMLEFT"
		cfg.x = (bar4Left or cfg.x) - insetRight - buttonSize
	end

	self:ApplyBarPosition(bar)
	self:SetBarButtonSize(bar, buttonSize)
	self:SetDefaultBarEnabled(id, true)
end

-- Settings.lua's "Reset to Modern Layout Default" button for Main Bar/Action Bar 1/Action Bar 2 (id 1-3)
-- and Right Action Bar 1/2 (id 4-5) - each id only ever touches its own bar, never its neighbors.
function ACAB:ResetBarLayoutToModernBase(id)
	self:EnsureDB()

	if id == 1 then
		self:ApplyModernSingleMainBar()
		return
	end

	if id == 2 then
		local bar1 = self.bars and self.bars[1]
		local bar2 = self.bars and self.bars[2]

		if bar1 and bar2 then
			self:ApplyModernSingleStackedActionBar(bar2, bar1)
			self:SetDefaultBarEnabled(2, true)
		end

		return
	end

	if id == 3 then
		local bar2 = self.bars and self.bars[2]
		local bar3 = self.bars and self.bars[3]

		if bar2 and bar3 then
			self:ApplyModernSingleStackedActionBar(bar3, bar2)
			self:SetDefaultBarEnabled(3, true)
		end

		return
	end

	if id == 4 or id == 5 then
		self:ApplyModernSingleVerticalBar(id)
	end
end

-------------------------------------------------------------------------
-- Enable / disable (bars 2-5 only - bar 1 is always active, no UI)
-- Bars 2-5's real Blizzard buttons are permanently hidden regardless of state; cfg.enabled + Show()/Hide()
-- on this addon's own Bar.lua bar frame is the sole visibility mechanism.
-------------------------------------------------------------------------

-- Toggling bar 2 (Bottom Left) also reflows the Stance Bar's position to avoid overlap.
function ACAB:SetDefaultBarEnabled(id, enabled)
	if id == 1 then
		-- Bar 1 (Main) has no enable/disable - always active.
		return
	end

	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg then
		return
	end

	enabled = enabled and true or false

	-- Captured before cfg.enabled is overwritten - Reflow*ForBar*Toggle must
	-- only fire on an actual state change, not every call (e.g.
	-- ApplyAllDefaultBars calls this at login with the already-current value).
	local wasEnabled = cfg.enabled and true or false

	cfg.enabled = enabled

	-- Pet Bar in native mode has no self.bars[id] pool bar - the chain-anchored container is its visibility target instead.
	local bar = self.bars and self.bars[id]
	local isNativePetBar = id == self.PET_BAR_ID and self:IsPetBarNativeModeEffective()

	if isNativePetBar then
		bar = self.petBarNativeContainer
	end

	-- Stance Bar native mode has no self.bars[id] pool bar - `bar` stays nil, a no-op below.
	-- Its native visibility uses ACABDB.stanceBarEnabled instead of cfg.enabled (styled mode only) - do not merge.

	if bar then
		-- Pet Bar additionally requires a real controllable pet action bar right now (PetHasActionBar).
		local shouldShow = enabled

		if enabled and id == self.PET_BAR_ID then
			shouldShow = PetHasActionBar and PetHasActionBar() and true or false
		end

		if shouldShow then
			bar:Show()
		else
			bar:Hide()

			-- Container's overlay is parented to UIParent, not the container - hiding the container doesn't cascade to it.
			if isNativePetBar and bar.ACABOverlay then
				bar.ACABOverlay:Hide()
				bar.ACABOverlay:EnableMouse(false)
			end
		end
	end

	if id == 2 and enabled ~= wasEnabled and ACABDB.useDefaultLayout ~= false then
		self:ReflowStanceBarForBar2Toggle(enabled)
	end

	if id == 3 and enabled ~= wasEnabled and ACABDB.useDefaultLayout ~= false then
		self:ReflowPetBarForBar3Toggle(enabled)
	end

	-- Cast Bar independently stacks above an actually-shown Pet Bar (GetCastBarBaselineY, NativeElements.lua).
	if id == self.PET_BAR_ID and ACABDB.useDefaultLayout ~= false and self.ReflowCastBarForStackToggle then
		self:ReflowCastBarForStackToggle()
	end

	-- Matches native's own dependency (bar 5 requires bar 4) - user can opt out via the General tab.
	if id == 4 then
		if enabled ~= wasEnabled and not enabled and not ACABDB.bypassRightActionBar2Dependency then
			self:SetDefaultBarEnabled(5, false)
		end

		-- Refreshes bar 5's own Settings UI (sidebar + page checkbox) since it locks/unlocks based on bar 4's state.
		if enabled ~= wasEnabled and ACAB:IsSettingsFrameCreated() then
			ACAB:RefreshBarList()
			ACAB:RefreshBarSettingsPage(5)
		end
	end

	-- Mirrors state into the native "Show ... ActionBar" global so the Interface Options checkbox
	-- doesn't look stuck - cfg.enabled above remains the sole visual authority.
	local nativeGlobal = ACAB.SHOW_MULTI_ACTIONBAR_GLOBAL[id]

	if nativeGlobal then
		-- Stored/compared as string "1"/"0" (LOCK_ACTIONBAR convention).
		-- Do NOT call MultiActionBar_Update() here - it gets "Right ActionBar 2" (bar 5) stuck disabled.
		setglobal(nativeGlobal, enabled and "1" or nil)

		-- This options framework only reads the global at panel-show time - set the control directly too.
		local control = getglobal("OptionsFrameCheckButton" .. tostring(id) .. "Control")

		if control and control.SetChecked then
			control:SetChecked(enabled)
		end
	end

	self:FixRightActionBar2Checkbox()
end

-------------------------------------------------------------------------
-- Pet Bar auto-hide (no controllable pet action bar right now)
-- Re-evaluates through SetDefaultBarEnabled above rather than calling bar:Show()/:Hide() directly.
-------------------------------------------------------------------------

function ACAB:RefreshPetBarVisibility()
	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[self.PET_BAR_ID]

	if cfg then
		self:SetDefaultBarEnabled(self.PET_BAR_ID, cfg.enabled)
	end

	-- Re-chain-anchors the real buttons back into our container.
	if self.petBarNativeContainer then
		self:ApplyPetBarNativeShape()
	end
end

-- Reconciles our own cfg.enabled (bars 2-5) from the native SHOW_MULTI_ACTIONBAR_1-4 globals whenever
-- MultiActionBar_Update runs. Only trusted reactively - these globals don't survive a real logout.
function ACAB:ReconcileDefaultBarEnabledFromNative()
	if not (ACABDB and ACABDB.defaultBars) then
		return
	end

	local id

	for id = 2, 5 do
		local nativeGlobal = ACAB.SHOW_MULTI_ACTIONBAR_GLOBAL[id]
		local cfg = ACABDB.defaultBars[id]

		if nativeGlobal and cfg then
			local nativeEnabled = getglobal(nativeGlobal) and true or false
			local currentEnabled = cfg.enabled and true or false

			if nativeEnabled ~= currentEnabled then
				-- Re-enters SetDefaultBarEnabled; harmless one-level no-op re-entry once values match, not a loop.
				self:SetDefaultBarEnabled(id, nativeEnabled)

				-- Keep the Settings window's checkboxes in sync too, if built this session.
				if ACAB:IsSettingsFrameCreated() then
					ACAB:RefreshBarList()
					ACAB:RefreshBarSettingsPage(id)
				end
			end
		end
	end

	self:FixRightActionBar2Checkbox()
end

-- This fork's Options -> Action Bars panel is a custom framework: "Show Right ActionBar 2" (bar 5) gets
-- stuck disabled instead of following "Show Right ActionBar" (bar 4) reactively - mirrored here instead.
local hookedBar4Checkbox = false

-- Enabled label color (1, 0.82, 0) - only forced when enabled; native handles the disabled grey color.
local RIGHT_ACTIONBAR2_LABEL_ENABLED_COLOR = { 1, 0.82, 0 }

local function SetCheckbox5LabelEnabledColor()
	local outer = getglobal("OptionsFrameCheckButton5")

	if not outer then
		return
	end

	local regions = { outer:GetRegions() }
	local i

	for i = 1, table.getn(regions) do
		local r = regions[i]
		local okType, objType = pcall(function() return r.GetObjectType and r:GetObjectType() end)

		if okType and objType == "FontString" then
			r:SetTextColor(
				RIGHT_ACTIONBAR2_LABEL_ENABLED_COLOR[1],
				RIGHT_ACTIONBAR2_LABEL_ENABLED_COLOR[2],
				RIGHT_ACTIONBAR2_LABEL_ENABLED_COLOR[3]
			)
		end
	end
end

function ACAB:FixRightActionBar2Checkbox()
	local control5 = getglobal("OptionsFrameCheckButton5Control")

	if control5 and control5.Enable and control5.Disable then
		local bar4Cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[4]
		local shouldEnable = (ACABDB and ACABDB.bypassRightActionBar2Dependency)
			or (bar4Cfg and bar4Cfg.enabled)

		if shouldEnable then
			control5:Enable()
			SetCheckbox5LabelEnabledColor()
		else
			control5:Disable()
		end
	end

	if not hookedBar4Checkbox then
		local control4 = getglobal("OptionsFrameCheckButton4Control")

		if control4 and control4.HookScript then
			control4:HookScript("OnClick", function()
				ACAB:FixRightActionBar2Checkbox()
			end)

			hookedBar4Checkbox = true
		end
	end
end

-- hooksecurefunc runs after MultiActionBar_Update applies the native checkbox/global state, so the
-- reconcile above always reads the new value.
if hooksecurefunc and MultiActionBar_Update then
	hooksecurefunc("MultiActionBar_Update", function()
		ACAB:ReconcileDefaultBarEnabledFromNative()
	end)
end

-- Every default bar (1-5) delegates to Bar.lua's own SetBarLayout (also re-clamps buttonCount, same as custom bars).
function ACAB:SetDefaultBarLayout(id, cols, rows)
	self:EnsureDB()

	local bar = self.bars and self.bars[id]

	if bar then
		self:SetBarLayout(bar, cols, rows)
	end
end

-------------------------------------------------------------------------
-- Builds every default bar (1-5) as a Bar.lua bar object.
-- Must run once at PLAYER_LOGIN before ApplyAllDefaultBars - every function above reads self.bars[id].
-- Permanently hides each bar's 12 real Blizzard buttons and builds its own Button.lua pool into self.bars[id].
-- If discovery failed for one of bars 2-5, that bar is skipped and keeps its real buttons visible.
-------------------------------------------------------------------------

-- ShapeshiftBar_Update() reads MultiBarBottomLeft:IsShown() to decide whether the Stance Bar can expand
-- its border into that space (50x50 vs 64x64 on an unchanged 30x30 button). Since ACAB permanently hides
-- bar 2's buttons, this parent frame is forced permanently shown to keep it on the compact branch.
local hasNeuteredMultiBarBottomLeft = false

local function ForceShowMultiBarBottomLeft(parent)
	if not parent then
		return
	end

	parent:Show()

	if not hasNeuteredMultiBarBottomLeft then
		parent.Hide = function() end
		hasNeuteredMultiBarBottomLeft = true
	end
end

-- Each real button's Show method is permanently overridden to a no-op once hidden, so a later native
-- call (e.g. ACTIONBAR_SHOWGRID's sweep) can't make it visible again.
-- Creates default-bar `id`'s pool-button bar (self.bars[id]) if not built yet - shared by
-- CreateFixedSlotDefaultBars' login-time loop and PetStanceBars.lua's Reset*ToModernBase functions.
function ACAB:EnsureFixedSlotBarCreated(id)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	-- Pet Bar in native mode skips the pool-button replica - CreatePetBarNativeContainer builds its
	-- own chain-anchored container from the real PetActionButton1-10 frames, which stay clickable.
	if id == self.PET_BAR_ID and cfg and self:IsPetBarNativeModeEffective() then
		return
	elseif id == self.STANCE_BAR_ID and cfg and self:IsStanceBarNativeModeEffective() then
		-- Handled by CreateStanceBarContainer instead.
		return
	end

	if not (cfg and (cfg.fixedActionSlots or cfg.dynamicDefaultBar) and not self.bars[id]) then
		return
	end

	local nativeButtons = self:GetDefaultBarButtons(id)

	if nativeButtons then
		local i

		for i = 1, table.getn(nativeButtons) do
			local btn = nativeButtons[i]

			if btn then
				btn:Hide()
				btn.Show = function() end
			end
		end

		if id == 2 then
			ForceShowMultiBarBottomLeft(nativeButtons[1]:GetParent())

			-- Forces an immediate recompute in case ShapeshiftBar_Update() already ran against the
			-- wrong (hidden) state above, before this fix ran.
			if ShapeshiftBar_Update then
				ShapeshiftBar_Update()
			end
		end
	end

	self.bars[id] = self:CreateBarFromConfig(cfg)

	-- Bar 1 has no cfg.enabled key (always nil), so it must be shown explicitly here.
	if id == 1 or cfg.enabled then
		self.bars[id]:Show()
	else
		self.bars[id]:Hide()
	end
end

function ACAB:CreateFixedSlotDefaultBars()
	self:EnsureDB()

	local i

	for i = 1, table.getn(self.DEFAULT_BAR_IDS) do
		self:EnsureFixedSlotBarCreated(self.DEFAULT_BAR_IDS[i])
	end
end

-------------------------------------------------------------------------
-- Apply all 5 default bars from SavedVariables
-------------------------------------------------------------------------

function ACAB:ApplyAllDefaultBars()
	self:EnsureDB()

	local i

	for i = 1, table.getn(self.DEFAULT_BAR_IDS) do
		local id = self.DEFAULT_BAR_IDS[i]
		local cfg = ACABDB.defaultBars[id]

		if cfg then
			if id ~= 1 then
				-- Bars 2-5: cfg.enabled is the sole visibility source now that their real buttons are permanently hidden.
				self:SetDefaultBarEnabled(id, cfg.enabled)
			end

			-- Always reapply shape/overlay regardless of enabled state - vanilla anchors extra multibars
			-- relative to each other, not UIParent, so a skipped bar needs its own independent overlay.
			self:ApplyDefaultBarShape(id)
		end
	end
end

-------------------------------------------------------------------------
-- Default bar / stance bar dragging (Edit Layout mode,
-- useDefaultLayout == false only)
--
-- Default bars 1-5 drag via Bar.lua's own EnsureBarOverlay/StartBarDrag/
-- StopBarDrag (dragKind == "bar"). The Stance Bar (dragKind == "stanceBar")
-- has no Bar.lua container of its own - it's tracked/repositioned directly
-- through this same shared cursor-tracking OnUpdate mechanism.
-------------------------------------------------------------------------

-- Created lazily, exactly once - shared by every default-bar AND
-- stance-bar drag (only one drag can ever be in progress at a time,
-- since it's driven by mouse button state), so a second frame per drag
-- kind would be redundant.
local dragFrame

-- Dragging is intercepted at the frame-stacking level: Bar.lua's overlay
-- frames sit mouse-enabled in HIGH strata over the real buttons, so the
-- native OnDragStart handler never fires and LOCK_ACTIONBAR is never
-- touched.

function ACAB:GetCursorPositionUIScale()
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	return x / scale, y / scale
end

-- Shared per-tick snap injection for every dragKind below and Bar.lua's
-- own bar drag - nudges pos.x/pos.y in place before the caller applies
-- them. No-ops when the setting is off or the frame can't report a
-- size/scale yet.
--
-- pos.point/pos.relativePoint are always "TOPLEFT"/"BOTTOMLEFT" (every
-- caller normalizes to this pair before dragging), so pos.x/pos.y convert
-- to/from screen pixels via this frame's effective scale alone.
-- centerSnap (Cast Bar only) uses ComputeCenterGridSnapAdjustment instead
-- of ComputeGridSnapAdjustment.
function ACAB:ApplyDragSnap(frame, pos, centerSnap)
	if not frame or not pos then
		return
	end

	local scale = frame:GetEffectiveScale()
	local width = frame:GetWidth()
	local height = frame:GetHeight()

	if not scale or not width or not height then
		return
	end

	-- Inflates the dragged box by its visual inset (Core.lua's GetElementVisualInset, nonzero only for
	-- default bars 1-5) so it compares border-edge-to-border-edge. Deflated back out before writing to pos.
	local il, ir, it, ib = ACAB:GetElementVisualInset(frame)
	local ilPx, irPx, itPx, ibPx = il * scale, ir * scale, it * scale, ib * scale

	local proposedLeft = pos.x * scale - ilPx
	local proposedTop = pos.y * scale + itPx

	local boxWidth = width * scale + ilPx + irPx
	local boxHeight = height * scale + itPx + ibPx

	-- Snap to Adjacent Elements takes priority per axis - Snap to Grid fills in whichever axis is left.
	local adjLeft, adjTop = ACAB:ComputeSnapAdjustment(
		proposedLeft,
		proposedTop,
		boxWidth,
		boxHeight,
		frame
	)

	local gridLeft, gridTop

	if centerSnap then
		gridLeft, gridTop = ACAB:ComputeCenterGridSnapAdjustment(
			proposedLeft,
			proposedTop,
			boxWidth,
			boxHeight,
			scale
		)
	else
		gridLeft, gridTop = ACAB:ComputeGridSnapAdjustment(
			proposedLeft,
			proposedTop,
			boxWidth,
			boxHeight,
			scale
		)
	end

	local adjustedLeft = adjLeft or gridLeft
	local adjustedTop = adjTop or gridTop

	if adjustedLeft then
		pos.x = (adjustedLeft + ilPx) / scale
	end

	if adjustedTop then
		pos.y = (adjustedTop - itPx) / scale
	end
end

-- Shared OnUpdate body for every drag kind - `this` is dragFrame itself (engine-invoked handler).
function ACAB:DefaultBarDrag_OnUpdate()
	local cx, cy = ACAB:GetCursorPositionUIScale()
	local dx = cx - this.dragStartCursorX
	local dy = cy - this.dragStartCursorY

	if this.dragKind == "stanceBar" then
		local pos = ACABDB.stanceBarPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(ACAB.stanceBarContainer, pos)

			ACAB:ApplyStanceBarPosition()
		end
	elseif this.dragKind == "bagBar" then
		local pos = ACABDB.bagBarPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(ACAB.bagBarContainer, pos)

			ACAB:ApplyBagBarPosition()
		end
	elseif this.dragKind == "microMenu" then
		local pos = ACABDB.microMenuPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(ACAB.microMenuContainer, pos)

			ACAB:ApplyMicroMenuPosition()
		end
	elseif this.dragKind == "keyRing" then
		local pos = ACABDB.keyRingPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(getglobal(ACAB.KEYRING_BUTTON_NAME), pos)

			ACAB:ApplyKeyRingPosition()
		end
	elseif this.dragKind == "latencyBar" then
		local pos = ACABDB.latencyBarPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(getglobal(ACAB.LATENCY_BAR_FRAME_NAME), pos)

			ACAB:ApplyLatencyBarPosition()
		end
	elseif this.dragKind == "expBar" then
		local pos = ACABDB.expBarPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(getglobal(ACAB.EXP_BAR_FRAME_NAME), pos)

			ACAB:ApplyExpBarPosition()
		end
	elseif this.dragKind == "castBar" then
		local pos = ACABDB.castBarPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(getglobal(ACAB.CAST_BAR_FRAME_NAME), pos, true)

			ACAB:ApplyCastBarPosition()
		end
	elseif this.dragKind == "pageIndicator" then
		local pos = ACABDB.mainBarPageIndicatorPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(ACAB.pageIndicatorContainer, pos)

			ACAB:ApplyPageIndicatorPosition()
		end
	elseif this.dragKind == "tooltip" then
		local pos = ACABDB.tooltipPosition

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(ACAB.tooltipFrame, pos)

			ACAB:ApplyTooltipPosition()
		end
	elseif this.dragKind == "petBarNative" then
		-- Writes straight into the shared ACABDB.defaultBars[PET_BAR_ID] cfg so position stays in sync
		-- with the custom-styled Pet Bar's own x/y regardless of active mode.
		local cfg = ACABDB.defaultBars[ACAB.PET_BAR_ID]

		if cfg then
			cfg.x = this.dragStartX + dx
			cfg.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(ACAB.petBarNativeContainer, cfg)

			ACAB:ApplyPetBarNativePosition()
		end
	elseif this.dragKind == "bar" then
		-- Bars 1-9: position lives on bar.config.x/y. ApplyBarPosition (not ApplyBarShape) is the
		-- minimal correct call - ApplyBarShape would also re-bind every button's action slot per tick.
		local bar = ACAB.bars and ACAB.bars[this.dragId]

		if bar and bar.config then
			local pos = {
				x = this.dragStartX + dx,
				y = this.dragStartY + dy,
			}

			ACAB:ApplyDragSnap(bar, pos)

			bar.config.x = pos.x
			bar.config.y = pos.y

			ACAB:ApplyBarPosition(bar)
		end
	end
end

function ACAB:EnsureDragFrame()
	if not dragFrame then
		dragFrame = CreateFrame("Frame", "ACABDefaultBarDragFrame", UIParent)
		dragFrame:Hide()
	end

	return dragFrame
end

-------------------------------------------------------------------------
-- Generic start/stop seam onto the shared cursor-tracking drag frame above.
-- Exposed as ACAB methods so Bar.lua's own StartBarDrag/StopBarDrag (bars 1-9) share this mechanism.
-------------------------------------------------------------------------

function ACAB:StartSharedDrag(dragKind, dragId, startX, startY)
	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = dragKind
	frame.dragId = dragId
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = startX or 0
	frame.dragStartY = startY or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopSharedDrag()
	if not dragFrame then
		return
	end

	dragFrame:SetScript("OnUpdate", nil)
	dragFrame:Hide()
end

-- True only while both Edit Layout mode AND useDefaultLayout == false are active - shared gate every
-- default-bar-button/stance-bar drag hook checks before doing anything.
function ACAB:CanDragDefaultLayout()
	return self:IsEditMode() and ACABDB and ACABDB.useDefaultLayout == false
end

-- Stance Bar position/spacing/scale/orientation/enable/drag: see the "Stance Bar (chain-anchored
-- container)" section below, which shares this container/overlay machinery with Bag Bar/Micro Menu/
-- Key Ring/Latency Bar.

-------------------------------------------------------------------------
-- Bag Bar / Micro Menu button-name constants, feeding the shared chain/grid-anchored container engine
-- below. Their own position/shape/enable functions live in NativeElements.lua.
-- Neither element has a single native container frame on real vanilla 1.12.1, so each builds a synthetic
-- container and reparents its real buttons into it, chain-anchored button-to-button (Bartender2's pattern).
-- Bag Bar = the 5 real vanilla bag buttons (no Key Ring). Micro Menu = the 8 real micro-menu buttons.
-------------------------------------------------------------------------

ACAB.BAG_BAR_BUTTON_NAMES = {
	"CharacterBag0Slot",
	"CharacterBag1Slot",
	"CharacterBag2Slot",
	"CharacterBag3Slot",
	"MainMenuBarBackpackButton",
}

ACAB.MICRO_MENU_BUTTON_NAMES = {
	"CharacterMicroButton",
	"SpellbookMicroButton",
	"TalentMicroButton",
	"QuestLogMicroButton",
	"SocialsMicroButton",
	"WorldMapMicroButton",
	"MainMenuMicroButton",
	"HelpMicroButton",
}

-- Resolves a fixed list of real global frame names into an ordered table, skipping any that don't exist.
function ACAB:GetButtonsByName(names)
	local buttons = {}
	local n = 0
	local i

	for i = 1, table.getn(names) do
		local frame = getglobal(names[i])

		if frame then
			n = n + 1
			buttons[n] = frame
		end
	end

	if n == 0 then
		return nil
	end

	return buttons
end

-- Sorts a button list left-to-right by each frame's real on-screen GetLeft() - call before reparenting.
function ACAB:SortButtonsByNativeLeft(buttons)
	table.sort(buttons, function(a, b)
		local aLeft = a:GetLeft() or 0
		local bLeft = b:GetLeft() or 0

		return aLeft < bLeft
	end)
end

-- Computes the per-pair gap across a chain of native button positions/widths, used once at
-- container-build time to seed nativeSpacing. Uses the median of the raw gaps to resist outliers.
local function ComputeMajorityGap(lefts, widths)
	local gaps = {}
	local n = 0
	local i

	for i = 2, table.getn(lefts) do
		local gap = (lefts[i] - lefts[i - 1]) - (widths[i - 1] or 0)

		if gap < 0 then
			gap = 0
		end

		n = n + 1
		gaps[n] = gap
	end

	if n == 0 then
		return 0
	end

	table.sort(gaps, function(a, b) return a < b end)

	local median

	if n - (math.floor(n / 2) * 2) == 0 then
		-- Even count: average the two middle values.
		local lo = gaps[n / 2]
		local hi = gaps[(n / 2) + 1]
		median = (lo + hi) / 2
	else
		median = gaps[math.floor((n + 1) / 2)]
	end

	return math.floor(median + 0.5)
end

-- Builds one synthetic container frame and reparents `buttons` (already sorted left-to-right) into it.
-- Chain-anchoring itself is factored into ApplyChainAnchoredShape below, re-runnable on any shape change.
-- HIGH strata: without it this frame would render behind MainMenuBarArtFrame's background art.
-- Returns the container plus button 1's captured native GetLeft()/GetTop() and the chain's majority
-- native gap - the caller seeds nativeAnchor/nativeSpacing from these before the buttons are reparented.
function ACAB:BuildChainAnchoredContainer(frameName, buttons)
	local lefts, tops, widths, heights = {}, {}, {}, {}
	local i

	for i = 1, table.getn(buttons) do
		lefts[i]   = buttons[i]:GetLeft() or 0
		tops[i]    = buttons[i]:GetTop() or 0
		widths[i]  = buttons[i]:GetWidth() or 36
		heights[i] = buttons[i]:GetHeight() or 36
	end

	local container = CreateFrame("Frame", frameName, UIParent)
	container:SetFrameStrata("HIGH")

	for i = 1, table.getn(buttons) do
		buttons[i]:SetParent(container)
	end

	-- Cached on the container itself so ApplyChainAnchoredShape can
	-- re-lay-out this exact chain later (spacing/orientation/scale
	-- changes) without re-measuring - widths/heights never change after
	-- this point, since these real Blizzard buttons are never
	-- individually resized here, only the container's own SetScale.
	container.chainButtons = buttons
	container.chainWidths = widths
	container.chainHeights = heights

	local nativeSpacing = ComputeMajorityGap(lefts, widths)

	-- button 1's captured lefts[1]/tops[1] are in its own effective-scale
	-- coordinate space, not literal screen pixels (same conversion as
	-- ACAB:CaptureNativeAnchor, Database.lua). Converts through real screen pixels
	-- here so every caller (Bag Bar/Micro Menu/Stance Bar) gets a
	-- consistent nativeX/nativeY.
	local buttonScale = buttons[1]:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()

	local nativeX = lefts[1]
	local nativeY = tops[1]

	if buttonScale and uiParentScale and uiParentScale ~= 0 then
		nativeX = (nativeX * buttonScale) / uiParentScale
		nativeY = (nativeY * buttonScale) / uiParentScale
	end

	return container, nativeX, nativeY, nativeSpacing
end

-- Re-chain-anchors a container's buttons from its current spacing/orientation and applies its current
-- scale - shared by ApplyBagBarShape/ApplyStanceBarShape. Micro Menu uses ApplyGridAnchoredShape instead.
-- horizontal: each button's TOPLEFT anchors to the previous button's TOPRIGHT, offset by `spacing`.
-- vertical: TOPLEFT anchors to the previous button's BOTTOMLEFT, offset downward by `spacing`.
-- Chains only currently-shown buttons (live IsShown() check every call) - a hidden button reserves no slot.

-- Finds the first and last currently-shown button in a chain. Returns first, last (nil if all hidden).
-- forceAllShown treats every button as shown (Pet Bar's native container with condense off).
function ACAB:GetChainShownEndpoints(container, forceAllShown)
	if not container or not container.chainButtons then
		return nil, nil
	end

	local buttons = container.chainButtons
	local first, last
	local i

	for i = 1, table.getn(buttons) do
		if buttons[i] and (forceAllShown or buttons[i]:IsShown()) then
			if not first then
				first = buttons[i]
			end

			last = buttons[i]
		end
	end

	return first, last
end

-- GetHitRectInsets() returns (left, right, top, bottom) trimming a button's clickable/visible area
-- inward from its frame edges (e.g. Micro Menu buttons: 58px frame, but only the bottom 40px is content).
-- Returns 0 for frames without the API.
function ACAB:GetHitInsets(frame)
	if not frame or not frame.GetHitRectInsets then
		return 0, 0, 0, 0
	end

	local left, right, top, bottom = frame:GetHitRectInsets()

	return left or 0, right or 0, top or 0, bottom or 0
end

-- Converts a value from `frame`'s local unit system into `overlay`'s (overlay is parented to UIParent
-- and doesn't track the container's own SetScale).
function ACAB:ScaleRatio(frame, overlay)
	local frameScale = frame and frame.GetEffectiveScale and frame:GetEffectiveScale()
	local overlayScale = overlay and overlay.GetEffectiveScale and overlay:GetEffectiveScale()

	if not frameScale or not overlayScale or overlayScale == 0 then
		return 1
	end

	return frameScale / overlayScale
end

-- Call before writing a changed scale: adjusts pos.x/pos.y so `corner` (TOPLEFT/TOPRIGHT/BOTTOMLEFT/
-- BOTTOMRIGHT) stays exactly where it was on screen (a SetPoint offset scales with the frame's own scale).
-- `localWidth`/`localHeight` are the frame's design size; only needed for a RIGHT/BOTTOM corner respectively.
function ACAB:CompensateScaleKeepingCornerFixed(pos, oldScale, newScale, corner, localWidth, localHeight)
	if not pos or not oldScale or not newScale then
		return
	end

	if oldScale == newScale or oldScale <= 0 or newScale <= 0 then
		return
	end

	local ratio = oldScale / newScale
	localWidth = localWidth or 0
	localHeight = localHeight or 0

	local offsetX = 0
	local offsetY = 0

	if corner == "TOPRIGHT" or corner == "BOTTOMRIGHT" then
		offsetX = localWidth
	end

	if corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT" then
		offsetY = -localHeight
	end

	pos.x = ((pos.x or 0) + offsetX) * ratio - offsetX
	pos.y = ((pos.y or 0) + offsetY) * ratio - offsetY
end

-- forceAllShown (Pet Bar native container, condense off) skips IsShown() checks so all 10 slots stay chained.
function ACAB:ApplyChainAnchoredShape(container, spacing, orientation, scale, forceAllShown)
	if not container or not container.chainButtons then
		return
	end

	local buttons = container.chainButtons
	local widths = container.chainWidths
	local heights = container.chainHeights

	-- Flag consumed by InstallReanchorGuard (when installed on this container's buttons): lets our own
	-- ClearAllPoints/SetPoint calls below through while swallowing native re-anchor attempts.
	local guardFlag = container.reanchorGuardFlag

	spacing = spacing or 0

	local first
	local firstIndex
	local i

	for i = 1, table.getn(buttons) do
		if buttons[i] and (forceAllShown or buttons[i]:IsShown()) then
			first = buttons[i]
			firstIndex = i
			break
		end
	end

	if not first then
		-- Every button in this chain is currently hidden - collapse the container instead of leaving it at its last real size.
		self:PixelSetSize(container, 1, 1)
		container:SetScale(scale or 1)

		if container.ACABOverlay then
			container.ACABOverlay:ClearAllPoints()
			container.ACABOverlay:SetAllPoints(container)
		end

		return
	end

	-- `first`'s frame TOPLEFT must stay at container's TOPLEFT with no hit-rect trim - container's saved
	-- position was captured against `first`'s raw frame corner, so trimming here would shift saved positions.
	-- The overlay below has no such dependency and gets full trimming on every side.
	if guardFlag then first[guardFlag] = true end
	first:ClearAllPoints()
	self:PixelSetPoint(first, "TOPLEFT", container, "TOPLEFT", 0, 0)
	if guardFlag then first[guardFlag] = nil end

	-- Main-axis seed stays `first`'s raw frame size. Cross-axis seed is pre-trimmed by `first`'s own
	-- hit-rect inset, so the loop below can still shrink it if another button's visible size is smaller.
	local firstLeftSeed, firstRightSeed, firstTopSeed, firstBottomSeed = self:GetHitInsets(first)

	local totalWidth = widths[firstIndex] or 0
	local totalHeight = heights[firstIndex] or 0

	if orientation then
		totalWidth = totalWidth - firstLeftSeed - firstRightSeed
	else
		totalHeight = totalHeight - firstTopSeed - firstBottomSeed
	end

	local prevBtn = first

	for i = firstIndex + 1, table.getn(buttons) do
		local btn = buttons[i]

		if btn then
			if forceAllShown or btn:IsShown() then
				local w = widths[i] or 0
				local h = heights[i] or 0

				local prevLeft, prevRight, prevTop, prevBottom = self:GetHitInsets(prevBtn)
				local btnLeft, btnRight, btnTop, btnBottom = self:GetHitInsets(btn)

				if guardFlag then btn[guardFlag] = true end
				btn:ClearAllPoints()

				if orientation then
					-- Offsets by real visible edges (frame edge + hit-rect inset), not raw frame edges,
					-- so `spacing` measures the real visible gap; reduces to bare `-spacing` when insets are 0.
					self:PixelSetPoint(btn, "TOPLEFT", prevBtn, "BOTTOMLEFT", 0, prevBottom - spacing + btnTop)

					totalHeight = totalHeight + spacing + h - prevBottom - btnTop

					local visibleW = w - btnLeft - btnRight

					if visibleW > totalWidth then
						totalWidth = visibleW
					end
				else
					-- Same reasoning, horizontal axis.
					self:PixelSetPoint(btn, "TOPLEFT", prevBtn, "TOPRIGHT", spacing - prevRight - btnLeft, 0)

					totalWidth = totalWidth + spacing + w - prevRight - btnLeft

					local visibleH = h - btnTop - btnBottom

					if visibleH > totalHeight then
						totalHeight = visibleH
					end
				end

				if guardFlag then btn[guardFlag] = nil end

				prevBtn = btn
			else
				-- Hidden - parked at the last visible button's own TOPLEFT (harmless overlap) rather than left on a stale anchor.
				if guardFlag then btn[guardFlag] = true end
				btn:ClearAllPoints()
				self:PixelSetPoint(btn, "TOPLEFT", prevBtn, "TOPLEFT", 0, 0)
				if guardFlag then btn[guardFlag] = nil end
			end
		end
	end

	-- Container's own size trims only the trailing edge - shrinking from the far end never touches
	-- container's TOPLEFT origin, unlike `first`'s own leading inset above.
	do
		local prevLeft, prevRight, prevTop, prevBottom = self:GetHitInsets(prevBtn)

		if orientation then
			totalHeight = totalHeight - prevBottom
		else
			totalWidth = totalWidth - prevRight
		end
	end

	self:PixelSetSize(container, totalWidth, totalHeight)
	container:SetScale(scale or 1)

	-- The overlay has no saved-position dependency, so it gets full trimming: `first`'s leading inset
	-- and `prevBtn`'s (last shown button) trailing inset, re-applied every time this function runs.
	if container.ACABOverlay then
		local firstLeft, firstRight, firstTop, firstBottom = self:GetHitInsets(first)
		local lastLeft, lastRight, lastTop, lastBottom = self:GetHitInsets(prevBtn)
		local firstRatio = self:ScaleRatio(first, container.ACABOverlay)
		local lastRatio = self:ScaleRatio(prevBtn, container.ACABOverlay)
		local topFudge = container.overlayTopFudge or 0

		container.ACABOverlay:ClearAllPoints()
		container.ACABOverlay:SetPoint("TOPLEFT", first, "TOPLEFT", firstLeft * firstRatio, -(firstTop + topFudge) * firstRatio)
		container.ACABOverlay:SetPoint("BOTTOMRIGHT", prevBtn, "BOTTOMRIGHT", -lastRight * lastRatio, lastBottom * lastRatio)
	end
end

-- Fixed-grid layout for Micro Menu only (Bag Bar/Stance Bar use ApplyChainAnchoredShape). cols x rows
-- stays as configured; a hidden button (e.g. TalentMicroButton below level 10) doesn't reserve its cell -
-- shown buttons compact to fill cells in order, leaving leftover cells empty at the end.
-- Re-run by the UpdateMicroButtons hook whenever Blizzard shows/hides a button.
function ACAB:ApplyGridAnchoredShape(container, cols, rows, spacing, scale)
	if not container or not container.chainButtons then
		return
	end

	local buttons = container.chainButtons
	local widths = container.chainWidths
	local heights = container.chainHeights

	spacing = spacing or 0

	-- Uniform cell size (largest button on each axis) plus each axis' hit-rect inset, so row/column
	-- pitch is measured edge-to-edge on real visible content, not raw frame size.
	local cellWidth, cellHeight = 0, 0
	local leftInset, rightInset, topInset, bottomInset = 0, 0, 0, 0
	local shown = {}
	local shownCount = 0
	local i

	for i = 1, table.getn(buttons) do
		if (widths[i] or 0) > cellWidth then
			cellWidth = widths[i]
		end

		if (heights[i] or 0) > cellHeight then
			cellHeight = heights[i]
		end

		local btnLeft, btnRight, btnTop, btnBottom = self:GetHitInsets(buttons[i])

		if btnLeft > leftInset then
			leftInset = btnLeft
		end

		if btnRight > rightInset then
			rightInset = btnRight
		end

		if btnTop > topInset then
			topInset = btnTop
		end

		if btnBottom > bottomInset then
			bottomInset = btnBottom
		end

		if buttons[i]:IsShown() then
			shownCount = shownCount + 1
			shown[shownCount] = buttons[i]
		else
			-- Flag consumed by InstallReanchorGuard: lets our own ClearAllPoints through while swallowing anything else.
			buttons[i].ACABApplyingMicroMenuPosition = true
			buttons[i]:ClearAllPoints()
			buttons[i].ACABApplyingMicroMenuPosition = nil
		end
	end

	-- container.overlayTopFudge (Micro Menu only) is the extra top trim the edit-mode overlay applies
	-- beyond GetHitRectInsets() - folded in here so row pitch matches where the overlay shows the button ending.
	local rowTopInset = topInset + (container.overlayTopFudge or 0)

	local colStep = cellWidth - leftInset - rightInset + spacing
	local rowStep = cellHeight - rowTopInset - bottomInset + spacing

	for i = 1, shownCount do
		local col, row = ButtonIndexToGridPos(i, cols)
		local xOff = col * colStep
		local yOff = -row * rowStep

		-- Same flag as the hidden-button branch above.
		shown[i].ACABApplyingMicroMenuPosition = true
		shown[i]:ClearAllPoints()
		self:PixelSetPoint(shown[i], "TOPLEFT", container, "TOPLEFT", xOff, yOff)
		shown[i].ACABApplyingMicroMenuPosition = nil
	end

	local totalWidth = cellWidth + ((cols - 1) * colStep) - rightInset
	local totalHeight = cellHeight + ((rows - 1) * rowStep) - bottomInset

	self:PixelSetSize(container, totalWidth, totalHeight)
	container:SetScale(scale or 1)

	if container.ACABOverlay then
		local first = shown[1]
		local last = shown[shownCount]

		if first and last then
			local firstLeft, firstRight, firstTop, firstBottom = self:GetHitInsets(first)
			local lastLeft, lastRight, lastTop, lastBottom = self:GetHitInsets(last)
			local firstRatio = self:ScaleRatio(first, container.ACABOverlay)
			local lastRatio = self:ScaleRatio(last, container.ACABOverlay)
			local topFudge = container.overlayTopFudge or 0

			container.ACABOverlay:ClearAllPoints()
			container.ACABOverlay:SetPoint("TOPLEFT", first, "TOPLEFT", firstLeft * firstRatio, -(firstTop + topFudge) * firstRatio)
			container.ACABOverlay:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", -lastRight * lastRatio, lastBottom * lastRatio)
		end
	end
end

-- Shared overlay helper: drag ownership + right-click-to-settings,
-- mirroring Bar.lua's own EnsureBarOverlay (TOOLTIP strata). Takes the
-- container frame, drag start/stop callbacks, the settings-page key for
-- right-click, an optional scroll-to-scale setter, an optional
-- FrameLevel, and forceAllShown (same meaning as ApplyChainAnchoredShape's
-- own parameter).
--
-- scaleSetFn mirrors Button.lua's OnMouseWheel step/delta convention,
-- applied to scale instead of buttonSize.
--
-- level defaults to 100 - same-strata frames aren't reliably ordered by
-- creation order, only by explicit FrameLevel, so overlapping overlays
-- (e.g. Key Ring over Bag Bar) need distinct levels.
--
-- Overlay is parented to UIParent, not `container` - Key Ring/Latency Bar
-- wrap real native frames deep in Blizzard's own ancestor chain, so every
-- sibling overlay needs to compare FrameLevel within the same tree. This
-- means hiding the real frame does NOT cascade to hide its overlay - see
-- SetKeyRingEnabled/SetLatencyBarEnabled for the explicit overlay:Hide()
-- this requires.
function ACAB:EnsureContainerOverlay(container, startDragFn, stopDragFn, settingsKey, scaleSetFn, level, displayName, forceAllShown)
	if container.ACABOverlay then
		return container.ACABOverlay
	end

	local overlay = CreateFrame("Frame", nil, UIParent)

	overlay:SetFrameStrata("TOOLTIP")
	overlay:SetFrameLevel(level or 100)

	-- Chain-anchored containers (chainButtons exists) anchor the overlay
	-- directly to the real first/last currently-shown button instead of
	-- SetAllPoints(container) - see ApplyChainAnchoredShape's matching
	-- anchor below, which re-applies this on every later change. Other
	-- container kinds (Key Ring, Latency Bar, Page Indicator) have no
	-- chainButtons and keep the SetAllPoints(container) anchor.
	local chainFirst, chainLast = self:GetChainShownEndpoints(container, forceAllShown)

	if chainFirst and chainLast then
		-- Trimmed by each endpoint's own hit-rect inset, same formula as
		-- ApplyChainAnchoredShape's own matching overlay anchor below (see
		-- GetHitInsets' comment above for the Micro Menu case). Converted
		-- through ScaleRatio since `overlay` and the buttons don't share an
		-- effective scale once the container's own Scale slider is
		-- anything but 1, plus container.overlayTopFudge (Micro Menu only
		-- - see ACAB.MICRO_MENU_OVERLAY_TOP_FUDGE's comment, Core.lua) for
		-- the small extra sliver GetHitRectInsets alone doesn't cover.
		local firstLeft, firstRight, firstTop, firstBottom = self:GetHitInsets(chainFirst)
		local lastLeft, lastRight, lastTop, lastBottom = self:GetHitInsets(chainLast)
		local firstRatio = self:ScaleRatio(chainFirst, overlay)
		local lastRatio = self:ScaleRatio(chainLast, overlay)
		local topFudge = container.overlayTopFudge or 0

		overlay:SetPoint("TOPLEFT", chainFirst, "TOPLEFT", firstLeft * firstRatio, -(firstTop + topFudge) * firstRatio)
		overlay:SetPoint("BOTTOMRIGHT", chainLast, "BOTTOMRIGHT", -lastRight * lastRatio, lastBottom * lastRatio)
	elseif container.overlayInset then
		-- Trims the overlay in by a fixed per-side amount (Latency Bar
		-- only, container.overlayInset) for a wrapped native frame whose
		-- bounds are bigger than its visible art. Converted through
		-- ScaleRatio so this stays correct at any Scale slider value.
		local inset = container.overlayInset
		local ratio = self:ScaleRatio(container, overlay)

		overlay:SetPoint("TOPLEFT", container, "TOPLEFT", (inset.left or 0) * ratio, -(inset.top or 0) * ratio)
		overlay:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -(inset.right or 0) * ratio, (inset.bottom or 0) * ratio)
	else
		overlay:SetAllPoints(container)
	end

	local tex = overlay:CreateTexture(nil, "OVERLAY")
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetVertexColor(0.35, 0.65, 1.0, 0.45)
	tex:SetAllPoints(overlay)

	-- Hover border + centered element-name label, mirroring Bar.lua's own EnsureBarOverlay.
	-- displayName is passed explicitly since settingsKey doesn't uniquely identify an element.
	overlay:SetBackdrop({
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 8,
	})
	overlay:SetBackdropBorderColor(0, 0, 0, 0)

	overlay:SetScript("OnEnter", function()
		this:SetBackdropBorderColor(0, 0, 0, 1)
	end)
	overlay:SetScript("OnLeave", function()
		this:SetBackdropBorderColor(0, 0, 0, 0)
	end)

	if displayName then
		local nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		nameText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
		nameText:SetText(displayName)
	end

	overlay:RegisterForDrag("LeftButton")
	overlay:SetScript("OnDragStart", function()
		startDragFn(ACAB)
	end)
	overlay:SetScript("OnDragStop", function()
		stopDragFn(ACAB)
	end)

	overlay:SetScript("OnMouseUp", function()
		if arg1 == "RightButton" then
			ACAB:OpenBarSettingsByKey(settingsKey)
		end
	end)

	-- Scroll-to-scale. Gated on the overlay's own mouse-enabled state (set by ApplyContainerOverlayVisual/
	-- ApplyDefaultLayoutEditVisual per element) so drag and scroll always agree on when it's interactive.
	overlay:EnableMouseWheel(true)
	overlay:SetScript("OnMouseWheel", function()
		if not scaleSetFn then
			return
		end

		if not overlay:IsMouseEnabled() then
			return
		end

		local delta = arg1 or 0
		local step = 0.1
		local current = container:GetScale() or 1

		scaleSetFn(ACAB, current + (delta * step))
	end)

	overlay:EnableMouse(false)
	overlay:Hide()

	container.ACABOverlay = overlay

	return overlay
end

-- Shows/hides + toggles mouse on a Bag Bar/Micro Menu overlay - called from ApplyDefaultLayoutEditVisual
-- below. `enabledFlag` is the element's own enable flag; `show` is ACAB:CanDragDefaultLayout()'s result.
function ACAB:ApplyContainerOverlayVisual(container, enabledFlag, show)
	if not container or not container.ACABOverlay then
		return
	end

	local overlay = container.ACABOverlay
	local interactive = show and (enabledFlag ~= false)

	overlay:EnableMouse(interactive and true or false)

	if interactive then
		overlay:Show()

		-- Resets the hover border every time the overlay is (re-)shown.
		overlay:SetBackdropBorderColor(0, 0, 0, 0)
	else
		overlay:Hide()
	end
end

-- Swallows SetPoint/ClearAllPoints on `frame` unless flagged via frame[flagName] (set by the element's
-- own Apply*Position call). Must stay in place - native code re-anchors these frames without clearing
-- the existing point first, corrupting their position.
-- Every swallowed SetPoint attempt is recorded into frame.ACABSwallowedAnchor instead of discarded, since
-- native code can retry repeatedly and the true final anchor can differ from a synchronous GetPoint(1)
-- read at login. Core.lua's WaitForWrappedFrameAnchorSettle polls this field for stability.
function ACAB:InstallReanchorGuard(frame, flagName)
	if not frame or frame.ACABReanchorGuarded then
		return
	end

	local nativeSetPoint = frame.SetPoint
	local nativeClearAllPoints = frame.ClearAllPoints

	frame.SetPoint = function(self, ...)
		if self[flagName] then
			return nativeSetPoint(self, unpack(arg))
		end

		-- arg[2] (relativeTo) may be a real frame reference or a plain string name; indexing a string
		-- with .GetName errors on this client (no string-method metatable), so check the string case first.
		local relTo = arg[2]
		local relName = "UIParent"

		if type(relTo) == "string" then
			relName = relTo
		elseif relTo and relTo.GetName and relTo:GetName() then
			relName = relTo:GetName()
		end

		self.ACABSwallowedAnchor = {
			point = arg[1],
			relativeTo = relName,
			relativePoint = arg[3],
			x = arg[4],
			y = arg[5],
		}
	end

	frame.ClearAllPoints = function(self)
		if self[flagName] then
			return nativeClearAllPoints(self)
		end
	end

	frame.ACABReanchorGuarded = true
end

-- Applies `native` (a relative anchor captured via GetPoint(1)) to `frame`, then re-reads its now-correct
-- GetLeft()/GetTop() to build a normal UIParent-relative absolute anchor table, since the live
-- position/Settings.lua sliders are always UIParent-relative.
-- guardFlagName must be set for elements with an InstallReanchorGuard, or this SetPoint is swallowed.
function ACAB:ResolveNativeAnchorToAbsolute(frame, native, guardFlagName)
	if not frame then
		return nil
	end

	-- Prefer whatever native code most recently tried to re-anchor this frame to (InstallReanchorGuard's
	-- swallow tracking) over the possibly-stale `native` snapshot passed in.
	native = frame.ACABSwallowedAnchor or native

	if not native then
		return nil
	end

	if guardFlagName then
		frame[guardFlagName] = true
	end

	frame:ClearAllPoints()
	self:PixelSetPoint(
		frame,
		native.point or "TOPLEFT",
		getglobal(native.relativeTo or "UIParent") or UIParent,
		native.relativePoint or "BOTTOMLEFT",
		native.x or 0,
		native.y or 0
	)

	if guardFlagName then
		frame[guardFlagName] = nil
	end

	local left, top = frame:GetLeft(), frame:GetTop()

	if not left or not top then
		return nil
	end

	return {
		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = left,
		y = top,
	}
end

-- Swallows Show() on `frame` unless isEnabledFn() returns true.
function ACAB:InstallShowGuard(frame, isEnabledFn)
	if not frame or frame.ACABShowGuarded then
		return
	end

	local nativeShow = frame.Show

	frame.Show = function(self)
		if isEnabledFn() then
			return nativeShow(self)
		end
	end

	frame.ACABShowGuarded = true
end

-------------------------------------------------------------------------
-- Default-layout / stance-bar edit-mode overlay refresh
-- Mirrors Bar.lua's ApplyEditModeVisual, but gated on ACAB:CanDragDefaultLayout() rather than edit mode
-- alone, so a "draggable" cue isn't shown when dragging isn't actually possible.
-------------------------------------------------------------------------

function ACAB:ApplyDefaultLayoutEditVisual()
	local show = self:CanDragDefaultLayout()

	-- Stance Bar/Pet Bar/Cast Bar are draggable in edit mode even on useDefaultLayout == true - their
	-- own baseline reflow still re-asserts Y on the next relevant toggle.
	local showAlwaysEditable = self:IsEditMode()

	-- Default bars 1-5 share Bar.lua's own EnsureBarOverlay/ApplyEditModeVisual; this function only
	-- drives the chain-anchored containers and native-wrapped elements below.

	-- Stance Bar / Bag Bar / Micro Menu are ACAB-owned chain-anchored containers, gated on both
	-- edit-mode/useDefaultLayout (`show`) AND this element's own enable flag.
	self:ApplyContainerOverlayVisual(self.stanceBarContainer, ACABDB.stanceBarEnabled, showAlwaysEditable)
	self:ApplyContainerOverlayVisual(self.bagBarContainer, ACABDB.bagBarEnabled, show)
	self:ApplyContainerOverlayVisual(self.microMenuContainer, ACABDB.microMenuEnabled, show)

	-- Pet Bar native container - gated on the same cfg.enabled the custom-styled mode uses.
	do
		local petCfg = ACABDB.defaultBars and ACABDB.defaultBars[self.PET_BAR_ID]

		self:ApplyContainerOverlayVisual(self.petBarNativeContainer, petCfg and petCfg.enabled, showAlwaysEditable)
	end

	-- Key Ring / Latency Bar / Experience Bar - looked up by name each call, since this only runs on
	-- edit-mode/useDefaultLayout toggles, not per frame.
	self:ApplyContainerOverlayVisual(getglobal(self.KEYRING_BUTTON_NAME), ACABDB.keyRingEnabled, show)
	self:ApplyContainerOverlayVisual(getglobal(self.LATENCY_BAR_FRAME_NAME), ACABDB.latencyBarEnabled, show)
	self:ApplyContainerOverlayVisual(getglobal(self.EXP_BAR_FRAME_NAME), ACABDB.expBarEnabled, show)

	self:ApplyContainerOverlayVisual(getglobal(self.CAST_BAR_FRAME_NAME), true, showAlwaysEditable)

	-- Page Indicator gated on defaultBarPaginationEnabled - this element has no enable flag of its own.
	self:ApplyContainerOverlayVisual(
		self.pageIndicatorContainer,
		ACABDB.defaultBarPaginationEnabled,
		show
	)

	-- Tooltip - independent of action-bar layout mode, same reasoning as Cast Bar above.
	self:ApplyContainerOverlayVisual(self.tooltipFrame, ACABDB.tooltipEnabled, showAlwaysEditable)
end

-------------------------------------------------------------------------
-- Position reassert after combat / looting
-- Latency Bar/Key Ring wrap a single real native frame directly; Bag Bar/Micro Menu/Stance Bar/Page
-- Indicator's buttons are real native frames reparented into our own containers - both groups risk
-- native FrameXML code silently re-anchoring them on its own.
-- Every Apply* call below is idempotent and no-ops if unbuilt. Triggered on PLAYER_REGEN_ENABLED and
-- LOOT_CLOSED. Default bars 1-5 excluded: their real buttons are permanently hidden at login.
-------------------------------------------------------------------------

function ACAB:ReassertNativeElementPositions()
	self:ApplyBagBarPosition()
	self:ApplyBagBarShape()

	self:ApplyMicroMenuPosition()
	self:ApplyMicroMenuShape()

	self:ApplyStanceBarPosition()
	self:ApplyStanceBarShape()

	self:ApplyKeyRingPosition()

	self:ApplyLatencyBarPosition()

	-- Experience Bar: same single-native-frame risk class as Latency Bar/Key Ring above.
	self:ApplyExpBarPosition()

	self:ApplyCastBarPosition()

	self:ApplyPageIndicatorPosition()
	self:ApplyPageIndicatorShape()
end
