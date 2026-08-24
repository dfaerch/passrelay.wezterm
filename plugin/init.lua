local wezterm = require("wezterm")

local M = {}

-- Track last local echo failure time per window
local last_echo_fail = {}

local function extract_field(obj, path)
    for part in path:gmatch("[^.]+") do
        if type(obj) == "table" then
            obj = obj[part]
        else
            return nil
        end
    end
    return obj
end

local function is_placeholder_path(path)
    if path == "" then return false end
    local part_count = 0
    for part in path:gmatch("[^.]+") do
        if not part:match("^[%w_%-]+$") then return false end
        part_count = part_count + 1
    end
    return part_count > 0 and not path:match("^%.") and not path:match("%.$") and not path:match("%.%.")
end

local function interpolate_user(command, account)
    if not account then return command end

    local command_record = account.value
    if type(command_record) ~= "table" then
        command_record = { label = command_record, id = account.id }
    end

    local result = command:gsub("%%user", function()
        return tostring(account.id)
    end)
    local interpolation_error
    result = result:gsub("{([^{}]+)}", function(path)
        if not is_placeholder_path(path) then
            return "{" .. path .. "}"
        end

        local value = extract_field(command_record, path)
        if value == nil then
            interpolation_error = "Selected user has no field '" .. path .. "'"
            return ""
        end
        if type(value) ~= "string" and type(value) ~= "number" and type(value) ~= "boolean" then
            interpolation_error = "Selected user field '" .. path .. "' is not a scalar value"
            return ""
        end
        return tostring(value)
    end)

    if interpolation_error then return nil, interpolation_error end
    return result
end

local function detect_local_echo(window, pane, test_chars, sleep_ms)
    local before_line = pane:get_lines_as_text()
    window:perform_action(wezterm.action.SendString(test_chars), pane)
    wezterm.sleep_ms(sleep_ms)
    local after_line = pane:get_lines_as_text()
    window:perform_action(wezterm.action.SendKey({ key = "Backspace" }), pane)
    return after_line ~= before_line
end

local function displayUserSelector(window, user_accounts, callback)
    local choices = {}
    for index, account in ipairs(user_accounts) do
        table.insert(choices, { label = tostring(account.label), id = tostring(index) })
    end
    window:perform_action(
        wezterm.action.InputSelector {
            title = "Select Account",
            choices = choices,
            action = wezterm.action_callback(function(window, _, id)
                local account = id and user_accounts[tonumber(id)]
                if account then callback(account) end
            end),
        },
        window:mux_window():active_pane()
    )
end

local function run_command(cmd, ...)
    local args = { ... }
    local success, output, stderr
    if type(cmd) == "function" then
        success, output = pcall(cmd, table.unpack(args))
    else
        local cmd_str = cmd
        if #args > 0 and type(args[1]) == "string" then
            cmd_str = cmd_str:gsub("%%user", function() return args[1] end)
        end
        success, output, stderr = wezterm.run_child_process({ "sh", "-c", cmd_str })
        if M.debug then
            wezterm.log_error("run_command() - cmd_str: " .. cmd_str)
            wezterm.log_error("run_command() - output: " .. tostring(output))
            wezterm.log_error("run_command() - stderr: " .. tostring(stderr))
        end
    end
    if not success then
        wezterm.log_error("Command failed: " .. tostring(stderr or output or "Unknown error"))
        return nil, stderr or output or "Unknown error"
    end
    if type(output) == "string" and output == "" then
        return nil, "No output returned from command"
    end
    return output, nil
end

