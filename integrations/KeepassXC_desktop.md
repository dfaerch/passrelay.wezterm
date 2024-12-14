# KeepassXC Integration

This documents how to use PassRelay to integrate a password-manager into Wezterm. 

This integrating for **KeepassXC** (not keepassxc-cli)

This integration allows you to retrieve passwords from a running GUI instance of KeePassXC when the database is unlocked (i.e., when you have entered your master password in KeePassXC).

## Initial notes

KeePassXC provides integration for webbrowsers to find logins for specific URL's. Since this allows for requesting by URL and not eg. login-name, we work around this by adding each user into KeePassXC as urls that look like this: `wezterm://username`. Secondly, KeePassXC does not allow us to list the users/urls, so instead we simply add these manually to the `get_userlist` function.

With these 2 minor workarounds, integration works perfectly.


## 1. KeePassXC-Proxy-CLI Setup

Assuming you have already installed KeePassXC, proceed to install and set up [keepassxc-proxy-cli](https://github.com/dfaerch/keepassxc-proxy-cli).

Open KeePassXC, unlock your database, and add a new entry. Add the username as the URL. In this case, we prefix the URL with `wezterm://` instead of `https://`. Let's add a user named "alice". Now you KeepassXC entry will look a bit like this:

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

## 2. WezTerm Configuration

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
      return {
        "alice", 
        "bob"
      }
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

**Note** the `get_userlist` part!
KeePassXC doesn't allow us to list users so we simply add this small Lua function that returns a list of username. Remember to set your own users here (without the wezterm:// part). 

**Alternative**: If you only need a _single_ password, simply remove the `get_userlist` entry entirely, and add the name to `get_password` instead of `%user`. Example with user `alice`:

```lua
passrelay.apply_to_config(config,
  {
    -- Command to get password
    get_password = "~/path/to/keepassxc-proxy-cli/keepassxc-proxy-cli.py -k ~/.keepassxc-proxy-cli.key -f %p -u 'wezterm://alice'",
  }
)
```

This way, the userselection will just be skipped.