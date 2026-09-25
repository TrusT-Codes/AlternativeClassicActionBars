-- DefaultBars.lua
-- Default bars 1-5 (wrapping Blizzard's MainMenuBar/MultiBar* frames), Main Bar art, and the shared chain/grid container + drag engine.
-- Must load before NativeElements/PetStanceBars/ExperienceBar.lua - their load-time calls need these, or login throws "attempt to call nil value".

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Real Blizzard button-frame name prefixes per default bar id (buttons numbered 1-N).
-------------------------------------------------------------------------

ACAB.DEFAULT_BAR_FRAME_PREFIXES = {
	[1] = "ActionButton",             -- Main bar (MainMenuBar).
	[2] = "MultiBarBottomLeftButton", -- Bottom Left.
	[3] = "MultiBarBottomRightButton",-- Bottom Right.
	[4] = "MultiBarRightButton",      -- Right.
	[5] = "MultiBarLeftButton",       -- Right 2.
	[ACAB.PET_BAR_ID] = "PetActionButton", -- Pet Bar (only 10 real frames).
	[ACAB.STANCE_BAR_ID] = "ShapeshiftButton", -- Stance Bar, styled mode: hide+neuter and anchor capture only.
}

-- Real vanilla stance bars top out at 10 slots (ShapeshiftButton1-10).
ACAB.MAX_STANCE_BUTTONS = 10

-- Returns ordered table of real Blizzard button frames for a default bar id, or nil if unknown/not yet loaded.
function ACAB:GetDefaultBarButtons(id)
	local prefix = self.DEFAULT_BAR_FRAME_PREFIXES[id]

	if not prefix then
		return nil
	end

	local buttons = {}
	local i

	for i = 1, self.MAX_BAR_BUTTONS do
		local frame = getglobal(prefix .. tostring(i))

		if not frame then
			-- Stops collecting rather than producing a sparse table.
			break
		end

		buttons[i] = frame
	end

	if table.getn(buttons) == 0 then
		return nil
	end

	return buttons
end

-------------------------------------------------------------------------
-- Default bars (1-5) action-slot source
-- Bar 1 pages via actionSlot = buttonID + (page-1)*12 (bonus bar offset -> page 6+offset);
-- bars 2-5 can only redirect to an assigned Extra Bar (GetDefaultBarSlotForIndex).
-------------------------------------------------------------------------

-- Page every default bar's buttons currently read from. Pagination toggle locks to page 1; stance-swap only applies on page 1.
function ACAB:GetDefaultBarEffectivePage()
	self:EnsureDB()

	local page = 1

	if ACABDB.defaultBarPaginationEnabled ~= false then
		page = CURRENT_ACTIONBAR_PAGE or 1
	end

	if ACABDB.defaultBarStanceSwapEnabled ~= false and page == 1 then
		local offset = GetBonusBarOffset and GetBonusBarOffset() or 0

		if offset and offset > 0 then
			page = 6 + offset
		end
	end

	return page
end

-- Resolves which of the player's stance slots is currently active (GetBonusBarOffset alone isn't a 1:1 mapping to stance index).
function ACAB:GetActiveStanceIndex()
	local count = GetNumShapeshiftForms and GetNumShapeshiftForms() or 0

	if not count or count <= 0 then
		return nil
	end

	local i

	for i = 1, count do
		local icon, name, isActive = GetShapeshiftFormInfo(i)

		if isActive then
			return i
		end
	end

	return nil
end

-- Action slot for pool button slotIndex of default bar id, from its per-stance (page 1/7-9) or per-page assignment:
-- nil (No Pageswap) = static slot, -1 (Default) = vanilla paging (bar 1 only), Extra Bar id = that bar's slot, else static.
function ACAB:GetDefaultBarSlotForIndex(id, slotIndex)
	local page = self:GetDefaultBarEffectivePage()

	local function StaticSlot()
		if id == 1 then
			return slotIndex
		end

		local cfg = ACABDB.defaultBars[id]

		return cfg and cfg.fixedActionSlots and cfg.fixedActionSlots[slotIndex]
	end

	-- Bars 2-5 have no native paging - "Default" equals "No Pageswap" for them.
	local function VanillaDefaultSlot()
		if id == 1 then
			return slotIndex + ((page - 1) * 12)
		end

		return StaticSlot()
	end

	local assignedId

	if page == 1 or (page >= 7 and page <= 9) then
		-- Must check the active stance, not the page: bonus-bar-less forms (Travel/Aquatic) stay on page 1.
		local stanceIndex = nil

		if ACABDB.defaultBarStanceSwapEnabled ~= false then
			stanceIndex = self:GetActiveStanceIndex()
		end

		assignedId = stanceIndex
			and ACABDB.defaultBarStanceBarAssignment
			and ACABDB.defaultBarStanceBarAssignment[id]
			and ACABDB.defaultBarStanceBarAssignment[id][stanceIndex]
	else
		assignedId = ACABDB.defaultBarPageBarAssignment
			and ACABDB.defaultBarPageBarAssignment[id]
	end

	if assignedId == nil then
		return StaticSlot()
	elseif assignedId == -1 then
		return VanillaDefaultSlot()
	end

	local slot = self:GetExtraBarSlotForIndex(assignedId, slotIndex)

	if slot then
		return slot
	end

	return StaticSlot()
end

-- Re-resolves every default bar's pool button slots from current page/bonus-bar state.
function ACAB:RefreshDefaultBarSlots()
	local id

	for id = 1, 5 do
		local bar = self.bars and self.bars[id]

		if bar then
			self:ApplyBarShape(bar)
		end
	end
end

-- Written by Settings.lua General tab checkboxes; only changes which action slots buttons read from, not visibility.
function ACAB:SetDefaultBarPaginationEnabled(enabled)
	self:EnsureDB()

	ACABDB.defaultBarPaginationEnabled = enabled and true or false

	self:RefreshDefaultBarSlots()

	-- Page Indicator visibility derives from this toggle (bar-1-only).
	if self.ApplyPageIndicatorVisibility then
		self:ApplyPageIndicatorVisibility()
	end
end

function ACAB:SetDefaultBarStanceSwapEnabled(enabled)
	self:EnsureDB()

	ACABDB.defaultBarStanceSwapEnabled = enabled and true or false

	self:RefreshDefaultBarSlots()
end

-- Hooks vanilla's ChangeActionBarPage so RefreshDefaultBarSlots reruns after CURRENT_ACTIONBAR_PAGE updates.
if hooksecurefunc and ChangeActionBarPage then
	hooksecurefunc("ChangeActionBarPage", function()
		ACAB:RefreshDefaultBarSlots()
	end)
end

-- BonusActionBarFrame is a separate overlay frame shown on stance/bonus-bar changes; hidden+neutered unconditionally.
function ACAB:HideBonusActionBarFrame()
	self:NeuterFrameShow(BonusActionBarFrame)
end

-------------------------------------------------------------------------
-- Main Bar's Blizzard art ("Gryphons / Background Art" dropdown, ACABDB.mainBarArtMode)
-------------------------------------------------------------------------

-- Shows/hides MainMenuBarArtFrame's Texture regions per art mode - never the frame itself, whose children
-- are ActionButton1-12. Level 5 must stay between MainMenuExpBar (2) and ACAB bars (10) or either renders wrong.
function ACAB:ApplyBlizzardArtVisibility()
	local artFrame = MainMenuBarArtFrame

	if not artFrame then
		return
	end

	self:EnsureDB()

	artFrame:SetFrameStrata("MEDIUM")
	artFrame:SetFrameLevel(5)

	-- Re-asserted with the art's own strata/level.
	self:ApplyPageIndicatorStrata()

	local mode = ACABDB.mainBarArtMode or self.MAIN_BAR_ART_MODE_FULL
	local gryphonNames = self.MAIN_BAR_ART_GRYPHON_REGION_NAMES

	local regions = { artFrame:GetRegions() }
	local i

	for i = 1, table.getn(regions) do
		local region = regions[i]

		if region and region.GetObjectType and region:GetObjectType() == "Texture" then
			local isGryphon = region.GetName and gryphonNames[region:GetName()]

			local hide = (mode == self.MAIN_BAR_ART_MODE_DISABLED)
				or (mode == self.MAIN_BAR_ART_MODE_NO_GRYPHONS and isGryphon)

			if hide then
				region:Hide()
			else
				region:Show()
			end
		end
	end
end

-------------------------------------------------------------------------
-- Main Bar art placement: MainMenuBarArtFrame follows ACABBar1's position and scales with its buttonSize.
-- Every art region anchors BOTTOM to the frame, so moving/scaling the frame carries them all.
-------------------------------------------------------------------------

-- Reads MainMenuBar's rect (values discarded) so MainMenuBarArtFrame never resolves against a stale parent (§5af).
local function WarmMainBarArtAncestorChain()
	if MainMenuBar then
		MainMenuBar:GetLeft()
		MainMenuBar:GetTop()
	end
end

