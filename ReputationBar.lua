-- ReputationBar.lua
-- Reputation Bar (ReputationWatchBar): follows the Experience Bar (on top of it, in its spot at max level). With
-- "Better Reputation Bar" on it groups to the Experience Bar's top/bottom or moves/scales on its own, plus a text overlay.

local ACAB = AlternativeClassicActionBars

ACAB.REP_BAR_FRAME_NAME = "ReputationWatchBar"
ACAB.REP_BAR_STATUS_FRAME_NAME = "ReputationWatchStatusBar"
ACAB.REP_BAR_NATIVE_TEXT_NAME = "ReputationWatchStatusBarText"

-- Better Reputation Bar's default overlay text size and color.
ACAB.REP_BAR_DEFAULT_FONT_SIZE = 10
ACAB.REP_BAR_DEFAULT_TEXT_COLOR = { r = 1, g = 1, b = 1 }

local REP_BAR_GUARD_FLAG = "ACABApplyingRepBarPosition"

-- Y offset per grouped side; TOP keeps native's 3-unit overlap with the Exp Bar.
local REP_BAR_SIDE_OFFSET_Y = { TOP = -3, BOTTOM = 0 }

-- Max gap (UIParent units) between Rep and Exp Bar edges for a drag stop to group them.
local REP_BAR_GROUP_SNAP_DISTANCE = 10

-- Swallows native re-anchors (ReputationWatchBar_Update re-pins it to MainMenuBar on every update).
ACAB:InstallReanchorGuard(getglobal(ACAB.REP_BAR_FRAME_NAME), REP_BAR_GUARD_FLAG)

-- Blocks native re-shows while the Reputation Bar is disabled.
ACAB:InstallShowGuard(getglobal(ACAB.REP_BAR_FRAME_NAME), function()
	return ACABDB and ACABDB.repBarEnabled ~= false
end)

-------------------------------------------------------------------------
-- Placement: follow the Experience Bar, or a saved free position
-------------------------------------------------------------------------

-- True while the Rep Bar is placed off the Exp Bar: Better Reputation Bar off, or on and grouped.
function ACAB:IsRepBarFollowingExpBar()
	return not ACABDB.betterRepBarEnabled or ACABDB.repBarGrouped ~= false
end

-- Exp Bar side the Rep Bar follows on; native mode always sits on top.
local function GetRepBarFollowSide()
	if ACABDB.betterRepBarEnabled and ACABDB.repBarGroupSide == "BOTTOM" then
		return "BOTTOM"
	end

	return "TOP"
end

-- Anchors the Rep Bar to the Exp Bar at the Exp Bar's effective scale.
local function ApplyRepBarFollowPosition(frame, expBar)
	frame:SetScale(expBar:GetEffectiveScale() / UIParent:GetEffectiveScale())

	local point, relativePoint, y

	if ACAB:IsPlayerMaxLevel() then
		-- Takes the Exp Bar's spot, as native does at max level.
		point, relativePoint, y = "TOP", "TOP", 0
	else
		local side = GetRepBarFollowSide()

		if side == "TOP" then
			point, relativePoint = "BOTTOM", "TOP"
		else
			point, relativePoint = "TOP", "BOTTOM"
		end

		y = REP_BAR_SIDE_OFFSET_Y[side]
	end

	frame[REP_BAR_GUARD_FLAG] = true
	frame:ClearAllPoints()
	ACAB:PixelSetPoint(frame, point, expBar, relativePoint, 0, y)
	frame[REP_BAR_GUARD_FLAG] = nil
end

-- Places the Rep Bar per its mode and ensures its edit-mode overlay. No-op before SetupRepBar.
function ACAB:ApplyRepBarPosition()
	if not self.repBarReady then return end

	local frame = getglobal(self.REP_BAR_FRAME_NAME)
	local expBar = getglobal(self.EXP_BAR_FRAME_NAME)
	if not frame or not expBar then return end

	if self:IsRepBarFollowingExpBar() or not ACABDB.repBarPosition then
		ApplyRepBarFollowPosition(frame, expBar)
	else
		frame:SetScale(ACABDB.repBarScale or 1)
		self:ApplySavedPosition(frame, ACABDB.repBarPosition, REP_BAR_GUARD_FLAG)
	end

	self:EnsureContainerOverlay(frame, self.StartRepBarDrag, self.StopRepBarDrag, "repbar", self.SetRepBarScale, nil, "Reputation Bar")
