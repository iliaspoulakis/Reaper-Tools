--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.3.0
  @about Simple utility to update REAPER to the latest version
  @changelog
    - OSX is now supported
    - Changelog links will search for corresponding forum posts
    - New simplified update logic (supports RC versions)
    - Fix for Windows network drives (by jkooks)
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
arch = arch == 'OSX64' and 'x86_64' or arch
arch = arch == 'OSX32' and 'i386' or arch

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
local dl_cmd, browser_cmd, user_dlink, dfile_name

-- GUI variables
local step = 0
local direction = 1
local opacity = 0.65
local main_cl, dev_cl
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
        cmd = 'cmd.exe /Q /C "' .. cmd .. '"'
    else
        cmd = '/bin/sh -c "' .. cmd .. '"'
    end
    local ret = reaper.ExecProcess(cmd, timeout or -2)
    print('Executing command:\n' .. cmd, debug)
    if ret then
        -- Remove exit code (first line)
        ret = ret:gsub('^.-\n', '')
        -- Remove Windows network drive error (fix by jkooks)
        ret = ret:gsub('^.-Defaulting to Windows directory%.', '')
        -- Remove all newlines
        ret = ret:gsub('[\r\n]', '')
        if ret ~= '' then
            print('Return value:\n' .. ret, debug)
        end
    end
    return ret
end

function SaveExitAndInstall(install_cmd)
    -- File: Close all projects
    reaper.Main_OnCommand(40886, 0)

    if reaper.IsProjectDirty(0) == 0 then
        ExecProcess(install_cmd)
        -- File: Quit REAPER
        reaper.Main_OnCommand(40004, 0)
        return true
    end
end

function ParseDownloadLink(file, dlink)
    local file_pattern
    if platform:match('Win') then
        file_pattern = (arch and '_' .. arch or '') .. '%-install%.exe'
    end
    if platform:match('OSX') then
        file_pattern = '%d_' .. arch .. '%.dmg'
    end
    if platform:match('Other') then
        file_pattern = '_linux_' .. arch .. '%.tar%.xz'
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

