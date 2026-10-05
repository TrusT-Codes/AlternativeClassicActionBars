-- ExtraBars.lua
-- Extra Bars 6-9: seeding, enable/disable and default/Modern layout resets on top of Bar.lua's engine.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Extra Bars (EXTRA_BAR_COUNT bars from EXTRA_BAR_ID_START)
-------------------------------------------------------------------------

function ACAB:IsExtraBarId(barId)
	return barId ~= nil
		and barId >= self.EXTRA_BAR_ID_START
		and barId < self.EXTRA_BAR_ID_START + self.EXTRA_BAR_COUNT
end

-- Restores an Extra Bar's position/buttonSize/spacing/grid to its fresh-created default.
function ACAB:ResetExtraBarLayout(barId)
	local bar = self.bars and self.bars[barId]
	if not bar or not bar.config then return end

	local index = barId - self.EXTRA_BAR_ID_START
	local x, y, cols, rows, buttonSize, spacing = self:GetDefaultExtraBarLayout(index)

	-- Must set shape before position: the TOPLEFT x/y conversion reads the bar's final size.
	self:SetBarLayout(bar, cols, rows)
	self:SetBarButtonCount(bar, cols * rows)
	self:SetBarSpacing(bar, spacing)
	self:SetBarButtonSize(bar, buttonSize)

	self:SetBarPosition(bar, x, y, "TOPLEFT", "BOTTOMLEFT")

	-- SetBarPosition cleared it; restore so dependants resettle.
	bar.config.usesDefaultPosition = true

	self:ReflowExtraBarDependants(barId)
end

-- Resets one Extra Bar to its Modern Layout slot, anchored to its live neighbor, without moving other bars.
function ACAB:ResetExtraBarLayoutToModernBase(barId)
	if not self:IsExtraBarId(barId) then return end

	self:EnsureDB()

	local bar = self.bars and self.bars[barId]
	if not bar then return end

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local rowY = self:GetModernVerticalBarCenteredY(buttonSize, spacing)
	local extraStart = self.EXTRA_BAR_ID_START

	if barId == extraStart then
		-- Extra Bar 1: just left of bar 5's current real edge.
		local bar5 = self.bars[5]
		if not bar5 then return end

		local bar5Left = self:GetElementRealEdges(bar5)

		self:ApplyModernVerticalExtraBarSlot(bar, buttonSize, spacing, bar5Left or bar5.config.x, rowY, "left")
	elseif barId == extraStart + 1 then
		-- Extra Bar 2: outermost on the left, flush to the screen edge.
		self:ApplyModernVerticalExtraBarSlot(bar, buttonSize, spacing, 0, rowY, "right")
	else
		-- Extra Bar 3/4: just right of the previous Extra Bar's current real edge.
		local prevBar = self.bars[barId - 1]
		if not prevBar then return end

		local _, prevRealRight = self:GetElementRealEdges(prevBar)

		self:ApplyModernVerticalExtraBarSlot(bar, buttonSize, spacing, prevRealRight or prevBar.config.x, rowY, "right")
	end
end

function ACAB:SetExtraBarEnabled(barId, enabled)
	local bar = self.bars and self.bars[barId]
	if not bar or not bar.config then return end

	enabled = enabled and true or false

	local wasEnabled = bar.config.enabled and true or false

	bar.config.enabled = enabled

	if enabled then
		bar:Show()
	else
		bar:Hide()
	end

	-- A default-positioned Extra Bar counts toward Stance/Pet/Cast Bar's stack.
	if enabled ~= wasEnabled and bar.config.usesDefaultPosition ~= false then
		self:ReflowExtraBarDependants(barId)
	end
end

-- Action slot of an Extra Bar's pool button, also for a hidden bar (it still supplies stance/page content).
function ACAB:GetExtraBarSlotForIndex(barId, slotIndex)
	local bar = self.bars and self.bars[barId]
	if not bar or not bar.config or not bar.config.slotStart then return nil end

	local slot = bar.config.slotStart + (slotIndex - 1)
	if slot > self.ACTION_SLOT_END then return nil end

	return slot
end
