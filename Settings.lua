-- Settings.lua
-- Settings-window shell: frame, view tabs and scroll areas, position-range math, profile/layout lock
-- gating, and the dynamic window-height fit. Page builders live in SettingsBars.lua/SettingsGeneral.lua.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------

ACAB.BUTTON_SIZE_MIN = 16
ACAB.BUTTON_SIZE_MAX = 64
ACAB.BUTTON_SIZE_STEP = 2

-- Font size slider range (hotkey/count/macro/Experience Bar text).
ACAB.FONT_SIZE_MIN = 6
ACAB.FONT_SIZE_MAX = 24
ACAB.FONT_SIZE_STEP = 1

-- Rounds a font size to the nearest integer and clamps it to [FONT_SIZE_MIN, FONT_SIZE_MAX].
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

-- Spacing slider range shared by every bar page.
ACAB.SPACING_MIN = 0
ACAB.SPACING_MAX = 20
ACAB.SPACING_STEP = 1

-- Real-to-displayed offset for the per-bar spacing slider (not simple-bar or global-spacing sliders).
function ACAB:GetSpacingDisplayOffset()
	return ACAB:IsVanillaBorderStyle() and ACAB.VANILLA_SPACING_FLOOR or 0
end

-- Real per-bar spacing max for the current border style (displayed max stays SPACING_MAX).
function ACAB:GetSpacingMax()
	return ACAB.SPACING_MAX + ACAB:GetSpacingDisplayOffset()
end

-- Simple-page configs by page key. must stay a top-level init: SettingsBars.lua fills it at load time.
ACAB.simpleBarPageConfigs = {}

-- Every string-keyed simple page, in bar-list order.
ACAB.SIMPLE_PAGE_KEYS = { "bagbar", "keyring", "micromenu", "latencybar", "expbar", "castbar", "tooltip" }

-- Settings-page layout indents.
ACAB.INDENT_SECTION = 18
ACAB.INDENT_CONTROL = 22
ACAB.INDENT_INPUT   = 85

-- Runs fn on the next frame; every Fit*View call goes through this so freshly shown panels have real rects.
function ACAB:DeferFit(fn)
	if C_Timer and C_Timer.After then
		C_Timer.After(0, fn)
	else
		fn()
	end
end

-- Width reserved beside a content viewport while its scrollbar is shown.
local SETTINGS_SCROLLBAR_RESERVED_WIDTH = 28

-- Left sidebar (bar list / Setup Wizard step list) width and its gap to the content viewport.
ACAB.SETTINGS_SIDEBAR_WIDTH = 140
ACAB.SETTINGS_SIDEBAR_GAP = 2

-- Profile-lock banner's Y offset below contentPanel's top.
local PROFILE_LOCK_BANNER_TOP = -34

-- Minimum profile-lock banner height; the real height is measured from its wrapped text.
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

-- Finds an Extra Bar's saved config by bar id (ACABDB.bars is an array, not keyed by id).
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
	if ACAB:IsDefaultBarFamilyId(barId) then
		return ACABDB.defaultBars[barId], true
	end

	return ACAB:FindCustomBarConfig(barId), false
end

-------------------------------------------------------------------------
-- Screen coordinate ranges
-------------------------------------------------------------------------

-- Generic X/Y range: twice UIParent's size per axis, covering every anchor corner plus off-screen drags.
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
-- Action-bar X/Y position clamp range
-- Symmetric around screen center: half the screen minus half the bar's visual footprint per axis.
-------------------------------------------------------------------------

function ACAB:GetActionBarCoordinateRange(cfg)
	local screenWidth, screenHeight = ACAB:GetUIParentAnchorSize()

	if not cfg or not cfg.buttonSize then
		return -screenWidth / 2, screenWidth / 2, -screenHeight / 2, screenHeight / 2
	end

	local barWidth, barHeight = ACAB:GetBarFrameSize(cfg)
	local insetLeft, insetRight, insetTop, insetBottom = ACAB:GetElementVisualInset({ config = cfg })

	local visualWidth = barWidth + insetLeft + insetRight
	local visualHeight = barHeight + insetTop + insetBottom

	-- Condensed Pet Bar: the filled cells' far edges (not the full overlay's) may reach the screen edge.
	local visibleWidth, visibleHeight = visualWidth, visualHeight

	if cfg.isPetBar and ACAB:ShouldCondensePetBarSlots() then
		local cols = cfg.cols or 1
		local filled = ACAB:GetPetBarFilledSlotCount()
		local usedCols, usedRows = cols, 1

		if filled <= 0 then
			usedCols = 1
		elseif filled < cols then
			usedCols = filled
		else
			usedRows = math.ceil(filled / cols)
		end

		local spacing = ACAB:GetBarEffectiveSpacing(cfg)

		visibleWidth = (usedCols * cfg.buttonSize) + ((usedCols - 1) * spacing) + insetLeft + insetRight
		visibleHeight = (usedRows * cfg.buttonSize) + ((usedRows - 1) * spacing) + insetTop + insetBottom
	end

	local minX = -(screenWidth - visualWidth) / 2
	local maxX = (screenWidth / 2) + (visualWidth / 2) - visibleWidth
	local minY = -(screenHeight / 2) - (visualHeight / 2) + visibleHeight
	local maxY = (screenHeight - visualHeight) / 2

	-- Never return a backwards span (max < min) for an oversized bar.
	if maxX < minX then
		maxX = minX
	end

	if maxY < minY then
		maxY = minY
	end

	return minX, maxX, minY, maxY