end

function ACAB:SetRepBarPosition(x, y)
	if self:IsRepBarFollowingExpBar() then return end

	if self:WriteSavedPositionXY("repBarPosition", x, y) then
		self:ApplyRepBarPosition()
	end
end

function ACAB:SetRepBarScale(scale)
	if self:IsRepBarFollowingExpBar() then return end

	self:SetElementScale("repBarScale", "repBarPosition", getglobal(self.REP_BAR_FRAME_NAME), scale, nil, self.ApplyRepBarPosition)
end

-- Disabling hides it; enabling lets native code re-show it (only while a faction is watched).
function ACAB:SetRepBarEnabled(enabled)
	self:EnsureDB()

	ACABDB.repBarEnabled = enabled and true or false

	if enabled then
		ReputationWatchBar_Update()
	else
		self:SetElementShown(getglobal(self.REP_BAR_FRAME_NAME), false)
	end

	self:ApplyRepBarEditVisual(self:CanDragDefaultLayout())
end

-- "Reset to Vanilla/Modern Layout": grouped on top of the Exp Bar, scale 1, free position cleared.
function ACAB:ResetRepBarLayout()
	self:EnsureDB()

	ACABDB.repBarGrouped = true
	ACABDB.repBarGroupSide = "TOP"
	ACABDB.repBarScale = 1
	ACABDB.repBarPosition = nil

	self:ApplyRepBarPosition()
	self:ApplyRepBarEditVisual(self:CanDragDefaultLayout())
end

-------------------------------------------------------------------------
-- Grouping with the Experience Bar (lock icon, snap on drag stop)
-------------------------------------------------------------------------

-- frame's rect in UIParent units: left, right, bottom, top (nil while unresolved).
local function GetUIParentRect(frame)
	local left, right = frame:GetLeft(), frame:GetRight()
	local bottom, top = frame:GetBottom(), frame:GetTop()
	if not left or not right or not bottom or not top then return nil end

	local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()

	return left * ratio, right * ratio, bottom * ratio, top * ratio
end

-- frame's current spot as a canonical position, or nil while unresolved.
local function CaptureRepBarCurrentPosition(frame)
	local left, top = frame:GetLeft(), frame:GetTop()
	if not left or not top then return nil end

	local pos = { point = "TOPLEFT", relativePoint = "BOTTOMLEFT", x = left, y = top }

	ACAB:ConvertPositionToCanonical(frame, pos)

	return pos
end

-- Saved free position, or the live spot while following the Exp Bar (settings-page sliders).
function ACAB:GetRepBarPosition()
	if not self:IsRepBarFollowingExpBar() and ACABDB.repBarPosition then
		return ACABDB.repBarPosition
	end

	local frame = getglobal(self.REP_BAR_FRAME_NAME)

	return frame and CaptureRepBarCurrentPosition(frame)
end

-- Groups (to side, else the last one) or ungroups the Rep Bar; ungrouping keeps its current spot and size.
function ACAB:SetRepBarGrouped(grouped, side)
	self:EnsureDB()

	local frame = getglobal(self.REP_BAR_FRAME_NAME)
	if not frame then return end

	if grouped then
		ACABDB.repBarGrouped = true

		if side then
			ACABDB.repBarGroupSide = side
		end
	else
		local pos = CaptureRepBarCurrentPosition(frame)

		if pos then
			ACABDB.repBarPosition = pos
		end

		ACABDB.repBarScale = self:ClampScaleSetting(frame:GetEffectiveScale() / UIParent:GetEffectiveScale()) or 1
		ACABDB.repBarGrouped = false
	end

	self:ApplyRepBarPosition()
	self:ApplyRepBarEditVisual(self:CanDragDefaultLayout())
	self:RefreshBarSettingsPage("repbar")
