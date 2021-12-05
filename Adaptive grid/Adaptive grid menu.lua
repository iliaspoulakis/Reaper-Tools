--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about User settings for adaptive grid
]]

local extname = 'FTC.AdaptiveGrid'
local _, file, sec, cmd = reaper.get_action_context()
local path = file:match('^(.+)[\\/]')

local min_spacing

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

function MenuCreateRecursive(menu)
    local str = ''
    if menu.title then str = str .. '>' .. menu.title .. '|' end

    for i, entry in ipairs(menu) do
        if #entry > 0 then
            str = str .. MenuCreateRecursive(entry) .. '|'
        else
            local arg = entry.arg

            if entry.IsGrayed and entry.IsGrayed(arg) or entry.is_grayed then
                str = str .. '#'
            end

            if entry.IsChecked and entry.IsChecked(arg) or entry.is_checked then
                str = str .. '!'
            end

            if menu.title and i == #menu then str = str .. '<' end
            str = str .. (entry.title or '') .. '|'
        end
    end
    return str:sub(1, #str - 1)
end

function MenuReturnRecursive(menu, idx, i)
    i = i or 1
    for _, entry in ipairs(menu) do
        if #entry > 0 then
            i = MenuReturnRecursive(entry, idx, i)
            if i < 0 then return i end
        elseif entry.title then
            if i == math.floor(idx) then
                if entry.OnReturn then entry.OnReturn(entry.arg) end
                return -1
            end
            i = i + 1
        end
    end
    return i
end

function IsStartupHookEnabled(script_cmd)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = reaper.ReverseNamedCommandLookup(script_cmd)

    if reaper.file_exists(startup_path) then
        -- Read content of __startup.lua
        local startup_file = io.open(startup_path, 'r')
        local content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_id .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        -- Check if line exists and whether it is commented out
        if s and e then
            local hook = content:sub(s, e)
            local comment = hook:match('[^\n]*%-%-[^\n]*reaper%.Main_OnCommand')
            if not comment then return true end
        end
    end
    return false
end

function SetStartupHookEnabled(script_cmd, is_enabled, comment, var_name)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = reaper.ReverseNamedCommandLookup(script_cmd)

    local content = ''
    local hook_exists = false

    -- Check startup script for existing hook
    if reaper.file_exists(startup_path) then

        local startup_file = io.open(startup_path, 'r')
        content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_id .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        if s and e then
            -- Add/remove comment from existing startup hook
            local hook = content:sub(s, e)
            local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
            hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)
            content = content:sub(1, s - 1) .. hook .. content:sub(e + 1)

            -- Write changes to file
            local new_startup_file = io.open(startup_path, 'w')
            new_startup_file:write(content)
            new_startup_file:close()

            hook_exists = true
        end
    end

    -- Create startup hook
    if is_enabled and not hook_exists then
        comment = comment and '-- ' .. comment .. '\n' or ''
        var_name = var_name or 'cmd_name'
        local hook = '%slocal %s = \'_%s\'\nreaper.\z
            Main_OnCommand(reaper.NamedCommandLookup(%s), 0)\n\n'
        hook = hook:format(comment, var_name, cmd_id, var_name)
        local startup_file = io.open(startup_path, 'w')
        startup_file:write(hook .. content)
        startup_file:close()
    end
end

function GetGridMultiplier()
    return tonumber(reaper.GetExtState(extname, 'main_mult')) or 0
end

function SetGridMultiplier(multiplier)
    reaper.SetExtState(extname, 'main_mult', multiplier, true)
end

function GetMIDIGridMultiplier()
    return tonumber(reaper.GetExtState(extname, 'midi_mult')) or 0
end

function SetMIDIGridMultiplier(multiplier)
    reaper.SetExtState(extname, 'midi_mult', multiplier, true)
end

function IsServiceEnabled()
    return reaper.GetExtState(extname, 'is_service_enabled') == ''
end

function SetServiceEnabled(is_enabled)
    local value = is_enabled and '' or 'no'
    reaper.SetExtState(extname, 'is_service_enabled', value, true)
