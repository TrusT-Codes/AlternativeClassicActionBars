-- ExperienceBar.lua
-- Experience Bar: position/enable/scale, bar-fill colors, rested-XP overlay/tick/glow pulse, and the
-- "Better Experience Bar" text overlay. Built on DefaultBars.lua's single-native-frame container engine.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Experience Bar (MainMenuExpBar) - single native frame; its rested/text regions move and scale with it.
-- Movable/scalable via EnsureContainerOverlay regardless of ACABDB.betterExpBarEnabled.
-------------------------------------------------------------------------

ACAB.EXP_BAR_FRAME_NAME = "MainMenuExpBar"

-- Blocks native re-shows (e.g. quest turn-in XP updates) while the Experience Bar is disabled.
ACAB:InstallShowGuard(getglobal(ACAB.EXP_BAR_FRAME_NAME), function()
	return ACABDB and ACABDB.expBarEnabled ~= false
end)

-- Owns the native "XP current / max" FontString (there is no MainMenuExpText global on this client).
ACAB.EXP_OVERLAY_FRAME_NAME = "MainMenuBarOverlayFrame"

-- Returns (and caches) MainMenuBarOverlayFrame's first FontString region - matched by type, never by index.
function ACAB:GetNativeExpOverlayText()
	if self.nativeExpOverlayText then
		return self.nativeExpOverlayText
	end

	local overlayFrame = getglobal(self.EXP_OVERLAY_FRAME_NAME)

	if not overlayFrame then
		return nil
	end

	local regions = { overlayFrame:GetRegions() }
	local i

	for i = 1, table.getn(regions) do
		local region = regions[i]

		if region and region.GetObjectType and region:GetObjectType() == "FontString" then
			self.nativeExpOverlayText = region
			return region
		end
	end

	return nil
end

-- Native rested-bonus fill on MainMenuExpBar. A Texture, not a StatusBar - color it via Set/GetVertexColor.
ACAB.EXP_RESTED_FRAME_NAME = "ExhaustionLevelFillBar"

-- Captures MainMenuExpBar's position once (scale-converted to UIParent units) plus its native GetPoint(1) anchor.
function ACAB:CaptureExpBarPositionIfNeeded()
	self:EnsureDB()

	if ACABDB.expBarPosition then
		return
	end

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local left = frame:GetLeft()
	local top = frame:GetTop()

	if not left or not top then
		return
	end

	local buttonScale = frame:GetEffectiveScale()
	local uiParentScale = UIParent:GetEffectiveScale()

	local x, y = left, top

	if buttonScale and uiParentScale and uiParentScale ~= 0 then
		x = (left * buttonScale) / uiParentScale
		y = (top * buttonScale) / uiParentScale
	end

	local anchor = {
		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = x,
		y = y,
	}

	ACABDB.expBarPosition = anchor

	-- Permanent pristine snapshot for "Reset to Vanilla Layout"; captured once, never rewritten.
	if not ACABDB.expBarNativeAnchor then
		ACABDB.expBarNativeAnchor = self:ReadNativeAnchor(frame)
	end
end

-- Gradient strip covering the bottom 3 units of MainMenuExpBar that its native border art leaves bare.
-- Do not replace with a clone of MainMenuXPBarTexture0-3 - that renders duplicated/distorted.
local function EnsureExpBarBottomBorderStrip(frame)
	if frame.ACABBottomBorderStrip then
		return frame.ACABBottomBorderStrip
	end

	-- Must be "OVERLAY", or the bar's fill paints over it.
	local strip = frame:CreateTexture(nil, "OVERLAY")
	strip:SetTexture("Interface\\Buttons\\WHITE8X8")

	-- Spans the bar's full width at any scale; 4 units tall.
	strip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	strip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	strip:SetHeight(4)

	-- Vertical dark gradient, or solid dark gray without SetGradientAlpha.
	if strip.SetGradientAlpha then
		strip:SetGradientAlpha("VERTICAL", 0.05, 0.05, 0.05, 0.85, 0.25, 0.25, 0.25, 0.55)
	else
		strip:SetVertexColor(0.12, 0.12, 0.12)
	end

	frame.ACABBottomBorderStrip = strip

	return strip
end

