-- UpdateCheck.lua
-- Peer version check: announces this client's version over addon messages and nags once if a peer's is newer.

local ACAB = AlternativeClassicActionBars

local MSG_PREFIX = "ACABVersion"
local ANNOUNCE_CHANNELS = { "PARTY", "GUILD", "RAID", "BATTLEGROUND" }

-- Logins in a row without a peer re-announcing the saved newer version before it is forgotten.
local SAVED_NAG_MAX_MISSED_LOGINS = 5

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

local VERSION_MAX_LENGTH = 24

-- True for "major.minor.patch" with an optional "-suffix" of letters, digits and dots, at most 24 characters.
function ACAB:IsValidVersionString(v)
	if type(v) ~= "string" or string.len(v) > VERSION_MAX_LENGTH then return false end

	return string.find(v, "^%d+%.%d+%.%d+$") ~= nil or string.find(v, "^%d+%.%d+%.%d+%-[%w%.]+$") ~= nil
end

ACAB.currentVersion = GetAddOnMetadata("AlternativeClassicActionBars", "Version") or "0.0.0"

local VERSION_CHANNEL = "ACABVersion"
local CHANNEL_MSG_PREFIX = "ACABv:"
local CHANNEL_JOIN_DELAY = 10
local REPLY_COOLDOWN = 60
local REPLY_MIN_DELAY = 1
local REPLY_MAX_DELAY = 6

local notifiedThisSession = false
local lastReplyAt = {}
local pendingReplies = {}

-- Returns true if channelName is the hidden version channel.
local function IsVersionChannel(channelName)
	return channelName and string.lower(channelName) == string.lower(VERSION_CHANNEL)
end

-- Sends this client's version on one distribution ("CHANNEL" uses the hidden version channel).
local function SendOwnVersion(distribution)
	if distribution == "CHANNEL" then
		local channelId = GetChannelName(VERSION_CHANNEL)
		if channelId and channelId > 0 then
			SendChatMessage(CHANNEL_MSG_PREFIX .. ACAB.currentVersion, "CHANNEL", nil, channelId)
		end
		return
	end
	SendAddonMessage(MSG_PREFIX, ACAB.currentVersion, distribution)
end

-- Prints the update nag once per session.
local function NotifyNewerVersion(remoteVersion)
	if notifiedThisSession then return end
	notifiedThisSession = true
	ACAB:Print("A newer version (" .. remoteVersion .. ") is available - you're on " .. ACAB.currentVersion ..
		". Get it at https://github.com/TrusT-Codes/AlternativeClassicActionBars/releases")
end

-- Clears the saved newest version and its missed-login counter.
local function ForgetSavedVersion()
	ACABDB.latestSeenVersion = nil
	ACABDB.latestSeenVersionMisses = nil
end

-- Stores remoteVersion as the newest seen version if it beats the saved one; resets the missed-login
-- counter when it is at least the saved one.
local function RememberVersion(remoteVersion)
	if not ACABDB then return end
	local cmp = ACABDB.latestSeenVersion and ACAB:CompareVersions(remoteVersion, ACABDB.latestSeenVersion) or 1
	if cmp > 0 then
		ACABDB.latestSeenVersion = remoteVersion
	end
	if cmp >= 0 then
		ACABDB.latestSeenVersionMisses = 0
	end
end

-- Login check: counts one missed login and nags if a saved version is newer than this one; forgets it once
-- caught up or after SAVED_NAG_MAX_MISSED_LOGINS logins in a row without a peer re-announcing it.
local function CheckSavedLatestVersion()
	if not ACABDB or not ACABDB.latestSeenVersion then return end
	if not ACAB:IsValidVersionString(ACABDB.latestSeenVersion) then
		ForgetSavedVersion()
		return
	end
	if ACAB:CompareVersions(ACABDB.latestSeenVersion, ACAB.currentVersion) <= 0 then
		ForgetSavedVersion()
		return
	end

	local misses = (ACABDB.latestSeenVersionMisses or 0) + 1
	if misses >= SAVED_NAG_MAX_MISSED_LOGINS then
		ForgetSavedVersion()
		return
	end

	ACABDB.latestSeenVersionMisses = misses
	NotifyNewerVersion(ACABDB.latestSeenVersion)
end

