--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.1
  @about Simple utility to update REAPER to the latest version
  @changelog
    - Reaper will now restart automatically after the install is finished
    - Added startup mode for use as global startup action
]]
-------------------------------- USER CONFIGURATION --------------------------------

-- Startup mode: Show GUI when updates are available (first script run only)
local startup_mode = false

-- Show GUI for new pre-release versions
local startup_check_dev_releases = false

------------------------------------------------------------------------------------

local platform = reaper.GetOS()
local install_dir = reaper.GetExePath()

-- Links to REAPER websites
local main_dlink = 'https://www.reaper.fm/download.php'
local dev_dlink = 'https://www.landoleet.org/'
local dlink, dfile_name

-- Define paths to temporary files
local tmp_dir = '/tmp/'
if platform:match('Win') then
    tmp_dir = reaper.ExecProcess('cmd.exe /c echo %TEMP%', 5000)
    tmp_dir = tmp_dir:match('^%d+(.+)$'):gsub('[\r\n]', '') .. '\\'
end
local step_path = tmp_dir .. 'reaper_uutil_step.txt'
local main_path = tmp_dir .. 'reaper_uutil_main.html'
local dev_path = tmp_dir .. 'reaper_uutil_dev.html'

-- App version & platform architecture
local app = reaper.GetAppVersion()
local curr_version = app:gsub('/.-$', '')
local main_version, dev_version, new_version

local arch = app:match('/(.-)$')
arch = arch == 'linux64' and 'x86_64' or arch
arch = arch == 'linux32' and 'i686' or arch

-- GUI variables
local step = 0
local direction = 1
local opacity = 0.65
local show_buttons = false
local task = 'Initializing...'
local title = 'REAPER Update Utility'
local font_factor = platform:match('Win') and 1.25 or 1

function ExecProcess(cmd)
    if platform:match('Win') then
        cmd = 'cmd.exe /c ' .. cmd
    else
        cmd = '/bin/sh -c "' .. cmd .. '"'
    end
    reaper.ExecProcess(cmd, -2)
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
    local file_pattern
    if platform:match('Win') then
        file_pattern = (arch and '_' .. arch or '') .. '%-install%.exe'
    end

    if platform:match('OSX') then
        file_pattern = '_' .. arch .. '%.dmg'
    end

    if platform:match('Other') then
        file_pattern = '_linux_' .. arch .. '%.tar%.xz'
    end

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
    gfx.x = (gfx.w - w) / 2
    gfx.y = (gfx.h - h) / 2.1
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

    if is_main_installed or is_hover then
        gfx.set(0.1, 0.65, 0.5)
    end

    if not is_main_installed and is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
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
    local tw, th = gfx.measurestr(main_version)
    gfx.x = gfx.w / 7 * 2 - tw / 2 + 1
    gfx.y = gfx.h / 2 - th / 2
    gfx.drawstr(main_version, 1)

    -- Info string
    local info = ''
    if is_main_new then
        gfx.set(1.12 * opacity, 0.92 * opacity, 0.67 * opacity)
        info = 'NEW!'
    end
    if is_main_installed then
        gfx.set(0.12, 0.52, 0.42)
        info = 'INSTALLED'
    end
    gfx.setfont(1, '', 14 * font_factor)
    local tw = gfx.measurestr(info)
    gfx.x = gfx.w / 7 * 2 - tw / 2 + 1
    gfx.y = y + h + 8
    gfx.drawstr(info, 1)

    -- Dev button
    gfx.set(0.6)
    local x = math.floor(gfx.w / 7) * 4
    local y = math.floor(gfx.h / 4)

    local is_dev_new = dev_version == new_version
    local is_dev_installed = dev_version == curr_version
    local is_hover = m_x >= x and m_x <= x + w and m_y >= y and m_y <= y + h

    if is_dev_installed or is_hover then
        gfx.set(0.1, 0.65, 0.5)
    end

    if not is_dev_installed and is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.55, 0.25)
    end

    if not is_dev_installed and is_hover and gfx.mouse_cap == 1 then
        gfx.set(0.8, 0.6, 0.35)
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
    local tw, th = gfx.measurestr(version)
    gfx.x = gfx.w / 7 * 5 - tw / 2 + 1
    gfx.y = gfx.h / 2 - th / 2
    gfx.drawstr(version, 1)

    -- Dev string
    gfx.setfont(1, '', 15 * font_factor, string.byte('i'))
    local version = dev_version:match('(+.-)$')
    local tw = gfx.measurestr(version)
    gfx.x = gfx.w / 7 * 5 - tw / 2 + 1
    gfx.y = gfx.y + th + 4
    gfx.drawstr(version, 1)

    -- Info string
    local info = ''
    if is_dev_new then
        gfx.set(1.12 * opacity, 0.92 * opacity, 0.67 * opacity)
        info = 'NEW!'
    end
    if is_dev_installed then
        gfx.set(0.08, 0.52, 0.41)
        info = 'INSTALLED'
    end
    gfx.setfont(1, '', 14 * font_factor)
    local tw = gfx.measurestr(info)
    gfx.x = gfx.w / 7 * 5 - tw / 2 + 1
    gfx.y = y + h + 8
    gfx.drawstr(info, 1)
