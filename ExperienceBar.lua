-- ExperienceBar.lua
-- Experience Bar subsystem: position/enable/scale, bar-fill colors, the rested-XP overlay/tick/glow-pulse
-- ticker, and the "Better Experience Bar" text overlay. Built on DefaultBars.lua's shared single-native-
-- frame container engine - must load after DefaultBars.lua.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Experience Bar
-- MainMenuExpBar is a single self-contained frame whose child regions (MainMenuBarOverlayFrame,
-- ExhaustionLevelFillBar/ExhaustionTick/ExhaustionTickGlow for "rested") all anchor relative to it, so
-- repositioning/scaling this one frame carries the whole native visual along.
-- Every accessor is defensively nil-checked via getglobal.
-- Movable/scalable via the same EnsureContainerOverlay treatment as Latency Bar/Key Ring, always -
-- independent of ACABDB.betterExpBarEnabled (the text overlay further below).
-------------------------------------------------------------------------

ACAB.EXP_BAR_FRAME_NAME = "MainMenuExpBar"

-- The native "XP current / max" label lives on a FontString region owned by MainMenuBarOverlayFrame -
-- there is no separately-named MainMenuExpText global on this client.
ACAB.EXP_OVERLAY_FRAME_NAME = "MainMenuBarOverlayFrame"

-- Resolves MainMenuBarOverlayFrame's native "XP current / max" FontString region (found via
-- GetObjectType(), never a hardcoded index), caching the result on self once found.
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

-- Native "how far the rested bonus would carry the player" blue overlay region on MainMenuExpBar.
-- It's a Texture with a solid-color fill, not a StatusBar, so SetVertexColor/GetVertexColor is the
-- correct color API (not SetStatusBarColor/GetStatusBarColor).
ACAB.EXP_RESTED_FRAME_NAME = "ExhaustionLevelFillBar"

-- Mirrors CaptureLatencyBarPositionIfNeeded/CaptureKeyRingPositionIfNeeded, converted through
-- GetEffectiveScale since MainMenuExpBar's cluster can differ in scale from UIParent.
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

	-- Permanent pristine snapshot (Reset to Vanilla Layout) - stores the frame's true native anchor via
	-- GetPoint(1) rather than the absolute snapshot above. Captured once, never written again.
	if not ACABDB.expBarNativeAnchor then
		local point, relativeTo, relativePoint, nx, ny = frame:GetPoint(1)

		if point and relativePoint and nx and ny then
			local relativeToName = "UIParent"

			if relativeTo and relativeTo.GetName and relativeTo:GetName() then
				relativeToName = relativeTo:GetName()
			end

			ACABDB.expBarNativeAnchor = {
				point = point,
				relativeTo = relativeToName,
				relativePoint = relativePoint,
				x = nx,
				y = ny,
			}
		end
	end
end

-- MainMenuXPBarTexture0-3 (native race-themed border art) anchor "BOTTOM" at y=+3, leaving the real
-- y=0-to-+3 strip permanently uncovered once the bar moves off its fixed native position.
-- Covered by a custom gradient strip below - do not try cloning the native border texture instead,
-- it renders duplicated/distorted.
local function EnsureExpBarBottomBorderStrip(frame)
	if frame.ACABBottomBorderStrip then
		return frame.ACABBottomBorderStrip
	end

	-- "OVERLAY": must render on top of the bar's fill texture layer, or the strip gets painted over.
	local strip = frame:CreateTexture(nil, "OVERLAY")
	strip:SetTexture("Interface\\Buttons\\WHITE8X8")

	-- BOTTOMLEFT/BOTTOMRIGHT dual anchor auto-tracks any width/scale change. 4 units overshoots the
	-- 3-unit-tall y=0-to-+3 native gap.
	strip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
	strip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
	strip:SetHeight(4)

	-- SetGradientAlpha gives a light-to-dark vertical fade for a beveled look; falls back to a solid
	-- dark-gray SetVertexColor if unavailable.
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

	-- Pins Experience Bar to Latency Bar's strata, one frame level below it, so it always renders underneath.
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

	-- The rested-glow pulse child texture inherits this frame's alpha automatically, no separate handling needed.
	self:ApplyHoverOnlyState(frame, ACABDB.expBarHoverOnly, function() return ACABDB.expBarHoverDuration or 3 end)
