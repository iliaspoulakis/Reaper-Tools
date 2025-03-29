--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 2.0.0
  @about Simple utility to update REAPER to the latest version
  @changelog
    - Windows: Use curl to download (if available on system)
    - Windows: Give reaper 5-10 seconds to close based on how many FX are loaded
    - Show state for toolbar buttons
    - Improve detecting when installation is cancelled (fix issue with CSI)
    - Find and open the correct changelog file available on Landoleet
]]

-- App version & platform architecture
local platform = reaper.GetOS()
local app = reaper.GetAppVersion()
local curr_version = app:gsub('/.-$', '')
local main_version, dev_version, new_version, install_version

local arch = app:match('/(.-)$')
if arch then
    if arch:match('win') then arch = arch:match('64') and 'x64' or arch end
    if arch:match('OSX') then
        arch = arch:match('64') and 'x86_64' or arch
        arch = arch:match('32') and 'i386' or arch
    end
    if arch:match('macOS') then arch = arch:match('arm') and 'arm64' or arch end
    if arch:match('linux') then
        arch = arch:match('64') and 'x86_64' or arch
        arch = arch:match('686') and 'i686' or arch
        arch = arch:match('arm') and 'armv7l' or arch
        arch = arch:match('aarch') and 'aarch64' or arch
    end
end

