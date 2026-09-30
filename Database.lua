-- Database.lua
-- SavedVariable lifecycle: native-anchor/spacing/action-slot capture, default- and extra-bar seeding,
-- ACAB:EnsureDB (migration-safe defaults), and the profile system (create/delete/copy/export/import).

local ACAB = AlternativeClassicActionBars

-- Bumping this reseeds ACABDB.defaultBars and wipes ACABDB.bars (see EnsureDB).
ACAB.SCHEMA_VERSION = 8

-- EnsureDB resets hoverBindMode once per session (login/reload), not per call.
local hasResetHoverBindModeThisSession = false

-- Returns a fresh { 1, 2, ..., count } identity slot map.
local function IdentitySlots(count)
	local slots = {}
	local i

	for i = 1, count do
		slots[i] = i
	end

	return slots
end

-- Captures a default bar's on-screen position from its first real Blizzard button, as a UIParent-relative
-- TOPLEFT/BOTTOMLEFT anchor.
function ACAB:CaptureNativeAnchor(id)
	local buttons = self.GetDefaultBarButtons and self:GetDefaultBarButtons(id)

	if not buttons then
		return nil
	end

	local first = buttons[1]

	if not first then
		return nil
	end

	local left = first:GetLeft()
	local top = first:GetTop()

	if not left or not top then
		return nil
	end

	local buttonScale = first:GetEffectiveScale()
	local targetScale = UIParent:GetEffectiveScale()

	if not buttonScale or not targetScale or targetScale == 0 then
		return nil
	end

	local screenX = left * buttonScale
	local screenY = top * buttonScale

	return {
		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = screenX / targetScale,
		y = screenY / targetScale,
	}
end

-- Captures the native gap between adjacent buttons on default bar `id`, rounded to the nearest pixel.
local function CaptureNativeSpacing(self, id, grid)
	local buttons = self.GetDefaultBarButtons and self:GetDefaultBarButtons(id)

	if not buttons then
		return nil
	end

	local horizontal = (grid.cols or 1) > (grid.rows or 1)

	local positions = {}
	local i

	for i = 1, table.getn(buttons) do
		local btn = buttons[i]

		if not btn then
			break
		end

		local pos = horizontal and btn:GetLeft() or btn:GetBottom()

		if not pos then
			return nil
		end

		positions[i] = pos
	end

	local count = table.getn(positions)

	if count < 2 then
		return nil
	end

	local size = horizontal and buttons[1]:GetWidth() or buttons[1]:GetHeight()
	size = size or self.BUTTON_SIZE

	local gaps = {}
	local n

	for n = 1, count - 1 do
		local delta = positions[n + 1] - positions[n]

		if delta < 0 then
			delta = -delta
		end

		gaps[n] = delta - size
	end

	-- Bucket gaps within 0.5px of each other, take the majority bucket.
	local buckets = {}
	local gi

	for gi = 1, table.getn(gaps) do
		local g = gaps[gi]
		local matched = false
		local bi

		for bi = 1, table.getn(buckets) do
			local b = buckets[bi]
			local diff = g - b.value

			if diff < 0 then
				diff = -diff
			end

			if diff <= 0.5 then
				b.count = b.count + 1
				matched = true
				break
			end
		end

		if not matched then
			table.insert(buckets, { value = g, count = 1 })
		end
	end

	local majority = buckets[1]
	local bi

	for bi = 2, table.getn(buckets) do
		if buckets[bi].count > majority.count then
			majority = buckets[bi]
		end
	end

	-- Convert from the native button family's scale to the bar frame's scale (== UIParent's).
	local buttonScale = buttons[1]:GetEffectiveScale()
	local targetScale = UIParent:GetEffectiveScale()

	if buttonScale and targetScale and targetScale ~= 0 then
		majority.value = (majority.value * buttonScale) / targetScale
	end

	local spacing = math.floor(majority.value + 0.5)

	if spacing < 0 then
		spacing = 0
	end

	return spacing
end

-- Fixed multibar slot offsets, used when a button's btn.action is missing.
local FIXED_SLOT_FALLBACK_OFFSET = {
	[2] = 60, -- MultiBarBottomLeft
	[3] = 48, -- MultiBarBottomRight
	[4] = 12, -- MultiBarRight
	[5] = 24, -- MultiBarLeft
}

-- Discovers default bar `id`'s (2-5) 12 real action slots from its live buttons. Returns slots, usedFallback.
local function CaptureFixedActionSlots(self, id)
	local buttons = self.GetDefaultBarButtons and self:GetDefaultBarButtons(id)

	if not buttons then
		return nil
	end

	local slots = {}
	local usedFallback = false
	local i

	for i = 1, table.getn(buttons) do
		local btn = buttons[i]

		if not btn then
			return nil
		end

		local slot = btn.action

		if not slot then
			local offset = FIXED_SLOT_FALLBACK_OFFSET[id]

			if offset then
				slot = offset + i
				usedFallback = true
			end
		end

		if not slot then
			return nil
		end

		slots[i] = slot
	end

	return slots, usedFallback
end

-- Used only when CaptureNativeAnchor can't read a real Blizzard button this session.
local FALLBACK_ANCHOR = {
	[1] = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 0 },
	[2] = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 42 },
	[3] = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 84 },
	[4] = { point = "RIGHT", relativePoint = "RIGHT", x = -18, y = 0 },
	[5] = { point = "RIGHT", relativePoint = "RIGHT", x = -58, y = 0 },
	[ACAB.PET_BAR_ID] = { point = "BOTTOM", relativePoint = "BOTTOM", x = -200, y = 130 },
	[ACAB.STANCE_BAR_ID] = { point = "BOTTOM", relativePoint = "BOTTOM", x = 0, y = 90 },
}

-- Builds one default-bar-family id's fresh saved config, capturing its real native anchor/spacing/action-slots.
local function SeedOneDefaultBar(self, id)
	local grid = self.DEFAULT_BAR_GRID[id]
	local anchor = self:CaptureNativeAnchor(id) or FALLBACK_ANCHOR[id]
	local spacing = CaptureNativeSpacing(self, id, grid) or 0

	local cfg = {
		id = id,

		-- Must not read ACAB.SHOW_MULTI_ACTIONBAR_GLOBAL - it doesn't survive a logout on this client.
		enabled = grid.enabled,
		point = anchor.point,
		relativePoint = anchor.relativePoint,
		x = anchor.x,
		y = anchor.y,
		cols = grid.cols,
		rows = grid.rows,
		buttonSize = self:GetCurrentButtonSizeBaseline(),
		spacing = spacing,
		buttonCount = grid.cols * grid.rows,

		-- Permanent pristine snapshot for "Reset to Vanilla Layout".
		nativeAnchor = {
			point = anchor.point,
			relativePoint = anchor.relativePoint,
			x = anchor.x,
			y = anchor.y,
		},
		nativeSpacing = spacing,
	}

	-- Bars 1-5 resolve action slots dynamically via GetDefaultBarSlotForIndex.
	if id >= 1 and id <= 5 then
		cfg.dynamicDefaultBar = true
	end

	if id >= 2 and id <= 5 then
		local fixedActionSlots, usedFallback = CaptureFixedActionSlots(self, id)

		if fixedActionSlots then
			cfg.fixedActionSlots = fixedActionSlots

			if usedFallback then
				self:Print(
					"WARNING: Default bar " .. tostring(id) ..
					" fixed action slots used FALLBACK offsets - " ..
					"button.action was missing, please verify live."
				)
			end
		else
			self:Print(
				"WARNING: Default bar " .. tostring(id) ..
				" could not discover its real action slots this session " ..
				"- it will keep using the old native-Blizzard-frame layout " ..
				"until this succeeds on a later login."
			)
		end
	end

	-- Pet Bar: pool index N drives pet slot N (1-10).
	if id == self.PET_BAR_ID then
		cfg.isPetBar = true
		cfg.fixedActionSlots = IdentitySlots(10)

		-- Default off: all 10 slots shown, blank where unassigned (vanilla look).
		cfg.condenseEmptyPetSlots = false
	end

	-- Stance Bar (styled mode): pool index N drives shapeshift form index N; buttonCount tracks the live form count.
	if id == self.STANCE_BAR_ID then
		cfg.isStanceBar = true
		cfg.fixedActionSlots = IdentitySlots(self.MAX_STANCE_BUTTONS)

		local liveCount = self:GetClampedLiveStanceCount()

		cfg.cols = liveCount > 0 and liveCount or 1
		cfg.rows = 1
		cfg.buttonCount = liveCount

		-- Native mode by default; styled mode is opt-in.
		cfg.useNativeStanceBar = true
	end

	return cfg
end

-- Builds a fresh ACABDB.defaultBars table for every default-bar-family id.
local function seedDefaultBars(self)
	local result = {}
	local i

	for i = 1, table.getn(self.DEFAULT_BAR_IDS) do
		local id = self.DEFAULT_BAR_IDS[i]

		result[id] = SeedOneDefaultBar(self, id)
	end

	return result
end

