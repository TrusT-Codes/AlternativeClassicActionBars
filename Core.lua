-- Core.lua
-- Addon bootstrap: identity constants, snap math, position helpers, edit/hoverbind/lock modes,
-- hover-fade controller, login sequence and the /acab slash commands.

AlternativeClassicActionBars = {}
local ACAB = AlternativeClassicActionBars

-- Action slot pool: pages 7-10, never surfaced by the default Blizzard UI.
ACAB.ACTION_SLOT_START = 73
ACAB.ACTION_SLOT_END   = 120

-- Defaults used when creating a NEW bar; existing bars keep their own saved config.
ACAB.BUTTON_SIZE = 36
ACAB.BUTTON_COLS = 12
ACAB.BUTTON_ROWS = 1

-- Minimum bar spacing in vanilla border style, avoiding native border overhang overlap. 0 in modern style.
ACAB.VANILLA_SPACING_FLOOR = 4

-- Extra buttonSize modern-style buttons need to look the same size as vanilla; spacing shifts oppositely on switch.
ACAB.MODERN_BUTTON_SIZE_DELTA = 4

-- Position nudge paired with MODERN_BUTTON_SIZE_DELTA so an anchored bar doesn't shift when buttonSize changes.
ACAB.MODERN_BUTTON_SIZE_POSITION_SHIFT = 2

-- Fixed pool size for a custom bar's button slots. Buttons beyond buttonCount are hidden, not destroyed.
ACAB.MAX_BAR_BUTTONS = 12

-- Equip-quality ring size ratio, matching vanilla's own ActionButtonTemplate.
ACAB.EQUIP_RING_RATIO = 62 / 36

-- Native border texture ratio to button size (66/36 at the default 36px button).
ACAB.BORDER_RATIO = 66 / 36

-- Vertical anchor offset of the native border texture (1px down from center).
ACAB.BORDER_Y_OFFSET = 1

-- Flat pixel amount subtracted from the border's visual inset on every side.
ACAB.BORDER_TEXTURE_FUDGE = 12

-- Extra top-only trim for Micro Menu, shared by the edit-mode overlay anchor and the grid layout row spacing.
ACAB.MICRO_MENU_OVERLAY_TOP_FUDGE = 2

-- Latency Bar edit-mode overlay inset - MainMenuBarPerformanceBarFrame's art sits inside a larger padded frame.
ACAB.LATENCY_BAR_OVERLAY_INSET = { left = 1, right = 6.5, top = 14, bottom = 11 }

-- "Snap to Adjacent Elements" capture distance, in real screen pixels.
ACAB.SNAP_THRESHOLD = 8

-- Pet Bar (wraps PetActionButton1-10); its fixedActionSlots are pet slots 1-10, not action slots.
ACAB.PET_BAR_ID = 10

-- Stance Bar's styled-mode entry (Button.lua isStanceSlot); native mode uses ACABDB.stanceBar* instead.
ACAB.STANCE_BAR_ID = 11

-- Every default-bar-family id, in display order.
ACAB.DEFAULT_BAR_IDS = { 1, 2, 3, 4, 5, ACAB.PET_BAR_ID, ACAB.STANCE_BAR_ID }

-- True for any id in ACAB.DEFAULT_BAR_IDS.
function ACAB:IsDefaultBarFamilyId(barId)
	if not barId then
		return false
	end

	local i

	for i = 1, table.getn(self.DEFAULT_BAR_IDS) do
		if self.DEFAULT_BAR_IDS[i] == barId then
			return true
		end
	end

	return false
end

-- Grid shape for each default bar. Position is captured live, not stored here - see CaptureNativeAnchor.
ACAB.DEFAULT_BAR_GRID = {
	[1] = { cols = 12, rows = 1 },                      -- Main.
	[2] = { cols = 12, rows = 1, enabled = false },      -- Bottom Left.
	[3] = { cols = 12, rows = 1, enabled = false },      -- Bottom Right.
	[4] = { cols = 1,  rows = 12, enabled = false },     -- Right.
	[5] = { cols = 1,  rows = 12, enabled = false },     -- Right 2.
	[ACAB.PET_BAR_ID] = { cols = 10, rows = 1, enabled = true }, -- Pet Bar.
	-- Stance Bar: SeedOneDefaultBar overrides cols/rows from the live form count.
	[ACAB.STANCE_BAR_ID] = { cols = 10, rows = 1, enabled = true },
}

-- Native FrameXML global backing each default bar's Interface Options checkbox. Session-scoped, not persisted.
ACAB.SHOW_MULTI_ACTIONBAR_GLOBAL = {
	[2] = "SHOW_MULTI_ACTIONBAR_1",
	[3] = "SHOW_MULTI_ACTIONBAR_2",
	[4] = "SHOW_MULTI_ACTIONBAR_3",
	[5] = "SHOW_MULTI_ACTIONBAR_4",
}

-- Friendly display names for the default-bar family.
ACAB.DEFAULT_BAR_NAMES = {
	[1] = "Main Bar",
	[2] = "Action Bar 1",
	[3] = "Action Bar 2",
	[4] = "Right Action Bar 1",
	[5] = "Right Action Bar 2",
	[ACAB.PET_BAR_ID] = "Pet Bar",
	[ACAB.STANCE_BAR_ID] = "Stance Bar",
}

-- ACABDB.mainBarArtMode values for Main Bar's Blizzard art (MainMenuBarArtFrame background + gryphons).
ACAB.MAIN_BAR_ART_MODE_FULL = "full"              -- Fully Enabled.
ACAB.MAIN_BAR_ART_MODE_NO_GRYPHONS = "noGryphons" -- Gryphons hidden, background shown.
ACAB.MAIN_BAR_ART_MODE_DISABLED = "disabled"      -- All art hidden.

-- MainMenuBarArtFrame region names of the two gryphon end-caps; every other region is background art.
ACAB.MAIN_BAR_ART_GRYPHON_REGION_NAMES = {
	MainMenuBarLeftEndCap = true,
	MainMenuBarRightEndCap = true,
}

-- True unless Main Bar's art is Fully Disabled - the condition for any element to be grouped with Main Bar.
function ACAB:IsMainBarArtEnabled()
	return ACABDB.mainBarArtMode ~= self.MAIN_BAR_ART_MODE_DISABLED
end

-- User-facing bar name; Extra Bars (ids 6+) are numbered from 1.
function ACAB:GetBarDisplayName(barId)
	if self.DEFAULT_BAR_NAMES[barId] then
		return self.DEFAULT_BAR_NAMES[barId]
	end

	if barId and barId >= 1 and barId <= 5 then
		return "Bar " .. tostring(barId)
	end

	return "Extra Bar " .. tostring((barId or 0) - 5)
end


-------------------------------------------------------------------------
-- Extra Bars 1-4 (ids 6-9): always present in ACABDB.bars, toggled via cfg.enabled.
-------------------------------------------------------------------------

ACAB.EXTRA_BAR_ID_START = 6
ACAB.EXTRA_BAR_COUNT = 4

-- Chat prefix color, also used for highlighted key/command names.
ACAB.CHAT_PREFIX_COLOR = "|cff33ccff"

function ACAB:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage(self.CHAT_PREFIX_COLOR .. "[ACAB]|r " .. tostring(msg))
end

-- Hides `frame` and permanently neuters its Show() to a no-op, so no later native code path can re-show it.
function ACAB:NeuterFrameShow(frame)
	if not frame then
		return
	end

	frame:Hide()

	if not frame.ACABShowNeutered then
		frame.Show = function() end
		frame.ACABShowNeutered = true
	end
end

-- Shared clamp/rounding for every native-element Scale setter - rounds to 0.1, clamps to [0.5, 2.0].
function ACAB:ClampScaleSetting(scale)
	scale = tonumber(scale)

	if not scale then
		return nil
	end

	scale = math.floor((scale * 10) + 0.5) / 10

	if scale < 0.5 then
		scale = 0.5
	end

	if scale > 2.0 then
		scale = 2.0
	end

	return scale
end

-- Shared clamp/rounding for every native-element Spacing setter - rounds to the nearest pixel.
function ACAB:ClampSpacingSetting(spacing, minSpacing, maxSpacing)
	spacing = tonumber(spacing)

	if not spacing then
		return nil
	end

	spacing = math.floor(spacing + 0.5)

	if spacing < minSpacing then
		spacing = minSpacing
	end

	if spacing > maxSpacing then
		spacing = maxSpacing
	end

	return spacing
end

-------------------------------------------------------------------------
-- Snap to Adjacent Elements / Snap to Grid
-- Called per drag tick from DefaultBars.lua's drag engine to nudge the proposed position.
-------------------------------------------------------------------------

