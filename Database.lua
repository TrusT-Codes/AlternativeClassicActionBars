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

-- Extra Bar `index`'s default layout (seeding and ResetExtraBarLayout). Returns x, y, cols, rows, buttonSize, spacing.
function ACAB:GetDefaultExtraBarLayout(index)
	local ref = EXTRA_BAR_DEFAULT_REFERENCE[index]
	local refCfg = ref and ACABDB.defaultBars and ACABDB.defaultBars[ref.refId]
	local grid = ref and self.DEFAULT_BAR_GRID[ref.refId]

	if not ref or not refCfg or not refCfg.nativeAnchor or not grid then
		local x, y = GetFallbackExtraBarPosition(self, index)
		return x, y, self.BUTTON_COLS, self.BUTTON_ROWS, self:GetCurrentButtonSizeBaseline(), 0
	end

	local buttonSize = self.BUTTON_SIZE
	local spacing = refCfg.nativeSpacing or refCfg.spacing or 0
	local pitch = (buttonSize + spacing) * ref.pitchCount

	local x = refCfg.nativeAnchor.x
	local y = refCfg.nativeAnchor.y

	if ref.side == "above" then
		y = y + pitch
	elseif ref.side == "left" then
		x = x - pitch
	end

	return x, y, grid.cols, grid.rows, buttonSize, spacing
end

-- Extra Bar's live height plus its reference-bar gap, for Stance/Pet/Cast Bar stacking. 0 if the bar is
-- missing, disabled, or moved off its default position.
function ACAB:GetExtraBarStackPitch(extraBarId)
	local bar = self.bars and self.bars[extraBarId]

	if not bar or not bar.config or not bar.config.enabled
		or bar.config.usesDefaultPosition == false then
		return 0
	end

	local index = extraBarId - self.EXTRA_BAR_ID_START
	local ref = EXTRA_BAR_DEFAULT_REFERENCE[index]
	local refCfg = ref and ACABDB.defaultBars and ACABDB.defaultBars[ref.refId]
	local gap = (refCfg and (refCfg.nativeSpacing or refCfg.spacing)) or 0

	return (bar:GetHeight() or 0) + gap
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

ACAB.DEFAULT_PROFILE_NAME = "Default"

-- Reserved name: hidden from GetProfileNames and rejected by ProfileNameTaken.
ACAB.MODERN_BASE_PROFILE_NAME = "ModernBase"

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

-- Sorted list of every saved profile name, Default always first.
function ACAB:GetProfileNames()
	local names = {}
	local n = 0
	local name

	for name in pairs(ACABProfilesDB or {}) do
		if name ~= self.DEFAULT_PROFILE_NAME and name ~= self.MODERN_BASE_PROFILE_NAME then
			n = n + 1
			names[n] = name
		end
	end

	table.sort(names)

	local result = { self.DEFAULT_PROFILE_NAME }
	local i

	for i = 1, n do
		table.insert(result, names[i])
	end

	return result
end

-- Resolves this character's profile, migrates pre-profile account data into Default once, and loads the
-- profile into ACABDB. Must run before EnsureDB.
function ACAB:ResolveActiveProfile()
	if not ACABCharDB then
		ACABCharDB = {
			activeProfile = self.DEFAULT_PROFILE_NAME,
			hasSelectedProfileBefore = false,
		}
	end

	if not ACABProfilesDB then
		ACABProfilesDB = {}
	end

	if not ACABProfilesDB[self.DEFAULT_PROFILE_NAME] and ACABDB then
		ACABProfilesDB[self.DEFAULT_PROFILE_NAME] = self:DeepCopyTable(ACABDB)
	end

	if not ACABCharDB.hasSelectedProfileBefore then
		self.pendingFirstLoginDialog = true
	end

	local activeProfile = ACABCharDB.activeProfile or self.DEFAULT_PROFILE_NAME

	-- Falls back to Default when the saved profile was deleted on another character.
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