end

function IsServiceRunning()
    return reaper.GetExtState(extname, 'is_service_running') ~= ''
end

function SetServiceRunning(is_running)
    local value = is_running and 'yes' or ''
    reaper.SetExtState(extname, 'is_service_running', value, false)
end

function StartService()
    if GetGridMultiplier() == 0 and GetMIDIGridMultiplier() == 0 then return end

    local script_name = 'Adaptive grid (background service).lua'
    local script_path = ConcatPath(path, script_name)

    if not reaper.file_exists(script_path) then
        local msg = 'Could not start background service!\n\nFile not found:\n%s'
        reaper.MB(msg:format(script_path), 'Adaptive grid', 0)
        return
    end

    local service_cmd = reaper.AddRemoveReaScript(true, 0, script_path, true)
    reaper.Main_OnCommand(service_cmd, 0)
    reaper.AddRemoveReaScript(false, 0, script_path, true)
end

function RunAdaptScript(is_midi)
    local script_path = ConcatPath(path, 'Adapt grid to zoom level.lua')

    if is_midi then
        local hwnd = reaper.MIDIEditor_GetActive()
        if hwnd then
            _G.mode = 2
            dofile(script_path)
        end
    else
        _G.mode = 1
        dofile(script_path)
    end
end

function UpdateToolbarToggleStates(section, multiplier)
    local registered_cmds = reaper.GetExtState(extname, 'registered_cmds')
    for reg_str in registered_cmds:gmatch('(.-);') do
        local reg_sec, reg_cmd, reg_mult = reg_str:match('(%d+) (%d+) (%-?%d+)')
        reg_sec = tonumber(reg_sec)
        reg_cmd = tonumber(reg_cmd)
        reg_mult = tonumber(reg_mult)
        if section == reg_sec then
            local state = reg_mult == multiplier and 1 or 0
            reaper.SetToggleCommandState(reg_sec, reg_cmd, state)
            reaper.RefreshToolbar2(reg_sec, reg_cmd)
        end
    end
end

function GetStringHash(str, length)
    local seed = 0
    -- Use deterministic seed based on str
    for i = 1, str:len() do seed = seed + str:byte(i) end
    math.randomseed(seed)
    local hash_table = {}
    for i = 1, length do hash_table[i] = ('%x'):format(math.random(0, 16)) end
    return table.concat(hash_table)
end

function CreateCustomAction(name, section, command, adapt_command)
    if not adapt_command then return '' end
    local pattern = 'ACT 3 %s "%s" "Custom: %s" %s _%s\n'
    local adapt_command_name = reaper.ReverseNamedCommandLookup(adapt_command)
    local hash = GetStringHash(name, 32)
    return pattern:format(section, hash, name, command, adapt_command_name)
end

