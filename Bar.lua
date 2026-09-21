-- Bar.lua
-- Multi-bar grid engine backed by the action-slot pool.
-- Bar config: id, point, relativePoint, x, y, cols, rows, buttonSize, slotStart, buttonCount.
-- Bar IDs are persistent identities, not array indices.

local ACAB = AlternativeClassicActionBars

ACAB.bars = {}

-------------------------------------------------------------------------
-- PixelUtil wrappers
-------------------------------------------------------------------------

local function PixelSetPoint(region, ...)
	if PixelUtil and PixelUtil.SetPoint then
		PixelUtil.SetPoint(region, unpack(arg))
	else
		region:SetPoint(unpack(arg))
	end
end

local function PixelSetSize(region, width, height)
	if PixelUtil and PixelUtil.SetSize then
		PixelUtil.SetSize(region, width, height)
	else
		region:SetWidth(width)
		region:SetHeight(height)
	end
end

-------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------

-- Calls fn(barId, bar) for every created bar.
function ACAB:ForEachBar(fn)
	local barId
	local bar

	for barId, bar in pairs(self.bars) do
		if bar then
			fn(barId, bar)
		end
	end
end

-- cfg.spacing may be absent on old saves; default to 0.
local function BarFrameSize(cfg)
	local spacing = cfg.spacing or 0

	local width = (cfg.buttonSize * cfg.cols) + ((cfg.cols - 1) * spacing)
	local height = (cfg.buttonSize * cfg.rows) + ((cfg.rows - 1) * spacing)

	return width, height
end

-- Converts a 1-based button index into a 0-based column/row (no % in Lua 5.0).
local function ButtonIndexToGridPos(index, cols)
	local i = index - 1
	local row = math.floor(i / cols)
	local col = i - (row * cols)
	return col, row
end

-------------------------------------------------------------------------
-- Position
-------------------------------------------------------------------------

function ACAB:ApplyBarPosition(bar)
	if not bar or not bar.config then
		return
	end

	local cfg = bar.config

	bar:ClearAllPoints()

	PixelSetPoint(
		bar,
		cfg.point or "TOPLEFT",
		UIParent,
		cfg.relativePoint or "TOPLEFT",
		cfg.x or 0,
		cfg.y or 0
	)

	-- Main Bar's Blizzard art (background + gryphons) rides along, anchored to this frame.
	if cfg.id == 1 and self.ApplyMainBarArtPosition then
		self:ApplyMainBarArtPosition()
	end
end

-------------------------------------------------------------------------
-- Button layout
-------------------------------------------------------------------------

function ACAB:LayoutButtons(bar)
	if not bar or not bar.buttons or not bar.config then
		return
	end

	local cfg = bar.config
	-- cfg.spacing may be absent on old saves; default to 0.
	local spacing = cfg.spacing or 0
	local i

	-- Pet Bar condense: compacts filled slots into sequential grid cells; suspended during edit mode/action-grid preview.
	local condensePet = cfg.isPetBar and self:ShouldCondensePetBarSlots()
		and not self:IsEditMode() and not self.isShowingActionGrid

	local compactIndex = 0

	for i = 1, table.getn(bar.buttons) do
		local btn = bar.buttons[i]

		if btn then
			local layoutIndex = i

			if condensePet then
				if btn.slotVisible and btn:IsSlotFilled() then
					compactIndex = compactIndex + 1
					layoutIndex = compactIndex
				else
					-- Skips this cell; UpdateGridVisibility hides slots condensed out.
					layoutIndex = nil
				end
			end

			if layoutIndex then
				local col, row = ButtonIndexToGridPos(layoutIndex, cfg.cols)

				local xOff = col * (cfg.buttonSize + spacing)
				local yOff = -row * (cfg.buttonSize + spacing)

				btn:ClearAllPoints()
				PixelSetPoint(
					btn,
					"TOPLEFT",
					bar,
					"TOPLEFT",
					xOff,
					yOff
				)
			end
		end
	end
end

-------------------------------------------------------------------------
-- Bar-level edit-mode overlay
--
-- One overlay per bar owns drag/right-click-settings/scroll-resize during
-- edit mode, at TOOLTIP strata so it catches clicks over gaps between
-- hidden pool slots. Inert outside edit mode.
-------------------------------------------------------------------------

local barOverlays = {}

-- Expands `overlay` past `bar`'s frame bounds via GetElementVisualInset so the
-- hitbox reaches the border's outer edge. Re-callable: insets can change after creation.
local function ApplyBarOverlayInsetAnchor(bar, overlay)
	overlay:ClearAllPoints()

	local insetLeft, insetRight, insetTop, insetBottom = ACAB:GetElementVisualInset(bar)

	if insetLeft ~= 0 or insetRight ~= 0 or insetTop ~= 0 or insetBottom ~= 0 then
		overlay:SetPoint("TOPLEFT", bar, "TOPLEFT", -insetLeft, insetTop)
		overlay:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", insetRight, -insetBottom)
	else
		overlay:SetAllPoints(bar)
	end
end