end

function checkNewVersion()
    -- Convert version strings to comparable numbers
    local curr_num = tonumber(({curr_version:gsub('[^%d.]', '')})[1])
    local main_num = tonumber(({main_version:gsub('[^%d.]', '')})[1])
    local dev_num = tonumber(({dev_version:gsub('[^%d.]', '')})[1])
    local latest_num = tonumber(reaper.GetExtState(title, 'version')) or curr_num
    local ret = false
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

function ShowGUI()
    -- Get REAPER window size
    local w_x, w_y, w_w, w_h
    for line in io.open(reaper.get_ini_file(), 'r'):lines() do
        w_x = w_x or line:match('^wnd_x=(.-)$')
        w_y = w_y or line:match('^wnd_y=(.-)$')
        w_w = w_w or line:match('^wnd_w=(.-)$')
        w_h = w_h or line:match('^wnd_h=(.-)$')
    end
    -- Show script window
    gfx.clear = reaper.ColorToNative(37, 37, 37)
    local gfx_w, gfx_h = 500, 250
    gfx.init(title, gfx_w, gfx_h, 0, w_x + (w_w - gfx_w) / 2, w_y + (w_h - gfx_h) / 2)
end

function Main()
    -- Check step file for newly completed steps
    local step_file = io.open(step_path, 'r')
    if step_file then
        step = step_file:read('*a'):gsub('[^%w_]+', '')
        step_file:close()
        os.remove(step_path)

        if step == 'check_update' then
            task = 'Checking for updates...'
            -- Download the HTML of the REAPER website
            local cmd = 'curl -L %s > %s && curl -L %s > %s'
            cmd = cmd:format(main_dlink, main_path, dev_dlink, dev_path)
            -- Show buttons if download succeeds, otherwise show error
            cmd = cmd .. ' && echo show_buttons > %s || echo err_internet > %s'
            ExecProcess(cmd:format(step_path, step_path))
        end

        if step == 'show_buttons' then
            -- Parse the REAPER website html for the download link
            local file = io.open(main_path, 'r')
            main_dlink = ParseDownloadLink(file, main_dlink)
            file:close()
            os.remove(main_path)
            -- Parse the LANDOLEET website html for the download link
            local file = io.open(dev_path, 'r')
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
                    return
                end
                startup_mode = false
                ShowGUI()
            end
            -- Show buttons with both versions (user choice)
            show_buttons = true
        end

        if step == 'download' then
            -- Download chosen REAPER version
            task = 'Downloading...'
            dfile_name = dlink:gsub('.-/', '')
            local cmd = 'curl -L -o %s%s %s'
            cmd = cmd:format(tmp_dir, dfile_name, dlink)

            local next_step
            if platform:match('Win') then
                next_step = 'windows_install'
            end
            if platform:match('OSX') then
                next_step = 'osx_install'
            end
            if platform:match('Other') then
                next_step = 'linux_extract'
            end
            -- Go to next step if download succeeds, otherwise show error
            cmd = cmd .. '&& echo %s > %s || echo err_internet > %s'
            ExecProcess(cmd:format(next_step, step_path, step_path))
        end

        if step == 'windows_install' then
            if not SaveAndQuit() then
                reaper.MB('\nInstallation cancelled!\n ', title, 0)
                return
            end
            -- Run Windows installation and restart reaper
            local cmd = '%s%s /S /D=%s & cd %s & reaper.exe'
            ExecProcess(cmd:format(tmp_dir, dfile_name, install_dir, install_dir))
        end

        -- TODO: OSX support
        if step == 'osx_install' then
        end

        if step == 'linux_extract' then
            -- Extract tar file
            task = 'Extracting...'
            local cmd = 'tar -xf %s%s -C %s && echo linux_install > %s'
            ExecProcess(cmd:format(tmp_dir, dfile_name, tmp_dir, step_path))
        end

        if step == 'linux_install' then
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
            local outer_install_dir = install_dir:gsub('/REAPER$', '')
            ExecProcess(cmd:format(tmp_dir, arch, outer_install_dir, install_dir))
        end

        if step == 'err_internet' then
            if not startup_mode then
                local msg = 'Could not fetch latest version. Please check your internet'
                reaper.MB(msg, 'Error', 0)
            end
            return
        end
    end
    if not startup_mode then
        -- Exit script on window close & escape key
        local char = gfx.getchar()
        if char == -1 or char == 27 then
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

-- Save the extstate value 'started' with persist=false (erase on startup)
startup_mode = startup_mode and reaper.GetExtState(title, 'started') ~= '1'
reaper.SetExtState(title, 'started', '1', false)

if not startup_mode then
    ShowGUI()
end

if platform:match('OSX') then
    task = 'OSX is not supported (yet)...'
else
    -- Write a 1 to the step file to trigger the first step
    ExecProcess('echo check_update > ' .. step_path)
end
reaper.defer(Main)