function CreateCustomActions()

    local actions = {
        {
            name = 'Zoom horizontally & adapt grid [MIDI CC relative/mousewheel]',
            cmd = 990,
            section = 0,
        },
        {
            name = 'Zoom horizontally & adapt grid [MIDI CC relative/mousewheel]',
            cmd = 40431,
            section = 32060,
        },
        {
            name = 'Zoom horizontally reversed & adapt grid [MIDI CC relative/mousewheel]',
            cmd = 979,
            section = 0,
        },
        {
            name = 'Zoom horizontally reversed & adapt grid [MIDI CC relative/mousewheel]',
            cmd = 40662,
            section = 32060,
        },
        {name = 'Zoom in horizontal & adapt grid', cmd = 1012, section = 0},
        {
            name = 'Zoom in horizontally & adapt grid',
            cmd = 1012,
            section = 32060,
        },
        {name = 'Zoom out horizontal & adapt grid', cmd = 1011, section = 0},
        {
            name = 'Zoom out horizontally & adapt grid',
            cmd = 1011,
            section = 32060,
        },
        {name = 'Zoom time selection & adapt grid', cmd = 40031, section = 0},
        {
            name = 'Zoom to project loop selection & adapt grid',
            cmd = 40726,
            section = 32060,
        },
        {name = 'Zoom out project & adapt grid', cmd = 40295, section = 0},
        {name = 'Zoom to content & adapt grid', cmd = 40466, section = 32060},
        {
            name = 'Zoom to selected notes/CC & adapt grid',
            cmd = 40725,
            section = 32060,
        },
    }

    local script_path = ConcatPath(path, 'Adapt grid to zoom level.lua')

    if not reaper.file_exists(script_path) then
        local msg = 'Could not find script: %s'
        reaper.MB(msg:format(script_path), 'Error', 0)
        return 0, 0
    end

    local main_cmd = reaper.AddRemoveReaScript(true, 0, script_path, true)
    local midi_cmd = reaper.AddRemoveReaScript(true, 32060, script_path, true)

    -- Create key map file
    local key_map_content = ''

    for _, action in ipairs(actions) do
        local adapt_cmd = action.section == 0 and main_cmd or midi_cmd
        local action_str = CreateCustomAction(action.name, action.section,
                                              action.cmd, adapt_cmd)
        key_map_content = key_map_content .. action_str
    end

    -- Save key map file
    local res_path = reaper.GetResourcePath()
    local key_map_name = 'AdaptiveGrid_CustomActions.ReaperKeyMap'
    local key_map_path = ConcatPath(res_path, 'KeyMaps', key_map_name)

    local key_map = io.open(key_map_path, 'w')
    if not key_map then
        reaper.MB('Could not create file!', 'Error', 0)
        return
    end
    key_map:write(key_map_content)
    key_map:close()

    reaper.ShowActionList(0)
    -- Set action list filter to adapt
    if reaper.JS_Window_Find then
        local action_list_title = reaper.JS_Localize('Actions', 'common')
        local action_list = reaper.JS_Window_Find(action_list_title, true)
        local filter = reaper.JS_Window_FindChildByID(action_list, 1324)
        reaper.JS_Window_SetTitle(filter, 'adapt')
    end

    local msg = 'A key map file with custom actions has been created.\n\n\z
        To import this file go to:\n\z
        Actions > Key map... (button) > Import shortcut key map'
    reaper.MB(msg, 'Adaptive grid', 0)

    -- Press keymap button
    if reaper.JS_Window_Find then
        reaper.ShowActionList(0)
        local action_list_title = reaper.JS_Localize('Actions', 'common')
        local action_list = reaper.JS_Window_Find(action_list_title, true)
        local key_map_button = reaper.JS_Window_FindChildByID(action_list, 6)
        reaper.JS_WindowMessage_Post(key_map_button, 'WM_KEYDOWN', 13, 0, 0, 0)
    end
end

function GetIniConfigValue(key, default)
    local ini_file = io.open(reaper.get_ini_file(), 'r')
    local pattern = '^' .. key .. '=(.+)'
    local ret = default
    for line in ini_file:lines() do
        local match = line:match(pattern)
        if match then ret = tonumber(match) or match end
    end
    ini_file:close()
    return ret
end

function ShowMenu(menu_str)
    -- On Windows a dummy window is required to show menu
    if reaper.GetOS():match('Win') then
        local x, y = reaper.GetMousePosition()
        gfx.init('AG', 0, 0, 0, x + 10, y + 20)
        gfx.x, gfx.y = gfx.screentoclient(x + 5, y + 10)
        if reaper.JS_Window_Find then
            local hwnd = reaper.JS_Window_Find('AG', true)
            reaper.JS_Window_Show(hwnd, 'HIDE')
        end
    end
    local ret = gfx.showmenu(menu_str)
    gfx.quit()
    return ret
end

function IsGridVisible() return reaper.GetToggleCommandState(40145) == 1 end

function ShowGrid(is_visible)
    if IsGridVisible() ~= is_visible then reaper.Main_OnCommand(40145, 0) end
end

function IsMIDIGridVisible()
    return reaper.GetToggleCommandStateEx(32060, 1017) == 1