-- Converts a region's frame bounds to real screen pixels, optionally expanded by a per-side visual inset.
local function GetRealScreenBounds(region, insetLeft, insetRight, insetTop, insetBottom)
	if not region or not region.GetLeft then
		return nil
	end

	insetLeft = insetLeft or 0
	insetRight = insetRight or 0
	insetTop = insetTop or 0
	insetBottom = insetBottom or 0

	local left, right, top, bottom = region:GetLeft(), region:GetRight(), region:GetTop(), region:GetBottom()
	local scale = region:GetEffectiveScale()

	if not left or not right or not top or not bottom or not scale then
		return nil
	end

	return (left - insetLeft) * scale, (right + insetRight) * scale, (top + insetTop) * scale, (bottom - insetBottom) * scale
end

-- Border-texture overhang beyond a vanilla-style button's frame bounds, per side (never negative).
local function ComputeVanillaBorderInsets(buttonSize, borderRatio, yOffset, fudge)
	local uniform = buttonSize * (borderRatio - 1) / 2

	local left = uniform - fudge
	local right = uniform - fudge
	local top = uniform - yOffset - fudge
	local bottom = uniform + yOffset - fudge

	if left < 0 then left = 0 end
	if right < 0 then right = 0 end
	if top < 0 then top = 0 end
	if bottom < 0 then bottom = 0 end

	return left, right, top, bottom
end

-- How far a frame's visible border overhangs its bounds on each side; non-zero only for bars 1-5 in vanilla style.
function ACAB:GetElementVisualInset(frame)
	if frame and frame.config and frame.config.id and self:IsVanillaBorderStyle() then
		local buttonSize = frame.config.buttonSize or self.BUTTON_SIZE

		return ComputeVanillaBorderInsets(buttonSize, self.BORDER_RATIO, self.BORDER_Y_OFFSET, self.BORDER_TEXTURE_FUDGE)
	end

	return 0, 0, 0, 0
end

-- Every currently visible/enabled draggable element except `excludeElement`, as real-screen-pixel bounding boxes.
function ACAB:GetAllSnapTargetBoxes(excludeElement)
	local boxes = {}

	-- Main Bar's followers move with it mid-drag - snapping to them feeds back into the drag (jitter).
	local draggingMainBar = excludeElement ~= nil and self.bars ~= nil and excludeElement == self.bars[1]

	local function AddBox(frame)
		if not frame or frame == excludeElement then
			return
		end

		if draggingMainBar and self:IsMainBarFollower(frame) then
			return
		end

		if not frame.IsShown or not frame:IsShown() then
			return
		end

		local left, right, top, bottom = GetRealScreenBounds(frame, self:GetElementVisualInset(frame))

		if left then
			table.insert(boxes, { left = left, right = right, top = top, bottom = bottom })
		end
	end

	if self.bars then
		local barId

		for barId, bar in pairs(self.bars) do
			AddBox(bar)
		end
	end

	AddBox(self.bagBarContainer)
	AddBox(self.microMenuContainer)
	AddBox(self.stanceBarContainer)
	AddBox(self.pageIndicatorContainer)

	AddBox(getglobal(self.KEYRING_BUTTON_NAME))
	AddBox(getglobal(self.LATENCY_BAR_FRAME_NAME))
	AddBox(getglobal(self.EXP_BAR_FRAME_NAME))

	return boxes
end

-- Visible edges of `frame` (visual-inset-adjusted) in UIParent units: left, right, top, bottom.
function ACAB:GetElementRealEdges(frame)
	if not frame then
		return nil
	end

	local insetLeft, insetRight, insetTop, insetBottom = self:GetElementVisualInset(frame)
	local left, right, top, bottom = GetRealScreenBounds(frame, insetLeft, insetRight, insetTop, insetBottom)

	if not left then
		return nil
	end

	local uiParentScale = UIParent:GetEffectiveScale()

	if not uiParentScale or uiParentScale == 0 then
		return nil
	end

	return left / uiParentScale, right / uiParentScale, top / uiParentScale, bottom / uiParentScale
end

-- Converts a UIParent-unit offset into `container`'s own scale (legacy cfg.x/cfg.y units).
function ACAB:ConvertUIParentOffsetToOwnScale(container, uiParentOffset)
	local scale = (container and container.GetScale and container:GetScale()) or 1

	if not scale or scale == 0 then
		scale = 1
	end

	return uiParentOffset / scale
end

-- Fraction of a rect's width/height a point name sits at (LEFT=0/RIGHT=1, BOTTOM=0/TOP=1, else 0.5).
function ACAB:GetPointFractions(point)
	local fx, fy = 0.5, 0.5

	point = point or "TOPLEFT"

	if string.find(point, "LEFT") then
		fx = 0
	elseif string.find(point, "RIGHT") then
		fx = 1
	end

	if string.find(point, "BOTTOM") then
		fy = 0
	elseif string.find(point, "TOP") then
		fy = 1
	end

	return fx, fy
end

-------------------------------------------------------------------------
-- Element positions
-- Canonical: { point = "CENTER", relativePoint = "CENTER", visualCenter = true, x, y }, x/y in UIParent
-- units from screen center to the element's visual center. Anything else is a legacy anchor (frame's own units).
-------------------------------------------------------------------------

function ACAB:IsCanonicalPosition(pos)
	return pos ~= nil and pos.visualCenter == true and pos.point == "CENTER" and pos.relativePoint == "CENTER"
end

-- UIParent's real anchoring size in UIParent units, via a CENTER-anchored probe frame.
-- WARNING: never UIParent:GetWidth()/GetHeight() - those undershoot the real screen on this client.
function ACAB:GetUIParentAnchorSize()
	local probe = self.uiParentCenterProbe

	if not probe then
		probe = CreateFrame("Frame", nil, UIParent)
		probe:SetWidth(2)
		probe:SetHeight(2)
		probe:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
		self.uiParentCenterProbe = probe
	end

	-- must read UIParent first or the probe resolves against a stale rect (§5af)
	UIParent:GetLeft()

	local centerX, centerY = probe:GetCenter()

	if not centerX or not centerY then
		return GetScreenWidth() or 1024, GetScreenHeight() or 768
	end

	return centerX * 2, centerY * 2
end

-- Visual edges' distance inside the frame rect (own units, negative = overhang): left, right, top, bottom.
function ACAB:GetVisualInsets(frame)
	if not frame then
		return 0, 0, 0, 0
	end

	if frame.config and frame.config.id then
		local left, right, top, bottom = self:GetElementVisualInset(frame)

		return -left, -right, -top, -bottom
	end

	local insets = frame.chainVisualInsets or frame.overlayInset

	if insets then
		return insets.left or 0, insets.right or 0, insets.top or 0, insets.bottom or 0
	end

	return 0, 0, 0, 0
end

local function RoundPosition(value)
	return math.floor((value * 100) + 0.5) / 100
end

-- Metrics table: scale vs UIParent (s), size (w/h, bars from config), insets (l/r/t/b), screen (W/H if needScreen).
local function GetPositionMetrics(self, frame, width, height, needScreen)
	local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()

	if not frameScale or frameScale == 0 or not uiParentScale or uiParentScale == 0 then
		return nil
	end

	if not width and frame.config and frame.config.buttonSize and self.GetBarFrameSize then
		width, height = self:GetBarFrameSize(frame.config)
	end

	local m = {}

	m.s = frameScale / uiParentScale
	m.w = width or frame:GetWidth() or 0
	m.h = height or frame:GetHeight() or 0
	m.l, m.r, m.t, m.b = self:GetVisualInsets(frame)

	if needScreen then
		m.W, m.H = self:GetUIParentAnchorSize()
	end

	return m
end

-- Frame rect's left/bottom in UIParent units for pos (canonical or legacy).
local function GetFrameLeftBottom(self, m, pos, fallbackRelativePoint)
	if self:IsCanonicalPosition(pos) then
		local centerX = (m.W / 2) + (pos.x or 0) - (((m.l - m.r) / 2) * m.s)
		local centerY = (m.H / 2) + (pos.y or 0) - (((m.b - m.t) / 2) * m.s)

		return centerX - (m.w * m.s / 2), centerY - (m.h * m.s / 2)
	end

	local pfx, pfy = self:GetPointFractions(pos.point or "TOPLEFT")
	local rfx, rfy = self:GetPointFractions(pos.relativePoint or fallbackRelativePoint or "BOTTOMLEFT")
	local anchorX = (rfx * m.W) + ((pos.x or 0) * m.s)
	local anchorY = (rfy * m.H) + ((pos.y or 0) * m.s)

	return anchorX - (pfx * m.w * m.s), anchorY - (pfy * m.h * m.s)
end

