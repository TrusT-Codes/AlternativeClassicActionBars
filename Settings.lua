-- Settings.lua
-- Unified settings window: default bars (1-5), Extra Bars (6-9), and native-frame "simple" pages
-- (Stance/Bag/Micro Menu/Latency/Experience Bar) share one bar list and a "Bars" view, plus a "General"
-- view for addon-wide settings. Every control is live: no pending/Apply state.
-- Per-bar editable settings (default bars 1-5, Extra Bars 6-9): x/y, buttonSize, spacing, cols/rows
-- (grid presets), buttonCount (Extra Bars only), enabled (bars 2-5 and 6-9 only).
-- point/relativePoint and slotStart are not exposed in the UI. Grid shape is one of 6 fixed presets
-- (1x12, 2x6, 3x4, 4x3, 6x2, 12x1), not free-form rows/cols sliders. Button size steps in 2px increments.
-- CreateSimpleBarPage builds the narrower simple-bar pages. GetOrCreateGeneralPanel builds the General tab.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------

ACAB.BUTTON_SIZE_MIN = 16
ACAB.BUTTON_SIZE_MAX = 64
ACAB.BUTTON_SIZE_STEP = 2

-- General tab's hotkey/count text font size sliders.
ACAB.FONT_SIZE_MIN = 6
ACAB.FONT_SIZE_MAX = 24
ACAB.FONT_SIZE_STEP = 1

-- Clamps a saved/native font size into the sliders' fixed [MIN, MAX] range, rounding via
-- math.floor(value + 0.5) - GetFont() can come back with float imprecision on this client.
function ACAB:ClampFontSize(size)
	if not size then
		return ACAB.FONT_SIZE_MIN
	end

	size = math.floor(size + 0.5)

	if size < ACAB.FONT_SIZE_MIN then
		return ACAB.FONT_SIZE_MIN
	end

	if size > ACAB.FONT_SIZE_MAX then
		return ACAB.FONT_SIZE_MAX
	end

	return size
end

-- Shared by both default bars (1-5) and custom bars (6+) Spacing sliders.
ACAB.SPACING_MIN = 0
ACAB.SPACING_MAX = 20
ACAB.SPACING_STEP = 1

-- Real-to-displayed spacing offset for the per-bar (1-9) spacing slider only - not the simple-bar
-- sliders or the global-spacing slider. Real values are only ever written at the OnValueChanged/
-- refresh boundary; the slider's on-screen value is always in displayed space.
function ACAB:GetSpacingDisplayOffset()
	return ACAB:IsVanillaBorderStyle() and ACAB.VANILLA_SPACING_FLOOR or 0
end
-- Populated later in this file (CreateSimpleBarPage). A ACAB field since both this file and
-- SettingsBars.lua's page builders need to read/write it regardless of file/definition order.
ACAB.simpleBarPageConfigs = {}

-- Layout indent constants, used instead of scattering magic numbers through every page-building call.
ACAB.INDENT_SECTION = 18
ACAB.INDENT_CONTROL = 22
ACAB.INDENT_INPUT   = 85

-- Defers `fn` to the next frame via C_Timer.After(0, ...), falling back to calling fn immediately if
-- C_Timer isn't available. Wraps every Fit*View call: GetBottom() on a panel just Show()'n/populated
-- this same tick has not resolved to real values yet.
function ACAB:DeferFit(fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, fn)
	else
		fn()
	end
end

-- Width reserved for each content viewport's scrollbar, reserved unconditionally so nothing reflows
-- when scrolling toggles on/off.
local SETTINGS_SCROLLBAR_RESERVED_WIDTH = 28

-- Fixed vertical band reserved for the Default-profile-lock warning banner, reserved unconditionally
-- so nothing reflows when the banner toggles.
local PROFILE_LOCK_BANNER_TOP = -34

-- Safety-margin reserve for the longer lock message, wrapped at the narrowest page width the banner
-- appears at. Real height is still recomputed dynamically from wrapped text.
local PROFILE_LOCK_BANNER_HEIGHT = 56
-------------------------------------------------------------------------
-- Basic helpers
-------------------------------------------------------------------------

local function SettingsFrame_OnDragStart()
	this:StartMoving()
end

local function SettingsFrame_OnDragStop()
	this:StopMovingOrSizing()
end

-- A ACAB: method since Settings.lua's own RefreshPositionSliderRange and SettingsBars.lua's page
-- builders both call it.
function ACAB:IsDefaultBarId(barId)
	return ACAB:IsDefaultBarFamilyId(barId)
end

-- Finds an Extra Bar's SavedVariables entry by ID, not array index - ACABDB.bars is a plain array.
function ACAB:FindCustomBarConfig(barId)
	local i

	for i = 1, table.getn(ACABDB.bars) do
		local cfg = ACABDB.bars[i]

		if cfg and cfg.id == barId then
			return cfg
		end
	end

	return nil
end

-- Returns cfg, isDefault for any bar id (1-5 default, 6+ custom).
function ACAB:GetBarConfig(barId)
	if ACAB:IsDefaultBarId(barId) then
		return ACABDB.defaultBars[barId], true
	end

	return ACAB:FindCustomBarConfig(barId), false
end
-------------------------------------------------------------------------
-- Screen coordinate ranges
-- Computed once per page build, not per-tick - the "Position (X: -1024 to 1024)" caption is a static
-- FontString set at build time.
-------------------------------------------------------------------------

-- Elements anchor at various corners, so a given element's offset from UIParent can need to span up to
-- a full screen dimension to reach the opposite edge, plus room to drag it fully off-screen. Doubling
-- UIParent's own size comfortably covers every anchor-corner combination in use.
function ACAB:GetScreenCoordinateRange()
	local width = UIParent:GetWidth()
	local height = UIParent:GetHeight()

	if not width or width <= 0 then
		width = 1024
	end

	if not height or height <= 0 then
		height = 768
	end

	return -width * 2, width * 2, -height * 2, height * 2
end