end

function ShowMIDIGrid(is_visible)
    local hwnd = reaper.MIDIEditor_GetActive()
    if IsMIDIGridVisible() ~= is_visible then
        reaper.MIDIEditor_OnCommand(hwnd, 1017)
    end
end

function IsGridStraight(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, false))
    return math.log(grid_div, 2) % 1 == 0
end

function IsGridInTriplets(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, false))
    return 2 / (grid_div % 1) % 3 < 0.0001
end

function GetClosestStraightDivision(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, false))
    return 2 ^ math.floor(math.log(grid_div, 2) + 0.5)
end

function SetGridStraight()
    local _, grid_div, _, swing_amt = reaper.GetSetProjectGrid(0, false)
    if not IsGridStraight(grid_div) then
        if IsGridInTriplets(grid_div) then
            grid_div = grid_div * 3 / 2
        else
            grid_div = GetClosestStraightDivision(grid_div)
        end
        reaper.GetSetProjectGrid(0, true, grid_div, 0, swing_amt)
    end
end

function SetGridToTriplets()
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, false)
    if not IsGridInTriplets(grid_div) then
        if IsGridStraight(grid_div) then
            grid_div = grid_div * 2 / 3
        else
            grid_div = GetClosestStraightDivision(grid_div) * 3 / 2
        end
        reaper.GetSetProjectGrid(0, true, grid_div, 0, swing, swing_amt)
    end
end

function IsGridSwingEnabled()
    local _, _, swing = reaper.GetSetProjectGrid(0, false)
    return swing == 1
end

function ToggleGridSwing()
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, false)
    if swing == 0 and swing_amt == 0 then swing_amt = 1 end
    reaper.GetSetProjectGrid(0, true, grid_div, 1 - swing, swing_amt)
end

function GetUserCustomGridSpacing(is_midi)
    local key = is_midi and 'midi_custom_spacing' or 'custom_spacing'
    local caption = 'Minimum grid spacing in pixels:'
    local custom_spacing = reaper.GetExtState(extname, key)
    local title = 'Adaptive Grid'
    local ret, spacing = reaper.GetUserInputs(title, 1, caption, custom_spacing)
    if not ret then return end
    spacing = tonumber(spacing) or 0
    if spacing <= 0 then
        reaper.MB('Value not permitted!', 'Error', 0)
        return false
    else
        min_spacing = is_midi and 15 or min_spacing
        if spacing < min_spacing then
            local status = ' (Currently: %s pixels in grid settings)'
            status = is_midi and ' (15px)' or status:format(min_spacing)
            local msg = 'The value you set is smaller than the minimum \z
                 grid line spacing%s.\n\z
                 This might have unwanted side effects.'
            reaper.MB(msg:format(status), 'Warning', 0)
        end
        reaper.SetExtState(extname, key, spacing, true)
        return true
    end
end

function CheckUserCustomGridSpacing(is_midi)
    local key = is_midi and 'midi_custom_spacing' or 'custom_spacing'
    local curr_spacing = tonumber(reaper.GetExtState(extname, key))
    if curr_spacing then return curr_spacing end
    return GetUserCustomGridSpacing(is_midi)
end

function SetUserCustomGridSpacing(is_midi)
    local ret = GetUserCustomGridSpacing(is_midi)
    if ret then
        if is_midi then
            SetMIDIAdaptiveGrid(-1)
        else
            SetAdaptiveGrid(-1)
        end
    end
end

function SetFixedGrid(new_grid_div)
    ShowGrid(true)
    SetGridMultiplier(0)
    UpdateToolbarToggleStates(0, 0)
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, false)
    if IsGridInTriplets(grid_div) then new_grid_div = new_grid_div * 2 / 3 end
    reaper.GetSetProjectGrid(0, true, new_grid_div, swing, swing_amt)
end

function CheckFixedGrid(grid_div)
    if not IsGridVisible() or GetGridMultiplier() ~= 0 then return false end
    local _, curr_grid_div = reaper.GetSetProjectGrid(0, false)
    return grid_div == curr_grid_div
