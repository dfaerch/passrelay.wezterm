# PassRelay

Password Manager Integration for WezTerm

*This plugin is a work in progress.*

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

Heres i will describe setting up for KeePassXC. To make your own integration with some other manager, please see the [Documentation](docs/README.md#Configuration)

### KeePassXC

This integration allows you to retrieve passwords from a running GUI instance of KeePassXC when the database is unlocked (i.e., when you have entered your master password in KeePassXC).

#### 1. KeePassXC-Proxy-CLI Setup

Assuming you have already installed KeePassXC, proceed to install and set up [keepassxc-proxy-cli](https://github.com/dfaerch/keepassxc-proxy-cli).

Open KeePassXC, unlock your database, and add a new entry. You need to add Name, Password and a URL. Since KeePassXC only allows us to search by URLs and not usernames, we will add the username as the URL. In this case, we prefix the URL with `wezterm://` instead of `https://`. Let's add a user named "alice":

``` 
Name: WezTerm Test User Alice
Password: s00pers3cret
URL: wezterm://alice
```

You don't need to fill out the other fields. Save the entry, and let's test that `keepassxc-proxy-cli` can actually read it.

```bash
$ ~/path/to/keepassxc-proxy-cli.py -k ~/.keepassxc-proxy-cli.key -u 'wezterm://alice'
```

*(If you get a "module not found" error, make sure you've followed the setup guide of [keepassxc-proxy-cli](https://github.com/dfaerch/keepassxc-proxy-cli).)*

Since this is your first request for this user, KeePassXC will display a dialog asking you to confirm that the application is allowed to access the password. Once you've confirmed, you should get output like this:

``` 
Name: WezTerm Test User Alice
Login:
Password: s00pers3cret
```

#### 2. WezTerm Configuration

Edit your WezTerm configuration file (`~/.wezterm.lua`).

First, ensure you already have this in your config:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()
```

Then, get and load the plugin:

```lua
passrelay = wezterm.plugin.require("https://github.com/dfaerch/passrelay.wezterm")
```

Finally, configure it and apply the configuration:

```lua
passrelay.apply_to_config(config,
  {
    -- Function that returns users
    get_userlist = function()
      return {"alice", "bob"}
    end,

    -- Command to get password
    get_password = "~/path/to/keepassxc-proxy-cli/keepassxc-proxy-cli.py -k ~/.keepassxc-proxy-cli.key -f %p -u 'wezterm://%user'",

    hotkey = {
      mods = 'CTRL',
      key  = 'p'
    }
  }
)
```

**Note** the `get_userlist` part—since KeePassXC doesn't allow us to list users, we don't need a command here. Instead, we just added a Lua function that, in this case, returns two hard-coded usernames. Remember to set your own users here. If you only need one user and want to skip the user-selection step, simply remove the `get_userlist` entry entirely.