-- Writes pos from a frame rect's left/bottom (UIParent units) - canonical when point is nil.
local function SetFrameLeftBottom(self, m, pos, left, bottom, point, relativePoint)
	if not point then
		local centerX = left + (m.w * m.s / 2) + (((m.l - m.r) / 2) * m.s)
		local centerY = bottom + (m.h * m.s / 2) + (((m.b - m.t) / 2) * m.s)

		pos.point = "CENTER"
		pos.relativePoint = "CENTER"
		pos.visualCenter = true
		pos.x = RoundPosition(centerX - (m.W / 2))
		pos.y = RoundPosition(centerY - (m.H / 2))

		return
	end

	relativePoint = relativePoint or point

	local pfx, pfy = self:GetPointFractions(point)
	local rfx, rfy = self:GetPointFractions(relativePoint)

	pos.point = point
	pos.relativePoint = relativePoint
	pos.visualCenter = nil
	pos.x = (left + (pfx * m.w * m.s) - (rfx * m.W)) / m.s
	pos.y = (bottom + (pfy * m.h * m.s) - (rfy * m.H)) / m.s
end

-- Rewrites pos in place as a legacy point/relativePoint anchor at the same screen spot; returns true if converted.
-- fallbackRelativePoint: what the caller's own apply assumes when a legacy pos.relativePoint is nil.
function ACAB:ConvertPositionAnchor(frame, pos, point, relativePoint, width, height, fallbackRelativePoint)
	if not frame or not pos then
		return false
	end

	relativePoint = relativePoint or point

	if not self:IsCanonicalPosition(pos)
		and (pos.point or "TOPLEFT") == point
		and (pos.relativePoint or fallbackRelativePoint or "BOTTOMLEFT") == relativePoint then
		pos.point = point
		pos.relativePoint = relativePoint
		pos.visualCenter = nil
		return false
	end

	local m = GetPositionMetrics(self, frame, width, height, true)

	if not m then
		return false
	end

	local left, bottom = GetFrameLeftBottom(self, m, pos, fallbackRelativePoint)

	SetFrameLeftBottom(self, m, pos, left, bottom, point, relativePoint)

	return true
end

-- Rewrites a legacy pos in place as canonical, same screen spot.
function ACAB:ConvertPositionToCanonical(frame, pos, width, height, fallbackRelativePoint)
	if not frame or not pos or self:IsCanonicalPosition(pos) then
		return false
	end

	local m = GetPositionMetrics(self, frame, width, height, true)

	if not m then
		return false
	end

	local left, bottom = GetFrameLeftBottom(self, m, pos, fallbackRelativePoint)

	SetFrameLeftBottom(self, m, pos, left, bottom, nil)

	return true
end

-- Copy of pos converted to a legacy point/relativePoint anchor - pos itself is untouched.
function ACAB:GetPositionInAnchor(frame, pos, point, relativePoint, fallbackRelativePoint)
	local copy = {
		point = pos.point,
		relativePoint = pos.relativePoint,
		visualCenter = pos.visualCenter,
		x = pos.x,
		y = pos.y,
	}

	self:ConvertPositionAnchor(frame, copy, point, relativePoint, nil, nil, fallbackRelativePoint)

	return copy
end

-- Frame rect for pos in UIParent units: left, right, bottom, top.
function ACAB:GetPositionFrameRect(frame, pos, fallbackRelativePoint)
	if not frame or not pos then
		return nil
	end

	local m = GetPositionMetrics(self, frame, nil, nil, true)

	if not m then
		return nil
	end

	local left, bottom = GetFrameLeftBottom(self, m, pos, fallbackRelativePoint)

	return left, left + (m.w * m.s), bottom, bottom + (m.h * m.s)
end

-- Converts a legacy pos to canonical; no-op before NormalizeAllPositionAnchors has run or on an unsized frame.
function ACAB:NormalizePositionAnchor(frame, pos, width, height, fallbackRelativePoint)
	if not frame or not pos or not self.positionAnchorsNormalized or self:IsCanonicalPosition(pos) then
		return false
	end

	local m = GetPositionMetrics(self, frame, width, height, false)

	if not m or m.w <= 1 or m.h <= 1 then
		return false
	end

	return self:ConvertPositionToCanonical(frame, pos, m.w, m.h, fallbackRelativePoint)
end

-- Normalizes pos, then anchors frame to UIParent from it. guardFlag: the frame's InstallReanchorGuard flag.
function ACAB:ApplyPositionToFrame(frame, pos, fallbackRelativePoint, width, height, guardFlag)
	if not frame or not pos then
		return
	end

	self:NormalizePositionAnchor(frame, pos, width, height, fallbackRelativePoint)

	local point = pos.point or "TOPLEFT"
	local relativePoint = pos.relativePoint or fallbackRelativePoint or "BOTTOMLEFT"
	local x = pos.x or 0
	local y = pos.y or 0

	if self:IsCanonicalPosition(pos) then
		local m = GetPositionMetrics(self, frame, width, height, false)

		if m then
			x = (x / m.s) - ((m.l - m.r) / 2)
			y = (y / m.s) - ((m.b - m.t) / 2)
		end
	end

	if guardFlag then
		frame[guardFlag] = true
	end

	frame:ClearAllPoints()
	self:PixelSetPoint(frame, point, UIParent, relativePoint, x, y)

	if guardFlag then
		frame[guardFlag] = nil
	end
end

-- Login pass: enables NormalizePositionAnchor and re-applies every element, migrating saves to canonical.
-- Must run after every element's shape/scale is applied, or the conversion reads stale sizes.
function ACAB:NormalizeAllPositionAnchors()
	self.positionAnchorsNormalized = true

	if self.bars then
		local barId, bar

		for barId, bar in pairs(self.bars) do
			if bar and bar.config then
				self:ApplyBarPosition(bar)
			end
		end
	end

	self:ApplyPetBarNativePosition()
	self:ApplyStanceBarPosition()
	self:ApplyBagBarPosition()
	self:ApplyMicroMenuPosition()
	self:ApplyKeyRingPosition()
	self:ApplyLatencyBarPosition()
	self:ApplyPageIndicatorPosition()
	self:ApplyExpBarPosition()
	self:ApplyCastBarPosition()
	self:ApplyTooltipPosition()
end

-- Computes a snap-adjusted (proposedLeft, proposedTop) against screen edges and every visible element's edges.
function ACAB:ComputeSnapAdjustment(proposedLeft, proposedTop, width, height, excludeElement)
	local baseline = (ACABDB and ACABDB.snapToAdjacentElements) and true or false
	local shiftHeld = (IsShiftKeyDown and IsShiftKeyDown()) and true or false

	-- Shift inverts the baseline setting for this drag tick.
	if baseline == shiftHeld then
		return nil, nil
	end

	if not proposedLeft or not proposedTop or not width or not height then
		return nil, nil
	end

	local threshold = self.SNAP_THRESHOLD

	local proposedRight = proposedLeft + width
	local proposedBottom = proposedTop - height

	local adjustedLeft, bestLeftDist
	local adjustedTop, bestTopDist

	local function ConsiderX(candidate, edge)
		local dist = candidate - edge

		if dist < 0 then
			dist = -dist
		end

		if dist <= threshold and (not bestLeftDist or dist < bestLeftDist) then
			adjustedLeft = proposedLeft + (candidate - edge)
			bestLeftDist = dist
		end
	end

	local function ConsiderY(candidate, edge)
		local dist = candidate - edge

		if dist < 0 then
			dist = -dist
		end

		if dist <= threshold and (not bestTopDist or dist < bestTopDist) then
			adjustedTop = proposedTop + (candidate - edge)
			bestTopDist = dist
		end
	end

	local screenLeft, screenRight, screenTop, screenBottom = GetRealScreenBounds(UIParent)

	if screenLeft then
		ConsiderX(screenLeft, proposedLeft)
		ConsiderX(screenRight, proposedRight)
		ConsiderY(screenTop, proposedTop)
		ConsiderY(screenBottom, proposedBottom)
	end

	local boxes = self:GetAllSnapTargetBoxes(excludeElement)
	local i

	for i = 1, table.getn(boxes) do
		local box = boxes[i]

		ConsiderX(box.left, proposedLeft)
		ConsiderX(box.right, proposedLeft)
		ConsiderX(box.left, proposedRight)
		ConsiderX(box.right, proposedRight)

		ConsiderY(box.top, proposedTop)
		ConsiderY(box.bottom, proposedTop)
		ConsiderY(box.top, proposedBottom)
		ConsiderY(box.bottom, proposedBottom)
	end

	return adjustedLeft, adjustedTop
end

-- Rounds `value` to the nearest multiple of `step`, half away from zero.
local function RoundToNearestMultiple(value, step)
	if not step or step == 0 then
		return value
	end

	local n = value / step

	if n >= 0 then
		n = math.floor(n + 0.5)
	else
		n = -math.floor(-n + 0.5)
	end

	return n * step
end

-- Picks whichever candidate anchor position keeps `proposed` closest to the cursor.
local function BestSnapCandidate(proposed, candidates)
	local best, bestDist
	local i

	for i = 1, table.getn(candidates) do
		local dist = candidates[i] - proposed

		if dist < 0 then
			dist = -dist
		end

		if not bestDist or dist < bestDist then
			best = candidates[i]
			bestDist = dist
		end
	end

	return best
end

