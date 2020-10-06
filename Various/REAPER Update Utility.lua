--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.2.0
  @about Simple utility to update REAPER to the latest version
  @changelog
    - Support for older Windows versions (7 and higher)
    - Auto-detect if script is used as startup action
    - Added Debugging output
    - Added Changelog GUI links
]]
-- Set this to true to show debugging output
local debug = false

-- App version & platform architecture
local platform = reaper.GetOS()
local app = reaper.GetAppVersion()
local curr_version = app:gsub('/.-$', '')
local main_version, dev_version, new_version

local arch = app:match('/(.-)$')
arch = arch == 'linux64' and 'x86_64' or arch
arch = arch == 'linux32' and 'i686' or arch

-- Links to REAPER websites
local main_dlink = 'https://www.reaper.fm/download.php'
local dev_dlink = 'https://www.landoleet.org/'
local main_changelog = 'https://www.reaper.fm/whatsnew.txt'
local dev_changelog = 'https://www.landoleet.org/whatsnew-dev.txt'

-- Paths
local install_path = reaper.GetExePath()
local res_path = reaper.GetResourcePath()
local tmp_path, step_path, main_path, dev_path

-- Startup mode
local startup_mode
local start_timeout = 90
local load_timeout = 2

-- Download variables
local dl_cmd, browser_cmd, dlink, dfile_name

-- GUI variables
local step = 0
local direction = 1
local opacity = 0.65
local show_buttons = false
local task = 'Initializing...'
local title = 'REAPER Update Utility'
local font_factor = platform:match('Win') and 1.25 or 1

function print(msg, debug)
    if debug == nil or debug then
        reaper.ShowConsoleMsg(tostring(msg) .. '\n')
    end
end

function ExecProcess(cmd, timeout)
    if platform:match('Win') then
        cmd = 'cmd.exe  /Q /C  ' .. cmd
    else
        cmd = '/bin/sh -c "' .. cmd .. '"'
    end
    local ret = reaper.ExecProcess(cmd, timeout or -2)
    print('Executing command:\n' .. cmd, debug)
    if ret then
        -- Remove exit code (first line) and all newlines
        ret = ret:gsub('^.-\n', ''):gsub('[\r\n]', '')
        if ret ~= '' then
            print('Return value:\n' .. ret, debug)
        end
    end
    return ret
end

function SaveAndQuit()
    -- File: Close all projects
    reaper.Main_OnCommand(40886, 0)

    if reaper.IsProjectDirty(0) == 0 then
        -- File: Quit REAPER
        reaper.Main_OnCommand(40004, 0)
        return true
    end
end

function ParseDownloadLink(file, dlink)
    local file_pattern = '_linux_' .. arch .. '%.tar%.xz'
    if platform:match('Win') then
        file_pattern = (arch and '_' .. arch or '') .. '%-install%.exe'
    end
    if platform:match('OSX') then
        file_pattern = '_' .. arch .. '%.dmg'
    end
    -- Match href file download link
    for line in file:lines() do
        local href = line:match('href="([^_"]-' .. file_pattern .. ')"')
        if href then
            dlink = dlink:match('(.-%..-%..-/)')
            return dlink .. href
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