-------------------------------------------------------------------------
-- Action-bar-specific X/Y position clamp range
-- Computed per-bar (depends on buttonSize/buttonCount/border style), kept live via
-- RefreshPositionSliderRange below. Bars anchor TOPLEFT-to-UIParent's BOTTOMLEFT, y=0 at the screen
-- bottom, increasing upward.
-- WARNING: use GetScreenWidth()/GetScreenHeight() for the screen-bounds terms, not
-- UIParent:GetWidth()/GetHeight() - UIParent has a non-1 self-scale, so its own GetWidth()/GetHeight()
-- undershoots the real screen edges.
--
-- xMin = 0
-- xMax = GetScreenWidth() - barWidth - borderSize
-- yMin = barHeight + borderSize
-- yMax = GetScreenHeight()
-- (barWidth/barHeight include inter-button spacing; use cols/rows, not
-- buttonCount, since a multi-row bar isn't buttonCount cells wide)
-------------------------------------------------------------------------

-- 4-unit vanilla action-button border vs. 1-unit modern/minimal border.
local function GetActionBarBorderSize()
	return ACAB:IsVanillaBorderStyle() and 4 or 1
end

function ACAB:GetActionBarCoordinateRange(cfg)
	-- Screen bounds come from GetScreenWidth()/GetScreenHeight(), not UIParent:GetWidth()/GetHeight().
	local screenWidthUnits = GetScreenWidth()
	local screenHeightUnits = GetScreenHeight()

	if not screenWidthUnits or screenWidthUnits <= 0 then
		screenWidthUnits = 1024
	end

	if not screenHeightUnits or screenHeightUnits <= 0 then
		screenHeightUnits = 768
	end

	local buttonSize = (cfg and cfg.buttonSize) or ACAB.BUTTON_SIZE
	local cols = (cfg and cfg.cols) or 1
	local rows = (cfg and cfg.rows) or 1
	local spacing = (cfg and cfg.spacing) or 0
	local borderSize = GetActionBarBorderSize()

	-- Pet Bar condense: Bar.lua's LayoutButtons compacts filled slots into cfg.cols-wide rows instead
	-- of reserving every one of the 10 pool slots' own cell - the clamp range must match that shape or the
	-- bar can never reach screen edges the full uncondensed grid blocked.
	if cfg and cfg.isPetBar and ACAB:ShouldCondensePetBarSlots() then
		local filled = ACAB:GetPetBarFilledSlotCount()

		if filled <= 0 then
			cols = 1
			rows = 1
		elseif filled < cols then
			cols = filled
			rows = 1
		else
			rows = math.ceil(filled / cols)
		end
	end

	local barWidth = (cols * buttonSize) + ((cols - 1) * spacing)
	local barHeight = (rows * buttonSize) + ((rows - 1) * spacing)

	local minX, maxX

	-- Modern Layout's Right Action Bar 1 (id 4) anchors BOTTOMRIGHT (flush
	-- to the screen's right edge) instead of every other bar's BOTTOMLEFT -
	-- mirror the range the same way GetSimpleElementCoordinateRange does
	-- for the corner cluster, or this slider reads cfg.x's BOTTOMRIGHT
	-- convention (0 at the right edge, negative moving left) as if it were
	-- BOTTOMLEFT and clamps it up to 0.
	if ACAB:IsRightAnchoredPoint(cfg and cfg.point) then
		minX = -(screenWidthUnits - barWidth - borderSize)
		maxX = 0
	else
		minX = 0
		maxX = screenWidthUnits - barWidth - borderSize
	end

	local minY = barHeight + borderSize
	local maxY = screenHeightUnits

	-- Never feed SetMinMaxValues a backwards span (max < min) if an
	-- oversized bar/border combination would otherwise invert it.
	if maxX < minX then
		maxX = minX
	end

	if maxY < minY then
		maxY = minY
	end

	return minX, maxX, minY, maxY
end

-- Recomputes and re-applies an action-bar page's X/Y slider clamp range from its current
-- buttonSize/buttonCount/cols/rows and border style. Also re-clamps the current value.
function ACAB:RefreshPositionSliderRange(page)
	if not page or not page.xSlider or not page.ySlider or not page.barId then
		return
	end

	local cfg = ACAB:GetBarConfig(page.barId)

	if not cfg then
		return
	end

	local minX, maxX, minY, maxY = ACAB:GetActionBarCoordinateRange(cfg)

	page.xSlider:SetMinMaxValues(minX, maxX)
	page.ySlider:SetMinMaxValues(minY, maxY)

	local x = page.xSlider:GetValue()
	local y = page.ySlider:GetValue()

	if x < minX then
		ACAB:SetSliderValueUnsnapped(page.xSlider, minX)
	elseif x > maxX then
		ACAB:SetSliderValueUnsnapped(page.xSlider, maxX)
	end

	if y < minY then
		ACAB:SetSliderValueUnsnapped(page.ySlider, minY)
	elseif y > maxY then
		ACAB:SetSliderValueUnsnapped(page.ySlider, maxY)
	end
end

-------------------------------------------------------------------------
-- Native/simple-element X/Y position clamp range (Bag Bar, Micro Menu, Stance/Pet Bar native mode,
-- Experience Bar, Cast Bar - not Latency Bar, whose overlay hitbox is oversized relative to its visual
-- footprint, a separate known issue).
-- Unlike action bars, these elements' footprint isn't formula-derived - read the real rendered size via
-- each element's `.ACABOverlay`, which tracks the trimmed real visual footprint.
-- WARNING - two things action bars don't need:
-- 1. Hit-rect padding: frame:GetWidth()/GetHeight() can exceed the real drawn size - prefer the overlay.
-- 2. Scale: these elements call :SetScale() directly, so pos.x/y are in pre-scale unit space - divide
--    by scale to compare against screenWidth/frameWidth.
-- extraMaxYPixels (optional): extra real screen pixels of headroom added before the scale division.
-------------------------------------------------------------------------

-- True for any point string anchored to the screen's right edge - Modern Layout's corner cluster
-- stores position this way, x=0 flush against the right edge and more negative moving left, the mirror
-- image of the BOTTOMLEFT/TOPLEFT convention every X/Y position slider otherwise assumes.
function ACAB:IsRightAnchoredPoint(point)
	return point ~= nil and string.find(point, "RIGHT") ~= nil
end

-- isRightAnchored (optional): mirrors minX/maxX for a RIGHT-anchored element's x convention (0 at the
-- screen's right edge, negative moving left) instead of the default LEFT-anchored one.
function ACAB:GetSimpleElementCoordinateRange(frame, extraMaxYPixels, isRightAnchored)
	local screenWidthUnits = GetScreenWidth()
	local screenHeightUnits = GetScreenHeight()

	if not screenWidthUnits or screenWidthUnits <= 0 then
		screenWidthUnits = 1024
	end

	if not screenHeightUnits or screenHeightUnits <= 0 then
		screenHeightUnits = 768
	end

	-- frame:GetWidth()/GetHeight() are scale-independent; multiply by the container's own scale for
	-- the same space frame:GetLeft()*scale uses.
	-- WARNING: don't use the overlay's GetWidth()/GetHeight() as the base size - it measures smaller
	-- than the true footprint once scale isn't 1. The overlay is only used below for the inset correction.
	local overlay = frame and frame.ACABOverlay

	local scale = (frame and frame:GetScale()) or 1

	if not scale or scale <= 0 then
		scale = 1
	end

	-- Some elements' overlay is trimmed inward from the container's own raw anchor corner - measured
	-- directly below (container-vs-overlay offset) rather than hardcoded, 0 when there's no trim.
	local leftInset, rightInset, topInset, bottomInset = 0, 0, 0, 0

	if overlay and frame then
		-- frame:GetLeft()/GetTop() are in the container's own local unit system; the overlay's scale
		-- is always 1 - multiply the container's edge by its own scale before diffing against the overlay's.
		local containerLeft = frame:GetLeft()
		local overlayLeft = overlay:GetLeft()
		local containerRight = frame:GetRight()
		local overlayRight = overlay:GetRight()
		local containerTop = frame:GetTop()
		local overlayTop = overlay:GetTop()
		local containerBottom = frame:GetBottom()
		local overlayBottom = overlay:GetBottom()

		if containerLeft and overlayLeft then
			leftInset = overlayLeft - (containerLeft * scale)
		end

		if containerRight and overlayRight then
			rightInset = (containerRight * scale) - overlayRight
		end

		if containerTop and overlayTop then
			topInset = (containerTop * scale) - overlayTop
		end

		if containerBottom and overlayBottom then
			bottomInset = overlayBottom - (containerBottom * scale)
		end
	end

	local extraY = 0

	if extraMaxYPixels and extraMaxYPixels ~= 0 then
		extraY = extraMaxYPixels * ACAB:GetPixelStep()
	end

	-- frameWidth/frameHeight convert the container's raw size into the same space as the insets above.
	-- Real right edge: (x*scale) + frameWidth*scale - rightInset <= screenWidth
	--   => x <= (screenWidth + rightInset)/scale - frameWidth
	-- Real top edge:   (x*scale) - topInset <= screenHeight + extra
	--   => x <= (screenHeight + extra + topInset)/scale
	-- Real bottom edge (minY): (y - frameHeight)*scale + bottomInset >= 0
	--   => y >= frameHeight - bottomInset/scale
	local frameWidth = (frame and frame:GetWidth()) or 0
	local frameHeight = (frame and frame:GetHeight()) or 0

	local minX, maxX

	if isRightAnchored then
		-- Mirror image of the LEFT-anchored formula below: 0 flush at the right edge, negative moving
		-- left - leftInset/rightInset swap roles since "distance from the right edge" reads from the opposite side.
		minX = -((screenWidthUnits + leftInset) / scale - frameWidth)
		maxX = 0
	else
		minX = 0
		maxX = (screenWidthUnits + rightInset) / scale - frameWidth
	end

	local minY = frameHeight - bottomInset / scale
	local maxY = (screenHeightUnits + extraY + topInset) / scale

	if maxX < minX then
		maxX = minX
	end

	if minY < 0 then
		minY = 0
	end

	if maxY < minY then
		maxY = minY
	end

	return minX, maxX, minY, maxY
end

-- Recomputes and re-applies a simple-page element's X/Y slider clamp range from its current rendered
-- size. No-ops for pages without config.getElementFrame (Latency Bar, deliberately left on the generic
-- screen-relative range). Also re-clamps the current value.
function ACAB:RefreshSimplePositionSliderRange(page, key)
	if not page or not page.xSlider or not page.ySlider then
		return
	end

	local config = ACAB.simpleBarPageConfigs[key]

	if not config or not config.getElementFrame then
		return
	end

	local frame = config.getElementFrame()

	if not frame then
		return
	end

	local pos = config.getPosition and config.getPosition()
	local isRightAnchored = ACAB:IsRightAnchoredPoint(pos and pos.point)
	local minX, maxX, minY, maxY = ACAB:GetSimpleElementCoordinateRange(frame, config.extraMaxYPixels, isRightAnchored)

	page.xSlider:SetMinMaxValues(minX, maxX)
	page.ySlider:SetMinMaxValues(minY, maxY)

	local x = page.xSlider:GetValue()
	local y = page.ySlider:GetValue()

	if x < minX then
		ACAB:SetSliderValueUnsnapped(page.xSlider, minX)
	elseif x > maxX then
		ACAB:SetSliderValueUnsnapped(page.xSlider, maxX)
	end

	if y < minY then
		ACAB:SetSliderValueUnsnapped(page.ySlider, minY)
	elseif y > maxY then
		ACAB:SetSliderValueUnsnapped(page.ySlider, maxY)
	end
end
-------------------------------------------------------------------------
-- Reusable scrollable content area
-- One generic ScrollFrame + wiring helper backs every settings page/tab, so any page that grows past
-- its available height gets scrolling with zero page-specific code.
-------------------------------------------------------------------------

-- How far one mouse-wheel notch moves the scrollbar, in pixels.
local SETTINGS_SCROLL_WHEEL_STEP = 30

-- Creates a native ScrollFrame parented to `parent`, with mouse-wheel scrolling wired in. Content
-- should be parented into whatever scrollchild ACAB:UpdateScrollFrame is later given (via
-- scrollFrame:SetScrollChild), not into scrollFrame itself.
-- scrollbarOnLeft (optional): re-anchors the scrollbar to the LEFT side instead of the default RIGHT.
function ACAB:CreateScrollFrame(parent, name, scrollbarOnLeft)
	local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")

	local scrollBar = getglobal(name .. "ScrollBar")

	scrollFrame.scrollBar = scrollBar

	-- Overrides the template's native OnScrollRangeChanged to a no-op, making ACAB:UpdateScrollFrame
	-- the single source of truth for scrollbar visibility.
	scrollFrame:SetScript("OnScrollRangeChanged", function() end)

	if scrollBar and scrollbarOnLeft then
		scrollBar:ClearAllPoints()
		scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPLEFT", -4, -16)
		scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMLEFT", -4, 16)
	end

	if scrollBar then
		-- Same dark backdrop as the top nav tabs (ACAB:StyleModernButton).
		scrollBar:SetBackdrop({
			bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})

		scrollBar:SetBackdropColor(0.08, 0.08, 0.08, 0.85)
		scrollBar:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
	end

	scrollFrame:EnableMouseWheel(true)

	scrollFrame:SetScript("OnMouseWheel", function()
		if not scrollBar then
			return
		end

		local minVal, maxVal = scrollBar:GetMinMaxValues()
		local newValue = scrollBar:GetValue() - (arg1 * SETTINGS_SCROLL_WHEEL_STEP)

		if newValue < minVal then
			newValue = minVal
		elseif newValue > maxVal then
			newValue = maxVal
		end

		scrollBar:SetValue(newValue)
	end)

	if scrollBar then
		-- Moves the scroll view in response to the slider's value changing
		-- (the up/down buttons and thumb-drag both work by changing it).
		scrollBar:SetScript("OnValueChanged", function()
			scrollFrame:SetVerticalScroll(this:GetValue())
		end)
	end

	return scrollFrame
end

-- Points `scrollFrame` at `scrollChild` (a plain Frame the caller already
-- parents its real page content into), sizes the scrollchild to
-- `requiredContentHeight` and the scrollFrame to the clamped
-- `viewportHeight`, restores scroll to `preserveScroll` (clamped to the
-- new range), and shows/hides the scrollbar depending on whether there's
-- anything to scroll. Called every time a page's content changes.
-- preserveScroll (optional): scroll offset to restore, in the same units
-- as GetVerticalScroll()/SetMinMaxValues (pixels). Omitted/nil starts at
-- the top.
function ACAB:UpdateScrollFrame(scrollFrame, scrollChild, requiredContentHeight, viewportHeight, preserveScroll)
	scrollChild:SetWidth(scrollFrame:GetWidth())
	scrollChild:SetHeight(requiredContentHeight)

	scrollFrame:SetScrollChild(scrollChild)
	scrollFrame:SetHeight(viewportHeight)

	local scrollBar = scrollFrame.scrollBar

	local maxScroll = requiredContentHeight - viewportHeight

	if maxScroll < 0 then
		maxScroll = 0
	end

	local targetScroll = preserveScroll or 0

	if targetScroll > maxScroll then
		targetScroll = maxScroll
	end

	if targetScroll < 0 then
		targetScroll = 0
	end

	scrollFrame:SetVerticalScroll(targetScroll)

	if scrollBar then
		scrollBar:SetMinMaxValues(0, maxScroll)
		scrollBar:SetValue(targetScroll)

		if maxScroll > 0 then
			scrollBar:Show()
		else
			scrollBar:Hide()
		end

		-- Each scrollframe that cares supplies its own re-layout callback at creation time, to hand the
		-- space a hidden scrollbar would have occupied back to the content.
		scrollFrame.needsScrollbar = maxScroll > 0

		if scrollFrame.applyScrollbarReserve then
			scrollFrame.applyScrollbarReserve()
			scrollChild:SetWidth(scrollFrame:GetWidth())
		end
	end
end

-- Lets other files check whether the settings window has been built this session without forcing it
-- into existence, unlike the ACAB:GetOrCreate*/RefreshBarList functions, which create it lazily.
function ACAB:IsSettingsFrameCreated()
	return ACAB.settingsFrame ~= nil
end

-------------------------------------------------------------------------
-- Create main settings frame
-------------------------------------------------------------------------

-- Every GetOrCreate*Page/Panel builder across all three settings files lazily creates the shell
-- through this same entry point.
function ACAB:CreateSettingsFrame()
	local f = CreateFrame(
		"Frame",
		"ACABSettingsFrame",
		UIParent
	)

	f:SetWidth(780)
	f:SetHeight(680)

	f:SetPoint(
		"CENTER",
		UIParent,
		"CENTER",
		0,
		0
	)

	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")

	f:SetScript(
		"OnDragStart",
		SettingsFrame_OnDragStart
	)

	f:SetScript(
		"OnDragStop",
		SettingsFrame_OnDragStop
	)

	f:SetBackdrop({
		bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
		edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
		tile = true,
		tileSize = 32,
		edgeSize = 32,
		insets = {
			left = 11,
			right = 12,
			top = 12,
			bottom = 11
		},
	})

	f:Hide()

	-------------------------------------------------------------------------
	-- Title
	-------------------------------------------------------------------------

	local title = f:CreateFontString(
		nil,
		"OVERLAY",
		"GameFontNormalLarge"
	)

	title:SetPoint(
		"TOP",
		f,
		"TOP",
		0,
		-16
	)

	title:SetText("AlternativeClassicActionBars Settings")

	-------------------------------------------------------------------------
	-- Close
	-------------------------------------------------------------------------

	local closeButton = CreateFrame(
		"Button",
		"ACABSettingsCloseButton",
		f,
		"UIPanelCloseButton"
	)

	closeButton:SetPoint(
		"TOPRIGHT",
		f,
		"TOPRIGHT",
		-4,
		-4
	)

	closeButton:SetScript(
		"OnClick",
		function()
			f:Hide()
		end
	)

	-------------------------------------------------------------------------
	-- Top-level view tabs ("Bars" / "General" / "Profiles")
	-- ShowBarsView/ShowGeneralView/ShowProfilesView own which panel is shown, mirroring the
	-- show/hide-one-page-at-a-time pattern GetOrCreateBarPage/ShowBarPage use for individual bar pages.
	-------------------------------------------------------------------------

	f.currentView = "bars"

	-- Top nav tabs get a fading gold highlight instead of ACAB:StyleModernButton's default solid
	-- border swap. Matches StyleModernButton's backdrop insets (3px each side) so the fade strip stays
	-- inside the button's black backdrop rectangle.
	local TAB_FADE_INSET = 3

	-- StyleModernButton's rest-state border color, used as the tab's "inactive" border color since tabs
	-- keep a real border for visual distinctness.
	local TAB_BORDER_REST_COLOR = { 0.55, 0.55, 0.55 }

	local function ApplyTabFadeHighlight(button)
		local stripWidth = 90 - (TAB_FADE_INSET * 2)
		local stripHeight = 20 - (TAB_FADE_INSET * 2)

		-- Persistent highlight for whichever tab matches the currently open view, same gold
		-- UI_ACCENT_COLOR as the bar-list sidebar's selected row. Created first so hoverStrip draws on top.
		local selectStrip = ACAB:CreateFadeStrip(button, stripWidth, stripHeight)

		selectStrip:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", TAB_FADE_INSET, TAB_FADE_INSET)
		selectStrip:SetFadeColor(ACAB.UI_ACCENT_COLOR[1], ACAB.UI_ACCENT_COLOR[2], ACAB.UI_ACCENT_COLOR[3])
		selectStrip:SetPeakAlpha(0.5)
		selectStrip:Hide()

		button.tabSelectStrip = selectStrip

		-- Hover uses the neutral UI_HOVER_COLOR, matching the bar-list sidebar's hover/select split so
		-- "hovering" and "currently open" stay distinguishable.
		local hoverStrip = ACAB:CreateFadeStrip(button, stripWidth, stripHeight)

		hoverStrip:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", TAB_FADE_INSET, TAB_FADE_INSET)
		hoverStrip:SetFadeColor(ACAB.UI_HOVER_COLOR[1], ACAB.UI_HOVER_COLOR[2], ACAB.UI_HOVER_COLOR[3])
		hoverStrip:SetPeakAlpha(0.5)
		hoverStrip:Hide()

		button.isHovering = false

		-- Border color tracks whichever fade is most prominent: hover wins over select, select wins over rest.
		function button:UpdateFadeBorderColor()
			if self.isHovering then
				self:SetBackdropBorderColor(ACAB.UI_HOVER_COLOR[1], ACAB.UI_HOVER_COLOR[2], ACAB.UI_HOVER_COLOR[3], 1)
			elseif self.tabSelectStrip and self.tabSelectStrip:IsShown() then
				self:SetBackdropBorderColor(ACAB.UI_ACCENT_COLOR[1], ACAB.UI_ACCENT_COLOR[2], ACAB.UI_ACCENT_COLOR[3], 1)
			else
				self:SetBackdropBorderColor(TAB_BORDER_REST_COLOR[1], TAB_BORDER_REST_COLOR[2], TAB_BORDER_REST_COLOR[3], 1)
			end
		end

		button:UpdateFadeBorderColor()

		-- Replaces the OnEnter/OnLeave StyleModernButton installed; OnMouseDown/OnMouseUp are untouched.
		button:SetScript("OnEnter", function()
			this.isHovering = true
			hoverStrip:Show()
			this:UpdateFadeBorderColor()
		end)

		button:SetScript("OnLeave", function()
			this.isHovering = false
			hoverStrip:Hide()
			this:UpdateFadeBorderColor()
		end)
	end

	local tabBarsButton = CreateFrame(
		"Button",
		nil,
		f
	)

	tabBarsButton:SetHeight(20)

	tabBarsButton:SetPoint(
		"TOPLEFT",
		f,
		"TOPLEFT",
		18,
		-34
	)

	ACAB:StyleModernButton(tabBarsButton, 90, 90)
	tabBarsButton:SetText("Bars")
	ApplyTabFadeHighlight(tabBarsButton)

	tabBarsButton:SetScript(
		"OnClick",
		function()
			ACAB:ShowBarsView()
		end
	)

	local tabGeneralButton = CreateFrame(
		"Button",
		nil,
		f
	)

	tabGeneralButton:SetHeight(20)

	tabGeneralButton:SetPoint(
		"LEFT",
		tabBarsButton,
		"RIGHT",
		6,
		0
	)

	ACAB:StyleModernButton(tabGeneralButton, 90, 90)
	tabGeneralButton:SetText("General")
	ApplyTabFadeHighlight(tabGeneralButton)

	tabGeneralButton:SetScript(
		"OnClick",
		function()
			ACAB:ShowGeneralView()
		end
	)

	local tabProfilesButton = CreateFrame(
		"Button",
		nil,
		f
	)

	tabProfilesButton:SetHeight(20)

	tabProfilesButton:SetPoint(
		"LEFT",
		tabGeneralButton,
		"RIGHT",
		6,
		0
	)

	ACAB:StyleModernButton(tabProfilesButton, 90, 90)
	tabProfilesButton:SetText("Profiles")
	ApplyTabFadeHighlight(tabProfilesButton)

	tabProfilesButton:SetScript(
		"OnClick",
		function()
			ACAB:ShowProfilesView()
		end
	)

	local tabEditModeButton = CreateFrame(
		"Button",
		nil,
		f
	)

	tabEditModeButton:SetHeight(20)

	tabEditModeButton:SetPoint(
		"LEFT",
		tabProfilesButton,
		"RIGHT",
		6,
		0
	)

	ACAB:StyleModernButton(tabEditModeButton, 90, 90)
	tabEditModeButton:SetText("Edit Mode")
	ApplyTabFadeHighlight(tabEditModeButton)

	tabEditModeButton:SetScript(
		"OnClick",
		function()
			ACAB:ShowEditModeView()
		end
	)

	f.tabButtonsByView = {
		bars = tabBarsButton,
		general = tabGeneralButton,
		profiles = tabProfilesButton,
		editmode = tabEditModeButton,
	}

	-- Matches f.currentView's initial value ("bars"); set manually since ACAB.settingsFrame isn't
	-- assigned yet for RefreshActiveTabHighlight to use.
	tabBarsButton.tabSelectStrip:Show()
	tabBarsButton:UpdateFadeBorderColor()

	-------------------------------------------------------------------------
	-- Divider between the tab row and the content below it. Two-point SetPoint (no fixed width) so it
	-- stretches to match the window's width regardless of which view resized it.
	-------------------------------------------------------------------------

	local tabContentDivider = f:CreateTexture(nil, "ARTWORK")

	tabContentDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
	tabContentDivider:SetVertexColor(0.5, 0.5, 0.5, 0.6)
	tabContentDivider:SetHeight(1)

	tabContentDivider:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -59)
	tabContentDivider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -59)

	-------------------------------------------------------------------------
	-- Left bar list
	-------------------------------------------------------------------------

	-- f.listPanel is the fixed viewport, same shape as contentScrollFrame below. f.listContent is its
	-- permanent scroll child that bar-list rows/divider get parented into, sized to the full row-list
	-- height so ACAB:UpdateScrollFrame can turn scrolling on when needed.
	f.listPanel = ACAB:CreateScrollFrame(f, "ACABSettingsListScrollFrame", true)

	f.listPanel:SetWidth(140)
	f.listPanel:SetHeight(610)

	-- Positioned by ApplyBarsViewScrollbarReserves (below): reserves scrollbar space only while shown.

	-- Same backdrop as contentScrollFrame below, so the row list reads as one bordered/divided container.
	f.listPanel:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = {
			left = 2,
			right = 2,
			top = 2,
			bottom = 2
		},
	})

	f.listPanel:SetBackdropColor(
		0,
		0,
		0,
		0.3
	)

	f.barButtons = {}
	f.barButtonsByBarId = {}

	-- Lives on the viewport (f.listPanel), not the scrolling f.listContent below, so it stays fixed at
	-- the top regardless of scroll position.
	local listTitle = f.listPanel:CreateFontString(
		nil,
		"OVERLAY",
		"GameFontNormal"
	)

	listTitle:SetPoint(
		"TOP",
		f.listPanel,
		"TOP",
		0,
		-8
	)

	listTitle:SetText("Action Bars")

	f.listContent = CreateFrame("Frame", nil, f.listPanel)

	-- SetWidth/SetHeight + SetScrollChild must be called immediately here, not left until the first
	-- deferred Fit, or the list renders nothing until the next-frame-deferred Fit finally runs.
	f.listContent:SetWidth(f.listPanel:GetWidth())
	f.listContent:SetHeight(610)

	f.listPanel:SetScrollChild(f.listContent)

	-------------------------------------------------------------------------
	-- Right content panel: contentScrollFrame is the fixed viewport for the Bars view, contentPanel its
	-- scroll child (ACAB:UpdateScrollFrame resizes it to fit the showing bar page). General/Profiles
	-- get their own pair (ACAB:CreateWideContentScrollFrame) instead of sharing this.
	-- WARNING: a scrollframe must stay permanently paired with the scrollchild it was created with -
	-- never re-target it at a different frame, or that frame renders with no resolvable position/size.
	-------------------------------------------------------------------------

	f.contentScrollFrame = ACAB:CreateScrollFrame(f, "ACABSettingsContentScrollFrame")

	f.contentScrollFrame:SetHeight(610)

	-------------------------------------------------------------------------
	-- Bars-view horizontal geometry: both panels' widths/anchors are recomputed from whichever
	-- scrollbars are currently shown, so an unscrolled panel gets that space back.
	-------------------------------------------------------------------------

	local BARS_VIEW_PADDING = 18
	local BARS_VIEW_LIST_WIDTH = 140
	local BARS_VIEW_PANEL_GAP = 2
	local BARS_VIEW_TOP = -64

	local function ApplyBarsViewScrollbarReserves()
		local leftReserve = f.listPanel.needsScrollbar and SETTINGS_SCROLLBAR_RESERVED_WIDTH or 0
		local rightReserve = f.contentScrollFrame.needsScrollbar and SETTINGS_SCROLLBAR_RESERVED_WIDTH or 0

		f.listPanel:ClearAllPoints()
		f.listPanel:SetPoint(
			"TOPLEFT",
			f,
			"TOPLEFT",
			BARS_VIEW_PADDING + leftReserve,
			BARS_VIEW_TOP
		)

		f.contentScrollFrame:ClearAllPoints()
		f.contentScrollFrame:SetPoint(
			"TOPRIGHT",
			f,
			"TOPRIGHT",
			-BARS_VIEW_PADDING - rightReserve,
			BARS_VIEW_TOP
		)

		-- Anchored by TOPRIGHT, so its width is what sets its left edge (the gap to the bar list beside it).
		f.contentScrollFrame:SetWidth(
			f:GetWidth()
				- (2 * BARS_VIEW_PADDING)
				- BARS_VIEW_LIST_WIDTH
				- BARS_VIEW_PANEL_GAP
				- leftReserve
				- rightReserve
		)
	end

	f.listPanel.applyScrollbarReserve = ApplyBarsViewScrollbarReserves
	f.contentScrollFrame.applyScrollbarReserve = ApplyBarsViewScrollbarReserves

	ApplyBarsViewScrollbarReserves()

	f.contentScrollFrame:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = {
			left = 2,
			right = 2,
			top = 2,
			bottom = 2
		},
	})

	f.contentScrollFrame:SetBackdropColor(
		0,
		0,
		0,
		0.3
	)

	f.contentPanel = CreateFrame(
		"Frame",
		nil,
		f.contentScrollFrame
	)

	f.contentPanel:SetWidth(f.contentScrollFrame:GetWidth())
	f.contentPanel:SetHeight(610)

	f.contentScrollFrame:SetScrollChild(f.contentPanel)

	f.pages = {}

	ACAB.settingsFrame = f

	return f