function M._continue_password(window, pane, module_settings, bypass_local_echo_check)
    bypass_local_echo_check = bypass_local_echo_check or false

    local function send_password(account)
        local password, err
        if type(module_settings.get_password) == "function" then
            if account then
                password, err = run_command(module_settings.get_password, account.value)
            else
                password, err = run_command(module_settings.get_password)
            end
        else
            local command
            command, err = interpolate_user(module_settings.get_password, account)
            if command then password, err = run_command(command) end
        end
        if password then
            window:focus()
            window:perform_action(wezterm.action.SendString(password), pane)
        else
            window:toast_notification("PassRelay Error", "Failed to get password.\n\n" .. tostring(err), nil, module_settings.toast_time)
            wezterm.log_error("Failed to get password: " .. tostring(err))
        end
    end

    local user_accounts = {}
    local get_userlist_def = module_settings.get_userlist
    local has_get_userlist = get_userlist_def ~= nil

    if has_get_userlist then
        local userlist_format = "text"
        local command = nil
        local id_path, label_path = nil, nil

        if type(get_userlist_def) == "table" then
            userlist_format = get_userlist_def.format or "text"
            command = get_userlist_def.command
            id_path = get_userlist_def.id_path
            label_path = get_userlist_def.label_path
        else
            command = get_userlist_def
        end

        if type(command) == "function" then
            userlist_format = "table"
        end

        local user_list_output, err = run_command(command)
        if not user_list_output or user_list_output == "" then
            wezterm.log_error("Failed to get user list: " .. tostring(err))
            has_get_userlist = false
        else
            if userlist_format == "json" then
                local decoded = nil
                local ok = pcall(function() decoded = wezterm.json_parse(user_list_output) end)
                if ok and type(decoded) == "table" then
                    for _, entry in ipairs(decoded) do
                        local uid = extract_field(entry, id_path)
                        local lbl = extract_field(entry, label_path)
                        if uid and lbl then
                            table.insert(user_accounts, { label = lbl, id = uid, value = entry })
                        end
                    end
                else
                    wezterm.log_error("Invalid JSON user list format")
                    has_get_userlist = false
                end
            elseif userlist_format == "text" then
                for account in user_list_output:gmatch("[^\r\n]+") do
                    table.insert(user_accounts, { label = account, id = account, value = account })
                end
            elseif userlist_format == "table" and type(user_list_output) == "table" then
                for _, account in ipairs(user_list_output) do
                    if type(account) == "string" then
                        table.insert(user_accounts, { label = account, id = account, value = account })
                    elseif type(account) == "table" and account.label ~= nil and account.id ~= nil then
                        table.insert(user_accounts, { label = account.label, id = account.id, value = account })
                    else
                        wezterm.log_error("Ignoring invalid user list entry: expected a string or a table with label and id")
                    end
                end
            else
                wezterm.log_error("Unknown user list format: " .. tostring(userlist_format))
                has_get_userlist = false
            end
        end
    end

    -- Dont display user selector
    if not has_get_userlist or #user_accounts == 0 then
        send_password(nil)
    else
        displayUserSelector(window, user_accounts, function(account)
          if not bypass_local_echo_check and module_settings.detect_local_echo_after_userlist and
             detect_local_echo(window, pane,
                 module_settings.detect_local_echo_chars,
                 module_settings.detect_local_echo_time
             )
          then
            window:toast_notification("PassRelay Error", "Local echo detected in terminal. Bailing.",
              nil,
              module_settings.toast_time
            )
            wezterm.log_warn("Local echo detected. Not sending password.")
            return
          end
          send_password(account)
        end)
   end
end

function M.exec_password_manager(window, pane, module_settings)
  if module_settings.detect_local_echo_before_userlist then
    local win_id = tostring(window:window_id())
    local now = tonumber(wezterm.time.now():format("%s"))
    local echo = detect_local_echo(window, pane,
      module_settings.detect_local_echo_chars,
      module_settings.detect_local_echo_time)

    if echo then
      if last_echo_fail[win_id] and (now - last_echo_fail[win_id] < 3) then
        window:perform_action(
          wezterm.action.Confirmation {
            message = "Local echo detected. Paste password anyway?",
            action = wezterm.action_callback(function(window, pane)
              wezterm.log_warn("User forced continue, despite local echo.")
              M._continue_password(window, pane, module_settings, true)
            end),
            cancel = wezterm.action_callback(function(window, pane)
              window:toast_notification("PassRelay", "Aborted", nil, 2000)
            end),
          },
          pane
        )
        return
      else
        last_echo_fail[win_id] = now
        window:toast_notification("PassRelay Error", "Local echo detected in terminal. Bailing.\nTry again within 3 seconds to force.",
          nil,
          module_settings.toast_time
        )
        wezterm.log_warn("Local echo detected. Not sending password.")
        return
      end
    end
  end

  M._continue_password(window, pane, module_settings)
end


--- Applies the passrelay configuration to WezTerm.
--
-- @param config table The WezTerm config table.
-- @param module_settings table Module settings.
function M.apply_to_config(config, module_settings)
    if not module_settings or not module_settings.get_password then
        wezterm.log_error("module_settings are missing required setting get_password")
        return
    end

    config.keys = config.keys or {}

    if module_settings.debug then
        wezterm.log_warn("enabling debug")
        M.debug = module_settings.debug
    end

    module_settings.toast_time = module_settings.toast_time or 3000
    module_settings.hotkey = module_settings.hotkey or { mods = 'CTRL', key = 'p' }
    module_settings.detect_local_echo_chars = module_settings.detect_local_echo_chars or ":"
    module_settings.detect_local_echo_time  = module_settings.detect_local_echo_time or 200

    -- Local echo detection settings. Default to checking twice: before userlist selection and after.
    module_settings.detect_local_echo_before_userlist = module_settings.detect_local_echo_before_userlist ~= false -- default to true
    module_settings.detect_local_echo_after_userlist  = module_settings.detect_local_echo_after_userlist  ~= false -- default to true

    -- If detect_local_echo is defined, it overrides both
    if module_settings.detect_local_echo ~= nil then
      module_settings.detect_local_echo_before_userlist = module_settings.detect_local_echo
      module_settings.detect_local_echo_after_userlist  = module_settings.detect_local_echo
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