function DrawButtons()
    task = ''
    local m_x = gfx.mouse_x
    local m_y = gfx.mouse_y
    local w = math.floor(gfx.w / 7) * 2
    local h = math.floor(gfx.h / 2)

    -- Main button
    gfx.set(0.6)
    local x = math.floor(gfx.w / 7)
    local y = math.floor(gfx.h / 4)

    local is_main_new = main_version == new_version
    local is_main_installed = main_version == curr_version
    local is_hover = m_x >= x and m_x <= x + w and m_y >= y and m_y <= y + h

    if is_main_new then
        gfx.set(1.15 * opacity, 0.92 * opacity, 0.6 * opacity)
    end

    if is_hover then
        gfx.set(0.8, 0.6, 0.35)
    end

    if is_main_installed then
        gfx.set(0.1, 0.65, 0.5)
    end

    if not is_main_installed and is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.1, 0.65, 0.5)
        dlink = main_dlink
    end

    if dlink == main_dlink and gfx.mouse_cap == 0 then
        if is_hover then
            ExecProcess('echo download > ' .. step_path)
            show_buttons = false
        else
            dlink = nil
        end
    end

    -- Border
    gfx.roundrect(x, y, w, h, 4, 1)
    gfx.roundrect(x + 1, y, w, h, 4, 1)
    gfx.roundrect(x, y + 1, w, h, 4, 1)

    -- Version string
    gfx.setfont(1, '', 30 * font_factor, string.byte('b'))
    local t_w, t_h = gfx.measurestr(main_version)
    gfx.x = math.floor(gfx.w / 7 * 2 - t_w / 2) + 1
    gfx.y = math.floor(gfx.h / 2 - t_h / 2)
    gfx.drawstr(main_version, 1)

    -- Changelog
    gfx.set(0.6)
    gfx.setfont(1, '', 12 * font_factor)
    local changelog = 'CHANGELOG'
    local t_w, t_h = gfx.measurestr(changelog)
    gfx.x = math.floor(gfx.w / 7 * 2 - t_w / 2) + 9
    gfx.y = math.floor(gfx.h * 3 / 32 + y + h) + 1

    local hov_y = gfx.y - math.floor(h / 16)
    local hov_h = gfx.y + math.floor(h / 16) + t_h
    local is_hover = m_x >= x and m_x <= x + w and m_y >= hov_y and m_y <= hov_h

    if is_hover then
        gfx.set(0.8, 0.6, 0.35)
    end

    if is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.1, 0.65, 0.5)
        dlink = main_changelog
    end

    if dlink == main_changelog and gfx.mouse_cap == 0 then
        if is_hover then
            ExecProcess(browser_cmd .. dlink)
        end
        dlink = nil
    end
    gfx.drawstr(changelog, 1)

    -- Info icon
    local c_x = gfx.x - t_w - 16
    local c_y = gfx.y + math.floor(t_h / 2)
    gfx.circle(c_x, c_y, 8, 1, 1)
    gfx.circle(c_x + 1, c_y, 8, 1, 1)
    gfx.set(0.13)
    gfx.setfont(0)
    local info = 'i'
    local i_w, i_h = gfx.measurestr(info)
    gfx.x = c_x - math.floor(i_w / 2) + 1
    gfx.y = c_y - math.floor(i_h / 2) + 1
    gfx.drawstr(info, 1)

    -- Dev button
    gfx.set(0.6)
    local x = math.floor(gfx.w / 7) * 4
    local y = math.floor(gfx.h / 4)

    local is_dev_new = dev_version == new_version
    local is_dev_installed = dev_version == curr_version
    local is_hover = m_x >= x and m_x <= x + w and m_y >= y and m_y <= y + h

    if is_dev_new then
        gfx.set(1.15 * opacity, 0.92 * opacity, 0.6 * opacity)
    end

    if is_hover then
        gfx.set(0.8, 0.6, 0.35)
    end

    if is_dev_installed then
        gfx.set(0.1, 0.65, 0.5)
    end

    if not is_dev_installed and is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.1, 0.65, 0.5)
        dlink = dev_dlink
    end

    if dlink == dev_dlink and gfx.mouse_cap == 0 then
        if is_hover then
            ExecProcess('echo download > ' .. step_path)
            show_buttons = false
        else
            dlink = nil
        end
    end

    -- Border
    gfx.roundrect(x, y, w, h, 4, 1)
    gfx.roundrect(x + 1, y, w, h, 4, 1)
    gfx.roundrect(x, y + 1, w, h, 4, 1)

    -- Version string
    gfx.setfont(1, '', 30 * font_factor, string.byte('b'))
    local version = dev_version:match('(.-)+')
    local t_w, t_h = gfx.measurestr(version)
    gfx.x = math.floor(gfx.w / 7 * 5 - t_w / 2) + 1
    gfx.y = math.floor(gfx.h / 2 - t_h / 2)
    gfx.drawstr(version, 1)

    -- Dev string
    gfx.setfont(1, '', 15 * font_factor, string.byte('i'))
    local version = dev_version:match('(+.-)$')
    local t_w = gfx.measurestr(version)
    gfx.x = math.floor(gfx.w / 7 * 5 - t_w / 2) + 1
    gfx.y = math.floor(gfx.y + t_h) + 4
    gfx.drawstr(version, 1)

    -- Changelog
    gfx.set(0.6)
    gfx.setfont(1, '', 12 * font_factor)
    local changelog = 'CHANGELOG'
    local t_w, t_h = gfx.measurestr(changelog)
    gfx.x = math.floor(gfx.w / 7 * 5 - t_w / 2) + 9
    gfx.y = math.floor(gfx.h * 3 / 32 + y + h) + 1

    local hov_y = gfx.y - math.floor(h / 16)
    local hov_h = gfx.y + math.floor(h / 16) + t_h
    local is_hover = m_x >= x and m_x <= x + w and m_y >= hov_y and m_y <= hov_h

    if is_hover then
        gfx.set(0.8, 0.6, 0.35)
    end

    if is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.1, 0.65, 0.5)
        dlink = dev_changelog
    end

    if dlink == dev_changelog and gfx.mouse_cap == 0 then
        if is_hover then
            ExecProcess(browser_cmd .. dlink)
        end
        dlink = nil
    end
    gfx.drawstr(changelog, 1)

    -- Info icon
    local c_x = gfx.x - t_w - 16
    local c_y = gfx.y + math.floor(t_h / 2)
    gfx.circle(c_x, c_y, 8, 1, 1)
    gfx.circle(c_x + 1, c_y, 8, 1, 1)
    gfx.set(0.13)
    gfx.setfont(0)
    local info = 'i'
    local i_w, i_h = gfx.measurestr(info)
    gfx.x = c_x - math.floor(i_w / 2) + 1
    gfx.y = c_y - math.floor(i_h / 2) + 1
    gfx.drawstr(info, 1)