end

function ACAB:SetExpBarPosition(x, y)
	x = tonumber(x)
	y = tonumber(y)

	if not x or not y or not ACABDB.expBarPosition then
		return
	end

	ACABDB.expBarPosition.x = x
	ACABDB.expBarPosition.y = y

	self:ApplyExpBarPosition()
end

-- Mirrors SetLatencyBarEnabled's structure - core UI element, default true, independently toggleable.
function ACAB:SetExpBarEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.expBarEnabled = enabled

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	if frame then
		if enabled then
			frame:Show()

			-- Text overlay isn't edit-mode-gated like frame.ACABOverlay, so it must be re-shown here
			-- explicitly or it stays invisible after a disable/re-enable cycle.
			if frame.ACABTextOverlay then
				frame.ACABTextOverlay:Show()
			end
		else
			frame:Hide()

			-- EnsureContainerOverlay's overlay is parented to UIParent, not `frame`, so hiding the real
			-- frame alone doesn't cascade to hide it.
			if frame.ACABOverlay then
				frame.ACABOverlay:Hide()
				frame.ACABOverlay:EnableMouse(false)
			end

			-- Same cascade problem/fix for the "Better Experience Bar" text overlay.
			if frame.ACABTextOverlay then
				frame.ACABTextOverlay:Hide()
			end
		end
	end
end

-- Mirrors SetLatencyBarScale/SetKeyRingScale's clamp/write/apply template.
function ACAB:SetExpBarScale(scale)
	self:EnsureDB()

	scale = self:ClampScaleSetting(scale)

	if not scale then
		return
	end

	local oldScale = ACABDB.expBarScale or 1
	local pos = ACABDB.expBarPosition
	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	if pos and frame then
		self:CompensateScaleKeepingCornerFixed(pos, oldScale, scale, "CENTER", frame:GetWidth(), frame:GetHeight())
	end

	ACABDB.expBarScale = scale

	if frame then
		frame:SetScale(scale)
	end

	if pos then
		self:ApplyExpBarPosition()
	end
end

-- Settings.lua's Experience Bar page "Only show on hover" checkbox/slider.
function ACAB:SetExpBarHoverOnly(enabled)
	self:SetHoverOnlySetting("expBarHoverOnly", enabled, self.ApplyExpBarPosition)
end

function ACAB:SetExpBarHoverDuration(duration)
	self:SetHoverDurationSetting("expBarHoverDuration", duration, self.ApplyExpBarPosition)
end

-- Settings.lua's Experience Bar page "Reset to Vanilla Layout" button - restores position AND scale.
function ACAB:ResetExpBarLayout()
	local native = ACABDB.expBarNativeAnchor
	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	-- Direct write, not SetExpBarScale(1) - that setter compensates the stored position using the OLD
	-- scale, which would inflate the native position we're about to restore. Set before resolving it.
	ACABDB.expBarScale = 1

	if frame then
		frame:SetScale(1)
	end

	local resolved = self:ResolveNativeAnchorToAbsolute(frame, native)

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

	local cx, cy = self:GetCursorPositionUIScale()

	local frame = self:EnsureDragFrame()

	frame.dragKind = "expBar"
	frame.dragStartCursorX = cx
	frame.dragStartCursorY = cy
	frame.dragStartX = pos.x or 0
	frame.dragStartY = pos.y or 0

	frame:SetScript("OnUpdate", self.DefaultBarDrag_OnUpdate)
	frame:Show()
end

function ACAB:StopExpBarDrag()
	self:StopSharedDrag()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage("expbar")
	end
end

-------------------------------------------------------------------------
-- Bar-fill colors
-- MainMenuExpBar's StatusBar fill and ExhaustionLevelFillBar's Texture fill are each independently
-- recolorable via Settings.lua's color-picker swatches. Native baseline captured lazily from the live
-- frames rather than seeded in Core.lua's EnsureDB, since the color getters return nothing meaningful
-- until these frames exist.
-- ExhaustionLevelFillBar is a Texture, so it uses SetVertexColor/GetVertexColor; MainMenuExpBar uses
-- SetStatusBarColor/GetStatusBarColor.
-------------------------------------------------------------------------