end

-- Creates one scrollframe+scrollchild pair spanning the full content width (the space the bar list
-- would otherwise occupy, hidden in General/Profiles). Returns scrollFrame, scrollChild - caller
-- stores both and builds its real content into scrollChild.
function ACAB:CreateWideContentScrollFrame(name)
	local scrollFrame = ACAB:CreateScrollFrame(ACAB.settingsFrame, name)

	scrollFrame:SetHeight(610)

	-- Must read ACAB.settingsFrame:GetWidth() (a fixed literal, never anchor-derived) rather than an
	-- anchor-implied width, which isn't guaranteed resolved yet the moment code reads it back.
	-- Only reserves room for its own scrollbar while shown - an unscrolled panel gets the full width.
	scrollFrame.applyScrollbarReserve = function()
		local reserve = scrollFrame.needsScrollbar and SETTINGS_SCROLLBAR_RESERVED_WIDTH or 0

		scrollFrame:SetWidth(ACAB.settingsFrame:GetWidth() - 18 - 18 - reserve)

		scrollFrame:ClearAllPoints()
		scrollFrame:SetPoint(
			"TOPRIGHT",
			ACAB.settingsFrame,
			"TOPRIGHT",
			-18 - reserve,
			-64
		)
	end

	scrollFrame.applyScrollbarReserve()

	scrollFrame:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})

	scrollFrame:SetBackdropColor(0, 0, 0, 0.3)

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)

	scrollChild:SetWidth(scrollFrame:GetWidth())
	scrollChild:SetHeight(610)

	scrollFrame:SetScrollChild(scrollChild)

	return scrollFrame, scrollChild