-- Public so DefaultBars.lua's Modern Layout geometry can measure a bar's
-- real inset-expanded footprint via ACAB:GetElementRealEdges(overlay).
function ACAB:EnsureBarOverlay(bar)
	local overlay = barOverlays[bar]

	if overlay then
		ApplyBarOverlayInsetAnchor(bar, overlay)
		return overlay
	end

	overlay = CreateFrame(
		"Frame",
		"ACABBarOverlay" .. tostring(bar.config.id),
		bar
	)

	-- Starts inert at HIGH strata/bar's frame level; ApplyEditModeVisual elevates during edit mode.
	overlay:SetFrameStrata("HIGH")
	overlay:SetFrameLevel(bar:GetFrameLevel())

	ApplyBarOverlayInsetAnchor(bar, overlay)

	local tex = overlay:CreateTexture(nil, "OVERLAY")
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetVertexColor(0.35, 0.65, 1.0, 0.45)
	tex:SetAllPoints(overlay)

	-- Hover border: transparent edge toggled by OnEnter/OnLeave below.
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

	-- Centered element-name label, shown/hidden with the overlay.
	local nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	nameText:SetText(ACAB:GetBarDisplayName(bar.config.id))

	-- RegisterForDrag set once; EnableMouse/strata toggle per edit-mode state in ApplyEditModeVisual.
	overlay:RegisterForDrag("LeftButton")
	overlay:SetScript("OnDragStart", function()
		ACAB:StartBarDrag(bar)
	end)
	overlay:SetScript("OnDragStop", function()
		ACAB:StopBarDrag(bar)
	end)

	-- Right-click opens bar settings; overlay covers the real buttons while mouse-enabled.
	overlay:SetScript("OnMouseUp", function()
		if arg1 == "RightButton" then
			ACAB:OpenBarSettings(bar)
		end
	end)

	-- Scroll wheel resizes, covering the whole overlay like drag-to-move.
	overlay:EnableMouseWheel(true)
	overlay:SetScript("OnMouseWheel", function()
		if not ACAB:IsEditMode() then
			return
		end

		local barId = bar.config.id

		if ACAB:IsDefaultBarFamilyId(barId) and
			ACABDB and ACABDB.useDefaultLayout ~= false then
			return
		end

		local delta = arg1 or 0
		local step = 2

		ACAB:SetBarButtonSize(bar, bar.config.buttonSize + (delta * step))
	end)

	overlay:EnableMouse(false)
	overlay:Hide()

	barOverlays[bar] = overlay

	return overlay
end

-------------------------------------------------------------------------
-- Edit mode visuals
-------------------------------------------------------------------------

function ACAB:ApplyEditModeVisual()
	local editMode = self:IsEditMode()

	self:ForEachBar(function(barId, bar)
		-- Default-bar-family bars (1-5, Pet Bar) drag individually only when edit mode is on and useDefaultLayout is false.
		local isDefaultBar1to5 = ACAB:IsDefaultBarFamilyId(barId)

		local canEdit = editMode

		if isDefaultBar1to5 then
			canEdit = editMode and ACABDB and ACABDB.useDefaultLayout == false
		end

		-- No per-button edit-mode tint; the bar-level overlay hitbox tint below is the only one.
		if bar.buttons then
			local i

			for i = 1, table.getn(bar.buttons) do
				local btn = bar.buttons[i]

				if btn then
					-- Re-evaluate Show/Hide immediately on edit-mode toggle.
					btn:UpdateGridVisibility()
				end
			end

			-- Re-flow positions: Pet Bar's condensed layout suspends itself during edit mode.
			self:LayoutButtons(bar)
		end

		-- Bar-level overlay owns edit-mode interaction while canEdit is true, otherwise inert.
		if bar then
			local overlay = self:EnsureBarOverlay(bar)

			overlay:EnableMouse(canEdit and true or false)

			if canEdit then
				overlay:SetFrameStrata("TOOLTIP")
				overlay:Show()

				-- Reset hover border to invisible in case OnLeave never fired last time.
				overlay:SetBackdropBorderColor(0, 0, 0, 0)
			else
				overlay:SetFrameStrata("HIGH")
				overlay:Hide()
			end
		end
	end)

	-- Also refreshes DefaultBars.lua's own overlays.
	if self.ApplyDefaultLayoutEditVisual then
		self:ApplyDefaultLayoutEditVisual()
	end

	self:ApplyLayoutGridVisual()

	-- Keeps Core.lua's ESC-to-exit keybinding swap in sync with edit mode's on/off state.
	if editMode then
		self:EnableEditModeEscapeBinding()
	else
		self:DisableEditModeEscapeBinding()
	end
end

-------------------------------------------------------------------------
-- Layout grid overlay (Edit Layout mode)
--
-- Reference grid spanning the screen at ACAB:GetLayoutGridSpacing(), center
-- line highlighted. Purely visual; ACABDB.snapToGrid controls drag behavior
-- separately. Ctrl temporarily flips ACABDB.showLayoutGrid via a poll ticker.
-------------------------------------------------------------------------

local LAYOUT_GRID_LINE_COLOR = { 0.4, 0.75, 1.0, 0.35 }
local LAYOUT_GRID_CENTER_COLOR = { 0.05, 0.25, 0.65, 0.9 }
local LAYOUT_GRID_LINE_THICKNESS = 1
local LAYOUT_GRID_CENTER_THICKNESS = 3
local LAYOUT_GRID_CTRL_POLL_INTERVAL = 0.05

-- Extra grid-line steps drawn past the screen edge as a rounding safety margin.
local LAYOUT_GRID_EDGE_OVERSHOOT_LINES = 5

