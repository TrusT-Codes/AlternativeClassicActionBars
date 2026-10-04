-- PageIndicator.lua
-- Page Indicator: Main Bar's page-turn arrows + page-number FontString in a synthetic container, built inline
-- with plain CreateFrame (not ElementEngine.lua's chain engine).

local ACAB = AlternativeClassicActionBars

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
	if not (l and t and r and b) then return nil end
	return l, t, r, b
end

-- Wraps Up/Down/Text in the container; retries on a timer while Up's rect is unresolved after login.
function ACAB:CreatePageIndicatorContainer()
	self:EnsureDB()

	if self.pageIndicatorContainer then return end

	local up = getglobal(self.PAGE_INDICATOR_UP_NAME)
	local down = getglobal(self.PAGE_INDICATOR_DOWN_NAME)
	local text = getglobal(self.PAGE_INDICATOR_TEXT_NAME)
	if not up or not down or not text then return end

	-- Native anchors, read before any reparenting.
	local upPoint, upRelTo, upRelPoint, upX, upY = up:GetPoint(1)
	local downPoint, downRelTo, downRelPoint, downX, downY = down:GetPoint(1)
	local textPoint, textRelTo, textRelPoint, textX, textY = text:GetPoint(1)

	-- Container TOPLEFT = Up's native TOPLEFT, converted to UIParent units below.
	local nativeLeft = up:GetLeft()
	local nativeTop = up:GetTop()

	if not nativeLeft or not nativeTop then
		-- A retry chain is already running; it owns the elapsed counter.
		if self.pageIndicatorCreateRetryPending then return end

		self.pageIndicatorCreateRetryElapsed = (self.pageIndicatorCreateRetryElapsed or 0)
			+ PAGE_INDICATOR_SHAPE_RETRY_INTERVAL

		if self.pageIndicatorCreateRetryElapsed >= PAGE_INDICATOR_CREATE_RETRY_TIMEOUT then
			self.pageIndicatorCreateRetryElapsed = nil
			self:Print("WARNING: Page Indicator's native position did not resolve in time - it stays at Blizzard's default spot this session.")
			return
		end

		self.pageIndicatorCreateRetryPending = true

		C_Timer.After(PAGE_INDICATOR_SHAPE_RETRY_INTERVAL, function()
			ACAB.pageIndicatorCreateRetryPending = nil
			ACAB:CreatePageIndicatorContainer()
		end)

		return
	end

	self.pageIndicatorCreateRetryElapsed = nil

	local upScale = up:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()
	if not upScale or not uiParentScale or uiParentScale == 0 then return end

	nativeLeft = (nativeLeft * upScale) / uiParentScale
	nativeTop = (nativeTop * upScale) / uiParentScale

	-- Down/Text anchored directly to Up/Down keep their own anchors.
	self.pageIndicatorDownFollowsUp = (downRelTo == up)
	self.pageIndicatorTextFollowsUp = (textRelTo == up)
	self.pageIndicatorTextFollowsDown = (textRelTo == down)

	-- Sharing Up's relativeTo: anchor to Up from GetPoint offsets - must not use rect reads (stale after login).
	local function SiblingAnchor(point, relTo, relPoint, x, y)
		if not relTo or relTo ~= upRelTo then return nil end

		-- Measures MainMenuBar instead of MainMenuBarArtFrame, whose own size is recalibrated by art positioning.
		local sizeFrame = relTo

		if relTo == MainMenuBarArtFrame and MainMenuBar then
			sizeFrame = MainMenuBar
		end

		local relWidth = sizeFrame.GetWidth and sizeFrame:GetWidth()
		local relHeight = sizeFrame.GetHeight and sizeFrame:GetHeight()
		if not relWidth or not relHeight then return nil end

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
	container:SetFrameStrata("LOW")

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
	if not container or not up or not down or not text then return end

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
		-- A retry chain is already running; it owns the elapsed counter.
		if self.pageIndicatorShapeRetryPending then return end

		self.pageIndicatorShapeRetryElapsed = (self.pageIndicatorShapeRetryElapsed or 0)
			+ PAGE_INDICATOR_SHAPE_RETRY_INTERVAL

		if self.pageIndicatorShapeRetryElapsed >= PAGE_INDICATOR_SHAPE_RETRY_TIMEOUT then
			self.pageIndicatorShapeRetryElapsed = nil
			self:Print("WARNING: Page Indicator's real position did not resolve in time - its edit-mode hitbox may be misaligned this session.")
			return
		end

		self.pageIndicatorShapeRetryPending = true

		C_Timer.After(PAGE_INDICATOR_SHAPE_RETRY_INTERVAL, function()
			ACAB.pageIndicatorShapeRetryPending = nil
			ACAB:ApplyPageIndicatorShape()
		end)

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

	if self:ApplyGroupedIfActive("pageindicator") then return end

	container:SetScale(ACABDB.mainBarPageIndicatorScale or 1)

	-- Default position depends on the container's measured width.
	if ACABDB.mainBarPageIndicatorFollowsMainBar ~= false then
		self:ApplyPageIndicatorPosition()
	end
end

-- Up/Down above MainMenuBarArtFrame (MEDIUM) - they keep the art's strata after reparenting otherwise.
function ACAB:ApplyPageIndicatorStrata()
	local container = self.pageIndicatorContainer
	if not container then return end

	container:SetFrameStrata("LOW")
	container:SetFrameLevel(11)

	if self.pageIndicatorUp then
		self.pageIndicatorUp:SetFrameStrata("LOW")
		self.pageIndicatorUp:SetFrameLevel(12)
	end

	if self.pageIndicatorDown then
		self.pageIndicatorDown:SetFrameStrata("LOW")
		self.pageIndicatorDown:SetFrameLevel(12)
	end
end

-- Canonical position vertically centered just right of Main Bar's visual edge, at the container's current width/scale.
function ACAB:GetPageIndicatorDefaultPosition()
	local bar1 = self.bars and self.bars[1]
	local container = self.pageIndicatorContainer
	if not bar1 or not bar1.config or not container then return nil end

	local barLeft, barRight, barBottom, barTop = self:GetPositionFrameRect(bar1, bar1.config, "TOPLEFT")
	local uiParentScale = UIParent:GetEffectiveScale()
	if not barLeft or not uiParentScale or uiParentScale == 0 then return nil end

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

	if self:ApplyGroupedIfActive("pageindicator") then return end

	local container = self.pageIndicatorContainer

	if container and ACABDB.mainBarPageIndicatorFollowsMainBar ~= false then
		local default = self:GetPageIndicatorDefaultPosition()

		if default then
			ACABDB.mainBarPageIndicatorPosition = default
		end
	end

	local pos = ACABDB.mainBarPageIndicatorPosition
	if not pos or not container then return end

	self:ApplySavedPosition(container, pos)
	self:EnsureElementOverlayAndHover("pageindicator", container)
end

-- Main Bar page's Page Indicator Scale slider.
function ACAB:SetPageIndicatorScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then return end

	ACABDB.mainBarPageIndicatorScale = scale

	if self:ApplyGroupedIfActive("pageindicator") then return end

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
	if not container then return end

	if ACABDB.defaultBarPaginationEnabled ~= false then
		container:Show()
	else
		container:Hide()
	end
end

function ACAB:StartPageIndicatorDrag()
	local pos = ACABDB.mainBarPageIndicatorPosition
	if not pos then return end

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