end
-------------------------------------------------------------------------
-- Default-PROFILE lock, distinct from ApplyDefaultLayoutGating below (which gates the unrelated
-- "Force Vanilla Layout Mode" checkbox - both gates are independent and can apply to the same controls
-- at once). The Default PROFILE must never be edited: every settings page shows a red warning banner
-- and locks its controls while it's active.
-------------------------------------------------------------------------

-- Text shown while the Default PROFILE is active - takes priority over the layout-lock text below if
-- both conditions are true at once (the Default profile's restriction is the broader one).
local PROFILE_LOCK_MESSAGE_PROFILE =
	"Editing Settings is prohibited while in default profile mode. " ..
	"Set up a profile if you wish to change Settings or access Layout " ..
	"Edit Mode. |cffffd100Click to create one now.|r"

-- Text shown while "Force Vanilla Layout Mode" (General tab) is on, on pages that gate only applies to
-- (bar 1 and the simple/native-backed pages).
local PROFILE_LOCK_MESSAGE_LAYOUT =
	"Editing Settings is prohibited while Force Vanilla Layout Mode " ..
	"is enabled. Disable it under General Settings if you wish to " ..
	"change Settings or access Layout Edit Mode. " ..
	"|cffffd100Click to jump to General Settings.|r"

-- Single entry point for "the user clicked something locked by the Default-profile/Force-default-layout
-- gate, now what" - used by the lock banner's OnClick and any locked control that opts into the same
-- behavior. Re-checks live state so priority always matches PROFILE_LOCK_MESSAGE_PROFILE's priority
-- (default profile wins when both are true). Default profile skips straight to the create-profile
-- dialog; otherwise, if only layout-force is on, jumps to General and pulses that checkbox.
function ACAB:HandleLockReasonClick()
	if ACAB:IsDefaultProfileActive() then
		ACAB:ShowCreateProfileDialog(function(ok)
			if ok then
				ACAB:ApplyUseDefaultLayoutChange(false)

				local generalPanel = ACAB.settingsFrame and ACAB.settingsFrame.generalPanel

				if generalPanel and generalPanel.useDefaultLayoutCheckbox then
					generalPanel.useDefaultLayoutCheckbox:SetChecked(false)
				end
			end
		end)
	elseif ACABDB.useDefaultLayout == true then
		ACAB:OpenSettingsPageByName("general")
		ACAB:HighlightGeneralLayoutCheckbox()
	end
end

-- One reusable warning banner per page - a solid strip anchored right below the page's title and right
-- above its first content control. Hidden by default; toggled (and its exact height/text) set by
-- ApplyProfileLockGating below - text isn't fixed at creation time since which message applies can change live.
function ACAB:CreateProfileLockWarning(page)
	-- "Button", not "Frame" - a plain Frame has no "OnClick" script handler in this client.
	local banner = CreateFrame("Button", nil, page)

	-- Parented to `page` (so it hides/shows along with it) but anchored to contentPanel - `page` itself
	-- slides down by this banner's height only while shown, and the banner has to stay put in that band.
	banner:SetPoint("TOPLEFT", ACAB.settingsFrame.contentPanel, "TOPLEFT", 0, PROFILE_LOCK_BANNER_TOP)
	banner:SetPoint("TOPRIGHT", ACAB.settingsFrame.contentPanel, "TOPRIGHT", 0, PROFILE_LOCK_BANNER_TOP)
	banner:SetHeight(PROFILE_LOCK_BANNER_HEIGHT)
	banner:SetFrameLevel(page:GetFrameLevel() + 5)

	banner:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 12,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})

	banner.lockedBackdropColor = { 0.35, 0, 0, 0.9 }
	banner.hoverBackdropColor = { 0.5, 0.08, 0.08, 0.9 }

	banner:SetBackdropColor(unpack(banner.lockedBackdropColor))

	local text = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

	text:SetPoint("TOPLEFT", banner, "TOPLEFT", ACAB.INDENT_SECTION, -6)
	text:SetPoint("TOPRIGHT", banner, "TOPRIGHT", -ACAB.INDENT_SECTION, -6)
	text:SetJustifyH("LEFT")
	text:SetJustifyV("TOP")
	text:SetTextColor(1, 0.15, 0.15)

	banner.text = text

	banner:EnableMouse(true)

	banner:SetScript("OnEnter", function()
		this:SetBackdropColor(unpack(this.hoverBackdropColor))
	end)

	banner:SetScript("OnLeave", function()
		this:SetBackdropColor(unpack(this.lockedBackdropColor))
	end)

	-- Shared with every other locked control's click - one place owns "what does clicking something
	-- locked by this reason do".
	banner:SetScript("OnClick", function()
		ACAB:HandleLockReasonClick()
	end)

	banner:Hide()

	return banner