local layoutGridFrame
local layoutGridVLines = {}
local layoutGridHLines = {}
local layoutGridCtrlTicker

local function EnsureLayoutGridFrame()
	if layoutGridFrame then
		return layoutGridFrame
	end

	layoutGridFrame = CreateFrame("Frame", "ACABLayoutGridFrame", UIParent)
	layoutGridFrame:SetAllPoints(UIParent)
	layoutGridFrame:SetFrameStrata("BACKGROUND")
	layoutGridFrame:EnableMouse(false)
	layoutGridFrame:Hide()

	return layoutGridFrame
end

-- Hides pooled line textures beyond `count`, keeping them for reuse.
local function HideLinesFrom(pool, count)
	local i

	for i = count + 1, table.getn(pool) do
		pool[i]:Hide()
	end
end

local function GetOrCreatePoolLine(pool, index, frame)
	local line = pool[index]

	if not line then
		line = frame:CreateTexture(nil, "BACKGROUND")
		line:SetTexture("Interface\\Buttons\\WHITE8X8")
		pool[index] = line
	end

	return line
end

-- Rebuilds every grid line texture from scratch at the current
-- ACAB:GetLayoutGridSpacing(). Called whenever Edit Layout mode is entered
-- and whenever the border style/baseline button size changes while it's
-- already active (ACAB:ApplyGlobalButtonStyle).
function ACAB:RebuildLayoutGrid()
	local frame = EnsureLayoutGridFrame()

	-- ACAB:GetLayoutGridSpacing() is a LOCAL unit, same space this frame
	-- shares with every other default-scale frame - used directly as a
	-- SetPoint offset with no scale conversion (dividing by
	-- GetEffectiveScale() here would double-convert and shrink the grid).
	local spacing = self:GetLayoutGridSpacing()

	if not spacing or spacing <= 0 then
		HideLinesFrom(layoutGridVLines, 0)
		HideLinesFrom(layoutGridHLines, 0)
		return
	end

	-- Reads UIParent's dimensions, not this overlay's - frame rects resolve lazily here, UIParent's is always resolved.
	local width = UIParent:GetWidth()
	local height = UIParent:GetHeight()

	if not width or not height or width <= 0 or height <= 0 then
		return
	end

	-- math.ceil so the last line covers the visible edge, plus an overshoot buffer.
	local halfCountX = math.ceil((width / 2) / spacing) + LAYOUT_GRID_EDGE_OVERSHOOT_LINES
	local halfCountY = math.ceil((height / 2) / spacing) + LAYOUT_GRID_EDGE_OVERSHOOT_LINES

	local vCount = 0
	local k

	for k = -halfCountX, halfCountX do
		vCount = vCount + 1

		local line = GetOrCreatePoolLine(layoutGridVLines, vCount, frame)
		local isCenter = (k == 0)
		local color = isCenter and LAYOUT_GRID_CENTER_COLOR or LAYOUT_GRID_LINE_COLOR
		local thickness = isCenter and LAYOUT_GRID_CENTER_THICKNESS or LAYOUT_GRID_LINE_THICKNESS

		line:ClearAllPoints()
		line:SetWidth(thickness)
		line:SetPoint("TOP", frame, "TOP", k * spacing, 0)
		line:SetPoint("BOTTOM", frame, "BOTTOM", k * spacing, 0)
		line:SetVertexColor(color[1], color[2], color[3], color[4])
		line:Show()
	end

	HideLinesFrom(layoutGridVLines, vCount)

	local hCount = 0

	for k = -halfCountY, halfCountY do
		hCount = hCount + 1

		local line = GetOrCreatePoolLine(layoutGridHLines, hCount, frame)
		local isCenter = (k == 0)
		local color = isCenter and LAYOUT_GRID_CENTER_COLOR or LAYOUT_GRID_LINE_COLOR
		local thickness = isCenter and LAYOUT_GRID_CENTER_THICKNESS or LAYOUT_GRID_LINE_THICKNESS

		line:ClearAllPoints()
		line:SetHeight(thickness)
		line:SetPoint("LEFT", frame, "LEFT", 0, k * spacing)
		line:SetPoint("RIGHT", frame, "RIGHT", 0, k * spacing)
		line:SetVertexColor(color[1], color[2], color[3], color[4])
		line:Show()
	end

	HideLinesFrom(layoutGridHLines, hCount)
end

-- True when the grid should be on screen: Edit Layout mode on, showLayoutGrid XOR'd with Ctrl held.
local function ComputeLayoutGridShouldShow()
	if not ACAB:IsEditMode() then
		return false
	end

	local base = ACABDB and ACABDB.showLayoutGrid or false
	local ctrlHeld = IsControlKeyDown and IsControlKeyDown()

	if ctrlHeld then
		return not base
	end

	return base
end

function ACAB:RefreshLayoutGridVisibility()
	local frame = EnsureLayoutGridFrame()

	if ComputeLayoutGridShouldShow() then
		frame:Show()
	else
		frame:Hide()
	end
end

