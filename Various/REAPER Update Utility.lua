--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.0
  @about Simple utility to update REAPER to the latest version
  @changelog
    - Reaper will now restart automatically after the install is finished
]]
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
    tmp_dir = tmp_dir:gsub('\r\n', ''):sub(3) .. '\\'
end
local step_path = tmp_dir .. 'reaper_update_step.txt'
local html_path = tmp_dir .. 'reaper_update_site.html'

-- App version & platform architecture
local app = reaper.GetAppVersion()
local curr_version = app:gsub('/.-$', '')
local main_version, dev_version

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

    local is_main_installed = curr_version == main_version
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
            ExecProcess('echo 4 > ' .. step_path)
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

    -- Installed string
    gfx.setfont(1, '', 14 * font_factor)
    local installed = is_main_installed and 'INSTALLED' or ''
    local tw = gfx.measurestr(installed)
    gfx.x = gfx.w / 7 * 2 - tw / 2 + 1
    gfx.y = y + h + 8
    gfx.drawstr(installed, 1)

    -- Dev button
    gfx.set(0.6)
    local x = math.floor(gfx.w / 7) * 4
    local y = math.floor(gfx.h / 4)

    local is_dev_installed = curr_version == dev_version
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
            ExecProcess('echo 4 > ' .. step_path)
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

    -- Installed string
    gfx.setfont(1, '', 14 * font_factor)
    local installed = is_dev_installed and 'INSTALLED' or ''
    local tw = gfx.measurestr(installed)
    gfx.x = gfx.w / 7 * 5 - tw / 2 + 1
    gfx.y = y + h + 8
    gfx.drawstr(installed, 1)
end

function Main()
    -- Check step file for newly completed steps
    local step_file = io.open(step_path, 'r')
    if step_file then
        step = tonumber(step_file:read('*a')) or 0
        step_file:close()
        os.remove(step_path)

        if step == 1 then
            -- Download the HTML of the REAPER website
            task = 'Checking latest release version...'
            local cmd = 'curl -L %s > %s && echo 2 > %s'
            ExecProcess(cmd:format(main_dlink, html_path, step_path))
        end

        if step == 2 then
            -- Parse the REAPER website html for the download link
            local file = io.open(html_path, 'r')
            main_dlink = ParseDownloadLink(file, main_dlink)
            file:close()
            os.remove(html_path)
            if not main_dlink then
                local msg = 'Could not parse download link!\nOS: %s\nArch: %s'
                reaper.MB(msg:format(platform, arch), 'Error', 0)
                return
            end
            -- Download the HTML of the LANDOLEET website
            task = 'Checking latest pre-release version...'
            local cmd = 'curl -L %s > %s && echo 3 > %s'
            ExecProcess(cmd:format(dev_dlink, html_path, step_path))
        end

        if step == 3 then
            -- Parse the LANDOLEET website html for the download link
            local file = io.open(html_path, 'r')
            dev_dlink = ParseDownloadLink(file, dev_dlink)
            file:close()
            os.remove(html_path)
            if not dev_dlink then
                local msg = 'Could not parse dev download link!\nOS: %s\nArch: %s'
                reaper.MB(msg:format(platform, arch), 'Error', 0)
                return
            end
            -- Show buttons with both versions (user choice)
            main_version = main_dlink:match('/reaper(.-)[_%-]'):gsub('(.)', '%1.', 1)
            dev_version = dev_dlink:match('/reaper(.-)[_%-]'):gsub('(.)', '%1.', 1)
            show_buttons = true
        end

        if step == 4 then
            -- Download chosen REAPER version
            task = 'Downloading...'
            dfile_name = dlink:gsub('.-/', '')
            local cmd = 'curl -L -o %s%s %s && echo 5 > %s'
            ExecProcess(cmd:format(tmp_dir, dfile_name, dlink, step_path))
        end

        if step == 5 then
            if platform:match('Win') then
                if not SaveAndQuit() then
                    reaper.MB('\nInstallation cancelled!\n ', title, 0)
                    return
                end
                -- Run Windows installation and restart reaper
                local cmd = '%s%s /S /D=%s & cd %s && reaper.exe'
                ExecProcess(cmd:format(tmp_dir, dfile_name, install_dir, install_dir))
            end
            if platform:match('OSX') then
            -- TODO: OSX support
            end
            if platform:match('Other') then
                -- Extract tar file
                task = 'Extracting...'
                local cmd = 'tar -xf %s%s -C %s && echo 6 > %s'
                ExecProcess(cmd:format(tmp_dir, dfile_name, tmp_dir, step_path))
            end
        end

        if step == 6 then
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
            cmd = "/bin/sh -c '" .. cmd .. "' && %s/reaper"

            -- Linux installer will also create a REAPER directory
            local outer_install_dir = install_dir:gsub('/REAPER$', '')
            ExecProcess(cmd:format(tmp_dir, arch, outer_install_dir, install_dir))
        end
    end
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
    reaper.defer(Main)
end

-- Get REAPER window size
local w_x, w_y, w_w, w_h
for line in io.open(reaper.get_ini_file(), 'r'):lines() do
    w_x = w_x or line:match('^wnd_x=(.-)$')
    w_y = w_y or line:match('^wnd_y=(.-)$')
    w_w = w_w or line:match('^wnd_w=(.-)$')
    w_h = w_h or line:match('^wnd_h=(.-)$')
end

-- Open script window
gfx.clear = reaper.ColorToNative(37, 37, 37)
local gfx_w, gfx_h = 500, 250
gfx.init(title, gfx_w, gfx_h, 0, w_x + (w_w - gfx_w) / 2, w_y + (w_h - gfx_h) / 2)

if platform:match('OSX') then
    task = 'OSX is not supported (yet)...'
else
    -- Write a 1 to the step file to trigger the first step
    ExecProcess('echo 1 > ' .. step_path)
end
reaper.defer(Main)