-- Schedules a reply after a random delay; cancelled if another peer answers with >= our version first.
local function ScheduleReply(distribution)
	if not distribution or pendingReplies[distribution] then return end
	local now = GetTime()
	if lastReplyAt[distribution] and now - lastReplyAt[distribution] < REPLY_COOLDOWN then return end
	local delay = REPLY_MIN_DELAY + math.random() * (REPLY_MAX_DELAY - REPLY_MIN_DELAY)
	pendingReplies[distribution] = C_Timer.NewTimer(delay, function()
		pendingReplies[distribution] = nil
		lastReplyAt[distribution] = GetTime()
		SendOwnVersion(distribution)
	end)
end

-- Cancels a pending reply on distribution.
local function CancelReply(distribution)
	local timer = pendingReplies[distribution]
	if timer then
		timer:Cancel()
		pendingReplies[distribution] = nil
	end
end

-- Joins the hidden version channel and removes it from every chat frame.
local function JoinVersionChannel()
	JoinChannelByName(VERSION_CHANNEL)
	for i = 1, NUM_CHAT_WINDOWS do
		local chatFrame = getglobal("ChatFrame" .. i)
		if chatFrame then
			ChatFrame_RemoveChannel(chatFrame, VERSION_CHANNEL)
		end
	end
end

-- Joins the hidden version channel and announces on it 2 seconds later.
local function JoinAndAnnounceOnVersionChannel()
	JoinVersionChannel()
	C_Timer.After(2, function()
		SendOwnVersion("CHANNEL")
	end)
end

-- Leaves the hidden version channel if this client is in it.
local function LeaveVersionChannel()
	local channelId = GetChannelName(VERSION_CHANNEL)
	if channelId and channelId > 0 then
		LeaveChannelByName(VERSION_CHANNEL)
	end
end

-- True unless the active profile opted out of the hidden version channel.
function ACAB:IsUpdateChannelEnabled()
	return not (ACABDB and ACABDB.updateChannelDisabled == true)
end

-- Saves the hidden-channel opt-out and joins (and announces) or leaves the channel right away.
function ACAB:SetUpdateChannelEnabled(enabled)
	ACABDB.updateChannelDisabled = not enabled
	if enabled then
		JoinAndAnnounceOnVersionChannel()
	else
		LeaveVersionChannel()
	end
end

-- Checks the saved newest version, then announces on group channels and (after a delay) joins and announces
-- on the hidden channel, or leaves it when opted out.
function ACAB:CheckForUpdates()
	CheckSavedLatestVersion()

	for i = 1, table.getn(ANNOUNCE_CHANNELS) do
		SendOwnVersion(ANNOUNCE_CHANNELS[i])
	end

	C_Timer.After(CHANNEL_JOIN_DELAY, function()
		if ACAB:IsUpdateChannelEnabled() then
			JoinAndAnnounceOnVersionChannel()
		else
			LeaveVersionChannel()
		end
	end)
end

-- Handles a peer's version: nags if newer, replies if older, cancels our reply if a peer already answered.
-- Malformed versions are ignored.
function ACAB:HandleVersionAnnouncement(remoteVersion, distribution)
	if not ACAB:IsValidVersionString(remoteVersion) then return end

	local cmp = ACAB:CompareVersions(remoteVersion, ACAB.currentVersion)
	if cmp < 0 then
		ScheduleReply(distribution)
		return
	end

	CancelReply(distribution)
	if cmp > 0 then
		RememberVersion(remoteVersion)
		NotifyNewerVersion(remoteVersion)
	end
end

-- Suppresses all chat-frame output for the hidden version channel.
local origChatFrameOnEvent = ChatFrame_OnEvent
ChatFrame_OnEvent = function(ev)
	if string.find(ev, "^CHAT_MSG_CHANNEL") and IsVersionChannel(arg9) then return end
	return origChatFrameOnEvent(ev)
end

-- Listens for peers' version announcements on addon messages and the hidden channel.
local listenerFrame = CreateFrame("Frame")
listenerFrame:RegisterEvent("CHAT_MSG_ADDON")
listenerFrame:RegisterEvent("CHAT_MSG_CHANNEL")
listenerFrame:SetScript("OnEvent", function()
	if event == "CHAT_MSG_ADDON" then
		if arg1 ~= MSG_PREFIX or arg4 == UnitName("player") then return end
		ACAB:HandleVersionAnnouncement(arg2, arg3)
	elseif event == "CHAT_MSG_CHANNEL" then
		if not IsVersionChannel(arg9) or arg2 == UnitName("player") then return end
		local _, _, remoteVersion = string.find(arg1 or "", "^" .. CHANNEL_MSG_PREFIX .. "(%S+)$")
		if remoteVersion then
			ACAB:HandleVersionAnnouncement(remoteVersion, "CHANNEL")
		end
	end
end)
