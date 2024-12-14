# PassRelay

Password Manager Integration for WezTerm

## Description

PassRelay is a plugin for WezTerm that enables integration with external password managers by defining external commands or Lua functions to retrieve passwords and optionally user accounts.

## Installation

The plugin can be installed using WezTerm's plugin system (`wezterm.plugin.require()`). Here's an example:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local passrelay_settings = {
    -- Configuration goes here. See Configuration below.
}

wezterm.plugin.require("https://github.com/dfaerch/passrelay.wezterm").apply_to_config(config, passrelay_settings)
```

## Configuration

To configure PassRelay, you need to define a settings table (e.g., `passrelay_settings`). Here's an outline:

```lua
local passrelay_settings = {
    get_userlist = ...,  -- Command or function to fetch a list of user accounts
    get_password = ...,  -- Command or function to fetch the password
    hotkey = {
        mods = ...,      -- Modifier keys (e.g., "CTRL", "ALT")
        key  = ...,      -- Key to press (e.g., "p")
    },
    toast_time = ...,    -- Duration for toast notifications in milliseconds
}
```

***Note:***: For more details, please see the [Documentation](docs/README.md#Configuration)

## Usage

There are 2 ways to use this:

- There are pre-made examples for different password managers in the [integrations](integrations/) subdir. If your password manager is listed there, simply follow that example.

- If you are looking to make your own integration with some other manager, please see the full [Documentation](docs/README.md#Configuration)


