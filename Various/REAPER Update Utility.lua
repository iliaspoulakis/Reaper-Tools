--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.4.1
  @about Simple utility to update REAPER to the latest version
  @changelog
    - Added debug button
]]
-- Set this to true to show debugging output
local debug = false
-- Set this to true to save debugging output in a log file
local log = false

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
local old_dlink = 'https://www.landoleet.org/old/'
local main_changelog = 'https://www.reaper.fm/whatsnew.txt'
local dev_changelog = 'https://www.landoleet.org/whatsnew-dev.txt'

-- Paths
local install_path = reaper.GetExePath()
local res_path = reaper.GetResourcePath()
local tmp_path, step_path, main_path, dev_path

-- Startup mode
local startup_mode = false
local start_timeout = 90
local load_timeout = 3

-- Download variables
local dl_cmd, browser_cmd, user_dlink, dfile_name

-- GUI variables
local step = 0
local direction = 1
local opacity = 0.65
local click = {}
local is_main_clicked = false
local main_cl, dev_cl
local show_buttons = false
local task = 'Initializing...'
local title = 'REAPER Update Utility'
local font_factor = platform:match('Win') and 1.25 or 1

local main_list = {}
local dev_list = {}

local debug_str = ''

function print(msg, debug)
    if debug == nil or debug then
        reaper.ShowConsoleMsg(tostring(msg) .. '\n')
    end
    if log then
        local separator = platform:match('Win') and '\\' or '/'
        local log_path = res_path .. separator .. 'update-utility.log'
        local log_file = io.open(log_path, 'a')
        log_file:write(msg, '\n')
        log_file:close()
    end
    debug_str = debug_str .. tostring(msg) .. '\n'
end

function ExecProcess(cmd, timeout)
    if platform:match('Win') then
        cmd = 'cmd.exe /Q /C "' .. cmd .. '"'
    else
        cmd = '/bin/sh -c "' .. cmd .. '"'
    end
    local ret = reaper.ExecProcess(cmd, timeout or -2)
    print('\nExecuting command:\n' .. cmd, debug)
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

function ExecInstall(install_cmd)
    -- File: Close all projects
    reaper.Main_OnCommand(40886, 0)

    if reaper.IsProjectDirty(0) == 0 then
        -- In Windows execute after quitting to avoid error dialog
        if not platform:match('Win') then
            ExecProcess(install_cmd)
        end
        -- File: Quit REAPER
        reaper.Main_OnCommand(40004, 0)
        if platform:match('Win') then
            ExecProcess(install_cmd)
        end
    else
        reaper.MB('\nInstallation cancelled!\n ', title, 0)
    end
end

function GetFilePattern()
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
    return 'href="([^_"]-' .. file_pattern .. ')"'
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