end

-- Applies an X/Y range to a page's position sliders and clamps their current values into it.
local function ApplyPositionSliderRange(page, minX, maxX, minY, maxY)
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

-- Re-applies an action-bar page's X/Y slider range from the bar's current size and border style.
function ACAB:RefreshPositionSliderRange(page)
	if not page or not page.xSlider or not page.ySlider or not page.barId then
		return
	end

	local cfg = ACAB:GetBarConfig(page.barId)

	if not cfg then
		return
	end

	local minX, maxX, minY, maxY = ACAB:GetActionBarCoordinateRange(cfg)

	ApplyPositionSliderRange(page, minX, maxX, minY, maxY)
end

-------------------------------------------------------------------------
-- Native/simple-element X/Y position clamp range
-- Symmetric around screen center minus half the element's scaled visual footprint;
-- extraMaxYPixels (optional) adds real screen pixels of headroom above the top edge.
-------------------------------------------------------------------------

function ACAB:GetSimpleElementCoordinateRange(frame, extraMaxYPixels)
	local screenWidth, screenHeight = ACAB:GetUIParentAnchorSize()
	local visualWidth, visualHeight = 0, 0

	if frame then
		local frameScale = frame:GetEffectiveScale()
		local uiParentScale = UIParent:GetEffectiveScale()
		local scale = 1

		if frameScale and uiParentScale and uiParentScale ~= 0 then
			scale = frameScale / uiParentScale
		end

		local insetLeft, insetRight, insetTop, insetBottom = ACAB:GetVisualInsets(frame)

		visualWidth = ((frame:GetWidth() or 0) - insetLeft - insetRight) * scale
		visualHeight = ((frame:GetHeight() or 0) - insetTop - insetBottom) * scale
	end

	local extraY = 0

	if extraMaxYPixels and extraMaxYPixels ~= 0 then
		extraY = extraMaxYPixels * ACAB:GetPixelStep()
	end

	local halfX = (screenWidth - visualWidth) / 2
	local halfY = (screenHeight - visualHeight) / 2

	if halfX < 0 then
		halfX = 0
	end

	if halfY < 0 then
		halfY = 0
	end

	return -halfX, halfX, -halfY, halfY + extraY
end

-- Simple-page element range; the generic screen range while its saved position is still non-canonical.
function ACAB:GetSimplePageCoordinateRange(config, frame)
	local pos = config.getPosition and config.getPosition()

	if pos and not self:IsCanonicalPosition(pos) then
		return self:GetScreenCoordinateRange()
	end

	return self:GetSimpleElementCoordinateRange(frame, config.extraMaxYPixels)
end

-- Re-applies a simple page's X/Y slider range from its element's current size; no-op without getElementFrame.
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

	local minX, maxX, minY, maxY = ACAB:GetSimplePageCoordinateRange(config, frame)

	ApplyPositionSliderRange(page, minX, maxX, minY, maxY)
end

-------------------------------------------------------------------------
-- Reusable scrollable content area: every settings page/tab scrolls through
-- CreateScrollFrame + UpdateScrollFrame.
-------------------------------------------------------------------------

-- Pixels scrolled per mouse-wheel notch.
local SETTINGS_SCROLL_WHEEL_STEP = 30

-- Creates a wheel-scrollable UIPanelScrollFrameTemplate frame; content goes into the scroll child
-- later passed to UpdateScrollFrame. scrollbarOnLeft (optional) moves the scrollbar to the left side.
function ACAB:CreateScrollFrame(parent, name, scrollbarOnLeft)
	local scrollFrame = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")

	local scrollBar = getglobal(name .. "ScrollBar")

	scrollFrame.scrollBar = scrollBar

	-- No-op: UpdateScrollFrame alone controls scrollbar visibility.
	scrollFrame:SetScript("OnScrollRangeChanged", function() end)

	if scrollBar and scrollbarOnLeft then
		scrollBar:ClearAllPoints()
		scrollBar:SetPoint("TOPRIGHT", scrollFrame, "TOPLEFT", -4, -16)
		scrollBar:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMLEFT", -4, 16)
	end

	if scrollBar then
		-- Same dark backdrop as the top nav tabs.
		scrollBar:SetBackdrop(ACAB.MODERN_BACKDROP)

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
		-- Scrolls the view whenever the scrollbar value changes (arrows or thumb drag).
		scrollBar:SetScript("OnValueChanged", function()
			scrollFrame:SetVerticalScroll(this:GetValue())
		end)
	end

	return scrollFrame
