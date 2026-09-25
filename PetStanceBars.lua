-- PetStanceBars.lua
-- Pet Bar and Stance Bar in native mode, on DefaultBars.lua's chain-anchored container engine (must load after it).
-- Kept in one file since they cross-call each other's Reflow*ForBar*Toggle functions.

local ACAB = AlternativeClassicActionBars

-------------------------------------------------------------------------
-- Local helpers shared by both bars
-------------------------------------------------------------------------

-- Top-edge Y over bar stackBarId (+ Extra Bar pitch) if enabled, else bar 1: ref + gap + container height.
local function GetStackedBaselineY(self, stackBarId, stackBarEnabled, extraBarId, container)
	local defaults = ACABDB and ACABDB.defaultBars
	local cfg1 = defaults and defaults[1]
	local stackCfg = defaults and defaults[stackBarId]

	local referenceY = cfg1 and cfg1.nativeAnchor and cfg1.nativeAnchor.y

	if stackBarEnabled and stackCfg and stackCfg.nativeAnchor then
		referenceY = stackCfg.nativeAnchor.y

		-- The Extra Bar sits above the stack bar - stack above it too when both are enabled.
		referenceY = referenceY + self:GetExtraBarStackPitch(extraBarId)
	end

	if not referenceY then
		return nil
	end

	if not container then
		return nil
	end

	return referenceY + self.PET_BAR_NATIVE_GAP + container:GetHeight()
end

-- Writes cfg.hoverOnly on default bar barId's saved cfg, then re-runs applyFn.
local function SetBarCfgHoverOnly(self, barId, enabled, applyFn)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[barId]

	if not cfg then
		return
	end

	cfg.hoverOnly = enabled and true or false

	applyFn(self)
end

-- Clamps and writes cfg.hoverDuration on default bar barId's saved cfg, then re-runs applyFn.
local function SetBarCfgHoverDuration(self, barId, duration, applyFn)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[barId]

	duration = self:ClampHoverDuration(duration)

	if not cfg or not duration then
		return
	end

	cfg.hoverDuration = duration

	applyFn(self)
end

-------------------------------------------------------------------------
-- Pet Bar, native mode (the real PetActionButton1-10 in a synthetic container)
-- Position/spacing live on ACABDB.defaultBars[PET_BAR_ID], shared with styled mode; only cfg.scale is native-only.
-------------------------------------------------------------------------

-- Fixed clearance above the topmost default bar (PetActionBarFrame's own GetBottom() is unreliable).
ACAB.PET_BAR_NATIVE_GAP = 14

-- Pet Bar's stacked top-edge Y: above Bar 3 (+ Extra Bar 2) if bar 3 is enabled, else above bar 1.
function ACAB:GetPetBarBaselineY(bar3Enabled)
	return GetStackedBaselineY(self, 3, bar3Enabled, self.EXTRA_BAR_ID_START + 1, self.petBarNativeContainer)
end

-- Re-stacks Pet Bar's Y off Bar 3's state (Default Layout only). No-op once cfg.usesDefaultPosition is false.
function ACAB:ReflowPetBarForBar3Toggle(bar3Enabled)
	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]
	local container = self.petBarNativeContainer

	if not cfg or not container or cfg.usesDefaultPosition == false then
		return
	end

	local y = self:GetPetBarBaselineY(bar3Enabled)

	if not y then
		return
	end

	-- y is a top edge - write it in TOPLEFT/BOTTOMLEFT terms, ApplyPetBarNativePosition converts back.
	self:ConvertPositionAnchor(container, cfg, "TOPLEFT", "BOTTOMLEFT", nil, nil, "TOPLEFT")

	cfg.y = y

	if cfg.nativeAnchor then
		cfg.nativeAnchor.y = y
	end

	self:ApplyPetBarNativePosition()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(self.PET_BAR_ID)
	end
end