end

function SetAdaptiveGrid(multiplier)
    -- Ask user for custom grid spacing if not available
    if multiplier == -1 and not CheckUserCustomGridSpacing(false) then return end

    ShowGrid(true)
    SetGridMultiplier(multiplier)
    UpdateToolbarToggleStates(0, multiplier)

    if multiplier ~= 0 then
        RunAdaptScript(false)
        if IsServiceEnabled() and not IsServiceRunning() then
            StartService()
        end
    end
end

function CheckAdaptiveGrid(multiplier)
    return IsGridVisible() and GetGridMultiplier() == multiplier
end

function SetMIDIAdaptiveGrid(multiplier)
    -- Ask user for custom grid spacing if not available
    if multiplier == -1 and not CheckUserCustomGridSpacing(true) then return end

    ShowMIDIGrid(true)
    SetMIDIGridMultiplier(multiplier)
    UpdateToolbarToggleStates(32060, multiplier)

    if multiplier ~= 0 then
        RunAdaptScript(true)
        if IsServiceEnabled() and not IsServiceRunning() then
            StartService()
        end
    end
end

function CheckMIDIAdaptiveGrid(multiplier)
    return GetMIDIGridMultiplier() == multiplier
end

local options_menu = {
    title = 'Options',
    {
        title = 'Set custom size for arrange view',
        OnReturn = SetUserCustomGridSpacing,
        arg = false,
    },
    {
        title = 'Set custom size for MIDI editor',
        OnReturn = SetUserCustomGridSpacing,
        arg = true,
    },
    {separator = true},
    {title = 'Create custom actions', OnReturn = CreateCustomActions},
    {separator = true},
    {
        title = 'Use background service',
        IsChecked = IsServiceEnabled,
        OnReturn = function()
            local is_enabled = IsServiceEnabled()
            if is_enabled and IsStartupHookEnabled(cmd) then
                SetStartupHookEnabled(cmd, false)
            end
            SetServiceEnabled(not is_enabled)
            if not is_enabled then StartService() end
        end,
    },
    {
        title = 'Run service on startup',
        IsChecked = IsStartupHookEnabled,
        OnReturn = function(script_cmd)
            local is_enabled = not IsStartupHookEnabled(script_cmd)
            local comment = 'Start script: Adaptive grid (background process)'
            local var_name = 'adaptive_grid_cmd'
            SetStartupHookEnabled(script_cmd, is_enabled, comment, var_name)
        end,
        IsGrayed = function() return not IsServiceEnabled() end,
        arg = cmd,
    },
}

local midi_menu = {
    {
        {
            title = 'Fixed',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 0,
        },
        {separator = true},
        {
            title = 'Narrowest',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 1,
        },
        {
            title = 'Narrow',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 2,
        },
        {
            title = 'Medium',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 3,
        },
        {
            title = 'Wide',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 4,
        },
        {
            title = 'Widest',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 6,
        },
        {
            title = 'Custom',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = -1,
        },
    },
    {separator = true},
    {
        title = 'Options',
        {
            title = 'Set custom size for MIDI editor',
            OnReturn = SetUserCustomGridSpacing,
            arg = true,
        },
    },
}

