local wezterm = require("wezterm")

local M = { version = 1 }

local function extract_field(obj, path)
    local parts = {}
    for p in path:gmatch("[^.]+") do
        table.insert(parts, p)
    end
    local value = obj
    for _, part in ipairs(parts) do
        if type(value) == "table" then
            value = value[part]
        else
            return nil
        end
    end
    return value
end

local function displaySelector(window, user_accounts, callback)
    local choices = {}
    for _, account in ipairs(user_accounts) do
        table.insert(choices, { label = account.label, id = account.id })
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
local function run_command(cmd, ...)
    local success, output, stderr
    local args = { ... }

    if type(cmd) == "function" then
        -- Pass all additional arguments to the function
        success, output = pcall(cmd, table.unpack(args))
        stderr = nil
    else
        -- Make a copy of cmd to avoid modifying the original
        local cmd_str = cmd

        -- If arguments are provided, substitute `%user` in the command string
        if #args > 0 and type(args[1]) == "string" then
            cmd_str = cmd_str:gsub("%%user", args[1])
        end

        -- Execute the command string
        success, output, stderr = wezterm.run_child_process({"sh", "-c", cmd_str})
        if M.debug then
            wezterm.log_error("run_command() - cmd_str: " .. cmd_str)    
            wezterm.log_error("run_command() - output: " .. output)
            wezterm.log_error("run_command() - strderr: " .. stderr)    
        end

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

function M.exec_password_manager(window, pane, module_settings)
    local user_accounts = {}

    local get_userlist_def = module_settings.get_userlist
    local has_get_userlist = get_userlist_def ~= nil

    if has_get_userlist then
        local userlist_format = "text"
        local command = nil
        local id_path, label_path = nil, nil

        -- detect if get_userlist is a table
        if type(get_userlist_def) == "table" then
            userlist_format = get_userlist_def.format or "text"
            command = get_userlist_def.command
            id_path = get_userlist_def.id_path
            label_path = get_userlist_def.label_path
        else
            command = get_userlist_def
        end

        -- If the command is a function, set the format to "table"
        if type(command) == "function" then
            userlist_format = "table"
        end

        local user_list_output, err = run_command(command)
        if not user_list_output or user_list_output == "" then
            window:toast_notification("PassRelay Error", "Failed to get user list.\n\n" .. tostring(err), nil, module_settings.toast_time)
            wezterm.log_error("Failed to get user list: " .. tostring(err))
            has_get_userlist = false
        else
            if userlist_format == "json" then
                local decoded = nil
                local ok, json_err = pcall(function()
                    decoded = wezterm.json_parse(user_list_output)
                end)
                if not ok or type(decoded) ~= "table" then
                    window:toast_notification("PassRelay Error", "Invalid JSON user list format", nil, module_settings.toast_time)
                    wezterm.log_error("Invalid JSON user list format")
                    has_get_userlist = false
                else
                    for _, entry in ipairs(decoded) do
                        local uid = extract_field(entry, id_path)
                        local lbl = extract_field(entry, label_path)
                        if uid and lbl then
                            table.insert(user_accounts, {label = lbl, id = uid})
                        end
                    end
                end
            elseif userlist_format == "text" then
                for account in user_list_output:gmatch("[^\r\n]+") do
                    table.insert(user_accounts, {label = account, id = account})
                end
            elseif userlist_format == "table" and type(user_list_output) == "table" then
                for _, account in ipairs(user_list_output) do
                    table.insert(user_accounts, {label = account, id = account})
                end
            else
                window:toast_notification("PassRelay Error", "Unknown user list format: " .. tostring(userlist_format), nil, module_settings.toast_time)
                wezterm.log_error("Unknown user list format: " .. tostring(userlist_format))
                has_get_userlist = false
            end
        end
    end

    if not has_get_userlist or #user_accounts == 0 then
        local password, err = run_command(module_settings.get_password)
        if password then
            window:perform_action(wezterm.action.SendString(password), pane)
        else
            window:toast_notification("PassRelay Error", "Failed to get password.\n\n" .. tostring(err), nil, module_settings.toast_time)
            wezterm.log_error("Failed to get password: " .. tostring(err))
        end
        return
    end

    displaySelector(window, user_accounts, function(selected_account)
        local password, err = run_command(module_settings.get_password, selected_account)
        if password then
            window:perform_action(wezterm.action.SendString(password), pane)
        else
            window:toast_notification("PassRelay Error", "Failed to get password.\n\n" .. tostring(err), nil, module_settings.toast_time)
            wezterm.log_error("Failed to get password: " .. tostring(err))
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

    if module_settings.debug then
        wezterm.log_warn("enabling debug")
        M.debug = module_settings.debug
    end

    if not module_settings.toast_time then
        module_settings.toast_time = 3000
    end

    if not module_settings.hotkey or not module_settings.hotkey.key or not module_settings.hotkey.mods then
        module_settings.hotkey = { mods = 'CTRL', key = 'p' }
    end

    table.insert(config.keys, {
        mods = module_settings.hotkey.mods,
        key = module_settings.hotkey.key,
        action = wezterm.action_callback(function(window, pane)
            M.exec_password_manager(window, pane, module_settings)
        end),
    })
end

return M