function parseOldDownloadLinks(file, old_dlink)
    local file_pattern = GetFilePattern()
    -- Find matching file download links
    for line in file:lines() do
        local file_name = line:match(file_pattern)
        if file_name and file_name:match('reaper') then
            local link = old_dlink .. file_name
            local main_match = file_name:match('reaper(%d+%a*)_')
            -- Divide matches into separate lists for main and dev releases
            if main_match then
                main_match = main_match:gsub('^(%d)', '%1.')
                if main_match ~= main_version then
                    main_list[#main_list + 1] = {version = main_match, link = link}
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

function showOldMenu()
    local list = is_main_clicked and main_list or dev_list
    local prev_group
    local menu_list = {}
    local group_list = {}
    -- Reorder list for showing in menu (reverse main order, but not sublists)
    for i = #list, 1, -1 do
        local group = list[i].version:match('^[%d.]+')
        if prev_group and group ~= prev_group or i == 1 then
            if #group_list > 1 then
                group_list[1].is_last = true
                group_list[#group_list].is_first = true
            end
            for n = #group_list, 1, -1 do
                if list[i].version ~= curr_version then
                    menu_list[#menu_list + 1] = group_list[n]
                end
            end
            group_list = {}
        end
        group_list[#group_list + 1] = list[i]
        prev_group = group
    end

    -- Create string to use with showmenu function
    local menu = ''
    for i, item in ipairs(menu_list) do
        local sep = i == 1 and '' or '|'
        if item.is_first then
            local group = item.version:match('^[%d.]+')
            sep = sep .. '>' .. group .. '|'
        end
        if item.is_last then
            sep = sep .. '<'
        end
        menu = menu .. sep .. item.version
    end

    -- Determine where to show the menu
    gfx.x = gfx.w * (is_main_clicked and 1 or 4) / 7
    gfx.y = gfx.h * 3 / 4 + 4

    local ret = gfx.showmenu(menu)
    if ret > 0 then
        user_dlink = menu_list[ret].link
        ExecProcess('echo download > ' .. step_path)
        show_buttons = false
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
        gfx.set(1.15 * opacity, 0.92 * opacity, 0.55 * opacity)
    end

    if is_hover then
        gfx.set(0.72)
    end

    if is_installed then
        gfx.set(0.1, 0.65, 0.5)
    end

    -- Button left click
    if not is_installed and is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
        click = {type = is_main, action = 'install'}
    end

    -- Button left click release
    if click.type == is_main and click.action == 'install' and gfx.mouse_cap == 0 then
        if is_hover and dlink ~= '' then
            user_dlink = dlink
            ExecProcess('echo download > ' .. step_path)
            show_buttons = false
        end
        click = {}
    end

    -- Button right click
    if is_hover and gfx.mouse_cap == 2 then
        gfx.set(0.8, 0.6, 0.35)
        click = {type = is_main, action = 'show_old'}
    end

    -- Button right click release
    if click.type == is_main and click.action == 'show_old' and gfx.mouse_cap == 0 then
        if is_hover then
            is_main_clicked = is_main
            if #main_list > 0 and #dev_list > 0 then
                reaper.defer(showOldMenu)
            else
                show_buttons = false
                task = 'Fetching old versions...'
                ExecProcess('echo get_old_versions > ' .. step_path)
            end
        end
        click = {}
    end

    -- Border
    gfx.roundrect(x, y, w, h, 4, 1)
    gfx.roundrect(x + 1, y, w, h, 4, 1)
    gfx.roundrect(x, y + 1, w, h, 4, 1)

    -- Version
    gfx.setfont(1, '', 30 * font_factor, string.byte('b'))
    local version_text = version:match('^([%d%.]+)') or 'none'
    local t_w, t_h = gfx.measurestr(version_text)
    gfx.x = math.floor(x + gfx.w / 7 - t_w / 2) + 1
    gfx.y = math.floor(gfx.h / 2 - t_h / 2)
    gfx.drawstr(version_text, 1)

    -- Subversion
    gfx.setfont(1, '', 15 * font_factor, string.byte('i'))
    local subversion_text = version:match('[%d%.]+(.-)$') or ''
    local t_w = gfx.measurestr(subversion_text)
    gfx.x = math.floor(x + gfx.w / 7 - t_w / 2) + 1
    gfx.y = math.floor(gfx.y + t_h) + 5
    gfx.drawstr(subversion_text, 1)

    -- Changelog
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

    gfx.set(0.57)

    if is_hover then
        gfx.set(0.72)
    end

    -- Changelog left click
    if is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
        click = {type = is_main, action = 'show_cl'}
    end

    -- Changelog left click release
    if click.type == is_main and click.action == 'show_cl' and gfx.mouse_cap == 0 then
        if is_hover then
            if is_main then
                main_cl = 'CHANGELOG'
                ExecProcess('echo get_main_changelog > ' .. step_path)
            elseif dev_version ~= 'none' then
                dev_cl = 'CHANGELOG'
                ExecProcess('echo get_dev_changelog > ' .. step_path)
            end
        end
        click = {}
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

    -- Debug output
    gfx.set(0.22)
    local is_hover = m_x >= gfx.w - 14 and m_x <= gfx.w - 2 and m_x >= 2 and m_y <= 14

    if is_hover then
        gfx.set(0.5)
    end

    -- Debug output left click
    if is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
        click = {type = is_main, action = 'debug'}
    end

    -- Debug output left click release
    if click.type == is_main and click.action == 'debug' and gfx.mouse_cap == 0 then
        if is_hover then
            reaper.ClearConsole()
            reaper.ShowConsoleMsg(debug_str)
        end
        click = {}
    end

    gfx.rect(gfx.w - 8, 4, 3, 3)
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
    local res = 0
    local i = 2
    for num in time:gmatch('%d+') do
        res = res + tonumber(num) * 60 ^ i
        i = i - 1
    end
    -- Make sure it works shortly before 12
    res = res % (12 * 60 * 60)
    if res <= start_timeout then
        res = res + 12 * 60 * 60
    end
    return res
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
        print('\n--STEP ' .. tostring(step), debug)
        step_file:close()
        os.remove(step_path)

        if step == 'check_update' then
            -- Download the HTML of the REAPER website
            local cmd = dl_cmd .. ' && ' .. dl_cmd
            cmd = cmd:format(main_dlink, main_path, dev_dlink, dev_path)
            -- Show buttons if download succeeds, otherwise show error
            cmd = cmd .. ' && echo display_update > %s || echo err_internet > %s'
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
            local file = io.open(dev_path, 'r')
            if not file then
                reaper.MB('File not found: ' .. dev_path, 'Error', 0)
                return
            end
            dev_dlink = ParseDownloadLink(file, dev_dlink)
            file:close()
            os.remove(dev_path)
            -- Parse latest versions from download link
            main_version = main_dlink:match('/reaper(.-)[_%-]'):gsub('(.)', '%1.', 1)
            if dev_dlink then
                dev_version = dev_dlink:match('/reaper(.-)[_%-]'):gsub('(.)', '%1.', 1)
            else
                dev_dlink = ''
                dev_version = 'none'
            end

            local saved_main_version = reaper.GetExtState(title, 'main_version')
            local saved_dev_version = reaper.GetExtState(title, 'dev_version')

            print('\nCurr version: ' .. tostring(curr_version), debug)
            print('\nSaved main version: ' .. tostring(saved_main_version), debug)
            print('Saved dev version: ' .. tostring(saved_dev_version), debug)
            print('\nMain version: ' .. tostring(main_version), debug)
            print('Dev version: ' .. tostring(dev_version), debug)

            -- Check if there's new version
            if saved_main_version ~= main_version then
                new_version = main_version
                print('Found new main version', debug)
            end
            if saved_dev_version ~= dev_version then
                -- If both are new, show update to the currently installed version
                local is_dev_installed = not curr_version:match('^%d+%.%d+%a*$')
                if (not new_version or is_dev_installed) and dev_version ~= 'none' then
                    new_version = dev_version
                    print('Found new dev version', debug)
                end
            end
            -- Check if the new version is already installed (first script run)
            if new_version == curr_version then
                new_version = nil
                print('Newly found version is already installed', debug)
            end
            -- Save latest version numbers in extstate for next check
            reaper.SetExtState(title, 'main_version', main_version, true)
            reaper.SetExtState(title, 'dev_version', dev_version, true)

            print('\nNew version: ' .. tostring(new_version), debug)

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
            -- Download chosen REAPER version
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
            task = 'Downloading...'
        end

        if step == 'windows_install' then
            -- Windows installer: /S is silent mode, /D specifies directory
            local cmd = '%s /S /D=%s & cd /D %s & start reaper.exe & del %s'
            local dfile_path = tmp_path .. dfile_name
            ExecInstall(cmd:format(dfile_path, install_path, install_path, dfile_path))
            return
        end

        if step == 'osx_install' then
            -- Mount downloaded dmg file and get the mount directory (yes agrees to license)
            local cmd = 'mount_dir=$(yes | hdiutil attach %s%s | grep Volumes | cut -f 3)'
            -- Get the .app name
            cmd = cmd .. ' && cd $mount_dir && app_name=$(ls | grep REAPER)'
            -- Copy .app to install path
            cmd = cmd .. ' && cp -rf $app_name %s'
            -- Unmount file and restart reaper
            cmd = cmd .. ' ; cd && hdiutil unmount $mount_dir ; open %s/$app_name'
            ExecInstall(cmd:format(tmp_path, dfile_name, install_path, install_path))
            return
        end

        if step == 'linux_extract' then
            -- Extract tar file
            local cmd = 'tar -xf %s%s -C %s && echo linux_install > %s'
            ExecProcess(cmd:format(tmp_path, dfile_name, tmp_path, step_path))
            task = 'Extracting...'
        end

        if step == 'linux_install' then
            -- Run Linux installation and restart
            local cmd = 'pkexec sh %sreaper_linux_%s/install-reaper.sh --install %s'
            -- Comment out the following lines to disable desktop integration etc.
            cmd = cmd .. ' --integrate-desktop'
            cmd = cmd .. ' --usr-local-bin-symlink'
            -- Wrap install command in new shell with sudo privileges (for chaining restart)
            cmd = "/bin/sh -c '" .. cmd .. "' ; %s/reaper"
            -- Linux installer will also create a REAPER directory
            local outer_install_path = install_path:gsub('/REAPER$', '')
            ExecInstall(cmd:format(tmp_path, arch, outer_install_path, install_path))
            return
        end

        if step == 'get_old_versions' then
            -- Show buttons if download succeeds, otherwise show error
            local cmd = dl_cmd
            cmd = cmd .. ' && echo show_old_versions > %s || echo err_internet > %s'
            cmd = cmd:format(old_dlink, main_path, step_path, step_path)
            ExecProcess(cmd)
        end

        if step == 'show_old_versions' then
            local file = io.open(main_path, 'r')
            if not file then
                reaper.MB('File not found: ' .. main_path, 'Error', 0)
                return
            end
            parseOldDownloadLinks(file, old_dlink)
            os.remove(main_path)
            task = ''
            show_buttons = true
            reaper.defer(showOldMenu)
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
        end

        if step == 'err_internet' then
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

print('\n-------------------------------------------', debug)
print('CPU achitecture: ' .. tostring(arch), debug)
print('Installation path: ' .. tostring(install_path), debug)
print('Resource path: ' .. tostring(res_path), debug)
print('Reaper version: ' .. tostring(curr_version), debug)

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

if has_already_run then
    startup_mode = false
elseif is_splash_vis then
    startup_mode = true
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
        -- Touch file and get it's modification date (os.time format is unreliable)
        cmd = 'cd /D %s && copy /b %s +,, >nul 2>&1 && '
        cmd = cmd .. 'forfiles /M %s /C "cmd /c echo @ftime"'
        cmd = cmd:format(res_path, 'reaper-reginfo2.ini', 'reaper-reginfo2.ini')
        os_time = ExecProcess(cmd, 1000)
        print('Start time (raw): ' .. start_time, debug)
        print('Load time (raw): ' .. load_time, debug)
        print('Curr time (raw): ' .. os_time, debug)
        -- Convert h:m:s syntax to seconds
        start_time = ConvertToSeconds(start_time)
        load_time = ConvertToSeconds(load_time)
        os_time = ConvertToSeconds(os_time)
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
    local is_same_time = start_time == load_time
    print('Same start time: ' .. tostring(is_same_time), debug)
    startup_mode = is_in_start_window and (is_in_load_window or is_same_time)
end

if log then
    local msg =
        " \nLogging to file is enabled!\n\nYou can find the file 'update-utility.log' \z
    in your resource directory:\n--> Options --> Show REAPER resource path...\n "
    reaper.MB(msg, title, 0)
end

print('Startup Mode: ' .. tostring(startup_mode), debug)
if not startup_mode then
    ShowGUI()
end

-- Trigger the first step (steps are triggered by writing to the step file)
ExecProcess('echo check_update > ' .. step_path)
reaper.defer(Main)