local main_menu = {
    {title = 'Straight', IsChecked = IsGridStraight, OnReturn = SetGridStraight},
    {
        title = 'Triplet',
        IsChecked = IsGridInTriplets,
        OnReturn = SetGridToTriplets,
    },
    {
        title = 'Swing',
        IsChecked = IsGridSwingEnabled,
        OnReturn = ToggleGridSwing,
    },
    {separator = true},
    {
        {
            title = '1/32',
            IsChecked = CheckFixedGrid,
            OnReturn = SetFixedGrid,
            arg = 0.03125,
        },
        {
            title = '1/16',
            IsChecked = CheckFixedGrid,
            OnReturn = SetFixedGrid,
            arg = 0.0625,
        },
        {
            title = '1/8',
            IsChecked = CheckFixedGrid,
            OnReturn = SetFixedGrid,
            arg = 0.125,
        },
        {
            title = '1/4',
            IsChecked = CheckFixedGrid,
            OnReturn = SetFixedGrid,
            arg = 0.25,
        },
        {
            title = '1/2',
            IsChecked = CheckFixedGrid,
            OnReturn = SetFixedGrid,
            arg = 0.5,
        },
        {
            title = '1',
            IsChecked = CheckFixedGrid,
            OnReturn = SetFixedGrid,
            arg = 1,
        },
        {
            title = '2',
            IsChecked = CheckFixedGrid,
            OnReturn = SetFixedGrid,
            arg = 2,
        },
        {
            title = '4',
            IsChecked = CheckFixedGrid,
            OnReturn = SetFixedGrid,
            arg = 4,
        },
    },
    {separator = true},
    {
        {
            title = 'Narrowest',
            IsChecked = CheckAdaptiveGrid,
            OnReturn = SetAdaptiveGrid,
            arg = 1,
        },
        {
            title = 'Narrow',
            IsChecked = CheckAdaptiveGrid,
            OnReturn = SetAdaptiveGrid,
            arg = 2,
        },
        {
            title = 'Medium',
            IsChecked = CheckAdaptiveGrid,
            OnReturn = SetAdaptiveGrid,
            arg = 3,
        },
        {
            title = 'Wide',
            IsChecked = CheckAdaptiveGrid,
            OnReturn = SetAdaptiveGrid,
            arg = 4,
        },
        {
            title = 'Widest',
            IsChecked = CheckAdaptiveGrid,
            OnReturn = SetAdaptiveGrid,
            arg = 6,
        },
        {
            title = 'Custom',
            IsChecked = CheckAdaptiveGrid,
            OnReturn = SetAdaptiveGrid,
            arg = -1,
        },
    },
    {separator = true},
    {
        title = 'Off',
        IsChecked = function() return not IsGridVisible() end,
        OnReturn = ShowGrid,
        arg = false,
    },
    {separator = true},
    {
        title = 'MIDI editor',
        {
            title = 'Fixed',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 0,
        },
        {separator = true},
        {
            title = 'Narrowest',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 1,
        },
        {
            title = 'Narrow',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 2,
        },
        {
            title = 'Medium',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 3,
        },
        {
            title = 'Wide',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 4,
        },
        {
            title = 'Widest',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = 6,
        },
        {
            title = 'Custom',
            IsChecked = CheckMIDIAdaptiveGrid,
            OnReturn = SetMIDIAdaptiveGrid,
            arg = -1,
        },
    },
    options_menu,
}

reaper.Undo_OnStateChange('Show adaptive grid menu')

if reaper.SNM_GetIntConfigVar then
    min_spacing = reaper.SNM_GetIntConfigVar('projgridmin', 8)
else
    min_spacing = GetIniConfigValue('projgridmin', 8)
    reaper.SetExtState(extname, 'projgridmin', min_spacing, true)
end

local is_hook_enabled = IsStartupHookEnabled(cmd)

local has_run = reaper.GetExtState(extname, 'has_run') == 'yes'
reaper.SetExtState(extname, 'has_run', 'yes', false)

if IsServiceEnabled() and not IsServiceRunning() then
    -- Exit immediately when running on startup but adaptive grid is deactivated
    if not has_run and is_hook_enabled then
        UpdateToolbarToggleStates(0, GetGridMultiplier())
        UpdateToolbarToggleStates(32060, GetMIDIGridMultiplier())
        StartService()
        return
    else
        -- Deactivate adaptive grid
        SetGridMultiplier(0)
        SetMIDIGridMultiplier(0)
        UpdateToolbarToggleStates(0, 0)
        UpdateToolbarToggleStates(32060, 0)
    end
end

local menu = sec == 32060 and midi_menu or main_menu
local menu_str = MenuCreateRecursive(menu)
local ret = ShowMenu(menu_str)
MenuReturnRecursive(menu, ret)

