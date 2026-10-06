-- Bar.lua
-- Multi-bar grid engine backed by the action-slot pool (slots 73-120).
-- Bar config: id, point, relativePoint, x, y, cols, rows, buttonSize, slotStart, buttonCount; ids are persistent, not indices.

local ACAB = AlternativeClassicActionBars

ACAB.bars = {}

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

-- Grid a bar lays out as: Main Bar uses vanilla 12x1 while its Blizzard art is shown, keeping its saved cols/rows.
function ACAB:GetEffectiveBarGrid(cfg)
	if cfg.id == 1 and self:IsMainBarArtEnabled() then
		return 12, 1
	end

	return cfg.cols, cfg.rows
end

local function BarFrameSize(cfg)
	local spacing = ACAB:GetBarEffectiveSpacing(cfg)
	local cols, rows = ACAB:GetEffectiveBarGrid(cfg)

	local width = (cfg.buttonSize * cols) + ((cols - 1) * spacing)
	local height = (cfg.buttonSize * rows) + ((rows - 1) * spacing)

	return width, height
end

-- Bar frame's width/height from its config (effective grid/spacing), before any border overhang.
function ACAB:GetBarFrameSize(cfg)
	return BarFrameSize(cfg)
end

-- Re-anchors Main Bar's Blizzard art and every element grouped with it after Main Bar moves or resizes.
local function ApplyMainBarFollowers()
	ACAB:ApplyMainBarArtPosition()
	ACAB:ApplyMainBarGroupedElements()
end

-- Calls btn[method](btn, arg) on every pool button of bar.
local function CallOnBarButtons(bar, method, arg)
	local i

	for i = 1, table.getn(bar.buttons) do
		local btn = bar.buttons[i]
		if btn then
			btn[method](btn, arg)
		end
	end
end

-- Manual move: styled Pet/Stance Bar stop following the vanilla stack; an Extra Bar leaves its default spot.
local function ClearDefaultPositionFlags(cfg)
	if cfg.id == ACAB.PET_BAR_ID or cfg.id == ACAB.STANCE_BAR_ID then
		cfg.styledDefaultPosition = false
	end

	if ACAB:IsExtraBarId(cfg.id) and cfg.usesDefaultPosition ~= false then
		cfg.usesDefaultPosition = false

		ACAB:ReflowExtraBarDependants(cfg.id)
	end
end

-------------------------------------------------------------------------
-- Position
-------------------------------------------------------------------------

function ACAB:ApplyBarPosition(bar)
	if not bar or not bar.config then return end

	local cfg = bar.config
	local barW, barH = BarFrameSize(cfg)

	self:ApplyPositionToFrame(bar, cfg, "TOPLEFT", barW, barH)

	if cfg.id == 1 then
		ApplyMainBarFollowers()
	end
end

-------------------------------------------------------------------------
-- Button layout
-------------------------------------------------------------------------

function ACAB:LayoutButtons(bar)
	if not bar or not bar.buttons or not bar.config then return end

	local cfg = bar.config
	local spacing = self:GetBarEffectiveSpacing(cfg)
	local cols = self:GetEffectiveBarGrid(cfg)
	local i

	-- Pet Bar condense: packs filled slots into sequential cells; suspended during edit mode/action-grid preview.
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
					-- Not placed; UpdateGridVisibility hides it.
					layoutIndex = nil
				end
			end

			if layoutIndex then
				local col, row = self:ButtonIndexToGridPos(layoutIndex, cols)

				local xOff = col * (cfg.buttonSize + spacing)
				local yOff = -row * (cfg.buttonSize + spacing)

				btn:ClearAllPoints()
				self:PixelSetPoint(btn, "TOPLEFT", bar, "TOPLEFT", xOff, yOff)
			end
		end
	end
end

-------------------------------------------------------------------------
-- Bar edit-mode overlay: drag, right-click settings and wheel resize in edit mode
-------------------------------------------------------------------------

local barOverlays = {}