end

-- Sizes scrollChild/scrollFrame, restores scroll to preserveScroll (pixels, clamped; nil = top) and
-- shows the scrollbar only when there is something to scroll.
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

		-- Owner's re-layout callback reclaims the width of a hidden scrollbar.
		scrollFrame.needsScrollbar = maxScroll > 0

		if scrollFrame.applyScrollbarReserve then
			scrollFrame.applyScrollbarReserve()
			scrollChild:SetWidth(scrollFrame:GetWidth())
		end
	end
end

-- True once the settings window exists; never creates it.
function ACAB:IsSettingsFrameCreated()
	return ACAB.settingsFrame ~= nil
end

-------------------------------------------------------------------------
-- Create main settings frame
-------------------------------------------------------------------------

-- Dark translucent bordered backdrop shared by the bar list and every content viewport.
local function ApplyPanelBackdrop(frame)
	frame:SetBackdrop({
		bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 8,
		edgeSize = 8,
		insets = { left = 2, right = 2, top = 2, bottom = 2 },
	})

	frame:SetBackdropColor(0, 0, 0, 0.3)
end

function ACAB:ApplySettingsPanelBackdrop(frame)
	ApplyPanelBackdrop(frame)
end

-- Builds the settings window shell; every GetOrCreate*Page/Panel builder creates it lazily through here.
function ACAB:CreateSettingsFrame()
	local f = CreateFrame("Frame", "ACABSettingsFrame", UIParent)

	f:SetWidth(780)
	f:SetHeight(680)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", SettingsFrame_OnDragStart)
	f:SetScript("OnDragStop", SettingsFrame_OnDragStop)

	f:SetBackdrop(ACAB.DIALOG_BACKDROP)

	f:Hide()

	-------------------------------------------------------------------------
	-- Title
	-------------------------------------------------------------------------

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")

	title:SetPoint("TOP", f, "TOP", 0, -16)
	title:SetText("AlternativeClassicActionBars Settings")

	f.titleText = title

	-------------------------------------------------------------------------
	-- Close
	-------------------------------------------------------------------------

	local closeButton = CreateFrame("Button", "ACABSettingsCloseButton", f, "UIPanelCloseButton")

	closeButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)

	-- The Setup Wizard's X cancels the wizard instead of only hiding the window.
	closeButton:SetScript("OnClick", function()
		if f.wizardMode then
			ACAB:CancelSetupWizard()
			return
		end

		f:Hide()
	end)

	f.closeButton = closeButton

	-------------------------------------------------------------------------
	-- Top-level view tabs (Bars / General / Profiles / Edit Mode)
	-------------------------------------------------------------------------

	f.currentView = "bars"

	-- Fade-strip inset, matching StyleModernButton's 3px backdrop insets.
	local TAB_FADE_INSET = 3

	-- StyleModernButton's rest-state border color.
	local TAB_BORDER_REST_COLOR = { 0.55, 0.55, 0.55 }

	-- Creates one hidden fade strip filling a tab button's backdrop.
	local function CreateTabStrip(button, color)
		local strip = ACAB:CreateFadeStrip(button, 90 - (TAB_FADE_INSET * 2), 20 - (TAB_FADE_INSET * 2))

		strip:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", TAB_FADE_INSET, TAB_FADE_INSET)
		strip:SetFadeColor(color[1], color[2], color[3])
		strip:SetPeakAlpha(0.5)
		strip:Hide()

		return strip
	end

	-- Replaces StyleModernButton's hover border swap with a gold "selected" and a white "hover" fade strip.
	local function ApplyTabFadeHighlight(button)
		-- Created first so hoverStrip draws on top.
		button.tabSelectStrip = CreateTabStrip(button, ACAB.UI_ACCENT_COLOR)

		local hoverStrip = CreateTabStrip(button, ACAB.UI_HOVER_COLOR)

		button.isHovering = false

		-- Border color priority: hover, then selected, then rest.
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

		-- Replaces StyleModernButton's OnEnter/OnLeave; OnMouseDown/OnMouseUp stay.
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

	local function CreateTabButton(text, onClick, point, relativeTo, relativePoint, x, y)
		local button = CreateFrame("Button", nil, f)

		button:SetHeight(20)
		button:SetPoint(point, relativeTo, relativePoint, x, y)

		ACAB:StyleModernButton(button, 90, 90)
		button:SetText(text)
		ApplyTabFadeHighlight(button)

		button:SetScript("OnClick", onClick)

		return button
	end

	local tabBarsButton = CreateTabButton("Bars", function() ACAB:ShowBarsView() end,
		"TOPLEFT", f, "TOPLEFT", 18, -34)
	local tabGeneralButton = CreateTabButton("General", function() ACAB:ShowGeneralView() end,
		"LEFT", tabBarsButton, "RIGHT", 6, 0)
	local tabProfilesButton = CreateTabButton("Profiles", function() ACAB:ShowProfilesView() end,
		"LEFT", tabGeneralButton, "RIGHT", 6, 0)
	local tabEditModeButton = CreateTabButton("Edit Mode", function() ACAB:ShowEditModeView() end,
		"LEFT", tabProfilesButton, "RIGHT", 6, 0)

	f.tabButtonsByView = {
		bars = tabBarsButton,
		general = tabGeneralButton,
		profiles = tabProfilesButton,
		editmode = tabEditModeButton,
	}

	-- Highlights the initial "bars" tab directly; RefreshActiveTabHighlight needs ACAB.settingsFrame, not set yet.
	tabBarsButton.tabSelectStrip:Show()
	tabBarsButton:UpdateFadeBorderColor()

	-------------------------------------------------------------------------
	-- Divider under the tab row, stretched to the window width.
	-------------------------------------------------------------------------

	local tabContentDivider = f:CreateTexture(nil, "ARTWORK")

	tabContentDivider:SetTexture("Interface\\Buttons\\WHITE8X8")
	tabContentDivider:SetVertexColor(0.5, 0.5, 0.5, 0.6)
	tabContentDivider:SetHeight(1)

	tabContentDivider:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -59)
	tabContentDivider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -59)

	-------------------------------------------------------------------------
	-- Left bar list: listPanel is the fixed viewport, listContent its scroll child holding the rows.
	-------------------------------------------------------------------------

	f.listPanel = ACAB:CreateScrollFrame(f, "ACABSettingsListScrollFrame", true)

	f.listPanel:SetWidth(140)
	f.listPanel:SetHeight(610)

	-- Positioned by ApplyBarsViewScrollbarReserves below.

	ApplyPanelBackdrop(f.listPanel)

	f.barButtons = {}
	f.barButtonsByBarId = {}

	-- On the viewport, not the scroll child, so it stays fixed while scrolling.
	local listTitle = f.listPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")

	listTitle:SetPoint("TOP", f.listPanel, "TOP", 0, -8)
	listTitle:SetText("Action Bars")

	f.listContent = CreateFrame("Frame", nil, f.listPanel)

	-- must be sized and set as scroll child right here, or the list renders empty until the deferred fit.
	f.listContent:SetWidth(f.listPanel:GetWidth())
	f.listContent:SetHeight(610)

	f.listPanel:SetScrollChild(f.listContent)

	-------------------------------------------------------------------------
	-- Right content panel: contentScrollFrame is the Bars-view viewport, contentPanel its scroll child.
	-- Other views get their own pair (ACAB:CreateWideContentScrollFrame).
	-- WARNING: keep every scrollframe paired with the scrollchild it was created with - re-targeting
	-- it leaves the new child with no resolvable position/size.
	-------------------------------------------------------------------------

	f.contentScrollFrame = ACAB:CreateScrollFrame(f, "ACABSettingsContentScrollFrame")

	f.contentScrollFrame:SetHeight(610)

	-------------------------------------------------------------------------
	-- Bars-view horizontal geometry: panel widths/anchors reserve scrollbar width only while shown.
	-------------------------------------------------------------------------

	local BARS_VIEW_PADDING = 18
	local BARS_VIEW_LIST_WIDTH = 140
	local BARS_VIEW_PANEL_GAP = 2
	local BARS_VIEW_TOP = -64

	local function ApplyBarsViewScrollbarReserves()
		-- The Setup Wizard's step list replaces the bar list, which never scrolls there.
		local leftReserve = (f.listPanel.needsScrollbar and not f.wizardMode) and SETTINGS_SCROLLBAR_RESERVED_WIDTH or 0
		local rightReserve = f.contentScrollFrame.needsScrollbar and SETTINGS_SCROLLBAR_RESERVED_WIDTH or 0

		f.listPanel:ClearAllPoints()
		f.listPanel:SetPoint("TOPLEFT", f, "TOPLEFT", BARS_VIEW_PADDING + leftReserve, BARS_VIEW_TOP)

		f.contentScrollFrame:ClearAllPoints()
		f.contentScrollFrame:SetPoint("TOPRIGHT", f, "TOPRIGHT", -BARS_VIEW_PADDING - rightReserve, BARS_VIEW_TOP)

		-- TOPRIGHT-anchored, so its width sets the gap to the bar list.
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
	f.applyBarsViewScrollbarReserves = ApplyBarsViewScrollbarReserves

	ApplyBarsViewScrollbarReserves()

	ApplyPanelBackdrop(f.contentScrollFrame)

	f.contentPanel = CreateFrame("Frame", nil, f.contentScrollFrame)

	f.contentPanel:SetWidth(f.contentScrollFrame:GetWidth())
	f.contentPanel:SetHeight(610)

	f.contentScrollFrame:SetScrollChild(f.contentPanel)

	f.pages = {}

	ACAB.settingsFrame = f

	return f