function DrawButton(x, y, version, dlink, changelog)
    local m_x = gfx.mouse_x
    local m_y = gfx.mouse_y
    local w = math.floor(gfx.w / 7) * 2
    local h = math.floor(gfx.h / 2)

    local is_new = version == new_version
    local is_dev = version == dev_version
    local is_main = version == main_version
    local is_installed = version == curr_version
    local is_hover = m_x >= x and m_x <= x + w and m_y >= y and m_y <= y + h

    gfx.set(0.6)

    if is_new then
        gfx.set(1.15 * opacity, 0.92 * opacity, 0.6 * opacity)
    end

    if is_hover then
        gfx.set(0.8, 0.6, 0.35)
    end

    if is_installed then
        gfx.set(0.1, 0.65, 0.5)
    end

    if not is_installed and is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.1, 0.65, 0.5)
        user_dlink = dlink
    end

    if user_dlink == dlink and gfx.mouse_cap == 0 then
        if is_hover then
            ExecProcess('echo download > ' .. step_path)
            show_buttons = false
        else
            user_dlink = nil
        end
    end

    -- Border
    gfx.roundrect(x, y, w, h, 4, 1)
    gfx.roundrect(x + 1, y, w, h, 4, 1)
    gfx.roundrect(x, y + 1, w, h, 4, 1)

    -- Version
    gfx.setfont(1, '', 30 * font_factor, string.byte('b'))
    local version_text = version:match('[^+]+')
    local t_w, t_h = gfx.measurestr(version_text)
    gfx.x = math.floor(x + gfx.w / 7 - t_w / 2) + 1
    gfx.y = math.floor(gfx.h / 2 - t_h / 2)
    gfx.drawstr(version_text, 1)

    -- Subversion
    gfx.setfont(1, '', 15 * font_factor, string.byte('i'))
    local subversion_text = version:match('(+.-)$') or ''
    local t_w = gfx.measurestr(subversion_text)
    gfx.x = math.floor(x + gfx.w / 7 - t_w / 2) + 1
    gfx.y = math.floor(gfx.y + t_h) + 4
    gfx.drawstr(subversion_text, 1)

    -- Changelog
    gfx.set(0.6)
    gfx.setfont(1, '', 12 * font_factor)
    local changelog_text = 'CHANGELOG'

    -- Display animation when main_cl is set
    if is_main and main_cl then
        main_cl = main_cl:sub(-1) .. main_cl:sub(1, #main_cl - 1)
        changelog_text = main_cl
    end

    -- Display animation when dev_cl is set
    if is_dev and dev_cl then
        dev_cl = dev_cl:sub(-1) .. dev_cl:sub(1, #dev_cl - 1)
        changelog_text = dev_cl
    end

    local t_w, t_h = gfx.measurestr(changelog_text)
    gfx.x = math.floor(x + gfx.w / 7 - t_w / 2) + 9
    gfx.y = math.floor(gfx.h * 3 / 32 + y + h) + 1

    local hov_y = gfx.y - math.floor(h / 16)
    local hov_h = gfx.y + math.floor(h / 16) + t_h
    local is_hover = m_x >= x and m_x <= x + w and m_y >= hov_y and m_y <= hov_h

    if is_hover then
        gfx.set(0.8, 0.6, 0.35)
    end

    if is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.1, 0.65, 0.5)
        user_dlink = changelog
    end

    if user_dlink == changelog and gfx.mouse_cap == 0 then
        if is_hover then
            if is_main then
                main_cl = 'CHANGELOG'
                ExecProcess('echo get_main_changelog > ' .. step_path)
            else
                dev_cl = 'CHANGELOG'
                ExecProcess('echo get_dev_changelog > ' .. step_path)
            end
        end
        user_dlink = nil
    end
    gfx.drawstr(changelog_text, 1)

    -- Info icon
    local c_x = gfx.x - t_w - 16
    local c_y = gfx.y + math.floor(t_h / 2)
    gfx.circle(c_x, c_y, 8, 1, 1)
    gfx.circle(c_x + 1, c_y, 8, 1, 1)
    gfx.set(0.13)
    gfx.setfont(0)
    local info_text = 'i'
    local i_w, i_h = gfx.measurestr(info_text)
    gfx.x = c_x - math.floor(i_w / 2) + 1
    gfx.y = c_y - math.floor(i_h / 2) + 1
    gfx.drawstr(info_text, 1)
end

function DrawButtons()
    task = ''
    local x = math.floor(gfx.w / 7)
    local y = math.floor(gfx.h / 4)
    DrawButton(x, y, main_version, main_dlink, main_changelog)
    local x = math.floor(gfx.w / 7) * 4
    local y = math.floor(gfx.h / 4)
    DrawButton(x, y, dev_version, dev_dlink, dev_changelog)
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

            -- Check if there's new version
            if reaper.GetExtState(title, 'main_version') ~= main_version then
                new_version = main_version
            end
            if reaper.GetExtState(title, 'dev_version') ~= dev_version then
                -- If both are new, show update to the currently installed version
                local is_dev_installed = not curr_version:match('^%d+%.%d+$')
                if not new_version or is_dev_installed then
                    new_version = dev_version
                end
            end
            -- Check if the new version is already installed (first script run)
            if new_version == curr_version then
                new_version = nil
            end
            -- Save latest version numbers in extstate for next check
            reaper.SetExtState(title, 'main_version', main_version, true)
            reaper.SetExtState(title, 'dev_version', dev_version, true)

            if startup_mode then
                if not new_version then
                    print('No update found! Exiting...', debug)
                    return
                end
                ShowGUI()
                startup_mode = false
            end
            -- Show buttons with both versions (user choice)
            show_buttons = true
        end

        if step == 'download' then
            print('\nSTEP ' .. step, debug)
            -- Download chosen REAPER version
            task = 'Downloading...'
            dfile_name = user_dlink:gsub('.-/', '')
            local cmd = dl_cmd:format(user_dlink, tmp_path .. dfile_name)
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
            -- Windows installer: /S is silent mode, /D specifies directory
            local cmd = '%s /S /D=%s & cd /D %s & start reaper.exe & del %s'
            local dfile_path = tmp_path .. dfile_name

            -- Save, exit and run install command
            cmd = cmd:format(dfile_path, install_path, install_path, dfile_path)
            if not SaveExitAndInstall(cmd) then
                reaper.MB('\nInstallation cancelled!\n ', title, 0)
            end
            return
        end

        if step == 'osx_install' then
            print('\nSTEP ' .. step, debug)
            -- Mount downloaded dmg file and get the mount directory (yes agrees to license)
            local cmd = 'mount_dir=$(yes | hdiutil attach %s%s | grep Volumes | cut -f 3)'
            -- Get the .app name
            cmd = cmd .. ' && cd $mount_dir && app_name=$(ls | grep REAPER)'
            -- Copy .app to install path
            cmd = cmd .. ' && cp -rf $app_name %s'
            -- Unmount file and restart reaper
            cmd = cmd .. ' ; cd && hdiutil unmount $mount_dir ; open %s/$app_name'

            -- Save, exit and run install command
            cmd = cmd:format(tmp_path, dfile_name, install_path, install_path)
            if not SaveExitAndInstall(cmd) then
                reaper.MB('\nInstallation cancelled!\n ', title, 0)
            end
            return
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
            -- Run Linux installation and restart
            local cmd = 'pkexec sh %sreaper_linux_%s/install-reaper.sh --install %s'
            -- Comment out the following lines to disable desktop integration etc.
            cmd = cmd .. ' --integrate-desktop'
            cmd = cmd .. ' --usr-local-bin-symlink'
            -- Wrap install command in new shell with sudo privileges (for chaining restart)
            cmd = "/bin/sh -c '" .. cmd .. "' ; %s/reaper"

            -- Linux installer will also create a REAPER directory
            local outer_install_path = install_path:gsub('/REAPER$', '')

            -- Save, exit and run install command
            cmd = cmd:format(tmp_path, arch, outer_install_path, install_path)
            if not SaveExitAndInstall(cmd) then
                reaper.MB('\nInstallation cancelled!\n ', title, 0)
            end
            return
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
            ExecProcess(cmd:format(link, file_path, step_path, step_path))
        end

        if step:match('^open_.-_changelog$') then
            print('\nSTEP ' .. step, debug)
            local file_path, version, changelog
            if step:match('main') then
                main_cl = nil
                file_path = main_path
                version = main_version
                changelog = main_changelog
            else
                dev_cl = nil
                file_path = dev_path
                version = dev_version
                changelog = dev_changelog
            end
            local file = io.open(file_path, 'r')
            local pattern = '<a href=".-" id="thread_title_(%d+)">v*V*'
            pattern = pattern .. version:gsub('%+', '%%+') .. ' '
            -- Default: Open the changelog website directly
            local cmd = browser_cmd .. changelog
            for line in file:lines() do
                local forum_link = line:match(pattern)
                if forum_link then
                    -- If forum post is matched, open this as changelog instead
                    local thread_link = 'https://forum.cockos.com/showthread.php?t='
                    cmd = browser_cmd .. thread_link .. forum_link
                    break
                end
            end
            file:close()
            ExecProcess(cmd)
            os.remove(file_path)
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
print('CPU achitecture: ' .. tostring(arch), debug)
print('Installation path: ' .. tostring(install_path), debug)
print('Resource path: ' .. tostring(res_path), debug)

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
local has_already_run = reaper.GetExtState(title, 'startup') == '1'
reaper.SetExtState(title, 'startup', '1', false)
print('Startup extstate: ' .. tostring(has_already_run), debug)
-- Check if splash is currently visible
local is_splash_vis = reaper.Splash_GetWnd() ~= nil
print('Startup splash: ' .. tostring(is_splash_vis), debug)

if is_splash_vis then
    startup_mode = true
elseif has_already_run then
    startup_mode = false
else
    -- Get file last modification time
    local cmd = 'cd %s && date -r %s +%%s'
    if platform:match('Win') then
        cmd = 'cd /D %s && forfiles /M %s /C "cmd /c echo @ftime"'
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
        os_time = os.date('%H:%M:%S')
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