-- On-demand synchronous recapture of every default bar's native anchor/spacing; reapplies live if bars exist.
function ACAB:RecaptureDefaultBarNativeAnchors()
	self:EnsureDB()

	self:Print("Recapturing positions to align Bars with your Screen.")
	local fresh = seedDefaultBars(self)
	local i

	-- Must update each cfg in place (anchor/spacing/slots only) - self.bars[id].config holds the same table.
	for i = 1, table.getn(self.DEFAULT_BAR_IDS) do
		local id = self.DEFAULT_BAR_IDS[i]
		local oldCfg = ACABDB.defaultBars[id]
		local newCfg = fresh[id]

		-- Native-mode Pet/Stance Bar buttons live in our own container, so they'd only read back our position.
		local selfReferencing =
			(id == self.PET_BAR_ID and self.petBarNativeContainer) or
			(id == self.STANCE_BAR_ID and self.stanceBarContainer)

		if selfReferencing then
			-- Leave oldCfg's anchor/spacing untouched.
		elseif oldCfg and newCfg then
			oldCfg.point = newCfg.point
			oldCfg.relativePoint = newCfg.relativePoint
			oldCfg.x = newCfg.x
			oldCfg.y = newCfg.y
			oldCfg.spacing = newCfg.spacing
			oldCfg.nativeAnchor = newCfg.nativeAnchor
			oldCfg.nativeSpacing = newCfg.nativeSpacing

			if newCfg.fixedActionSlots then
				oldCfg.fixedActionSlots = newCfg.fixedActionSlots
			end
		elseif newCfg then
			-- No existing cfg for this id - the fresh table becomes the real one.
			ACABDB.defaultBars[id] = newCfg
		end
	end

	self:ReapplyAfterNativeRecapture()
end

-- Re-applies the default bars and everything derived from their native anchors (Pet Bar X, Extra Bars 1-4).
-- No-op until bars are built.
function ACAB:ReapplyAfterNativeRecapture()
	if not (self.bars and self.bars[1]) then
		return
	end

	local i

	self:ApplyAllDefaultBars()

	-- Re-derives Pet Bar's x/y from Bar 3/Bar 1's just-refreshed nativeAnchor.
	if self.SyncPetBarAnchorX then
		self:SyncPetBarAnchorX()
	end

	if self.petBarNativeContainer and ACABDB.useDefaultLayout ~= false then
		local bar3Cfg = ACABDB.defaultBars[3]
		self:ReflowPetBarForBar3Toggle(bar3Cfg and bar3Cfg.enabled)
	end

	-- Extra Bar 1-4's default layout is relative to a default bar's nativeAnchor.
	if self.ResetExtraBarLayout then
		for i = self.EXTRA_BAR_ID_START, self.EXTRA_BAR_ID_START + self.EXTRA_BAR_COUNT - 1 do
			self:ResetExtraBarLayout(i)
		end
	end

	self:Print("All Bars and UI-Elements applied to their correct position after recapture.")
end

-- Clears the stored native anchor + position of Key Ring/Latency Bar/Exp Bar/Cast Bar so the next reload
-- recaptures them.
function ACAB:RecaptureWrappedNativeFrameAnchors()
	self:EnsureDB()

	ACABDB.keyRingPosition = nil
	ACABDB.keyRingNativeAnchor = nil
	ACABDB.latencyBarPosition = nil
	ACABDB.latencyBarNativeAnchor = nil
	ACABDB.expBarPosition = nil
	ACABDB.expBarNativeAnchor = nil
	ACABDB.castBarPosition = nil
	ACABDB.castBarNativeAnchor = nil

	-- Must clear alongside castBarPosition above, or the stack-reflow floor stays stale.
	ACABDB.castBarStackBaseY = nil

	self:Print("Key Ring/Latency Bar/Exp Bar/Cast Bar native anchors cleared - /reload now to capture them fresh.")
end

-- Fallback Extra Bar position (stacked vertically by index) when the reference bar's native anchor is missing.
local function GetFallbackExtraBarPosition(self, index)
	return 20, 150 + (index * ((self.BUTTON_ROWS * self.BUTTON_SIZE) + 40))
end

-- Extra Bar default positions: pitchCount button pitches to `side` of a reference default bar's native
-- position. Keyed by index 0-3 (Extra Bar 1-4).
local EXTRA_BAR_DEFAULT_REFERENCE = {
	[0] = { refId = 2, side = "above", pitchCount = 1 }, -- Extra Bar 1: above Action Bar 1.
	[1] = { refId = 3, side = "above", pitchCount = 1 }, -- Extra Bar 2: above Action Bar 2.
	[2] = { refId = 5, side = "left",  pitchCount = 1 }, -- Extra Bar 3: left of Right Action Bar 2.
	[3] = { refId = 5, side = "left",  pitchCount = 2 }, -- Extra Bar 4: left of Right Action Bar 2 (double pitch, i.e. left of Extra Bar 3).
}

-- Extra Bar `index`'s default layout (seeding and ResetExtraBarLayout): the reference bar's size, spacing and grid,
-- one bar pitch (its frame plus its own button gap) above/left of it. Reads the built reference bar's current
-- config, else its Reset-to-Vanilla values. Returns TOPLEFT/BOTTOMLEFT x, y, cols, rows, buttonSize, spacing.
function ACAB:GetDefaultExtraBarLayout(index)
	local ref = EXTRA_BAR_DEFAULT_REFERENCE[index]
	local refCfg = ref and ACABDB.defaultBars and ACABDB.defaultBars[ref.refId]
	local grid = ref and self.DEFAULT_BAR_GRID[ref.refId]

	if not ref or not refCfg or not refCfg.nativeAnchor or not grid then
		local x, y = GetFallbackExtraBarPosition(self, index)
		return x, y, self.BUTTON_COLS, self.BUTTON_ROWS, self:GetCurrentButtonSizeBaseline(), 0
	end

	local refBar = self.bars and self.bars[ref.refId]
	local left, right, bottom, top

	if refBar and refBar.config == refCfg and refCfg.buttonSize then
		left, right, bottom, top = self:GetPositionFrameRect(refBar, refCfg, "TOPLEFT")
	end

	local buttonSize, spacing, cols, rows

	if left then
		buttonSize = refCfg.buttonSize
		spacing = refCfg.spacing or 0
		cols = refCfg.cols or grid.cols
		rows = refCfg.rows or grid.rows
	else
		-- Same values ResetDefaultBarLayout gives the reference bar (Modern style: corner shifted up-left).
		local shift = self:IsVanillaBorderStyle() and 0 or self.MODERN_BUTTON_SIZE_POSITION_SHIFT

		buttonSize = self:GetCurrentButtonSizeBaseline()
		spacing = self:GetDefaultBarNativeSpacing(refCfg)
		cols = grid.cols
		rows = grid.rows

		local width, height = self:GetBarFrameSize({ cols = cols, rows = rows, buttonCount = cols * rows, buttonSize = buttonSize, spacing = spacing })

		left = refCfg.nativeAnchor.x - shift
		top = refCfg.nativeAnchor.y + shift
		right = left + width
		bottom = top - height
	end

	local gap = self:GetBarEffectiveSpacing({ buttonSize = buttonSize, spacing = spacing })
	local x = left
	local y = top

	if ref.side == "above" then
		y = top + (((top - bottom) + gap) * ref.pitchCount)
	elseif ref.side == "left" then
		x = left - (((right - left) + gap) * ref.pitchCount)
	end

	return x, y, cols, rows, buttonSize, spacing
end

-- Extra Bar's live height plus its own button gap (the gap GetDefaultExtraBarLayout leaves below it), for
-- Stance/Pet/Cast Bar stacking. 0 if the bar is missing, disabled, or moved off its default position.
function ACAB:GetExtraBarStackPitch(extraBarId)
	local bar = self.bars and self.bars[extraBarId]

	if not bar or not bar.config or not bar.config.enabled
		or bar.config.usesDefaultPosition == false then
		return 0
	end

	return (bar:GetHeight() or 0) + self:GetBarEffectiveSpacing(bar.config)
end

-- Resettles Stance/Pet/Cast Bar when Extra Bar 1/2's stacking contribution changes (each Reflow* self-guards).
function ACAB:ReflowExtraBarDependants(extraBarId)
	local index = extraBarId - self.EXTRA_BAR_ID_START

	if index == 0 then
		local bar2Cfg = ACABDB.defaultBars[2]
		self:ReflowStanceBarForBar2Toggle(bar2Cfg and bar2Cfg.enabled)
	elseif index == 1 then
		local bar3Cfg = ACABDB.defaultBars[3]
		self:ReflowPetBarForBar3Toggle(bar3Cfg and bar3Cfg.enabled)
	end

	if self.ReflowCastBarForStackToggle then
		self:ReflowCastBarForStackToggle()
	end
end

-- Allocates one Extra Bar's config.
local function seedExtraBarConfig(self, id)
	local index = id - self.EXTRA_BAR_ID_START
	local x, y, cols, rows, buttonSize, spacing = self:GetDefaultExtraBarLayout(index)

	local needed = cols * rows
	local slotStart = self:GetNextFreeSlotStart(needed)

	if not slotStart then
		self:Print(
			"WARNING: Extra Bar " .. tostring(id - self.EXTRA_BAR_ID_START + 1) ..
			" could not be allocated a free action-slot block this session " ..
			"- the 48-slot free pool (73-120) is unexpectedly already full."
		)

		return nil
	end

	return {
		id = id,

		point = "TOPLEFT",
		relativePoint = "BOTTOMLEFT",
		x = x,
		y = y,

		cols = cols,
		rows = rows,

		buttonSize = buttonSize,

		slotStart = slotStart,
		buttonCount = cols * rows,

		spacing = spacing,

		enabled = false,
	}
end

