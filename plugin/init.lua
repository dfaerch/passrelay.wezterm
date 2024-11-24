local wezterm = require("wezterm")

---@class password_fetch_module
local M = {}

--- function to display an input selector for user list
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
local function run_command(cmd)
    local success, output, stderr
    if type(cmd) == "function" then
        success, output = pcall(cmd)
    else
        success, output, stderr = wezterm.run_child_process({"sh", "-c", cmd})
    end
    return success, output, stderr
end

--- Getting a password
-- @param window Window The wezterm window object
-- @param pane Pane The wezterm pane object
-- @param module_settings table The setting for this module
function M.get_password(window, pane, module_settings)
    local user_accounts = {}

    -- Check if `get_userlist` is provided
    if module_settings.get_userlist then
        -- Fetch the user list via `get_userlist`
        local success, user_list, stderr = run_command(module_settings.get_userlist)

        -- Log and handle potential errors
        if not success or type(user_list) ~= "string" or user_list == "" then
            wezterm.log_info("User list command failed with output: " .. tostring(user_list))
            wezterm.log_info("User list command stderr: " .. tostring(stderr))
            window:toast_notification("Password Retrieval", "Failed to get user list: ".. stderr, nil, 3000)
            return
        end

        -- Split user list by newline
        for account in user_list:gmatch("[^\r\n]+") do
            table.insert(user_accounts, account)
        end
    end

    -- If no user accounts found, assume no selection and proceed to password fetch
    if #user_accounts == 0 then
        local get_password = module_settings.get_password

        -- Run `get_password` without account substitution
        local success, password, stderr = run_command(get_password)
        if success and type(password) == "string" and password ~= "" then
            window:perform_action(wezterm.action.SendString(password), pane)
        else
            window:toast_notification("Password Retrieval", "Failed to get password " .. stderr, nil, 3000)
        end
        return
    end

    -- Otherwise, use displaySelector to prompt user for account selection
    displaySelector(window, user_accounts, function(selected_account)
        -- Replace `%user` in `get_password` with selected account
        local get_password = module_settings.get_password:gsub("%%user", selected_account)

        local success, password, stderr = run_command(get_password)
        if success and type(password) == "string" and password ~= "" then
            window:perform_action(wezterm.action.SendString(password), pane)
        else
            window:toast_notification("Password Retrieval", "Failed to get password", nil, 3000)
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