end

-- Creates a full-width scrollframe+scrollchild pair (General/Profiles/Edit Mode); returns both.
function ACAB:CreateWideContentScrollFrame(name)
	local scrollFrame = ACAB:CreateScrollFrame(ACAB.settingsFrame, name)

	scrollFrame:SetHeight(610)

	-- Sized from settingsFrame:GetWidth() (a fixed literal), not anchors, which may not be resolved yet.
	-- Reserves scrollbar width only while the scrollbar is shown, and the step list's width in the Setup Wizard.
	scrollFrame.applyScrollbarReserve = function()
		local reserve = scrollFrame.needsScrollbar and SETTINGS_SCROLLBAR_RESERVED_WIDTH or 0
		local sidebar = 0

		if ACAB.settingsFrame.wizardMode then
			sidebar = ACAB.SETTINGS_SIDEBAR_WIDTH + ACAB.SETTINGS_SIDEBAR_GAP
		end

		scrollFrame:SetWidth(ACAB.settingsFrame:GetWidth() - 18 - 18 - reserve - sidebar)

		scrollFrame:ClearAllPoints()
		scrollFrame:SetPoint("TOPRIGHT", ACAB.settingsFrame, "TOPRIGHT", -18 - reserve, -64)
	end

	scrollFrame.applyScrollbarReserve()

	ApplyPanelBackdrop(scrollFrame)

	local scrollChild = CreateFrame("Frame", nil, scrollFrame)

	scrollChild:SetWidth(scrollFrame:GetWidth())
	scrollChild:SetHeight(610)

	scrollFrame:SetScrollChild(scrollChild)

	return scrollFrame, scrollChild