local version = tonumber(app:match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(1) end

-- Links to REAPER websites
local main_dlink = 'https://www.reaper.fm/download.php'
local dev_dlink = 'https://www.landoleet.org/'
local old_dlink = 'https://www.landoleet.org/old/'
local main_changelog = 'https://www.reaper.fm/whatsnew.txt'
local dev_changelog

-- Paths
local separator = platform:match('Win') and '\\' or '/'
local install_path = reaper.GetExePath()
local res_path = reaper.GetResourcePath()
local ini_file = reaper.get_ini_file()
local scripts_path = res_path .. separator .. 'Scripts' .. separator
local tmp_path, step_path, main_path, dev_path, cmd_log_path
local user_log_path = res_path .. separator .. 'update-utility.log'
local startup_log_path = res_path .. separator .. 'update-utility-startup.log'
local is_portable = res_path == install_path

-- Download variables
local dl_cmd, browser_cmd, user_dlink, dfile_name

-- GUI variables
local m_x, m_y
local step = 0
local direction = 1
local opacity = 0.65
local hover_cnt = 0
local click = {}
local is_main_clicked = false
local show_buttons = false
local task = 'Initializing...'
local title = 'REAPER Update Utility'
local font_factor = platform:match('Win') and 1.25 or 1

local main_list = {}
local dev_list = {}

local hook_cmd = ''
local debug_str = ''

local startup_mode = false
local settings

function print(msg, force)
    if settings.debug_console.enabled or force then
        reaper.ShowConsoleMsg(tostring(msg) .. '\n')
    end
    if settings.debug_file.enabled then
        local user_log_file = io.open(user_log_path, 'a')
        if user_log_file then
            user_log_file:write(msg, '\n')
            user_log_file:close()
        else
            local msg = 'Warning: Writing to log file failed. Already in use!\n'
            reaper.ShowConsoleMsg(msg)
        end
    end
    debug_str = debug_str .. tostring(msg) .. '\n'
end

function ExecProcess(cmd, timeout)
    if platform:match('Win') then
        cmd = 'cmd.exe /Q /C "' .. cmd .. '"'
    elseif platform:match('OSX') or platform:match('macOS') then
        cmd = '/bin/sh -c \'' .. cmd .. '\''
    else
        cmd = '/bin/sh -c "' .. cmd .. '"'
    end
    local ret = reaper.ExecProcess(cmd, timeout or -2)
    print('\nExecuting command:\n' .. cmd)
    local exit_code
    if ret then
        exit_code = tonumber(ret:match('^%d+'))
        -- Remove exit code (first line)
        ret = ret:gsub('^.-\n', '')
        -- Remove Windows network drive error (fix by jkooks)
        ret = ret:gsub('.+CMD%.EXE.-UNC.+%.', '')
        -- Remove all newlines
        ret = ret:gsub('[\r\n]', '')
        if ret ~= '' then print('\nReturn value:\n' .. ret) end
    end
    return ret, exit_code
end

function ExecInstall(install_cmd)
    if settings.dialog_install.enabled then
        local msg =
        'Reaper has to close for the installation process to begin.\n\z
        Should you have unsaved projects, you will be prompted to save them.\n\z
        After the installation is complete, reaper will restart automatically.\n\n\z
        Quit reaper and proceed with installation of v%s?'
        local ret = reaper.MB(msg:format(install_version), title, 4)
        if ret == 7 then
            print('User exit...')
            return
        end
    end

    -- Save last active project in extstate (restore on startup)
    local _, fn = reaper.EnumProjects(-1)
    if fn ~= '' then
        -- Check reaper preference if user wants to open last active project
        local ret, setting = reaper.get_config_var_string('loadlastproj')
        local setting = ret and tonumber(setting) & 7 or 0
        if setting < 2 then
            reaper.SetExtState(title, 'last_proj', fn, true)
        end
    end

    -- Get current state count of open projects
    local state_cnts = {}
    local p = 0
    repeat
        local proj = reaper.EnumProjects(p)
        if proj then state_cnts[proj] = reaper.GetProjectStateChangeCount(proj) end
        p = p + 1
    until not proj

    -- File: Close all projects
    reaper.Main_OnCommand(40886, 0)

    -- Check if user cancelled the dialog. If so, state count doesn't change
    local curr_proj = reaper.EnumProjects(-1)
    local state_cnt = reaper.GetProjectStateChangeCount(curr_proj)
    local did_cancel = state_cnt == state_cnts[curr_proj]

    if not did_cancel then
        if reaper.file_exists(scripts_path .. '__update.lua') then
            reaper.SetExtState(title, 'lua_hook', '1', true)
        end
        -- In Windows execute after quitting to avoid error dialog
        if not platform:match('Win') then ExecProcess(install_cmd) end
        -- File: Quit REAPER
        reaper.Main_OnCommand(40004, 0)
        if platform:match('Win') then ExecProcess(install_cmd) end
    else
        reaper.MB('\nInstallation cancelled!\n ', title, 0)
    end
end

function GetFilePattern()
    local file_pattern
    if platform:match('Win') then
        file_pattern = (arch and '_' .. arch or '') .. '%-install%.exe'
    end
    if platform:match('OSX') then file_pattern = '%d%a?_' .. arch .. '%.dmg' end
    if platform:match('macOS') then file_pattern = '_universal%.dmg' end
    if platform:match('Other') then
        file_pattern = '_linux_' .. arch .. '%.tar%.xz'
    end
    return 'href="([^_"]-reaper[^_"]-' .. file_pattern .. ')"'
end

function ParseDownloadLink(file, dlink)
    local file_pattern = GetFilePattern()
    -- Match first file download link
    for line in file:lines() do
        local file_name = line:match(file_pattern)
        if file_name then
            dlink = dlink:match('(.-%..-%..-/)')
            return dlink .. file_name
        end
    end
end

function ParseDevChangelogLink(file, vs)
    for line in file:lines() do
        if line:match('whatsnew') then
            if vs:match('rc') then
                if line:match('whatsnew-rc.txt') then
                    return 'https://www.landoleet.org/whatsnew-rc.txt'
                end
            end
            if line:match('whatsnew-dev.txt') then
                return 'https://www.landoleet.org/whatsnew-dev.txt'
            elseif line:match('whatsnew.txt') then
                return 'https://www.landoleet.org/whatsnew.txt'
            end
        end
    end
    return 'https://www.landoleet.org/whatsnew.txt'
end

function ParseHistory(file, dlink)
    local file_pattern = GetFilePattern()
    -- Find matching file download links
    for line in file:lines() do
        local file_name = line:match(file_pattern)
        if file_name and file_name:match('reaper') then
            local link = dlink .. file_name
            local main_match = file_name:match('reaper(%d+%a*)_')
            -- Divide matches into separate lists for main and dev releases
            if main_match then
                main_match = main_match:gsub('^(%d)', '%1.')
                if main_match ~= main_version then
                    main_list[#main_list + 1] = {
                        version = main_match,
                        link = link,
                    }
                end
            else
                local dev_match = file_name:match('reaper(.-)_')
                dev_match = dev_match:gsub('^(%d)', '%1.')
                if dev_match ~= dev_version then
                    dev_list[#dev_list + 1] = {version = dev_match, link = link}
                end
            end
        end
    end
end

local function SortByAttributeName(array, attribute, is_descending)
    local function Format(d) return ('%03d%s'):format(#d, d) end
    local function Compare(a, b)
        a = a[attribute]
        b = b[attribute]
        local a_num = tonumber(a)
        local b_num = tonumber(b)
        if a_num and b_num then
            if is_descending then return a_num < b_num end
            return a_num > b_num
        end
        local a_str = tostring(a):gsub('%d+', Format)
        local b_str = tostring(b):gsub('%d+', Format)
        if is_descending then return a_str < b_str end
        return a_str > b_str
    end
    table.sort(array, Compare)
end

function ShowHistoryMenu()
    local list = is_main_clicked and main_list or dev_list
    local prev_group
    local menu_list = {}
    local group_list = {}

    SortByAttributeName(list, 'version', true)

    -- Reorder list for showing in menu (reverse order)
    for i = #list, 1, -1 do
        local group = list[i].version:match('^[%d.]+')
        if prev_group and group ~= prev_group or i == 1 then
            -- Create submenus
            if #group_list > 1 or not is_main_clicked then
                -- Move dev versions to the top
                local offs = 1
                for n = 1, #group_list do
                    if group_list[n].version:match('dev') then
                        local val = group_list[n]
                        table.remove(group_list, n)
                        table.insert(group_list, offs, val)
                        offs = offs + 1
                    end
                end
                -- Mark first and last entry (for menu creation)
                group_list[1].is_first = true
                group_list[#group_list].is_last = true
            end
            menu_list[#menu_list + 1] = group_list
            group_list = {}
        end
        group_list[#group_list + 1] = list[i]
        group_list.group = group
        prev_group = group
    end

    SortByAttributeName(menu_list, 'group', false)

    local flat_menu_list = {}
    for _, group in ipairs(menu_list) do
        for _, item in ipairs(group) do
            flat_menu_list[#flat_menu_list + 1] = item
        end
    end

    -- Create string to use with showmenu function
    local menu = ''
    for i, item in ipairs(flat_menu_list) do
        local sep = i == 1 and '' or '|'
        if item.is_first then
            local group = item.version:match('^[%d.]+')
            sep = sep .. '>' .. group .. '|'
        end
        if item.is_last then sep = sep .. '<' end
        menu = menu .. sep .. item.version
    end

    -- Determine where to show the menu
    gfx.x = gfx.w * (is_main_clicked and 1 or 4) / 7
    gfx.y = gfx.h * 3 / 4 + 4

    local ret = gfx.showmenu(menu)
    if ret > 0 then
        user_dlink = flat_menu_list[ret].link
        install_version = flat_menu_list[ret].version
        ExecProcess('echo download > ' .. step_path)
        show_buttons = false
    end
end

function CheckStartupHook()
    local _, _, _, cmd = reaper.get_action_context()
    local script_id = reaper.ReverseNamedCommandLookup(cmd)
    local startup_script_path = scripts_path .. '__startup.lua'

    if reaper.file_exists(startup_script_path) then
        local file = io.open(startup_script_path, 'r')
        if not file then return false end
        local content = file:read('*a')
        file:close()

        -- Find line that contains script_id (also next line if available)
        local pattern = '[^\n]+' .. script_id .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        -- Check if line exists and is not commented out
        if s and e then
            local hook = content:sub(s, e)
            local comment = hook:match('[^\n]*%-%-[^\n]*reaper%.Main_OnCommand')
            if not comment then return true end
        end
    end
    return false
end

function SetStartupHook(is_enabled)
    local _, _, _, cmd = reaper.get_action_context()
    local script_id = reaper.ReverseNamedCommandLookup(cmd)
    local startup_script_path = scripts_path .. '__startup.lua'

    local content
    local hook_exists = false

    -- Check startup script for existing hook
    if reaper.file_exists(startup_script_path) then
        local file = io.open(startup_script_path, 'r')
        if not file then return end
        content = file:read('*a')
        file:close()

        -- Find line that contains script_id (also next line if available)
        local pattern = '[^\n]+' .. script_id .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        -- Add/remove comment from existing startup hook
        if s and e then
            local hook = content:sub(s, e)
            hook_exists = true
            local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
            hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)

            content = content:sub(1, s - 1) .. hook .. content:sub(e + 1)

            file = io.open(startup_script_path, 'w')
            if not file then
                reaper.MB('Could not write to file', 'Error', 0)
                return
            end
            file:write(content)
            file:close()
        end
    end

    -- Create startup hook
    if is_enabled and not hook_exists then
        local hook =
        '-- Start script: REAPER Update Utility (check for new versions)\n\z
        local update_utility_cmd = \'_%s\'\n\z
        reaper.Main_OnCommand(reaper.NamedCommandLookup(update_utility_cmd), 0)\n\n'

        local file = io.open(startup_script_path, 'w')
        if not file then return end
        file:write(hook:format(script_id) .. (content or ''))
        file:close()
    end
end

function LoadSettings()
    local show_install_dialog = platform:match('OSX') or platform:match('macOS')
    show_install_dialog = show_install_dialog or is_portable
    local default_settings = {
        ['startup_hook'] = {idx = 1, default = false},
        ['force_startup'] = {idx = 2, default = false},
        ['notify_main'] = {idx = 3, default = true},
        ['notify_dev'] = {idx = 4, default = true},
        ['notify_rc'] = {idx = 5, default = true},
        ['dialog_install'] = {idx = 6, default = show_install_dialog},
        ['dialog_dl_cancel'] = {idx = 7, default = true},
        ['debug_startup'] = {idx = 8, default = false},
        ['debug_console'] = {idx = 9, default = false},
        ['debug_file'] = {idx = 10, default = false},
    }
    for key, setting in pairs(default_settings) do
        local ret = reaper.GetExtState(title, key)
        setting.enabled = ret == 'true' or ret == '' and setting.default
    end
    return default_settings
end

function ShowSettingsMenu()
    -- Check for script startup hook each time menu is clicked
    settings.startup_hook.enabled = CheckStartupHook()

    local state = {}
    for key, setting in pairs(settings) do
        state[setting.idx] = {key = key, enabled = setting.enabled}
    end

    local menu =
    '>Startup notifications|%1Run script on startup||%2Only show window when \z
    a new version is available (notifications)|>Check for...|%3Main|%4Dev|<%5RC|<\z
    |>Confirmation dialogs|%6Before installing|<%7When cancelling download\z
    |>Debugging|%8Dump startup log|%9Log to console|%10Log to file'
    local function substitute(s)
        return state[tonumber(s)].enabled and '!' or ''
    end
    menu = menu:gsub('%%(%d+)', substitute)

    local ret = gfx.showmenu(menu)

    if ret > 0 then
        local enabled = not state[ret].enabled
        reaper.SetExtState(title, state[ret].key, tostring(enabled), true)
        settings[state[ret].key].enabled = enabled

        -- Make sure user can't unselect all notification options
        if not settings.notify_dev.enabled and not settings.notify_rc.enabled then
            reaper.SetExtState(title, 'notify_main', 'true', true)
            settings.notify_main.enabled = true
        end

        if ret == 1 then SetStartupHook(enabled) end

        if ret == 8 then
            reaper.SetExtState(title, 'debug_startup', 'false', true)
            settings.debug_startup.enabled = false

            local startup_log_file = io.open(startup_log_path, 'w')
            if not startup_log_file then return end
            startup_log_file:write(debug_str, '\n')
            startup_log_file:close()

            local msg = 'Created new file: update-utility-startup.log\n\n\z
                Please attach this file to your forum post. It will be automatically \z
                deleted the next time this script runs. Thank you for testing!\n\n\z
                The containing folder (your resource directory) will \z
                now automatically open in explorer/finder\n '
            reaper.MB(msg, title, 0)
            -- Show REAPER resource path in explorer
            reaper.Main_OnCommand(40027, 0)
        end

        if ret == 10 then
            os.remove(user_log_path)
            if enabled then
                local user_log_file = io.open(user_log_path, 'a')
                if not user_log_file then return end
                user_log_file:write(debug_str, '\n')
                user_log_file:close()
                local msg = ' \nLogging to file is now enabled!\n\n\z
                    You can find the file \'update-utility.log\' in your resource \z
                    directory:\n--> Options --> Show REAPER resource path...\n\n\z
                    Open resource directory now?\n '
                local response = reaper.MB(msg, title, 4)
                if response == 6 then
                    -- Show REAPER resource path in explorer
                    reaper.Main_OnCommand(40027, 0)
                end
            else
                reaper.MB('Removed log file. Thank you for testing!', title, 0)
            end
        end
    end
end

function DrawTask()
    direction = opacity > 0.65 and -1 or direction
    direction = opacity < 0.35 and 1 or direction
    opacity = opacity + 0.01 * direction
    gfx.set(opacity)
    gfx.setfont(1, '', 15 * font_factor)
    local w, h = gfx.measurestr(task)
    gfx.x = math.floor((gfx.w - w) / 2)
    gfx.y = math.floor((gfx.h - h) / 2.1)
    gfx.drawstr(task, 1)
end

function DrawSettingsButton()
    gfx.set(0.40)

    local is_hover = m_x >= 2 and m_x <= 20 and m_y >= 2 and m_y <= 20

    if is_hover then
        gfx.set(0.52)
        hover_cnt = hover_cnt + 1
        local tooltip = 'Show menu'
        local tooltip_x, tooltip_y = reaper.GetMousePosition()
        if hover_cnt > 12 then
            reaper.TrackCtl_SetToolTip(tooltip, tooltip_x, tooltip_y, true)
        end
    end

    -- Left click
    if is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
        click = {action = 'menu'}
    end

    -- Left click release
    if click.action == 'menu' and gfx.mouse_cap == 0 then
        gfx.x = 4
        gfx.y = 4
        if is_hover then ShowSettingsMenu() end
        click = {}
    end

    gfx.rect(6, 06, 17, 3)
    gfx.rect(6, 11, 17, 3)
    gfx.rect(6, 16, 17, 3)
end

function DrawVersionHistoryButton(x, y, is_main)
    local is_hover = m_x >= x - 10 and m_x <= x + 10 and
        m_y >= y - 10 and m_y <= y + 10
    local is_clicked = click.type == is_main and click.action == 'show_hist'

    -- Hover
    gfx.set(0.57)
    if is_hover then
        gfx.set(0.72)
        hover_cnt = hover_cnt + 1
        local tooltip = 'List old versions'
        local tooltip_x, tooltip_y = reaper.GetMousePosition()
        if hover_cnt > 12 then
            reaper.TrackCtl_SetToolTip(tooltip, tooltip_x, tooltip_y, true)
        end
    end

    -- Left click
    if is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
        click = {type = is_main, action = 'show_hist'}
    end

    --  Left click release
    if gfx.mouse_cap == 0 and is_clicked then
        if is_hover then
            is_main_clicked = is_main
            if #main_list > 0 and #dev_list > 0 then
                reaper.defer(ShowHistoryMenu)
            else
                show_buttons = false
                task = 'Fetching old versions...'
                ExecProcess('echo get_history > ' .. step_path)
            end
        end
        click = {}
    end

    -- Draw
    gfx.circle(x, y, 8.3, 0)
    gfx.line(x, y, x, y - 4)
    gfx.line(x, y, x + 3, y + 3)
end

function DrawChangelogButton(x, y, is_main)
    local is_hover = m_x >= x - 10 and m_x <= x + 10 and
        m_y >= y - 10 and m_y <= y + 10
    local is_clicked = click.type == is_main and click.action == 'show_cl'

    -- Hover
    gfx.set(0.57)
    if is_hover then
        gfx.set(0.72)
        hover_cnt = hover_cnt + 1
        local tooltip = 'Open changelog in web browser'
        local tooltip_x, tooltip_y = reaper.GetMousePosition()
        if hover_cnt > 12 then
            reaper.TrackCtl_SetToolTip(tooltip, tooltip_x, tooltip_y, true)
        end
    end

    -- Left click
    if is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
        click = {type = is_main, action = 'show_cl'}
    end

    -- Left click release
    if gfx.mouse_cap == 0 and is_clicked then
        if is_hover and (is_main or dev_version ~= 'none') then
            show_buttons = false
            task = 'Checking forum for post...'
            local type = is_main and 'main' or 'dev'
            ExecProcess('echo get_' .. type .. '_changelog > ' .. step_path)
        end
        click = {}
    end

    -- Draw
    gfx.circle(x, y, 8, 1, 1)
    gfx.circle(x + 1, y, 8, 1, 1)
    gfx.set(0.13)
    gfx.setfont(0)
    local info_text = 'i'
    local i_w, i_h = gfx.measurestr(info_text)
    gfx.x = x - math.floor(i_w / 2) + 1
    gfx.y = y - math.floor(i_h / 2) + 1
    gfx.drawstr(info_text, 1)
end

function DrawInstallButton(x, y, w, h, version, dlink)
    local is_new = version == new_version
    local is_main = version == main_version
    local is_installed = version == curr_version
    local is_hover = m_x >= x and m_x <= x + w and m_y >= y and m_y <= y + h

    gfx.set(0.5)

    -- State
    gfx.setfont(1, '', 14 * font_factor, string.byte('b'))
    local branch = is_main and 'MAIN' or 'PRE-RELEASE'
    local t_w, t_h = gfx.measurestr(branch)
    gfx.x = math.floor(x + gfx.w / 7 - t_w / 2) + 1
    gfx.y = math.floor(y + h) + 13
    gfx.drawstr(branch, 1)

    gfx.set(0.6)

    if is_new then gfx.set(1.15 * opacity, 0.92 * opacity, 0.55 * opacity) end

    if is_hover then gfx.set(0.72) end

    if is_installed then gfx.set(0.1, 0.65, 0.5) end

    -- Button left click
    if not is_installed and is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
        click = {type = is_main, action = 'install'}
    end

    -- Button left click release
    if click.type == is_main and click.action == 'install' and gfx.mouse_cap ==
        0 then
        if is_hover and dlink ~= '' then
            user_dlink = dlink
            install_version = version
            ExecProcess('echo download > ' .. step_path)
            show_buttons = false
        end
        click = {}
    end

    -- Button hover
    if is_hover then
        hover_cnt = hover_cnt + 1
        local tooltip = 'Install v' .. version
        local tooltip_x, tooltip_y = reaper.GetMousePosition()
        if hover_cnt > 12 then
            reaper.TrackCtl_SetToolTip(tooltip, tooltip_x, tooltip_y, true)
        end
    end

    -- Border
    gfx.roundrect(x, y, w, h, 4, 1)
    gfx.roundrect(x + 1, y, w, h, 4, 1)
    gfx.roundrect(x, y + 1, w, h, 4, 1)

    -- Version
    gfx.setfont(1, '', 30 * font_factor, string.byte('b'))
    local version_text = version:match('^([%d%.]+)') or 'none'
    t_w, t_h = gfx.measurestr(version_text)
    gfx.x = math.floor(x + gfx.w / 7 - t_w / 2) + 1
    gfx.y = math.floor(gfx.h / 2 - t_h / 2)
    gfx.drawstr(version_text, 1)

    -- Subversion
    gfx.setfont(1, '', 15 * font_factor, string.byte('i'))
    local subversion_text = version:match('[%d%.]+(.-)$') or ''
    t_w = gfx.measurestr(subversion_text)
    gfx.x = math.floor(x + gfx.w / 7 - t_w / 2) + 1
    gfx.y = math.floor(gfx.y + t_h) + 5
    gfx.drawstr(subversion_text, 1)
end

function DrawGUI()
    if gfx.mouse_x ~= m_x or gfx.mouse_y ~= m_y then
        hover_cnt = 0
        reaper.TrackCtl_SetToolTip('', 0, 0, true)
    end
    m_x = gfx.mouse_x
    m_y = gfx.mouse_y

    task = ''
    local x = gfx.w // 7
    local y = gfx.h // 4
    local w = gfx.w // 7 * 2
    local h = gfx.h // 2

    DrawVersionHistoryButton(x + w // 2 - 16, y - 18, true)
    DrawChangelogButton(x + w // 2 + 16, y - 18, true)
    DrawInstallButton(x, y, w, h, main_version, main_dlink)

    DrawVersionHistoryButton(x * 4 + w // 2 - 16, y - 18, false)
    DrawChangelogButton(x * 4 + w // 2 + 16, y - 18, false)
    DrawInstallButton(x * 4, y, w, h, dev_version, dev_dlink)

    DrawSettingsButton()
end

function ShowGUI()
    -- Show script window in center of screen
    gfx.clear = reaper.ColorToNative(37, 37, 37)
    local w, h = 500, 250
    local x, y = reaper.GetMousePosition()
    local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, x, y, x, y, 1)
    gfx.init(title, w, h, 0, (r + l - w) / 2, (b + t - h) / 2 - 24)
end

function Main()
    -- Check step file for newly completed steps
    local step_file = io.open(step_path, 'r')
    if step_file then
        step = step_file:read('*a'):gsub('[^%w_]+', '')
        step_file:close()
        os.remove(step_path)

        -- Print log file of previous step
        local cmd_log_file = io.open(cmd_log_path, 'r')
        if cmd_log_file then
            print('\nCommand log:\n')
            print(cmd_log_file:read('*a'))
            cmd_log_file:close()
            os.remove(cmd_log_path)
        end

        print('\n------------- Step ' .. tostring(step) .. ' ---------------')

        if step == 'check_update' then
            -- Download the HTML of the REAPER website
            local cmd = dl_cmd .. ' >> %s 2>&1'
            cmd = cmd:format(main_dlink, main_path, cmd_log_path)
            -- Download the HTML of the Landoleet website
            cmd = cmd .. ' && ' .. dl_cmd .. ' >> %s 2>&1'
            cmd = cmd:format(dev_dlink, dev_path, cmd_log_path)
            -- Show buttons if download succeeds, otherwise show error
            cmd = cmd .. ' && echo display_update > %s'
            cmd = cmd .. ' || echo err_internet > %s'
            ExecProcess(cmd:format(step_path, step_path))
            task = 'Checking for updates...'
        end

        if step == 'display_update' then
            -- Parse the REAPER website html for the download link
            local file = io.open(main_path, 'r')
            if not file then
                reaper.MB('File not found: ' .. main_path, 'Error', 0)
                return
            end
            main_dlink = ParseDownloadLink(file, main_dlink)
            file:close()
            os.remove(main_path)
            if not main_dlink then
                local msg = 'Could not parse download link!\nOS: %s\nArch: %s'
                reaper.MB(msg:format(platform, arch), 'Error', 0)
                return
            end
            -- Parse the LANDOLEET website html for the download link
            file = io.open(dev_path, 'r')
            if not file then
                reaper.MB('File not found: ' .. dev_path, 'Error', 0)
                return
            end
            dev_dlink = ParseDownloadLink(file, dev_dlink)
            -- Parse latest versions from download link
            local pattern = '/reaper(.-)[_%-]'
            main_version = main_dlink:match(pattern):gsub('(.)', '%1.', 1)
            if dev_dlink then
                dev_version = dev_dlink:match(pattern):gsub('(.)', '%1.', 1)
            else
                dev_dlink = ''
                dev_version = 'none'
            end

            dev_changelog = ParseDevChangelogLink(file, dev_version)
            file:close()
            os.remove(dev_path)

            local saved_main_version = reaper.GetExtState(title, 'main_version')
            local saved_dev_version = reaper.GetExtState(title, 'dev_version')

            print('\nCurr version: ' .. tostring(curr_version))
            print('\nSaved main version: ' .. tostring(saved_main_version))
            print('Saved dev version: ' .. tostring(saved_dev_version))
            print('\nMain version: ' .. tostring(main_version))
            print('Dev version: ' .. tostring(dev_version))

            -- Check if there's new version
            if saved_main_version ~= main_version then
                new_version = main_version
                print('Found new main version')
            end
            if saved_dev_version ~= dev_version then
                -- If both are new, show update to the currently installed version
                local is_installed = not curr_version:match('^%d+%.%d+%a*$')
                if (not new_version or is_installed) and dev_version ~= 'none' then
                    new_version = dev_version
                    print('Found new dev version')
                end
            end
            -- Check if the new version is already installed (first script run)
            if new_version == curr_version then
                new_version = nil
                print('Newly found version is already installed')
            end
            -- Save latest version numbers in extstate for next check
            reaper.SetExtState(title, 'main_version', main_version, true)
            reaper.SetExtState(title, 'dev_version', dev_version, true)

            print('\nNew version: ' .. tostring(new_version))

            if startup_mode then
                if not new_version then
                    print('No update found! Exiting...')
                    return
                elseif new_version:match('dev') or new_version:match('pre') then
                    if not settings.notify_dev.enabled then
                        print('No dev notifications! Exiting...')
                        return
                    end
                elseif new_version:match('rc') then
                    if not settings.notify_rc.enabled then
                        print('No rc notifications! Exiting...')
                        return
                    end
                elseif not settings.notify_main.enabled then
                    print('No main notifications! Exiting...')
                    return
                end
                ShowGUI()
                startup_mode = false
            end
            -- Show buttons with both versions (user choice)
            show_buttons = true
        end

        if step == 'download' then
            -- Choose next step based on platform
            local next_step = 'linux_extract'
            if platform:match('Win') then
                next_step = 'windows_install'
            end
            if platform:match('OSX') or platform:match('macOS') then
                next_step = 'osx_install'
            end

            -- Get downloaded file name from url
            dfile_name = user_dlink:gsub('.-/', '')

            -- Download chosen REAPER version
            local cmd = dl_cmd .. ' >> %s 2>&1'
            cmd = cmd:format(user_dlink, tmp_path .. dfile_name, cmd_log_path)
            -- Go to next step if download succeeds, otherwise show error
            cmd = cmd .. ' && echo %s > %s'
            cmd = cmd .. ' || echo err_internet > %s'
            cmd = cmd:format(next_step, step_path, step_path)
            ExecProcess(cmd)
            task = 'Downloading...'
        end

        if step == 'windows_install' then
            local log_path = cmd_log_path
            if settings.debug_file.enabled then
                log_path = user_log_path
            end

            local portable_str = is_portable and '/PORTABLE' or '/ADMIN'
            local dfile_path = tmp_path .. dfile_name

            -- Count how many FX are loaded across all projects
            local fx_cnt = 0
            local p = 0
            repeat
                local proj = reaper.EnumProjects(p)
                if proj then
                    for t = 0, reaper.CountTracks(proj) - 1 do
                        local track = reaper.GetTrack(proj, t)
                        fx_cnt = fx_cnt + reaper.TrackFX_GetCount(track)
                    end
                end
                p = p + 1
            until not proj

            -- Pick a timeout between 5 and 10 seconds based on FX count
            -- (give REAPER time to close projects)
            local timeout = math.ceil(math.min(10, 5 + fx_cnt / 100 * 5))
            local cmd = 'timeout %d >> %s 2>&1'
            cmd = cmd:format(timeout, log_path)

            -- Run the installer .exe  with appropriate options
            -- /S silent mode
            -- /D installation directory
            -- /ADMIN ask for permission
            -- /PORTABLE for portable installs
            cmd = cmd .. ' & %s /S %s /D=%s >> %s 2>&1'
            cmd = cmd:format(dfile_path, portable_str, install_path, log_path)
            -- Go to installation directory
            cmd = cmd .. ' & cd /D %s >> %s 2>&1'
            cmd = cmd:format(install_path, log_path)
            -- Execute hook script (if it exists)
            if hook_cmd ~= '' then
                cmd = cmd .. ' %s >> %s 2>&1'
                cmd = cmd:format(hook_cmd, log_path)
            end
            -- Delete downloaded installer file
            cmd = cmd .. ' & del %s >> %s 2>&1'
            cmd = cmd:format(dfile_path, log_path)
            -- Restart reaper
            cmd = cmd .. ' & start reaper.exe -cfgfile \"%s\"'
            cmd = cmd:format(ini_file)
            ExecInstall(cmd)
            return
        end

        if step == 'osx_install' then
            local log_path = cmd_log_path
            if settings.debug_file.enabled then
                log_path = user_log_path
            end

            -- Mount downloaded dmg file and get the mount directory (yes agrees to license)
            local cmd = 'mount_dir=$(yes | hdiutil attach \"%s%s\" '
            cmd = cmd .. '| grep Volumes | cut -f 3) >> \"%s\" 2>&1'
            cmd = cmd .. ' && echo \"mount_dir: $mount_dir\" >> \"%s\" 2>&1'
            cmd = cmd:format(tmp_path, dfile_name, log_path, log_path)
            -- Go to mount directory
            cmd = cmd .. ' && cd \"$mount_dir\" >> \"%s\" 2>&1'
            cmd = cmd:format(log_path)
            -- Get the .app name
            cmd = cmd .. ' && app_name=$(ls | grep REAPER)'
            cmd = cmd .. ' && echo \"app_name: $app_name\" >> \"%s\" 2>&1'
            cmd = cmd:format(log_path)
            -- Copy .app to install path
            cmd = cmd .. ' && ditto \"$app_name\" \"%s/$app_name\"'
            cmd = cmd .. ' >> \"%s\" 2>&1'
            cmd = cmd:format(install_path, log_path)
            -- Unmount file
            cmd = cmd .. ' ; cd'
            cmd = cmd .. ' && hdiutil eject \"$mount_dir\" >> \"%s\" 2>&1'
            cmd = cmd:format(log_path)
            -- Execute hook script (if it exists)
            if hook_cmd ~= '' then
                cmd = cmd .. ' %s >> \"%s\" 2>&1'
                cmd = cmd:format(hook_cmd, log_path)
            end
            -- Restart REAPER
            cmd = cmd .. ' ; echo \"Starting: %s/$app_name\" >> \"%s\" 2>&1'
            cmd = cmd .. ' && open \"%s/$app_name\" --args -cfgfile \"%s\"'
            cmd = cmd:format(install_path, log_path, install_path, ini_file)
            ExecInstall(cmd)
            return
        end

        if step == 'linux_extract' then
            -- Extract tar file in /tmp directory
            local cmd = 'tar -xf %s%s -C %s >> %s 2>&1'
            cmd = cmd:format(tmp_path, dfile_name, tmp_path, cmd_log_path)
            -- Go to installation step or show error
            cmd = cmd .. ' && echo linux_install > %s'
            cmd = cmd .. ' || echo err_extract > %s'
            cmd = cmd:format(step_path, step_path)
            ExecProcess(cmd)
            task = 'Extracting...'
        end

        if step == 'err_extract' then
            local msg = 'Extracting failed!\nShow debugging output in console?'
            local ret = reaper.MB(msg, 'Error', 4)
            if ret == 6 then print(debug_str, true) end
            return
        end

        if step == 'linux_install' then
            local log_path = cmd_log_path
            if settings.debug_file.enabled then
                log_path = user_log_path
            end

            -- Determine path to the extracted installer shell script
            local sh_path = '%sreaper_linux_%s/install-reaper.sh'
            sh_path = sh_path:format(tmp_path, arch)
            -- Note: Linux installer creates a REAPER directory
            local outer_install_path = install_path:gsub('/REAPER$', '')
            -- Only use options for non portable installs
            local options = '--integrate-desktop --usr-local-bin-symlink'
            if is_portable then options = '' end

            -- Run Linux installation
            local cmd = 'pkexec sh %s --install %s %s >> %s 2>&1'
            cmd = cmd:format(sh_path, outer_install_path, options, log_path)
            -- Wrap install command in new shell with sudo privileges
            cmd = '/bin/sh -c \'' .. cmd .. '\''
            -- Execute hook script (if it exists)
            if hook_cmd ~= '' then
                cmd = cmd .. ' %s >> %s 2>&1'
                cmd = cmd:format(hook_cmd, log_path)
            end
            --  Restart reaper
            cmd = cmd .. ' ; %s/reaper'
            cmd = cmd:format(install_path)
            ExecInstall(cmd)
            return
        end

        if step == 'get_history' then
            -- Show buttons if download succeeds, otherwise show error
            local cmd = dl_cmd .. ' >> %s 2>&1'
            cmd = cmd:format(old_dlink, main_path, cmd_log_path)
            cmd = cmd .. ' && echo show_history > %s'
            cmd = cmd .. ' || echo err_internet > %s'
            cmd = cmd:format(step_path, step_path)
            ExecProcess(cmd)
        end

        if step == 'show_history' then
            local file = io.open(main_path, 'r')
            if not file then
                reaper.MB('File not found: ' .. main_path, 'Error', 0)
                return
            end
            ParseHistory(file, old_dlink)
            os.remove(main_path)
            task = ''
            show_buttons = true
            reaper.defer(ShowHistoryMenu)
        end

        if step:match('^get_.-_changelog$') then
            local file_path, cl_cmd, link
            if step:match('main') then
                file_path = main_path
                cl_cmd = 'echo open_main_changelog > %s'
                link = 'https://forum.cockos.com/forumdisplay.php?f=19'
            else
                file_path = dev_path
                cl_cmd = 'echo open_dev_changelog > %s'
                link = 'https://forum.cockos.com/forumdisplay.php?f=37'
            end
            -- Download the corresponding sub-forum website
            local cmd = dl_cmd .. ' && ' .. cl_cmd .. ' ||' .. cl_cmd
            cmd = cmd:format(link, file_path, step_path, step_path)
            ExecProcess(cmd)
        end

        if step:match('^open_.-_changelog$') then
            local file_path, version, changelog
            if step:match('main') then
                file_path = main_path
                version = main_version
                changelog = main_changelog
            else
                file_path = dev_path
                version = dev_version
                changelog = dev_changelog
            end
            local file = io.open(file_path, 'r')
            if file then
                local thread_link = 'https://forum.cockos.com/showthread.php?t='
                local pattern = '<a href=".-" id="thread_title_(%d+)">v*V*'
                pattern = pattern .. version:gsub('%+', '%%+') .. ' '
                -- Default: Open the changelog website directly
                local cmd = browser_cmd .. changelog
                for line in file:lines() do
                    local forum_link = line:match(pattern)
                    if forum_link then
                        -- If forum post is matched, open this as changelog instead
                        cmd = browser_cmd .. thread_link .. forum_link
                        break
                    end
                end
                file:close()
                ExecProcess(cmd)
                os.remove(file_path)
            end
            show_buttons = true
        end

        if step == 'err_internet' then
            local msg = 'Download failed!\nShow debugging output in console?'
            if not startup_mode then
                local ret = reaper.MB(msg, 'Error', 4)
                if ret == 6 then print(debug_str, true) end
            end
            return
        end
    end
    if not startup_mode then
        -- Exit script on window close & escape key
        local char = gfx.getchar()
        if char == -1 or char == 27 then
            if task == 'Downloading...' and settings.dialog_dl_cancel.enabled then
                local msg = 'Quit installation of v%s?'
                local ret = reaper.MB(msg:format(install_version), title, 4)
                if ret == 6 then
                    print('User exit...')
                    return
                elseif char == -1 then
                    ShowGUI()
                end
            else
                print('User exit...')
                return
            end
        end
        if show_buttons then
            -- User hotkey 'm'
            if char == 109 then
                user_dlink = main_dlink
                install_version = main_version
                ExecProcess('echo download > ' .. step_path)
                show_buttons = false
            end
            -- User hotkey 'd'
            if char == 100 then
                user_dlink = dev_dlink
                install_version = dev_version
                ExecProcess('echo download > ' .. step_path)
                show_buttons = false
            end
            -- User hotkey 'M'
            if char == 77 then
                ExecProcess('echo get_main_changelog > ' .. step_path)
            end
            -- User hotkey 'D'
            if char == 68 then
                ExecProcess('echo get_dev_changelog > ' .. step_path)
            end
        end
        -- Draw content
        DrawTask()
        if show_buttons then DrawGUI() end
        gfx.update()
    end
    reaper.defer(Main)
end

settings = LoadSettings()

if not platform:match('Win') then
    -- String escape Unix paths (spaces and brackets)
    install_path = install_path:gsub('[%s%(%)]', '\\%1')
    res_path = res_path:gsub('[%s%(%)]', '\\%1')
end

-- Define paths to temporary files
tmp_path = '/tmp/'
if platform:match('Win') then
    tmp_path = ExecProcess('echo %TEMP%', 1000)
    if not tmp_path then
        reaper.MB('Could not get temporary directory', 'Error', 0)
        return
    end
    tmp_path = tmp_path .. '\\'
end
step_path = tmp_path .. 'reaper_uutil_step.txt'
main_path = tmp_path .. 'reaper_uutil_main.html'
dev_path = tmp_path .. 'reaper_uutil_dev.html'
cmd_log_path = tmp_path .. 'reaper_uutil_log.txt'

local cmd_log_file = io.open(cmd_log_path, 'r')
if cmd_log_file then
    print('\nCommand log:\n')
    print(cmd_log_file:read('*a'))
    cmd_log_file:close()
    os.remove(cmd_log_path)
end

-- Delete existing temporary files from previous runs
os.remove(step_path)
os.remove(main_path)
os.remove(dev_path)
os.remove(startup_log_path)

print('\n-------------------------------------------')
print('CPU achitecture: ' .. tostring(arch))
print('Installation path: ' .. tostring(install_path))
print('Resource path: ' .. tostring(res_path))
print('Reaper version: ' .. tostring(curr_version))
print('Portable: ' .. (is_portable and 'yes' or 'no'))

-- Set command for downloading from terminal
dl_cmd = 'curl -k -L %s -o %s'
if platform:match('Win') then
    -- Check if curl is installed
    local _, exit_code = ExecProcess(('curl --version'), 1000)
    local has_curl = exit_code == 0
    if not has_curl then
        -- Use powershell instead of curl
        dl_cmd = 'powershell.exe -windowstyle hidden (new-object \z
                System.Net.WebClient).DownloadFile(\'%s\', \'%s\')'
    end
end

-- Set command for opening web-pages from terminal
browser_cmd = 'xdg-open '
if platform:match('Win') then browser_cmd = 'start ' end
if platform:match('OSX') or platform:match('macOS') then browser_cmd = 'open ' end

-- Set command for platform-dependent post-install hooks
if platform:match('Win') then
    if reaper.file_exists(scripts_path .. '__update.bat') then
        hook_cmd = '& start "" /D "' .. scripts_path .. '" /W __update.bat'
    end
    if reaper.file_exists(scripts_path .. '__update.sh') then
        hook_cmd = '& bash -c "sh ' .. scripts_path .. '__update.sh"'
    end
elseif reaper.file_exists(scripts_path .. '__update.sh') then
    if platform:match('OS') then
        hook_cmd = '; sh \"' .. scripts_path .. '__update.sh\"'
    else
        hook_cmd = '; sh \'' .. scripts_path .. '__update.sh\''
    end
end

-- Run lua startup hook
if reaper.GetExtState(title, 'lua_hook') == '1' then
    reaper.DeleteExtState(title, 'lua_hook', true)
    if reaper.file_exists(scripts_path .. '__update.lua') then
        dofile(scripts_path .. '__update.lua')
    end
end

-- Check if the script has already run since last restart (using extstate persist)
local has_already_run = reaper.GetExtState(title, 'startup') == '1'
reaper.SetExtState(title, 'startup', '1', false)
print('Startup extstate: ' .. tostring(has_already_run))

if has_already_run then
    startup_mode = false
elseif settings.force_startup.enabled then
    print('Forced startup up mode is enabled!')
    startup_mode = true
end
print('Startup mode: ' .. tostring(startup_mode))

if settings.debug_file.enabled then
    local msg =
    ' \nLogging to file is enabled!\n\nYou can find the file \'update-utility.log\' \z
    in your resource directory:\n--> Options --> Show REAPER resource path...\n '
    reaper.MB(msg, title, 0)
end

local last_proj = reaper.GetExtState(title, 'last_proj')
if last_proj ~= '' then
    -- Restore previously loaded project
    if not has_already_run and CheckStartupHook() then
        reaper.Main_openProject(last_proj)
    end
    reaper.SetExtState(title, 'last_proj', '', true)
end

if startup_mode then
    local prev_time = tonumber(reaper.GetExtState(title, 'prev_start_time')) or 0
    local curr_time = reaper.time_precise()
    local time_diff = math.abs(math.ceil(curr_time - prev_time))
    print(('Last update check: %s seconds ago'):format(time_diff))
    -- Check if 3 minutes have passed since last update check
    if time_diff < 60 * 3 then
        print('Exiting without checking for updates!')
        return
    end
    reaper.SetExtState(title, 'prev_start_time', curr_time, true)
else
    ShowGUI()
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

reaper.atexit(function()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
end)

-- Trigger the first step (steps are triggered by writing to the step file)
ExecProcess('echo check_update > ' .. step_path)
reaper.defer(Main)