-- Converts a legacy (non-canonical) CENTER-anchored Extra Bar to TOPLEFT/BOTTOMLEFT, keeping its on-screen position.
function ACAB:MigrateExtraBarAnchor(cfg)
	if not cfg or cfg.point ~= "CENTER" or self:IsCanonicalPosition(cfg) then
		return
	end

	local screenWidth = GetScreenWidth() or 1024
	local screenHeight = GetScreenHeight() or 768
	local cols = cfg.cols or self.BUTTON_COLS
	local rows = cfg.rows or self.BUTTON_ROWS
	local buttonSize = cfg.buttonSize or self:GetCurrentButtonSizeBaseline()
	local spacing = cfg.spacing or 0

	local barWidth = (cols * buttonSize) + ((cols - 1) * spacing)
	local barHeight = (rows * buttonSize) + ((rows - 1) * spacing)

	local centerX = (screenWidth / 2) + (cfg.x or 0)
	local centerY = (screenHeight / 2) + (cfg.y or 0)

	cfg.point = "TOPLEFT"
	cfg.relativePoint = "BOTTOMLEFT"
	cfg.x = centerX - (barWidth / 2)
	cfg.y = centerY + (barHeight / 2)
end

-- Ensures exactly ACAB.EXTRA_BAR_COUNT Extra Bar configs exist.
function ACAB:EnsureExtraBars()
	local id

	for id = self.EXTRA_BAR_ID_START, self.EXTRA_BAR_ID_START + self.EXTRA_BAR_COUNT - 1 do
		local found = false
		local i

		for i = 1, table.getn(ACABDB.bars) do
			if ACABDB.bars[i] and ACABDB.bars[i].id == id then
				found = true
				self:MigrateExtraBarAnchor(ACABDB.bars[i])
				break
			end
		end

		if not found then
			local cfg = seedExtraBarConfig(self, id)

			if cfg then
				table.insert(ACABDB.bars, cfg)
			end
		end
	end
end

-------------------------------------------------------------------------
-- Profiles
-- ACABDB = active profile's live data; ACABProfilesDB (account-wide) = every profile's data by name;
-- ACABCharDB (per-character) = which profile this character uses.
-------------------------------------------------------------------------

-- Built-in locked profiles: Default Vanilla (native layout) and Default Modern (Modern Layout baseline).
ACAB.DEFAULT_PROFILE_NAME = "Default Vanilla"
ACAB.MODERN_PROFILE_NAME = "Default Modern"

-- Default Vanilla's pre-rename name; migrated in ResolveActiveProfile and reserved afterwards.
ACAB.LEGACY_DEFAULT_PROFILE_NAME = "Default"

-- Reserved name: hidden from GetProfileNames and rejected by ProfileNameTaken.
ACAB.MODERN_BASE_PROFILE_NAME = "ModernBase"

-- True for the two built-in locked profiles.
function ACAB:IsBuiltInProfileName(name)
	return name == self.DEFAULT_PROFILE_NAME or name == self.MODERN_PROFILE_NAME
end

-- Plain recursive deep copy - ACABDB only ever holds plain data.
function ACAB:DeepCopyTable(t)
	if type(t) ~= "table" then
		return t
	end

	local copy = {}
	local k, v

	for k, v in pairs(t) do
		copy[k] = self:DeepCopyTable(v)
	end

	return copy
end

-- Sorted list of every saved profile name, the built-in profiles always first.
function ACAB:GetProfileNames()
	local names = {}
	local n = 0
	local name

	for name in pairs(ACABProfilesDB or {}) do
		if not self:IsBuiltInProfileName(name) and name ~= self.MODERN_BASE_PROFILE_NAME
			and name ~= self.LEGACY_DEFAULT_PROFILE_NAME then
			n = n + 1
			names[n] = name
		end
	end

	table.sort(names)

	local result = { self.DEFAULT_PROFILE_NAME }

	if ACABProfilesDB and ACABProfilesDB[self.MODERN_PROFILE_NAME] then
		table.insert(result, self.MODERN_PROFILE_NAME)
	end

	local i

	for i = 1, n do
		table.insert(result, names[i])
	end

	return result
end

-- First "<name> (Custom)" / "<name> (Custom N)" not yet used in ACABProfilesDB.
local function FreeCustomProfileName(name)
	local candidate = name .. " (Custom)"
	local n = 2

	while ACABProfilesDB[candidate] do
		candidate = name .. " (Custom " .. tostring(n) .. ")"
		n = n + 1
	end

	return candidate
end

-- Moves a user profile named like a built-in one out of the way.
local function MoveUserProfileOffBuiltInName(self, name)
	local newName = FreeCustomProfileName(name)

	ACABProfilesDB[newName] = ACABProfilesDB[name]
	ACABProfilesDB[name] = nil

	if ACABCharDB.activeProfile == name then
		ACABCharDB.activeProfile = newName
	end

	self:Print("Your profile \"" .. name .. "\" was renamed to \"" .. newName .. "\" - that name now belongs to a built-in profile.")
end

-- Renames the account's "Default" profile to Default Vanilla and this character's pointer to it; frees both
-- built-in names from user profiles.
local function MigrateBuiltInProfileNames(self)
	local legacy = self.LEGACY_DEFAULT_PROFILE_NAME

	if ACABProfilesDB[legacy] then
		if ACABProfilesDB[self.DEFAULT_PROFILE_NAME] then
			MoveUserProfileOffBuiltInName(self, self.DEFAULT_PROFILE_NAME)
		end

		ACABProfilesDB[self.DEFAULT_PROFILE_NAME] = ACABProfilesDB[legacy]
		ACABProfilesDB[legacy] = nil
	end

	local modernData = ACABProfilesDB[self.MODERN_PROFILE_NAME]

	if modernData and not modernData.builtInModernProfile then
		MoveUserProfileOffBuiltInName(self, self.MODERN_PROFILE_NAME)
	end

	if ACABCharDB.activeProfile == legacy then
		ACABCharDB.activeProfile = self.DEFAULT_PROFILE_NAME
	end
end

-- Writes the Modern Layout baseline flags onto profile data; the geometry itself is applied live on the next
-- login that loads it (ACAB:ApplyPendingLayoutBaseline).
function ACAB:ApplyModernBaselineFlags(data)
	data.useDefaultLayout = false
	data.pendingLayoutBaseline = "modern"
	data.vanillaLayoutStacking = nil

	-- Modern Layout's Bag Bar is flush.
	data.bagBarSpacing = 0

	data.modernBorderStyle = true

	-- must match modernBorderStyle, or the next login treats it as a live style switch and shifts every bar
	data.lastAppliedVanillaStyle = false

	data.mainBarArtMode = self.MAIN_BAR_ART_MODE_DISABLED
	data.snapToGrid = false
	data.snapToAdjacentElements = false

	data.globalSpacingEnabled = false
	data.globalSpacingValue = 0
	data.globalButtonSizeEnabled = false
	data.globalButtonSizeValue = self.BUTTON_SIZE

	data.expBarEnabled = true
	data.betterExpBarEnabled = true

	if data.defaultBars then
		local stanceCfg = data.defaultBars[self.STANCE_BAR_ID]
		local petCfg = data.defaultBars[self.PET_BAR_ID]

		if stanceCfg then
			stanceCfg.useNativeStanceBar = false
		end

		if petCfg then
			petCfg.useNativePetBar = false
			petCfg.condenseEmptyPetSlots = false
		end
	end
end

-- Default Vanilla's saved data; snapshots the live ACABDB first while Default Vanilla is active and unsaved.
-- Falls back to the live ACABDB, never an empty table (see CreateProfile).
function ACAB:GetDefaultVanillaData()
	ACABProfilesDB = ACABProfilesDB or {}

	-- Live data first while Default Vanilla is loaded: the snapshot misses this session's recapture.
	if self.activeProfileName == self.DEFAULT_PROFILE_NAME then
		self:EnsureDB()
		self:SaveActiveProfileData()
	end

	if ACABProfilesDB[self.DEFAULT_PROFILE_NAME] then
		return ACABProfilesDB[self.DEFAULT_PROFILE_NAME]
	end

	self:EnsureDB()

	return ACABDB
end

-- Fresh Default Modern data: Default Vanilla's saved data plus the Modern Layout baseline flags; nil while
-- Default Vanilla has no snapshot yet.
function ACAB:BuildModernBaseProfileData()
	local source = ACABProfilesDB and ACABProfilesDB[self.DEFAULT_PROFILE_NAME]

	if not source then
		return nil
	end

	local data = self:DeepCopyTable(source)

	self:ApplyModernBaselineFlags(data)
	data.builtInModernProfile = true

	return data
end

-- Builds Default Modern if it's still missing (a fresh install has no Default Vanilla snapshot at login).
function ACAB:EnsureModernBaseProfile()
	if ACABProfilesDB and ACABProfilesDB[self.MODERN_PROFILE_NAME] then
		return
	end

	self:GetDefaultVanillaData()

	local modernData = self:BuildModernBaseProfileData()

	if modernData then
		ACABProfilesDB[self.MODERN_PROFILE_NAME] = modernData
	end
end

-------------------------------------------------------------------------
-- Profile data sanitizing: drops wrong-typed fields so EnsureDB reseeds them (runs on saved profiles at login
-- and on imported data). Never touches one-shot flags.
-------------------------------------------------------------------------

local SANITIZE_LIMIT = 1e15