end

-------------------------------------------------------------------------
-- Default-profile lock: while the Default profile is active every page shows a red banner and locks
-- its controls. Independent of ApplyDefaultLayoutGating below; both can apply at once.
-------------------------------------------------------------------------

-- Banner text while the Default profile is active (wins over the layout-lock text).
local PROFILE_LOCK_MESSAGE_PROFILE =
	"Editing Settings is prohibited while in default profile mode. " ..
	"Set up a profile if you wish to change Settings or access Layout " ..
	"Edit Mode. |cffffd100Click to create one now.|r"

-- Banner text while Force Vanilla Layout Mode locks a page (bar 1 and the simple pages).
local PROFILE_LOCK_MESSAGE_LAYOUT =
	"Editing Settings is prohibited while Force Vanilla Layout Mode " ..
	"is enabled. Disable it under General Settings if you wish to " ..
	"change Settings or access Layout Edit Mode. " ..
	"|cffffd100Click to jump to General Settings.|r"

-- Click on a locked banner/control: Default profile opens the create-profile dialog; otherwise the
-- layout lock jumps to General and pulses its checkbox.
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

-- Creates a page's hidden lock banner below its title; ApplyProfileLockGating shows it and sets its text.
function ACAB:CreateProfileLockWarning(page)
	-- Button, since a plain Frame has no OnClick on this client.
	local banner = CreateFrame("Button", nil, page)

	-- Parented to page but anchored to contentPanel, so it stays put while page slides down under it.
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

	banner:SetScript("OnClick", function()
		ACAB:HandleLockReasonClick()
	end)

	banner:Hide()

	return banner
end

-- Slides page down by the lock banner's height while locked; title and banner stay on contentPanel.
function ACAB:ApplyPageBannerReserve(page, locked)
	if not page or not ACAB.settingsFrame or not ACAB.settingsFrame.contentPanel then
		return
	end

	local reserve = 0

	if locked then
		-- Measured banner height, floored at PROFILE_LOCK_BANNER_HEIGHT.
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

-- Sets the banner text and resizes the banner to the text's wrapped height at the page's width.
local function SetProfileLockBannerMessage(banner, message)
	-- must set explicit widths: a TOPLEFT+TOPRIGHT pair alone doesn't wrap text on this client.
	local page = banner:GetParent()
	local width = page:GetWidth()

	if width and width > 0 then
		banner:SetWidth(width)
		banner.text:SetWidth(width - (2 * ACAB.INDENT_SECTION))
	end

	banner.text:SetText(message)
	banner:SetHeight((banner.text:GetHeight() or 0) + 12)
