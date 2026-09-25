-- UpdateCheck.lua
-- Peer version check: announces this client's version over addon messages and nags once if a peer's is newer.

local ACAB = AlternativeClassicActionBars

local MSG_PREFIX = "ACABVersion"
local ANNOUNCE_CHANNELS = { "PARTY", "GUILD", "RAID", "BATTLEGROUND" }

-- Strips a leading "v" or "release/" from a version string.
local function StripVersionPrefix(v)
	if string.find(v, "^release/") then
		return string.sub(v, string.len("release/") + 1)
	end
	if string.find(v, "^v%d") then
		return string.sub(v, 2)
	end
	return v
end

-- Splits `s` on the first `sep`, returning the head and the remainder (nil if `sep` is absent).
local function SplitOnce(s, sep)
	local pos = string.find(s, sep, 1, true)
	if not pos then
		return s, nil
	end
	return string.sub(s, 1, pos - 1), string.sub(s, pos + 1)
end

-- Splits a dot-delimited version core ("1.2.3") into a list of numbers.
local function VersionParts(core)
	local parts = {}
	local rest = core
	while rest do
		local part, remainder = SplitOnce(rest, ".")
		table.insert(parts, tonumber(part) or 0)
		rest = remainder
	end
	return parts
end

-- Compares two "major.minor.patch[-prerelease]" version strings.
-- Returns -1/0/1 for a</=/> b. A "-suffix" ranks below the same core version without one.
function ACAB:CompareVersions(a, b)
	local aCore, aPre = SplitOnce(StripVersionPrefix(a or ""), "-")
	local bCore, bPre = SplitOnce(StripVersionPrefix(b or ""), "-")
	local aParts, bParts = VersionParts(aCore), VersionParts(bCore)

	for i = 1, math.max(table.getn(aParts), table.getn(bParts)) do
		local x, y = aParts[i] or 0, bParts[i] or 0
		if x ~= y then
			return x < y and -1 or 1
		end
	end

	if aPre and not bPre then return -1 end
	if bPre and not aPre then return 1 end
	if aPre and bPre and aPre ~= bPre then
		return aPre < bPre and -1 or 1
	end

	return 0
end

ACAB.currentVersion = GetAddOnMetadata("AlternativeClassicActionBars", "Version") or "0.0.0"

local notifiedThisSession = false

-- Broadcasts this client's version on every announce channel (called once at the end of login).
function ACAB:CheckForUpdates()
	for i = 1, table.getn(ANNOUNCE_CHANNELS) do
		SendAddonMessage(MSG_PREFIX, ACAB.currentVersion, ANNOUNCE_CHANNELS[i])
	end
end

-- Nags once per session if remoteVersion is newer than this client's own version.
function ACAB:HandleVersionAnnouncement(remoteVersion)
	if notifiedThisSession then
		return
	end

	if ACAB:CompareVersions(remoteVersion, ACAB.currentVersion) > 0 then
		notifiedThisSession = true
		ACAB:Print("A newer version (" .. remoteVersion .. ") is available - you're on " .. ACAB.currentVersion ..
			". Get it at https://github.com/TrusT-Codes/AlternativeClassicActionBars/releases")
	end
end

-- Listens for peers' version announcements.
local listenerFrame = CreateFrame("Frame")
listenerFrame:RegisterEvent("CHAT_MSG_ADDON")
listenerFrame:SetScript("OnEvent", function()
	if event ~= "CHAT_MSG_ADDON" or arg1 ~= MSG_PREFIX then
		return
	end
	ACAB:HandleVersionAnnouncement(arg2)
end)