-- (Re)builds the grid and starts/stops the Ctrl-poll ticker with edit mode.
function ACAB:ApplyLayoutGridVisual()
	local editMode = self:IsEditMode()

	if layoutGridCtrlTicker then
		layoutGridCtrlTicker:Cancel()
		layoutGridCtrlTicker = nil
	end

	if editMode then
		self:RebuildLayoutGrid()
		self:RefreshLayoutGridVisibility()

		if C_Timer and C_Timer.NewTicker then
			layoutGridCtrlTicker = C_Timer.NewTicker(LAYOUT_GRID_CTRL_POLL_INTERVAL, function()
				if ACAB:IsEditMode() then
					ACAB:RefreshLayoutGridVisibility()
				end
			end)
		end
	else
		EnsureLayoutGridFrame():Hide()
	end
end

-------------------------------------------------------------------------
-- Button size
-------------------------------------------------------------------------

function ACAB:SetBarButtonSize(bar, newSize)
	if not bar or not bar.config then
		return
	end

	newSize = tonumber(newSize)

	if not newSize then
		return
	end

	-- Restricted to even values, matching the 2px mouse-wheel/Settings UI step.
	newSize = math.floor(newSize / 2) * 2

	if newSize < 16 then
		newSize = 16
	end

	if newSize > 64 then
		newSize = 64
	end

	bar.config.buttonSize = newSize

	local i

	for i = 1, table.getn(bar.buttons) do
		local btn = bar.buttons[i]

		if btn then
			btn:ApplySize(newSize)
		end
	end

	local barW, barH = BarFrameSize(bar.config)

	PixelSetSize(bar, barW, barH)

	self:LayoutButtons(bar)

	-- Every buttonSize-changing path funnels through here, so this is the single place that rebuilds the grid,
	-- and the single place Main Bar's Blizzard art (background + gryphons) rescales to match.
	if bar.config.id == 1 then
		if self:IsEditMode() then
			self:RebuildLayoutGrid()
		end

		if self.ApplyMainBarArtPosition then
			self:ApplyMainBarArtPosition()
		end
	end
end

-------------------------------------------------------------------------
-- Spacing (true custom bars, id 6+)
--
-- Mirrors DefaultBars.lua's SetDefaultBarSpacing (clamp, write, reapply);
-- writes directly to bar.config since a custom bar's cfg IS its own
-- ACABDB.bars[] entry.
-------------------------------------------------------------------------

function ACAB:SetBarSpacing(bar, spacing)
	if not bar or not bar.config then
		return
	end

	spacing = tonumber(spacing)

	if not spacing then
		return
	end

	spacing = math.floor(spacing + 0.5)

	-- Vanilla style has a minimum spacing floor; modern has none.
	local minSpacing = self:IsVanillaBorderStyle() and self.VANILLA_SPACING_FLOOR or 0

	if spacing < minSpacing then
		spacing = minSpacing
	end

	if spacing > 20 then
		spacing = 20
	end

	bar.config.spacing = spacing

	self:ApplyBarShape(bar)

	-- ACAB:GetLayoutGridSpacing includes Main Bar's configured spacing, not just buttonSize.
	if bar.config.id == 1 and self:IsEditMode() then
		self:RebuildLayoutGrid()
	end
end