end

-- Greys out a control and blocks its input.
function ACAB:LockControl(control, locked)
	control:EnableMouse(not locked)
	control:SetAlpha(locked and 0.5 or 1)

	-- Templated Buttons also need Disable()/Enable(); EnableMouse alone doesn't block their OnClick.
	if control.Disable and control.Enable then
		if locked then
			control:Disable()
		else
			control:Enable()
		end
	end
end

-- Greys a control and sets control.ACABLocked (CreateLabeledCheckbox blocks the click), keeping its tooltip.
-- must not use EnableMouse/Disable here: both also swallow OnEnter/OnLeave on this client.
function ACAB:LockControlKeepingTooltip(control, locked)
	control.ACABLocked = locked and true or false

	control:SetAlpha(locked and 0.5 or 1)
end

-- Page controls locked by ApplyProfileLockGating, checked by presence (covers bar and simple pages).
local PROFILE_LOCK_CONTROL_NAMES = {
	"xSlider", "ySlider", "xStepperBigMinus", "xStepperMinus", "xStepperPlus", "xStepperBigPlus",
	"yStepperBigMinus", "yStepperMinus", "yStepperPlus", "yStepperBigPlus", "xValueClick", "yValueClick",
	"buttonSizeSlider", "spacingSlider",
	"scaleSlider", "resetPositionButton", "resetModernButton", "enableCheckbox",
	"buttonCountMinus", "buttonCountPlus", "pageIndicatorSlider",
	"betterExpBarCheckbox", "expBarShowLevelCheckbox",
	"expBarShowCurrentOverMaxCheckbox", "expBarShowPercentCheckbox",
	"expBarShowRestedPercentCheckbox", "expBarShowRestedTotalCheckbox",
	"expBarFontSizeSlider", "earnedColorSwatch", "restedColorSwatch",
	"expBarTextColorSwatch", "expBarGlowPulseIntervalSlider",
	"useVanillaPetBarCheckbox", "condenseEmptyPetSlotsCheckbox",
	"animateAutoCastGlowCheckbox", "useVanillaStanceBarCheckbox",
	"hoverOnlyCheckbox", "hoverDurationSlider",
}

-- Shows/hides a page's lock banner and locks its controls; alsoCheckLayoutLock also applies the
-- Force Vanilla Layout lock (bar 1 and the simple pages).
function ACAB:ApplyProfileLockGating(page, alsoCheckLayoutLock)
	local profileLocked = self:IsDefaultProfileActive()
	local layoutLocked = alsoCheckLayoutLock and (ACABDB.useDefaultLayout == true)
	local locked = profileLocked or layoutLocked

	if page.profileLockWarning then
		page.profileLockWarning:SetShown(locked)

		if locked then
			-- Profile lock message wins over the layout one.
			SetProfileLockBannerMessage(
				page.profileLockWarning,
				profileLocked and PROFILE_LOCK_MESSAGE_PROFILE or PROFILE_LOCK_MESSAGE_LAYOUT
			)
		end
	end

	ACAB:ApplyPageBannerReserve(page, locked)

	-- Numbered default-family bars keep their enable checkbox usable while locked.
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
				-- UIDropDownMenuTemplate clicks go through its child Button, which needs Disable()/Enable().
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
-- Called by simple/native-backed pages only; default bars get it via ApplyProfileLockGating's
-- alsoCheckLayoutLock, custom bars never gate on it.
-------------------------------------------------------------------------

-- Position stepper buttons and click-to-edit readouts, gated like the sliders they flank.
local POSITION_BUTTON_NAMES = {
	"xStepperBigMinus", "xStepperMinus", "xStepperPlus", "xStepperBigPlus",
	"yStepperBigMinus", "yStepperMinus", "yStepperPlus", "yStepperBigPlus",
	"xValueClick", "yValueClick",
}

-- EnableMouse + alpha gate (works on template-less swatches); toggleEnabled also calls Enable()/Disable().
local function GateControl(control, interactive, alpha, toggleEnabled)
	if not control then
		return
	end

	control:EnableMouse(interactive)
	control:SetAlpha(alpha)

	if toggleEnabled then
		if interactive then
			control:Enable()
		else
			control:Disable()
		end
	end
end

function ACAB:ApplyDefaultLayoutGating(page, interactive)
	local alpha = interactive and 1 or 0.5

	GateControl(page.xSlider, interactive, alpha)
	GateControl(page.ySlider, interactive, alpha)

	local pi

	for pi = 1, table.getn(POSITION_BUTTON_NAMES) do
		GateControl(page[POSITION_BUTTON_NAMES[pi]], interactive, alpha, true)
	end

	GateControl(page.buttonSizeSlider, interactive, alpha)
	GateControl(page.spacingSlider, interactive, alpha)

	-- EnableMouse alone doesn't block this template's OnClick.
	GateControl(page.hoverOnlyCheckbox, interactive, alpha, true)

	GateControl(page.hoverDurationSlider, interactive, alpha)

	if page.gridSwatches then
		local i

		for i = 1, table.getn(page.gridSwatches) do
			GateControl(page.gridSwatches[i], interactive, alpha)
		end
	end
