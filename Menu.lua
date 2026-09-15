-- Menu.lua
-- Context menu opened by the minimap button, built on vanilla's native
-- UIDropDownMenuTemplate system.

local ACAB = AlternativeClassicActionBars

ACAB.menuFrame = CreateFrame("Frame", "ACABDropDownMenu", UIParent, "UIDropDownMenuTemplate")

local function InitializeMenu()
	local info = {}

	info.text = "Settings"
	info.notCheckable = true
	info.func = function() ACAB:ToggleSettingsFrame() end
	UIDropDownMenu_AddButton(info)

	info = {}
	info.text = "Configure Layout"
	info.isNotRadio = true
	info.checked = ACAB:IsEditMode()
	info.func = function() ACAB:ToggleEditMode() end
	info.keepShownOnClick = true

	if ACAB:IsDefaultProfileActive() then
		info.disabled = 1
		info.tooltipWhileDisabled = 1
		info.tooltipOnButton = 1
		info.tooltipTitle = "Configure Layout"
		info.tooltipText = "A profile other than the Default profile needs to be active to use Edit Layout mode."
	end

	UIDropDownMenu_AddButton(info)

	info = {}
	info.text = "Lock Action Bars"
	info.isNotRadio = true
	info.checked = ACAB:IsLockActionBars()
	info.func = function() ACAB:ToggleLockActionBars() end
	info.keepShownOnClick = true
	UIDropDownMenu_AddButton(info)

	info = {}
	info.text = "Hoverbind"
	info.isNotRadio = true
	info.checked = ACAB:IsHoverBindMode()
	info.func = function() ACAB:ToggleHoverBindMode() end
	info.keepShownOnClick = true
	UIDropDownMenu_AddButton(info)

	info = {}
	info.text = "Always Show Action Bars"
	info.isNotRadio = true
	info.checked = ACAB:IsAlwaysShowMultibars()
	info.func = function() ACAB:ToggleAlwaysShowMultibars() end
	info.keepShownOnClick = true
	UIDropDownMenu_AddButton(info)
end

UIDropDownMenu_Initialize(ACAB.menuFrame, InitializeMenu, "MENU")

function ACAB:ToggleMainMenu()
	ToggleDropDownMenu(1, nil, self.menuFrame, "ACABMinimapButton", 0, 0)
end