-- Case-insensitive check against every existing profile name (including Default and the reserved name).
function ACAB:ProfileNameTaken(name)
	if not name or name == "" then
		return false
	end

	local lowerName = string.lower(name)

	if lowerName == string.lower(self.MODERN_BASE_PROFILE_NAME) then
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

-- Creates a new profile seeded from Default's saved data, or from the live ACABDB if Default isn't saved yet.
-- Must not fall back to an empty table - native-mode Pet/Stance Bar resets no-op without defaultBars entries.
function ACAB:CreateProfile(name)
	if not name or name == "" then
		return false, "Profile name cannot be empty."
	end

	ACABProfilesDB = ACABProfilesDB or {}

	if self:ProfileNameTaken(name) then
		return false, "A profile named \"" .. name .. "\" already exists."
	end

	local defaultData = ACABProfilesDB[self.DEFAULT_PROFILE_NAME]

	if not defaultData then
		self:EnsureDB()
		defaultData = ACABDB
	end

	ACABProfilesDB[name] = self:DeepCopyTable(defaultData)

	return true
end

-- Deletes a profile (never Default); deleting the active profile falls this character back to Default.
function ACAB:DeleteProfile(name)
	if not name or name == self.DEFAULT_PROFILE_NAME then
		return false, "The Default profile cannot be deleted."
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

	if not targetName or targetName == "" then
		return false, "Invalid target profile."
	end

	ACABProfilesDB[targetName] = self:DeepCopyTable(ACABProfilesDB[sourceName])

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
	return { str = str, pos = 1, len = string.len(str) }
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

	if not num then
		return nil, "invalid token"
	end

	return num
end

-- Parses a {[key]=value,...} table starting at the opening brace; nil keys are skipped.
local function ParseImportTable(p)
	p.pos = p.pos + 1

	local result = {}

	SkipImportWhitespace(p)

	if string.sub(p.str, p.pos, p.pos) == "}" then
		p.pos = p.pos + 1
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

-- Parses one whole value; nil on any error or trailing input.
local function ParseImportBody(body)
	local p = NewImportParser(body)
	local value, err = ParseImportValue(p)

	if err then
		return nil
	end

	SkipImportWhitespace(p)

	if p.pos <= p.len then
		return nil
	end

	return value
end

-- Validates and parses an exported profile string without applying it. Returns true, data or false, errorMessage.
function ACAB:ParseProfileImportString(str)
	if type(str) ~= "string" then
		return false, self.PROFILE_IMPORT_ERROR_MESSAGE
	end

	local prefixLen = string.len(PROFILE_EXPORT_PREFIX)

	if string.sub(str, 1, prefixLen) ~= PROFILE_EXPORT_PREFIX then
		return false, self.PROFILE_IMPORT_ERROR_MESSAGE
	end

	local body = string.sub(str, prefixLen + 1)
	local ok, result = pcall(ParseImportBody, body)

	if not ok or type(result) ~= "table" then
		return false, self.PROFILE_IMPORT_ERROR_MESSAGE
	end

	return true, result
end

-- Overwrites the active profile's live data and saved entry with parsed import data.
-- Must write both, or the logout-time SaveActiveProfileData before ReloadUI clobbers the import.
function ACAB:ApplyImportedProfileData(data)
	ACABDB = self:DeepCopyTable(data)

	ACABProfilesDB = ACABProfilesDB or {}
	ACABProfilesDB[self.activeProfileName] = self:DeepCopyTable(data)
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

-- This character's first-login dialog: setup wizard, use an existing profile, or stay on Default.
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

	if table.getn(self:GetProfileNames()) > 1 then
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
		message = "Thank you for choosing ACAB, you are currently using the Profile \"Default\". " ..
			"The Default profile is locked and cannot be edited - Edit Layout mode and Settings changes are unavailable while it is active.\n\n" ..
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
	if not ACABDB then
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