end

function checkNewVersion()
    -- Convert version strings to comparable numbers
    local curr_num = tonumber(({curr_version:gsub('[^%d.]', '')})[1])
    local main_num = tonumber(({main_version:gsub('[^%d.]', '')})[1])
    local dev_num = tonumber(({dev_version:gsub('[^%d.]', '')})[1])
    local latest_num = tonumber(reaper.GetExtState(title, 'version')) or curr_num
    local ret = false
    -- Check new pre-release versions (keep logic for potential future user option)
    local startup_check_dev_releases = true
    -- Check if new numbers are higher than when last checked
    if main_num > latest_num then
        new_version = main_version
        latest_num = main_num
        ret = true
    end
    if dev_num > latest_num then
        if startup_check_dev_releases then
            new_version = dev_version
            ret = true
        else
            -- Show info about dev version if there's not a new main version
            if not new_version then
                new_version = dev_version
            end
        end
        latest_num = dev_num
    end
    reaper.SetExtState(title, 'version', latest_num, true)
    return ret
end

function ConvertToSeconds(time)
    local i = 2
    local res = 0
    for num in time:gmatch('%d+') do
        res = res + tonumber(num) * 60 ^ i
        i = i - 1
    end
    return res
end

function ShowGUI()
    -- Show script window in center of screen
    gfx.clear = reaper.ColorToNative(37, 37, 37)
    local w, h = 500, 250
    local x, y = reaper.GetMousePosition()
    local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, x, y, x, y, 1)
    gfx.init(title, w, h, 0, (r + l - w) / 2, (b + t - h) / 2)
end