function ACAB:CaptureExpBarColorsIfNeeded()
	self:EnsureDB()

	if not ACABDB.expBarColorEarned then
		local frame = getglobal(self.EXP_BAR_FRAME_NAME)
		local r, g, b

		if frame and frame.GetStatusBarColor then
			r, g, b = frame:GetStatusBarColor()
		end

		-- Fallback: a reasonable vanilla-matching purple/violet, only used
		-- if the live frame isn't available yet at capture time.
		ACABDB.expBarColorEarned = {
			r = r or 0.58,
			g = g or 0.0,
			b = b or 0.55,
		}

		-- Permanent pristine snapshot ("Reset Colors to Default"), mirroring
		-- Same capture-once/never-rewritten pattern as expBarNativeAnchor above.
		ACABDB.expBarNativeColorEarned = {
			r = ACABDB.expBarColorEarned.r,
			g = ACABDB.expBarColorEarned.g,
			b = ACABDB.expBarColorEarned.b,
		}
	end

	if not ACABDB.expBarColorRested then
		local restedFrame = getglobal(self.EXP_RESTED_FRAME_NAME)
		local r, g, b

		if restedFrame and restedFrame.GetVertexColor then
			r, g, b = restedFrame:GetVertexColor()
		end

		-- Fallback: real vanilla's own rested-bonus blue.
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

-- When the feature is off, explicitly reverts both frames to their captured native baseline color
-- rather than leaving them untouched. Single choke point for the login sequence, color-picker
-- live-preview func/cancelFunc, "Reset Colors to Default", and the "Enable Better Experience Bar" checkbox.
function ACAB:ApplyExpBarColors()
	self:CaptureExpBarColorsIfNeeded()

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)
	local restedFrame = getglobal(self.EXP_RESTED_FRAME_NAME)

	if not ACABDB.betterExpBarEnabled then
		local nativeEarned = ACABDB.expBarNativeColorEarned
		local nativeRested = ACABDB.expBarNativeColorRested

		if frame and frame.SetStatusBarColor and nativeEarned then
			frame:SetStatusBarColor(nativeEarned.r, nativeEarned.g, nativeEarned.b)
		end

		if restedFrame and restedFrame.SetVertexColor and nativeRested then
			restedFrame:SetVertexColor(nativeRested.r, nativeRested.g, nativeRested.b)
		end

		-- The custom rested-XP overlay reuses this same expBarColorRested field.
		self:ApplyExpBarRestedOverlay()

		return
	end

	local earned = ACABDB.expBarColorEarned

	if frame and frame.SetStatusBarColor and earned then
		frame:SetStatusBarColor(earned.r, earned.g, earned.b)
	end

	local rested = ACABDB.expBarColorRested

	if restedFrame and restedFrame.SetVertexColor and rested then
		restedFrame:SetVertexColor(rested.r, rested.g, rested.b)
	end

	self:ApplyExpBarRestedOverlay()
end

-- Settings.lua's color-picker swatches call these directly from
-- ColorPickerFrame.func/cancelFunc.
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

-- Settings.lua's "Reset Colors to Default" button.
function ACAB:ResetExpBarColors()
	self:CaptureExpBarColorsIfNeeded()

	local nativeEarned = ACABDB.expBarNativeColorEarned
	local nativeRested = ACABDB.expBarNativeColorRested

	if nativeEarned then
		ACABDB.expBarColorEarned = {
			r = nativeEarned.r,
			g = nativeEarned.g,
			b = nativeEarned.b,
		}
	end

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
-- Custom rested-XP overlay
-- Replaces ExhaustionLevelFillBar's own native width, which degenerates to ~8 units wide whenever
-- UnitXP+GetXPExhaustion exceeds UnitXPMax (a large banked rested pool) - a custom Texture is drawn on
-- top instead. Formula ported from BEB/BEB.lua's BEB.UpdateElement("BEBRestedXpBar")/"BEBXpBar" branches.
-- Gated on ACABDB.betterExpBarEnabled and GetRestState() == 1; native ExhaustionLevelFillBar untouched when off.
-------------------------------------------------------------------------