local SANITIZE_BOOLEAN_KEYS = {
	"editMode", "useDefaultLayout", "modernBorderStyle", "bypassRightActionBar2Dependency", "lastAppliedVanillaStyle",
	"globalSpacingEnabled", "globalButtonSizeEnabled", "defaultBarPaginationEnabled", "defaultBarStanceSwapEnabled",
	"mainBarPageIndicatorFollowsMainBar", "tintWholeButtonOnRange", "snapToAdjacentElements", "showLayoutGrid",
	"snapToGrid", "useCustomGridSize", "bagBarEnabled", "microMenuEnabled", "stanceBarEnabled", "keyRingEnabled",
	"latencyBarEnabled", "tooltipEnabled", "expBarEnabled", "stanceBarUsesDefaultPosition",
	"castBarUsesDefaultPosition", "bagBarHoverOnly", "microMenuHoverOnly", "latencyBarHoverOnly", "expBarHoverOnly",
	"keyRingHoverOnly", "betterExpBarEnabled", "expBarShowCurrentOverMax", "expBarShowPercent", "expBarShowLevel",
	"expBarShowRestedPercent", "expBarShowRestedTotal", "bagBarOrientation", "stanceBarOrientation", "showMacroText",
	"bagBarGroupUnlocked", "keyRingGroupUnlocked", "microMenuGroupUnlocked", "latencyBarGroupUnlocked",
	"pageIndicatorGroupUnlocked", "hoverBindMode", "vanillaLayoutStacking", "pendingDefaultBarRecapture",
	"pendingDisableExtraBars",
}

local SANITIZE_NUMBER_KEYS = {
	"minimapAngle", "globalSpacingValue", "globalButtonSizeValue", "keyRingHoverDuration",
	"bagBarHoverDuration", "microMenuHoverDuration", "latencyBarHoverDuration", "expBarHoverDuration",
	"expBarGlowPulseInterval", "microMenuCols", "microMenuRows", "stanceBarNativeGap",
	"bagBarSpacing", "bagBarNativeSpacing", "microMenuSpacing", "microMenuNativeSpacing", "stanceBarSpacing",
	"stanceBarNativeSpacing", "castBarStackBaseY",
}

-- Numbers that must stay above 0 (scales, font sizes, grid size).
local SANITIZE_SCALE_KEYS = {
	"mainBarPageIndicatorScale", "tooltipScale", "expBarScale", "latencyBarScale", "castBarScale", "keyRingScale",
	"bagBarScale", "microMenuScale", "stanceBarScale",
	"hotkeyFontSize", "countFontSize", "macroFontSize", "expBarFontSize", "customGridSize",
}

local SANITIZE_COLOR_KEYS = {
	"expBarTextColor", "expBarColorEarned", "expBarColorRested", "expBarNativeColorEarned", "expBarNativeColorRested",
}

-- Per-bar cfg fields outside position/grid/slot; a wrong type drops only that field.
local SANITIZE_BAR_BOOLEAN_KEYS = {
	"enabled", "usesDefaultPosition", "hoverOnly", "useNativeStanceBar", "useNativePetBar", "condenseEmptyPetSlots",
	"spacingUnlocked", "buttonSizeUnlocked", "animateAutoCastGlow", "dynamicDefaultBar", "isPetBar", "isStanceBar",
	"visualCenter",
}

local SANITIZE_BAR_NUMBER_KEYS = { "hoverDuration", "nativeSpacing" }

local SANITIZE_POSITION_KEYS = {
	"bagBarPosition", "microMenuPosition", "keyRingPosition", "latencyBarPosition", "castBarPosition",
	"expBarPosition", "tooltipPosition", "stanceBarPosition", "mainBarPageIndicatorPosition",
	"bagBarNativeAnchor", "microMenuNativeAnchor", "keyRingNativeAnchor", "latencyBarNativeAnchor",
	"castBarNativeAnchor", "expBarNativeAnchor", "stanceBarNativeAnchor", "mainBarPageIndicatorNativeAnchor",
}

local function IsFiniteNumber(v)
	return type(v) == "number" and v == v and v > -SANITIZE_LIMIT and v < SANITIZE_LIMIT
end

local function IsIntegerInRange(v, low, high)
	return IsFiniteNumber(v) and v == math.floor(v) and v >= low and v <= high
end

-- Position-style table: finite x/y, string anchors when present.
local function IsValidPositionTable(t)
	return type(t) == "table"
		and (t.x == nil or IsFiniteNumber(t.x))
		and (t.y == nil or IsFiniteNumber(t.y))
		and (t.point == nil or type(t.point) == "string")
		and (t.relativePoint == nil or type(t.relativePoint) == "string")
end

-- Bar cfg (default-bar family or custom bar): finite numeric fields, grid within MAX_BAR_BUTTONS, slot start in the pool.
local function IsValidBarConfig(self, cfg)
	if not IsValidPositionTable(cfg) then
		return false
	end

	if cfg.cols ~= nil and not IsIntegerInRange(cfg.cols, 1, self.MAX_BAR_BUTTONS) then return false end
	if cfg.rows ~= nil and not IsIntegerInRange(cfg.rows, 1, self.MAX_BAR_BUTTONS) then return false end

	if cfg.cols and cfg.rows and cfg.cols * cfg.rows > self.MAX_BAR_BUTTONS then
		return false
	end

	if cfg.buttonCount ~= nil and not IsIntegerInRange(cfg.buttonCount, 0, self.MAX_BAR_BUTTONS) then return false end
	if cfg.slotStart ~= nil and not IsIntegerInRange(cfg.slotStart, self.ACTION_SLOT_START, self.ACTION_SLOT_END) then return false end
	if cfg.buttonSize ~= nil and not (IsFiniteNumber(cfg.buttonSize) and cfg.buttonSize > 0) then return false end
	if cfg.spacing ~= nil and not IsFiniteNumber(cfg.spacing) then return false end
	if cfg.nativeAnchor ~= nil and not IsValidPositionTable(cfg.nativeAnchor) then return false end

	if cfg.fixedActionSlots ~= nil then
		if type(cfg.fixedActionSlots) ~= "table" then
			return false
		end

		local k, slot

		for k, slot in pairs(cfg.fixedActionSlots) do
			if not IsIntegerInRange(slot, 1, self.ACTION_SLOT_END) then
				return false
			end
		end
	end

	return true
end

local function IsValidColorTable(t)
	return type(t) == "table" and IsFiniteNumber(t.r) and IsFiniteNumber(t.g) and IsFiniteNumber(t.b)
end

-- Drops wrong-typed non-structural fields from one bar cfg; `label` prefixes the issue lines.
local function SanitizeBarExtras(cfg, label, issues)
	local i, key

	for i = 1, table.getn(SANITIZE_BAR_BOOLEAN_KEYS) do
		key = SANITIZE_BAR_BOOLEAN_KEYS[i]

		if cfg[key] ~= nil and type(cfg[key]) ~= "boolean" then
			cfg[key] = nil

			if issues then table.insert(issues, label .. "." .. key .. " must be true or false") end
		end
	end

	for i = 1, table.getn(SANITIZE_BAR_NUMBER_KEYS) do
		key = SANITIZE_BAR_NUMBER_KEYS[i]

		if cfg[key] ~= nil and not IsFiniteNumber(cfg[key]) then
			cfg[key] = nil

			if issues then table.insert(issues, label .. "." .. key .. " must be a number") end
		end
	end

	if cfg.scale ~= nil and not (IsFiniteNumber(cfg.scale) and cfg.scale > 0) then
		cfg.scale = nil

		if issues then table.insert(issues, label .. ".scale must be a number above 0") end
	end
end