-- Shared grid-snap setup: real-pixel spacing, UIParent's real bounds and center - or nil when grid snap
-- is off this tick (Alt inverts ACABDB.snapToGrid) or there is nothing to snap.
local function GetGridSnapContext(self, proposedLeft, proposedTop, width, height, scale)
	local baseline = (ACABDB and ACABDB.snapToGrid) and true or false
	local altHeld = (IsAltKeyDown and IsAltKeyDown()) and true or false

	if baseline == altHeld then
		return nil
	end

	if not proposedLeft or not proposedTop or not width or not height then
		return nil
	end

	local spacing = self:GetLayoutGridSpacing()

	if not spacing or spacing <= 0 then
		return nil
	end

	spacing = spacing * (scale or 1)

	local screenLeft, screenRight, screenTop, screenBottom = GetRealScreenBounds(UIParent)

	if not screenLeft then
		return nil
	end

	return spacing, screenLeft, screenRight, screenTop, screenBottom,
		(screenLeft + screenRight) / 2, (screenTop + screenBottom) / 2
end

-- Grid-snaps a dragged element's top-left corner, checking near edge, far edge, center and screen edges.
-- `scale` converts GetLayoutGridSpacing()'s local units to real screen pixels.
function ACAB:ComputeGridSnapAdjustment(proposedLeft, proposedTop, width, height, scale)
	local spacing, screenLeft, screenRight, screenTop, screenBottom, centerX, centerY =
		GetGridSnapContext(self, proposedLeft, proposedTop, width, height, scale)

	if not spacing then
		return nil, nil
	end

	local function NearestOnAxis(point, origin)
		return origin + RoundToNearestMultiple(point - origin, spacing)
	end

	local adjustedLeft = BestSnapCandidate(proposedLeft, {
		NearestOnAxis(proposedLeft, centerX),
		NearestOnAxis(proposedLeft + width, centerX) - width,
		NearestOnAxis(proposedLeft + (width / 2), centerX) - (width / 2),
		screenLeft,
		screenRight - width,
	})

	local adjustedTop = BestSnapCandidate(proposedTop, {
		NearestOnAxis(proposedTop, centerY),
		NearestOnAxis(proposedTop - height, centerY) + height,
		NearestOnAxis(proposedTop - (height / 2), centerY) + (height / 2),
		screenTop,
		screenBottom + height,
	})

	return adjustedLeft, adjustedTop
end

-- Per-axis real-pixel capture radius for ComputeCenterGridSnapAdjustment.
local CENTER_GRID_SNAP_CAPTURE_PX_X = 10
local CENTER_GRID_SNAP_CAPTURE_PX_Y = 2

-- Snaps a point to its nearest grid line if within capturePx, else nil.
local function SnapPointWithinCapture(point, origin, spacing, capturePx)
	local offset = point - origin
	local nearestOffset = RoundToNearestMultiple(offset, spacing)
	local distance = offset - nearestOffset

	if distance < 0 then
		distance = -distance
	end

	if distance <= capturePx then
		return origin + nearestOffset
	end

	return nil
end

-- Appends `value` to `list` at index n+1 if non-nil, returns the new n.
local function AppendCandidate(list, n, value)
	if value then
		list[n + 1] = value
		return n + 1
	end

	return n
end

-- Snaps the near edge, far edge, or center to a grid line, each only within its own per-axis capture radius.
function ACAB:ComputeCenterGridSnapAdjustment(proposedLeft, proposedTop, width, height, scale)
	local spacing, screenLeft, screenRight, screenTop, screenBottom, centerX, centerY =
		GetGridSnapContext(self, proposedLeft, proposedTop, width, height, scale)

	if not spacing then
		return nil, nil
	end

	local nearX = SnapPointWithinCapture(proposedLeft, centerX, spacing, CENTER_GRID_SNAP_CAPTURE_PX_X)
	local farX = SnapPointWithinCapture(proposedLeft + width, centerX, spacing, CENTER_GRID_SNAP_CAPTURE_PX_X)
	local midX = SnapPointWithinCapture(proposedLeft + (width / 2), centerX, spacing, CENTER_GRID_SNAP_CAPTURE_PX_X)

	local xCandidates = {}
	local xn = 0
	xn = AppendCandidate(xCandidates, xn, nearX)
	xn = AppendCandidate(xCandidates, xn, farX and (farX - width))
	xn = AppendCandidate(xCandidates, xn, midX and (midX - (width / 2)))

	local adjustedLeft

	if xn > 0 then
		adjustedLeft = BestSnapCandidate(proposedLeft, xCandidates)
	end

	local nearY = SnapPointWithinCapture(proposedTop, centerY, spacing, CENTER_GRID_SNAP_CAPTURE_PX_Y)
	local farY = SnapPointWithinCapture(proposedTop - height, centerY, spacing, CENTER_GRID_SNAP_CAPTURE_PX_Y)
	local midY = SnapPointWithinCapture(proposedTop - (height / 2), centerY, spacing, CENTER_GRID_SNAP_CAPTURE_PX_Y)

	local yCandidates = {}
	local yn = 0
	yn = AppendCandidate(yCandidates, yn, nearY)
	yn = AppendCandidate(yCandidates, yn, farY and (farY + height))
	yn = AppendCandidate(yCandidates, yn, midY and (midY + (height / 2)))

	local adjustedTop

	if yn > 0 then
		adjustedTop = BestSnapCandidate(proposedTop, yCandidates)
	end

	return adjustedLeft, adjustedTop
end

-------------------------------------------------------------------------
-- Global border/spacing style
-------------------------------------------------------------------------

-- Single source of truth for the global border/spacing style.
function ACAB:IsVanillaBorderStyle()
	if ACABDB and ACABDB.useDefaultLayout ~= false then
		return true
	end

	return not (ACABDB and ACABDB.modernBorderStyle)
end

-- Whether the Pet Bar is effectively in native mode - forces native+uncondensed while default layout is on.
function ACAB:IsPetBarNativeModeEffective()
	if ACABDB and ACABDB.useDefaultLayout ~= false then
		return true
	end

	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[self.PET_BAR_ID]

	return cfg and cfg.useNativePetBar == true
end

-- Whether the Stance Bar is effectively in native mode - forces native while default layout is on.
function ACAB:IsStanceBarNativeModeEffective()
	if ACABDB and ACABDB.useDefaultLayout ~= false then
		return true
	end

	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[self.STANCE_BAR_ID]

	return cfg and cfg.useNativeStanceBar == true
end

-- Live GetNumShapeshiftForms() count, clamped to MAX_STANCE_BUTTONS (DefaultBars.lua; runtime calls only).
function ACAB:GetClampedLiveStanceCount()
	local liveCount = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0

	if liveCount > self.MAX_STANCE_BUTTONS then
		liveCount = self.MAX_STANCE_BUTTONS
	end

	return liveCount
end

-- Re-syncs styled Stance Bar cfg's buttonCount/cols/rows to the live form count, keeping a valid custom shape.
-- Returns true if it changed something.
function ACAB:ApplyStanceBarLiveShape()
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.STANCE_BAR_ID]

	if not cfg then
		return false
	end

	local liveCount = self:GetClampedLiveStanceCount()

	local shapeValid = cfg.cols and cfg.rows and (cfg.cols * cfg.rows) == liveCount

	if cfg.buttonCount == liveCount and shapeValid then
		return false
	end

	cfg.buttonCount = liveCount
	-- Resets to a sensible default Nx1 shape.
	cfg.cols = liveCount > 0 and liveCount or 1
	cfg.rows = 1

	return true
end

-- Whether the Pet Bar should hide empty slots - forced false while default layout is on.
function ACAB:ShouldCondensePetBarSlots()
	if ACABDB and ACABDB.useDefaultLayout ~= false then
		return false
	end

	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[self.PET_BAR_ID]

	return cfg and cfg.condenseEmptyPetSlots == true
end

-- Live count of Pet Bar slots (1-10) currently assigned an ability/command.
function ACAB:GetPetBarFilledSlotCount()
	if not GetPetActionInfo then
		return 0
	end

	local count = 0
	local i

	for i = 1, 10 do
		if GetPetActionInfo(i) ~= nil then
			count = count + 1
		end
	end

	return count
end

-- buttonSize a brand-new bar should seed at, correct for the currently active style.
function ACAB:GetCurrentButtonSizeBaseline()
	if self:IsVanillaBorderStyle() then
		return self.BUTTON_SIZE
	end

	return self.BUTTON_SIZE + self.MODERN_BUTTON_SIZE_DELTA
end

-- Layout-grid line spacing: the custom grid size if enabled, else Main Bar's buttonSize (+ spacing in vanilla style).
function ACAB:GetLayoutGridSpacing()
	if ACABDB and ACABDB.useCustomGridSize and ACABDB.customGridSize then
		return ACABDB.customGridSize
	end

	local mainBar = self.bars and self.bars[1]
	local size = (mainBar and mainBar.config and mainBar.config.buttonSize)
		or self:GetCurrentButtonSizeBaseline()

	if not self:IsVanillaBorderStyle() then
		return size
	end

	local spacing = (mainBar and mainBar.config and mainBar.config.spacing)
		or self.VANILLA_SPACING_FLOOR

	return size + spacing