function ACAB:CreatePetBarNativeContainer()
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg or not self:IsPetBarNativeModeEffective() or self.petBarNativeContainer then
		return
	end

	local buttons = self:GetDefaultBarButtons(self.PET_BAR_ID)

	if not buttons then
		return
	end

	self:SortButtonsByNativeLeft(buttons)

	local container = self:BuildChainAnchoredContainer("ACABPetBarNativeContainer", buttons)

	self.petBarNativeContainer = container
	self.petBarNativeButtons = buttons

	self:ApplyPetBarNativeShape()
	self:ApplyPetBarNativePosition()
	self:SetDefaultBarEnabled(self.PET_BAR_ID, cfg.enabled)
end

-- Same cfg (and legacy TOPLEFT relativePoint default) as styled mode's ApplyBarPosition.
function ACAB:ApplyPetBarNativePosition()
	local cfg = ACABDB and ACABDB.defaultBars and ACABDB.defaultBars[self.PET_BAR_ID]
	local container = self.petBarNativeContainer

	if not cfg or not container then
		return
	end

	self:ApplyPositionToFrame(container, cfg, "TOPLEFT")

	self:EnsureContainerOverlay(container, self.StartPetBarNativeDrag, self.StopPetBarNativeDrag, self.PET_BAR_ID, self.SetPetBarNativeScale, nil, "Pet Bar", not self:ShouldCondensePetBarSlots())

	-- Hover settings shared with styled mode's cfg.
	self:ApplyHoverOnlyState(container, cfg.hoverOnly, function() return cfg.hoverDuration or 3 end)
end

function ACAB:SetPetBarNativePosition(x, y)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	x = tonumber(x)
	y = tonumber(y)

	if not cfg or not x or not y then
		return
	end

	cfg.x = x
	cfg.y = y

	-- Manually positioned - stop auto-stacking its Y.
	cfg.usesDefaultPosition = false

	self:ApplyPetBarNativePosition()
end

-- Re-lays-out the real pet buttons from cfg.spacing/cfg.scale (always horizontal).
function ACAB:ApplyPetBarNativeShape()
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg then
		return
	end

	self:ApplyChainAnchoredShape(
		self.petBarNativeContainer,
		cfg.spacing or 0,
		false,
		cfg.scale or 1,
		not self:ShouldCondensePetBarSlots()
	)
end

-- Writes the same cfg.spacing styled mode uses.
function ACAB:SetPetBarNativeSpacing(spacing)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	spacing = self:ClampSpacingSetting(spacing, 0, 20)

	if not cfg or not spacing then
		return
	end

	cfg.spacing = spacing

	self:ApplyPetBarNativeShape()
end

function ACAB:SetPetBarNativeScale(scale)
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	scale = self:ClampScaleSetting(scale)

	if not cfg or not scale then
		return
	end

	local oldScale = cfg.scale or 1

	if self.petBarNativeContainer then
		self:CompensateScaleKeepingCornerFixed(cfg, oldScale, scale, "CENTER", self.petBarNativeContainer:GetWidth(), self.petBarNativeContainer:GetHeight())
	end

	cfg.scale = scale

	self:ApplyPetBarNativeShape()
	self:ApplyPetBarNativePosition()
end

function ACAB:SetPetBarNativeHoverOnly(enabled)
	SetBarCfgHoverOnly(self, self.PET_BAR_ID, enabled, self.ApplyPetBarNativePosition)
end

function ACAB:SetPetBarNativeHoverDuration(duration)
	SetBarCfgHoverDuration(self, self.PET_BAR_ID, duration, self.ApplyPetBarNativePosition)
end

-- Restores the native position (on the computed stack baseline), native spacing and scale 1.
function ACAB:ResetPetBarNativeLayout()
	self:EnsureDB()

	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg or not cfg.nativeAnchor then
		return
	end

	cfg.point = cfg.nativeAnchor.point
	cfg.relativePoint = cfg.nativeAnchor.relativePoint
	cfg.x = cfg.nativeAnchor.x
	cfg.y = cfg.nativeAnchor.y

	-- Computed baseline wins over the captured nativeAnchor, which can be stale.
	local bar3Cfg = ACABDB.defaultBars[3]
	local computedY = self:GetPetBarBaselineY(bar3Cfg and bar3Cfg.enabled)

	if computedY then
		cfg.y = computedY
	end

	if cfg.nativeSpacing then
		cfg.spacing = cfg.nativeSpacing
	end

	cfg.scale = 1

	cfg.usesDefaultPosition = true

	-- Shape first: the canonical position conversion reads the container's final size/scale.
	self:ApplyPetBarNativeShape()
	self:ApplyPetBarNativePosition()