local function EnsureExpBarRestedOverlay(frame)
	if frame.ACABRestedOverlay then
		return frame.ACABRestedOverlay
	end

	-- "ARTWORK": above the native StatusBar fill, below "OVERLAY" so the Better Exp Bar text stays on top.
	local tex = frame:CreateTexture(nil, "ARTWORK")
	tex:SetTexture("Interface\\Buttons\\WHITE8X8")

	frame.ACABRestedOverlay = tex

	return tex
end

-- Rested-XP boundary tick: ports BEB's custom art (BEB_TICK_TEXTURE/BEB_TICK_GLOW_TEXTURE below) and
-- its multi-level-crossing position/texcoord logic from BEB/BEB.lua's BEB.UpdateElement
-- "BEBRestedXpTick"/"BEBRestedXpTickGlow" branches. "ARTWORK" (tick) below "OVERLAY" (glow) reproduces
-- BEB's own frame-level ordering (glow renders on top of tick).

-- BEB/BEB.lua's own BEB.XpPerLvl table, ported verbatim (index N = XP required from level N to N+1).
ACAB.XP_PER_LEVEL = {
	400, 900, 1400, 2100, 2800, 3600, 4400, 5400, 6500, 7600,
	8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
	25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
	50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
	95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
	153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800, 217400,
}

-- SetTexture paths must resolve against the in-game AddOns folder name, "AlternativeClassicActionBars".
local BEB_TICK_TEXTURE = "Interface\\AddOns\\AlternativeClassicActionBars\\Textures\\BEB-ExhaustionTicks"
local BEB_TICK_GLOW_TEXTURE = "Interface\\AddOns\\AlternativeClassicActionBars\\Textures\\BEB-ExhaustionTicksGlow"

-- BEB's own default BEBRestedXpTick size - the tick/glow art is a hand-drawn 2x2 quadrant sheet, so its
-- pixel dimensions are tied to that art, not to MainMenuExpBar's own native height.
local BEB_TICK_WIDTH = 27
local BEB_TICK_HEIGHT = 26

local function EnsureExpBarRestedTick(frame)
	if frame.ACABRestedTick then
		return frame.ACABRestedTick, frame.ACABRestedTickGlow
	end

	local tick = frame:CreateTexture(nil, "ARTWORK")
	tick:SetTexture(BEB_TICK_TEXTURE)
	tick:SetWidth(BEB_TICK_WIDTH)
	tick:SetHeight(BEB_TICK_HEIGHT)

	-- Glow covers tick's own bounds exactly (SetAllPoints(tick) below, once tick is positioned/sized).
	local glow = frame:CreateTexture(nil, "OVERLAY")
	glow:SetTexture(BEB_TICK_GLOW_TEXTURE)

	frame.ACABRestedTick = tick
	frame.ACABRestedTickGlow = glow

	return tick, glow
end

-- Rested-XP tick glow pulse: looping alpha animation driven by C_Timer.NewTicker (BEB's source has no
-- such animation). Only the glow's alpha is animated; the tick texture stays constant.
local EXP_BAR_RESTED_GLOW_PULSE_INTERVAL = 0.05
local EXP_BAR_RESTED_GLOW_PULSE_LOW_ALPHA = 0.35
local EXP_BAR_RESTED_GLOW_PULSE_HIGH_ALPHA = 1.0

-- Full fade-in/fade-out cycle, seconds - fallback for saves that predate ACABDB.expBarGlowPulseInterval.
-- The ticker callback reads the DB field fresh every tick so the Settings.lua slider can change speed live.
local EXP_BAR_RESTED_GLOW_PULSE_PERIOD_DEFAULT = 1.5

local expBarRestedGlowPulseTicker
local expBarRestedGlowPulseStartTime

-- Cancels the ticker outright (Cancel()-and-nil, not a pause flag) whenever the glow isn't shown.
local function StopExpBarRestedGlowPulse()
	if expBarRestedGlowPulseTicker then
		expBarRestedGlowPulseTicker:Cancel()
		expBarRestedGlowPulseTicker = nil
	end
end