end

-------------------------------------------------------------------------
-- Edit mode ("Configure Layout")
-------------------------------------------------------------------------

-- ESCAPE exits edit mode via bindings.xml's ACABEDITMODEESCAPE, swapped onto ESCAPE unsaved (never SaveBindings).

-- Called from bindings.xml - must stay a plain global function.
function ACAB_EditModeEscapeFire()
	ACAB:SetEditMode(false)
end

-- Swaps ESCAPE onto ACABEDITMODEESCAPE, remembering its previous action; no-op while already swapped.
function ACAB:EnableEditModeEscapeBinding()
	if self.editModeEscapeBindingActive then
		return
	end

	local previousAction = GetBindingAction("ESCAPE")

	self.editModeEscapePreviousAction = (previousAction ~= "" and previousAction) or nil
	self.editModeEscapeBindingActive = true

	SetBinding("ESCAPE", "ACABEDITMODEESCAPE")
end

-- Restores ESCAPE's previous binding (or clears it).
function ACAB:DisableEditModeEscapeBinding()
	if not self.editModeEscapeBindingActive then
		return
	end

	if self.editModeEscapePreviousAction then
		SetBinding("ESCAPE", self.editModeEscapePreviousAction)
	else
		SetBinding("ESCAPE")
	end

	self.editModeEscapePreviousAction = nil
	self.editModeEscapeBindingActive = false
end

function ACAB:IsEditMode()
	return ACABDB and ACABDB.editMode == true
end

-- The Default profile can never be edited.
function ACAB:IsDefaultProfileActive()
	return not ACABCharDB or ACABCharDB.activeProfile == self.DEFAULT_PROFILE_NAME
end

-- Wraps a modifier-key name in the same color as the chat prefix.
local function ColorKeyName(key)
	return ACAB.CHAT_PREFIX_COLOR .. key .. "|r"
end

-- Prints the edit-mode controls summary on enable, or the OFF notice.
local function PrintEditModeState(enabled)
	if enabled then
		ACAB:Print("Configure Layout |cff20ff20ON|r \r")
		ACAB:Print(ColorKeyName("drag").." to move, " .. ColorKeyName("scroll") .. " to scale, " .. ColorKeyName("right-click") .. " to open settings for any Element")
		ACAB:Print("Hold " .. ColorKeyName("Shift") .. " while dragging to temporarily invert 'Snap to Adjacent Elements' Setting")
		ACAB:Print("Hold " .. ColorKeyName("Alt") .. " while dragging to temporarily invert 'Snap to Grid' Setting")
		ACAB:Print("Hold " .. ColorKeyName("Ctrl") .. " to temporarily show/hide the layout grid")
		ACAB:Print("Press " .. ColorKeyName("Escape") .. " to |cffff2020exit|r the Configure Layout mode")
	else
		ACAB:Print("Configure Layout |cffff2020OFF|r.")
	end
end

function ACAB:SetEditMode(enabled)
	self:EnsureDB()
	enabled = enabled and true or false

	if enabled and self:IsDefaultProfileActive() then
		self:Print("Edit Layout mode is disabled while the Default profile is active. Switch to another profile (Settings > Profiles) to edit your bar layout.")
		return
	end

	-- Edit mode always wins over hoverbind mode.
	if enabled and self:IsHoverBindMode() then
		self:SetHoverBindMode(false)
	end

	ACABDB.editMode = enabled
	self:ApplyEditModeVisual()

	if enabled then
		self:ForceHoverFadeFramesVisible()
	else
		self:RestoreHoverFadeFrames()
	end

	PrintEditModeState(enabled)
end

function ACAB:ToggleEditMode()
	self:SetEditMode(not self:IsEditMode())
end

-------------------------------------------------------------------------
-- Hoverbind mode (mutually exclusive with edit mode)
-------------------------------------------------------------------------

function ACAB:IsHoverBindMode()
	return ACABDB and ACABDB.hoverBindMode == true
end

function ACAB:SetHoverBindMode(enabled)
	self:EnsureDB()
	enabled = enabled and true or false

	if enabled and self:IsEditMode() then
		self:Print("Cannot enable Hoverbind while Configure Layout is on.")
		return
	end

	ACABDB.hoverBindMode = enabled

	if self.ApplyHoverBindVisual then
		self:ApplyHoverBindVisual(enabled)
	end

	if enabled then
		self:ForceHoverFadeFramesVisible()
	else
		self:RestoreHoverFadeFrames()
	end
end

function ACAB:ToggleHoverBindMode()
	if not self:IsHoverBindMode() and self:IsEditMode() then
		self:Print("Cannot enable Hoverbind while Configure Layout is on.")
		return
	end

	self:SetHoverBindMode(not self:IsHoverBindMode())
	self:Print(self:IsHoverBindMode()
		and "Hoverbind |cff20ff20ON|r - hover a button and press a key to bind it. Red = unbound, green = bound."
		or "Hoverbind |cffff2020OFF|r.")
end

-------------------------------------------------------------------------
-- Only show on hover
-- Shared controller for every hover-only element; hover is a shared cursor poll, not OnEnter/OnLeave.
-------------------------------------------------------------------------

local HOVER_FADE_TICK_INTERVAL = 0.04
local HOVER_POLL_TICK_INTERVAL = 0.06

-- Every frame with an installed hover-fade controller, keyed by itself.
local hoverFadeFrames = {}

-- Clamps a hover-fade duration to 0-10s; nil if not a number.
function ACAB:ClampHoverDuration(duration)
	duration = tonumber(duration)

	if not duration then
		return nil
	end

	if duration < 0 then
		duration = 0
	end

	if duration > 10 then
		duration = 10
	end

	return duration
end