-- Polls MainMenuBarArtFrame's left/top until 2 consecutive reads match (3s timeout), then calls callback(left, top).
local function WaitForMainBarArtSettle(callback)
	local artFrame = MainMenuBarArtFrame

	if not artFrame or not C_Timer or not C_Timer.NewTicker then
		WarmMainBarArtAncestorChain()
		callback(artFrame and artFrame:GetLeft(), artFrame and artFrame:GetTop())
		return
	end

	local pollInterval = 0.1
	local stableReadsRequired = 2
	local timeout = 3

	WarmMainBarArtAncestorChain()
	local lastLeft, lastTop = artFrame:GetLeft(), artFrame:GetTop()
	local stableCount = 0
	local elapsed = 0

	local ticker
	ticker = C_Timer.NewTicker(pollInterval, function()
		elapsed = elapsed + pollInterval

		WarmMainBarArtAncestorChain()
		local left, top = artFrame:GetLeft(), artFrame:GetTop()

		if left and top and lastLeft and lastTop and left == lastLeft and top == lastTop then
			stableCount = stableCount + 1
		else
			stableCount = 0
		end

		lastLeft, lastTop = left, top

		local settled = stableCount >= stableReadsRequired
		local timedOut = elapsed >= timeout

		if settled or timedOut then
			ticker:Cancel()
			callback(lastLeft, lastTop)
		end
	end)
end

-- Captures MainMenuBarArtFrame's native offset/size once, after its position settles (asynchronous), then
-- applies the art position. Until then ApplyMainBarArtPosition leaves the art at its native spot.
function ACAB:CaptureMainBarArtNativeOffsetIfNeeded()
	-- .width check re-captures saves from before width/height were stored.
	if ACABDB.mainBarArtNativeOffset and ACABDB.mainBarArtNativeOffset.width then
		return
	end

	local artFrame = MainMenuBarArtFrame
	local cfg = ACABDB.defaultBars and ACABDB.defaultBars[1]
	local nativeAnchor = cfg and cfg.nativeAnchor

	if not artFrame or not nativeAnchor or artFrame.ACABArtSettlePolling then
		return
	end

	artFrame.ACABArtSettlePolling = true

	WaitForMainBarArtSettle(function(left, top)
		artFrame.ACABArtSettlePolling = nil

		if not left or not top then
			return
		end

		local frameScale = artFrame:GetEffectiveScale()
		local targetScale = UIParent:GetEffectiveScale()

		if not frameScale or not targetScale or targetScale == 0 then
			return
		end

		local screenY = (top * frameScale) / targetScale
		local frameW = artFrame:GetWidth()
		local frameH = artFrame:GetHeight()

		if not frameW or frameW <= 0 or not frameH or frameH <= 0 then
			return
		end

		-- Left gryphon's right edge, in the frame's unscaled units from its left edge.
		local gryphon = getglobal("MainMenuBarLeftEndCap")
		local gryphonRightFromFrameLeft = nil

		if gryphon then
			local point, _, _, x = gryphon:GetPoint(1)
			local gryphonWidth = gryphon:GetWidth()

			if point == "BOTTOM" and x and gryphonWidth then
				gryphonRightFromFrameLeft = (frameW / 2) + x + (gryphonWidth / 2)
			end
		end

		ACABDB.mainBarArtNativeOffset = {
			y = screenY - nativeAnchor.y,
			gryphonRightFromFrameLeft = gryphonRightFromFrameLeft,
			-- FrameXML <Size>, reasserted by ApplyMainBarArtPosition.
			width = frameW,
			height = frameH,
		}

		ACAB:ApplyMainBarArtPosition()
	end)
end

-- Main Bar button 1's LEFT/TOP in UIParent units - the corner that stays fixed when buttonSize changes.
-- Modern style returns the vanilla-equivalent corner (MODERN_BUTTON_SIZE_POSITION_SHIFT down-right).
local function GetButton1ScreenAnchor(bar)
	-- Must read UIParent first (value discarded) or bar's rect can resolve against a stale ancestor (§5af).
	UIParent:GetLeft()

	local left = bar:GetLeft()
	local top = bar:GetTop()

	if not left or not top then
		return nil
	end

	if not ACAB:IsVanillaBorderStyle() then
		left = left + ACAB.MODERN_BUTTON_SIZE_POSITION_SHIFT
		top = top - ACAB.MODERN_BUTTON_SIZE_POSITION_SHIFT
	end

	local barScale = bar:GetEffectiveScale()
	local targetScale = UIParent:GetEffectiveScale()

	if not barScale or not targetScale or targetScale == 0 then
		return nil
	end

	local screenLeft = (left * barScale) / targetScale
	local screenTop = (top * barScale) / targetScale

	-- Modern style: art (and everything grouped with it) sits 1.5 physical pixels higher to line up with the buttons.
	if not ACAB:IsVanillaBorderStyle() then
		screenTop = screenTop + (1.5 * PixelUtil.GetNearestPixelSize(0, targetScale, 1))
	end

	return screenLeft, screenTop
end

-- Main Bar's buttonSize as its vanilla-style equivalent (Modern runs MODERN_BUTTON_SIZE_DELTA larger).
function ACAB:GetMainBarVanillaButtonSize(cfg)
	local size = (cfg and cfg.buttonSize) or self.BUTTON_SIZE

	if not self:IsVanillaBorderStyle() then
		size = size - self.MODERN_BUTTON_SIZE_DELTA
	end

	return size
end

-- Scale of Main Bar's Blizzard art and every element grouped with it.
function ACAB:GetMainBarArtScale(cfg)
	return self:GetMainBarVanillaButtonSize(cfg) / self.BUTTON_SIZE
end

-- Every bar's laid-out button gap: Main Bar's art-slot formula, shared so equal configs give equal footprints.
function ACAB:GetBarEffectiveSpacing(cfg)
	local spacing = (cfg and cfg.spacing) or 0
	local scale = self:GetMainBarArtScale(cfg)

	if self:IsVanillaBorderStyle() then
		return spacing * scale
	end

	return (spacing + self.VANILLA_SPACING_FLOOR) * scale - self.MODERN_BUTTON_SIZE_DELTA
end

