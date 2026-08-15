# 1Password Desktop Integration

This documents how to use PassRelay to integrate a password-manager into Wezterm. 

This integrating for the **Desktop version of 1Password**.

## Prerequisites

You must have:
- Installed `1Password-cli` and `1Password-desktop`
- Configured 1Password's [desktop app integration](https://developer.1password.com/docs/cli/app-integration/)

## Wezterm Configuration

First, ensure you already have this in your config:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()
```

Then, install & load the plugin:
```lua
passrelay = wezterm.plugin.require("https://github.com/dfaerch/passrelay.wezterm")
```

And then cofigure it:
```lua
local passrelay_settings = {
  get_userlist = {
    format='json',
    command = "op item list --tags wezterm --format=json",
    id_path = "id",
    label_path = "title"
  },
  get_password = "op item get %user --fields password --reveal",
  hotkey = { mods = 'CTRL', key = 'p' },
}
passrelay.apply_to_config(config,passrelay_settings)
```