-- Drops wrong-typed fields from one profile's data in place; structural damage falls back to EnsureDB reseeding.
-- Appends one "<field> <expectation>" line per dropped field to `issues` when given.
function ACAB:SanitizeProfileData(data, issues)
	local i, key

	local function Drop(field, expected)
		data[field] = nil

		if issues then
			table.insert(issues, field .. " " .. expected)
		end
	end

	if type(data.schemaVersion) ~= "number" then
		data.schemaVersion = self.SCHEMA_VERSION
	end

	for i = 1, table.getn(SANITIZE_BOOLEAN_KEYS) do
		key = SANITIZE_BOOLEAN_KEYS[i]

		if data[key] ~= nil and type(data[key]) ~= "boolean" then Drop(key, "must be true or false") end
	end

	for i = 1, table.getn(SANITIZE_NUMBER_KEYS) do
		key = SANITIZE_NUMBER_KEYS[i]

		if data[key] ~= nil and not IsFiniteNumber(data[key]) then Drop(key, "must be a number") end
	end

	for i = 1, table.getn(SANITIZE_SCALE_KEYS) do
		key = SANITIZE_SCALE_KEYS[i]

		if data[key] ~= nil and not (IsFiniteNumber(data[key]) and data[key] > 0) then
			Drop(key, "must be a number above 0")
		end
	end

	for i = 1, table.getn(SANITIZE_POSITION_KEYS) do
		key = SANITIZE_POSITION_KEYS[i]

		if data[key] ~= nil and not IsValidPositionTable(data[key]) then Drop(key, "must hold numeric x/y and text anchors") end
	end

	if data.tooltipAnchorCorner ~= nil and type(data.tooltipAnchorCorner) ~= "string" then
		Drop("tooltipAnchorCorner", "must be text")
	end

	for i = 1, table.getn(SANITIZE_COLOR_KEYS) do
		key = SANITIZE_COLOR_KEYS[i]

		if data[key] ~= nil and not IsValidColorTable(data[key]) then Drop(key, "must hold numeric r/g/b") end
	end

	local artOffset = data.mainBarArtNativeOffset

	if artOffset ~= nil and not (type(artOffset) == "table"
		and (artOffset.y == nil or IsFiniteNumber(artOffset.y))
		and (artOffset.gryphonRightFromFrameLeft == nil or IsFiniteNumber(artOffset.gryphonRightFromFrameLeft))
		and (artOffset.width == nil or IsFiniteNumber(artOffset.width))
		and (artOffset.height == nil or IsFiniteNumber(artOffset.height))) then
		Drop("mainBarArtNativeOffset", "must hold numeric y/width/height")
	end

	if data.latestSeenVersion ~= nil and type(data.latestSeenVersion) ~= "string" then
		Drop("latestSeenVersion", "must be text")
	end

	local artMode = data.mainBarArtMode

	if artMode ~= nil and artMode ~= self.MAIN_BAR_ART_MODE_FULL and artMode ~= self.MAIN_BAR_ART_MODE_NO_GRYPHONS
		and artMode ~= self.MAIN_BAR_ART_MODE_DISABLED then
		Drop("mainBarArtMode", "must be \"full\", \"noGryphons\" or \"disabled\"")
	end

	if data.pendingLayoutBaseline ~= nil and data.pendingLayoutBaseline ~= "modern"
		and data.pendingLayoutBaseline ~= "vanilla" then
		Drop("pendingLayoutBaseline", "must be \"modern\" or \"vanilla\"")
	end

	-- Page/stance assignment maps: [id] -> number or { [stanceIndex] -> number }.
	local assignmentKeys = { "defaultBarPageBarAssignment", "defaultBarStanceBarAssignment" }
	local a, k, v

	for a = 1, 2 do
		key = assignmentKeys[a]

		if data[key] ~= nil and type(data[key]) ~= "table" then
			Drop(key, "must be a table")
		elseif data[key] then
			for k, v in pairs(data[key]) do
				if type(v) ~= "number" and type(v) ~= "table" then
					data[key][k] = nil

					if issues then
						table.insert(issues, key .. "[" .. tostring(k) .. "] must be a number or table")
					end
				end
			end
		end
	end

	-- Any damaged default-bar cfg reseeds the whole defaultBars table (Pet/Stance cfgs are reseeded alone by EnsureDB).
	if data.defaultBars ~= nil then
		local valid = type(data.defaultBars) == "table"

		if valid then
			for i = 1, 5 do
				if not IsValidBarConfig(self, data.defaultBars[i]) then
					valid = false
				end
			end

			for k, v in pairs(data.defaultBars) do
				if type(k) ~= "number" or not IsValidBarConfig(self, v) then
					valid = false
				end
			end
		end

		if not valid then
			Drop("defaultBars", "has a bar entry with missing or invalid values (reset to defaults)")
		else
			for k, v in pairs(data.defaultBars) do
				SanitizeBarExtras(v, "defaultBars[" .. k .. "]", issues)
			end
		end
	end

	-- Custom/Extra bars: non-table or damaged entries are dropped (EnsureExtraBars reseeds missing Extra Bars).
	if data.bars ~= nil then
		local cleaned = {}
		local n = 0

		if type(data.bars) == "table" then
			for i = 1, table.getn(data.bars) do
				local cfg = data.bars[i]

				if IsValidBarConfig(self, cfg) and IsIntegerInRange(cfg.id, 1, SANITIZE_LIMIT) then
					SanitizeBarExtras(cfg, "bars[" .. i .. "]", issues)
					n = n + 1
					cleaned[n] = cfg
				elseif issues then
					table.insert(issues, "bars[" .. tostring(i) .. "] has invalid values (removed)")
				end
			end
		elseif issues then
			table.insert(issues, "bars must be a table")
		end

		data.bars = cleaned
	end
end

-- Joins the first few sanitize issues into one line.
local function FormatSanitizeIssues(issues)
	local shown = {}
	local total = table.getn(issues)
	local i

	for i = 1, math.min(total, 5) do
		shown[i] = issues[i]
	end

	local text = table.concat(shown, "; ")

	if total > 5 then
		text = text .. "; and " .. tostring(total - 5) .. " more"
	end

	return text
end

-- Resolves this character's profile, migrates pre-profile account data into Default Vanilla once, rebuilds
-- Default Modern, and loads the profile into ACABDB. Must run before EnsureDB.
function ACAB:ResolveActiveProfile()
	if type(ACABCharDB) ~= "table" then
		ACABCharDB = {
			activeProfile = self.DEFAULT_PROFILE_NAME,
			hasSelectedProfileBefore = false,
		}
	end

	if type(ACABProfilesDB) ~= "table" then
		ACABProfilesDB = {}
	end

	if type(ACABDB) ~= "table" then
		ACABDB = nil
	end

	-- Non-table profile entries and non-string names are unusable; damaged fields inside the rest are dropped.
	local profileName, profileData

	for profileName, profileData in pairs(ACABProfilesDB) do
		if type(profileName) ~= "string" or type(profileData) ~= "table" then
			ACABProfilesDB[profileName] = nil
		else
			local issues = {}

			self:SanitizeProfileData(profileData, issues)

			if issues[1] then
				self:Print("Reset invalid saved settings in profile \"" .. profileName .. "\": " .. FormatSanitizeIssues(issues))
			end
		end
	end

	if ACABDB then
		local issues = {}

		self:SanitizeProfileData(ACABDB, issues)

		if issues[1] then
			self:Print("Reset invalid saved settings: " .. FormatSanitizeIssues(issues))
		end
	end

	MigrateBuiltInProfileNames(self)

	if not ACABProfilesDB[self.DEFAULT_PROFILE_NAME] and ACABDB then
		ACABProfilesDB[self.DEFAULT_PROFILE_NAME] = self:DeepCopyTable(ACABDB)
	end

	-- Rebuilt whenever it isn't the loaded profile, so it follows Default Vanilla and the current screen size.
	if ACABCharDB.activeProfile ~= self.MODERN_PROFILE_NAME or not ACABProfilesDB[self.MODERN_PROFILE_NAME] then
		local modernData = self:BuildModernBaseProfileData()

		if modernData then
			ACABProfilesDB[self.MODERN_PROFILE_NAME] = modernData
		end
	end

	if not ACABCharDB.hasSelectedProfileBefore then
		self.pendingFirstLoginDialog = true
	end

	local activeProfile = ACABCharDB.activeProfile

	if type(activeProfile) ~= "string" then
		activeProfile = self.DEFAULT_PROFILE_NAME
		ACABCharDB.activeProfile = activeProfile
	end

	-- Falls back to Default Vanilla when the saved profile was deleted on another character.
	if activeProfile ~= self.DEFAULT_PROFILE_NAME and not ACABProfilesDB[activeProfile] then
		self:Print("Profile \"" .. activeProfile .. "\" no longer exists - switched to \"" .. self.DEFAULT_PROFILE_NAME .. "\".")
		activeProfile = self.DEFAULT_PROFILE_NAME
		ACABCharDB.activeProfile = activeProfile
	end

	self.activeProfileName = activeProfile

	local snapshot = ACABProfilesDB[activeProfile]

	if snapshot then
		ACABDB = self:DeepCopyTable(snapshot)
	else
		ACABDB = nil
	end
end

-- Writes the live ACABDB back into ACABProfilesDB[activeProfileName].
function ACAB:SaveActiveProfileData()
	if not self.activeProfileName or not ACABDB then
		return
	end

	ACABProfilesDB = ACABProfilesDB or {}
	ACABProfilesDB[self.activeProfileName] = self:DeepCopyTable(ACABDB)
end

-- Case-insensitive check against every existing profile name (including the built-in and reserved names).
function ACAB:ProfileNameTaken(name)
	if not name or name == "" then
		return false
	end

	local lowerName = string.lower(name)

	if lowerName == string.lower(self.MODERN_BASE_PROFILE_NAME)
		or lowerName == string.lower(self.LEGACY_DEFAULT_PROFILE_NAME)
		or lowerName == string.lower(self.MODERN_PROFILE_NAME) then
		return true
	end

	local names = self:GetProfileNames()
	local i

	for i = 1, table.getn(names) do
		if string.lower(names[i]) == lowerName then
			return true
		end
	end

	return false
end

-- Creates a new profile seeded from the active Default Modern, else Default Vanilla's saved data, or from the live
-- ACABDB if it isn't saved yet. Must not fall back to an empty table - native-mode Pet/Stance Bar resets no-op
-- without defaultBars entries.
function ACAB:CreateProfile(name)
	if not name or name == "" then
		return false, "Profile name cannot be empty."
	end

	ACABProfilesDB = ACABProfilesDB or {}

	if self:ProfileNameTaken(name) then
		return false, "A profile named \"" .. name .. "\" already exists."
	end

	if self.activeProfileName == self.MODERN_PROFILE_NAME then
		self:SaveActiveProfileData()

		ACABProfilesDB[name] = self:DeepCopyTable(ACABProfilesDB[self.MODERN_PROFILE_NAME])
		ACABProfilesDB[name].builtInModernProfile = nil

		return true
	end

	local defaultData = ACABProfilesDB[self.DEFAULT_PROFILE_NAME]

	if not defaultData then
		self:EnsureDB()
		defaultData = ACABDB
	end

	ACABProfilesDB[name] = self:DeepCopyTable(defaultData)

	return true
end

-- Deletes a profile (never a built-in one); deleting the active profile falls this character back to Default Vanilla.
function ACAB:DeleteProfile(name)
	if not name or self:IsBuiltInProfileName(name) then
		return false, "The built-in \"" .. tostring(name) .. "\" profile cannot be deleted."
	end

	if not ACABProfilesDB or not ACABProfilesDB[name] then
		return false, "Profile \"" .. tostring(name) .. "\" does not exist."
	end

	ACABProfilesDB[name] = nil

	if ACABCharDB and ACABCharDB.activeProfile == name then
		ACABCharDB.activeProfile = self.DEFAULT_PROFILE_NAME

		-- Must also update the live pointer, or SaveActiveProfileData resurrects the deleted profile.
		self.activeProfileName = self.DEFAULT_PROFILE_NAME
		ACABDB = self:DeepCopyTable(ACABProfilesDB[self.DEFAULT_PROFILE_NAME] or {})
	end

	return true
end