-- Writes a flat ACABDB hover-only flag, then re-runs applyFn (the element's own Apply*Position).
function ACAB:SetHoverOnlySetting(field, enabled, applyFn)
	self:EnsureDB()

	ACABDB[field] = enabled and true or false

	applyFn(self)
end

-- Clamps and writes a flat ACABDB hover duration, then re-runs applyFn. Ignores non-numeric input.
function ACAB:SetHoverDurationSetting(field, duration, applyFn)
	self:EnsureDB()

	duration = self:ClampHoverDuration(duration)

	if not duration then
		return
	end

	ACABDB[field] = duration

	applyFn(self)
end

-- True if UIParent-unit point x/y lies inside frame's rect.
local function IsPointOverFrame(x, y, frame)
	local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()

	if not left or not right or not top or not bottom then
		return false
	end

	return x >= left and x <= right and y >= bottom and y <= top
end

local function IsCursorOverFrame(frame)
	local x, y = ACAB:GetCursorPositionUIScale()

	return IsPointOverFrame(x, y, frame)
end

local hoverPollTicker = nil

-- Single shared ticker for every registered hover-only frame, started lazily on first registration.
local function StartHoverPollTicker()
	if hoverPollTicker or not C_Timer or not C_Timer.NewTicker then
		return
	end

	hoverPollTicker = C_Timer.NewTicker(HOVER_POLL_TICK_INTERVAL, function()
		if ACAB:IsEditMode() or ACAB:IsHoverBindMode() then
			return
		end

		local x, y = ACAB:GetCursorPositionUIScale()
		local frame

		for frame in pairs(hoverFadeFrames) do
			if frame.ACABHoverOnlyEnabled then
				local hovering = IsPointOverFrame(x, y, frame)

				if hovering and not frame.ACABHoverOnlyHovering then
					ACAB:CancelHoverFadeTicker(frame)
					frame:SetAlpha(1)
				elseif not hovering and frame.ACABHoverOnlyHovering then
					ACAB:StartHoverFadeTicker(frame, frame.ACABHoverOnlyGetDuration and frame.ACABHoverOnlyGetDuration() or 3)
				end

				frame.ACABHoverOnlyHovering = hovering
			end
		end
	end)
end

-- Cancels frame's running fade ticker, if any.
function ACAB:CancelHoverFadeTicker(frame)
	if frame.ACABHoverFadeTicker then
		frame.ACABHoverFadeTicker:Cancel()
		frame.ACABHoverFadeTicker = nil
	end
end

-- Holds alpha 1 for 4/5 of duration, then fades linearly to 0 (duration <= 0 hides at once).
-- Edit Layout/Hoverbind mode keep alpha 1 while active.
function ACAB:StartHoverFadeTicker(frame, duration)
	self:CancelHoverFadeTicker(frame)

	duration = tonumber(duration) or 0

	if duration <= 0 or not C_Timer or not C_Timer.NewTicker then
		frame:SetAlpha(0)
		return
	end

	local holdEnd = duration * 0.8
	local startTime = GetTime()

	frame:SetAlpha(1)

	frame.ACABHoverFadeTicker = C_Timer.NewTicker(HOVER_FADE_TICK_INTERVAL, function()
		if ACAB:IsEditMode() or ACAB:IsHoverBindMode() then
			frame:SetAlpha(1)
			return
		end

		local elapsed = GetTime() - startTime

		if elapsed >= duration then
			frame:SetAlpha(0)
			ACAB:CancelHoverFadeTicker(frame)
			return
		end

		if elapsed <= holdEnd then
			frame:SetAlpha(1)
		else
			frame:SetAlpha(1 - ((elapsed - holdEnd) / (duration - holdEnd)))
		end
	end)
end

-- Adds `frame` to the shared hover poll (idempotent), starting the poll ticker if needed.
function ACAB:InstallHoverFadeController(frame)
	if frame.ACABHoverFadeInstalled then
		return
	end

	frame.ACABHoverFadeInstalled = true
	hoverFadeFrames[frame] = frame

	StartHoverPollTicker()
end

-- Turns a frame's hover-only mode on/off; getDuration returns its fade duration.
function ACAB:ApplyHoverOnlyState(frame, enabled, getDuration)
	if not frame then
		return
	end

	enabled = enabled and true or false

	frame.ACABHoverOnlyEnabled = enabled
	frame.ACABHoverOnlyGetDuration = getDuration

	if not enabled then
		self:CancelHoverFadeTicker(frame)
		frame:SetAlpha(1)
		return
	end

	frame:EnableMouse(true)

	self:InstallHoverFadeController(frame)

	-- Seeds hover state so enabling under the cursor doesn't hide the frame.
	frame.ACABHoverOnlyHovering = IsCursorOverFrame(frame)

	if not frame.ACABHoverFadeTicker then
		if self:IsEditMode() or self:IsHoverBindMode() or frame.ACABHoverOnlyHovering then
			frame:SetAlpha(1)
		else
			frame:SetAlpha(0)
		end
	end
end

-- Forces every hover-fade frame to alpha 1 (while editing/binding).
function ACAB:ForceHoverFadeFramesVisible()
	local frame

	for frame in pairs(hoverFadeFrames) do
		frame:SetAlpha(1)
	end
end

-- Undoes ForceHoverFadeFramesVisible: re-hides idle, un-hovered hover-only frames.
function ACAB:RestoreHoverFadeFrames()
	if self:IsEditMode() or self:IsHoverBindMode() then
		return
	end

	local frame

	for frame in pairs(hoverFadeFrames) do
		if frame.ACABHoverOnlyEnabled and not frame.ACABHoverFadeTicker and not frame.ACABHoverOnlyHovering then
			frame:SetAlpha(0)
		end
	end
end

-------------------------------------------------------------------------
-- Lock Action Bars: the plain global LOCK_ACTIONBAR ("0"/"1"), not a CVar
-------------------------------------------------------------------------

function ACAB:IsLockActionBars()
	return LOCK_ACTIONBAR == "1"
end

function ACAB:SetLockActionBars(enabled)
	LOCK_ACTIONBAR = enabled and "1" or "0"
end

function ACAB:ToggleLockActionBars()
	self:SetLockActionBars(not self:IsLockActionBars())
	self:Print(self:IsLockActionBars()
		and "Action bars locked - dragging a filled button no longer picks up its action."
		or "Action bars unlocked.")
end

-------------------------------------------------------------------------
-- Load
-------------------------------------------------------------------------

-- Settle polls: native frame positions aren't final right after PLAYER_ENTERING_WORLD.
local SETTLE_POLL_INTERVAL = 0.1
local SETTLE_STABLE_READS_REQUIRED = 2
local SETTLE_TIMEOUT = 3

-- Polls ActionButton1 until its position holds steady (or SETTLE_TIMEOUT), then
-- calls callback(earlyLeft, earlyTop, settledLeft, settledTop, elapsed).
function ACAB:WaitForNativeBarSettle(callback)
	local ref = getglobal("ActionButton1")

	if not ref or not C_Timer or not C_Timer.NewTicker then
		callback(nil, nil, nil, nil, 0)
		return
	end

	local earlyLeft, earlyTop = ref:GetLeft(), ref:GetTop()
	local lastLeft, lastTop = earlyLeft, earlyTop
	local stableCount = 0
	local elapsed = 0

	local ticker
	ticker = C_Timer.NewTicker(SETTLE_POLL_INTERVAL, function()
		elapsed = elapsed + SETTLE_POLL_INTERVAL

		local left, top = ref:GetLeft(), ref:GetTop()

		if left and top and lastLeft and lastTop
			and left == lastLeft and top == lastTop then
			stableCount = stableCount + 1
		else
			stableCount = 0
		end

		lastLeft, lastTop = left, top

		local settled = stableCount >= SETTLE_STABLE_READS_REQUIRED
		local timedOut = elapsed >= SETTLE_TIMEOUT

		if settled or timedOut then
			ticker:Cancel()

			if timedOut and not settled then
				ACAB:Print(
					"WARNING: native action bar position did not settle within " ..
					tostring(SETTLE_TIMEOUT) .. "s - proceeding with its current, " ..
					"possibly not-yet-final position."
				)
			end

			callback(earlyLeft, earlyTop, lastLeft, lastTop, elapsed)
		end
	end)
end

-- Like WaitForNativeBarSettle, but polls frame.ACABSwallowedAnchor; callback gets the settled anchor or nil.
local function WaitForWrappedFrameAnchorSettle(frame, callback)
	if not frame or not C_Timer or not C_Timer.NewTicker then
		callback(nil)
		return
	end

	local function SameAnchor(a, b)
		if not a or not b then
			return false
		end

		return a.point == b.point and a.relativeTo == b.relativeTo
			and a.relativePoint == b.relativePoint and a.x == b.x and a.y == b.y
	end

	local lastAnchor = frame.ACABSwallowedAnchor
	local stableCount = 0
	local elapsed = 0

	local ticker
	ticker = C_Timer.NewTicker(SETTLE_POLL_INTERVAL, function()
		elapsed = elapsed + SETTLE_POLL_INTERVAL

		local anchor = frame.ACABSwallowedAnchor

		if anchor and SameAnchor(anchor, lastAnchor) then
			stableCount = stableCount + 1
		else
			stableCount = 0
		end

		lastAnchor = anchor

		local settled = anchor and stableCount >= SETTLE_STABLE_READS_REQUIRED
		local timedOut = elapsed >= SETTLE_TIMEOUT

		if settled or timedOut then
			ticker:Cancel()
			callback(settled and lastAnchor or nil)
		end
	end)
end

-- Max px ActionButton1 may drift from Main Bar's captured nativeAnchor before a silent recapture.
local DRIFT_TOLERANCE = 1

-- Post-login drift check poll, stricter than WaitForNativeBarSettle.
local POST_LOGIN_SETTLE_STABLE_READS = 10
local POST_LOGIN_SETTLE_TIMEOUT = 10

-- Copies Bar 3's (or Bar 1's) nativeAnchor.x into Pet Bar's cfg.x, reapplying live if built.
function ACAB:SyncPetBarAnchorX()
	local defaults = ACABDB and ACABDB.defaultBars
	local cfg = defaults and defaults[ACAB.PET_BAR_ID]

	if not cfg or ACABDB.useDefaultLayout == false then
		return
	end

	local bar3Anchor = defaults[3] and defaults[3].nativeAnchor
	local bar1Anchor = defaults[1] and defaults[1].nativeAnchor
	local anchor = bar3Anchor or bar1Anchor

	if not anchor then
		return
	end

	local petNative = ACAB.petBarNativeContainer
	local petStyled = ACAB.bars and ACAB.bars[ACAB.PET_BAR_ID]
	local frame = petNative or petStyled

	-- x is a native left edge: written as TOPLEFT/BOTTOMLEFT, the apply below converts back.
	if frame then
		ACAB:ConvertPositionAnchor(frame, cfg, "TOPLEFT", "BOTTOMLEFT", nil, nil, "TOPLEFT")
		cfg.x = anchor.x
	elseif not ACAB:IsCanonicalPosition(cfg) then
		cfg.point = "TOPLEFT"
		cfg.relativePoint = "BOTTOMLEFT"
		cfg.x = anchor.x
	end

	cfg.nativeAnchor = cfg.nativeAnchor or {}
	cfg.nativeAnchor.point = "TOPLEFT"
	cfg.nativeAnchor.relativePoint = "BOTTOMLEFT"
	cfg.nativeAnchor.x = anchor.x

	if petNative then
		ACAB:ApplyPetBarNativePosition()
	elseif petStyled then
		ACAB:ApplyBarPosition(petStyled)
	end
end

-- Builds the native Pet Bar container once and aligns it to the default layout.
local function SetupPetBarNativeContainer()
	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[ACAB.PET_BAR_ID]

	if not cfg or ACAB.petBarNativeContainer then
		return
	end

	-- must create the container before SyncPetBarAnchorX, which converts a canonical cfg through it
	ACAB:CreatePetBarNativeContainer()
	ACAB:SyncPetBarAnchorX()

	if ACABDB.useDefaultLayout ~= false then
		local bar3Cfg = ACABDB.defaultBars[3]
		ACAB:ReflowPetBarForBar3Toggle(bar3Cfg and bar3Cfg.enabled)
	end
