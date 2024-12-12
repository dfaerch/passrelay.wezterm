# PassRelay Documentation

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

Check out the `Examples` below for more complete examples.

***Note:***: All options are optional except for `get_password`.

### **get_userlist**
### **get_userlist**

Specifies how to fetch the list of user accounts. If not provided, no user selection will occur.

- If `get_userlist` is given as a simple string, it is interpreted as shorthand for:  
  `get_userlist = { format = "text", command = "your_command" }`  
  The default `format` is `"text"`, and the command's output is treated as plain text with one username per line.

 **JSON format**: Use a table to specify the `format`, `command`, and the fields `id_path` and `label_path`. Example:  
  ```lua
  get_userlist = 
    { 
      format = "json", 
      command = "your_command_to_fetch_json", 
      id_path = "id", 
      label_path = "additional_information" 
    }
  ```  
  `label_path` is used to identify what field in the json should be extract to use for the label (ie the name displayed to the user), and `id_path` is for the `id` that will not be displayed, but will be sent to the %user param of `get_password`.

- **Plain text format**: When the `format` is `"text"`, the output should contain one username per line. Example:  
  `get_userlist = "/bin/echo -e \"bob\\nalice\""`

- **Function**: If a function is provided, it will be called, and a list of users is expected to be returned. Example:  
```lua
get_userlist = function()
    return {"alice", "bob"}
end
```

### **get_password** *(mandatory)*

A command (string) or function to fetch the password.

- **If given a string**, this string will be executed by `sh -c`. For example, `get_password = "/bin/echo password123"` will execute "/bin/echo" and return the password "password123" to the console. If used with `get_userlist`, you can add `%user` to the command to pass in the selected username, e.g., `get_password = "grep %user /path/to/userlist"`. Note that no sanitization is done by PassRelay on the username before inserting.

- **If given a function**, the function will be called (with the username as an argument if `get_userlist` is defined), and must return the password as a string. Example:

```lua
get_password = function(user)
    return "password123"
end
```

***Note:*** Remember that if you do not return a newline, you will have to hit enter yourself on the password prompt. This may be desirable in some cases, but in most cases, you probably want to return a newline as well.

### **hotkey**

A table defining the keybinding for triggering password retrieval:

- `mods`: Modifier keys (e.g., `"CTRL"`, `"ALT"`).
- `key`: The key to press (e.g., `"p"`).

Default is `CTRL+p`.

### ***debug***

Set to 1, to get extra debug ouput. *NOTE*: This will show/log passwords too.

### **toast_time**

Duration (in milliseconds) for toast notifications. Toasts display error information.

Default is 3000 ms.

## Developer Examples

If you are looking to integrate with a password manager yourself, this section is for you.

**NOTE**: PassRelay is meant to talk to password managers that are already running, eg. as an agent or a GUI, and thus currently has no way of prompting the user for a master password to unlock the password manager.


### Basic Examples

The next two examples are basic demonstrations of how to use the module.

***Note:*** These examples use hardcoded passwords only to simplify the example. It is not recommended to do this in practice.

#### Basic Example 1

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local passrelay_settings = {
  get_userlist = '/bin/echo -e "bob\nalice"',
  get_password = "echo %user:testpass",

  hotkey = {
      mods = 'CTRL',
      key  = 'p',
  },

  toast_time = 3000,
}

wezterm.plugin.require("https://github.com/dfaerch/passrelay.wezterm").apply_to_config(config, passrelay_settings)
```

##### Result:

When you hit `CTRL+p`, you can choose between "bob" or "alice". If you choose "bob", you will get `bob:testpass` output into your terminal.

#### Basic Example 2

You can also use functions for `get_userlist` and `get_password` instead (or for just one of them if you wish). Here's an example with two functions:

```lua
local wezterm = require 'wezterm'
local config = wezterm.config_builder()

local passrelay_settings = {
  get_userlist = function()
      return {"alice", "bob"}
  end,
  get_password = function(user)
      local users = {
          bob = "password123",
          alice = "s00pers3cret",
      }
      return users[user]
  end,

  hotkey = {
      mods = 'CTRL',
      key  = 'p',
  },

  toast_time = 3000,
}

wezterm.plugin.require("https://github.com/dfaerch/passrelay.wezterm").apply_to_config(config, passrelay_settings)
```

##### Result:

When you hit `CTRL+p`, you can choose between "alice" or "bob". The user will then be used to look up in the table in the get_password() function, and in the case of alice, return `password123`.