-------------------------------------------------------------------------
-- Only show on hover (Settings.lua's per-bar checkbox/slider)
-------------------------------------------------------------------------

function ACAB:SetBarHoverOnly(bar, enabled)
	if not bar or not bar.config then
		return
	end

	bar.config.hoverOnly = enabled and true or false

	self:ApplyBarShape(bar)
end

function ACAB:SetBarHoverDuration(bar, duration)
	if not bar or not bar.config then
		return
	end

	duration = self:ClampHoverDuration(duration)

	if not duration then
		return
	end

	bar.config.hoverDuration = duration

	self:ApplyBarShape(bar)
end

-------------------------------------------------------------------------
-- Global border/spacing style sweep (General tab's modernBorderStyle /
-- useDefaultLayout's forced-vanilla lock)
--
-- Re-styles every bar's buttons for the current global style. On a real
-- style transition it also shifts buttonSize by MODERN_BUTTON_SIZE_DELTA,
-- nudges position to compensate, and shifts spacing the opposite way so
-- buttonSize + spacing stays visually constant.
-------------------------------------------------------------------------

function ACAB:ApplyGlobalButtonStyle()
	if not self.bars then
		return
	end

	local vanilla = self:IsVanillaBorderStyle()

	if ACABDB.lastAppliedVanillaStyle == nil then
		ACABDB.lastAppliedVanillaStyle = vanilla
	elseif ACABDB.lastAppliedVanillaStyle ~= vanilla then
		local delta = vanilla and -self.MODERN_BUTTON_SIZE_DELTA or self.MODERN_BUTTON_SIZE_DELTA

		-- posShift compensates for the size delta being anchor-relative, not centered.
		local posShift = self.MODERN_BUTTON_SIZE_POSITION_SHIFT
		local dx = vanilla and posShift or -posShift
		local dy = vanilla and -posShift or posShift

		-- Opposite sign to the buttonSize delta above.
		local spacingDelta = vanilla and self.VANILLA_SPACING_FLOOR or -self.VANILLA_SPACING_FLOOR

		-- Skip bars 1-5 when useDefaultLayout just reset them, or the delta double-shifts them.
		local skipDefaultBars = ACABDB.useDefaultLayout ~= false

		self:ForEachBar(function(barId, bar)
			if bar.config and bar.config.buttonSize and
				not (skipDefaultBars and ACAB:IsDefaultBarFamilyId(barId)) then
				self:SetBarButtonSize(bar, bar.config.buttonSize + delta)
				self:SetBarPosition(bar, (bar.config.x or 0) + dx, (bar.config.y or 0) + dy)
				self:SetBarSpacing(bar, (bar.config.spacing or 0) + spacingDelta)
			end
		end)

		-- Global buttonSize override gets the same shift, then re-applies to stay authoritative.
		if ACABDB.globalButtonSizeEnabled and ACABDB.globalButtonSizeValue then
			ACABDB.globalButtonSizeValue = ACABDB.globalButtonSizeValue + delta
			self:ApplyGlobalButtonSize()
		end

		ACABDB.lastAppliedVanillaStyle = vanilla
	end

	self:ForEachBar(function(barId, bar)
		if bar.config then
			local i

			for i = 1, table.getn(bar.buttons) do
				local btn = bar.buttons[i]

				if btn and btn.ApplyBorderStyle then
					btn:ApplyBorderStyle()
				end
			end
		end
	end)

	-- Stance Bar is a chain-anchored container of real Blizzard buttons,
	-- not one of self.bars above - swept separately via its own
	-- DefaultBars.lua-owned border-style function.
	if self.ApplyStanceBarBorderStyle then
		self:ApplyStanceBarBorderStyle()
	end

	-- ACAB:GetLayoutGridSpacing() tracks this same border style/baseline
	-- size - rebuild the layout grid immediately if Edit Layout mode is
	-- currently active, instead of leaving it stale until next toggle.
	if self:IsEditMode() then
		self:RebuildLayoutGrid()
	end
end

-------------------------------------------------------------------------
-- Global spacing/button-size overrides (General tab's globalSpacingEnabled/
-- globalButtonSizeEnabled)
--
-- While enabled, the General-tab slider drives every bar except ones
-- unlocked via their own lock icon (cfg.spacingUnlocked/buttonSizeUnlocked).
-- No-op while disabled or while useDefaultLayout owns bars 1-5.
-------------------------------------------------------------------------

function ACAB:ApplyGlobalSpacing()
	if not (self.bars and ACABDB.globalSpacingEnabled) or
		ACABDB.useDefaultLayout ~= false then
		return
	end

	self:ForEachBar(function(barId, bar)
		if bar.config and not bar.config.spacingUnlocked then
			self:ApplyGlobalSpacingToBar(bar)
		end
	end)
end

function ACAB:ApplyGlobalButtonSize()
	if not (self.bars and ACABDB.globalButtonSizeEnabled) or
		ACABDB.useDefaultLayout ~= false then
		return
	end

	self:ForEachBar(function(barId, bar)
		if bar.config and not bar.config.buttonSizeUnlocked then
			self:ApplyGlobalButtonSizeToBar(bar)
		end
	end)
end

-- Applies the current global Spacing value to a single bar, ignoring its lock state.
function ACAB:ApplyGlobalSpacingToBar(bar)
	if not (bar and bar.config and ACABDB.globalSpacingEnabled) or
		ACABDB.useDefaultLayout ~= false then
		return
	end

	-- Vanilla-only floor, see SetBarSpacing.
	local floor = self:IsVanillaBorderStyle() and self.VANILLA_SPACING_FLOOR or 0
	local real = (ACABDB.globalSpacingValue or 0) + floor

	self:SetBarSpacing(bar, real)
end

-- Mirrors ApplyGlobalSpacingToBar exactly, for Button Size.
function ACAB:ApplyGlobalButtonSizeToBar(bar)
	if not (bar and bar.config and ACABDB.globalButtonSizeEnabled) or
		ACABDB.useDefaultLayout ~= false then
		return
	end

	local size = ACABDB.globalButtonSizeValue or self.BUTTON_SIZE

	self:SetBarButtonSize(bar, size)
end

-------------------------------------------------------------------------
-- Apply position directly from settings
-------------------------------------------------------------------------

function ACAB:SetBarPosition(bar, x, y)
	if not bar or not bar.config then
		return
	end

	x = tonumber(x)
	y = tonumber(y)

	if not x or not y then
		return
	end

	bar.config.x = x
	bar.config.y = y

	self:ApplyBarPosition(bar)

	-- Manual X/Y write: clear Extra Bar 1/2's "still at default position" flag and resettle dependants.
	if self:IsExtraBarId(bar.config.id) and bar.config.usesDefaultPosition ~= false then
		bar.config.usesDefaultPosition = false

		if ACABDB.useDefaultLayout ~= false then
			self:ReflowExtraBarDependants(bar.config.id)
		end
	end
end

-------------------------------------------------------------------------
-- Apply layout configuration
--
-- buttonCount can be smaller than cols*rows; ApplyBarShape shows/hides pool
-- slots to match. Grid presets total at most MAX_BAR_BUTTONS (12).
-------------------------------------------------------------------------

function ACAB:SetBarLayout(bar, cols, rows)
	if not bar or not bar.config then
		return false
	end

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

	if cols * rows > self.MAX_BAR_BUTTONS then
		self:Print("Bar " .. tostring(bar.config.id) ..
			" layout cannot exceed " .. tostring(self.MAX_BAR_BUTTONS) ..
			" buttons.")
		return false
	end

	bar.config.cols = cols
	bar.config.rows = rows

	-- Clamps buttonCount down when the new grid has fewer cells; growing
	-- the grid back out does not restore a previously reduced buttonCount.
	local maxButtons = cols * rows
	local currentCount = bar.config.buttonCount or maxButtons

	if currentCount > maxButtons then
		bar.config.buttonCount = maxButtons
	end

	self:ApplyBarShape(bar)

	return true
end

-------------------------------------------------------------------------
-- Button count
--
-- Lets a custom bar show fewer than cols*rows buttons. Never resizes the
-- button pool itself - ApplyBarShape shows/hides existing pool slots.
-------------------------------------------------------------------------

function ACAB:SetBarButtonCount(bar, count)
	if not bar or not bar.config then
		return false
	end

	count = tonumber(count)

	if not count then
		return false
	end

	count = math.floor(count)

	local maxButtons = bar.config.cols * bar.config.rows

	if count < 1 then
		count = 1
	end

	if count > maxButtons then
		count = maxButtons
	end

	bar.config.buttonCount = count

	self:ApplyBarShape(bar)

	return true
end

-------------------------------------------------------------------------
-- Slot start
-------------------------------------------------------------------------

-- Returns true when a bar currently occupies a given action slot.

function ACAB:IsActionSlotUsed(slot, ignoredBarId)
	local i

	for i = 1, table.getn(ACABDB.bars) do
		local cfg = ACABDB.bars[i]

		if cfg and cfg.id ~= ignoredBarId then
			local count = (cfg.cols or 0) * (cfg.rows or 0)
			local first = cfg.slotStart
			local last = first and (first + count - 1)

			if first and last then
				if slot >= first and slot <= last then
					return true
				end
			end
		end
	end

	return false
end

-- Checks whether a complete contiguous slot range is free.

function ACAB:IsActionSlotRangeFree(startSlot, count, ignoredBarId)
	if not startSlot or not count then
		return false
	end

	if startSlot < self.ACTION_SLOT_START then
		return false
	end

	if startSlot + count - 1 > self.ACTION_SLOT_END then
		return false
	end

	local slot

	for slot = startSlot, startSlot + count - 1 do
		if self:IsActionSlotUsed(slot, ignoredBarId) then
			return false
		end
	end

	return true
end

-- Finds the first free contiguous action-slot range of `neededCount` slots,
-- scanning the whole pool so slots freed by a deleted bar can be reused.
-- Prefers page 10 (109-120, unreached by any native paging) first, so
-- pages 7-9 stay free for stance/page content assignment.
local PREFERRED_SLOT_START = 109

function ACAB:GetNextFreeSlotStart(neededCount)
	if not neededCount or neededCount < 1 then
		return nil
	end

	local candidate

	for candidate = PREFERRED_SLOT_START,
		self.ACTION_SLOT_END - neededCount + 1 do

		if self:IsActionSlotRangeFree(candidate, neededCount, nil) then
			return candidate
		end
	end

	for candidate = self.ACTION_SLOT_START,
		PREFERRED_SLOT_START - 1 - neededCount + 1 do

		if self:IsActionSlotRangeFree(candidate, neededCount, nil) then
			return candidate
		end
	end

	return nil
end

-------------------------------------------------------------------------
-- Apply a bar's shape (grid, slotStart, buttonCount) to its existing
-- button pool
--
-- The pool is created once and never destroyed. A layout change re-maps
-- each pool slot's action slot (Rebind), shows/hides up to buttonCount,
-- and repositions via LayoutButtons.
-------------------------------------------------------------------------

function ACAB:ApplyBarShape(bar)
	if not bar or not bar.config or not bar.buttons then
		return
	end

	local cfg = bar.config

	-- Bars saved before buttonCount existed fall back to filling the whole grid.
	local buttonCount = cfg.buttonCount or (cfg.cols * cfg.rows)

	local i

	for i = 1, table.getn(bar.buttons) do
		local btn = bar.buttons[i]

		if btn then
			local desiredSlot
			local slotValid

			-- Default bars (1-5): pool slot i resolves via GetDefaultBarSlotForIndex.
			-- Must check dynamicDefaultBar before fixedActionSlots below - bars 2-5 set both.
			if cfg.dynamicDefaultBar then
				desiredSlot = self:GetDefaultBarSlotForIndex(cfg.id, i)
				slotValid = desiredSlot ~= nil
			-- Fixed-slot bars (Pet Bar): binds pool slot i to cfg.fixedActionSlots[i], a pet slot 1-10.
			elseif cfg.fixedActionSlots then
				desiredSlot = cfg.fixedActionSlots[i]
				slotValid = desiredSlot ~= nil
			else
				desiredSlot = cfg.slotStart + (i - 1)
				slotValid = desiredSlot <= self.ACTION_SLOT_END
			end

			if slotValid then
				btn:Rebind(desiredSlot)
				btn:SetSlotVisible(i <= buttonCount)
			else
				-- Corrupt/hand-edited SavedVariables entry: keep hidden rather than rebind to an invalid slot.
				btn:SetSlotVisible(false)
			end
		end
	end

	local barW, barH = BarFrameSize(cfg)

	PixelSetSize(bar, barW, barH)

	-- Re-asserted every call - a native page-swap/stance-change path can re-level Bar 1 behind the art frame otherwise.
	bar:SetFrameStrata("HIGH")
	bar:SetFrameLevel(10)

	self:LayoutButtons(bar)

	-- Ensures the bar's overlay exists and its inset anchors are current.
	self:EnsureBarOverlay(bar)

	-- cfg.hoverOnly/cfg.hoverDuration may be nil on a bar saved before this feature existed.
	self:ApplyHoverOnlyState(bar, cfg.hoverOnly, function() return cfg.hoverDuration or 3 end)

	self:ApplyEditModeVisual()
end

-------------------------------------------------------------------------
-- Bar creation
-------------------------------------------------------------------------

function ACAB:CreateBarFromConfig(cfg)
	local barW, barH = BarFrameSize(cfg)

	local bar = CreateFrame(
		"Frame",
		"ACABBar" .. tostring(cfg.id),
		UIParent
	)

	-- HIGH, not MEDIUM - MainMenuBarArtFrame's :Raise() on click would push above MEDIUM and hide the bar.
	bar:SetFrameStrata("HIGH")

	-- Frame LEVEL decides stacking within a strata tier; comfortably below the overlay's level 100.
	bar:SetFrameLevel(10)

	PixelSetSize(bar, barW, barH)

	bar:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile     = true,
		tileSize = 8,
		edgeSize = 8,
		insets   = {
			left = 0,
			right = 0,
			top = 0,
			bottom = 0
		},
	})

	bar:SetBackdropColor(0, 0, 0, 0)
	bar:SetBackdropBorderColor(0, 0, 0, 0)

	bar:SetMovable(true)
	bar:RegisterForDrag("LeftButton")

	bar:SetScript("OnDragStart", function()
		if not ACAB:IsEditMode() then
			return
		end

		ACAB:StartBarDrag(this)
	end)

	bar:SetScript("OnDragStop", function()
		ACAB:StopBarDrag(this)
	end)

	bar.config = cfg

	self:ApplyBarPosition(bar)

	bar.buttons = {}

	-- Pool sized to MAX_BAR_BUTTONS (12) once here, never destroyed/recreated (see ApplyBarShape).
	local i

	for i = 1, self.MAX_BAR_BUTTONS do
		local slot

		-- Default bars (1-5): initial slot via GetDefaultBarSlotForIndex; ApplyBarShape re-resolves it later.
		if cfg.dynamicDefaultBar then
			slot = self:GetDefaultBarSlotForIndex(cfg.id, i)

			if not slot then
				break
			end
		-- Fixed-slot bars (Pet Bar): pool slot i binds to cfg.fixedActionSlots[i], a pet slot 1-10.
		elseif cfg.fixedActionSlots then
			slot = cfg.fixedActionSlots[i]

			if not slot then
				break
			end
		else
			slot = cfg.slotStart + (i - 1)

			if slot > self.ACTION_SLOT_END then
				self:Print(
					"Warning: Bar " .. tostring(cfg.id) ..
					" ran out of free action slots at button " ..
					tostring(i)
				)

				break
			end
		end

		bar.buttons[i] =
			self:CreateActionButton(
				bar,
				slot,
				i
			)
	end

	self:ApplyBarShape(bar)

	return bar