-- Positions/scales MainMenuBarArtFrame against Main Bar's button 1. Runs on every Main Bar move/resize (Bar.lua).
function ACAB:ApplyMainBarArtPosition()
	self:EnsureDB()

	local artFrame = MainMenuBarArtFrame
	local bar = self.bars and self.bars[1]

	if not artFrame or not bar or not bar.config then
		return
	end

	self:CaptureMainBarArtNativeOffsetIfNeeded()

	local offset = ACABDB.mainBarArtNativeOffset

	-- Incomplete offset (no width) must not apply, or the art's rect dies and the capture can never finish.
	if not offset or not offset.width or not offset.height then
		return
	end

	local scale = self:GetMainBarArtScale(bar.config)

	artFrame.ACABApplyingMainBarArtPosition = true

	-- Must reassert the native size every call or the frame's rect stops resolving once Lua SetPoints it (§5ak).
	artFrame:SetWidth(offset.width)
	artFrame:SetHeight(offset.height)

	artFrame:SetScale(scale)
	artFrame:ClearAllPoints()

	-- Anchored to UIParent (not `bar`) at button 1's corner; the bar's saved top-left only until button 1 resolves.
	local btn1X, btn1Y = GetButton1ScreenAnchor(bar)

	if not btn1X or not btn1Y then
		local left, _, _, top = self:GetPositionFrameRect(bar, bar.config, "TOPLEFT")

		btn1X = btn1X or left
		btn1Y = btn1Y or top
	end

	local baseX = btn1X or 0
	local baseY = btn1Y or 0

	-- Measured offset from button 1 at scale 1, plus a residual that grows with (scale - 1).
	local artX = baseX + 42.7 + 40 * (scale - 1)

	local measuredYCorrection = 7.0000189174628

	local artY = baseY + measuredYCorrection + 10 * (scale - 1)

	-- Always TOPLEFT/BOTTOMLEFT - artX/artY are bottom-left screen coordinates whatever Main Bar's own anchor
	-- point is. Offsets resolve through artFrame's own scale - must divide by scale or the art drifts.
	artFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", artX / scale, artY / scale)
	artFrame.ACABApplyingMainBarArtPosition = nil

	-- ActionButton1-12 are artFrame's children - from here on this session their live position is no
	-- longer native (see Core.lua's VerifyDefaultBarAnchorsSettled).
	self.mainBarArtMoved = true

	-- Forces the shown art textures to redraw at the new anchor (Hide/Show each one).
	do
		local regions = { artFrame:GetRegions() }
		local i

		for i = 1, table.getn(regions) do
			local region = regions[i]

			if region and region.GetObjectType and region:GetObjectType() == "Texture" and region:IsShown() then
				region:Hide()
				region:Show()
			end
		end
	end
end

-------------------------------------------------------------------------
-- Elements grouped with Main Bar: Bag Bar, Key Ring, Micro Menu, Latency Bar, Page Indicator.
-- While grouped each sits at its vanilla offset (from native-anchor snapshots) from Main Bar's button 1,
-- scaled with Main Bar's art. Their Apply*Position/Apply*Shape (NativeElements.lua) try ApplyGroupedIfActive first.
-------------------------------------------------------------------------

-- One descriptor per groupable element. Method-name fields resolve on ACAB at call time.
--   pixelCorrection: {x, y} screen-pixel nudge on the vanilla offset (+ right/up), scaled with Main Bar.
--   pixelNudgeY: whole physical pixels added to the final grouped Y, unscaled (+ up).
--   capture(): lazily captures the element's saved/native position before it's read.
--   applyScale(frame, scale): sets the element's grouped scale (and shape) before it's anchored.
--   applyUngrouped(): restores the element's own saved scale/position.
local GROUPABLE_ELEMENTS = {
	bagbar = {
		name = "Bag Bar",
		settingsKey = "bagbar",
		unlockField = "bagBarGroupUnlocked",
		nativeAnchorField = "bagBarNativeAnchor",
		pixelCorrection = { -1, 2 },
		startDrag = "StartBagBarDrag",
		stopDrag = "StopBagBarDrag",
		setScale = "SetBagBarScale",
		hoverOnlyField = "bagBarHoverOnly",
		hoverDurationField = "bagBarHoverDuration",
		getFrame = function() return ACAB.bagBarContainer end,
		applyScale = function(frame, scale)
			ACAB:ApplyChainAnchoredShape(frame, ACABDB.bagBarSpacing or 0, ACAB:GetBagBarEffectiveVertical(), scale)
		end,
		applyUngrouped = function() ACAB:SetBagBarScale(ACABDB.bagBarScale or 1) end,
	},

	keyring = {
		name = "Key Ring",
		settingsKey = "keyring",
		unlockField = "keyRingGroupUnlocked",
		nativeAnchorField = "keyRingNativeAnchor",
		pixelCorrection = { -1, 1 },
		pixelNudgeY = -1,
		startDrag = "StartKeyRingDrag",
		stopDrag = "StopKeyRingDrag",
		setScale = "SetKeyRingScale",
		-- Above every other overlay's 100 so Key Ring's drag surface wins where it overlaps Bag Bar's.
		overlayLevel = 150,
		hoverOnlyField = "keyRingHoverOnly",
		hoverDurationField = "keyRingHoverDuration",
		capture = function() ACAB:CaptureKeyRingPositionIfNeeded() end,
		getFrame = function() return getglobal(ACAB.KEYRING_BUTTON_NAME) end,
		applyScale = function(frame, scale) ACAB:ApplyKeyRingStrataAndScale(frame, scale) end,
		applyUngrouped = function() ACAB:SetKeyRingScale(ACABDB.keyRingScale or 1) end,
	},

	micromenu = {
		name = "Micro Menu",
		settingsKey = "micromenu",
		unlockField = "microMenuGroupUnlocked",
		nativeAnchorField = "microMenuNativeAnchor",
		startDrag = "StartMicroMenuDrag",
		stopDrag = "StopMicroMenuDrag",
		setScale = "SetMicroMenuScale",
		hoverOnlyField = "microMenuHoverOnly",
		hoverDurationField = "microMenuHoverDuration",
		getFrame = function() return ACAB.microMenuContainer end,
		applyScale = function(frame, scale)
			local cols, rows = ACAB:GetMicroMenuEffectiveGrid()

			ACAB:ApplyGridAnchoredShape(frame, cols, rows, ACABDB.microMenuSpacing or 0, scale)
		end,
		applyUngrouped = function() ACAB:SetMicroMenuScale(ACABDB.microMenuScale or 1) end,
	},

	latencybar = {
		name = "Latency Bar",
		settingsKey = "latencybar",
		unlockField = "latencyBarGroupUnlocked",
		nativeAnchorField = "latencyBarNativeAnchor",
		pixelCorrection = { -1, 1 },
		pixelNudgeY = -1,
		startDrag = "StartLatencyBarDrag",
		stopDrag = "StopLatencyBarDrag",
		setScale = "SetLatencyBarScale",
		-- InstallReanchorGuard flag - without it the guard swallows our own SetPoint.
		guardFlag = "ACABApplyingLatencyBarPosition",
		overlayInset = ACAB.LATENCY_BAR_OVERLAY_INSET,
		hoverOnlyField = "latencyBarHoverOnly",
		hoverDurationField = "latencyBarHoverDuration",
		capture = function() ACAB:CaptureLatencyBarPositionIfNeeded() end,
		getFrame = function() return getglobal(ACAB.LATENCY_BAR_FRAME_NAME) end,
		applyScale = function(frame, scale) frame:SetScale(scale) end,
		applyUngrouped = function() ACAB:SetLatencyBarScale(ACABDB.latencyBarScale or 1) end,
	},

	pageindicator = {
		name = "Page Indicator",
		-- No page of its own - its Scale slider lives on Main Bar's page.
		settingsKey = 1,
		unlockField = "pageIndicatorGroupUnlocked",
		nativeAnchorField = "mainBarPageIndicatorNativeAnchor",
		startDrag = "StartPageIndicatorDrag",
		stopDrag = "StopPageIndicatorDrag",
		setScale = "SetPageIndicatorScale",
		getFrame = function() return ACAB.pageIndicatorContainer end,
		applyScale = function(frame, scale) frame:SetScale(scale) end,
		applyUngrouped = function()
			ACAB:SetPageIndicatorScale(ACABDB.mainBarPageIndicatorScale or 1)
			ACAB:ApplyPageIndicatorPosition()
		end,
	},
}

-- Order ApplyMainBarGroupedElements applies the elements in.
local GROUPABLE_ELEMENT_ORDER = { "bagbar", "keyring", "micromenu", "latencybar", "pageindicator" }

function ACAB:IsElementGroupUnlocked(elementKey)
	local element = GROUPABLE_ELEMENTS[elementKey]

	return element ~= nil and ACABDB[element.unlockField] == true
end

-- True while elementKey is anchored to Main Bar: Main Bar art is enabled and the element isn't unlocked.
function ACAB:IsElementGrouped(elementKey)
	return GROUPABLE_ELEMENTS[elementKey] ~= nil
		and ACABDB ~= nil
		and self:IsMainBarArtEnabled()
		and not self:IsElementGroupUnlocked(elementKey)
end

-- Snaps an anchor offset to whole physical pixels like PixelSetPoint does at UIParent's effective scale.
local function SnapNativeOffset(value)
	return PixelUtil.GetNearestPixelSize(value or 0, UIParent:GetEffectiveScale())
end

-- Vanilla TOPLEFT (UIParent units) of `frame` from its native anchor snapshot, at scale 1, offset
-- pixel-snapped. A relativeTo other than UIParent (MainMenuBar in practice) is read live.
local function ResolveNativeTopLeft(native, frame)
	local relFrame = nil

	if native.relativeTo and native.relativeTo ~= "UIParent" then
		relFrame = getglobal(native.relativeTo)

		if not relFrame then
			return nil
		end
	end

	local rfx, rfy = ACAB:GetPointFractions(native.relativePoint or "BOTTOMLEFT")
	local relX, relY

	-- Must read UIParent first (value discarded) or relFrame can resolve against a stale ancestor (§5af).
	UIParent:GetLeft()

	if relFrame then
		local left, right = relFrame:GetLeft(), relFrame:GetRight()
		local top, bottom = relFrame:GetTop(), relFrame:GetBottom()

		if not left or not right or not top or not bottom then
			return nil
		end

		local ratio = relFrame:GetEffectiveScale() / UIParent:GetEffectiveScale()

		relX = (left + (right - left) * rfx) * ratio
		relY = (bottom + (top - bottom) * rfy) * ratio
	else
		relX = UIParent:GetWidth() * rfx
		relY = UIParent:GetHeight() * rfy
	end

	local pfx, pfy = ACAB:GetPointFractions(native.point or "TOPLEFT")
	local width = frame:GetWidth() or 0
	local height = frame:GetHeight() or 0

	return relX + SnapNativeOffset(native.x) - (width * pfx), relY + SnapNativeOffset(native.y) + (height * (1 - pfy))
end

-- The element's vanilla offset from Main Bar's native button-1 anchor, in buttonSize-36 units.
local function GetGroupedElementBaseline(element, frame)
	local mainCfg = ACABDB.defaultBars and ACABDB.defaultBars[1]
	local mainNative = mainCfg and mainCfg.nativeAnchor
	local native = ACABDB[element.nativeAnchorField]

	if not mainNative or not native or not frame then
		return nil
	end

	local left, top = ResolveNativeTopLeft(native, frame)

	if not left or not top then
		return nil
	end

	local correction = element.pixelCorrection
	local uiScale = UIParent:GetEffectiveScale()
	local correctionX, correctionY = 0, 0

	if correction and uiScale and uiScale ~= 0 then
		correctionX = correction[1] / uiScale
		correctionY = correction[2] / uiScale
	end

	return (left - mainNative.x) + correctionX, (top - mainNative.y) + correctionY
end

-- elementKey's grouped absolute target (not yet divided for SetPoint) plus the scale to apply, or nil.
function ACAB:GetGroupedElementPlacement(elementKey, frame)
	local element = GROUPABLE_ELEMENTS[elementKey]
	local bar = self.bars and self.bars[1]

	if not element or not bar or not bar.config then
		return nil
	end

	local baseX, baseY = GetGroupedElementBaseline(element, frame)

	if not baseX then
		return nil
	end

	local btn1X, btn1Y = GetButton1ScreenAnchor(bar)

	if not btn1X or not btn1Y then
		return nil
	end

	local barScale = self:GetMainBarArtScale(bar.config)
	local targetY = btn1Y + (baseY * barScale)
	local nudgeY = element.pixelNudgeY

	if nudgeY then
		-- One physical pixel in UIParent units (minPixels = 1 forces exactly one).
		local onePixel = PixelUtil.GetNearestPixelSize(0, UIParent:GetEffectiveScale(), 1)

		targetY = targetY + (nudgeY * onePixel)
	end

	return btn1X + (baseX * barScale), targetY, barScale
end

-- Divides an absolute target by frame's effective-scale ratio to UIParent (SetPoint offsets resolve
-- through the frame's full effective scale). Must run after the frame's SetScale.
function ACAB:DivideForGroupedSetPoint(frame, targetX, targetY)
	local frameScale = frame:GetEffectiveScale()
	local targetScale = UIParent:GetEffectiveScale()

	if not frameScale or not targetScale or targetScale == 0 then
		return targetX, targetY
	end

	local ratio = frameScale / targetScale

	if not ratio or ratio == 0 then
		return targetX, targetY
	end

	return targetX / ratio, targetY / ratio
end

-- Sets frame's own scale so its effective scale equals desiredScale, cancelling the scale Key Ring
-- inherits from MainMenuBarArtFrame (scaled by ApplyMainBarArtPosition in every art mode).
function ACAB:SetKeyRingOwnScaleForEffective(frame, desiredScale)
	desiredScale = desiredScale or 1

	local parent = frame:GetParent()
	local parentScale = parent and parent:GetEffectiveScale()
	local targetScale = UIParent:GetEffectiveScale()

	if not parentScale or not targetScale or targetScale == 0 then
		frame:SetScale(desiredScale)
		return
	end

	local inheritedRatio = parentScale / targetScale

	if not inheritedRatio or inheritedRatio == 0 then
		frame:SetScale(desiredScale)
		return
	end

	frame:SetScale(desiredScale / inheritedRatio)
end

-- Shared tail of every groupable element's grouped and ungrouped position apply: ensures its edit-mode
-- overlay exists and reapplies its hover-only state.
function ACAB:EnsureElementOverlayAndHover(elementKey, frame)
	local element = GROUPABLE_ELEMENTS[elementKey]

	if element.overlayInset then
		frame.overlayInset = element.overlayInset
	end

	self:EnsureContainerOverlay(
		frame,
		self[element.startDrag],
		self[element.stopDrag],
		element.settingsKey,
		self[element.setScale],
		element.overlayLevel,
		element.name
	)

	if element.hoverOnlyField then
		self:ApplyHoverOnlyState(frame, ACABDB[element.hoverOnlyField], function() return ACABDB[element.hoverDurationField] or 3 end)
	end
end

-- Scales and anchors elementKey at its grouped placement. Returns false, leaving the frame untouched, while
-- its frame or Main Bar's anchors aren't available yet.
local function ApplyGroupedElementPosition(elementKey)
	local element = GROUPABLE_ELEMENTS[elementKey]

	if element.capture then
		element.capture()
	end

	local frame = element.getFrame()

	if not frame then
		return false
	end

	local x, y, scale = ACAB:GetGroupedElementPlacement(elementKey, frame)

	if not x then
		return false
	end

	element.applyScale(frame, scale)

	local passedX, passedY = ACAB:DivideForGroupedSetPoint(frame, x, y)
	local guardFlag = element.guardFlag

	if guardFlag then
		frame[guardFlag] = true
	end

	frame:ClearAllPoints()
	frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", passedX, passedY)

	if guardFlag then
		frame[guardFlag] = nil
	end

	ACAB:EnsureElementOverlayAndHover(elementKey, frame)

	return true
end

-- Applies elementKey's grouped placement if it's grouped. Returns true only if that happened, so callers
-- fall back to their own ungrouped path otherwise.
function ACAB:ApplyGroupedIfActive(elementKey)
	if not self:IsElementGrouped(elementKey) then
		return false
	end

	return ApplyGroupedElementPosition(elementKey)
end

-- Flips elementKey's group lock - shared by the settings-page and edit-mode lock icons.
function ACAB:ToggleElementGroupLock(elementKey)
	local element = GROUPABLE_ELEMENTS[elementKey]

	if not element then
		return
	end

	ACABDB[element.unlockField] = not (ACABDB[element.unlockField] == true)

	self:ApplyMainBarGroupedElements()
	self:ApplyDefaultLayoutEditVisual()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(element.settingsKey)
	end
end

-- Re-applies every groupable element: grouped ones to Main Bar, the rest to their own saved scale/position.
-- Runs on Main Bar move/resize (Bar.lua), art-mode changes, lock toggles, and login.
function ACAB:ApplyMainBarGroupedElements()
	self:EnsureDB()

	local i

	for i = 1, table.getn(GROUPABLE_ELEMENT_ORDER) do
		local elementKey = GROUPABLE_ELEMENT_ORDER[i]

		if not self:ApplyGroupedIfActive(elementKey) then
			GROUPABLE_ELEMENTS[elementKey].applyUngrouped()
		end
	end
end

-- True if `frame` moves along with Main Bar: grouped with it, or the Page Indicator in follow mode.
function ACAB:IsMainBarFollower(frame)
	if not frame then
		return false
	end

	if frame == self.pageIndicatorContainer and ACABDB.mainBarPageIndicatorFollowsMainBar ~= false then
		return true
	end

	local i

	for i = 1, table.getn(GROUPABLE_ELEMENT_ORDER) do
		local elementKey = GROUPABLE_ELEMENT_ORDER[i]

		if self:IsElementGrouped(elementKey) and GROUPABLE_ELEMENTS[elementKey].getFrame() == frame then
			return true
		end
	end

	return false
end

-- Offset (container units) from container's CENTER to its edit-mode overlay's center, from the same
-- static trims EnsureContainerOverlay/ApplyChainAnchoredShape/ApplyGridAnchoredShape/overlayInset apply.
local function GetOverlayCenterOffset(container)
	if container.chainButtons then
		local first = ACAB:GetChainShownEndpoints(container)

		if not first then
			return 0, 0
		end

		local left, _, top = ACAB:GetHitInsets(first)

		return left / 2, -(top + (container.overlayTopFudge or 0)) / 2
	end

	local inset = container.overlayInset

	if inset then
		return ((inset.left or 0) - (inset.right or 0)) / 2, ((inset.bottom or 0) - (inset.top or 0)) / 2
	end

	return 0, 0
end

-- Edit-mode lock icon for elementKey, parented/anchored to the element itself (not its overlay, whose
-- anchors Bag Bar/Micro Menu rebuild every shape pass) so it also hides with the element.
function ACAB:EnsureGroupLockIcon(elementKey, container)
	if container.ACABGroupLockIcon then
		return container.ACABGroupLockIcon
	end

	local icon = self:CreateLockToggleButton(container, "ACABEditModeGroupLock" .. elementKey, {
		tooltipTitle = GROUPABLE_ELEMENTS[elementKey].name,
		lockedLine = "This Element is currently locked to MainBar-ArtBar, click to unlock",
		unlockedLine = "This Element is currently unlocked from MainBar-ArtBar, click to lock",
		onClick = function()
			ACAB:ToggleElementGroupLock(elementKey)
		end,
	})

	icon:SetFrameStrata("TOOLTIP")
	icon:SetFrameLevel(200)
	icon:Hide()

	container.ACABGroupLockIcon = icon

	return icon
end

-- Edit-mode visual for a groupable element: overlay only while ungrouped, lock icon (centered on the
-- overlay hitbox) whenever Main Bar art is enabled.
function ACAB:ApplyGroupedElementEditVisual(elementKey, container, enabledFlag, show)
	self:ApplyContainerOverlayVisual(container, enabledFlag, show and not self:IsElementGrouped(elementKey))

	if not container or not container.ACABOverlay then
		return
	end

	local icon = self:EnsureGroupLockIcon(elementKey, container)
	local dx, dy = GetOverlayCenterOffset(container)

	icon:ClearAllPoints()
	icon:SetPoint("CENTER", container, "CENTER", dx, dy)

	icon:SetShown(show and self:IsMainBarArtEnabled() and enabledFlag ~= false)
	icon:SetLocked(not self:IsElementGroupUnlocked(elementKey))
end

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
-- Default bars 1-5: shape, size, spacing (edit-mode overlays come from Bar.lua's EnsureBarOverlay)
-------------------------------------------------------------------------

-- self.bars[id] for a default bar that has a saved cfg, else nil.
local function GetConfiguredDefaultBar(id)
	ACAB:EnsureDB()

	if not ACABDB.defaultBars[id] then
		return nil
	end

	return ACAB.bars and ACAB.bars[id]
end

-- Positions and grid-reflows default bar `id` per its saved config (Bar.lua's ApplyBarPosition/ApplyBarShape).
function ACAB:ApplyDefaultBarShape(id)
	local bar = GetConfiguredDefaultBar(id)

	if bar then
		self:ApplyBarPosition(bar)
		self:ApplyBarShape(bar)
	end
end

-- Resizes default bar `id`'s buttons via Bar.lua's SetBarButtonSize.
function ACAB:SetDefaultBarButtonSize(id, size)
	local bar = GetConfiguredDefaultBar(id)

	if bar then
		self:SetBarButtonSize(bar, size)
	end
end

-- Grid setter - delegates to Bar.lua's SetBarLayout (which also re-clamps buttonCount).
function ACAB:SetDefaultBarLayout(id, cols, rows)
	self:EnsureDB()

	local bar = self.bars and self.bars[id]

	if bar then
		self:SetBarLayout(bar, cols, rows)
	end
end

-- Default bar cfg's native spacing in the active border style (Modern runs VANILLA_SPACING_FLOOR lower).
function ACAB:GetDefaultBarNativeSpacing(cfg)
	local spacing = (cfg and cfg.nativeSpacing) or 0

	if not self:IsVanillaBorderStyle() then
		spacing = math.max(0, spacing - self.VANILLA_SPACING_FLOOR)
	end

	return spacing
end

-- Pins Main Bar's spacing to its native value while its art is enabled - any other gap pushes buttons off
-- their art slots.
function ACAB:EnforceMainBarArtSpacing()
	local cfg = ACABDB.defaultBars and ACABDB.defaultBars[1]
	local bar = self.bars and self.bars[1]

	if not cfg or not cfg.nativeSpacing or not bar or not self:IsMainBarArtEnabled() then
		return
	end

	local spacing = self:GetDefaultBarNativeSpacing(cfg)

	if cfg.spacing == spacing then
		return
	end

	cfg.spacing = spacing

	self:ApplyBarShape(bar)

	if self:IsEditMode() then
		self:RebuildLayoutGrid()
	end
end

-- Art turned off: Main Bar's spacing returns to Global Spacing (if it applies) or its pre-art value
-- (cfg.spacingBeforeArt, written by the art-mode dropdown on its off -> on switch).
function ACAB:RestoreMainBarSpacingAfterArt()
	local cfg = ACABDB.defaultBars and ACABDB.defaultBars[1]
	local bar = self.bars and self.bars[1]

	if not cfg or not bar or self:IsMainBarArtEnabled() then
		return
	end

	local previous = cfg.spacingBeforeArt

	cfg.spacingBeforeArt = nil

	if ACABDB.globalSpacingEnabled and ACABDB.useDefaultLayout == false and not cfg.spacingUnlocked then
		self:ApplyGlobalSpacingToBar(bar)
	elseif previous then
		self:SetDefaultBarSpacing(1, previous)
	end
end

-- Spacing slider equivalent of SetDefaultBarButtonSize; writes cfg.spacing then reapplies via ApplyBarShape.
function ACAB:SetDefaultBarSpacing(id, spacing)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg then
		return
	end

	if id == 1 and self:IsMainBarArtEnabled() then
		self:EnforceMainBarArtSpacing()
		return
	end

	-- Vanilla-only minimum spacing clamp, mirrors Bar.lua's SetBarSpacing.
	local minSpacing = self:IsVanillaBorderStyle() and self.VANILLA_SPACING_FLOOR or 0

	spacing = self:ClampSpacingSetting(spacing, minSpacing, 20)

	if not spacing then
		return
	end

	cfg.spacing = spacing

	local bar = self.bars and self.bars[id]

	if bar then
		self:ApplyBarShape(bar)
	end

	-- Vanilla-style grid spacing includes Main Bar's configured spacing, not just buttonSize (Core.lua GetLayoutGridSpacing).
	if id == 1 and self:IsEditMode() then
		self:RebuildLayoutGrid()
	end
end

-- Position slider setter - delegates to Bar.lua's SetBarPosition.
function ACAB:SetDefaultBarPosition(id, x, y)
	local bar = GetConfiguredDefaultBar(id)

	if bar then
		self:SetBarPosition(bar, x, y)
	end
end

-------------------------------------------------------------------------
-- Reset to Vanilla Layout (position, spacing, grid shape, size)
-- Position/spacing come from cfg.nativeAnchor/nativeSpacing (seeded by Database.lua's seedDefaultBars);
-- grid shape/button size from ACAB.DEFAULT_BAR_GRID and the current button-size baseline.
-------------------------------------------------------------------------

-- Writes cfg.nativeAnchor into cfg's position, moved `shift` up-left.
local function RestoreNativeAnchor(cfg, shift)
	cfg.point = cfg.nativeAnchor.point
	cfg.relativePoint = cfg.nativeAnchor.relativePoint
	cfg.x = cfg.nativeAnchor.x - shift
	cfg.y = cfg.nativeAnchor.y + shift
end

-- Restores default bar `id`'s vanilla position/grid shape/button size; Modern style gets the same layout
-- in Modern terms (larger buttons, smaller spacing, corner shifted up-left).
function ACAB:ResetDefaultBarLayout(id)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg or not cfg.nativeAnchor then
		return
	end

	local modern = not self:IsVanillaBorderStyle()
	local shift = modern and self.MODERN_BUTTON_SIZE_POSITION_SHIFT or 0

	local grid = self.DEFAULT_BAR_GRID[id]

	-- Stance Bar: one cell per live form, not the 10-slot preset.
	if id == self.STANCE_BAR_ID then
		local liveCount = self:GetClampedLiveStanceCount()

		grid = { cols = (liveCount > 0) and liveCount or 1, rows = 1 }
		cfg.buttonCount = liveCount
	end

	local bar = self.bars and self.bars[id]

	if not bar then
		RestoreNativeAnchor(cfg, shift)
		return
	end

	if cfg.nativeSpacing then
		cfg.spacing = self:GetDefaultBarNativeSpacing(cfg)
	end

	-- Shape first: ApplyBarPosition converts the native anchor to canonical using the bar's final size.
	if grid then
		self:SetBarLayout(bar, grid.cols, grid.rows)
	end

	self:SetBarButtonSize(bar, self:GetCurrentButtonSizeBaseline())

	-- Ensures restored spacing applies even if SetBarLayout was skipped.
	self:ApplyBarShape(bar)

	RestoreNativeAnchor(cfg, shift)

	self:ApplyBarPosition(bar)
end

-------------------------------------------------------------------------
-- Modern Layout geometry (Setup Wizard + every "Reset to Modern Layout Default" button)
-- Positions are read off the real rendered edge of the neighboring bar (GetElementRealEdges) after it
-- is applied - never a buttonSize*N formula, or border-style insets go stale.
-------------------------------------------------------------------------

-- Button size/spacing Modern Layout uses everywhere: the General tab's global overrides if on, otherwise
-- the same defaults Reset to Vanilla Layout uses in the active border style.
function ACAB:GetModernLayoutSizing()
	self:EnsureDB()

	local buttonSize = (ACABDB.globalButtonSizeEnabled and ACABDB.globalButtonSizeValue) or self:GetCurrentButtonSizeBaseline()
	local spacing

	if ACABDB.globalSpacingEnabled and ACABDB.globalSpacingValue then
		-- Mirrors Bar.lua's ApplyGlobalSpacingToBar: the vanilla border floor is added, not clamped.
		local floor = self:IsVanillaBorderStyle() and self.VANILLA_SPACING_FLOOR or 0

		spacing = floor + ACABDB.globalSpacingValue
	else
		spacing = self:GetDefaultBarNativeSpacing(ACABDB.defaultBars and ACABDB.defaultBars[1])
	end

	return buttonSize, spacing
end

-- Modern Layout scale for Pet/Stance Bar's native (~36px) buttons: 0.9 below buttonSize 36, else 1.
function ACAB:GetModernPetStanceScale()
	local buttonSize = self:GetModernLayoutSizing()

	if buttonSize < 36 then
		return 0.9
	end

	return 1
end

-- Extra Main Bar Y needed to clear a bottom-docked Experience Bar.
-- Must read the saved ACABDB.expBarPosition, not the live frame - the Setup Wizard runs this before the frame moves.
function ACAB:GetModernBaseExpBarClearance()
	self:EnsureDB()

	if ACABDB.expBarEnabled == false then
		return 0
	end

	local pos = ACABDB.expBarPosition
	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	if not pos or not frame then
		return 0
	end

	-- Top edge under 20 units above the screen's bottom edge means it's sitting at the bottom.
	local _, _, _, top = self:GetPositionFrameRect(frame, pos, "BOTTOMLEFT")

	if not top or top >= 20 then
		return 0
	end

	local height = frame:GetHeight() or 20

	-- Same rowGap Modern Layout's own preset uses between stacked rows.
	return height + 6
end

-- Writes Modern Layout's 12x1 row shape into a bar config.
local function SetModernRowShape(cfg, buttonSize, spacing)
	cfg.buttonSize = buttonSize
	cfg.spacing = spacing
	cfg.cols = 12
	cfg.rows = 1
	cfg.buttonCount = 12
end

-- Anchors `bar` bottom-centered at `y`, then applies its 12x1 shape at buttonSize.
local function ApplyModernRowBar(bar, y, buttonSize)
	local cfg = bar.config

	cfg.point = "BOTTOM"
	cfg.relativePoint = "BOTTOM"
	cfg.x = 0
	cfg.y = y

	ACAB:ApplyBarPosition(bar)
	ACAB:SetBarLayout(bar, 12, 1)
	ACAB:SetBarButtonSize(bar, buttonSize)
	ACAB:ApplyBarShape(bar)
end

-- Setup Wizard: stacks Main Bar (1) -> Action Bar 1 (2) -> Action Bar 2 (3) with zero gap, each on the
-- real rendered top edge of the bar below it.
function ACAB:ApplyModernMainActionBarsLayout()
	self:EnsureDB()

	local bar1 = self.bars and self.bars[1]
	local bar2 = self.bars and self.bars[2]
	local bar3 = self.bars and self.bars[3]

	if not bar1 or not bar2 or not bar3 then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()

	SetModernRowShape(bar1.config, buttonSize, spacing)
	ApplyModernRowBar(bar1, 4 + self:GetModernBaseExpBarClearance(), buttonSize)

	local _, _, bar1RealTop = self:GetElementRealEdges(bar1)

	SetModernRowShape(bar2.config, buttonSize, spacing)

	local _, _, _, bar2InsetBottom = self:GetElementVisualInset(bar2)

	ApplyModernRowBar(bar2, (bar1RealTop or 0) + bar2InsetBottom, buttonSize)
	self:SetDefaultBarEnabled(2, true)

	local _, _, bar2RealTop = self:GetElementRealEdges(bar2)

	SetModernRowShape(bar3.config, buttonSize, spacing)

	local _, _, _, bar3InsetBottom = self:GetElementVisualInset(bar3)

	ApplyModernRowBar(bar3, (bar2RealTop or 0) + bar3InsetBottom, buttonSize)
	self:SetDefaultBarEnabled(3, true)
end

-- The Y that vertically centers a 12-row, 1-col Modern Layout vertical bar on screen.
-- Shared by Right Action Bar 1/2 and Extra Bar 1-4 so the six-bar cluster centers as one row.
function ACAB:GetModernVerticalBarCenteredY(buttonSize, spacing)
	local _, screenHeight = self:GetUIParentAnchorSize()
	local effectiveSpacing = self:GetBarEffectiveSpacing({ buttonSize = buttonSize, spacing = spacing })
	local clusterHeight = (buttonSize * 12) + (effectiveSpacing * 11)

	return (screenHeight - clusterHeight) / 2
end

-- Reshapes an Extra Bar to 1x12, flush left or right (anchorSide) of anchorRealEdge (UIParent units).
-- "right" returns the bar frame's measured real right edge for chaining; "left" returns anchorRealEdge.
function ACAB:ApplyModernVerticalExtraBarSlot(bar, buttonSize, spacing, anchorRealEdge, y, anchorSide)
	if not bar or not bar.config then
		return anchorRealEdge
	end

	local cfg = bar.config

	cfg.buttonSize = buttonSize
	cfg.spacing = spacing

	self:SetBarLayout(bar, 1, 12)
	self:SetBarButtonCount(bar, 12)

	local insetLeft, insetRight = self:GetElementVisualInset(bar)

	cfg.point = "BOTTOMLEFT"
	cfg.relativePoint = "BOTTOMLEFT"
	cfg.y = y
	cfg.usesDefaultPosition = false

	if anchorSide == "right" then
		cfg.x = anchorRealEdge + insetLeft
	else
		cfg.x = anchorRealEdge - insetRight - buttonSize
	end

	self:ApplyBarPosition(bar)
	self:SetBarButtonSize(bar, buttonSize)
	self:ApplyBarShape(bar)
	self:SetExtraBarEnabled(cfg.id, true)

	if anchorSide ~= "right" then
		return anchorRealEdge
	end

	local _, realRight = self:GetElementRealEdges(bar)

	return realRight or (cfg.x + buttonSize + insetRight)
end

-- Setup Wizard: right cluster Right Action Bar 1/2 (id 4/5) + Extra Bar 1, left cluster Extra Bar 2/3/4.
-- id 4 and Extra Bar 2 sit flush against the screen edges; the rest chain zero-gap off their outer neighbor's real edge.
function ACAB:ApplyModernVerticalBarClusterLayout()
	self:EnsureDB()

	local bar4 = self.bars and self.bars[4]
	local bar5 = self.bars and self.bars[5]

	if not bar4 or not bar5 then
		return
	end

	local extraStart = self.EXTRA_BAR_ID_START
	local extra1 = self.bars[extraStart]
	local extra2 = self.bars[extraStart + 1]
	local extra3 = self.bars[extraStart + 2]
	local extra4 = self.bars[extraStart + 3]

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local cfg5 = bar5.config
	local cfg4 = bar4.config

	cfg5.buttonSize = buttonSize
	cfg5.spacing = spacing
	cfg4.buttonSize = buttonSize
	cfg4.spacing = spacing

	self:SetBarLayout(bar4, 1, 12)
	self:SetBarLayout(bar5, 1, 12)

	-- Shared row Y for the whole six-bar cluster.
	local rowY = self:GetModernVerticalBarCenteredY(buttonSize, spacing)

	local _, insetRight4 = self:GetElementVisualInset(bar4)

	-- id 4: outermost, flush against the screen's right edge.
	cfg4.point = "BOTTOMRIGHT"
	cfg4.relativePoint = "BOTTOMRIGHT"
	cfg4.x = -insetRight4
	cfg4.y = rowY

	self:ApplyBarPosition(bar4)
	self:SetBarButtonSize(bar4, buttonSize)
	self:SetDefaultBarEnabled(4, true)

	local bar4Left = self:GetElementRealEdges(bar4)
	local _, insetRight5 = self:GetElementVisualInset(bar5)

	-- id 5: immediate left of id 4, zero gap.
	cfg5.point = "BOTTOMLEFT"
	cfg5.relativePoint = "BOTTOMLEFT"
	cfg5.x = (bar4Left or cfg4.x) - insetRight5 - buttonSize
	cfg5.y = rowY

	self:ApplyBarPosition(bar5)
	self:SetBarButtonSize(bar5, buttonSize)
	self:SetDefaultBarEnabled(5, true)

	local bar5Left = self:GetElementRealEdges(bar5)

	if extra1 then
		self:ApplyModernVerticalExtraBarSlot(extra1, buttonSize, spacing, bar5Left or cfg5.x, rowY, "left")
	end

	if extra2 then
		local extra2Right = self:ApplyModernVerticalExtraBarSlot(extra2, buttonSize, spacing, 0, rowY, "right")

		if extra3 then
			local extra3Right = self:ApplyModernVerticalExtraBarSlot(extra3, buttonSize, spacing, extra2Right, rowY, "right")

			if extra4 then
				self:ApplyModernVerticalExtraBarSlot(extra4, buttonSize, spacing, extra3Right, rowY, "right")
			end
		end
	end
end

-- Applies Main Bar's own modern position/shape only - never moves Action Bar 1/2.
function ACAB:ApplyModernSingleMainBar()
	self:EnsureDB()

	local bar1 = self.bars and self.bars[1]

	if not bar1 then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()

	SetModernRowShape(bar1.config, buttonSize, spacing)
	ApplyModernRowBar(bar1, 4 + self:GetModernBaseExpBarClearance(), buttonSize)
end

-- Applies `bar`'s own modern position/shape only, stacked zero-gap on `belowBar`'s current real top edge
-- (belowBar itself is never touched).
function ACAB:ApplyModernSingleStackedActionBar(bar, belowBar)
	if not bar or not belowBar then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()

	SetModernRowShape(bar.config, buttonSize, spacing)

	local _, _, belowRealTop = self:GetElementRealEdges(belowBar)
	local _, _, _, insetBottom = self:GetElementVisualInset(bar)

	ApplyModernRowBar(bar, (belowRealTop or 0) + insetBottom, buttonSize)
end

-- Applies bar `id`'s (4 or 5) own modern position/shape only - never moves its neighbor.
-- id 4 is independent (flush against the screen's right edge); id 5 reads id 4's current real left edge.
function ACAB:ApplyModernSingleVerticalBar(id)
	self:EnsureDB()

	local bar = self.bars and self.bars[id]

	if not bar then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local cfg = bar.config
	local rowY = self:GetModernVerticalBarCenteredY(buttonSize, spacing)

	if id == 4 then
		cfg.buttonSize = buttonSize
		cfg.spacing = spacing
		self:SetBarLayout(bar, 1, 12)

		-- Flush against the screen's right edge.
		local _, insetRight = self:GetElementVisualInset(bar)

		cfg.point = "BOTTOMRIGHT"
		cfg.relativePoint = "BOTTOMRIGHT"
		cfg.x = -insetRight
		cfg.y = rowY
	else
		local bar4 = self.bars[4]

		if not bar4 then
			return
		end

		cfg.buttonSize = buttonSize
		cfg.spacing = spacing
		self:SetBarLayout(bar, 1, 12)

		-- Falls back to bar 4's saved x when it has no rect, same as the cluster layout.
		local bar4Left = self:GetElementRealEdges(bar4)
		local _, insetRight = self:GetElementVisualInset(bar)

		cfg.point = "BOTTOMLEFT"
		cfg.relativePoint = "BOTTOMLEFT"
		cfg.x = (bar4Left or bar4.config.x) - insetRight - buttonSize
		cfg.y = rowY
	end

	self:ApplyBarPosition(bar)
	self:SetBarButtonSize(bar, buttonSize)
	self:SetDefaultBarEnabled(id, true)
end

-- "Reset to Modern Layout Default" (SettingsBars.lua) for bars 1-5 - each id only touches its own bar.
function ACAB:ResetBarLayoutToModernBase(id)
	self:EnsureDB()

	if id == 1 then
		self:ApplyModernSingleMainBar()
		return
	end

	if id == 2 then
		local bar1 = self.bars and self.bars[1]
		local bar2 = self.bars and self.bars[2]

		if bar1 and bar2 then
			self:ApplyModernSingleStackedActionBar(bar2, bar1)
			self:SetDefaultBarEnabled(2, true)
		end

		return
	end

	if id == 3 then
		local bar2 = self.bars and self.bars[2]
		local bar3 = self.bars and self.bars[3]

		if bar2 and bar3 then
			self:ApplyModernSingleStackedActionBar(bar3, bar2)
			self:SetDefaultBarEnabled(3, true)
		end

		return
	end

	if id == 4 or id == 5 then
		self:ApplyModernSingleVerticalBar(id)
	end
end

-------------------------------------------------------------------------
-- Enable / disable (bars 2-5 and Pet Bar - bar 1 is always active)
-- Real Blizzard buttons stay hidden; cfg.enabled + Show()/Hide() on the Bar.lua bar frame is the sole visibility source.
-------------------------------------------------------------------------

-- Also reflows dependent default-layout elements (Stance Bar on bar 2, Pet Bar on bar 3, Cast Bar on Pet Bar).
function ACAB:SetDefaultBarEnabled(id, enabled)
	if id == 1 then
		-- Bar 1 (Main) has no enable/disable - always active.
		return
	end

	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	if not cfg then
		return
	end

	enabled = enabled and true or false

	-- Reflows below must only fire on a real state change (ApplyAllDefaultBars re-sends the current value).
	local wasEnabled = cfg.enabled and true or false

	cfg.enabled = enabled

	-- Native-mode Pet Bar has no pool bar - its chain-anchored container is the visibility target instead.
	local bar = self.bars and self.bars[id]
	local isNativePetBar = id == self.PET_BAR_ID and self:IsPetBarNativeModeEffective()

	if isNativePetBar then
		bar = self.petBarNativeContainer
	end

	-- Native-mode Stance Bar has no pool bar either (bar stays nil); it uses ACABDB.stanceBarEnabled,
	-- not cfg.enabled (styled mode only) - do not merge the two.
	if bar then
		-- Pet Bar also needs a controllable pet action bar right now.
		local shouldShow = enabled

		if enabled and id == self.PET_BAR_ID then
			shouldShow = PetHasActionBar and PetHasActionBar() and true or false
		end

		if shouldShow then
			bar:Show()
		else
			bar:Hide()

			-- The overlay is parented to UIParent, so hiding the container doesn't hide it.
			if isNativePetBar and bar.ACABOverlay then
				bar.ACABOverlay:Hide()
				bar.ACABOverlay:EnableMouse(false)
			end
		end
	end

	if id == 2 and enabled ~= wasEnabled and ACABDB.useDefaultLayout ~= false then
		self:ReflowStanceBarForBar2Toggle(enabled)
	end

	if id == 3 and enabled ~= wasEnabled and ACABDB.useDefaultLayout ~= false then
		self:ReflowPetBarForBar3Toggle(enabled)
	end

	-- Cast Bar independently stacks above an actually-shown Pet Bar (GetCastBarBaselineY, NativeElements.lua).
	if id == self.PET_BAR_ID and ACABDB.useDefaultLayout ~= false and self.ReflowCastBarForStackToggle then
		self:ReflowCastBarForStackToggle()
	end

	-- Matches native's own dependency (bar 5 requires bar 4) - user can opt out via the General tab.
	if id == 4 then
		if enabled ~= wasEnabled and not enabled and not ACABDB.bypassRightActionBar2Dependency then
			self:SetDefaultBarEnabled(5, false)
		end

		-- Bar 5's sidebar row and page checkbox lock/unlock with bar 4's state.
		if enabled ~= wasEnabled and ACAB:IsSettingsFrameCreated() then
			ACAB:RefreshBarList()
			ACAB:RefreshBarSettingsPage(5)
		end
	end

	-- Mirrors state into the native "Show ... ActionBar" global/checkbox for Interface Options (display only).
	local nativeGlobal = ACAB.SHOW_MULTI_ACTIONBAR_GLOBAL[id]

	if nativeGlobal then
		-- Do NOT call MultiActionBar_Update() here - it gets "Right ActionBar 2" (bar 5) stuck disabled.
		setglobal(nativeGlobal, enabled and "1" or nil)

		-- The options panel only reads the global when shown - set its control directly too.
		local control = getglobal("OptionsFrameCheckButton" .. tostring(id) .. "Control")

		if control and control.SetChecked then
			control:SetChecked(enabled)
		end
	end

	self:FixRightActionBar2Checkbox()
end

-------------------------------------------------------------------------
-- Pet Bar auto-hide (no controllable pet action bar right now)
-------------------------------------------------------------------------

-- Re-evaluates Pet Bar visibility through SetDefaultBarEnabled, then re-chains its native buttons.
function ACAB:RefreshPetBarVisibility()
	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[self.PET_BAR_ID]

	if cfg then
		self:SetDefaultBarEnabled(self.PET_BAR_ID, cfg.enabled)
	end

	if self.petBarNativeContainer then
		self:ApplyPetBarNativeShape()
	end
end

-- Reconciles our own cfg.enabled (bars 2-5) from the native SHOW_MULTI_ACTIONBAR_1-4 globals whenever
-- MultiActionBar_Update runs. Only trusted reactively - these globals don't survive a real logout.
function ACAB:ReconcileDefaultBarEnabledFromNative()
	if not (ACABDB and ACABDB.defaultBars) then
		return
	end

	local id

	for id = 2, 5 do
		local nativeGlobal = ACAB.SHOW_MULTI_ACTIONBAR_GLOBAL[id]
		local cfg = ACABDB.defaultBars[id]

		if nativeGlobal and cfg then
			local nativeEnabled = getglobal(nativeGlobal) and true or false
			local currentEnabled = cfg.enabled and true or false

			if nativeEnabled ~= currentEnabled then
				-- Any re-entry is a one-level no-op once values match - not a loop.
				self:SetDefaultBarEnabled(id, nativeEnabled)

				if ACAB:IsSettingsFrameCreated() then
					ACAB:RefreshBarList()
					ACAB:RefreshBarSettingsPage(id)
				end
			end
		end
	end

	self:FixRightActionBar2Checkbox()
end

-- This fork's Options -> Action Bars panel leaves "Show Right ActionBar 2" (bar 5) stuck disabled instead of
-- following "Show Right ActionBar" (bar 4) - FixRightActionBar2Checkbox mirrors that dependency by hand.
local hookedBar4Checkbox = false

-- Label color, forced only when enabled; native handles the disabled grey.
local RIGHT_ACTIONBAR2_LABEL_ENABLED_COLOR = { 1, 0.82, 0 }

local function SetCheckbox5LabelEnabledColor()
	local outer = getglobal("OptionsFrameCheckButton5")

	if not outer then
		return
	end

	local regions = { outer:GetRegions() }
	local i

	for i = 1, table.getn(regions) do
		local r = regions[i]
		local okType, objType = pcall(function() return r.GetObjectType and r:GetObjectType() end)

		if okType and objType == "FontString" then
			r:SetTextColor(
				RIGHT_ACTIONBAR2_LABEL_ENABLED_COLOR[1],
				RIGHT_ACTIONBAR2_LABEL_ENABLED_COLOR[2],
				RIGHT_ACTIONBAR2_LABEL_ENABLED_COLOR[3]
			)
		end
	end
end

-- Enables bar 5's options checkbox only while bar 4 is enabled (or the dependency bypass is on); hooks bar 4's checkbox once.
function ACAB:FixRightActionBar2Checkbox()
	local control5 = getglobal("OptionsFrameCheckButton5Control")

	if control5 and control5.Enable and control5.Disable then
		local bar4Cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[4]
		local shouldEnable = (ACABDB and ACABDB.bypassRightActionBar2Dependency)
			or (bar4Cfg and bar4Cfg.enabled)

		if shouldEnable then
			control5:Enable()
			SetCheckbox5LabelEnabledColor()
		else
			control5:Disable()
		end
	end

	if not hookedBar4Checkbox then
		local control4 = getglobal("OptionsFrameCheckButton4Control")

		if control4 and control4.HookScript then
			control4:HookScript("OnClick", function()
				ACAB:FixRightActionBar2Checkbox()
			end)

			hookedBar4Checkbox = true
		end
	end
end

-- Post-hook: runs after MultiActionBar_Update has applied the native globals, so the reconcile reads new values.
if hooksecurefunc and MultiActionBar_Update then
	hooksecurefunc("MultiActionBar_Update", function()
		ACAB:ReconcileDefaultBarEnabledFromNative()
	end)
end

-------------------------------------------------------------------------
-- Pool-bar creation (self.bars[id]) for every default bar - once at PLAYER_LOGIN, before ApplyAllDefaultBars.
-- Each bar's real Blizzard buttons are hidden for good (left alone if they can't be found).
-------------------------------------------------------------------------

-- ShapeshiftBar_Update() only keeps the Stance Bar's compact border while MultiBarBottomLeft is shown, so
-- that parent stays permanently shown (Hide neutered) once bar 2's real buttons are hidden.
local hasNeuteredMultiBarBottomLeft = false

local function ForceShowMultiBarBottomLeft(parent)
	if not parent then
		return
	end

	parent:Show()

	if not hasNeuteredMultiBarBottomLeft then
		parent.Hide = function() end
		hasNeuteredMultiBarBottomLeft = true
	end
end

-- Creates default bar `id`'s pool-button bar (self.bars[id]) if not built yet - used at login and by
-- PetStanceBars.lua's Reset*ToModernBase.
function ACAB:EnsureFixedSlotBarCreated(id)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[id]

	-- Native-mode Pet Bar: CreatePetBarNativeContainer wraps the real PetActionButton1-10 instead.
	if id == self.PET_BAR_ID and cfg and self:IsPetBarNativeModeEffective() then
		return
	elseif id == self.STANCE_BAR_ID and cfg and self:IsStanceBarNativeModeEffective() then
		-- Handled by CreateStanceBarContainer instead.
		return
	end

	if not (cfg and (cfg.fixedActionSlots or cfg.dynamicDefaultBar) and not self.bars[id]) then
		return
	end

	local nativeButtons = self:GetDefaultBarButtons(id)

	if nativeButtons then
		local i

		for i = 1, table.getn(nativeButtons) do
			local btn = nativeButtons[i]

			-- Show neutered so native code (e.g. ACTIONBAR_SHOWGRID's sweep) can't re-show it.
			if btn then
				btn:Hide()
				btn.Show = function() end
			end
		end

		if id == 2 then
			ForceShowMultiBarBottomLeft(nativeButtons[1]:GetParent())

			-- Recomputes in case ShapeshiftBar_Update already ran against the hidden state.
			if ShapeshiftBar_Update then
				ShapeshiftBar_Update()
			end
		end
	end

	self.bars[id] = self:CreateBarFromConfig(cfg)

	-- Bar 1 has no cfg.enabled key (always nil), so it must be shown explicitly here.
	if id == 1 or cfg.enabled then
		self.bars[id]:Show()
	else
		self.bars[id]:Hide()
	end
end

function ACAB:CreateFixedSlotDefaultBars()
	self:EnsureDB()

	local i

	for i = 1, table.getn(self.DEFAULT_BAR_IDS) do
		self:EnsureFixedSlotBarCreated(self.DEFAULT_BAR_IDS[i])
	end
end

-------------------------------------------------------------------------
-- Apply all 5 default bars from SavedVariables
-------------------------------------------------------------------------

function ACAB:ApplyAllDefaultBars()
	self:EnsureDB()

	local i

	for i = 1, table.getn(self.DEFAULT_BAR_IDS) do
		local id = self.DEFAULT_BAR_IDS[i]
		local cfg = ACABDB.defaultBars[id]

		if cfg then
			if id ~= 1 then
				self:SetDefaultBarEnabled(id, cfg.enabled)
			end

			-- Reapplied even while disabled, so every bar keeps its own position/overlay.
			self:ApplyDefaultBarShape(id)
		end
	end
end

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
	if not frame or not pos then
		return
	end

	local scale = frame:GetEffectiveScale()
	local width = frame:GetWidth()
	local height = frame:GetHeight()

	if not scale or not width or not height then
		return
	end

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

	if not adjustedLeft and not adjustedTop then
		return
	end

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
	if not dragFrame then
		return
	end

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

	if n == 0 then
		return nil
	end

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
	container:SetFrameStrata("HIGH")

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
	if not pos or not oldScale or not newScale then
		return
	end

	if oldScale == newScale or oldScale <= 0 or newScale <= 0 then
		return
	end

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
	if not container or not container.chainButtons then
		return
	end

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
	if not container or not container.chainButtons then
		return
	end

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
		if not scaleSetFn then
			return
		end

		if not overlay:IsMouseEnabled() then
			return
		end

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
	if not container or not container.ACABOverlay then
		return
	end

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
	if not frame or frame.ACABReanchorGuarded then
		return
	end

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

-- Only ApplyMainBarArtPosition may re-anchor MainMenuBarArtFrame. Top-level call: must stay below
-- InstallReanchorGuard's definition or login throws "attempt to call nil value".
ACAB:InstallReanchorGuard(MainMenuBarArtFrame, "ACABApplyingMainBarArtPosition")

-- Applies a relative anchor (GetPoint(1) snapshot) to `frame` and returns its resulting TOPLEFT as a
-- UIParent-relative TOPLEFT/BOTTOMLEFT position table, or nil.
-- guardFlagName must be passed for frames with an InstallReanchorGuard, or this SetPoint is swallowed.
function ACAB:ResolveNativeAnchorToAbsolute(frame, native, guardFlagName)
	if not frame then
		return nil
	end

	-- The anchor native code last tried to set (InstallReanchorGuard) wins over the passed snapshot.
	native = frame.ACABSwallowedAnchor or native

	if not native then
		return nil
	end

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

	if not left or not top then
		return nil
	end

	return {
		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = left,
		y = top,
	}
end

-- Swallows Show() on `frame` unless isEnabledFn() returns true.
function ACAB:InstallShowGuard(frame, isEnabledFn)
	if not frame or frame.ACABShowGuarded then
		return
	end

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
	if not frame then
		return
	end

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

	if not x or not y or not ACABDB[field] then
		return false
	end

	ACABDB[field].x = x
	ACABDB[field].y = y

	return true
end

-- Clamps and stores ACABDB[scaleField], keeping frame's center fixed. Returns clamped scale (nil if invalid), pos.
function ACAB:StoreCompensatedScale(scaleField, posField, frame, scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return nil
	end

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

	if not (point and relativePoint and x and y) then
		return nil
	end

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

-------------------------------------------------------------------------
-- Edit-mode overlay refresh for native-wrapped elements and chain containers
-- (bars 1-5 use Bar.lua's ApplyEditModeVisual). Most are gated on CanDragDefaultLayout(), not edit mode alone.
-------------------------------------------------------------------------

function ACAB:ApplyDefaultLayoutEditVisual()
	local show = self:CanDragDefaultLayout()

	-- Stance Bar/Pet Bar/Cast Bar/Tooltip stay draggable in edit mode even on useDefaultLayout == true.
	local showAlwaysEditable = self:IsEditMode()

	self:ApplyContainerOverlayVisual(self.stanceBarContainer, ACABDB.stanceBarEnabled, showAlwaysEditable)

	-- Grouped with Main Bar: no overlay, lock icon instead (ApplyGroupedElementEditVisual).
	self:ApplyGroupedElementEditVisual("bagbar", self.bagBarContainer, ACABDB.bagBarEnabled, show)
	self:ApplyGroupedElementEditVisual("micromenu", self.microMenuContainer, ACABDB.microMenuEnabled, show)

	-- Native Pet Bar - gated on the same cfg.enabled styled mode uses.
	do
		local petCfg = ACABDB.defaultBars and ACABDB.defaultBars[self.PET_BAR_ID]

		self:ApplyContainerOverlayVisual(self.petBarNativeContainer, petCfg and petCfg.enabled, showAlwaysEditable)
	end

	self:ApplyGroupedElementEditVisual("keyring", getglobal(self.KEYRING_BUTTON_NAME), ACABDB.keyRingEnabled, show)
	self:ApplyGroupedElementEditVisual("latencybar", getglobal(self.LATENCY_BAR_FRAME_NAME), ACABDB.latencyBarEnabled, show)
	self:ApplyContainerOverlayVisual(getglobal(self.EXP_BAR_FRAME_NAME), ACABDB.expBarEnabled, show)

	self:ApplyContainerOverlayVisual(getglobal(self.CAST_BAR_FRAME_NAME), true, showAlwaysEditable)

	-- Page Indicator has no enable flag of its own - gated on pagination instead.
	self:ApplyGroupedElementEditVisual(
		"pageindicator",
		self.pageIndicatorContainer,
		ACABDB.defaultBarPaginationEnabled,
		show
	)

	self:ApplyContainerOverlayVisual(self.tooltipFrame, ACABDB.tooltipEnabled, showAlwaysEditable)
end

-------------------------------------------------------------------------
-- Position reassert after combat / looting (PLAYER_REGEN_ENABLED, LOOT_CLOSED)
-- Re-applies every native-wrapped element FrameXML may have silently re-anchored; each Apply* is idempotent
-- and no-ops if unbuilt. Bars 1-5 are excluded - their real buttons stay hidden.
-------------------------------------------------------------------------

function ACAB:ReassertNativeElementPositions()
	-- Grouped elements route to their grouped placement inside these Apply* calls.
	self:ApplyBagBarPosition()
	self:ApplyBagBarShape()

	self:ApplyMicroMenuPosition()
	self:ApplyMicroMenuShape()

	self:ApplyStanceBarPosition()
	self:ApplyStanceBarShape()

	self:ApplyKeyRingPosition()

	self:ApplyLatencyBarPosition()

	self:ApplyExpBarPosition()

	self:ApplyCastBarPosition()

	self:ApplyPageIndicatorPosition()
	self:ApplyPageIndicatorShape()
end