end

-- Shared by the settings-page and edit-mode lock icons.
function ACAB:ToggleRepBarGroupLock()
	if not ACABDB.betterRepBarEnabled then return end

	self:SetRepBarGrouped(not self:IsRepBarFollowingExpBar())
end

-- Groups a free Rep Bar dropped with an edge near the Exp Bar's top or bottom edge (horizontal overlap required).
function ACAB:TryGroupRepBarWithExpBar()
	if not ACABDB.betterRepBarEnabled or self:IsRepBarFollowingExpBar() then return end

	local rL, rR, rB, rT = GetUIParentRect(getglobal(self.REP_BAR_FRAME_NAME))
	local eL, eR, eB, eT = GetUIParentRect(getglobal(self.EXP_BAR_FRAME_NAME))
	if not rL or not eL then return end

	if rR <= eL or rL >= eR then return end

	if math.abs(rB - eT) <= REP_BAR_GROUP_SNAP_DISTANCE then
		self:SetRepBarGrouped(true, "TOP")
	elseif math.abs(rT - eB) <= REP_BAR_GROUP_SNAP_DISTANCE then
		self:SetRepBarGrouped(true, "BOTTOM")
	end
end

function ACAB:StartRepBarDrag()
	self:StartElementDrag("repBar")
end

function ACAB:StopRepBarDrag()
	self:StopSharedDrag()
	self:TryGroupRepBarWithExpBar()
	self:RefreshBarSettingsPage("repbar")
end

-- Edit-mode lock icon, parented to the Rep Bar (hides with it).
local function EnsureRepBarLockIcon(frame)
	if frame.ACABGroupLockIcon then
		return frame.ACABGroupLockIcon
	end

	local icon = ACAB:CreateLockToggleButton(frame, "ACABEditModeGroupLockrepbar", {
		tooltipTitle = "Reputation Bar",
		lockedLine = "This Element is currently locked to the Experience Bar, click to unlock",
		unlockedLine = "This Element is currently unlocked from the Experience Bar, click to lock",
		onClick = function()
			ACAB:ToggleRepBarGroupLock()
		end,
	})

	icon:SetFrameStrata("TOOLTIP")
	icon:SetFrameLevel(200)
	icon:Hide()

	frame.ACABGroupLockIcon = icon

	return icon
end

-- Overlay only while free; lock icon whenever Better Reputation Bar is on.
function ACAB:ApplyRepBarEditVisual(show)
	local frame = getglobal(self.REP_BAR_FRAME_NAME)
	if not frame or not frame.ACABOverlay then return end

	local enabled = ACABDB.repBarEnabled ~= false
	local free = ACABDB.betterRepBarEnabled and not self:IsRepBarFollowingExpBar()

	self:ApplyContainerOverlayVisual(frame, enabled, show and free)

	local icon = EnsureRepBarLockIcon(frame)

	icon:ClearAllPoints()
	icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
	icon:SetShown(show and ACABDB.betterRepBarEnabled and enabled)
	icon:SetLocked(not free)
end

-------------------------------------------------------------------------
-- Bar-fill color (StatusBar color; native repaints it with the standing color on every update)
-------------------------------------------------------------------------

-- True while the fill uses ACABDB.repBarColor instead of the standing color.
local function UsesCustomRepBarColor()
	return ACABDB ~= nil and ACABDB.betterRepBarEnabled == true and ACABDB.repBarUseStandingColor == false
		and ACABDB.repBarColor ~= nil
end

-- Replaces every color passed to SetStatusBarColor with ACABDB.repBarColor while UsesCustomRepBarColor().
local function InstallRepBarColorGuard(statusBar)
	if not statusBar or statusBar.ACABColorGuarded then return end

	local nativeSetColor = statusBar.SetStatusBarColor

	statusBar.SetStatusBarColor = function(self, r, g, b, a)
		local color = UsesCustomRepBarColor() and ACABDB.repBarColor

		if color then
			r, g, b = color.r, color.g, color.b
		end

		if a then
			return nativeSetColor(self, r, g, b, a)
		end

		return nativeSetColor(self, r, g, b)
	end

	statusBar.ACABColorGuarded = true