end

-- Modern Layout: Pet Bar flush on Action Bar 2's (bar 3's) real top edge, right edges aligned (native or styled mode).
function ACAB:ResetPetBarLayoutToModernBase()
	self:EnsureDB()

	local bar3 = self.bars and self.bars[3]

	if not bar3 then
		return
	end

	local _, bar3Right, bar3Top = self:GetElementRealEdges(bar3)

	if not bar3Right then
		return
	end

	if self:IsPetBarNativeModeEffective() then
		local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

		-- Built on demand - this session may have booted in styled mode.
		self:CreatePetBarNativeContainer()

		local container = self.petBarNativeContainer

		if not cfg or not container then
			return
		end

		-- Scale must settle before positioning - PixelSetPoint reads the live effective scale.
		cfg.scale = self:GetModernPetStanceScale()

		-- Same default spacing Reset to Vanilla Layout restores.
		if cfg.nativeSpacing then
			cfg.spacing = cfg.nativeSpacing
		end

		self:ApplyPetBarNativeShape()

		local containerLeft, containerRight = self:GetElementRealEdges(container)
		local containerWidth = (containerLeft and containerRight and (containerRight - containerLeft)) or container:GetWidth() or 0
		local _, _, _, insetBottom = self:GetElementVisualInset(container)

		cfg.point = "BOTTOMLEFT"
		cfg.relativePoint = "BOTTOMLEFT"
		cfg.x = self:ConvertUIParentOffsetToOwnScale(container, bar3Right - containerWidth)
		cfg.y = self:ConvertUIParentOffsetToOwnScale(container, bar3Top + insetBottom)

		cfg.usesDefaultPosition = false

		self:ApplyPetBarNativePosition()
		return
	end

	-- Styled mode: a regular pool bar sized via cfg.buttonSize, built on demand (first login boots native).
	self:EnsureFixedSlotBarCreated(self.PET_BAR_ID)

	local petBar = self.bars[self.PET_BAR_ID]

	if not petBar then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local cfg = petBar.config

	cfg.buttonSize = buttonSize
	cfg.spacing = spacing
	cfg.cols = 10
	cfg.rows = 1
	cfg.buttonCount = 10

	local barWidth = (buttonSize * 10) + (spacing * 9)
	local _, insetRight, _, insetBottom = self:GetElementVisualInset(petBar)

	cfg.point = "BOTTOMLEFT"
	cfg.relativePoint = "BOTTOMLEFT"
	cfg.x = bar3Right - insetRight - barWidth
	cfg.y = bar3Top + insetBottom

	self:ApplyBarPosition(petBar)
	self:SetBarLayout(petBar, cfg.cols, cfg.rows)
	self:SetBarButtonSize(petBar, buttonSize)
	self:ApplyBarShape(petBar)
	self:SetDefaultBarEnabled(self.PET_BAR_ID, true)
end

function ACAB:StartPetBarNativeDrag()
	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if not cfg then
		return
	end

	self:StartSharedDrag("petBarNative", nil, cfg.x or 0, cfg.y or 0)
end

function ACAB:StopPetBarNativeDrag()
	self:StopSharedDrag()

	-- Manually moved - stop auto-stacking its Y.
	local cfg = ACABDB.defaultBars[self.PET_BAR_ID]

	if cfg then
		cfg.usesDefaultPosition = false
	end

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(self.PET_BAR_ID)
	end
end

-------------------------------------------------------------------------
-- Stance Bar, native mode (the real ShapeshiftButtonN in a synthetic chain-anchored container)
-- Button count follows GetNumShapeshiftForms(); RebuildStanceBarContainer updates the chain in place.
-------------------------------------------------------------------------