function Main()
    -- Check step file for newly completed steps
    local step_file = io.open(step_path, 'r')
    if step_file then
        step = step_file:read('*a'):gsub('[^%w_]+', '')
        step_file:close()
        os.remove(step_path)

        if step == 'check_update' then
            print('\nSTEP ' .. step, debug)
            task = 'Checking for updates...'
            -- Download the HTML of the REAPER website
            local cmd = dl_cmd .. ' && ' .. dl_cmd
            cmd = cmd:format(main_dlink, main_path, dev_dlink, dev_path)
            -- Show buttons if download succeeds, otherwise show error
            cmd = cmd .. ' && echo display_update > %s || echo err_internet > %s'
            ExecProcess(cmd:format(step_path, step_path))
        end

        if step == 'display_update' then
            print('\nSTEP ' .. step, debug)
            -- Parse the REAPER website html for the download link
            local file = io.open(main_path, 'r')
            if not file then
                reaper.MB('File not found: ' .. main_path, 'Error', 0)
                return
            end
            main_dlink = ParseDownloadLink(file, main_dlink)
            file:close()
            os.remove(main_path)
            -- Parse the LANDOLEET website html for the download link
            local file = io.open(dev_path, 'r')
            if not file then
                reaper.MB('File not found: ' .. dev_path, 'Error', 0)
                return
            end
            dev_dlink = ParseDownloadLink(file, dev_dlink)
            file:close()
            os.remove(dev_path)
            if not main_dlink or not dev_dlink then
                local msg = 'Could not parse download link!\nOS: %s\nArch: %s'
                reaper.MB(msg:format(platform, arch), 'Error', 0)
                return
            end
            -- Parse latest versions from download link
            main_version = main_dlink:match('/reaper(.-)[_%-]'):gsub('(.)', '%1.', 1)
            dev_version = dev_dlink:match('/reaper(.-)[_%-]'):gsub('(.)', '%1.', 1)

            local is_new = checkNewVersion()
            if startup_mode then
                if not is_new then
                    print('No update found! Exiting...', debug)
                    return
                end
                startup_mode = false
                ShowGUI()
            end
            -- Show buttons with both versions (user choice)
            show_buttons = true
        end

        if step == 'download' then
            print('\nSTEP ' .. step, debug)
            -- Download chosen REAPER version
            task = 'Downloading...'
            dfile_name = dlink:gsub('.-/', '')
            local cmd = dl_cmd:format(dlink, tmp_path .. dfile_name)
            -- Choose next step based on platform
            local next_step = 'linux_extract'
            if platform:match('Win') then
                next_step = 'windows_install'
            end
            if platform:match('OSX') then
                next_step = 'osx_install'
            end
            -- Go to next step if download succeeds, otherwise show error
            cmd = cmd .. '&& echo %s > %s || echo err_internet > %s'
            ExecProcess(cmd:format(next_step, step_path, step_path))
        end

        if step == 'windows_install' then
            print('\nSTEP ' .. step, debug)
            if not SaveAndQuit() then
                reaper.MB('\nInstallation cancelled!\n ', title, 0)
                return
            end
            -- Run Windows installation and restart reaper
            local cmd = '%s%s /S /D=%s & cd %s & start reaper.exe'
            ExecProcess(cmd:format(tmp_path, dfile_name, install_path, install_path))
        end

        -- TODO: OSX support
        if step == 'osx_install' then
            print('\nSTEP ' .. step, debug)
        end

        if step == 'linux_extract' then
            print('\nSTEP ' .. step, debug)
            -- Extract tar file
            task = 'Extracting...'
            local cmd = 'tar -xf %s%s -C %s && echo linux_install > %s'
            ExecProcess(cmd:format(tmp_path, dfile_name, tmp_path, step_path))
        end

        if step == 'linux_install' then
            print('\nSTEP ' .. step, debug)
            if not SaveAndQuit() then
                reaper.MB('\nInstallation cancelled!\n ', title, 0)
                return
            end
            -- Run Linux installation and restart
            local cmd = 'pkexec sh %sreaper_linux_%s/install-reaper.sh --install %s'
            -- Comment out the following lines to disable desktop integration etc.
            cmd = cmd .. ' --integrate-desktop'
            cmd = cmd .. ' --usr-local-bin-symlink'
            -- Wrap install command in new shell with sudo privileges (for chaining restart)
            cmd = "/bin/sh -c '" .. cmd .. "' ; %s/reaper"

            -- Linux installer will also create a REAPER directory
            local outer_install_path = install_path:gsub('/REAPER$', '')
            ExecProcess(cmd:format(tmp_path, arch, outer_install_path, install_path))
        end

        if step == 'err_internet' then
            print('\nSTEP ' .. step, debug)
            if not startup_mode then
                reaper.MB('Download failed', 'Error', 0)
            end
            return
        end
    end
    if not startup_mode then
        -- Exit script on window close & escape key
        local char = gfx.getchar()
        if char == -1 or char == 27 then
            print('User exit...', debug)
            return
        end
        -- Draw content
        DrawTask(task)
        if show_buttons then
            DrawButtons()
        end
        gfx.update()
    end
    reaper.defer(Main)