end

-------------------------------------------------------------------------
-- Create all bars from SavedVariables
-------------------------------------------------------------------------

function ACAB:CreateAllBars()
	self:EnsureDB()

	self.bars = {}

	local i

	for i = 1, table.getn(ACABDB.bars) do
		local cfg = ACABDB.bars[i]

		if cfg and cfg.id then
			local bar = self:CreateBarFromConfig(cfg)

			self.bars[cfg.id] = bar

			-- Extra Bars (6-9) default to hidden until cfg.enabled is set; no-op for other bar kinds.
			if self:IsExtraBarId(cfg.id) then
				if cfg.enabled then
					bar:Show()
				else
					bar:Hide()
				end
			end
		end
	end

	self:ApplyEditModeVisual()
end

-------------------------------------------------------------------------
-- Extra Bar enable/disable (ids 6-9)
--
-- Mirrors DefaultBars.lua's SetDefaultBarEnabled. Capacity fixed at
-- EXTRA_BAR_COUNT (4), seeded once by Core.lua's EnsureExtraBars.
-------------------------------------------------------------------------

function ACAB:IsExtraBarId(barId)
	return barId ~= nil
		and barId >= self.EXTRA_BAR_ID_START
		and barId < self.EXTRA_BAR_ID_START + self.EXTRA_BAR_COUNT