end

-- Recaptures bars 1-5's native anchors if ActionButton1 drifted from Main Bar's; true if it did.
-- WARNING: skip once Main Bar's art moved this session - ActionButton1 would measure the moved spot.
local function VerifyDefaultBarAnchorsSettled()
	if (ACABDB and ACABDB.useDefaultLayout == false) or ACAB.mainBarArtMoved then
		return
	end

	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[1]
	local liveAnchor = cfg and ACAB:CaptureNativeAnchor(1)

	if not cfg or not cfg.nativeAnchor or not liveAnchor then
		return
	end

	if math.abs(liveAnchor.x - cfg.nativeAnchor.x) > DRIFT_TOLERANCE
		or math.abs(liveAnchor.y - cfg.nativeAnchor.y) > DRIFT_TOLERANCE then
		ACAB:RecaptureDefaultBarNativeAnchors()
		return true
	end
end

-- Waits for ActionButton1 to hold steady after login, then runs the drift check.
local function WaitForPostLoginSettleThenVerify()
	local ref = getglobal("ActionButton1")

	if not ref or not C_Timer or not C_Timer.NewTicker then
		VerifyDefaultBarAnchorsSettled()
		return
	end

	local lastLeft, lastTop = ref:GetLeft(), ref:GetTop()
	local stableCount = 0
	local elapsed = 0

	local ticker
	ticker = C_Timer.NewTicker(SETTLE_POLL_INTERVAL, function()
		elapsed = elapsed + SETTLE_POLL_INTERVAL

		local left, top = ref:GetLeft(), ref:GetTop()

		if left and top and lastLeft and lastTop
			and left == lastLeft and top == lastTop then
			stableCount = stableCount + 1
		else
			stableCount = 0
		end

		lastLeft, lastTop = left, top

		if stableCount >= POST_LOGIN_SETTLE_STABLE_READS or elapsed >= POST_LOGIN_SETTLE_TIMEOUT then
			ticker:Cancel()
			VerifyDefaultBarAnchorsSettled()
		end
	end)
end

-- Full login sequence, run once WaitForNativeBarSettle reports the native bars settled. Step order is load-bearing.
function ACAB:RunLoginSequence(earlyLeft, earlyTop, settledLeft, settledTop, waited)
	ACAB:ResolveActiveProfile()

	ACAB:EnsureDB()

	-- Must run before anything moves Main Bar's art (ActionButton1's parent) - native anchors are only measurable until then.
	local recapturedAtLogin = false

	if ACABDB.pendingDefaultBarRecapture then
		ACABDB.pendingDefaultBarRecapture = nil
		ACAB:RecaptureDefaultBarNativeAnchors()
		recapturedAtLogin = true
	else
		recapturedAtLogin = VerifyDefaultBarAnchorsSettled() == true
	end

	-- Must run before CreateFixedSlotDefaultBars/CreateBagBarAndMicroMenu move these frames, or capture reads moved spots.
	ACAB:CaptureKeyRingPositionIfNeeded()
	ACAB:CaptureLatencyBarPositionIfNeeded()
	ACAB:CaptureExpBarPositionIfNeeded()
	ACAB:CaptureCastBarPositionIfNeeded()
	ACAB:CaptureMainBarArtNativeOffsetIfNeeded()

	-- Async: stores Latency Bar/Cast Bar's native anchors once their swallowed anchors settle.
	do
		local function SyncNativeAnchorFromSwallow(frame, dbKey)
			WaitForWrappedFrameAnchorSettle(frame, function(anchor)
				if anchor then
					ACABDB[dbKey] = anchor
				end
			end)
		end

		SyncNativeAnchorFromSwallow(getglobal(ACAB.LATENCY_BAR_FRAME_NAME), "latencyBarNativeAnchor")
		SyncNativeAnchorFromSwallow(getglobal(ACAB.CAST_BAR_FRAME_NAME), "castBarNativeAnchor")
	end

	-- Must run before CreateFixedSlotDefaultBars builds the Stance Bar's button pool.
	ACAB:ApplyStanceBarLiveShape()

	ACAB:CreateAllBars()

	-- Must run before CreateFixedSlotDefaultBars hides bar 2's real buttons and reflows ShapeshiftBarFrame.
	ACAB:CaptureStanceBarNativeGap()

	ACAB:CreateFixedSlotDefaultBars()

	ACAB:ApplyAllDefaultBars()

	ACAB:ApplyGlobalButtonStyle()

	ACAB:ApplyGlobalSpacing()
	ACAB:ApplyGlobalButtonSize()
	ACAB:EnforceMainBarArtSpacing()

	ACAB:CreateStanceBarContainer()

	if ACABDB.useDefaultLayout ~= false then
		local bar2Cfg = ACABDB.defaultBars[2]
		ACAB:ReflowStanceBarForBar2Toggle(bar2Cfg and bar2Cfg.enabled)
	end

	ACAB:CreateBagBarAndMicroMenu()
	SetupPetBarNativeContainer()

	-- The login-start recapture ran before any bar existed - re-derive the bars built off its anchors now.
	if recapturedAtLogin then
		ACAB:ReapplyAfterNativeRecapture()
	end

	ACAB:CreatePageIndicatorContainer()

	ACAB:SetKeyRingEnabled(ACABDB.keyRingEnabled ~= false)

	ACAB:SetKeyRingScale(ACABDB.keyRingScale or 1)
	ACAB:ApplyKeyRingPosition()

	ACAB:SetLatencyBarEnabled(ACABDB.latencyBarEnabled ~= false)
	ACAB:SetLatencyBarScale(ACABDB.latencyBarScale or 1)
	ACAB:ApplyLatencyBarPosition()

	ACAB:SetExpBarEnabled(ACABDB.expBarEnabled ~= false)
	ACAB:SetExpBarScale(ACABDB.expBarScale or 1)
	ACAB:ApplyExpBarPosition()

	ACAB:SetCastBarScale(ACABDB.castBarScale or 1)
	ACAB:ApplyCastBarPosition()

	ACAB:SetTooltipEnabled(ACABDB.tooltipEnabled == true)
	ACAB:SetTooltipScale(ACABDB.tooltipScale or 1)
	ACAB:ApplyTooltipPosition()
	ACAB:HookGameTooltipDefaultAnchor()

	-- Sets Cast Bar's stacked Y now instead of on the first stack-affecting toggle.
	if ACABDB.useDefaultLayout ~= false then
		ACAB:ReflowCastBarForStackToggle()
	end

	ACAB:ApplyExpBarColors()

	ACAB:ApplyBetterExpBarVisual()

	ACAB:ApplyBlizzardArtVisibility()

	-- Must run after every element above has its final shape/scale.
	ACAB:NormalizeAllPositionAnchors()

	-- Must run after Main Bar and every element above are positioned.
	ACAB:ApplyMainBarGroupedElements()

	ACAB:CreateMinimapButton()

	ACAB:Print("Fully initialized! Click the minimap button or use /acab for options.")

	ACAB:CheckForUpdates()

	if ACAB.pendingFirstLoginDialog then
		ACAB.pendingFirstLoginDialog = nil
		ACAB:ShowFirstLoginDialog()
	end

	WaitForPostLoginSettleThenVerify()
end

-------------------------------------------------------------------------
-- Slash commands
-------------------------------------------------------------------------

-- /acab settings <page>: page name -> settings view or bar/element page.
local SETTINGS_PAGE_ALIASES = {
	general = { view = "general" },
	profiles = { view = "profiles" },
	editmode = { view = "editmode" },
	bars = { view = "bars" },

	main = { page = 1 },
	mainbar = { page = 1 },
	["1"] = { page = 1 },
	["2"] = { page = 2 },
	["3"] = { page = 3 },
	["4"] = { page = 4 },
	["5"] = { page = 5 },
	["6"] = { page = ACAB.EXTRA_BAR_ID_START },
	["7"] = { page = ACAB.EXTRA_BAR_ID_START + 1 },
	["8"] = { page = ACAB.EXTRA_BAR_ID_START + 2 },
	["9"] = { page = ACAB.EXTRA_BAR_ID_START + 3 },
	extra1 = { page = ACAB.EXTRA_BAR_ID_START },
	extra2 = { page = ACAB.EXTRA_BAR_ID_START + 1 },
	extra3 = { page = ACAB.EXTRA_BAR_ID_START + 2 },
	extra4 = { page = ACAB.EXTRA_BAR_ID_START + 3 },
	pet = { page = ACAB.PET_BAR_ID },
	petbar = { page = ACAB.PET_BAR_ID },
	stance = { page = ACAB.STANCE_BAR_ID },
	stancebar = { page = ACAB.STANCE_BAR_ID },

	bags = { page = "bagbar" },
	bagbar = { page = "bagbar" },
	keyring = { page = "keyring" },
	keys = { page = "keyring" },
	micro = { page = "micromenu" },
	micromenu = { page = "micromenu" },
	latency = { page = "latencybar" },
	latencybar = { page = "latencybar" },
	xp = { page = "expbar" },
	exp = { page = "expbar" },
	expbar = { page = "expbar" },
	experience = { page = "expbar" },
	cast = { page = "castbar" },
	castbar = { page = "castbar" },
	tooltip = { page = "tooltip" },
}