-- Overwrites targetName's saved data with a copy of sourceName's.
function ACAB:CopyProfileInto(sourceName, targetName)
	if not ACABProfilesDB or not ACABProfilesDB[sourceName] then
		return false, "Source profile \"" .. tostring(sourceName) .. "\" does not exist."
	end

	if not targetName or targetName == "" or self:IsBuiltInProfileName(targetName) then
		return false, "Invalid target profile."
	end

	ACABProfilesDB[targetName] = self:DeepCopyTable(ACABProfilesDB[sourceName])
	ACABProfilesDB[targetName].builtInModernProfile = nil

	if targetName == self.activeProfileName then
		ACABDB = self:DeepCopyTable(ACABProfilesDB[targetName])
	end

	return true
end

-------------------------------------------------------------------------
-- Profile export/import
-- Format: PROFILE_EXPORT_PREFIX + a compact [key]=value table literal. Import is parsed by hand, never
-- loadstring'd (pasted text is untrusted). Keep the format stable so existing exports still import.
-------------------------------------------------------------------------

local PROFILE_EXPORT_PREFIX = "TBVPROFILE1:"

-- Import strings beyond these limits are rejected (a real export is ~5 KB, 4 tables deep).
local PROFILE_IMPORT_MAX_LENGTH = 262144
local PROFILE_IMPORT_MAX_DEPTH = 12

ACAB.PROFILE_IMPORT_ERROR_MESSAGE =
	"Invalid Profile Import Syntax, please double check you copied all " ..
	"Text correctly on your Export and try again"

-- Escapes backslash, quote, and \n \r \t (ParseImportString's inverse).
local function EscapeExportString(s)
	s = string.gsub(s, "\\", "\\\\")
	s = string.gsub(s, "\"", "\\\"")
	s = string.gsub(s, "\n", "\\n")
	s = string.gsub(s, "\r", "\\r")
	s = string.gsub(s, "\t", "\\t")

	return s
end

-- Appends `value`'s serialized form to `parts`; unsupported types serialize as nil.
local function SerializeValue(value, parts)
	if type(value) == "table" then
		table.insert(parts, "{")

		local k, v

		for k, v in pairs(value) do
			if v ~= nil then
				table.insert(parts, "[")
				SerializeValue(k, parts)
				table.insert(parts, "]=")
				SerializeValue(v, parts)
				table.insert(parts, ",")
			end
		end

		table.insert(parts, "}")
	elseif type(value) == "string" then
		table.insert(parts, "\"" .. EscapeExportString(value) .. "\"")
	elseif type(value) == "number" then
		table.insert(parts, tostring(value))
	elseif type(value) == "boolean" then
		table.insert(parts, value and "true" or "false")
	else
		table.insert(parts, "nil")
	end
end

-- Serializes the active profile's live ACABDB into one exportable string.
function ACAB:ExportActiveProfileString()
	local parts = {}

	SerializeValue(ACABDB, parts)

	return PROFILE_EXPORT_PREFIX .. table.concat(parts, "")
end

-- Recursive-descent parser for SerializeValue's grammar. Parse functions return value, or nil, errorString.
local function NewImportParser(str)
	return { str = str, pos = 1, len = string.len(str), depth = 0 }
end

local function SkipImportWhitespace(p)
	while p.pos <= p.len do
		local c = string.sub(p.str, p.pos, p.pos)

		if c == " " or c == "\t" or c == "\n" or c == "\r" then
			p.pos = p.pos + 1
		else
			break
		end
	end
end

local ParseImportValue

-- Parses a quoted string starting at the opening quote.
local function ParseImportString(p)
	p.pos = p.pos + 1

	local resultParts = {}

	while true do
		if p.pos > p.len then
			return nil, "unterminated string"
		end

		local c = string.sub(p.str, p.pos, p.pos)

		if c == "\"" then
			p.pos = p.pos + 1
			break
		elseif c == "\\" then
			local nextC = string.sub(p.str, p.pos + 1, p.pos + 1)

			if nextC == "\\" then
				table.insert(resultParts, "\\")
			elseif nextC == "\"" then
				table.insert(resultParts, "\"")
			elseif nextC == "n" then
				table.insert(resultParts, "\n")
			elseif nextC == "r" then
				table.insert(resultParts, "\r")
			elseif nextC == "t" then
				table.insert(resultParts, "\t")
			else
				return nil, "bad escape sequence"
			end

			p.pos = p.pos + 2
		else
			table.insert(resultParts, c)
			p.pos = p.pos + 1
		end
	end

	return table.concat(resultParts, "")
end

-- Parses a bare token up to the next , } or ] as true/false/nil or a number.
local function ParseImportNumberOrKeyword(p)
	local startPos = p.pos

	while p.pos <= p.len do
		local c = string.sub(p.str, p.pos, p.pos)

		if c == "," or c == "}" or c == "]" then
			break
		end

		p.pos = p.pos + 1
	end

	local token = string.sub(p.str, startPos, p.pos - 1)

	if token == "true" then
		return true
	elseif token == "false" then
		return false
	elseif token == "nil" then
		return nil
	end

	local num = tonumber(token)

	-- Rejects NaN and +-infinity.
	if not num or num ~= num or num <= -SANITIZE_LIMIT or num >= SANITIZE_LIMIT then
		return nil, "invalid value (expected true, false, nil or a normal number)"
	end

	return num
end

-- Parses a {[key]=value,...} table starting at the opening brace; nil keys are skipped.
local function ParseImportTable(p)
	p.pos = p.pos + 1
	p.depth = p.depth + 1

	if p.depth > PROFILE_IMPORT_MAX_DEPTH then
		return nil, "tables nested too deep"
	end

	local result = {}

	SkipImportWhitespace(p)

	if string.sub(p.str, p.pos, p.pos) == "}" then
		p.pos = p.pos + 1
		p.depth = p.depth - 1
		return result
	end

	while true do
		SkipImportWhitespace(p)

		if string.sub(p.str, p.pos, p.pos) ~= "[" then
			return nil, "expected '[' for table key"
		end

		p.pos = p.pos + 1
		SkipImportWhitespace(p)

		local key, keyErr = ParseImportValue(p)

		if key == nil and keyErr then
			return nil, keyErr
		end

		if key ~= nil and type(key) ~= "string" and type(key) ~= "number" then
			return nil, "invalid key type"
		end

		SkipImportWhitespace(p)

		if string.sub(p.str, p.pos, p.pos) ~= "]" then
			return nil, "expected ']' after table key"
		end

		p.pos = p.pos + 1
		SkipImportWhitespace(p)

		if string.sub(p.str, p.pos, p.pos) ~= "=" then
			return nil, "expected '=' after table key"
		end

		p.pos = p.pos + 1
		SkipImportWhitespace(p)

		local value, valueErr = ParseImportValue(p)

		if value == nil and valueErr then
			return nil, valueErr
		end

		if key ~= nil then
			result[key] = value
		end

		SkipImportWhitespace(p)

		local c = string.sub(p.str, p.pos, p.pos)

		if c == "," then
			p.pos = p.pos + 1
			SkipImportWhitespace(p)

			if string.sub(p.str, p.pos, p.pos) == "}" then
				p.pos = p.pos + 1
				break
			end
		elseif c == "}" then
			p.pos = p.pos + 1
			break
		else
			return nil, "expected ',' or '}' in table"
		end
	end

	p.depth = p.depth - 1

	return result
end

ParseImportValue = function(p)
	SkipImportWhitespace(p)

	if p.pos > p.len then
		return nil, "unexpected end of input"
	end

	local c = string.sub(p.str, p.pos, p.pos)

	if c == "{" then
		return ParseImportTable(p)
	elseif c == "\"" then
		return ParseImportString(p)
	else
		return ParseImportNumberOrKeyword(p)
	end
end

-- Parses one whole value; returns the value, or nil, error, position on failure or trailing input.
local function ParseImportBody(body)
	local p = NewImportParser(body)
	local value, err = ParseImportValue(p)

	if err then
		return nil, err, p.pos
	end

	SkipImportWhitespace(p)

	if p.pos <= p.len then
		return nil, "unexpected text after the end of the profile", p.pos
	end

	return value
end

-- Error banner text: the general message plus what went wrong and where (character count includes the prefix).
function ACAB:BuildImportErrorMessage(detail, body, pos)
	local text = self.PROFILE_IMPORT_ERROR_MESSAGE .. "\nProblem: " .. detail

	if body and pos then
		local near = string.gsub(string.sub(body, math.max(pos - 12, 1), pos + 8), "%c", "?")

		text = text .. " at character " .. tostring(pos + string.len(PROFILE_EXPORT_PREFIX)) .. " (near \"" .. near .. "\")"
	end

	return text
end

-- Validates and parses an exported profile string without applying it.
-- Returns true, data, warningText-or-nil (fields dropped for wrong types) or false, errorMessage.
function ACAB:ParseProfileImportString(str)
	if type(str) ~= "string" then
		return false, self:BuildImportErrorMessage("the pasted value is not text")
	end

	if string.len(str) > PROFILE_IMPORT_MAX_LENGTH then
		return false, self:BuildImportErrorMessage("the text is longer than " .. tostring(PROFILE_IMPORT_MAX_LENGTH / 1024) .. " KB")
	end

	local prefixLen = string.len(PROFILE_EXPORT_PREFIX)

	if string.sub(str, 1, prefixLen) ~= PROFILE_EXPORT_PREFIX then
		return false, self:BuildImportErrorMessage("the text must start with " .. PROFILE_EXPORT_PREFIX)
	end

	local body = string.sub(str, prefixLen + 1)
	local ok, result, err, pos = pcall(ParseImportBody, body)

	if not ok then
		return false, self:BuildImportErrorMessage("the text could not be read")
	end

	if err then
		return false, self:BuildImportErrorMessage(err, body, pos)
	end

	if type(result) ~= "table" or type(result.schemaVersion) ~= "number" then
		return false, self:BuildImportErrorMessage("this is not a profile (no numeric schemaVersion found)")
	end

	-- Marks the built-in Default Modern profile; only ACAB itself writes it.
	result.builtInModernProfile = nil

	local issues = {}

	if not pcall(self.SanitizeProfileData, self, result, issues) then
		return false, self:BuildImportErrorMessage("the profile values could not be checked")
	end

	local warning

	if issues[1] then
		warning = "Wrong-typed values will be reset to defaults: " .. FormatSanitizeIssues(issues)
	end

	return true, result, warning