-- Idempotent - a call while already running is a no-op, so repeated ApplyExpBarRestedOverlay calls
-- while resting never restart/stutter the animation.
local function StartExpBarRestedGlowPulse(glow)
	if expBarRestedGlowPulseTicker or not C_Timer or not C_Timer.NewTicker then
		return
	end

	expBarRestedGlowPulseStartTime = GetTime()

	expBarRestedGlowPulseTicker = C_Timer.NewTicker(EXP_BAR_RESTED_GLOW_PULSE_INTERVAL, function()
		local elapsed = GetTime() - expBarRestedGlowPulseStartTime

		-- Sine-wave oscillation, t sweeps 0..1..0 once per `period` seconds - read fresh every tick so
		-- Settings.lua slider changes take effect on the next tick.
		local period = (ACABDB and ACABDB.expBarGlowPulseInterval)
			or EXP_BAR_RESTED_GLOW_PULSE_PERIOD_DEFAULT

		local t = 0.5 + 0.5 * math.sin(elapsed * ((2 * math.pi) / period))
		local alpha = EXP_BAR_RESTED_GLOW_PULSE_LOW_ALPHA
			+ ((EXP_BAR_RESTED_GLOW_PULSE_HIGH_ALPHA - EXP_BAR_RESTED_GLOW_PULSE_LOW_ALPHA) * t)

		glow:SetAlpha(alpha)
	end)
end

-- Called from ACAB:ApplyExpBarColors, ACAB:ApplyBetterExpBarVisual, and Events.lua's
-- betterExpBarEventFrame OnEvent handler - safe to call unconditionally from all of them.
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
		if tex then
			tex:Hide()
		end

		if tick then
			tick:Hide()
		end

		if glow then
			glow:Hide()
		end

		StopExpBarRestedGlowPulse()

		return
	end

	-- GetWidth() is unaffected by SetScale (which only changes rendering), same as the native fill uses.
	local barWidth = frame:GetWidth()
	local xpMax = UnitXPMax and UnitXPMax("player")
	local xp = UnitXP and UnitXP("player")
	local exhaustion = GetXPExhaustion and GetXPExhaustion()

	if not barWidth or barWidth <= 0 or not xpMax or xpMax <= 0 or not xp or not exhaustion then
		if tex then
			tex:Hide()
		end

		if tick then
			tick:Hide()
		end

		if glow then
			glow:Hide()
		end

		StopExpBarRestedGlowPulse()

		return
	end

	-- Earned-XP fill width; the rested overlay's left edge starts where this ends.
	local scale = barWidth / xpMax
	local xpWidth = (xp == 0) and 1 or (scale * xp)

	local width

	if (xp + exhaustion) > xpMax then
		-- Exceeds max: fill the entire remainder of the bar.
		width = barWidth - xpWidth
	else
		local restedEdge = (xp + exhaustion) * scale
		width = restedEdge - xpWidth
	end

	if not width or width <= 0 then
		if tex then
			tex:Hide()
		end

		if tick then
			tick:Hide()
		end

		if glow then
			glow:Hide()
		end

		StopExpBarRestedGlowPulse()

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

	-- The tick's position is independent of the rested-overlay fill's boundaryX above - it can represent
	-- progress into the next (or next-next) level's XP requirement, as a fraction of the same bar width.
	local level = UnitLevel and UnitLevel("player")

	if not level or level < 1 or not ACAB.XP_PER_LEVEL[1] then
		if tick then
			tick:Hide()
		end

		if glow then
			glow:Hide()
		end

		StopExpBarRestedGlowPulse()

		return
	end

	local position
	local restState

	-- Ported from BEB/BEB.lua's "BEBRestedXpTick" branch - three level brackets (< 59 / == 59 / == 60),
	-- each with within-level / crosses-one-level / crosses-two-levels sub-branching.
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
		-- Same 3 states, but ACAB.XP_PER_LEVEL has no level 61 entry to measure fractional progress
		-- against, so the "crosses two levels" case clamps to the bar's right edge instead.
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
		-- level == 60 (vanilla cap, 2 states) - also the fallback for level > 60, clamped to the bar's right edge.
		if (xp + exhaustion) > xpMax then
			position = barWidth
			restState = 2
		else
			position = (xp + exhaustion) * scale
			restState = 1
		end
	end

	tick, glow = EnsureExpBarRestedTick(frame)

	-- BEB's texcoord selection: a 2x2 quadrant sheet, same mapping for both tick and glow.
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

	-- IsResting() reports standing in a rest area right now (distinct from GetRestState(), which stays
	-- 1 for banked rest XP even after leaving the inn).
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
-- Modeled on the BEB reference addon's TextVars.lua formulas - a single centered FontString assembled
-- from up to 5 independently toggleable segments, kept live via PLAYER_XP_UPDATE/UPDATE_EXHAUSTION/
-- PLAYER_LEVEL_UP, all registered unconditionally.
-- Entirely independent of the Experience Bar container above - follows MainMenuExpBar's position/scale.
-- The FontString lives on its own dedicated "HIGH"-strata overlay frame rather than directly on
-- MainMenuExpBar, since that frame sits below MainMenuBarArtFrame within the "MEDIUM" strata tier.
-------------------------------------------------------------------------