-- Captures once the topmost default bar (1 or 2) to ShapeshiftBarFrame gap.
-- Must run before CreateFixedSlotDefaultBars, which hides bar 2's buttons and collapses that native anchor.
function ACAB:CaptureStanceBarNativeGap()
	if ACABDB.stanceBarNativeGap then
		return
	end

	local frame = ShapeshiftBarFrame

	if not frame then
		return
	end

	local bottom = frame:GetBottom()

	if not bottom then
		return
	end

	local frameScale = frame:GetEffectiveScale()
	local targetScale = UIParent:GetEffectiveScale()

	if not frameScale or not targetScale or targetScale == 0 then
		return
	end

	local screenBottom = (bottom * frameScale) / targetScale

	local defaults = ACABDB.defaultBars
	local cfg1 = defaults and defaults[1]
	local cfg2 = defaults and defaults[2]

	local referenceY = cfg1 and cfg1.nativeAnchor and cfg1.nativeAnchor.y

	if cfg2 and cfg2.enabled and cfg2.nativeAnchor then
		referenceY = cfg2.nativeAnchor.y
	end

	if not referenceY then
		return
	end

	local gap = screenBottom - referenceY

	-- Discards implausible reads (real gap is ~5) from a corrupted/unreflowed frame.
	if gap <= 0 or gap >= self.BUTTON_SIZE then
		self:Print(
			"WARNING: Stance Bar native gap capture produced an implausible " ..
			"value (" .. tostring(gap) .. ") and was discarded - falling back " ..
			"to a default clearance until a later capture succeeds."
		)
		return
	end

	ACABDB.stanceBarNativeGap = gap
end

-- Hides ShapeshiftBarFrame's leftover background art for good (vanilla's ShapeshiftBar_Update re-Shows it).
local function HideShapeshiftBarFrame()
	ACAB:NeuterFrameShow(ShapeshiftBarFrame)
end

-- Builds the container once stance/form buttons exist (no-op with 0 forms; RebuildStanceBarContainer retries).
function ACAB:CreateStanceBarContainer()
	self:EnsureDB()

	-- Styled mode drives the real buttons through Button.lua's pool - must not build over them.
	if not self:IsStanceBarNativeModeEffective() then
		return
	end

	if self.stanceBarContainer then
		return
	end

	local buttons = self:GetStanceBarButtons()

	if not buttons then
		return
	end

	-- Safety net; the real capture runs earlier in the login sequence.
	self:CaptureStanceBarNativeGap()

	self:SortButtonsByNativeLeft(buttons)

	local container, nativeLeft, nativeTop, nativeSpacing =
		self:BuildChainAnchoredContainer("ACABStanceBarContainer", buttons)

	self.stanceBarContainer = container
	self.stanceBarButtons = buttons

	self:SeedNativePosition("stanceBarNativeAnchor", "stanceBarPosition", nativeLeft, nativeTop)

	if not ACABDB.stanceBarNativeSpacing then
		ACABDB.stanceBarNativeSpacing = nativeSpacing
	end

	-- Through the setter, so the seed is rounded/clamped like a slider value.
	if not ACABDB.stanceBarSpacing then
		self:SetStanceBarSpacing(nativeSpacing)
	end

	self:ApplyStanceBarShape()
	self:ApplyStanceBarBorderStyle()

	self:ApplyStanceBarPosition()
	self:SetStanceBarEnabled(ACABDB.stanceBarEnabled ~= false)

	HideShapeshiftBarFrame()
end

-- On a form-set change: creates the container if missing, else updates its chain in place (keeping saved layout).
function ACAB:RebuildStanceBarContainer()
	self:EnsureDB()

	if not self:IsStanceBarNativeModeEffective() then
		return
	end

	HideShapeshiftBarFrame()

	local buttons = self:GetStanceBarButtons()

	if not buttons then
		-- Every form lost (e.g. respec): hide and empty the container, keep it for later.
		if self.stanceBarContainer then
			self.stanceBarContainer:Hide()
			self.stanceBarContainer.chainButtons = {}
			self.stanceBarContainer.chainWidths = {}
			self.stanceBarContainer.chainHeights = {}
		end

		return
	end

	local container = self.stanceBarContainer

	if not container then
		self:CreateStanceBarContainer()
		return
	end

	local widths, heights = {}, {}
	local i

	for i = 1, table.getn(buttons) do
		if buttons[i]:GetParent() ~= container then
			buttons[i]:SetParent(container)
		end

		widths[i] = buttons[i]:GetWidth() or 36
		heights[i] = buttons[i]:GetHeight() or 36
	end

	container.chainButtons = buttons
	container.chainWidths = widths
	container.chainHeights = heights

	self.stanceBarButtons = buttons

	self:ApplyStanceBarShape()
	self:ApplyStanceBarBorderStyle()

	if ACABDB.stanceBarEnabled ~= false then
		container:Show()
	end