end

InstallRepBarColorGuard(getglobal(ACAB.REP_BAR_STATUS_FRAME_NAME))

-- Watched faction's native standing color, or nil without a watched faction.
function ACAB:GetRepBarStandingColor()
	local _, reaction = GetWatchedFactionInfo()
	local color = reaction and FACTION_BAR_COLORS[reaction]
	if not color then return nil end

	return { r = color.r, g = color.g, b = color.b }
end

-- Repaints the fill: the guard swaps in the custom color, else the standing color stays.
function ACAB:ApplyRepBarColors()
	local statusBar = getglobal(self.REP_BAR_STATUS_FRAME_NAME)
	local color = self:GetRepBarStandingColor()

	if statusBar and color then
		statusBar:SetStatusBarColor(color.r, color.g, color.b)
	end
end

-- Color-picker swatch setters (ColorPickerFrame.func/cancelFunc).
function ACAB:SetRepBarColor(r, g, b)
	self:EnsureDB()

	ACABDB.repBarColor = { r = r, g = g, b = b }

	self:ApplyRepBarColors()
end

function ACAB:SetRepBarTextColor(r, g, b)
	self:EnsureDB()

	ACABDB.repBarTextColor = { r = r, g = g, b = b }

	if self.betterRepBarText then
		self.betterRepBarText:SetTextColor(r, g, b)
	end
end

-- "Toggle current Standing Color" checkbox; turning it off starts the custom color at the current standing color.
function ACAB:SetRepBarUseStandingColor(enabled)
	self:EnsureDB()

	ACABDB.repBarUseStandingColor = enabled and true or false

	if not enabled and not ACABDB.repBarColor then
		ACABDB.repBarColor = self:GetRepBarStandingColor()
	end

	self:ApplyRepBarColors()
end

-- "Reset Colors to Default": standing colors back, text color back to REP_BAR_DEFAULT_TEXT_COLOR.
function ACAB:ResetRepBarColors()
	self:EnsureDB()

	local default = self.REP_BAR_DEFAULT_TEXT_COLOR

	ACABDB.repBarUseStandingColor = true
	ACABDB.repBarColor = nil
	self:SetRepBarTextColor(default.r, default.g, default.b)
	self:ApplyRepBarColors()
end

-------------------------------------------------------------------------
-- "Better Reputation Bar" text overlay: one FontString on a HIGH-strata child of the status bar
-------------------------------------------------------------------------

local function EnsureRepBarTextOverlay(statusBar)
	if statusBar.ACABTextOverlay then
		return statusBar.ACABTextOverlay
	end

	local overlay = CreateFrame("Frame", "ACABRepBarTextOverlay", statusBar)

	overlay:SetFrameStrata("HIGH")
	overlay:SetAllPoints(statusBar)

	statusBar.ACABTextOverlay = overlay

	return overlay
end

-- Joins the enabled segments ("Stormwind", "Friendly", "1200/6000", "20%") with spaces.
local function ComputeBetterRepBarText()
	local name, reaction, minValue, maxValue, value = GetWatchedFactionInfo()
	if not name then return "" end

	local total = maxValue - minValue
	local current = value - minValue

	local segments = {}
	local n = 0

	if ACABDB.repBarShowName then
		n = n + 1
		segments[n] = name
	end

	if ACABDB.repBarShowStanding then
		n = n + 1
		segments[n] = getglobal("FACTION_STANDING_LABEL" .. tostring(reaction)) or ""
	end

	if ACABDB.repBarShowValues then
		n = n + 1
		segments[n] = tostring(current) .. "/" .. tostring(total)
	end

	if ACABDB.repBarShowPercent then
		local pct = 0

		if total > 0 then
			pct = math.floor(((current / total) * 100) + 0.5)
		end

		n = n + 1
		segments[n] = tostring(pct) .. "%"
	end

	return table.concat(segments, " ")
end

function ACAB:UpdateBetterRepBarText()
	if self.betterRepBarText then
		self.betterRepBarText:SetText(ComputeBetterRepBarText())
	end