-- Dedicated overlay frame the text FontString is created on; SetAllPoints(frame) tracks MainMenuExpBar's
-- own position/size. Reads the live ACABDB.expBarEnabled flag at creation time so a bar that starts
-- disabled doesn't leave this text floating (created lazily, so SetExpBarEnabled can't reach it earlier).
local function EnsureExpBarTextOverlay(frame)
	if frame.ACABTextOverlay then
		return frame.ACABTextOverlay
	end

	-- Parented to `frame` (MainMenuExpBar), not UIParent, so it doesn't drift off-center; a child
	-- frame's strata/level is independent of its parent's, so this doesn't reintroduce art-masking.
	local overlay = CreateFrame("Frame", "ACABExpBarTextOverlay", frame)

	overlay:SetFrameStrata("HIGH")
	overlay:SetAllPoints(frame)

	-- Matches whatever SetExpBarEnabled would already have set had this overlay existed at login time.
	if ACABDB and ACABDB.expBarEnabled == false then
		overlay:Hide()
	end

	frame.ACABTextOverlay = overlay

	return overlay
end

-- Lua 5.0 has no math.round - same floor(x + 0.5) idiom used throughout this addon.
local function ExpBarRound(n)
	return math.floor(n + 0.5)
end

-- Assembles only the currently-enabled segments into one space-joined line (each segment is already
-- self-labeled, e.g. "Lvl 2", "26/900", "3%"). Ported from BEB/TextVars.lua's "$plv"/"$pdl"/"$prt"/"$rxp".
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

-- A plain Hide() call does not stick - native code re-Shows this FontString on other triggers.
-- Neutering Show() itself fixes it, but must be reversible: captured once, lazily, restored when the
-- feature turns back off.
local realExpOverlayTextShow

local function UpdateBetterExpBarText()
	local text = ACAB.betterExpBarText

	if text then
		text:SetText(ComputeBetterExpBarText())
	end

	-- Show() itself is neutered while the feature is on, so this Hide() call is defense-in-depth.
	local nativeText = ACAB:GetNativeExpOverlayText()

	if nativeText and ACABDB.betterExpBarEnabled then
		nativeText:Hide()
	end
end

-- Shared OnEvent handler for Events.lua's betterExpBarEventFrame watcher - refreshes both the text
-- overlay and the custom rested-XP overlay, since both are gated on the same enable toggle.
function ACAB:BetterExpBarOnEvent()
	UpdateBetterExpBarText()
	self:ApplyExpBarRestedOverlay()
end

-- Creates (once)/shows/hides/live-updates the text overlay per ACABDB.betterExpBarEnabled.
-- GameFontNormalSmall supports GetFont() with no FontString instance required, so it's read lazily here
-- (the overlay itself may not exist yet to sample a size from).
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