end

-- Applies ACABDB.stanceBarPosition to the container and ensures its overlay and hover-only state.
function ACAB:ApplyStanceBarPosition()
	local pos = ACABDB.stanceBarPosition
	local container = self.stanceBarContainer

	if not pos or not container then
		return
	end

	self:ApplyPositionToFrame(container, pos, "BOTTOMLEFT")

	self:EnsureContainerOverlay(container, self.StartStanceBarDrag, self.StopStanceBarDrag, self.STANCE_BAR_ID, self.SetStanceBarScale, nil, "Stance Bar")

	-- Hover settings shared with styled mode's cfg.
	local cfg = ACABDB.defaultBars[self.STANCE_BAR_ID]

	if cfg then
		self:ApplyHoverOnlyState(container, cfg.hoverOnly, function() return cfg.hoverDuration or 3 end)
	end
end

function ACAB:SetStanceBarPosition(x, y)
	if not self:WriteSavedPositionXY("stanceBarPosition", x, y) then
		return
	end

	-- Manually positioned - stop auto-stacking its Y.
	ACABDB.stanceBarUsesDefaultPosition = false

	self:ApplyStanceBarPosition()
end

-- Restores the native (Vanilla Layout) position on the computed stack baseline.
function ACAB:ResetStanceBarPosition()
	local native = ACABDB.stanceBarNativeAnchor

	if not native then
		return
	end

	ACABDB.stanceBarPosition = self:CopyNativePosition(native)

	-- Computed baseline wins over the captured nativeAnchor, which can be stale.
	local bar2Cfg = ACABDB.defaultBars[2]
	local computedY = self:GetStanceBarBaselineY(bar2Cfg and bar2Cfg.enabled)

	if computedY then
		ACABDB.stanceBarPosition.y = computedY
	end

	ACABDB.stanceBarUsesDefaultPosition = true

	self:ApplyStanceBarPosition()
end

-- Modern Layout: native mode flush on Action Bar 2's (bar 3's) real top edge, left-aligned; else the styled reset.
function ACAB:ResetStanceBarPositionToModernBase()
	self:EnsureDB()

	if not self:IsStanceBarNativeModeEffective() then
		self:ResetStanceBarShapeToModernBase()
		return
	end

	-- Built on demand - this session may have booted in styled mode.
	self:CreateStanceBarContainer()

	local bar3 = self.bars and self.bars[3]
	local container = self.stanceBarContainer

	if not bar3 or not container then
		return
	end

	-- Scale must settle before positioning - PixelSetPoint reads the live effective scale.
	ACABDB.stanceBarScale = self:GetModernPetStanceScale()
	self:ApplyStanceBarShape()

	local bar3Left, _, bar3Top = self:GetElementRealEdges(bar3)

	if not bar3Left then
		return
	end

	local _, _, _, insetBottom = self:GetElementVisualInset(container)

	ACABDB.stanceBarPosition = {
		point = "BOTTOMLEFT",
		relativePoint = "BOTTOMLEFT",
		x = self:ConvertUIParentOffsetToOwnScale(container, bar3Left),
		y = self:ConvertUIParentOffsetToOwnScale(container, bar3Top + insetBottom),
	}

	ACABDB.stanceBarUsesDefaultPosition = false

	self:ApplyStanceBarPosition()
end