-- Applies ACABDB.expBarPosition to MainMenuExpBar and ensures its overlay, border strip, and hover-only state.
function ACAB:ApplyExpBarPosition()
	self:CaptureExpBarPositionIfNeeded()

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local pos = ACABDB.expBarPosition

	if pos then
		self:ApplySavedPosition(frame, pos)
	end

	-- Pins Experience Bar to Latency Bar's strata, one frame level below it.
	do
		local latencyBarFrame = getglobal(self.LATENCY_BAR_FRAME_NAME)

		if latencyBarFrame then
			local latencyLevel = latencyBarFrame:GetFrameLevel()

			frame:SetFrameStrata(latencyBarFrame:GetFrameStrata())
			frame:SetFrameLevel((latencyLevel > 0) and (latencyLevel - 1) or 0)
		end
	end

	self:EnsureContainerOverlay(frame, self.StartExpBarDrag, self.StopExpBarDrag, "expbar", self.SetExpBarScale, nil, "Experience Bar")
	EnsureExpBarBottomBorderStrip(frame)

	-- Also fades the rested-glow child texture (it inherits this frame's alpha).
	self:ApplyHoverOnlyState(frame, ACABDB.expBarHoverOnly, function() return ACABDB.expBarHoverDuration or 3 end)
end

function ACAB:SetExpBarPosition(x, y)
	if self:WriteSavedPositionXY("expBarPosition", x, y) then
		self:ApplyExpBarPosition()
	end
end

-- Shows/hides MainMenuExpBar together with its drag overlay and text overlay.
function ACAB:SetExpBarEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.expBarEnabled = enabled

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	self:SetElementShown(frame, enabled)

	-- Must re-show explicitly, or the text overlay stays hidden after a disable/re-enable cycle.
	if frame and frame.ACABTextOverlay then
		if enabled then
			frame.ACABTextOverlay:Show()
		else
			frame.ACABTextOverlay:Hide()
		end
	end
end

-- Clamps, compensates the saved position around the bar's center, then applies the new scale.
function ACAB:SetExpBarScale(scale)
	local frame = getglobal(self.EXP_BAR_FRAME_NAME)
	local pos

	scale, pos = self:StoreCompensatedScale("expBarScale", "expBarPosition", frame, scale)

	if not scale then
		return
	end

	if frame then
		frame:SetScale(scale)
	end

	if pos then
		self:ApplyExpBarPosition()
	end
end

-- Experience Bar settings page "Only show on hover" checkbox/slider.
function ACAB:SetExpBarHoverOnly(enabled)
	self:SetHoverOnlySetting("expBarHoverOnly", enabled, self.ApplyExpBarPosition)
end

function ACAB:SetExpBarHoverDuration(duration)
	self:SetHoverDurationSetting("expBarHoverDuration", duration, self.ApplyExpBarPosition)
end

-- "Reset to Vanilla Layout": restores native position and scale 1.
function ACAB:ResetExpBarLayout()
	local native = ACABDB.expBarNativeAnchor
	local frame = getglobal(self.EXP_BAR_FRAME_NAME)
	local resolved = self:ResetScaleAndResolveNative(frame, "expBarScale", native)

	if resolved then
		ACABDB.expBarPosition = resolved
	end

	self:ApplyExpBarPosition()
end

function ACAB:StartExpBarDrag()
	self:CaptureExpBarPositionIfNeeded()

	local pos = ACABDB.expBarPosition

	if not pos then
		return
	end

	self:StartSharedDrag("expBar", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopExpBarDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("expbar")
	end
end

-------------------------------------------------------------------------
-- Bar-fill colors
-- Earned fill = MainMenuExpBar StatusBar color; rested fill = ExhaustionLevelFillBar vertex color.
-- Both native baselines are captured lazily from the live frames, not seeded in EnsureDB.
-------------------------------------------------------------------------

-- Better Experience Bar's default overlay text size.
ACAB.EXP_BAR_DEFAULT_FONT_SIZE = 10

-- Better Experience Bar's default earned fill (#a40aa4).
ACAB.EXP_BAR_DEFAULT_COLOR_EARNED = { r = 164 / 255, g = 10 / 255, b = 164 / 255 }

local function CopyColor(color)
	return { r = color.r, g = color.g, b = color.b }
end

local function ColorsMatch(a, b)
	return math.abs(a.r - b.r) < 0.002 and math.abs(a.g - b.g) < 0.002 and math.abs(a.b - b.b) < 0.002
end

-- Captures the native earned/rested colors once; the custom earned color starts at EXP_BAR_DEFAULT_COLOR_EARNED.
function ACAB:CaptureExpBarColorsIfNeeded()
	self:EnsureDB()

	if not ACABDB.expBarColorEarned then
		local frame = getglobal(self.EXP_BAR_FRAME_NAME)
		local r, g, b

		if frame and frame.GetStatusBarColor then
			r, g, b = frame:GetStatusBarColor()
		end

		-- Permanent pristine snapshot of the native fill (fallback purple if the live frame isn't available yet);
		-- captured once, never rewritten.
		ACABDB.expBarNativeColorEarned = {
			r = r or 0.58,
			g = g or 0.0,
			b = b or 0.55,
		}

		ACABDB.expBarColorEarned = CopyColor(self.EXP_BAR_DEFAULT_COLOR_EARNED)
	end

	-- One-shot: moves a never-customized earned color (still the native snapshot) to the new default. Never reset.
	if not ACABDB.expBarDefaultEarnedColorMigrated then
		ACABDB.expBarDefaultEarnedColorMigrated = true

		local native = ACABDB.expBarNativeColorEarned

		if native and ColorsMatch(ACABDB.expBarColorEarned, native) then
			ACABDB.expBarColorEarned = CopyColor(self.EXP_BAR_DEFAULT_COLOR_EARNED)
		end
	end

	if not ACABDB.expBarColorRested then
		local restedFrame = getglobal(self.EXP_RESTED_FRAME_NAME)
		local r, g, b

		if restedFrame and restedFrame.GetVertexColor then
			r, g, b = restedFrame:GetVertexColor()
		end

		-- Fallback: vanilla's rested-bonus blue.
		ACABDB.expBarColorRested = {
			r = r or 0.0,
			g = g or 0.39,
			b = b or 0.88,
		}

		ACABDB.expBarNativeColorRested = {
			r = ACABDB.expBarColorRested.r,
			g = ACABDB.expBarColorRested.g,
			b = ACABDB.expBarColorRested.b,
		}
	end
end

-- Applies the custom colors while Better Experience Bar is on, else reverts both fills to the native
-- snapshot; then refreshes the custom rested-XP overlay (which also uses expBarColorRested).
function ACAB:ApplyExpBarColors()
	self:CaptureExpBarColorsIfNeeded()

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)
	local restedFrame = getglobal(self.EXP_RESTED_FRAME_NAME)
	local earned, rested

	if ACABDB.betterExpBarEnabled then
		earned = ACABDB.expBarColorEarned
		rested = ACABDB.expBarColorRested
	else
		earned = ACABDB.expBarNativeColorEarned
		rested = ACABDB.expBarNativeColorRested
	end

	if frame and frame.SetStatusBarColor and earned then
		frame:SetStatusBarColor(earned.r, earned.g, earned.b)
	end

	if restedFrame and restedFrame.SetVertexColor and rested then
		restedFrame:SetVertexColor(rested.r, rested.g, rested.b)
	end

	self:ApplyExpBarRestedOverlay()
end

-- Color-picker swatch setters (ColorPickerFrame.func/cancelFunc).
function ACAB:SetExpBarColorEarned(r, g, b)
	self:CaptureExpBarColorsIfNeeded()

	ACABDB.expBarColorEarned = { r = r, g = g, b = b }

	self:ApplyExpBarColors()
end

function ACAB:SetExpBarColorRested(r, g, b)
	self:CaptureExpBarColorsIfNeeded()

	ACABDB.expBarColorRested = { r = r, g = g, b = b }

	self:ApplyExpBarColors()
end

-- "Reset Colors to Default": earned back to EXP_BAR_DEFAULT_COLOR_EARNED, rested back to its native snapshot.
function ACAB:ResetExpBarColors()
	self:CaptureExpBarColorsIfNeeded()

	local nativeRested = ACABDB.expBarNativeColorRested

	ACABDB.expBarColorEarned = CopyColor(self.EXP_BAR_DEFAULT_COLOR_EARNED)

	if nativeRested then
		ACABDB.expBarColorRested = {
			r = nativeRested.r,
			g = nativeRested.g,
			b = nativeRested.b,
		}
	end

	self:ApplyExpBarColors()
end

-------------------------------------------------------------------------
-- Custom rested-XP overlay, drawn over ExhaustionLevelFillBar (whose native width breaks with a large
-- rested pool). Fill and tick formulas ported from BEB/BEB.lua. Shown only while Better Experience Bar is
-- on and GetRestState() == 1; the native fill is never touched.
-------------------------------------------------------------------------

local function EnsureExpBarRestedOverlay(frame)
	if frame.ACABRestedOverlay then
		return frame.ACABRestedOverlay
	end

	-- "ARTWORK": above the native StatusBar fill, below the "OVERLAY" text.
	local tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")

	frame.ACABRestedOverlay = tex

	return tex
end

-- BEB's XpPerLvl table (index N = XP required from level N to N+1).
ACAB.XP_PER_LEVEL = {
	400, 900, 1400, 2100, 2800, 3600, 4400, 5400, 6500, 7600,
	8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
	25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
	50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
	95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
	153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800, 217400,
}

-- Paths must use the in-game AddOns folder name, "AlternativeClassicActionBars".
local BEB_TICK_TEXTURE = "Interface\\AddOns\\AlternativeClassicActionBars\\Textures\\BEB-ExhaustionTicks"
local BEB_TICK_GLOW_TEXTURE = "Interface\\AddOns\\AlternativeClassicActionBars\\Textures\\BEB-ExhaustionTicksGlow"

-- BEB's tick size, tied to its 2x2 quadrant art sheet.
local BEB_TICK_WIDTH = 27
local BEB_TICK_HEIGHT = 26

-- Rested-boundary tick ("ARTWORK") with its glow ("OVERLAY") on top.
local function EnsureExpBarRestedTick(frame)
	if frame.ACABRestedTick then
		return frame.ACABRestedTick, frame.ACABRestedTickGlow
	end

	local tick = frame:CreateTexture(nil, "ARTWORK")
	tick:SetTexture(BEB_TICK_TEXTURE)
	tick:SetWidth(BEB_TICK_WIDTH)
	tick:SetHeight(BEB_TICK_HEIGHT)

	-- Sized/anchored later via SetAllPoints(tick).
	local glow = frame:CreateTexture(nil, "OVERLAY")
	glow:SetTexture(BEB_TICK_GLOW_TEXTURE)

	frame.ACABRestedTick = tick
	frame.ACABRestedTickGlow = glow

	return tick, glow
end

-- Glow pulse: C_Timer ticker animating only the glow's alpha along a sine wave.
local EXP_BAR_RESTED_GLOW_PULSE_INTERVAL = 0.05
local EXP_BAR_RESTED_GLOW_PULSE_LOW_ALPHA = 0.35
local EXP_BAR_RESTED_GLOW_PULSE_HIGH_ALPHA = 1.0

-- Full pulse cycle in seconds when ACABDB.expBarGlowPulseInterval is unset.
local EXP_BAR_RESTED_GLOW_PULSE_PERIOD_DEFAULT = 1.5

local expBarRestedGlowPulseTicker
local expBarRestedGlowPulseStartTime

-- Cancels and nils the pulse ticker.
local function StopExpBarRestedGlowPulse()
	if expBarRestedGlowPulseTicker then
		expBarRestedGlowPulseTicker:Cancel()
		expBarRestedGlowPulseTicker = nil
	end
end

-- Starts the pulse ticker; no-op while already running.
local function StartExpBarRestedGlowPulse(glow)
	if expBarRestedGlowPulseTicker or not C_Timer or not C_Timer.NewTicker then
		return
	end

	expBarRestedGlowPulseStartTime = GetTime()

	expBarRestedGlowPulseTicker = C_Timer.NewTicker(EXP_BAR_RESTED_GLOW_PULSE_INTERVAL, function()
		local elapsed = GetTime() - expBarRestedGlowPulseStartTime

		-- Period read fresh every tick so the settings slider applies live.
		local period = (ACABDB and ACABDB.expBarGlowPulseInterval)
			or EXP_BAR_RESTED_GLOW_PULSE_PERIOD_DEFAULT

		local t = 0.5 + 0.5 * math.sin(elapsed * ((2 * math.pi) / period))
		local alpha = EXP_BAR_RESTED_GLOW_PULSE_LOW_ALPHA
			+ ((EXP_BAR_RESTED_GLOW_PULSE_HIGH_ALPHA - EXP_BAR_RESTED_GLOW_PULSE_LOW_ALPHA) * t)

		glow:SetAlpha(alpha)
	end)
end

-- Hides the tick and glow (if created) and stops the pulse.
local function HideExpBarRestedTick(tick, glow)
	if tick then
		tick:Hide()
	end

	if glow then
		glow:Hide()
	end

	StopExpBarRestedGlowPulse()
end

-- Hides the rested fill, tick, and glow (if created) and stops the pulse.
local function HideExpBarRestedOverlay(tex, tick, glow)
	if tex then
		tex:Hide()
	end

	HideExpBarRestedTick(tick, glow)
end

-- Lays out (or hides) the rested fill, tick, and glow pulse. Safe to call unconditionally.
function ACAB:ApplyExpBarRestedOverlay()
	self:EnsureDB()

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local tex = frame.ACABRestedOverlay
	local tick = frame.ACABRestedTick
	local glow = frame.ACABRestedTickGlow

	if not ACABDB.betterExpBarEnabled or not GetRestState or GetRestState() ~= 1 then
		HideExpBarRestedOverlay(tex, tick, glow)

		return
	end

	-- Unscaled local width, same as the native fill uses.
	local barWidth = frame:GetWidth()
	local xpMax = UnitXPMax and UnitXPMax("player")
	local xp = UnitXP and UnitXP("player")
	local exhaustion = GetXPExhaustion and GetXPExhaustion()

	if not barWidth or barWidth <= 0 or not xpMax or xpMax <= 0 or not xp or not exhaustion then
		HideExpBarRestedOverlay(tex, tick, glow)

		return
	end

	-- Earned-XP fill width; the rested fill starts where it ends.
	local scale = barWidth / xpMax
	local xpWidth = (xp == 0) and 1 or (scale * xp)

	local width

	if (xp + exhaustion) > xpMax then
		-- Rested pool passes this level: fill the rest of the bar.
		width = barWidth - xpWidth
	else
		local restedEdge = (xp + exhaustion) * scale
		width = restedEdge - xpWidth
	end

	if not width or width <= 0 then
		HideExpBarRestedOverlay(tex, tick, glow)

		return
	end

	tex = EnsureExpBarRestedOverlay(frame)

	local color = ACABDB.expBarColorRested

	if color then
		tex:SetVertexColor(color.r, color.g, color.b)
	end

	tex:ClearAllPoints()
	tex:SetPoint("TOPLEFT", frame, "TOPLEFT", xpWidth, 0)
	tex:SetWidth(width)
	tex:SetHeight(frame:GetHeight())
	tex:Show()

	-- Tick position may be progress into the next (or next-next) level, as a fraction of the bar width.
	local level = UnitLevel and UnitLevel("player")

	if not level or level < 1 or not ACAB.XP_PER_LEVEL[1] then
		HideExpBarRestedTick(tick, glow)

		return
	end

	local position
	local restState

	-- BEB's "BEBRestedXpTick" logic: restState 1 = within this level, 2 = crosses one level, 3 = two levels.
	if level < 59 then
		if (xp + exhaustion - xpMax) > ACAB.XP_PER_LEVEL[level + 1] then
			position = ((xp + exhaustion - xpMax - ACAB.XP_PER_LEVEL[level + 1]) / ACAB.XP_PER_LEVEL[level + 2]) * barWidth
			restState = 3
		elseif (xp + exhaustion) > xpMax then
			position = ((xp + exhaustion - xpMax) / ACAB.XP_PER_LEVEL[level + 1]) * barWidth
			restState = 2
		else
			position = (xp + exhaustion) * scale
			restState = 1
		end
	elseif level == 59 then
		-- No level-61 entry, so state 3 clamps to the bar's right edge.
		if (xp + exhaustion - xpMax) > ACAB.XP_PER_LEVEL[level + 1] then
			position = barWidth
			restState = 3
		elseif (xp + exhaustion) > xpMax then
			position = ((xp + exhaustion - xpMax) / ACAB.XP_PER_LEVEL[level + 1]) * barWidth
			restState = 2
		else
			position = (xp + exhaustion) * scale
			restState = 1
		end
	else
		-- Level 60+: two states, state 2 clamps to the bar's right edge.
		if (xp + exhaustion) > xpMax then
			position = barWidth
			restState = 2
		else
			position = (xp + exhaustion) * scale
			restState = 1
		end
	end

	tick, glow = EnsureExpBarRestedTick(frame)

	-- Quadrant of the 2x2 art sheet per restState, shared by tick and glow.
	local left, right, top, bottom

	if restState == 3 then
		left, right, top, bottom = 0, 0.5, 0.5, 1
	elseif restState == 2 then
		left, right, top, bottom = 0.5, 1, 0, 0.5
	else
		left, right, top, bottom = 0, 0.5, 0, 0.5
	end

	tick:SetTexCoord(left, right, top, bottom)
	glow:SetTexCoord(left, right, top, bottom)

	tick:ClearAllPoints()
	tick:SetPoint("CENTER", frame, "LEFT", position, 0)
	tick:Show()

	glow:ClearAllPoints()
	glow:SetAllPoints(tick)

	-- Glow pulses only while in a rest area right now (IsResting), not merely with banked rest XP.
	if IsResting and IsResting() == 1 then
		glow:Show()
		StartExpBarRestedGlowPulse(glow)
	else
		glow:Hide()
		StopExpBarRestedGlowPulse()
	end
end

-------------------------------------------------------------------------
-- "Better Experience Bar" text overlay
-- One centered FontString built from up to 5 toggleable segments (BEB TextVars.lua formulas), kept live by
-- Events.lua's betterExpBarEventFrame. Lives on its own "HIGH"-strata child frame of MainMenuExpBar so
-- MainMenuBarArtFrame (same "MEDIUM" tier as the bar) can't cover it.
-------------------------------------------------------------------------

-- Text overlay frame tracking MainMenuExpBar via SetAllPoints; starts hidden if the bar is disabled.
local function EnsureExpBarTextOverlay(frame)
	if frame.ACABTextOverlay then
		return frame.ACABTextOverlay
	end

	-- Must be parented to MainMenuExpBar, not UIParent, or its size/centering drifts.
	local overlay = CreateFrame("Frame", "ACABExpBarTextOverlay", frame)

	overlay:SetFrameStrata("HIGH")
	overlay:SetAllPoints(frame)

	-- Same state SetExpBarEnabled would have set had the overlay existed already.
	if ACABDB and ACABDB.expBarEnabled == false then
		overlay:Hide()
	end

	frame.ACABTextOverlay = overlay

	return overlay
end

-- Rounds to the nearest integer.
local function ExpBarRound(n)
	return math.floor(n + 0.5)
end

-- Joins the enabled, self-labeled segments ("Lvl 2", "26/900", "3%", ...) with spaces.
local function ComputeBetterExpBarText()
	local cur = UnitXP and UnitXP("player")
	local max = UnitXPMax and UnitXPMax("player")
	local exhaustion = GetXPExhaustion and GetXPExhaustion()

	local segments = {}
	local n = 0

	if ACABDB.expBarShowLevel then
		n = n + 1
		segments[n] = "Lvl " .. tostring(UnitLevel("player"))
	end

	if ACABDB.expBarShowCurrentOverMax and cur and max then
		n = n + 1
		segments[n] = tostring(cur) .. "/" .. tostring(max)
	end

	if ACABDB.expBarShowPercent then
		local levelPct = 0

		if cur and max and max > 0 then
			levelPct = ExpBarRound((cur / max) * 100)
		end

		n = n + 1
		segments[n] = tostring(levelPct) .. "%"
	end

	if ACABDB.expBarShowRestedPercent then
		local restedPct = 0

		if exhaustion and max and max > 0 then
			restedPct = ExpBarRound((exhaustion * 100) / (max * 1.5))
		end

		n = n + 1
		segments[n] = "Rested: " .. tostring(restedPct) .. "%"
	end

	if ACABDB.expBarShowRestedTotal then
		n = n + 1
		segments[n] = tostring(exhaustion or 0) .. " Rested Xp"
	end

	return table.concat(segments, " ")
end

-- Native text's real Show method, captured once before it gets neutered; restored when the feature is off.
local realExpOverlayTextShow

-- Refreshes the overlay text and keeps the native label hidden while the feature is on.
local function UpdateBetterExpBarText()
	local text = ACAB.betterExpBarText

	if text then
		text:SetText(ComputeBetterExpBarText())
	end

	local nativeText = ACAB:GetNativeExpOverlayText()

	if nativeText and ACABDB.betterExpBarEnabled then
		nativeText:Hide()
	end
end

-- Events.lua's betterExpBarEventFrame handler: refreshes the text and the rested-XP overlay.
function ACAB:BetterExpBarOnEvent()
	UpdateBetterExpBarText()
	self:ApplyExpBarRestedOverlay()
end

-- Returns (and caches) GameFontNormalSmall's path/size; a Font object, so no FontString is needed.
function ACAB:CaptureNativeExpBarFontIfNeeded()
	if self.NATIVE_EXPBAR_FONT then
		return self.NATIVE_EXPBAR_FONT
	end

	if not GameFontNormalSmall or not GameFontNormalSmall.GetFont then
		return nil
	end

	local path, size = GameFontNormalSmall:GetFont()

	if not path then
		return nil
	end

	self.NATIVE_EXPBAR_FONT = { path = path, size = size }

	return self.NATIVE_EXPBAR_FONT
end

-- Creates (once)/shows/hides the text overlay per ACABDB.betterExpBarEnabled, swapping the native label.
function ACAB:ApplyBetterExpBarVisual()
	self:EnsureDB()

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local nativeText = self:GetNativeExpOverlayText()

	-- Captured on every login regardless of the feature state.
	self:CaptureNativeExpBarFontIfNeeded()

	-- Must capture the real Show before it is ever neutered below.
	if nativeText and not realExpOverlayTextShow then
		realExpOverlayTextShow = nativeText.Show
	end

	if not ACABDB.betterExpBarEnabled then
		if self.betterExpBarText then
			self.betterExpBarText:Hide()
		end

		-- Restore the real Show before calling it.
		if nativeText then
			if realExpOverlayTextShow then
				nativeText.Show = realExpOverlayTextShow
			end

			nativeText:Show()
		end

		self:ApplyExpBarRestedOverlay()

		return
	end

	if nativeText then
		-- Neuters Show - native code re-shows this label, so a plain Hide() doesn't stick.
		if realExpOverlayTextShow then
			nativeText.Show = function() end
		end

		nativeText:Hide()
	end

	if not self.betterExpBarText then
		local textOverlay = EnsureExpBarTextOverlay(frame)
		local text = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

		text:SetPoint("CENTER", textOverlay, "CENTER", 0, 0)

		local fontPath, fontSize = text:GetFont()

		-- Saved size, else EXP_BAR_DEFAULT_FONT_SIZE; always OUTLINE.
		local applySize = ACABDB.expBarFontSize or self.EXP_BAR_DEFAULT_FONT_SIZE

		if fontPath then
			text:SetFont(fontPath, applySize or fontSize, "OUTLINE")
		end

		local textColor = ACABDB.expBarTextColor

		if textColor then
			text:SetTextColor(textColor.r, textColor.g, textColor.b)
		end

		self.betterExpBarText = text
	end

	self.betterExpBarText:Show()
	UpdateBetterExpBarText()

	self:ApplyExpBarRestedOverlay()
end

-- Font Size slider: rounds (GetFont sizes come back as floats) and applies.
function ACAB:SetExpBarFontSize(size)
	self:EnsureDB()

	size = ExpBarRound(size)

	ACABDB.expBarFontSize = size

	if self.betterExpBarText and self.NATIVE_EXPBAR_FONT then
		self.betterExpBarText:SetFont(self.NATIVE_EXPBAR_FONT.path, size, "OUTLINE")
	end
end

-- Pulse Interval slider: rounds to 1 decimal and clamps to 0.5-5 (the running ticker reads it every tick).
function ACAB:SetExpBarGlowPulseInterval(interval)
	self:EnsureDB()

	interval = tonumber(interval)

	if not interval then
		return
	end

	interval = ExpBarRound(interval * 10) / 10

	if interval < 0.5 then
		interval = 0.5
	end

	if interval > 5 then
		interval = 5
	end

	ACABDB.expBarGlowPulseInterval = interval
end

-- Text color swatch setter (ColorPickerFrame.func/cancelFunc).
function ACAB:SetExpBarTextColor(r, g, b)
	self:EnsureDB()

	ACABDB.expBarTextColor = { r = r, g = g, b = b }

	if self.betterExpBarText then
		self.betterExpBarText:SetTextColor(r, g, b)
	end
end