end

-- Opens/collapses the band the profile-lock banner occupies by sliding `page` down by the banner's
-- height only while shown. Works by moving `page` itself; the page title and banner stay anchored to
-- contentPanel instead so they don't move with it.
function ACAB:ApplyPageBannerReserve(page, locked)
	if not page or not ACAB.settingsFrame or not ACAB.settingsFrame.contentPanel then
		return
	end

	local reserve = 0

	if locked then
		-- The banner's real height, not PROFILE_LOCK_BANNER_HEIGHT: recomputed from however many
		-- lines its message wraps to, which can exceed that constant. Falls back if not measured yet.
		reserve = (page.profileLockWarning and page.profileLockWarning:GetHeight())
			or PROFILE_LOCK_BANNER_HEIGHT

		if reserve < PROFILE_LOCK_BANNER_HEIGHT then
			reserve = PROFILE_LOCK_BANNER_HEIGHT
		end
	end

	page:ClearAllPoints()
	page:SetPoint("TOPLEFT", ACAB.settingsFrame.contentPanel, "TOPLEFT", 0, -reserve)
	page:SetPoint("BOTTOMRIGHT", ACAB.settingsFrame.contentPanel, "BOTTOMRIGHT", 0, 0)
end

-- Sets the banner's message and resizes it to fit however many lines that message actually wraps to at
-- the page's current width, so a longer message or narrower window never gets cut off.
local function SetProfileLockBannerMessage(banner, message)
	-- Must set explicit SetWidth on both banner and text - a TOPLEFT+TOPRIGHT anchor pair alone does
	-- not reliably wrap text in this environment (renders as one long line instead).
	local page = banner:GetParent()
	local width = page:GetWidth()

	if width and width > 0 then
		banner:SetWidth(width)
		banner.text:SetWidth(width - (2 * ACAB.INDENT_SECTION))
	end

	banner.text:SetText(message)
	banner:SetHeight((banner.text:GetHeight() or 0) + 12)
end

function ACAB:LockControl(control, locked)
	control:EnableMouse(not locked)
	control:SetAlpha(locked and 0.5 or 1)

	-- Templated Buttons additionally need :Disable()/:Enable() - EnableMouse alone doesn't grey them
	-- out or block their OnClick the way it does for sliders/template-less swatch buttons.
	if control.Disable and control.Enable then
		if locked then
			control:Disable()
		else
			control:Enable()
		end
	end
end

