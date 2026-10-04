-- ElementEngine.lua
-- Shared machinery for native-wrapped elements: grid-index/pixel helpers, the cursor-tracking drag engine,
-- the chain/grid-anchored container engine, InstallReanchorGuard/InstallShowGuard, and the single-frame
-- element helpers. Must load before DefaultBars.lua and NativeElements.lua: both make top-level guard calls.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Grid-index math and pixel-snapped positioning helpers
-------------------------------------------------------------------------

-- 1-based button index -> 0-based col, row (shared with Bar.lua's LayoutButtons).
function ACAB:ButtonIndexToGridPos(index, cols)
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

-- Pixel-snapped re-anchor of `frame` to UIParent from a saved position table (canonical or legacy).
-- guardFlag (optional) is the frame's InstallReanchorGuard flag, set around the call so it isn't swallowed.
function ACAB:ApplySavedPosition(frame, pos, guardFlag)
	self:ApplyPositionToFrame(frame, pos, "BOTTOMLEFT", nil, nil, guardFlag)
end

-------------------------------------------------------------------------
-------------------------------------------------------------------------
-- Shared cursor-tracking drag engine (Edit Layout mode)
-- One OnUpdate drives every drag kind: bars via Bar.lua's StartBarDrag ("bar"), native elements via their
-- own Start*Drag. Edit-mode overlays sit above the real buttons, so native OnDragStart never fires.
-------------------------------------------------------------------------

-- Created lazily once; only one drag can run at a time.
local dragFrame

-- Cursor position in UIParent units.
function ACAB:GetCursorPositionUIScale()
	local scale = UIParent:GetEffectiveScale()
	local x, y = GetCursorPosition()
	return x / scale, y / scale
end

-- Per-tick snap for every drag kind: nudges pos.x/pos.y in place (any UIParent-relative anchor) toward
-- adjacent elements, else the grid; no-op while nothing snaps or the frame has no size/scale yet.
-- centerSnap (Cast Bar) uses ComputeCenterGridSnapAdjustment instead of ComputeGridSnapAdjustment.
function ACAB:ApplyDragSnap(frame, pos, centerSnap)
	if not frame or not pos then return end

	local scale = frame:GetEffectiveScale()
	local width = frame:GetWidth()
	local height = frame:GetHeight()
	if not scale or not width or not height then return end

	local topLeftPos = self:GetPositionInAnchor(frame, pos, "TOPLEFT", "BOTTOMLEFT")

	-- Inflates the box by its visual inset (vanilla-style bar borders) so snapping compares border edges;
	-- deflated again before writing to pos.
	local il, ir, it, ib = ACAB:GetElementVisualInset(frame)
	local ilPx, irPx, itPx, ibPx = il * scale, ir * scale, it * scale, ib * scale

	local proposedLeft = topLeftPos.x * scale - ilPx
	local proposedTop = topLeftPos.y * scale + itPx

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
	if not adjustedLeft and not adjustedTop then return end

	if adjustedLeft then
		topLeftPos.x = (adjustedLeft + ilPx) / scale
	end

	if adjustedTop then
		topLeftPos.y = (adjustedTop - itPx) / scale
	end

	if self:IsCanonicalPosition(pos) then
		self:ConvertPositionToCanonical(frame, topLeftPos)
	else
		self:ConvertPositionAnchor(frame, topLeftPos, pos.point or "TOPLEFT", pos.relativePoint or "BOTTOMLEFT")
	end

	pos.x = topLeftPos.x
	pos.y = topLeftPos.y
end

-- Drag kinds that move a saved position table: getPos() -> table whose x/y are written, getFrame() ->
-- frame snapped against, apply = ACAB method re-anchoring it, centerSnap = ApplyDragSnap's flag.
local POSITION_DRAG_KINDS = {
	stanceBar = {
		getPos = function() return ACABDB.stanceBarPosition end,
		getFrame = function() return ACAB.stanceBarContainer end,
		apply = "ApplyStanceBarPosition",
	},
	bagBar = {
		getPos = function() return ACABDB.bagBarPosition end,
		getFrame = function() return ACAB.bagBarContainer end,
		apply = "ApplyBagBarPosition",
	},
	microMenu = {
		getPos = function() return ACABDB.microMenuPosition end,
		getFrame = function() return ACAB.microMenuContainer end,
		apply = "ApplyMicroMenuPosition",
	},
	keyRing = {
		getPos = function() return ACABDB.keyRingPosition end,
		getFrame = function() return getglobal(ACAB.KEYRING_BUTTON_NAME) end,
		apply = "ApplyKeyRingPosition",
	},
	latencyBar = {
		getPos = function() return ACABDB.latencyBarPosition end,
		getFrame = function() return getglobal(ACAB.LATENCY_BAR_FRAME_NAME) end,
		apply = "ApplyLatencyBarPosition",
	},
	expBar = {
		getPos = function() return ACABDB.expBarPosition end,
		getFrame = function() return getglobal(ACAB.EXP_BAR_FRAME_NAME) end,
		apply = "ApplyExpBarPosition",
	},
	castBar = {
		getPos = function() return ACABDB.castBarPosition end,
		getFrame = function() return getglobal(ACAB.CAST_BAR_FRAME_NAME) end,
		apply = "ApplyCastBarPosition",
		centerSnap = true,
	},
	pageIndicator = {
		getPos = function() return ACABDB.mainBarPageIndicatorPosition end,
		getFrame = function() return ACAB.pageIndicatorContainer end,
		apply = "ApplyPageIndicatorPosition",
	},
	tooltip = {
		getPos = function() return ACABDB.tooltipPosition end,
		getFrame = function() return ACAB.tooltipFrame end,
		apply = "ApplyTooltipPosition",
	},
	-- Native Pet Bar writes the shared defaultBars[PET_BAR_ID] cfg, so styled mode keeps the same x/y.
	petBarNative = {
		getPos = function() return ACABDB.defaultBars[ACAB.PET_BAR_ID] end,
		getFrame = function() return ACAB.petBarNativeContainer end,
		apply = "ApplyPetBarNativePosition",
	},
}

-- Shared OnUpdate body for every drag kind - `this` is dragFrame (engine-invoked handler).
function ACAB:DefaultBarDrag_OnUpdate()
	local cx, cy = ACAB:GetCursorPositionUIScale()
	local dx = cx - this.dragStartCursorX
	local dy = cy - this.dragStartCursorY
	local kind = POSITION_DRAG_KINDS[this.dragKind]

	if kind then
		local pos = kind.getPos()

		if pos then
			pos.x = this.dragStartX + dx
			pos.y = this.dragStartY + dy

			ACAB:ApplyDragSnap(kind.getFrame(), pos, kind.centerSnap)

			ACAB[kind.apply](ACAB)
		end
	elseif this.dragKind == "bar" then
		-- Bars 1-9 (position on bar.config). ApplyBarPosition only - ApplyBarShape would re-bind every slot per tick.
		local bar = ACAB.bars and ACAB.bars[this.dragId]

		if bar and bar.config then
			local pos = {
				point = bar.config.point or "TOPLEFT",
				relativePoint = bar.config.relativePoint or "TOPLEFT",
				visualCenter = bar.config.visualCenter,
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
-- Start/stop seam onto the shared drag frame (Bar.lua's StartBarDrag/StopBarDrag use it too).
-------------------------------------------------------------------------

-- Starts tracking the cursor for dragKind from saved position startX/startY.
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
	if not dragFrame then return end

	dragFrame:SetScript("OnUpdate", nil)
	dragFrame:Hide()
end

-- True only while Edit Layout mode is on AND useDefaultLayout == false - the shared drag gate.
function ACAB:CanDragDefaultLayout()
	return self:IsEditMode() and ACABDB and ACABDB.useDefaultLayout == false
end

-------------------------------------------------------------------------
-- Chain/grid-anchored container engine (Bag Bar, Micro Menu, Stance Bar, native Pet Bar)
-- Elements without a native container get a synthetic one with their real buttons reparented into it,
-- chained button-to-button (Bartender2's pattern). Element-specific code lives in NativeElements/PetStanceBars.lua.
-------------------------------------------------------------------------

-- Bag Bar's 5 real bag buttons (Key Ring excluded) and Micro Menu's 8 real micro buttons.

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

	if n == 0 then return nil end

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

-- Rounded median gap between consecutive native buttons (negative gaps count as 0) - seeds nativeSpacing.
local function ComputeMedianGap(lefts, widths)
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

	table.sort(gaps)

	local median

	-- Even count: average of the two middle values.
	if n - (math.floor(n / 2) * 2) == 0 then
		local lo = gaps[n / 2]
		local hi = gaps[(n / 2) + 1]
		median = (lo + hi) / 2
	else
		median = gaps[math.floor((n + 1) / 2)]
	end

	return math.floor(median + 0.5)
end

-- Builds a HIGH-strata container (above MainMenuBarArtFrame's art) and reparents `buttons` (sorted left-to-right)
-- into it; layout itself is ApplyChainAnchoredShape/ApplyGridAnchoredShape.
-- Returns container, button 1's native left/top in UIParent units, and the chain's median native gap.
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
	container:SetFrameStrata("LOW")
	container:SetFrameLevel(10)

	for i = 1, table.getn(buttons) do
		buttons[i]:SetParent(container)
	end

	-- Cached for later re-layouts; the real buttons are never resized individually, only the container scales.
	container.chainButtons = buttons
	container.chainWidths = widths
	container.chainHeights = heights

	local nativeSpacing = ComputeMedianGap(lefts, widths)

	-- Button 1's corner from its own effective-scale units into UIParent units (as CaptureNativeAnchor does).
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

-- frame's GetHitRectInsets() (left, right, top, bottom trim of its visible area, e.g. Micro Menu's 58px
-- frame with 40px of content), or zeros for frames without the API.
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

-- Anchors overlay from first's TOPLEFT to last's BOTTOMRIGHT, trimmed by their hit-rect insets plus
-- container.overlayTopFudge, in overlay units. clearPoints clears the overlay's old anchors first.
local function AnchorOverlayToChainEndpoints(overlay, container, first, last, clearPoints)
	local firstLeft, _, firstTop = ACAB:GetHitInsets(first)
	local _, lastRight, _, lastBottom = ACAB:GetHitInsets(last)
	local firstRatio = ACAB:ScaleRatio(first, overlay)
	local lastRatio = ACAB:ScaleRatio(last, overlay)
	local topFudge = container.overlayTopFudge or 0

	if clearPoints then
		overlay:ClearAllPoints()
	end

	overlay:SetPoint("TOPLEFT", first, "TOPLEFT", firstLeft * firstRatio, -(firstTop + topFudge) * firstRatio)
	overlay:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", -lastRight * lastRatio, lastBottom * lastRatio)
end

-- Call before writing a changed scale: adjusts pos.x/pos.y so `corner` (TOPLEFT/TOPRIGHT/BOTTOMLEFT/
-- BOTTOMRIGHT) stays exactly where it was on screen (a SetPoint offset scales with the frame's own scale).
-- `localWidth`/`localHeight` are the frame's design size. "CENTER" keeps a canonical position unchanged.
function ACAB:CompensateScaleKeepingCornerFixed(pos, oldScale, newScale, corner, localWidth, localHeight)
	if not pos or not oldScale or not newScale then return end

	if oldScale == newScale or oldScale <= 0 or newScale <= 0 then return end

	local ratio = oldScale / newScale
	localWidth = localWidth or 0
	localHeight = localHeight or 0

	-- Canonical x/y is the element's center in UIParent units - shift it by the corner's size change.
	if self:IsCanonicalPosition(pos) then
		local cornerFx, cornerFy = self:GetPointFractions(corner)

		pos.x = (pos.x or 0) + ((cornerFx - 0.5) * localWidth * (oldScale - newScale))
		pos.y = (pos.y or 0) + ((cornerFy - 0.5) * localHeight * (oldScale - newScale))
		return
	end

	local cornerFx, cornerFy = self:GetPointFractions(corner)
	local pointFx, pointFy = self:GetPointFractions(pos.point or "TOPLEFT")

	local offsetX = (cornerFx - pointFx) * localWidth
	local offsetY = (cornerFy - pointFy) * localHeight

	pos.x = ((pos.x or 0) + offsetX) * ratio - offsetX
	pos.y = ((pos.y or 0) + offsetY) * ratio - offsetY
end

-- Re-chains a container's shown buttons (hidden ones reserve no slot) `spacing` apart between visible edges,
-- horizontally or (orientation truthy) vertically, then sizes/scales the container and re-anchors its overlay.
-- forceAllShown (native Pet Bar, condense off) chains all 10 slots regardless of IsShown().
function ACAB:ApplyChainAnchoredShape(container, spacing, orientation, scale, forceAllShown)
	if not container or not container.chainButtons then return end

	local buttons = container.chainButtons
	local widths = container.chainWidths
	local heights = container.chainHeights

	-- InstallReanchorGuard's flag (if installed on these buttons) - lets our own re-anchors through.
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
		-- Every button hidden: collapse the container rather than keep its last size.
		self:PixelSetSize(container, 1, 1)
		container:SetScale(scale or 1)
		container.chainVisualInsets = nil

		if container.ACABOverlay then
			container.ACABOverlay:ClearAllPoints()
			container.ACABOverlay:SetAllPoints(container)
		end

		return
	end

	-- Must stay untrimmed: saved positions were captured against `first`'s raw frame corner (only the overlay trims).
	if guardFlag then first[guardFlag] = true end
	first:ClearAllPoints()
	self:PixelSetPoint(first, "TOPLEFT", container, "TOPLEFT", 0, 0)
	if guardFlag then first[guardFlag] = nil end

	-- Main-axis seed is `first`'s raw size; cross-axis seed is its visible (hit-rect-trimmed) size.
	local firstLeftSeed, firstRightSeed, firstTopSeed, firstBottomSeed = self:GetHitInsets(first)

	local totalWidth = widths[firstIndex] or 0
	local totalHeight = heights[firstIndex] or 0

	if orientation then
		totalWidth = totalWidth - firstLeftSeed - firstRightSeed
	else
		totalHeight = totalHeight - firstTopSeed - firstBottomSeed
	end

	local prevBtn = first
	local lastIndex = firstIndex

	for i = firstIndex + 1, table.getn(buttons) do
		local btn = buttons[i]

		if btn then
			if forceAllShown or btn:IsShown() then
				lastIndex = i

				local w = widths[i] or 0
				local h = heights[i] or 0

				local _, prevRight, _, prevBottom = self:GetHitInsets(prevBtn)
				local btnLeft, btnRight, btnTop, btnBottom = self:GetHitInsets(btn)

				if guardFlag then btn[guardFlag] = true end
				btn:ClearAllPoints()

				-- Offsets between visible edges (frame edge + hit-rect inset), so `spacing` is the visible gap.
				if orientation then
					self:PixelSetPoint(btn, "TOPLEFT", prevBtn, "BOTTOMLEFT", 0, prevBottom - spacing + btnTop)

					totalHeight = totalHeight + spacing + h - prevBottom - btnTop

					local visibleW = w - btnLeft - btnRight

					if visibleW > totalWidth then
						totalWidth = visibleW
					end
				else
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
				-- Hidden: parked on the last visible button's TOPLEFT instead of a stale anchor.
				if guardFlag then btn[guardFlag] = true end
				btn:ClearAllPoints()
				self:PixelSetPoint(btn, "TOPLEFT", prevBtn, "TOPLEFT", 0, 0)
				if guardFlag then btn[guardFlag] = nil end
			end
		end
	end

	-- Container size trims only the trailing edge, so its TOPLEFT origin never moves.
	do
		local _, prevRight, _, prevBottom = self:GetHitInsets(prevBtn)

		if orientation then
			totalHeight = totalHeight - prevBottom
		else
			totalWidth = totalWidth - prevRight
		end
	end

	self:PixelSetSize(container, totalWidth, totalHeight)
	container:SetScale(scale or 1)

	-- Overlay edges' distance inside the container (container units), same trims as the overlay below.
	do
		local firstLeft, _, firstTop = self:GetHitInsets(first)
		local _, lastRight, _, lastBottom = self:GetHitInsets(prevBtn)
		local insets = {
			left = firstLeft,
			top = firstTop + (container.overlayTopFudge or 0),
			right = 0,
			bottom = 0,
		}

		if orientation then
			insets.right = totalWidth - ((widths[lastIndex] or 0) - lastRight)
		else
			insets.bottom = totalHeight - ((heights[lastIndex] or 0) - lastBottom)
		end

		container.chainVisualInsets = insets
	end

	-- Overlay is fully trimmed on every side (prevBtn = last shown button).
	if container.ACABOverlay then
		AnchorOverlayToChainEndpoints(container.ACABOverlay, container, first, prevBtn, true)
	end
end

-- Micro Menu's fixed cols x rows grid: shown buttons fill cells in order (a hidden one, e.g. TalentMicroButton
-- below level 10, reserves no cell). Re-run by the UpdateMicroButtons hook.
function ACAB:ApplyGridAnchoredShape(container, cols, rows, spacing, scale)
	if not container or not container.chainButtons then return end

	local buttons = container.chainButtons
	local widths = container.chainWidths
	local heights = container.chainHeights

	spacing = spacing or 0

	-- Uniform cell = largest button per axis; the largest hit-rect insets make the pitch visible-edge-to-edge.
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
			-- InstallReanchorGuard flag - lets our own ClearAllPoints through.
			buttons[i].ACABApplyingMicroMenuPosition = true
			buttons[i]:ClearAllPoints()
			buttons[i].ACABApplyingMicroMenuPosition = nil
		end
	end

	-- Includes the overlay's extra top trim so row pitch matches the overlay's visible button edge.
	local rowTopInset = topInset + (container.overlayTopFudge or 0)

	local colStep = cellWidth - leftInset - rightInset + spacing
	local rowStep = cellHeight - rowTopInset - bottomInset + spacing

	for i = 1, shownCount do
		local col, row = self:ButtonIndexToGridPos(i, cols)
		local xOff = col * colStep
		local yOff = -row * rowStep

		shown[i].ACABApplyingMicroMenuPosition = true
		shown[i]:ClearAllPoints()
		self:PixelSetPoint(shown[i], "TOPLEFT", container, "TOPLEFT", xOff, yOff)
		shown[i].ACABApplyingMicroMenuPosition = nil
	end

	local totalWidth = cellWidth + ((cols - 1) * colStep) - rightInset
	local totalHeight = cellHeight + ((rows - 1) * rowStep) - bottomInset

	self:PixelSetSize(container, totalWidth, totalHeight)
	container:SetScale(scale or 1)

	-- Overlay edges' distance inside the container (container units), same trims as the overlay below.
	container.chainVisualInsets = nil

	if shownCount > 0 then
		local first = shown[1]
		local last = shown[shownCount]
		local firstLeft, _, firstTop = self:GetHitInsets(first)
		local _, lastRight, _, lastBottom = self:GetHitInsets(last)
		local lastCol, lastRow = self:ButtonIndexToGridPos(shownCount, cols)

		container.chainVisualInsets = {
			left = firstLeft,
			top = firstTop + (container.overlayTopFudge or 0),
			right = totalWidth - ((lastCol * colStep) + (last:GetWidth() or cellWidth) - lastRight),
			bottom = totalHeight - ((lastRow * rowStep) + (last:GetHeight() or cellHeight) - lastBottom),
		}
	end

	if container.ACABOverlay then
		local first = shown[1]
		local last = shown[shownCount]

		if first and last then
			AnchorOverlayToChainEndpoints(container.ACABOverlay, container, first, last, true)
		end
	end
end

-- Creates container's edit-mode overlay once: TOOLTIP-strata drag surface, right-click -> settingsKey's page,
-- wheel -> scaleSetFn(+-0.1), optional name label; level defaults to 100 (overlapping overlays need distinct levels).
-- Parented to UIParent, not `container`: hiding the element doesn't hide its overlay - callers hide it explicitly.
function ACAB:EnsureContainerOverlay(container, startDragFn, stopDragFn, settingsKey, scaleSetFn, level, displayName, forceAllShown)
	if container.ACABOverlay then
		return container.ACABOverlay
	end

	local overlay = CreateFrame("Frame", nil, UIParent)

	overlay:SetFrameStrata("TOOLTIP")
	overlay:SetFrameLevel(level or 100)

	-- Chain containers: first/last shown button, trimmed (re-applied by the shape passes). Others: the container,
	-- trimmed by its fixed overlayInset if it has one.
	local chainFirst, chainLast = self:GetChainShownEndpoints(container, forceAllShown)

	if chainFirst and chainLast then
		AnchorOverlayToChainEndpoints(overlay, container, chainFirst, chainLast, false)
	elseif container.overlayInset then
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

	-- Hover border + centered name label, as in Bar.lua's EnsureBarOverlay.
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

	-- Scroll-to-scale, only while the overlay is mouse-enabled (same gate as dragging).
	overlay:EnableMouseWheel(true)
	overlay:SetScript("OnMouseWheel", function()
		if not scaleSetFn then return end

		if not overlay:IsMouseEnabled() then return end

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

-- Shows + mouse-enables container's overlay while `show` and its element's enabledFlag ~= false, else hides it.
function ACAB:ApplyContainerOverlayVisual(container, enabledFlag, show)
	if not container or not container.ACABOverlay then return end

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

-- Swallows SetPoint/ClearAllPoints on `frame` unless frame[flagName] is set (by our own Apply*Position).
-- Must stay - native code re-anchors these frames without clearing old points, corrupting their position.
-- Each swallowed SetPoint is recorded in frame.ACABSwallowedAnchor (polled by Core.lua's WaitForWrappedFrameAnchorSettle).
function ACAB:InstallReanchorGuard(frame, flagName)
	if not frame or frame.ACABReanchorGuarded then return end

	local nativeSetPoint = frame.SetPoint
	local nativeClearAllPoints = frame.ClearAllPoints

	frame.SetPoint = function(self, ...)
		if self[flagName] then
			return nativeSetPoint(self, unpack(arg))
		end

		-- relativeTo may be a frame or a name string - must check string first (indexing a string errors here).
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

-- Applies a relative anchor (GetPoint(1) snapshot) to `frame` and returns its resulting TOPLEFT as a
-- UIParent-relative TOPLEFT/BOTTOMLEFT position table, or nil.
-- guardFlagName must be passed for frames with an InstallReanchorGuard, or this SetPoint is swallowed.
function ACAB:ResolveNativeAnchorToAbsolute(frame, native, guardFlagName)
	if not frame then return nil end

	-- The anchor native code last tried to set (InstallReanchorGuard) wins over the passed snapshot.
	native = frame.ACABSwallowedAnchor or native

	if not native then return nil end

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
	if not left or not top then return nil end

	return {
		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = left,
		y = top,
	}
end

-- Swallows Show() on `frame` unless isEnabledFn() returns true.
function ACAB:InstallShowGuard(frame, isEnabledFn)
	if not frame or frame.ACABShowGuarded then return end

	local nativeShow = frame.Show

	frame.Show = function(self)
		if isEnabledFn() then
			return nativeShow(self)
		end
	end

	frame.ACABShowGuarded = true
end

-------------------------------------------------------------------------
-- Single-frame element helpers shared by NativeElements/PetStanceBars/ExperienceBar.lua
-------------------------------------------------------------------------

-- Shows or hides an element; its edit-mode overlay is parented to UIParent, so it's hidden explicitly.
function ACAB:SetElementShown(frame, shown)
	if not frame then return end

	if shown then
		frame:Show()
	else
		frame:Hide()

		if frame.ACABOverlay then
			frame.ACABOverlay:Hide()
			frame.ACABOverlay:EnableMouse(false)
		end
	end
end

-- Writes numeric x/y into the saved position ACABDB[field]. Returns false if nothing was written.
function ACAB:WriteSavedPositionXY(field, x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB[field] then return false end

	ACABDB[field].x = x
	ACABDB[field].y = y

	return true
end

-- Clamps and stores ACABDB[scaleField], keeping frame's center fixed. Returns clamped scale (nil if invalid), pos.
function ACAB:StoreCompensatedScale(scaleField, posField, frame, scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then return nil end

	local oldScale = ACABDB[scaleField] or 1
	local pos = ACABDB[posField]

	if pos and frame then
		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, "CENTER", frame:GetWidth(), frame:GetHeight())
	end

	ACABDB[scaleField] = scale

	return scale, pos
end

-- Resets scale to 1 and returns native resolved to absolute. Must bypass Set*Scale, whose compensation inflates it.
function ACAB:ResetScaleAndResolveNative(frame, scaleField, native, guardFlag)
	ACABDB[scaleField] = 1

	if frame then
		frame:SetScale(1)
	end

	return self:ResolveNativeAnchorToAbsolute(frame, native, guardFlag)
end

-- frame's GetPoint(1) anchor as a saved table (relativeTo by name, UIParent if unnamed), or nil if incomplete.
function ACAB:ReadNativeAnchor(frame)
	local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
	if not (point and relativePoint and x and y) then return nil end

	local relativeToName = "UIParent"

	if relativeTo and relativeTo.GetName and relativeTo:GetName() then
		relativeToName = relativeTo:GetName()
	end

	return {
		point = point,
		relativeTo = relativeToName,
		relativePoint = relativePoint,
		x = x,
		y = y,
	}
end

-- Seeds ACABDB[nativeField] and ACABDB[posField] (each only if unset) with a TOPLEFT/BOTTOMLEFT absolute position.
function ACAB:SeedNativePosition(nativeField, posField, x, y)
	if not ACABDB[nativeField] then
		ACABDB[nativeField] = {
			point = "TOPLEFT",
			relativePoint = "BOTTOMLEFT",
			x = x,
			y = y,
		}
	end

	if not ACABDB[posField] then
		ACABDB[posField] = {
			point = "TOPLEFT",
			relativePoint = "BOTTOMLEFT",
			x = x,
			y = y,
		}
	end
end

-- Fresh position table copied from a saved native anchor's point/relativePoint/x/y.
function ACAB:CopyNativePosition(native)
	return {
		point = native.point,
		relativePoint = native.relativePoint,
		x = native.x,
		y = native.y,
	}
end