end

-- Overwrites the active profile's live data and saved entry with parsed import data.
-- Must write both, or the logout-time SaveActiveProfileData before ReloadUI clobbers the import.
function ACAB:ApplyImportedProfileData(data)
	if not self.activeProfileName or self:IsBuiltInProfileName(self.activeProfileName) then
		return false
	end

	ACABDB = self:DeepCopyTable(data)

	ACABProfilesDB = ACABProfilesDB or {}
	ACABProfilesDB[self.activeProfileName] = self:DeepCopyTable(data)

	return true
end

-- Switches this character to an existing profile and reloads the UI.
function ACAB:SwitchProfile(name)
	if not ACABProfilesDB or not ACABProfilesDB[name] then
		return false, "Profile \"" .. tostring(name) .. "\" does not exist."
	end

	self:SaveActiveProfileData()

	ACABCharDB = ACABCharDB or {}
	ACABCharDB.activeProfile = name
	ACABCharDB.hasSelectedProfileBefore = true

	ReloadUI()

	return true
end

-- Shared "enter a new profile name" dialog; creates the profile and switches to it.
function ACAB:ShowCreateProfileDialog(onCreated)
	self:ShowDialog({
		title = "New Profile",
		message = "Enter the name for the new profile",
		mode = "textinput",
		buttons = {
			{
				text = "Accept",
				isDefault = true,
				onClick = function(value)
					local ok, reason = ACAB:CreateProfile(value)

					if ok then
						ACAB:SwitchProfile(value)
					elseif reason then
						ACAB:Print(reason)
					end

					if onCreated then
						onCreated(ok, value)
					end
				end,
			},
			{ text = "Cancel", onClick = function() end },
		},
	})
end

-- This character's first-login dialog: setup wizard, use an existing profile, or stay on Default Vanilla.
function ACAB:ShowFirstLoginDialog()
	local buttons = {
		{
			text = "Set up a new custom Profile",
			isDefault = true,
			variant = "prominent",
			onClick = function()
				ACAB:ShowSetupWizard()
			end,
		},
	}

	-- Shown only when a custom (non-built-in) profile exists.
	local names = self:GetProfileNames()
	local hasCustomProfile = false
	local i

	for i = 1, table.getn(names) do
		if not self:IsBuiltInProfileName(names[i]) then
			hasCustomProfile = true
		end
	end

	if hasCustomProfile then
		table.insert(buttons, {
			text = "use existing profile",
			onClick = function()
				ACAB:ShowDialog({
					title = "Use Existing Profile",
					message = "Choose a profile to use for this character.",
					mode = "dropdown",
					options = ACAB:GetProfileNames(),
					buttons = {
						{
							text = "Accept",
							isDefault = true,
							onClick = function(value)
								if value then
									ACAB:SwitchProfile(value)
								end
							end,
						},
						{ text = "Cancel", onClick = function() end },
					},
				})
			end,
		})
	end

	table.insert(buttons, {
		text = "Stay on this uneditable default profile!",
		danger = true,
		variant = "minor",
		onClick = function()
			ACABCharDB = ACABCharDB or {}
			ACABCharDB.hasSelectedProfileBefore = true
		end,
	})

	self:ShowDialog({
		title = "Welcome to ACAB",
		message = "Thank you for choosing ACAB, you are currently using the Profile \"" .. self.DEFAULT_PROFILE_NAME .. "\". " ..
			"The built-in \"" .. self.DEFAULT_PROFILE_NAME .. "\" and \"" .. self.MODERN_PROFILE_NAME .. "\" profiles are locked and " ..
			"cannot be edited - Edit Layout mode and Settings changes are unavailable while one of them is active.\n\n" ..
			"Do you wish to set up your own custom profile?",
		mode = "confirm",
		buttons = buttons,
	})
end

-------------------------------------------------------------------------
-- EnsureDB: migration-safe defaults. Order matters - never reorder, change a default, or reset a one-shot flag.
-------------------------------------------------------------------------

-- One-shot forced default-bar anchor recaptures, applied in this order.
local ANCHOR_RECAPTURE_FLAGS = {
	"anchorRecaptureDone",
	"anchorScaleFixDone",
	"anchorTimingFixDone",
	"anchorEnterWorldFixDone",
}

