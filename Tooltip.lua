-- Tooltip.lua
-- Tooltip position/scale/anchor corner/enable, via a synthetic frame the fixed-position GameTooltip is redirected onto.

local ACAB = AlternativeClassicActionBars

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

	if self.tooltipFrame then return end

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
	if not pos or not frame then return end

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

	if not scale then return end

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

	if corner ~= "TOPLEFT" and corner ~= "TOPRIGHT" and corner ~= "BOTTOMLEFT" and corner ~= "BOTTOMRIGHT" then return end

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
	self:StartElementDrag("tooltip")
end

function ACAB:StopTooltipDrag()
	self:StopElementDrag("tooltip")
end

-- Redirects every fixed-position GameTooltip onto the synthetic frame (other tooltip objects are skipped).
function ACAB:HookGameTooltipDefaultAnchor()
	if self.tooltipDefaultAnchorHooked then return end

	self.tooltipDefaultAnchorHooked = true

	-- Every SetOwner resets scale 1; the SetDefaultAnchor post-hook below reapplies the custom scale.
	local nativeSetOwner = GameTooltip.SetOwner
	GameTooltip.SetOwner = function(tooltip, a1, a2, a3, a4)
		tooltip:SetScale(1)
		return nativeSetOwner(tooltip, a1, a2, a3, a4)
	end

	hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, owner)
		if tooltip ~= GameTooltip then return end

		if not ACABDB.tooltipEnabled then return end

		if not ACAB.tooltipFrame then return end

		local corner = ACABDB.tooltipAnchorCorner or "BOTTOMRIGHT"

		GameTooltip:ClearAllPoints()
		GameTooltip:SetPoint(corner, ACAB.tooltipFrame, corner, 0, 0)
		GameTooltip:SetScale(ACABDB.tooltipScale or 1)
	end)
end