end

print('\nSTARTING...', debug)

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

-- Delete existing temporary files from previous runs
os.remove(step_path)
os.remove(main_path)
os.remove(dev_path)

-- Set command for downloading from terminal
dl_cmd = 'curl -L %s -o %s'
if platform:match('Win') then
    dl_cmd = 'powershell.exe -windowstyle hidden (new-object System.Net.WebClient)'
    dl_cmd = dl_cmd .. ".DownloadFile('%s', '%s')"
end

-- Set command for opening web-pages from terminal
browser_cmd = 'xdg-open '
if platform:match('Win') then
    browser_cmd = 'start '
end
if platform:match('OSX') then
    browser_cmd = 'open '
end

-- Check if the script has already run since last restart (using extstate persist)
startup_mode = reaper.GetExtState(title, 'startup') ~= '1'
reaper.SetExtState(title, 'startup', '1', false)
if not startup_mode then
    print('Startup Mode: Script has already been started', debug)
else
    -- Get file last modification time
    local cmd = 'cd %s && date -r %s +%%s'
    if platform:match('Win') then
        cmd = 'cd %s && forfiles /M %s /C "cmd /c echo @ftime"'
    end
    -- The reginfo2.ini file is written to when reaper is started
    local start_time = ExecProcess(cmd:format(res_path, 'reaper-reginfo2.ini'), 1000)
    -- The reaper.ini file is written to shortly before startups scripts are loaded
    local load_time = ExecProcess(cmd:format(res_path, 'reaper.ini'), 1000)
    if not start_time or not load_time then
        reaper.MB('Could not get file modification time', 'Error', 0)
        return
    end
    -- Get current OS time
    local os_time = os.time()
    if platform:match('Win') then
        os_time = os.date():gsub('.- ', '')
        print('Start time (raw): ' .. start_time, debug)
        print('Load time (raw): ' .. load_time, debug)
        print('Curr time (raw): ' .. os_time, debug)
        -- Convert h:m:s syntax to seconds
        start_time = ConvertToSeconds(start_time)
        load_time = ConvertToSeconds(load_time)
        os_time = ConvertToSeconds(os_time)
        -- Make sure it works shortly before 12pm
        os_time = os_time <= start_timeout and os_time + 24 * 60 * 60 or os_time
    end
    print('Start time: ' .. start_time, debug)
    print('Load time: ' .. load_time, debug)
    print('Curr time: ' .. os_time, debug)
    -- Check time passed
    local start_diff = math.ceil(os_time - start_time)
    local load_diff = math.ceil(os_time - load_time)
    print('Start diff: ' .. start_diff .. ' / ' .. start_timeout, debug)
    print('Load diff: ' .. load_diff .. ' / ' .. load_timeout, debug)
    local is_in_start_window = start_diff >= 0 and start_diff <= start_timeout
    local is_in_load_window = load_diff >= 0 and load_diff <= load_timeout
    startup_mode = is_in_start_window and is_in_load_window
end

print('Startup Mode: ' .. tostring(startup_mode), debug)
if not startup_mode then
    ShowGUI()
end

if platform:match('OSX') then
    task = 'OSX is not supported (yet)...'
else
    -- Trigger the first step (steps are triggered by writing to the step file)
    ExecProcess('echo check_update > ' .. step_path)
end
reaper.defer(Main)
