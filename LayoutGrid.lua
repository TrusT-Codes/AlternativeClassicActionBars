-- LayoutGrid.lua
-- Edit Layout mode's screen grid overlay; holding Ctrl inverts ACABDB.showLayoutGrid.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Layout grid overlay (Edit Layout mode); holding Ctrl inverts ACABDB.showLayoutGrid
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

-- Draws 2*halfCount+1 vertical (or horizontal) lines `spacing` apart from the frame's center; hides leftovers.
local function DrawLayoutGridLines(pool, frame, halfCount, spacing, vertical)
	local count = 0
	local k

	for k = -halfCount, halfCount do
		count = count + 1

		local line = GetOrCreatePoolLine(pool, count, frame)
		local isCenter = (k == 0)
		local color = isCenter and LAYOUT_GRID_CENTER_COLOR or LAYOUT_GRID_LINE_COLOR
		local thickness = isCenter and LAYOUT_GRID_CENTER_THICKNESS or LAYOUT_GRID_LINE_THICKNESS

		line:ClearAllPoints()

		if vertical then
			line:SetWidth(thickness)
			line:SetPoint("TOP", frame, "TOP", k * spacing, 0)
			line:SetPoint("BOTTOM", frame, "BOTTOM", k * spacing, 0)
		else
			line:SetHeight(thickness)
			line:SetPoint("LEFT", frame, "LEFT", 0, k * spacing)
			line:SetPoint("RIGHT", frame, "RIGHT", 0, k * spacing)
		end

		line:SetVertexColor(color[1], color[2], color[3], color[4])
		line:Show()
	end

	HideLinesFrom(pool, count)
end

-- Redraws every grid line at the current GetLayoutGridSpacing().
function ACAB:RebuildLayoutGrid()
	local frame = EnsureLayoutGridFrame()

	-- Already in local units: must not divide by GetEffectiveScale.
	local spacing = self:GetLayoutGridSpacing()
	if not spacing or spacing <= 0 then
		HideLinesFrom(layoutGridVLines, 0)
		HideLinesFrom(layoutGridHLines, 0)
		return
	end

	-- UIParent's size, not this frame's: this frame's rect may not be resolved yet.
	local width, height = self:GetUIParentAnchorSize()

	if not width or not height or width <= 0 or height <= 0 then return end

	local halfCountX = math.ceil((width / 2) / spacing) + LAYOUT_GRID_EDGE_OVERSHOOT_LINES
	local halfCountY = math.ceil((height / 2) / spacing) + LAYOUT_GRID_EDGE_OVERSHOOT_LINES

	DrawLayoutGridLines(layoutGridVLines, frame, halfCountX, spacing, true)
	DrawLayoutGridLines(layoutGridHLines, frame, halfCountY, spacing, false)
end

-- True in Edit Layout mode when showLayoutGrid XOR Ctrl held.
local function ComputeLayoutGridShouldShow()
	if not ACAB:IsEditMode() then return false end

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

		layoutGridCtrlTicker = C_Timer.NewTicker(LAYOUT_GRID_CTRL_POLL_INTERVAL, function()
			if ACAB:IsEditMode() then
				ACAB:RefreshLayoutGridVisibility()
			end
		end)
	else
		EnsureLayoutGridFrame():Hide()
	end
end