end

-- Restores an Extra Bar's position/buttonSize/spacing/grid to its fresh-created default.
function ACAB:ResetExtraBarLayout(barId)
	local bar = self.bars and self.bars[barId]

	if not bar or not bar.config then
		return
	end

	local index = barId - self.EXTRA_BAR_ID_START
	local x, y, cols, rows, buttonSize, spacing = self:GetDefaultExtraBarLayout(index)

	-- GetDefaultExtraBarLayout's x/y assume TOPLEFT/BOTTOMLEFT (matching
	-- every nativeAnchor) - Modern Layout's own slot function leaves this
	-- bar's anchor at BOTTOMLEFT/BOTTOMLEFT, which SetBarPosition below
	-- doesn't touch, so reset it here too.
	bar.config.point = "TOPLEFT"
	bar.config.relativePoint = "BOTTOMLEFT"

	self:SetBarLayout(bar, cols, rows)
	self:SetBarButtonCount(bar, cols * rows)
	self:SetBarSpacing(bar, spacing)
	self:SetBarButtonSize(bar, buttonSize)
	self:SetBarPosition(bar, x, y)

	-- Restore usesDefaultPosition (SetBarPosition above cleared it) so dependants resettle.
	bar.config.usesDefaultPosition = true

	if ACABDB.useDefaultLayout ~= false then
		self:ReflowExtraBarDependants(barId)
	end
