local wezterm = require("wezterm")

---@class password_fetch_module
local M = { version = 1 }

--- Function to display an input selector for user list
-- @param window Window The wezterm window object
-- @param user_accounts table The list of user accounts
-- @param callback function Function to call with the selected account
local function displaySelector(window, user_accounts, callback)
    local choices = {}
    for _, account in ipairs(user_accounts) do
        table.insert(choices, {label = account, id = account})
    end

    window:perform_action(
        wezterm.action.InputSelector {
            title = "Select Account",
            choices = choices,
            action = wezterm.action_callback(function(window, _, id)
                if id then
                    callback(id)
                end
            end),
        },
        window:mux_window():active_pane()
    )
end

-- Determine if cmd is a command or a function call, then execute
-- Determine if cmd is a command or a function call, then execute
local function run_command(cmd, ...)
    local success, output, stderr
    local args = { ... }

    wezterm.log_info("Type of cmd: " .. type(cmd))

    if type(cmd) == "function" then
        -- Pass all additional arguments to the function
        success, output = pcall(cmd, table.unpack(args))
        stderr = nil
    else
        -- Make a copy of cmd to avoid modifying the original
        local cmd_str = cmd

        -- If arguments are provided, substitute `%user` in the command string
        if #args > 0 and type(args[1]) == "string" then
            local selected_account = args[1]
            cmd_str = cmd_str:gsub("%%user", selected_account)
        end

        -- Execute the command string
        success, output, stderr = wezterm.run_child_process({"sh", "-c", cmd_str})
    end

    -- Error handling and output processing
    if not success then
        local err_msg = stderr or output or "Unknown error"
        wezterm.log_error("Command failed: " .. tostring(err_msg))
        return nil, err_msg
    end

    if type(output) == "string" and output == "" then
        return nil, "No output returned from command"
    end

    return output, nil
end

--- Getting a password
-- @param window Window The wezterm window object
-- @param pane Pane The wezterm pane object
-- @param module_settings table The settings for this module
function M.get_password(window, pane, module_settings)
    local user_accounts = {}

    -- Check if `get_userlist` is provided
    if module_settings.get_userlist then
        -- Fetch the user list via `get_userlist`
        local user_list, err = run_command(module_settings.get_userlist)

        -- Handle potential errors
        if not user_list then
            window:toast_notification("PassRelay Error", "Failed to get user list.\n\n" .. tostring(err), nil, module_settings.toast_time)
            return
        end

        -- Process the user list
        if type(user_list) == "string" then
            -- Split user list by newline
            for account in user_list:gmatch("[^\r\n]+") do
                table.insert(user_accounts, account)
            end
        elseif type(user_list) == "table" then
            -- Assume it's a list of account names
            user_accounts = user_list
        else
            window:toast_notification("PassRelay Error", "Invalid user list format", nil, module_settings.toast_time)
            return
        end
    end

    -- If no user accounts found, proceed to password fetch without selection
    if #user_accounts == 0 then
        -- Run `get_password` without account substitution
        local password, err = run_command(module_settings.get_password)

        if password then
            window:perform_action(wezterm.action.SendString(password), pane)
        else
            window:toast_notification("PassRelay Error", "Failed to get password.\n\n" .. tostring(err), nil, module_settings.toast_time)
        end
        return
    end

    -- Otherwise, prompt user for account selection
    displaySelector(window, user_accounts, function(selected_account)
        -- Run `get_password` with the selected account
        local password, err = run_command(module_settings.get_password, selected_account)

        if password then
            window:perform_action(wezterm.action.SendString(password), pane)
        else
            window:toast_notification("PassRelay Error", "Failed to get password.\n\n" .. tostring(err), nil, module_settings.toast_time)
        end
    end)
end

function M.apply_to_config(config, module_settings)
    if not module_settings or not module_settings.get_password then
        wezterm.log_error("module_settings are missing required setting get_password")
        wezterm.toast_notification("Configuration Error", "module_settings are missing required get_password", nil, 5000)
        return
    end

    config.keys = config.keys or {}

    if not module_settings or not module_settings.toast_time then
        module_settings.toast_time = 3000
    end

    if not module_settings or not module_settings.hotkey or not module_settings.hotkey.key or not module_settings.hotkey.mods then
        module_settings.hotkey = {
            mods = 'CTRL',
            key  = 'p'
        }
    end

    table.insert(config.keys, {
        mods = module_settings.hotkey.mods ,
        key = module_settings.hotkey.key,
        action = wezterm.action_callback(function(window, pane)
            M.get_password(window, pane, module_settings)
        end),
    })
end

return M
