local wezterm = require("wezterm")

local M = {}

-- Track last local echo failure time per window
local last_echo_fail = {}


------------------------
-- PassRelay update availability check
------------------------

local DEFAULT_UPDATE_BRANCH = "v1"
local PASSRELAY_PLUGIN_URL = "https://github.com/dfaerch/passrelay.wezterm"
local UPDATE_STATE_DIR = ".data"
local UPDATE_STATE_FILE_PREFIX = "update-state-"
local SECONDS_PER_HOUR = 60 * 60
local SECONDS_PER_DAY = 24 * SECONDS_PER_HOUR
local update_checks_in_progress = {}

local function trim(value)
    return value and value:match("^%s*(.-)%s*$") or ""
end

local function state_filename(branch)
    return UPDATE_STATE_FILE_PREFIX .. branch:gsub("[^%w%._-]", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end

local function state_path(plugin_dir, branch)
    return plugin_dir .. "/" .. UPDATE_STATE_DIR .. "/" .. state_filename(branch)
end

local function read_update_state(plugin_dir, branch)
    local state = {}
    local file = io.open(state_path(plugin_dir, branch), "r")
    if not file then return state end

    for line in file:lines() do
        local key, value = line:match("^([a-z_]+)=(.*)$")
        if key then state[key] = value end
    end
    file:close()
    return state
end

local function write_update_state(plugin_dir, branch, state)
    local created = wezterm.run_child_process({ "mkdir", "-p", plugin_dir .. "/" .. UPDATE_STATE_DIR })
    if not created then
        wezterm.log_warn("PassRelay update check: unable to create state directory")
        return false
    end

    local file, err = io.open(state_path(plugin_dir, branch), "w")
    if not file then
        wezterm.log_warn("PassRelay update check: unable to save state: " .. tostring(err))
        return false
    end

    for _, key in ipairs({ "last_check", "remote_hash", "first_seen", "first_notified", "final_notification_sent" }) do
        if state[key] then file:write(key .. "=" .. state[key] .. "\n") end
    end
    file:close()
    return true
end

local function passrelay_plugin_dir()
    for _, plugin in ipairs(wezterm.plugin.list()) do
        local url = (plugin.url or ""):gsub("/+$", ""):gsub("%.git$", "")
        if url == PASSRELAY_PLUGIN_URL then return plugin.plugin_dir end
    end
end

local function should_check_for_update(state, now, interval)
    local last_check = tonumber(state.last_check) or 0
    local first_seen = tonumber(state.first_seen)
    if first_seen and now - first_seen < 7 * SECONDS_PER_DAY then
        interval = 8 * SECONDS_PER_HOUR
    end
    return now - last_check >= interval
end

local function check_for_update(window, module_settings, plugin_dir)
    local now = os.time()
    local state = read_update_state(plugin_dir, module_settings.update_check_branch)

    local local_ok, local_hash, local_stderr = wezterm.run_child_process({ "git", "-C", plugin_dir, "rev-parse", "HEAD" })
    if not local_ok then
        wezterm.log_warn("PassRelay update check: unable to read local revision: " .. trim(local_stderr or local_hash or "unknown error"))
        return
    end

    local remote_ok, remote_output, remote_stderr = wezterm.run_child_process({
        "git", "-C", plugin_dir, "ls-remote", "origin", "refs/heads/" .. module_settings.update_check_branch,
    })
    local remote_hash, remote_branch
    if remote_output then
        remote_hash, remote_branch = remote_output:match("^([0-9a-fA-F]+)[ \t]+refs/heads/(.-)%s*$")
    end
    if not remote_ok then
        wezterm.log_warn(
            "PassRelay update check: unable to query origin/" .. module_settings.update_check_branch
            .. ": " .. trim(remote_stderr or remote_output or "unknown error")
        )
        return
    end
    if not remote_hash or remote_branch ~= module_settings.update_check_branch then
        wezterm.log_warn(
            "PassRelay update check: unexpected ls-remote response for origin/" .. module_settings.update_check_branch
            .. ": " .. trim(remote_output or "no output")
        )
        return
    end

    local local_revision = trim(local_hash)
    if state.remote_hash ~= remote_hash then
        state.remote_hash = remote_hash
        state.first_seen = tostring(now)
        state.first_notified = nil
        state.final_notification_sent = nil
    end
    state.last_check = tostring(now)

    if remote_hash ~= local_revision then
        if not state.first_notified then
            window:toast_notification("PassRelay", "A PassRelay update is available.", nil, module_settings.toast_time)
            state.first_notified = tostring(now)
        elseif not state.final_notification_sent and now - (tonumber(state.first_seen) or now) >= 8 * SECONDS_PER_DAY then
            window:toast_notification(
                "PassRelay",
                "PassRelay update still available. You won't be notified about this specific update again.",
                nil,
                module_settings.toast_time
            )
            state.final_notification_sent = "true"
        end
    end

    write_update_state(plugin_dir, module_settings.update_check_branch, state)
end

local function schedule_update_check(window, module_settings)
    local plugin_dir = passrelay_plugin_dir()
    if not plugin_dir or update_checks_in_progress[plugin_dir] then return end

    local state = read_update_state(plugin_dir, module_settings.update_check_branch)
    if not should_check_for_update(state, os.time(), module_settings.update_check_interval) then return end

    update_checks_in_progress[plugin_dir] = true
    wezterm.time.call_after(0, function()
        check_for_update(window, module_settings, plugin_dir)
        update_checks_in_progress[plugin_dir] = nil
    end)
end

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
    for _, account in ipairs(user_accounts) do
        table.insert(choices, { label = account.label, id = account.id })
    end
    window:perform_action(
        wezterm.action.InputSelector {
            title = "Select Account",
            choices = choices,
            action = wezterm.action_callback(function(window, _, id)
                if id then callback(id) end
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
            cmd_str = cmd_str:gsub("%%user", args[1])
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

    local function send_password(id)
        local password, err = run_command(module_settings.get_password, id)
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
                            table.insert(user_accounts, { label = lbl, id = uid })
                        end
                    end
                else
                    wezterm.log_error("Invalid JSON user list format")
                    has_get_userlist = false
                end
            elseif userlist_format == "text" then
                for account in user_list_output:gmatch("[^\r\n]+") do
                    table.insert(user_accounts, { label = account, id = account })
                end
            elseif userlist_format == "table" and type(user_list_output) == "table" then
                for _, account in ipairs(user_list_output) do
                    table.insert(user_accounts, { label = account, id = account })
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
        displayUserSelector(window, user_accounts, function(id)
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
          send_password(id)
        end)
   end
end

function M.exec_password_manager(window, pane, module_settings)
  if module_settings.check_for_updates then
    schedule_update_check(window, module_settings)
  end

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
        wezterm.toast_notification("Configuration Error", "module_settings are missing required get_password", nil, 5000)
        return
    end

    config.keys = config.keys or {}

    if module_settings.debug then
        wezterm.log_warn("enabling debug")
        M.debug = module_settings.debug
    end

    module_settings.toast_time = module_settings.toast_time or 3000
    module_settings.check_for_updates = module_settings.check_for_updates ~= false
    module_settings.update_check_interval = module_settings.update_check_interval or SECONDS_PER_DAY
    module_settings.update_check_branch = module_settings.update_check_branch or DEFAULT_UPDATE_BRANCH
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
