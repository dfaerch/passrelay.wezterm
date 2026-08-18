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

Then, install and configure the plugin:

```lua
local passrelay_settings = (function()
  local op_accounts = {}

  local function get_userlist()
    local success, stdout, stderr =
      wezterm.run_child_process({ "op", "item", "list", "--tags", "wezterm", "--format=json" })
    if not success then
      error("op item list failed: " .. tostring(stderr))
    end

    local items = wezterm.json_parse(stdout)
    op_accounts = {}
    local labels = {}
    for _, item in ipairs(items) do
      local label = item.title .. " (" .. item.vault.name .. ")"
      op_accounts[label] = item.vault.id .. "/" .. item.id
      table.insert(labels, label)
    end
    return labels
  end

  local function get_password(user)
    local path = op_accounts[user]
    if not path then
      error("no known 1Password item for " .. tostring(user))
    end

    local success, stdout, stderr = wezterm.run_child_process({ "op", "read", "op://" .. path .. "/password" })
    if not success then
      error("op read failed: " .. tostring(stderr))
    end
    return stdout
  end

  return {
    get_userlist = get_userlist,
    get_password = get_password,
    hotkey = { mods = "ALT|CTRL", key = "p" },
  }
end)()
wezterm.plugin.require("https://github.com/dfaerch/passrelay.wezterm").apply_to_config(config, passrelay_settings)
```

## Implementation Notes

In order to reliably retrieve the password value, even when the password
contains special characters such as quotes or commas, it's important
that the 1Password CLI [op read](https://www.1password.dev/cli/reference/commands/read)
command be used.

Do not use `op item get` to retrieve the password because the format of the returned
password value is not consistent when the password contains special characters
(e.g., quoting and escaping.)