-- Styled-mode Modern Layout: a 1-column grid flush left of Main Bar, bottom edges aligned.
function ACAB:ResetStanceBarShapeToModernBase()
	self:EnsureDB()

	-- Built on demand (first login boots native).
	self:EnsureFixedSlotBarCreated(self.STANCE_BAR_ID)

	local mainBar = self.bars and self.bars[1]
	local stanceBar = self.bars and self.bars[self.STANCE_BAR_ID]

	if not mainBar or not stanceBar then
		return
	end

	local mainBarLeft, _, _, mainBarBottom = self:GetElementRealEdges(mainBar)

	if not mainBarLeft then
		return
	end

	local buttonSize, spacing = self:GetModernLayoutSizing()
	local cfg = stanceBar.config

	-- One row per live form; falls back to the saved row count (or 4).
	local rows = (GetNumShapeshiftForms and GetNumShapeshiftForms()) or 0

	if rows < 1 then
		rows = cfg.rows or 4
	end

	cfg.buttonSize = buttonSize
	cfg.spacing = spacing
	cfg.cols = 1
	cfg.rows = rows
	cfg.buttonCount = rows

	local _, insetRight, _, insetBottom = self:GetElementVisualInset(stanceBar)

	cfg.point = "BOTTOMLEFT"
	cfg.relativePoint = "BOTTOMLEFT"
	cfg.x = mainBarLeft - insetRight - buttonSize
	cfg.y = mainBarBottom + insetBottom

	self:ApplyBarPosition(stanceBar)
	self:SetBarLayout(stanceBar, cfg.cols, cfg.rows)
	self:SetBarButtonSize(stanceBar, buttonSize)
	self:ApplyBarShape(stanceBar)
end

-- The container's Show()/Hide() cascades to every real stance button.
function ACAB:SetStanceBarEnabled(enabled)
	self:EnsureDB()

	enabled = enabled and true or false

	ACABDB.stanceBarEnabled = enabled

	self:SetElementShown(self.stanceBarContainer, enabled)
end

-- Stance Bar's stacked top-edge Y: above Bar 2 (+ Extra Bar 1) if bar 2 is enabled, else above bar 1.
function ACAB:GetStanceBarBaselineY(bar2Enabled)
	return GetStackedBaselineY(self, 2, bar2Enabled, self.EXTRA_BAR_ID_START, self.stanceBarContainer)
end

-- Re-stacks Stance Bar's Y off Bar 2's state (Default Layout only). No-op once stanceBarUsesDefaultPosition is false.
function ACAB:ReflowStanceBarForBar2Toggle(bar2Enabled)
	if ACABDB.stanceBarUsesDefaultPosition == false then
		return
	end

	local pos = ACABDB.stanceBarPosition
	local container = self.stanceBarContainer

	if not pos or not container then
		return
	end

	local y = self:GetStanceBarBaselineY(bar2Enabled)

	if not y then
		return
	end

	-- y is a top edge - write it in TOPLEFT/BOTTOMLEFT terms, ApplyStanceBarPosition converts back.
	self:ConvertPositionAnchor(container, pos, "TOPLEFT", "BOTTOMLEFT", nil, nil, "BOTTOMLEFT")

	pos.y = y

	self:ApplyStanceBarPosition()

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(self.STANCE_BAR_ID)
	end
end

-- Re-lays-out the real stance buttons from saved spacing/orientation/scale. No-op until the container exists.
function ACAB:ApplyStanceBarShape()
	self:EnsureDB()

	self:ApplyChainAnchoredShape(
		self.stanceBarContainer,
		ACABDB.stanceBarSpacing or 0,
		ACABDB.stanceBarOrientation == true,
		ACABDB.stanceBarScale or 1
	)
end

