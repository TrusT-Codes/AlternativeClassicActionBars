-- ProfileDialogs.lua
-- Create-profile and first-login dialogs (built on Dialog.lua's ACAB:ShowDialog; runtime only).

local ACAB = AlternativeClassicActionBars

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