-- Greys `control` like ACAB:LockControl, but never touches EnableMouse or Disable()/Enable() - both
-- also swallow OnEnter/OnLeave entirely on this client, which would kill a "why is this locked" tooltip.
-- Only stamps control.ACABLocked; the actual click-block lives in CreateLabeledCheckbox's own OnClick wrapper.
function ACAB:LockControlKeepingTooltip(control, locked)
	control.ACABLocked = locked and true or false

	control:SetAlpha(locked and 0.5 or 1)
end

-- Every optional widget name either a full bar page or a simple bar page can have on itself. Checked by
-- presence so the same list works for both page shapes. enableCheckbox is locked like everything else
-- by default - only exempted, inline below, for the numbered default bars (1-5).
local PROFILE_LOCK_CONTROL_NAMES = {
	"xSlider", "ySlider", "xStepperBigMinus", "xStepperMinus", "xStepperPlus", "xStepperBigPlus",
	"yStepperBigMinus", "yStepperMinus", "yStepperPlus", "yStepperBigPlus", "xValueClick", "yValueClick",
	"buttonSizeSlider", "spacingSlider",
	"scaleSlider", "resetPositionButton", "resetModernButton", "enableCheckbox",
	"buttonCountMinus", "buttonCountPlus", "pageIndicatorSlider",
	"orientationCheckbox", "keyRingCheckbox", "keyRingScaleSlider",
	"betterExpBarCheckbox", "expBarShowLevelCheckbox",
	"expBarShowCurrentOverMaxCheckbox", "expBarShowPercentCheckbox",
	"expBarShowRestedPercentCheckbox", "expBarShowRestedTotalCheckbox",
	"expBarFontSizeSlider", "earnedColorSwatch", "restedColorSwatch",
	"expBarTextColorSwatch", "expBarGlowPulseIntervalSlider",
	"useVanillaPetBarCheckbox", "condenseEmptyPetSlotsCheckbox",
	"animateAutoCastGlowCheckbox", "useVanillaStanceBarCheckbox",
	"hoverOnlyCheckbox", "hoverDurationSlider",
}