-- Opens the settings window to a specific page by name (/acab settings <pagename>).
function ACAB:OpenSettingsPageByName(name)
	local target = SETTINGS_PAGE_ALIASES[string.lower(name or "")]

	if not target then
		self:Print("Unknown settings page \"" .. tostring(name) .. "\". Type " .. ColorKeyName("/acab help") .. " for a list.")
		return
	end

	self:ShowSettingsFrame()

	if target.view == "general" then
		self:ShowGeneralView()
	elseif target.view == "profiles" then
		self:ShowProfilesView()
	elseif target.view == "editmode" then
		self:ShowEditModeView()
	elseif target.view == "bars" then
		self:ShowBarsView()
	elseif target.page then
		self:ShowBarPage(target.page)
	end
end

-- /acab profile with no subcommand: current profile plus usage list.
local function PrintProfileStatus()
	ACAB:Print("Current profile: \"" .. tostring(ACABCharDB and ACABCharDB.activeProfile or ACAB.DEFAULT_PROFILE_NAME) .. "\"")
	ACAB:Print("Available " .. ColorKeyName("/acab profile") .. " parameters:")
	ACAB:Print(ColorKeyName("/acab profile list") .. " - list all profiles in chat")
	ACAB:Print(ColorKeyName("/acab profile select <name>") .. " - switch to another profile")
	ACAB:Print(ColorKeyName("/acab profile add <name>") .. " - create a new profile")
	ACAB:Print(ColorKeyName("/acab profile delete <name>") .. " - delete a profile")
	ACAB:Print(ColorKeyName("/acab profile copy [name]") .. " - copy settings into the current profile from [name], or pick from a dropdown if omitted")
	ACAB:Print(ColorKeyName("/acab profile export") .. " - show the current profile's export string")
	ACAB:Print(ColorKeyName("/acab profile import") .. " - paste an export string into the current profile")
end

local function PrintProfileList()
	local names = ACAB:GetProfileNames()
	local active = ACABCharDB and ACABCharDB.activeProfile or ACAB.DEFAULT_PROFILE_NAME
	local i

	ACAB:Print("Profiles:")

	for i = 1, table.getn(names) do
		local marker = (names[i] == active) and " |cff20ff20(active)|r" or ""
		ACAB:Print("  " .. names[i] .. marker)
	end
end

-- Dispatches /acab profile <subcommand> [name], reusing the Profiles tab's dialogs.
function ACAB:HandleProfileCommand(rest)
	local subcommand, arg = string.match(rest or "", "^(%S*)%s*(.-)$")

	subcommand = string.lower(subcommand or "")

	-- Mirrors the Profiles tab hiding Export/Copy/Import on Default.
	if (subcommand == "copy" or subcommand == "import" or subcommand == "export")
		and self:IsDefaultProfileActive() then
		self:Print("The Default profile cannot be copied, imported or exported. Switch to or create another profile first (" .. ColorKeyName("/acab profile add <name>") .. ").")
		return
	end

	if subcommand == "" then
		PrintProfileStatus()
	elseif subcommand == "list" then
		PrintProfileList()
	elseif subcommand == "select" then
		if arg == "" then
			self:Print("Usage: /acab profile select <name>")
			return
		end

		local ok, reason = self:SwitchProfile(arg)

		if not ok and reason then
			self:Print(reason)
		end
	elseif subcommand == "add" then
		if arg == "" then
			self:Print("Usage: /acab profile add <name>")
			return
		end

		local ok, reason = self:CreateProfile(arg)

		if ok then
			self:SwitchProfile(arg)
		elseif reason then
			self:Print(reason)
		end
	elseif subcommand == "delete" then
		if arg == "" then
			self:Print("Usage: /acab profile delete <name>")
			return
		end

		if arg == self.DEFAULT_PROFILE_NAME then
			self:Print("The Default profile cannot be deleted.")
			return
		end

		if not ACABProfilesDB or not ACABProfilesDB[arg] then
			self:Print("Profile \"" .. arg .. "\" does not exist.")
			return
		end

		local targetName = arg
		local wasActive = (ACABCharDB and ACABCharDB.activeProfile == targetName)

		self:ShowDialog({
			title = "Delete Profile",
			message = "ATTENTION: This action will delete all settings present " ..
				"on profile \"" .. targetName .. "\" and is not reversible.",
			mode = "confirm",
			buttons = {
				{
					text = "Accept",
					onClick = function()
						ACAB:DeleteProfile(targetName)

						if wasActive then
							ReloadUI()
						elseif ACAB.settingsFrame and ACAB.settingsFrame.profilesPanel then
							ACAB:RefreshProfilesPanel()
						end
					end,
				},
				{ text = "Cancel", onClick = function() end },
			},
		})
	elseif subcommand == "copy" then
		local targetName = (ACABCharDB and ACABCharDB.activeProfile) or self.DEFAULT_PROFILE_NAME

		-- No name: dropdown picker, same as the Profiles tab's "Copy from other profile" button.
		if arg == "" then
			self:ShowCopyProfileDialog(targetName)
			return
		end

		if not ACABProfilesDB or not ACABProfilesDB[arg] then
			self:Print("Profile \"" .. arg .. "\" does not exist.")
			return
		end

		if arg == targetName then
			self:Print("Cannot copy a profile into itself.")
			return
		end

		self:ShowCopyProfileDialog(targetName, arg)
	elseif subcommand == "export" then
		self:ShowExportProfileDialog()
	elseif subcommand == "import" then
		self:ShowImportProfileDialog()
	else
		self:Print("Unknown profile command \"" .. subcommand .. "\". Type " .. ColorKeyName("/acab profile") .. " for a list.")
	end
end

local function PrintCommandHelp()
	ACAB:Print("Available " .. ColorKeyName("/acab") .. " commands:")
	ACAB:Print(ColorKeyName("/acab") .. " - toggle the Settings window")
	ACAB:Print(ColorKeyName("/acab menu") .. " - open the minimap right-click menu")
	ACAB:Print(ColorKeyName("/acab edit") .. " - toggle Configure Layout mode")
	ACAB:Print(ColorKeyName("/acab bind") .. " - toggle Hoverbind keybind mode")
	ACAB:Print(ColorKeyName("/acab settings <page>") .. " - jump straight to a settings page")
	ACAB:Print("  pages: general, bars, profiles, editmode, main, 1-9/extra1-4, pet, stance, bags, keyring, micro, latency, exp, cast, tooltip")
	ACAB:Print(ColorKeyName("/acab profile") .. " - show current profile and profile commands")
	ACAB:Print(ColorKeyName("/acab recapture") .. " - force a fresh capture of default bar native anchors")
	ACAB:Print(ColorKeyName("/acab version") .. " - show the installed addon version")
	ACAB:Print(ColorKeyName("/acab help") .. " - show this list")
end

-- /acab dispatcher; PrintCommandHelp lists every command.
SLASH_ACAB1 = "/acab"
SlashCmdList["ACAB"] = function(msg)
	msg = msg or ""

	local command, rest = string.match(msg, "^(%S*)%s*(.-)$")
	command = string.lower(command or "")

	if command == "" then
		ACAB:ToggleSettingsFrame()
	elseif command == "menu" then
		ACAB:ToggleMainMenu()
	elseif command == "edit" then
		ACAB:ToggleEditMode()
	elseif command == "bind" then
		ACAB:ToggleHoverBindMode()
	elseif command == "settings" then
		if rest == "" then
			ACAB:ShowSettingsFrame()
		else
			ACAB:OpenSettingsPageByName(rest)
		end
	elseif command == "profile" then
		ACAB:HandleProfileCommand(rest)
	elseif command == "recapture" then
		-- Once Main Bar's art moved ActionButton1 this session, only the next login can measure native.
		if ACAB.mainBarArtMoved then
			ACABDB.pendingDefaultBarRecapture = true
			ACAB:Print("Default bar positions will be recaptured on your next /reload.")
		else
			ACAB:RecaptureDefaultBarNativeAnchors()
		end

		ACAB:RecaptureWrappedNativeFrameAnchors()
	elseif command == "version" then
		ACAB:Print("Version " .. ACAB.currentVersion)
	elseif command == "help" then
		PrintCommandHelp()
	else
		ACAB:Print("Unknown command \"" .. msg .. "\". Type " .. ColorKeyName("/acab help") .. " for a list.")
	end
end