function ACAB:ApplyBetterExpBarVisual()
	self:EnsureDB()

	local frame = getglobal(self.EXP_BAR_FRAME_NAME)

	if not frame then
		return
	end

	local nativeText = self:GetNativeExpOverlayText()

	-- Captured unconditionally so ACAB.NATIVE_EXPBAR_FONT is populated on every login regardless of
	-- whether the feature is currently on.
	self:CaptureNativeExpBarFontIfNeeded()

	-- Captures the real Show method exactly once, lazily - must happen before it's ever neutered below.
	if nativeText and not realExpOverlayTextShow then
		realExpOverlayTextShow = nativeText.Show
	end

	if not ACABDB.betterExpBarEnabled then
		if self.betterExpBarText then
			self.betterExpBarText:Hide()
		end

		-- Reversible restore: undo the Show() neutering below before calling Show(), so the native
		-- label comes back rather than silently no-oping against its own neutered method.
		if nativeText then
			if realExpOverlayTextShow then
				nativeText.Show = realExpOverlayTextShow
			end

			nativeText:Show()
		end

		-- Hides the custom rested-XP overlay too - gated on this same toggle.
		self:ApplyExpBarRestedOverlay()

		return
	end

	if nativeText then
		-- Neuters Show() itself so no native handler can re-show this label - a plain Hide() doesn't stick.
		if realExpOverlayTextShow then
			nativeText.Show = function() end
		end

		nativeText:Hide()
	end

	if not self.betterExpBarText then
		-- Created on the dedicated text-overlay frame, not on `frame` directly (see section header).
		-- The overlay SetAllPoints(frame), so anchoring CENTER to the overlay's CENTER lands this
		-- exactly in the middle of the bar.
		local textOverlay = EnsureExpBarTextOverlay(frame)
		local text = textOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

		text:SetPoint("CENTER", textOverlay, "CENTER", 0, 0)

		-- OUTLINE flag keeps this readable regardless of the fill color underneath it.
		local fontPath, fontSize = text:GetFont()

		-- Starts one size smaller than the native default until ACABDB.expBarFontSize holds a real
		-- saved value (same lazy-default idiom as ACABDB.hotkeyFontSize/countFontSize).
		local applySize = ACABDB.expBarFontSize

		if not applySize and self.NATIVE_EXPBAR_FONT then
			applySize = self.NATIVE_EXPBAR_FONT.size - 1
		end

		if fontPath then
			text:SetFont(fontPath, applySize or fontSize, "OUTLINE")
		end

		-- ACABDB.expBarTextColor has no native equivalent to preserve/revert to (this addon's own
		-- FontString, not a native region), so a straight default is seeded rather than captured.
		local textColor = ACABDB.expBarTextColor

		if textColor then
			text:SetTextColor(textColor.r, textColor.g, textColor.b)
		end

		self.betterExpBarText = text

		-- Events.lua's betterExpBarEventFrame watcher is created unconditionally at file load, not
		-- lazily here - it no-ops safely via self.betterExpBarText's own nil-checks while the feature is off.
	end

	self.betterExpBarText:Show()
	UpdateBetterExpBarText()

	-- Shows/refreshes the custom rested-XP overlay immediately rather than waiting for the next event.
	self:ApplyExpBarRestedOverlay()
end

-- Settings.lua's Experience Bar page Font Size slider calls this directly on every OnValueChanged -
-- mirrors Button.lua's SetHotkeyFontSize/SetCountFontSize's round-then-write template (GetFont() has
-- float imprecision on this client, e.g. 11.999999726451 instead of 12).
function ACAB:SetExpBarFontSize(size)
	self:EnsureDB()

	size = math.floor(size + 0.5)

	ACABDB.expBarFontSize = size

	if self.betterExpBarText and self.NATIVE_EXPBAR_FONT then
		self.betterExpBarText:SetFont(self.NATIVE_EXPBAR_FONT.path, size, "OUTLINE")
	end
end

-- Settings.lua's Experience Bar page Pulse Interval slider calls this directly - rounds to 1 decimal and
-- clamps to 0.5-5.0 so a stray write can't hand the sine formula a zero/negative period. The ticker
-- callback reads this field fresh every tick, so writing it here is enough to reach the running animation.
function ACAB:SetExpBarGlowPulseInterval(interval)
	self:EnsureDB()

	interval = tonumber(interval)

	if not interval then
		return
	end

	interval = math.floor((interval * 10) + 0.5) / 10

	if interval < 0.5 then
		interval = 0.5
	end

	if interval > 5 then
		interval = 5
	end

	ACABDB.expBarGlowPulseInterval = interval
end

-- Settings.lua's text-color swatch calls this from ColorPickerFrame.func/cancelFunc - same mechanic as
-- SetExpBarColorEarned/SetExpBarColorRested above, against this addon's own FontString via SetTextColor.
function ACAB:SetExpBarTextColor(r, g, b)
	self:EnsureDB()

	ACABDB.expBarTextColor = { r = r, g = g, b = b }

	if self.betterExpBarText then
		self.betterExpBarText:SetTextColor(r, g, b)
	end
end