-- alsoCheckLayoutLock: true on the pages the Default-layout lock also applies to (bar 1's page, every
-- simple/native-backed page) - the banner shows for that lock too, with its own message, and the same
-- combined lock drives control-locking below.
function ACAB:ApplyProfileLockGating(page, alsoCheckLayoutLock)
	local profileLocked = self:IsDefaultProfileActive()
	local layoutLocked = alsoCheckLayoutLock and (ACABDB.useDefaultLayout == true)
	local locked = profileLocked or layoutLocked

	if page.profileLockWarning then
		page.profileLockWarning:SetShown(locked)

		if locked then
			-- Profile lock takes priority (the banner's OnClick re-derives this same priority live).
			SetProfileLockBannerMessage(
				page.profileLockWarning,
				profileLocked and PROFILE_LOCK_MESSAGE_PROFILE or PROFILE_LOCK_MESSAGE_LAYOUT
			)
		end
	end

	-- Opens up the banner's band only while it's actually shown, instead of every page permanently reserving it.
	ACAB:ApplyPageBannerReserve(page, locked)

	-- Numbered default bars (1-5, Pet Bar) keep enable/disable available even while everything else
	-- locks - every other page has no exemption.
	local barId = page.barId
	local isNumberedDefaultBar = type(barId) == "number" and ACAB:IsDefaultBarFamilyId(barId)

	local i

	for i = 1, table.getn(PROFILE_LOCK_CONTROL_NAMES) do
		local name = PROFILE_LOCK_CONTROL_NAMES[i]
		local control = page[name]

		if control then
			local exempt = isNumberedDefaultBar and name == "enableCheckbox"

			ACAB:LockControl(control, locked and not exempt)
		end
	end

	if page.gridSwatches then
		for i = 1, table.getn(page.gridSwatches) do
			ACAB:LockControl(page.gridSwatches[i], locked)
		end
	end

	if page.assignmentRows then
		for i = 1, table.getn(page.assignmentRows) do
			local row = page.assignmentRows[i]

			if row.dropdown then
				-- EnableMouse(false) on the dropdown frame itself doesn't block its click handling -
				-- UIDropDownMenuTemplate's clickable region is a separate child Button needing :Disable()/:Enable().
				local dropdownButton = getglobal(row.dropdown:GetName() .. "Button")

				if dropdownButton then
					ACAB:LockControl(dropdownButton, locked)
				else
					ACAB:LockControl(row.dropdown, locked)
				end
			end
		end
	end
end

-------------------------------------------------------------------------
-- Default-layout gating (General tab's "Force Vanilla Layout Mode")
-- Uses EnableMouse(false) rather than Slider/Button Enable()/Disable() - a universal Frame method that
-- also works on template-less grid swatch buttons. Only simple/native-backed pages call this; default
-- bars (1-5) get the same effect via ApplyProfileLockGating's alsoCheckLayoutLock; custom bars never gate on this.
-------------------------------------------------------------------------

function ACAB:ApplyDefaultLayoutGating(page, interactive)
	local alpha = interactive and 1 or 0.5

	if page.xSlider then
		page.xSlider:EnableMouse(interactive)
		page.xSlider:SetAlpha(alpha)
	end

	if page.ySlider then
		page.ySlider:EnableMouse(interactive)
		page.ySlider:SetAlpha(alpha)
	end

	-- Stepper buttons and the click-to-edit value readouts gate the same way the sliders they flank do.
	local positionButtonNames = {
		"xStepperBigMinus", "xStepperMinus", "xStepperPlus", "xStepperBigPlus",
		"yStepperBigMinus", "yStepperMinus", "yStepperPlus", "yStepperBigPlus",
		"xValueClick", "yValueClick",
	}

	local pi

	for pi = 1, table.getn(positionButtonNames) do
		local control = page[positionButtonNames[pi]]

		if control then
			control:EnableMouse(interactive)
			control:SetAlpha(alpha)

			if interactive then
				control:Enable()
			else
				control:Disable()
			end
		end
	end

	if page.buttonSizeSlider then
		page.buttonSizeSlider:EnableMouse(interactive)
		page.buttonSizeSlider:SetAlpha(alpha)
	end

	if page.spacingSlider then
		page.spacingSlider:EnableMouse(interactive)
		page.spacingSlider:SetAlpha(alpha)
	end

	if page.hoverOnlyCheckbox then
		page.hoverOnlyCheckbox:EnableMouse(interactive)
		page.hoverOnlyCheckbox:SetAlpha(alpha)

		-- EnableMouse alone doesn't block this template's OnClick, see LockControl's comment above.
		if interactive then
			page.hoverOnlyCheckbox:Enable()
		else
			page.hoverOnlyCheckbox:Disable()
		end
	end

	if page.hoverDurationSlider then
		page.hoverDurationSlider:EnableMouse(interactive)
		page.hoverDurationSlider:SetAlpha(alpha)
	end

	if page.gridSwatches then
		local i

		for i = 1, table.getn(page.gridSwatches) do
			local swatch = page.gridSwatches[i]

			swatch:EnableMouse(interactive)
			swatch:SetAlpha(alpha)
		end
	end
end

-- Re-applies gating to every currently-built default-bar page (1-5) - called whenever the General
-- tab's checkbox changes, so any page already open/cached updates immediately.
function ACAB:RefreshDefaultLayoutGatingOnAllPages()
	if not ACAB.settingsFrame then
		return
	end

	local i

	for i = 1, table.getn(ACAB.DEFAULT_BAR_IDS) do
		local id = ACAB.DEFAULT_BAR_IDS[i]

		if ACAB.settingsFrame.pages[id] then
			self:RefreshBarSettingsPage(id)
		end
	end

	-- Bag Bar / Micro Menu / Latency Bar / Experience Bar / Cast Bar are also gated on
	-- useDefaultLayout, so their pages need the same live refresh if already built/cached. Stance Bar
	-- (like Pet Bar) is covered by the ACAB.DEFAULT_BAR_IDS loop above, keyed by its own numeric id.
	local specialKeys = { "bagbar", "micromenu", "latencybar", "expbar", "castbar", "tooltip" }
	local si

	for si = 1, table.getn(specialKeys) do
		if ACAB.settingsFrame.pages[specialKeys[si]] then
			self:RefreshBarSettingsPage(specialKeys[si])
		end
	end
end

-------------------------------------------------------------------------
-- Dynamic content-panel/window height: measures the real on-screen bottom edge of whichever controls
-- are actually shown, so each page gets a window sized to its own content instead of a fixed size
-- tuned for the busiest page.
-------------------------------------------------------------------------

-- Distance from the settings window's top edge down to contentPanel/listPanel's top, and from their
-- bottom edge down to the window's own bottom edge - the fixed "chrome" every view's content sits inside.
local SETTINGS_CHROME_TOP = 64
local SETTINGS_CHROME_BOTTOM = 18

-- Never shrinks below whatever the current view naturally needs to avoid feeling cramped.
local SETTINGS_CONTENT_MIN_HEIGHT = 260

-- The settings window can never grow taller than this fraction of the player's actual screen height.
local SETTINGS_MAX_HEIGHT_RATIO = 0.9

-- Appends frame to list only if non-nil, at the next free index. table.getn/# have undefined behavior
-- on tables with nil "holes" (Lua 5.0 manual), so candidate lists are built through this helper rather
-- than a table constructor with nils embedded in it.
local function AppendCandidate(list, n, frame)
	if frame then
		list[n + 1] = frame
		return n + 1
	end

	return n
end

-- Deepest distance from `referenceTop` down to any candidate's bottom edge - how much vertical room
-- the content needs.
-- WARNING: measured as a delta between two live positions, not a computed screen-center estimate - the
-- settings window is movable, so a position-derived estimate goes wrong once dragged.
local function MeasureDeepestExtent(candidateList, referenceTop)
	if not candidateList or not referenceTop then
		return nil
	end

	local deepest = nil
	local i

	for i = 1, table.getn(candidateList) do
		local frame = candidateList[i]

		if frame and frame.GetBottom and not (frame.IsShown and not frame:IsShown()) then
			local bottom = frame:GetBottom()

			if bottom then
				local depth = referenceTop - bottom

				if not deepest or depth > deepest then
					deepest = depth
				end
			end
		end
	end

	return deepest
end

-- Resizes `scrollChildPanel`/listPanel/the outer window to fit the lowest bottom edge in candidateList,
-- floored at SETTINGS_CONTENT_MIN_HEIGHT and capped at the screen-relative max.
-- listCandidateList (optional): fits/scrolls the bar-list sidebar independently using the same shared
-- viewportHeight. minContentHeight (optional): floor on top of SETTINGS_CONTENT_MIN_HEIGHT.
-- noMinFloor (optional): skips SETTINGS_CONTENT_MIN_HEIGHT for a view (Profiles) meant to shrink-to-fit.
-- Returns the measured (unclamped, unfloored) content height.
local function ApplySettingsHeightFromCandidates(candidateList, scrollFrame, scrollChildPanel, listCandidateList, minContentHeight, noMinFloor)
	if not ACAB.settingsFrame or not scrollFrame or not scrollChildPanel then
		return nil
	end

	-- Captured before either scroll position gets reset below, so ACAB:UpdateScrollFrame can restore
	-- the user's actual scroll position instead of snapping back to the top on every re-fit.
	local previousContentScroll = scrollFrame:GetVerticalScroll()
	local previousListScroll = listCandidateList and ACAB.settingsFrame.listPanel
		and ACAB.settingsFrame.listPanel:GetVerticalScroll()

	-- Both scroll positions must reset to the top before measuring: GetTop()/GetBottom() read real
	-- screen positions that shift with the current scroll offset.
	scrollFrame:SetVerticalScroll(0)

	if listCandidateList and ACAB.settingsFrame.listPanel then
		ACAB.settingsFrame.listPanel:SetVerticalScroll(0)
	end

	-- Top-down resolve pass. Required, not a debug leftover - the discarded return values ARE the
	-- point (see docs/01-Environment-Capability-Analysis.md §5af).
	-- WARNING: frame rects resolve lazily on this client, against the anchor's own cached rect.
	-- SetVerticalScroll(0) above moves this subtree without re-resolving it, so reading a child while
	-- its ancestor is still stale caches wrong values. Resolving top-down (scrollChildPanel first, then
	-- every measured frame) avoids that - dropping either loop, or reordering it, brings the bug back.
	scrollChildPanel:GetTop()

	local resolveI

	for resolveI = 1, table.getn(candidateList) do
		local resolveFrame = candidateList[resolveI]

		if resolveFrame.GetBottom then
			resolveFrame:GetBottom()
		end
	end

	if scrollChildPanel.hotkeyTitle then
		local resolveNames = {
			"macroTextCheckbox", "macroTitle", "macroSlider", "macroValueText", "macroResetButton",
			"hotkeyTitle", "hotkeySlider", "hotkeyValueText", "hotkeyResetButton",
			"countTitle", "countSlider", "countValueText", "countResetButton",
			"modernBorderStyleCheckbox",
		}

		local resolveJ

		for resolveJ = 1, table.getn(resolveNames) do
			local resolveFrame = scrollChildPanel[resolveNames[resolveJ]]

			if resolveFrame then
				resolveFrame:GetBottom()
			end
		end
	end

	local contentDepth = MeasureDeepestExtent(candidateList, scrollChildPanel:GetTop())

	local listDepth = nil

	if listCandidateList and ACAB.settingsFrame.listContent then
		listDepth = MeasureDeepestExtent(listCandidateList, ACAB.settingsFrame.listContent:GetTop())
	end

	if not contentDepth and not listDepth then
		return nil
	end

	local BOTTOM_MARGIN = 20
	local measuredContentHeight = contentDepth and (contentDepth + BOTTOM_MARGIN) or 0
	local listContentHeight = listDepth and (listDepth + BOTTOM_MARGIN) or 0

	-- The shared viewport is driven by whichever side needs more room -
	-- same "tallest side wins" rule as before, just now from two
	-- independently measured depths instead of one merged bottom edge.
	local sharedRequirement = measuredContentHeight

	if listContentHeight > sharedRequirement then
		sharedRequirement = listContentHeight
	end

	if minContentHeight and sharedRequirement < minContentHeight then
		sharedRequirement = minContentHeight
	end

	if not noMinFloor and sharedRequirement < SETTINGS_CONTENT_MIN_HEIGHT then
		sharedRequirement = SETTINGS_CONTENT_MIN_HEIGHT
	end

	local contentHeight = measuredContentHeight

	if not noMinFloor and contentHeight < SETTINGS_CONTENT_MIN_HEIGHT then
		contentHeight = SETTINGS_CONTENT_MIN_HEIGHT
	end

	-- Clamps the visible viewport height to a screen-relative ceiling.
	-- Real content height (above) stays unclamped for ACAB:UpdateScrollFrame.
	local maxViewportHeight = (GetScreenHeight() * SETTINGS_MAX_HEIGHT_RATIO)
		- SETTINGS_CHROME_TOP - SETTINGS_CHROME_BOTTOM

	local viewportHeight = sharedRequirement

	if viewportHeight > maxViewportHeight then
		viewportHeight = maxViewportHeight
	end

	ACAB:UpdateScrollFrame(
		scrollFrame,
		scrollChildPanel,
		contentHeight,
		viewportHeight,
		previousContentScroll
	)

	if listCandidateList and ACAB.settingsFrame.listPanel and ACAB.settingsFrame.listContent then
		ACAB:UpdateScrollFrame(
			ACAB.settingsFrame.listPanel,
			ACAB.settingsFrame.listContent,
			listContentHeight,
			viewportHeight,
			previousListScroll
		)
	elseif ACAB.settingsFrame.listPanel then
		ACAB.settingsFrame.listPanel:SetHeight(viewportHeight)
	end

	ACAB.settingsFrame:SetHeight(
		viewportHeight + SETTINGS_CHROME_TOP + SETTINGS_CHROME_BOTTOM
	)

	return measuredContentHeight
end

-- Bars view: combines the current bar page's own controls with the bar list's rows - both are visible
-- side by side, so the window has to be tall enough for whichever is actually taller.
function ACAB:FitSettingsWindowToBarPage(barId)
	if not ACAB.settingsFrame then
		return
	end

	local page = ACAB.settingsFrame.pages[barId]

	if not page then
		return
	end

	local candidates = {}
	local n = 0

	n = AppendCandidate(candidates, n, page.hoverOnlyCheckbox)
	n = AppendCandidate(candidates, n, page.hoverDurationSlider)
	n = AppendCandidate(candidates, n, page.hoverDurationValueText)
	n = AppendCandidate(candidates, n, page.xValueText)
	n = AppendCandidate(candidates, n, page.yValueText)
	n = AppendCandidate(candidates, n, page.spacingValueText)
	n = AppendCandidate(candidates, n, page.buttonSizeValueText)
	n = AppendCandidate(candidates, n, page.resetPositionButton)
	n = AppendCandidate(candidates, n, page.resetModernButton)
	n = AppendCandidate(candidates, n, page.buttonCountMinus)
	n = AppendCandidate(candidates, n, page.buttonCountPlus)
	n = AppendCandidate(candidates, n, page.buttonCountValueText)
	n = AppendCandidate(candidates, n, page.enableCheckbox)
	n = AppendCandidate(candidates, n, page.pageIndicatorValueText)
	n = AppendCandidate(candidates, n, page.useVanillaPetBarCheckbox)

	-- Scale/Orientation controls, present on the simple bar pages (Stance Bar/Bag Bar/Micro Menu)
	-- alongside Spacing above - included here since this shared function handles both page shapes.
	n = AppendCandidate(candidates, n, page.scaleValueText)
	n = AppendCandidate(candidates, n, page.orientationCheckbox)
	n = AppendCandidate(candidates, n, page.keyRingCheckbox)
	n = AppendCandidate(candidates, n, page.keyRingScaleValueText)

	-- "Better Experience Bar" + its 5 text toggles + Font Size slider + 3 color pickers + Reset Colors
	-- button + Pulse Interval slider (Experience Bar page only).
	n = AppendCandidate(candidates, n, page.betterExpBarCheckbox)
	n = AppendCandidate(candidates, n, page.expBarFontSizeSlider)
	n = AppendCandidate(candidates, n, page.expBarFontSizeValueText)
	n = AppendCandidate(candidates, n, page.expBarShowLevelCheckbox)
	n = AppendCandidate(candidates, n, page.expBarShowCurrentOverMaxCheckbox)
	n = AppendCandidate(candidates, n, page.expBarShowPercentCheckbox)
	n = AppendCandidate(candidates, n, page.expBarShowRestedPercentCheckbox)
	n = AppendCandidate(candidates, n, page.expBarShowRestedTotalCheckbox)
	n = AppendCandidate(candidates, n, page.earnedColorSwatch)
	n = AppendCandidate(candidates, n, page.restedColorSwatch)
	n = AppendCandidate(candidates, n, page.expBarTextColorSwatch)
	n = AppendCandidate(candidates, n, page.resetColorsButton)
	n = AppendCandidate(candidates, n, page.expBarGlowPulseIntervalSlider)
	n = AppendCandidate(candidates, n, page.expBarGlowPulseIntervalValueText)

	-- Stance/Page Bar Assignment rows - present on any default bar's (1-5) own page. Each row is
	-- included as its own candidate, same convention gridSwatches below uses.
	if page.assignmentRows then
		local i

		for i = 1, table.getn(page.assignmentRows) do
			n = AppendCandidate(candidates, n, page.assignmentRows[i])
		end
	end

	if page.gridSwatches then
		local i

		for i = 1, table.getn(page.gridSwatches) do
			local swatch = page.gridSwatches[i]

			n = AppendCandidate(candidates, n, swatch)
			n = AppendCandidate(candidates, n, swatch.caption)
		end
	end

	-- Stance Bar's "no stances currently available" message takes the grid swatches' place.
	n = AppendCandidate(candidates, n, page.noStancesText)

	n = AppendCandidate(candidates, n, page.useVanillaStanceBarCheckbox)

	-- Measured/fitted separately from the page's own candidates above - the bar-list sidebar scrolls
	-- independently of the content page, so it needs its own true bottom-most-row measurement.
	local listCandidates = {}
	local listN = 0

	if ACAB.settingsFrame.barButtons then
		local i

		for i = 1, table.getn(ACAB.settingsFrame.barButtons) do
			listN = AppendCandidate(listCandidates, listN, ACAB.settingsFrame.barButtons[i])
		end
	end

	-- The scrollchild is ACAB.settingsFrame.contentPanel itself, not `page` - every bar page uses
	-- page:SetAllPoints(contentPanel), so `page` always just mirrors contentPanel's own rect.
	local measured = ApplySettingsHeightFromCandidates(
		candidates,
		ACAB.settingsFrame.contentScrollFrame,
		ACAB.settingsFrame.contentPanel,
		listCandidates,
		ACAB.settingsFrame.standardBarPageHeight
	)

	-- "Standard bar page" baseline: every numbered bar page except bar 1 is built by the same code path
	-- with the same controls, so they all measure the same height - record it as the window's floor.
	-- This stops the window from resizing between those pages, and from shrinking below that baseline
	-- when a shorter page is selected. Bar 1 is excluded: its assignment rows would inflate the baseline.
	if measured and type(barId) == "number" and barId ~= 1 then
		if not ACAB.settingsFrame.standardBarPageHeight or measured > ACAB.settingsFrame.standardBarPageHeight then
			ACAB.settingsFrame.standardBarPageHeight = measured
		end
	end
end

-- General view: no bar list is shown here, just its checkboxes/sliders.
function ACAB:FitSettingsWindowToGeneralView()
	if not ACAB.settingsFrame or not ACAB.settingsFrame.generalPanel then
		return
	end

	local panel = ACAB.settingsFrame.generalPanel

	local candidates = {}
	local n = 0

	n = AppendCandidate(candidates, n, panel.useDefaultLayoutCheckbox)
	n = AppendCandidate(candidates, n, panel.tintWholeButtonCheckbox)
	n = AppendCandidate(candidates, n, panel.disableBlizzardArtCheckbox)
	n = AppendCandidate(candidates, n, panel.mainBarPaginationCheckbox)
	n = AppendCandidate(candidates, n, panel.mainBarStanceSwapCheckbox)

	-- Stance/Page Bar Assignment rows live on each default bar's (1-5) own settings page - see
	-- FitSettingsWindowToBarPage for their candidate handling.

	n = AppendCandidate(candidates, n, panel.macroTextCheckbox)
	n = AppendCandidate(candidates, n, panel.macroValueText)
	n = AppendCandidate(candidates, n, panel.macroResetButton)

	n = AppendCandidate(candidates, n, panel.hotkeyValueText)
	n = AppendCandidate(candidates, n, panel.hotkeyResetButton)
	n = AppendCandidate(candidates, n, panel.countValueText)
	n = AppendCandidate(candidates, n, panel.countResetButton)
	n = AppendCandidate(candidates, n, panel.modernBorderStyleCheckbox)
	n = AppendCandidate(candidates, n, panel.globalSpacingCheckbox)
	n = AppendCandidate(candidates, n, panel.globalSpacingSlider)
	n = AppendCandidate(candidates, n, panel.globalSpacingValueText)
	n = AppendCandidate(candidates, n, panel.globalButtonSizeCheckbox)
	n = AppendCandidate(candidates, n, panel.globalButtonSizeSlider)
	n = AppendCandidate(candidates, n, panel.globalButtonSizeValueText)
	n = AppendCandidate(candidates, n, panel.bypassBar2DepCheckbox)

	-- "Enable Better Experience Bar" lives on the Experience Bar's own settings page.

	ApplySettingsHeightFromCandidates(candidates, ACAB.settingsFrame.generalScrollFrame, panel)
end
function ACAB:FitSettingsWindowToProfilesView()
	if not ACAB.settingsFrame or not ACAB.settingsFrame.profilesPanel then
		return
	end

	local panel = ACAB.settingsFrame.profilesPanel

	local candidates = {}
	local n = 0

	n = AppendCandidate(candidates, n, panel.profileDropdown)
	n = AppendCandidate(candidates, n, panel.wizardButton)
	n = AppendCandidate(candidates, n, panel.exportButton)
	n = AppendCandidate(candidates, n, panel.copyButton)
	n = AppendCandidate(candidates, n, panel.importButton)
	n = AppendCandidate(candidates, n, panel.deleteButton)

	-- Profiles is a short page by nature - shrink-to-fit instead of matching the other views' floor.
	ApplySettingsHeightFromCandidates(candidates, ACAB.settingsFrame.profilesScrollFrame, panel, nil, nil, true)
end
function ACAB:FitSettingsWindowToEditModeView()
	if not ACAB.settingsFrame or not ACAB.settingsFrame.editModePanel then
		return
	end

	local panel = ACAB.settingsFrame.editModePanel

	local candidates = {}
	local n = 0

	n = AppendCandidate(candidates, n, panel.snapToAdjacentCheckbox)
	n = AppendCandidate(candidates, n, panel.showLayoutGridCheckbox)
	n = AppendCandidate(candidates, n, panel.snapToGridCheckbox)
	n = AppendCandidate(candidates, n, panel.useCustomGridSizeCheckbox)
	n = AppendCandidate(candidates, n, panel.customGridSizeSlider)
	n = AppendCandidate(candidates, n, panel.customGridSizeValueText)

	-- Edit Mode is a short page by nature - shrink-to-fit instead of matching the other views' floor.
	ApplySettingsHeightFromCandidates(candidates, ACAB.settingsFrame.editModeScrollFrame, panel, nil, nil, true)
end
-------------------------------------------------------------------------
-- Show settings
-------------------------------------------------------------------------

function ACAB:ShowSettingsFrame()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	self:RefreshBarList()

	ACAB.settingsFrame:Show()

	if not ACAB.settingsFrame.activeBarId then
		self:ShowBarPage(1)
	elseif ACAB.settingsFrame.currentView == "general" then
		ACAB:DeferFit(function() ACAB:FitSettingsWindowToGeneralView() end)
	elseif ACAB.settingsFrame.currentView == "profiles" then
		ACAB:DeferFit(function() ACAB:FitSettingsWindowToProfilesView() end)
	elseif ACAB.settingsFrame.currentView == "editmode" then
		ACAB:DeferFit(function() ACAB:FitSettingsWindowToEditModeView() end)
	else
		-- RefreshBarList (above) just rebuilt the bar-list rows from scratch, so even though the
		-- active page isn't changing here, the window still needs to refit against the new row count.
		ACAB:DeferFit(function() ACAB:FitSettingsWindowToBarPage(ACAB.settingsFrame.activeBarId) end)
	end
end

-------------------------------------------------------------------------
-- Toggle settings
-------------------------------------------------------------------------

function ACAB:ToggleSettingsFrame()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	if ACAB.settingsFrame:IsShown() then
		ACAB.settingsFrame:Hide()
	else
		self:ShowSettingsFrame()
	end
end