function ACAB:EnsureDB()
	if type(ACABDB) ~= "table" then
		ACABDB = {}
	end

	if ACABDB.editMode == nil then ACABDB.editMode = false end
	if ACABDB.minimapAngle == nil then ACABDB.minimapAngle = 200 end
	if ACABDB.useDefaultLayout == nil then ACABDB.useDefaultLayout = true end
	if ACABDB.modernBorderStyle == nil then ACABDB.modernBorderStyle = false end
	if ACABDB.bypassRightActionBar2Dependency == nil then ACABDB.bypassRightActionBar2Dependency = false end

	if ACABDB.lastAppliedVanillaStyle == nil then
		ACABDB.lastAppliedVanillaStyle = ACAB:IsVanillaBorderStyle()
	end

	if ACABDB.globalSpacingEnabled == nil then ACABDB.globalSpacingEnabled = false end
	if ACABDB.globalSpacingValue == nil then ACABDB.globalSpacingValue = 0 end
	if ACABDB.globalButtonSizeEnabled == nil then ACABDB.globalButtonSizeEnabled = false end
	if ACABDB.globalButtonSizeValue == nil then ACABDB.globalButtonSizeValue = ACAB.BUTTON_SIZE end

	-- Default-bar (1-5) pagination/stance-swap gates, migrated from the old bar-1-only fields, else true.
	if ACABDB.defaultBarPaginationEnabled == nil then
		if ACABDB.mainBarPaginationEnabled ~= nil then
			ACABDB.defaultBarPaginationEnabled = ACABDB.mainBarPaginationEnabled
		else
			ACABDB.defaultBarPaginationEnabled = true
		end
	end
	if ACABDB.defaultBarStanceSwapEnabled == nil then
		if ACABDB.mainBarStanceSwapEnabled ~= nil then
			ACABDB.defaultBarStanceSwapEnabled = ACABDB.mainBarStanceSwapEnabled
		else
			ACABDB.defaultBarStanceSwapEnabled = true
		end
	end

	-- Per default-bar id: [id] -> assignedId, [id][stanceIndex] -> assignedId; nil = No Pageswap.
	-- Migrates the old bar-1-only value in.
	if not ACABDB.defaultBarPageBarAssignment then
		ACABDB.defaultBarPageBarAssignment = {}

		if ACABDB.mainBarPageBarAssignment then
			ACABDB.defaultBarPageBarAssignment[1] = ACABDB.mainBarPageBarAssignment
		end
	end

	if not ACABDB.defaultBarStanceBarAssignment then
		ACABDB.defaultBarStanceBarAssignment = {}

		if ACABDB.mainBarStanceBarAssignment then
			ACABDB.defaultBarStanceBarAssignment[1] = ACABDB.mainBarStanceBarAssignment
		end
	end

	-- One-time: sets bar 1's nil page/stance assignments to -1 (Default). Never reset this flag.
	if not ACABDB.migratedDefaultBarSwapSentinel then
		ACABDB.migratedDefaultBarSwapSentinel = true

		if ACABDB.defaultBarPageBarAssignment[1] == nil then
			ACABDB.defaultBarPageBarAssignment[1] = -1
		end

		if not ACABDB.defaultBarStanceBarAssignment[1] then
			ACABDB.defaultBarStanceBarAssignment[1] = {}
		end

		local liveCount = self:GetClampedLiveStanceCount()
		local s

		for s = 1, liveCount do
			if ACABDB.defaultBarStanceBarAssignment[1][s] == nil then
				ACABDB.defaultBarStanceBarAssignment[1][s] = -1
			end
		end
	end

	if ACABDB.mainBarPageIndicatorScale == nil then ACABDB.mainBarPageIndicatorScale = 1 end
	-- Page Indicator follows Main Bar until dragged away.
	if ACABDB.mainBarPageIndicatorFollowsMainBar == nil then ACABDB.mainBarPageIndicatorFollowsMainBar = true end

	-- stanceBarPosition/stanceBarNativeAnchor are captured lazily on first build, not seeded here.
	-- Nils a corrupted stanceBarNativeGap so the next login recaptures it.
	if ACABDB.stanceBarNativeGap
		and (ACABDB.stanceBarNativeGap <= 0 or ACABDB.stanceBarNativeGap >= self.BUTTON_SIZE) then
		ACABDB.stanceBarNativeGap = nil
	end

	if ACABDB.tintWholeButtonOnRange == nil then ACABDB.tintWholeButtonOnRange = true end

	-- One-time migration from the old boolean ACABDB.disableBlizzardArt (left in place, no longer read).
	if ACABDB.mainBarArtMode == nil then
		if ACABDB.disableBlizzardArt == true then
			ACABDB.mainBarArtMode = ACAB.MAIN_BAR_ART_MODE_DISABLED
		else
			ACABDB.mainBarArtMode = ACAB.MAIN_BAR_ART_MODE_FULL
		end
	end

	-- Clears an obsolete saved field.
	ACABDB.groupedElementOffsets = nil

	-- Key Ring's hover-only settings are seeded once from Bag Bar's.
	if ACABDB.keyRingHoverOnly == nil then
		ACABDB.keyRingHoverOnly = ACABDB.bagBarHoverOnly == true
	end

	if ACABDB.keyRingHoverDuration == nil then
		ACABDB.keyRingHoverDuration = ACABDB.bagBarHoverDuration or 3
	end

	if ACABDB.snapToAdjacentElements == nil then ACABDB.snapToAdjacentElements = true end

	-- One-time: forces snapToAdjacentElements on for saves predating the true default.
	if not ACABDB.snapDefaultCorrectedOnce then
		ACABDB.snapDefaultCorrectedOnce = true
		ACABDB.snapToAdjacentElements = true
	end

	if ACABDB.showLayoutGrid == nil then ACABDB.showLayoutGrid = true end
	if ACABDB.snapToGrid == nil then ACABDB.snapToGrid = true end
	if ACABDB.useCustomGridSize == nil then ACABDB.useCustomGridSize = false end

	if ACABDB.bagBarEnabled == nil then ACABDB.bagBarEnabled = true end
	if ACABDB.microMenuEnabled == nil then ACABDB.microMenuEnabled = true end
	if ACABDB.stanceBarEnabled == nil then ACABDB.stanceBarEnabled = true end
	if ACABDB.keyRingEnabled == nil then ACABDB.keyRingEnabled = true end
	if ACABDB.latencyBarEnabled == nil then ACABDB.latencyBarEnabled = true end
	if ACABDB.latencyBarScale == nil then ACABDB.latencyBarScale = 1 end

	if ACABDB.tooltipEnabled == nil then ACABDB.tooltipEnabled = false end
	if ACABDB.tooltipScale == nil then ACABDB.tooltipScale = 1 end
	if ACABDB.tooltipAnchorCorner == nil then ACABDB.tooltipAnchorCorner = "BOTTOMRIGHT" end

	if ACABDB.expBarEnabled == nil then ACABDB.expBarEnabled = true end
	if ACABDB.expBarScale == nil then ACABDB.expBarScale = 1 end

	-- Stance/Cast Bar "at default position" flags (Pet Bar's lives on its cfg); cleared on user drag/slider move.
	if ACABDB.stanceBarUsesDefaultPosition == nil then ACABDB.stanceBarUsesDefaultPosition = true end
	if ACABDB.castBarUsesDefaultPosition == nil then ACABDB.castBarUsesDefaultPosition = true end

	-- Only-show-on-hover for simple elements (Bag Bar's pair also governs Key Ring); grid bars use cfg fields.
	if ACABDB.bagBarHoverOnly == nil then ACABDB.bagBarHoverOnly = false end
	if ACABDB.bagBarHoverDuration == nil then ACABDB.bagBarHoverDuration = 3 end
	if ACABDB.microMenuHoverOnly == nil then ACABDB.microMenuHoverOnly = false end
	if ACABDB.microMenuHoverDuration == nil then ACABDB.microMenuHoverDuration = 3 end
	if ACABDB.latencyBarHoverOnly == nil then ACABDB.latencyBarHoverOnly = false end
	if ACABDB.latencyBarHoverDuration == nil then ACABDB.latencyBarHoverDuration = 3 end
	if ACABDB.expBarHoverOnly == nil then ACABDB.expBarHoverOnly = false end
	if ACABDB.expBarHoverDuration == nil then ACABDB.expBarHoverDuration = 3 end

	if ACABDB.castBarScale == nil then ACABDB.castBarScale = 1 end

	if ACABDB.betterExpBarEnabled == nil then ACABDB.betterExpBarEnabled = false end
	if ACABDB.expBarShowCurrentOverMax == nil then ACABDB.expBarShowCurrentOverMax = true end
	if ACABDB.expBarShowPercent == nil then ACABDB.expBarShowPercent = true end
	if ACABDB.expBarShowLevel == nil then ACABDB.expBarShowLevel = true end
	if ACABDB.expBarShowRestedPercent == nil then ACABDB.expBarShowRestedPercent = true end
	if ACABDB.expBarShowRestedTotal == nil then ACABDB.expBarShowRestedTotal = true end

	-- expBarColorEarned/Rested (+ native snapshots) and expBarFontSize are captured lazily, not seeded here.
	if not ACABDB.expBarTextColor then
		ACABDB.expBarTextColor = { r = 1, g = 0.82, b = 0 }
	end

	if ACABDB.expBarGlowPulseInterval == nil then ACABDB.expBarGlowPulseInterval = 1.5 end

	if ACABDB.keyRingScale == nil then ACABDB.keyRingScale = 1 end
	if ACABDB.bagBarScale == nil then ACABDB.bagBarScale = 1 end
	if ACABDB.microMenuScale == nil then ACABDB.microMenuScale = 1 end
	if ACABDB.stanceBarScale == nil then ACABDB.stanceBarScale = 1 end

	if ACABDB.bagBarOrientation == nil then ACABDB.bagBarOrientation = false end
	if ACABDB.stanceBarOrientation == nil then ACABDB.stanceBarOrientation = false end

	-- Micro Menu grid (cols x rows), default one row of 8.
	if ACABDB.microMenuCols == nil then ACABDB.microMenuCols = 8 end
	if ACABDB.microMenuRows == nil then ACABDB.microMenuRows = 1 end

	-- bagBarSpacing/microMenuSpacing/stanceBarSpacing (+ native snapshots) are captured lazily on first build.
	-- One-time forced recapture of those, without the schema bump that would also wipe ACABDB.bars.
	if not ACABDB.spacingRecaptureDone then
		ACABDB.spacingRecaptureDone = true

		ACABDB.bagBarSpacing = nil
		ACABDB.bagBarNativeSpacing = nil
		ACABDB.microMenuSpacing = nil
		ACABDB.microMenuNativeSpacing = nil
		ACABDB.stanceBarSpacing = nil
		ACABDB.stanceBarNativeSpacing = nil
	end

	-- hotkeyFontSize/countFontSize/macroFontSize stay nil until a slider moves (nil = captured default).
	if ACABDB.showMacroText == nil then ACABDB.showMacroText = false end

	-- Each flag forces one default-bar/Page Indicator anchor recapture (reseeds defaultBars, keeps ACABDB.bars).
	do
		local f

		for f = 1, table.getn(ANCHOR_RECAPTURE_FLAGS) do
			local flag = ANCHOR_RECAPTURE_FLAGS[f]

			if not ACABDB[flag] then
				ACABDB[flag] = true

				ACABDB.defaultBars = nil

				ACABDB.mainBarPageIndicatorNativeAnchor = nil
				ACABDB.mainBarPageIndicatorPosition = nil
			end
		end
	end

	if not ACABDB.schemaVersion or ACABDB.schemaVersion < self.SCHEMA_VERSION then
		ACABDB.schemaVersion = self.SCHEMA_VERSION
		ACABDB.defaultBars = seedDefaultBars(self)
		ACABDB.bars = {}
	end

	if not ACABDB.defaultBars then
		ACABDB.defaultBars = seedDefaultBars(self)
	end

	-- Re-asserts dynamicDefaultBar = true on every default bar's (1-5) cfg.
	do
		local defId

		for defId = 1, 5 do
			local defCfg = ACABDB.defaultBars[defId]

			if defCfg then
				defCfg.dynamicDefaultBar = true
			end
		end
	end

	-- Seeds just the Pet Bar cfg for saves predating it (no schema bump, which would wipe ACABDB.bars).
	if not ACABDB.defaultBars[self.PET_BAR_ID] then
		ACABDB.defaultBars[self.PET_BAR_ID] = SeedOneDefaultBar(self, self.PET_BAR_ID)
	end

	-- Pet Bar structural fields re-asserted every call; user-editable ones only nil-seeded.
	-- Its default position is set later, by SetupPetBarNativeContainer.
	do
		local petCfg = ACABDB.defaultBars[self.PET_BAR_ID]

		petCfg.isPetBar = true
		petCfg.fixedActionSlots = IdentitySlots(10)

		if petCfg.condenseEmptyPetSlots == nil then petCfg.condenseEmptyPetSlots = false end
		if petCfg.animateAutoCastGlow == nil then petCfg.animateAutoCastGlow = false end
	end

	-- Seeds just the Stance Bar (styled mode) cfg for saves predating it; native-mode stanceBar* fields untouched.
	if not ACABDB.defaultBars[self.STANCE_BAR_ID] then
		ACABDB.defaultBars[self.STANCE_BAR_ID] = SeedOneDefaultBar(self, self.STANCE_BAR_ID)
	end

	-- Stance Bar structural fields re-asserted every call; useNativeStanceBar only nil-seeded.
	do
		local stanceCfg = ACABDB.defaultBars[self.STANCE_BAR_ID]

		stanceCfg.isStanceBar = true
		stanceCfg.fixedActionSlots = IdentitySlots(self.MAX_STANCE_BUTTONS)

		if stanceCfg.useNativeStanceBar == nil then stanceCfg.useNativeStanceBar = true end
	end

	if not ACABDB.bars then
		ACABDB.bars = {}
	end

	self:EnsureExtraBars()

	-- Once per session only - resetting on every call would stomp SetHoverBindMode(true) mid-session.
	if not hasResetHoverBindModeThisSession then
		ACABDB.hoverBindMode = false
		hasResetHoverBindModeThisSession = true
	end
end