end

-- Resets one Extra Bar to its Modern Layout slot, anchored to its live neighbor, without moving other bars.
function ACAB:ResetExtraBarLayoutToModernBase(barId)
	if not self:IsExtraBarId(barId) then
		return
	end

	self:EnsureDB()

	local bar = self.bars and self.bars[barId]

	if not bar then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local rowY = self:GetModernVerticalBarCenteredY(buttonSize, spacing)
	local extraStart = self.EXTRA_BAR_ID_START

	if barId == extraStart then
		-- Extra Bar 1: immediate left of Right Action Bar 2 (id 5)'s current real edge.
		local bar5 = self.bars[5]

		if not bar5 then
			return
		end

		local bar5Left = self:GetElementRealEdges(bar5)

		self:ApplyModernVerticalExtraBarSlot(bar, buttonSize, spacing, bar5Left or bar5.config.x, rowY, "left")
	elseif barId == extraStart + 1 then
		-- Extra Bar 2: outermost on the left, flush to the screen edge.
		self:ApplyModernVerticalExtraBarSlot(bar, buttonSize, spacing, 0, rowY, "right")
	else
		-- Extra Bar 3/4: immediate right of the previous Extra Bar's current real edge.
		local prevBar = self.bars[barId - 1]

		if not prevBar then
			return
		end

		local _, prevRealRight = self:GetElementRealEdges(prevBar)

		self:ApplyModernVerticalExtraBarSlot(bar, buttonSize, spacing, prevRealRight or prevBar.config.x, rowY, "right")
	end
end

function ACAB:SetExtraBarEnabled(barId, enabled)
	local bar = self.bars and self.bars[barId]

	if not bar or not bar.config then
		return
	end

	enabled = enabled and true or false

	local wasEnabled = bar.config.enabled and true or false

	bar.config.enabled = enabled

	if enabled then
		bar:Show()
	else
		bar:Hide()
	end

	-- Extra Bar 1 (index 0, above Bar 2) and Extra Bar 2 (index 1, above
	-- Bar 3) each add to Stance/Pet/Cast Bar's stacked baseline - see
	-- GetExtraBarStackPitch (Database.lua). Only meaningful in Default
	-- Layout mode (same guard SetDefaultBarEnabled uses for bar 2/3), and
	-- only while this Extra Bar is still at its own default position -
	-- once the user has dragged it elsewhere it no longer counts toward
	-- anyone else's stack (GetExtraBarStackPitch's own same guard), so
	-- toggling it further shouldn't move anything either.
	if enabled ~= wasEnabled and ACABDB.useDefaultLayout ~= false
		and bar.config.usesDefaultPosition ~= false then
		self:ReflowExtraBarDependants(barId)
	end
end

-------------------------------------------------------------------------
-- Extra Bar slot lookup
--
-- Resolves pool-slot `slotIndex` of Extra Bar `barId` to its bound native
-- action slot. Ignores enabled/IsShown - a stance/page source Extra Bar
-- keeps supplying its default bar regardless of its own visibility.
-------------------------------------------------------------------------

function ACAB:GetExtraBarSlotForIndex(barId, slotIndex)
	local bar = self.bars and self.bars[barId]

	if not bar or not bar.config or not bar.config.slotStart then
		return nil
	end

	local slot = bar.config.slotStart + (slotIndex - 1)

	if slot > self.ACTION_SLOT_END then
		return nil
	end

	return slot
end

-------------------------------------------------------------------------
-- Bar drag
--
-- Uses the shared cursor-tracking loop (ACAB:StartSharedDrag/StopSharedDrag,
-- dragKind == "bar") for live snap-while-dragging.
-------------------------------------------------------------------------

function ACAB:StartBarDrag(bar)
	if not bar or not bar.config then
		return
	end

	local cfg = bar.config

	-- Normalize to the TOPLEFT/BOTTOMLEFT anchor convention every chain-anchored element uses.
	local scale = bar:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()
	local left, top = bar:GetLeft(), bar:GetTop()

	if not scale or not uiParentScale or uiParentScale == 0 or not left or not top then
		return
	end

	cfg.point = "TOPLEFT"
	cfg.relativePoint = "BOTTOMLEFT"
	cfg.x = (left * scale) / uiParentScale
	cfg.y = (top * scale) / uiParentScale

	self:ApplyBarPosition(bar)

	self:StartSharedDrag("bar", cfg.id, cfg.x, cfg.y)
end

function ACAB:StopBarDrag(bar)
	if not bar then
		return
	end

	self:StopSharedDrag()

	-- Extra Bar 1/2 only - same flag/resettle treatment as SetBarPosition's drag-path equivalent.
	if bar.config and self:IsExtraBarId(bar.config.id) and bar.config.usesDefaultPosition ~= false then
		bar.config.usesDefaultPosition = false

		if ACABDB.useDefaultLayout ~= false then
			self:ReflowExtraBarDependants(bar.config.id)
		end
	end

	-- Keeps the Settings X/Y sliders in sync if this bar's page is already built/cached.
	if bar.config and self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(bar.config.id)
	end
end