end

-- Refreshes every already-built default-bar and simple page after a layout/style gating change.
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

	local specialKeys = ACAB.SIMPLE_PAGE_KEYS
	local si

	for si = 1, table.getn(specialKeys) do
		if ACAB.settingsFrame.pages[specialKeys[si]] then
			self:RefreshBarSettingsPage(specialKeys[si])
		end
	end
end

-------------------------------------------------------------------------
-- Dynamic window height: sized to the measured bottom edge of the controls actually shown.
-------------------------------------------------------------------------

-- Window chrome above and below the content viewports; the Setup Wizard adds its Back/Next row below.
local SETTINGS_CHROME_TOP = 64
local SETTINGS_CHROME_BOTTOM = 18
local SETTINGS_WIZARD_CHROME_BOTTOM = 60

local function GetSettingsChromeBottom()
	if ACAB.settingsFrame and ACAB.settingsFrame.wizardMode then
		return SETTINGS_WIZARD_CHROME_BOTTOM
	end

	return SETTINGS_CHROME_BOTTOM
end

-- Minimum content height (unless noMinFloor).
local SETTINGS_CONTENT_MIN_HEIGHT = 260

-- Maximum window height as a fraction of screen height.
local SETTINGS_MAX_HEIGHT_RATIO = 0.9

-- Appends frame at n+1 if non-nil and returns the new count (keeps candidate lists free of nil holes).
local function AppendCandidate(list, n, frame)
	if frame then
		list[n + 1] = frame
		return n + 1
	end

	return n
end

-- Largest distance from referenceTop down to a shown candidate's bottom edge.
-- must stay a delta of two live positions: the window is movable, so position estimates break once dragged.
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

-- Fits scrollChildPanel, listPanel and the window to the deepest candidate (floored, screen-capped);
-- returns the raw measured content height. Optional: listCandidateList (bar-list rows, same viewport),
-- minContentHeight (extra floor), noMinFloor (skip SETTINGS_CONTENT_MIN_HEIGHT).
local function ApplySettingsHeightFromCandidates(candidateList, scrollFrame, scrollChildPanel, listCandidateList, minContentHeight, noMinFloor)
	if not ACAB.settingsFrame or not scrollFrame or not scrollChildPanel then
		return nil
	end

	-- Saved so UpdateScrollFrame can restore the user's scroll position after the re-fit.
	local previousContentScroll = scrollFrame:GetVerticalScroll()
	local previousListScroll = listCandidateList and ACAB.settingsFrame.listPanel
		and ACAB.settingsFrame.listPanel:GetVerticalScroll()

	-- Scroll both to the top before measuring; measured rects shift with the scroll offset.
	scrollFrame:SetVerticalScroll(0)

	if listCandidateList and ACAB.settingsFrame.listPanel then
		ACAB.settingsFrame.listPanel:SetVerticalScroll(0)
	end

	-- WARNING: load-bearing top-down resolve pass (discarded reads); keep byte-for-byte or the stale-rect
	-- height bug returns. See known-problems.md: "Settings height-fit top-down resolve pass"
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

	-- Shared viewport height: the taller of content and bar list, then floored.
	local sharedRequirement = measuredContentHeight

	if listContentHeight > sharedRequirement then
		sharedRequirement = listContentHeight
	end

	if minContentHeight and sharedRequirement < minContentHeight then
		sharedRequirement = minContentHeight
	end

	-- The Setup Wizard's step list shares the viewport height and must fit every row.
	local stepList = ACAB.settingsFrame.wizardMode and ACAB.settingsFrame.wizardStepList

	if stepList and stepList.requiredHeight and sharedRequirement < stepList.requiredHeight then
		sharedRequirement = stepList.requiredHeight
	end

	if not noMinFloor and sharedRequirement < SETTINGS_CONTENT_MIN_HEIGHT then
		sharedRequirement = SETTINGS_CONTENT_MIN_HEIGHT
	end

	local contentHeight = measuredContentHeight

	if not noMinFloor and contentHeight < SETTINGS_CONTENT_MIN_HEIGHT then
		contentHeight = SETTINGS_CONTENT_MIN_HEIGHT
	end

	-- Viewport is capped to a screen-relative max; content height stays unclamped for scrolling.
	local maxViewportHeight = (GetScreenHeight() * SETTINGS_MAX_HEIGHT_RATIO)
		- SETTINGS_CHROME_TOP - GetSettingsChromeBottom()

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

	if ACAB.settingsFrame.wizardStepList then
		ACAB.settingsFrame.wizardStepList:SetHeight(viewportHeight)
	end

	ACAB.settingsFrame:SetHeight(
		viewportHeight + SETTINGS_CHROME_TOP + GetSettingsChromeBottom()
	)

	return measuredContentHeight
