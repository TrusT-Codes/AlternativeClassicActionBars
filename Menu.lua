-- Menu.lua
-- Minimap-button context menu, built on vanilla's native UIDropDownMenuTemplate.

local ACAB = AlternativeClassicActionBars

ACAB.menuFrame = CreateFrame("Frame", "ACABDropDownMenu", UIParent, "UIDropDownMenuTemplate")

-- Checkbox entry that keeps the menu open on click.
local function NewToggleInfo(text, checked, func)
	return {
		text = text,
		isNotRadio = true,
		checked = checked,
		func = func,
		keepShownOnClick = true,
	}
end

local function InitializeMenu()
	local info = {}

	info.text = "Settings"
	info.notCheckable = true
	info.func = function() ACAB:ToggleSettingsFrame() end
	UIDropDownMenu_AddButton(info)

	info = NewToggleInfo("Configure Layout", ACAB:IsEditMode(), function() ACAB:ToggleEditMode() end)

	if ACAB:IsDefaultProfileActive() then
		info.disabled = 1
		info.tooltipWhileDisabled = 1
		info.tooltipOnButton = 1
		info.tooltipTitle = "Configure Layout"
		info.tooltipText = "A profile other than the built-in Default profiles needs to be active to use Edit Layout mode."
	end

	UIDropDownMenu_AddButton(info)

	UIDropDownMenu_AddButton(NewToggleInfo("Lock Action Bars", ACAB:IsLockActionBars(),
		function() ACAB:ToggleLockActionBars() end))

	UIDropDownMenu_AddButton(NewToggleInfo("Hoverbind", ACAB:IsHoverBindMode(),
		function() ACAB:ToggleHoverBindMode() end))

	UIDropDownMenu_AddButton(NewToggleInfo("Always Show Action Bars", ACAB:IsAlwaysShowMultibars(),
		function() ACAB:ToggleAlwaysShowMultibars() end))
end

UIDropDownMenu_Initialize(ACAB.menuFrame, InitializeMenu, "MENU")

function ACAB:ToggleMainMenu()
	ToggleDropDownMenu(1, nil, self.menuFrame, "ACABMinimapButton", 0, 0)
end