-- Resizes a bar by mouse-wheel delta in edit mode; default-family bars are locked while useDefaultLayout is on.
function ACAB:ResizeBarFromWheel(bar, delta)
	if not self:IsEditMode() or not bar or not bar.config then return end

	if self:IsDefaultBarFamilyId(bar.config.id) and
		ACABDB and ACABDB.useDefaultLayout ~= false then
		return
	end

	self:SetBarButtonSize(bar, bar.config.buttonSize + ((delta or 0) * 2))
end

-- Anchors the overlay to the bar expanded by its visual inset, so the hitbox reaches the border's outer edge.
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

-- Creates (once) and re-anchors a bar's edit-mode overlay; also used to measure a bar's inset-expanded footprint.
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

	-- Starts inert; ApplyEditModeVisual raises it to TOOLTIP in edit mode.
	overlay:SetFrameStrata("HIGH")
	overlay:SetFrameLevel(bar:GetFrameLevel())

	ApplyBarOverlayInsetAnchor(bar, overlay)

	local tex = overlay:CreateTexture(nil, "OVERLAY")
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")
	tex:SetVertexColor(0.35, 0.65, 1.0, 0.45)
	tex:SetAllPoints(overlay)

	-- Hover border, shown only while the cursor is over the overlay.
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

	local nameText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	nameText:SetPoint("CENTER", overlay, "CENTER", 0, 0)
	nameText:SetText(ACAB:GetBarDisplayName(bar.config.id))

	overlay:RegisterForDrag("LeftButton")
	overlay:SetScript("OnDragStart", function()
		ACAB:StartBarDrag(bar)
	end)
	overlay:SetScript("OnDragStop", function()
		ACAB:StopBarDrag(bar)
	end)

	-- Right-click opens the bar's settings page.
	overlay:SetScript("OnMouseUp", function()
		if arg1 == "RightButton" then
			ACAB:OpenBarSettings(bar)
		end
	end)

	overlay:EnableMouseWheel(true)
	overlay:SetScript("OnMouseWheel", function()
		ACAB:ResizeBarFromWheel(bar, arg1)
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
	local barId, bar

	for barId, bar in pairs(self.bars) do
		if bar then
			-- Default-bar-family bars (1-5, Pet Bar) are editable only while useDefaultLayout is off.
			local canEdit = editMode

			if self:IsDefaultBarFamilyId(barId) then
				canEdit = editMode and ACABDB and ACABDB.useDefaultLayout == false
			end

			if bar.buttons then
				CallOnBarButtons(bar, "UpdateGridVisibility")

				-- Re-flow: Pet Bar's condensed layout suspends itself during edit mode.
				self:LayoutButtons(bar)
			end

			local overlay = self:EnsureBarOverlay(bar)

			overlay:EnableMouse(canEdit and true or false)

			if canEdit then
				overlay:SetFrameStrata("TOOLTIP")
				overlay:Show()

				-- Clears a hover border left on if OnLeave never fired.
				overlay:SetBackdropBorderColor(0, 0, 0, 0)
			else
				overlay:SetFrameStrata("HIGH")
				overlay:Hide()
			end
		end
	end

	-- DefaultBars.lua's own overlays.
	self:ApplyDefaultLayoutEditVisual()

	self:ApplyLayoutGridVisual()

	-- Keeps Core.lua's ESC-to-exit binding in sync with edit mode.
	if editMode then
		self:EnableEditModeEscapeBinding()
	else
		self:DisableEditModeEscapeBinding()
	end
end

-------------------------------------------------------------------------
-- Button size
-------------------------------------------------------------------------

function ACAB:SetBarButtonSize(bar, newSize)
	if not bar or not bar.config then return end

	newSize = tonumber(newSize)

	if not newSize then return end

	-- Even values only, matching the 2px wheel/slider step.
	newSize = math.floor(newSize / 2) * 2

	if newSize < 16 then
		newSize = 16
	end

	if newSize > 64 then
		newSize = 64
	end

	bar.config.buttonSize = newSize

	CallOnBarButtons(bar, "ApplySize", newSize)

	local barW, barH = BarFrameSize(bar.config)

	self:PixelSetSize(bar, barW, barH)

	self:LayoutButtons(bar)

	-- Main Bar: layout grid, art and grouped elements follow the new size.
	if bar.config.id == 1 then
		if self:IsEditMode() then
			self:RebuildLayoutGrid()
		end

		ApplyMainBarFollowers()
	end
end

-------------------------------------------------------------------------
-- Spacing (clamp, write to bar.config, reapply shape)
-------------------------------------------------------------------------

function ACAB:SetBarSpacing(bar, spacing)
	if not bar or not bar.config then return end

	spacing = tonumber(spacing)

	if not spacing then return end

	spacing = math.floor(spacing + 0.5)

	-- Vanilla style has a minimum spacing floor; modern has none.
	local minSpacing = self:IsVanillaBorderStyle() and self.VANILLA_SPACING_FLOOR or 0

	if spacing < minSpacing then
		spacing = minSpacing
	end

	if spacing > self:GetSpacingMax() then
		spacing = self:GetSpacingMax()
	end

	bar.config.spacing = spacing

	self:ApplyBarShape(bar)

	-- Layout grid spacing depends on Main Bar's spacing.
	if bar.config.id == 1 and self:IsEditMode() then
		self:RebuildLayoutGrid()
	end
end

-------------------------------------------------------------------------
-- Only show on hover
-------------------------------------------------------------------------

function ACAB:SetBarHoverOnly(bar, enabled)
	if not bar or not bar.config then return end

	bar.config.hoverOnly = enabled and true or false

	self:ApplyBarShape(bar)
end

function ACAB:SetBarHoverDuration(bar, duration)
	if not bar or not bar.config then return end

	duration = self:ClampHoverDuration(duration)

	if not duration then return end

	bar.config.hoverDuration = duration

	self:ApplyBarShape(bar)
end

-------------------------------------------------------------------------
-- Global border style sweep (a style switch also shifts buttonSize, position and spacing)
-------------------------------------------------------------------------

function ACAB:ApplyGlobalButtonStyle()
	if not self.bars then return end

	local vanilla = self:IsVanillaBorderStyle()

	if ACABDB.lastAppliedVanillaStyle == nil then
		ACABDB.lastAppliedVanillaStyle = vanilla
	elseif ACABDB.lastAppliedVanillaStyle ~= vanilla then
		local delta = vanilla and -self.MODERN_BUTTON_SIZE_DELTA or self.MODERN_BUTTON_SIZE_DELTA

		-- Compensates for the size delta growing from the anchor corner, not the center.
		local posShift = self.MODERN_BUTTON_SIZE_POSITION_SHIFT
		local dx = vanilla and posShift or -posShift
		local dy = vanilla and -posShift or posShift

		-- Opposite sign to the buttonSize delta.
		local spacingDelta = vanilla and self.VANILLA_SPACING_FLOOR or -self.VANILLA_SPACING_FLOOR

		-- Skip default-family bars while useDefaultLayout owns them, or the delta double-shifts them.
		local skipDefaultBars = ACABDB.useDefaultLayout ~= false

		self:ForEachBar(function(barId, bar)
			if bar.config and bar.config.buttonSize and
				not (skipDefaultBars and ACAB:IsDefaultBarFamilyId(barId)) then
				self:SetBarButtonSize(bar, bar.config.buttonSize + delta)

				-- Only a legacy corner anchor needs the nudge; canonical positions are the visual center.
				if not ACAB:IsCanonicalPosition(bar.config) then
					self:SetBarPosition(bar, (bar.config.x or 0) + dx, (bar.config.y or 0) + dy)
				end

				self:SetBarSpacing(bar, (bar.config.spacing or 0) + spacingDelta)

				-- Re-centers on the new style's border overhang.
				if ACAB:IsCanonicalPosition(bar.config) then
					self:ApplyBarPosition(bar)
				end
			end
		end)

		-- Global buttonSize override gets the same shift, then re-applies.
		if ACABDB.globalButtonSizeEnabled and ACABDB.globalButtonSizeValue then
			ACABDB.globalButtonSizeValue = ACABDB.globalButtonSizeValue + delta
			self:ApplyGlobalButtonSize()
		end

		ACABDB.lastAppliedVanillaStyle = vanilla
	end

	-- Main Bar's spacing stays on its art slots in the new style.
	self:EnforceMainBarArtSpacing()

	self:ForEachBar(function(barId, bar)
		if bar.config then
			CallOnBarButtons(bar, "ApplyBorderStyle")
		end
	end)

	-- Native-mode Stance Bar isn't in self.bars; styled separately.
	self:ApplyStanceBarBorderStyle()

	-- Layout grid spacing tracks the border style.
	if self:IsEditMode() then
		self:RebuildLayoutGrid()
	end
end

-------------------------------------------------------------------------
-- Global spacing/button-size overrides (bars without spacingUnlocked/buttonSizeUnlocked)
-------------------------------------------------------------------------

-- Calls ACAB[applyMethod](ACAB, bar) on every bar without cfg[unlockedKey], while ACABDB[enabledKey] is on.
local function ApplyGlobalToLockedBars(enabledKey, unlockedKey, applyMethod)
	if not (ACAB.bars and ACABDB[enabledKey]) or ACABDB.useDefaultLayout ~= false then return end

	local barId, bar

	for barId, bar in pairs(ACAB.bars) do
		if bar and bar.config and not bar.config[unlockedKey] then
			ACAB[applyMethod](ACAB, bar)
		end
	end
end

function ACAB:ApplyGlobalSpacing()
	ApplyGlobalToLockedBars("globalSpacingEnabled", "spacingUnlocked", "ApplyGlobalSpacingToBar")
end

function ACAB:ApplyGlobalButtonSize()
	ApplyGlobalToLockedBars("globalButtonSizeEnabled", "buttonSizeUnlocked", "ApplyGlobalButtonSizeToBar")
end

-- Applies the current global Spacing value to a single bar, ignoring its lock state.
function ACAB:ApplyGlobalSpacingToBar(bar)
	if not (bar and bar.config and ACABDB.globalSpacingEnabled) or
		ACABDB.useDefaultLayout ~= false then
		return
	end

	-- Main Bar's spacing is pinned to its art slots while the art is enabled.
	if bar.config.id == 1 and self:IsMainBarArtEnabled() then
		self:EnforceMainBarArtSpacing()
		return
	end

	-- Global value is relative to the vanilla-only spacing floor.
	local floor = self:IsVanillaBorderStyle() and self.VANILLA_SPACING_FLOOR or 0
	local real = (ACABDB.globalSpacingValue or 0) + floor

	self:SetBarSpacing(bar, real)
end

-- Applies the current global Button Size value to a single bar, ignoring its lock state.
function ACAB:ApplyGlobalButtonSizeToBar(bar)
	if not (bar and bar.config and ACABDB.globalButtonSizeEnabled) or
		ACABDB.useDefaultLayout ~= false then
		return
	end

	local size = ACABDB.globalButtonSizeValue or self.BUTTON_SIZE

	self:SetBarButtonSize(bar, size)
end

-------------------------------------------------------------------------
-- Position from settings
-------------------------------------------------------------------------

-- point/relativePoint (optional): legacy anchor x/y are given in; ApplyBarPosition converts to canonical.
function ACAB:SetBarPosition(bar, x, y, point, relativePoint)
	if not bar or not bar.config then return end

	x = tonumber(x)
	y = tonumber(y)

	if not x or not y then return end

	if point then
		bar.config.point = point
		bar.config.relativePoint = relativePoint or point
		bar.config.visualCenter = nil
	end

	bar.config.x = x
	bar.config.y = y

	self:ApplyBarPosition(bar)

	ClearDefaultPositionFlags(bar.config)
end

-------------------------------------------------------------------------
-- Grid layout (cols*rows <= MAX_BAR_BUTTONS)
-------------------------------------------------------------------------

function ACAB:SetBarLayout(bar, cols, rows)
	if not bar or not bar.config then return false end

	cols = tonumber(cols)
	rows = tonumber(rows)

	if not cols or not rows then return false end

	cols = math.floor(cols)
	rows = math.floor(rows)

	if cols < 1 or rows < 1 then return false end

	if cols * rows > self.MAX_BAR_BUTTONS then
		self:Print("Bar " .. tostring(bar.config.id) ..
			" layout cannot exceed " .. tostring(self.MAX_BAR_BUTTONS) ..
			" buttons.")
		return false
	end

	bar.config.cols = cols
	bar.config.rows = rows

	-- Clamps buttonCount down to the new cell count; growing the grid doesn't restore it.
	local maxButtons = cols * rows
	local currentCount = bar.config.buttonCount or maxButtons
	if currentCount > maxButtons then
		bar.config.buttonCount = maxButtons
	end

	self:ApplyBarShape(bar)

	return true
end

-------------------------------------------------------------------------
-- Button count (<= cols*rows; hides pool slots, never resizes the pool)
-------------------------------------------------------------------------

function ACAB:SetBarButtonCount(bar, count)
	if not bar or not bar.config then return false end

	count = tonumber(count)

	if not count then return false end

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
-- Action-slot pool allocator (ACTION_SLOT_START..ACTION_SLOT_END)
-------------------------------------------------------------------------

-- True when a pool-backed bar's full MAX_BAR_BUTTONS slot block (clamped to the pool end) covers `slot`.
function ACAB:IsActionSlotUsed(slot, ignoredBarId)
	local i

	for i = 1, table.getn(ACABDB.bars) do
		local cfg = ACABDB.bars[i]
		if cfg and cfg.id ~= ignoredBarId and not cfg.dynamicDefaultBar and not cfg.fixedActionSlots then
			local first = cfg.slotStart
			if first and slot >= first and slot <= first + self.MAX_BAR_BUTTONS - 1 and slot <= self.ACTION_SLOT_END then
				return true
			end
		end
	end

	return false
end

-- True when every slot of a contiguous range is inside the pool and unused.
function ACAB:IsActionSlotRangeFree(startSlot, count, ignoredBarId)
	if not startSlot or not count then return false end

	if startSlot < self.ACTION_SLOT_START then return false end

	if startSlot + count - 1 > self.ACTION_SLOT_END then return false end

	local slot

	for slot = startSlot, startSlot + count - 1 do
		if self:IsActionSlotUsed(slot, ignoredBarId) then return false end
	end

	return true
end

-- Page 10 (109-120) is scanned first, keeping pages 7-9 free for stance/page content.
local PREFERRED_SLOT_START = 109

-- First free contiguous range for a new pool-backed bar (always MAX_BAR_BUTTONS slots), or nil.
function ACAB:GetNextFreeSlotStart(neededCount)
	if not neededCount or neededCount < 1 then return nil end

	if neededCount < self.MAX_BAR_BUTTONS then
		neededCount = self.MAX_BAR_BUTTONS
	end

	local candidate

	for candidate = PREFERRED_SLOT_START, self.ACTION_SLOT_END - neededCount + 1 do
		if self:IsActionSlotRangeFree(candidate, neededCount, nil) then
			return candidate
		end
	end

	for candidate = self.ACTION_SLOT_START, PREFERRED_SLOT_START - neededCount do
		if self:IsActionSlotRangeFree(candidate, neededCount, nil) then
			return candidate
		end
	end

	return nil
end

-------------------------------------------------------------------------
-- Bar shape: re-binds each pool button's slot, shows up to buttonCount, resizes and re-lays out
-------------------------------------------------------------------------

-- Slot for pool button i: default-bar paging, fixed pet/stance slot, or slotStart + i - 1 (nil past the pool end).
local function ResolvePoolSlot(cfg, i)
	-- dynamicDefaultBar must be checked before fixedActionSlots: bars 2-5 set both.
	if cfg.dynamicDefaultBar then
		return ACAB:GetDefaultBarSlotForIndex(cfg.id, i)
	elseif cfg.fixedActionSlots then
		return cfg.fixedActionSlots[i]
	end

	local slot = cfg.slotStart + (i - 1)
	if slot <= ACAB.ACTION_SLOT_END then
		return slot
	end

	return nil
end

-- skipEditVisual: caller runs ApplyEditModeVisual once itself after shaping several bars.
function ACAB:ApplyBarShape(bar, skipEditVisual)
	if not bar or not bar.config or not bar.buttons then return end

	local cfg = bar.config

	-- Bars saved without buttonCount fill the whole grid.
	local buttonCount = cfg.buttonCount or (cfg.cols * cfg.rows)

	local i

	for i = 1, table.getn(bar.buttons) do
		local btn = bar.buttons[i]
		if btn then
			local slot = ResolvePoolSlot(cfg, i)
			if slot then
				btn:Rebind(slot)
				btn:SetSlotVisible(i <= buttonCount)
			else
				-- No valid slot (e.g. hand-edited SavedVariables): keep hidden.
				btn:SetSlotVisible(false)
			end
		end
	end

	local barW, barH = BarFrameSize(cfg)

	self:PixelSetSize(bar, barW, barH)

	-- Must re-assert every call, or a page/stance swap can bury Bar 1 behind the art frame (LOW level 5).
	bar:SetFrameStrata("LOW")
	bar:SetFrameLevel(10)

	self:LayoutButtons(bar)

	-- Creates the overlay or refreshes its inset anchors.
	self:EnsureBarOverlay(bar)

	-- Built once per bar (bar.config never changes).
	if not bar.ACABHoverDurationGetter then
		bar.ACABHoverDurationGetter = function() return cfg.hoverDuration or 3 end
	end

	self:ApplyHoverOnlyState(bar, cfg.hoverOnly, bar.ACABHoverDurationGetter)

	if not skipEditVisual then
		self:ApplyEditModeVisual()
	end

	-- Main Bar footprint changed: art and grouped elements follow. Size-gated so page/stance swaps skip it.
	if cfg.id == 1 and (bar.ACABFollowerWidth ~= barW or bar.ACABFollowerHeight ~= barH) then
		bar.ACABFollowerWidth = barW
		bar.ACABFollowerHeight = barH

		ApplyMainBarFollowers()
	end
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

	-- Must stay LOW, below bags (MEDIUM); art frame is LOW level 5 so it stays under the bar.
	bar:SetFrameStrata("LOW")
	bar:SetFrameLevel(10)

	self:PixelSetSize(bar, barW, barH)

	bar:SetBackdrop(self.FLAT_BACKDROP)

	bar:SetBackdropColor(0, 0, 0, 0)
	bar:SetBackdropBorderColor(0, 0, 0, 0)

	bar:SetMovable(true)
	bar:RegisterForDrag("LeftButton")

	bar:SetScript("OnDragStart", function()
		if not ACAB:IsEditMode() then return end

		ACAB:StartBarDrag(this)
	end)

	bar:SetScript("OnDragStop", function()
		ACAB:StopBarDrag(this)
	end)

	bar.config = cfg

	self:ApplyBarPosition(bar)

	bar.buttons = {}

	-- Pool of up to MAX_BAR_BUTTONS, created once and never rebuilt.
	local i

	for i = 1, self.MAX_BAR_BUTTONS do
		local slot = ResolvePoolSlot(cfg, i)
		if not slot then
			if not cfg.dynamicDefaultBar and not cfg.fixedActionSlots then
				self:Print(
					"Warning: Bar " .. tostring(cfg.id) ..
					" ran out of free action slots at button " ..
					tostring(i)
				)
			end

			break
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

			-- Extra Bars stay hidden until cfg.enabled is set.
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
-- Bar drag (shared drag engine, dragKind "bar")
-------------------------------------------------------------------------

function ACAB:StartBarDrag(bar)
	if not bar or not bar.config then return end

	local cfg = bar.config

	-- Must run first: normalizes cfg to canonical before the drag reads its x/y.
	self:ApplyBarPosition(bar)

	self:StartSharedDrag("bar", cfg.id, cfg.x, cfg.y)
end

function ACAB:StopBarDrag(bar)
	if not bar then return end

	self:StopSharedDrag()

	if bar.config then
		ClearDefaultPositionFlags(bar.config)

		-- Syncs the Settings X/Y sliders.
		self:RefreshBarSettingsPage(bar.config.id)
	end
end