end

-- Bars view: fits the window to the bar page's controls and the bar-list rows beside it.
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
	n = AppendCandidate(candidates, n, page.mainBarArtModeRow)
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

	-- Simple-page controls.
	n = AppendCandidate(candidates, n, page.scaleValueText)

	-- Experience Bar page controls.
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

	-- Stance/Page assignment rows (default bars 1-5).
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

	-- Stance Bar's "no stances" message, shown instead of the grid swatches.
	n = AppendCandidate(candidates, n, page.noStancesText)

	n = AppendCandidate(candidates, n, page.useVanillaStanceBarCheckbox)

	-- Bar-list rows, measured separately since the sidebar scrolls independently (hidden in the Setup Wizard).
	local listCandidates = nil
	local listN = 0

	if ACAB.settingsFrame.barButtons and not ACAB.settingsFrame.wizardMode then
		listCandidates = {}

		local i

		for i = 1, table.getn(ACAB.settingsFrame.barButtons) do
			listN = AppendCandidate(listCandidates, listN, ACAB.settingsFrame.barButtons[i])
		end
	end

	-- Measured against contentPanel, whose rect every bar page mirrors.
	local measured = ApplySettingsHeightFromCandidates(
		candidates,
		ACAB.settingsFrame.contentScrollFrame,
		ACAB.settingsFrame.contentPanel,
		listCandidates,
		ACAB.settingsFrame.standardBarPageHeight
	)

	-- Records the tallest numbered bar page (except bar 1) as the Bars-view height floor.
	if measured and type(barId) == "number" and barId ~= 1 then
		if not ACAB.settingsFrame.standardBarPageHeight or measured > ACAB.settingsFrame.standardBarPageHeight then
			ACAB.settingsFrame.standardBarPageHeight = measured
		end
	end
end

-- General view: fits the window to the General panel's controls.
function ACAB:FitSettingsWindowToGeneralView()
	if not ACAB.settingsFrame or not ACAB.settingsFrame.generalPanel then
		return
	end

	local panel = ACAB.settingsFrame.generalPanel

	local candidates = {}
	local n = 0

	n = AppendCandidate(candidates, n, panel.useDefaultLayoutCheckbox)
	n = AppendCandidate(candidates, n, panel.tintWholeButtonCheckbox)
	n = AppendCandidate(candidates, n, panel.mainBarPaginationCheckbox)
	n = AppendCandidate(candidates, n, panel.mainBarStanceSwapCheckbox)

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

	ApplySettingsHeightFromCandidates(candidates, ACAB.settingsFrame.generalScrollFrame, panel)
end

-- Setup Wizard decision steps: shrink-to-fit the shown step's direct children and regions.
function ACAB:FitSettingsWindowToWizardView()
	if not ACAB.settingsFrame or not ACAB.settingsFrame.wizardPanel then
		return
	end

	local panel = ACAB.settingsFrame.wizardPanel
	local step = panel.activeStep

	if not step then
		return
	end

	local candidates = {}
	local n = 0
	local widgets = { step:GetChildren() }
	local regions = { step:GetRegions() }
	local i

	for i = 1, table.getn(widgets) do
		n = AppendCandidate(candidates, n, widgets[i])
	end

	for i = 1, table.getn(regions) do
		n = AppendCandidate(candidates, n, regions[i])
	end

	ApplySettingsHeightFromCandidates(candidates, ACAB.settingsFrame.wizardScrollFrame, panel, nil, nil, true)
end

-- Profiles view: shrink-to-fit (no minimum height floor).
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

	ApplySettingsHeightFromCandidates(candidates, ACAB.settingsFrame.profilesScrollFrame, panel, nil, nil, true)
end

-- Edit Mode view: shrink-to-fit (no minimum height floor).
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

	ApplySettingsHeightFromCandidates(candidates, ACAB.settingsFrame.editModeScrollFrame, panel, nil, nil, true)
end

-------------------------------------------------------------------------
-- Show settings
-------------------------------------------------------------------------

function ACAB:ShowSettingsFrame()
	if not ACAB.settingsFrame then
		ACAB:CreateSettingsFrame()
	end

	-- The running Setup Wizard re-shows its own current step.
	if ACAB.settingsFrame.wizardMode then
		ACAB.settingsFrame:Show()
		self:ShowSetupWizardCurrentStep()
		return
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
		-- Refit for the bar-list rows RefreshBarList just rebuilt.
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
