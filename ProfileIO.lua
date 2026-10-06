-- ProfileIO.lua
-- Profile export serializer and hand-rolled import parser, plus import validation/apply.

local ACAB = AlternativeClassicActionBars

-- Same value as Database.lua's SANITIZE_LIMIT.
local SANITIZE_LIMIT = 1e15

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
		warning = "Wrong-typed values will be reset to defaults: " .. self:FormatSanitizeIssues(issues)
	end

	return true, result, warning
end

-- Session-state keys an import never takes from the exporter; the importer's own live values are kept.
local IMPORT_LOCAL_KEYS = { "latestSeenVersion", "latestSeenVersionMisses", "editMode", "hoverBindMode" }

-- Overwrites the active profile's live data and saved entry with parsed import data.
-- Must write both, or the logout-time SaveActiveProfileData before ReloadUI clobbers the import.
function ACAB:ApplyImportedProfileData(data)
	if not self.activeProfileName or self:IsBuiltInProfileName(self.activeProfileName) then return false end

	local i, key

	for i = 1, table.getn(IMPORT_LOCAL_KEYS) do
		key = IMPORT_LOCAL_KEYS[i]
		data[key] = ACABDB and ACABDB[key]
	end

	ACABDB = self:DeepCopyTable(data)

	ACABProfilesDB = ACABProfilesDB or {}
	ACABProfilesDB[self.activeProfileName] = self:DeepCopyTable(data)

	return true
end