end

-- Native text's real Show method, captured once before it gets neutered; restored when the feature is off.
local realRepTextShow

-- Creates (once)/shows/hides the text overlay per ACABDB.betterRepBarEnabled, swapping the native hover label.
function ACAB:ApplyBetterRepBarVisual()
	self:EnsureDB()

	local statusBar = getglobal(self.REP_BAR_STATUS_FRAME_NAME)
	if not statusBar then return end

	local nativeText = getglobal(self.REP_BAR_NATIVE_TEXT_NAME)

	-- Must capture the real Show before it is ever neutered below.
	if nativeText and not realRepTextShow then
		realRepTextShow = nativeText.Show
	end

	if not ACABDB.betterRepBarEnabled then
		if self.betterRepBarText then
			self.betterRepBarText:Hide()
		end

		-- Native shows it again on hover.
		if nativeText and realRepTextShow then
			nativeText.Show = realRepTextShow
		end

		self:ApplyRepBarColors()
		return
	end

	if nativeText then
		-- Neuters Show - native hover code re-shows this label.
		nativeText.Show = function() end
		nativeText:Hide()
	end

	if not self.betterRepBarText then
		local text = EnsureRepBarTextOverlay(statusBar):CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")

		text:SetPoint("CENTER", statusBar.ACABTextOverlay, "CENTER", 0, 0)

		self.repBarFontPath = text:GetFont()
		self.betterRepBarText = text

		self:SetRepBarFontSize(ACABDB.repBarFontSize or self.REP_BAR_DEFAULT_FONT_SIZE)

		local textColor = ACABDB.repBarTextColor or self.REP_BAR_DEFAULT_TEXT_COLOR

		text:SetTextColor(textColor.r, textColor.g, textColor.b)
	end

	self.betterRepBarText:Show()
	self:UpdateBetterRepBarText()
	self:ApplyRepBarColors()
end

-- Font Size slider: rounds (GetFont sizes come back as floats) and applies, always OUTLINE.
function ACAB:SetRepBarFontSize(size)
	self:EnsureDB()

	size = math.floor(size + 0.5)

	ACABDB.repBarFontSize = size

	if self.betterRepBarText and self.repBarFontPath then
		self.betterRepBarText:SetFont(self.repBarFontPath, size, "OUTLINE")
	end
end

-- "Enable Better Reputation Bar" checkbox.
function ACAB:SetBetterRepBarEnabled(enabled)
	self:EnsureDB()

	ACABDB.betterRepBarEnabled = enabled and true or false

	self:ApplyBetterRepBarVisual()
	self:ApplyRepBarPosition()
	self:ApplyRepBarEditVisual(self:CanDragDefaultLayout())
end

-------------------------------------------------------------------------
-- Login + native update hook
-------------------------------------------------------------------------

-- Login stage: reparents to UIParent (off MainMenuBar), re-runs the native layout and places/styles the bar.
function ACAB:SetupRepBar()
	local frame = getglobal(self.REP_BAR_FRAME_NAME)
	if not frame then return end

	frame:SetParent(UIParent)

	self.repBarReady = true
	self.expBarLayoutLevel = UnitLevel("player")

	-- Native layout: shows the bar if a faction is watched, picks the max-level look, shows/hides the Exp Bar.
	if ACABDB.repBarEnabled ~= false then
		ReputationWatchBar_Update()
	else
		self:SetElementShown(frame, false)
	end

	self:ApplyRepBarPosition()
	self:ApplyBetterRepBarVisual()
end

-- Native re-layout (watched faction change, standing change, level up): re-place and refresh text.
hooksecurefunc("ReputationWatchBar_Update", function(newLevel)
	if not ACAB.loginSequenceDone then return end

	ACAB.expBarLayoutLevel = newLevel or UnitLevel("player")

	ACAB:ApplyRepBarPosition()
	ACAB:UpdateBetterRepBarText()
	ACAB:ApplyRepBarColors()
	ACAB:ApplyRepBarEditVisual(ACAB:CanDragDefaultLayout())
end)