-- Applies the global border style to the real stance buttons (modern: no NormalTexture, dark backdrop, inset icon).
function ACAB:ApplyStanceBarBorderStyle()
	local buttons = self.stanceBarButtons

	if not buttons then
		return
	end

	local vanilla = self:IsVanillaBorderStyle()
	local i

	for i = 1, table.getn(buttons) do
		local btn = buttons[i]

		if btn then
			local name = btn:GetName()
			local icon = name and getglobal(name .. "Icon")
			local normalTex = btn:GetNormalTexture()

			if vanilla then
				if normalTex then
					normalTex:Show()
				end

				if icon then
					icon:ClearAllPoints()
					icon:SetAllPoints(btn)
				end

				if btn.ACABModernBackdrop then
					btn.ACABModernBackdrop:Hide()
				end
			else
				if normalTex then
					normalTex:Hide()
				end

				if icon then
					icon:ClearAllPoints()
					icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
					icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
				end

				-- Must be a separate lower-level frame: btn:SetBackdrop() renders above the icon and greys it out.
				if not btn.ACABModernBackdrop then
					local backdrop = CreateFrame("Frame", nil, btn:GetParent())

					backdrop:SetFrameStrata(btn:GetFrameStrata())
					backdrop:SetFrameLevel(math.max((btn:GetFrameLevel() or 1) - 1, 0))
					backdrop:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
					backdrop:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 0, 0)
					backdrop:SetBackdrop({
						bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
						edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
						tile = true,
						tileSize = 8,
						edgeSize = 8,
						insets = { left = 1, right = 1, top = 1, bottom = 1 },
					})
					backdrop:SetBackdropColor(0, 0, 0, 0.75)
					backdrop:SetBackdropBorderColor(1, 1, 1, 1)

					btn.ACABModernBackdrop = backdrop
				end

				btn.ACABModernBackdrop:Show()
			end
		end
	end
end

-- Plain 0-20 range in both border styles.
function ACAB:SetStanceBarSpacing(spacing)
	self:EnsureDB()

	spacing = self:ClampSpacingSetting(spacing, 0, 20)

	if not spacing then
		return
	end

	ACABDB.stanceBarSpacing = spacing

	self:ApplyStanceBarShape()
end

function ACAB:SetStanceBarScale(scale)
	local pos

	scale, pos = self:StoreCompensatedScale("stanceBarScale", "stanceBarPosition", self.stanceBarContainer, scale)

	if not scale then
		return
	end

	self:ApplyStanceBarShape()

	if pos then
		self:ApplyStanceBarPosition()
	end
end

function ACAB:SetStanceBarNativeHoverOnly(enabled)
	SetBarCfgHoverOnly(self, self.STANCE_BAR_ID, enabled, self.ApplyStanceBarPosition)
end

function ACAB:SetStanceBarNativeHoverDuration(duration)
	SetBarCfgHoverDuration(self, self.STANCE_BAR_ID, duration, self.ApplyStanceBarPosition)
end

-- Restores spacing/scale/orientation to their native baseline (position: ResetStanceBarPosition).
function ACAB:ResetStanceBarLayout()
	self:EnsureDB()

	self:SetStanceBarSpacing(ACABDB.stanceBarNativeSpacing or 0)
	ACABDB.stanceBarScale = 1
	ACABDB.stanceBarOrientation = false

	self:ApplyStanceBarShape()
end

function ACAB:StartStanceBarDrag()
	local pos = ACABDB.stanceBarPosition

	if not pos then
		return
	end

	self:StartSharedDrag("stanceBar", nil, pos.x or 0, pos.y or 0)
end

function ACAB:StopStanceBarDrag()
	self:StopSharedDrag()

	-- Manually moved - stop auto-stacking its Y.
	ACABDB.stanceBarUsesDefaultPosition = false

	if self.RefreshBarSettingsPage then
		self:RefreshBarSettingsPage(self.STANCE_BAR_ID)
	end
end

-------------------------------------------------------------------------
-- Stance bar buttons
-------------------------------------------------------------------------

-- The first GetNumShapeshiftForms() ShapeshiftButtonN frames (not IsShown(): unreliable early), capped, or nil.
function ACAB:GetStanceBarButtons()
	local count = self:GetClampedLiveStanceCount()

	if count <= 0 then
		return nil
	end

	local buttons = {}
	local i

	for i = 1, count do
		local frame = getglobal("ShapeshiftButton" .. tostring(i))

		if not frame then
			-- Stops at the first missing frame.
			break
		end

		buttons[i] = frame
	end

	if table.getn(buttons) == 0 then
		return nil
	end

	return buttons
end

