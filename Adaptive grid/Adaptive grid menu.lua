--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about User settings for adaptive grid
]]
local extname = 'FTC.AdaptiveGrid'
local _, file, sec, cmd = reaper.get_action_context()
local path = file:match('^(.+)[\\/]')

-- Check REAPER version
local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(3) end

local min_spacing

local is_frame_grid = reaper.GetToggleCommandState(41885) == 1
local is_measure_grid = reaper.GetToggleCommandState(40725) == 1

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

            if entry.title or entry.separator then
                str = str .. (entry.title or '') .. '|'
            end
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

function GetStartupHookCommandID()
    if _G.cmd then return _G.cmd end
    -- Note: Startup hook commands have to be in the main section
    local _, script_file, section, cmd_id = reaper.get_action_context()
    if section == 0 then
        -- Save command name when main section script is run first
        local cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
        reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
    else
        -- Look for saved command name by main section script
        local cmd_name = reaper.GetExtState(extname, 'hook_cmd_name')
        cmd_id = reaper.NamedCommandLookup(cmd_name)
        if cmd_id == 0 then
            -- Add the script to main section (to get cmd id)
            cmd_id = reaper.AddRemoveReaScript(true, 0, script_file, true)
            if cmd_id ~= 0 then
                -- Save command name to avoid adding script on next run
                cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
                reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
            end
        end
    end
    return cmd_id
end

function IsStartupHookEnabled()
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    if reaper.file_exists(startup_path) then
        -- Read content of __startup.lua
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return false end
        local content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
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

function SetStartupHookEnabled(is_enabled, comment, var_name)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    local content = ''
    local hook_exists = false

    -- Check startup script for existing hook
    if reaper.file_exists(startup_path) then
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return end

        content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        if s and e then
            -- Add/remove comment from existing startup hook
            local hook = content:sub(s, e)
            local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
            hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)
            content = content:sub(1, s - 1) .. hook .. content:sub(e + 1)

            -- Write changes to file
            local new_startup_file = io.open(startup_path, 'w')
            if not new_startup_file then return end
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
        hook = hook:format(comment, var_name, cmd_name, var_name)
        local startup_file = io.open(startup_path, 'w')
        if not startup_file then return end
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
            local env = setmetatable({_G = {mode = 2}}, {__index = _G})
            local chunk = loadfile(script_path, 'bt', env)
            if chunk then chunk() end
        end
    else
        local env = setmetatable({_G = {mode = 1}}, {__index = _G})
        local chunk = loadfile(script_path, 'bt', env)
        if chunk then chunk() end
    end
end

function RegisterToolbarToggleState(section, command, multiplier)
    local command_name = reaper.ReverseNamedCommandLookup(command)
    local entry = ('%s %s %s'):format(section, command_name, multiplier)
    local entries = reaper.GetExtState(extname, 'toolbar_entries')
    if not entries:find(entry, 0, true) then
        entries = entries .. entry .. ';'
        reaper.SetExtState(extname, 'toolbar_entries', entries, true)
    end
end

function UpdateToolbarToggleStates(section, multiplier)
    local entries = reaper.GetExtState(extname, 'toolbar_entries')
    local updated_entries = ''
    for entry in entries:gmatch('(.-);') do
        local pattern = '(%d+) (.-) (%-?%d+)'
        local entry_sec, entry_cmd_name, entry_mult = entry:match(pattern)
        entry_sec = tonumber(entry_sec)
        entry_mult = tonumber(entry_mult)
        local entry_cmd = reaper.NamedCommandLookup('_' .. entry_cmd_name)
        if section == entry_sec and entry_cmd > 0 then
            local state = entry_mult == multiplier and 1 or 0
            if entry_mult == 1000 and multiplier ~= 0 then state = 1 end
            reaper.SetToggleCommandState(entry_sec, entry_cmd, state)
            reaper.RefreshToolbar2(entry_sec, entry_cmd)
            updated_entries = updated_entries .. entry .. ';'
        elseif section ~= entry_sec then
            updated_entries = updated_entries .. entry .. ';'
        end
    end
    if updated_entries ~= entries then
        reaper.SetExtState(extname, 'toolbar_entries', updated_entries, true)
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

function GetIniConfigValue(key, default)
    local ini_file = io.open(reaper.get_ini_file(), 'r')
    if not ini_file then return default end
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
    -- Toggle fullscreen
    local is_full_screen = reaper.GetToggleCommandState(40346) == 1

    -- Determine operating system
    local os = reaper.GetOS()
    local is_windows = os:match('Win')
    local is_mac = os:match('OSX') or os:match('macOS')

    -- Get currently focused window (make sure that focus doesn't change)
    local focus_hwnd
    if reaper.JS_Window_GetFocus then
        focus_hwnd = reaper.JS_Window_GetFocus()
    end

    -- On Windows and MacOS (fullscreen), a dummy window is required to show menu
    if is_windows or is_mac and is_full_screen then
        local offs = is_windows and {x = 10, y = 20} or {x = 0, y = 0}
        local x, y = reaper.GetMousePosition()
        gfx.init('FTC.AG', 0, 0, 0, x + offs.x, y + offs.y)
        gfx.x, gfx.y = gfx.screentoclient(x + offs.x / 2, y + offs.y / 2)
        if reaper.JS_Window_Find then
            if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end
            local hwnd = reaper.JS_Window_Find('FTC.AG', true)
            reaper.JS_Window_Show(hwnd, 'HIDE')
            reaper.JS_Window_SetOpacity(hwnd, 'ALPHA', 0)
        end
    end

    if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end

    local ret = gfx.showmenu(menu_str)
    gfx.quit()

    if focus_hwnd then reaper.JS_Window_SetFocus(focus_hwnd) end
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

function GetStraightGrid(grid_div)
    if math.log(grid_div, 2) % 1 == 0 then return grid_div end
    if grid_div > 1 then
        local is_triplet = 2 * grid_div % (2 / 3) == 0
        if is_triplet then return grid_div * (3 / 2) end
        local is_quintuplet = 4 * grid_div % (4 / 5) == 0
        if is_quintuplet then return grid_div * (5 / 4) end
        local is_septuplet = 4 * grid_div % (4 / 7) == 0
        if is_septuplet then return grid_div * (7 / 4) end
        local is_dotted = 2 * grid_div % 3 == 0
        if is_dotted then return grid_div * (2 / 3) end
    else
        local is_triplet = 2 / grid_div % 3 == 0
        if is_triplet then return grid_div * (3 / 2) end
        local is_quintuplet = 4 / grid_div % 5 == 0
        if is_quintuplet then return grid_div * (5 / 4) end
        local is_septuplet = 4 / grid_div % 7 == 0
        if is_septuplet then return grid_div * (7 / 4) end
        local is_dotted = 2 / grid_div % (2 / 3) == 0
        if is_dotted then return grid_div * (2 / 3) end
    end
end

function LoadProjectGrid(grid_div)
    if reaper.GetExtState(extname, 'preserve_grid_type') ~= '1' then
        return false
    end
    local str_grid_div = GetStraightGrid(grid_div)
    if not str_grid_div then return false end

    local _, state = reaper.GetProjExtState(0, extname, str_grid_div)
    local swing = 0
    local swing_amt
    grid_div = str_grid_div
    if state ~= '' then
        if state:sub(1, 1) == 's' then
            swing, swing_amt = 1, tonumber(state:sub(2))
        else
            grid_div = tonumber(state)
        end
    end
    reaper.GetSetProjectGrid(0, 1, grid_div, swing, swing_amt)
    return true
end

function SaveProjectGrid(grid_div, swing, swing_amt)
    if reaper.GetExtState(extname, 'preserve_grid_type') ~= '1' then
        return
    end
    local str_grid_div = GetStraightGrid(grid_div)
    if not str_grid_div then return end
    local state = ''
    if swing == 1 and swing_amt then
        state = 's' .. swing_amt
    elseif str_grid_div ~= grid_div then
        state = ('%.32f'):format(grid_div)
    end
    reaper.SetProjExtState(0, extname, str_grid_div, state)
end

function GetClosestStraightGrid(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, 0))
    return 2 ^ math.floor(math.log(grid_div, 2) + 0.5)
end

function IsStraightGrid(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, 0))
    return math.log(grid_div, 2) % 1 == 0
end

function SetStraightGrid()
    local _, grid_div, _, swing_amt = reaper.GetSetProjectGrid(0, 0)
    if not IsStraightGrid(grid_div) then
        if IsTripletGrid(grid_div) then
            grid_div = grid_div * (3 / 2)
        elseif IsQuintupletGrid(grid_div) then
            grid_div = grid_div * (5 / 4)
        elseif IsSeptupletGrid(grid_div) then
            grid_div = grid_div * (7 / 4)
        elseif IsDottedGrid(grid_div) then
            grid_div = grid_div * (2 / 3)
        else
            grid_div = GetClosestStraightGrid(grid_div)
        end
        reaper.GetSetProjectGrid(0, 1, grid_div, 0, swing_amt)
        SaveProjectGrid(grid_div, 0, swing_amt)
    end
    return grid_div
end

function IsTripletGrid(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, 0))
    if grid_div > 1 then
        return 2 * grid_div % (2 / 3) == 0
    else
        return 2 / grid_div % 3 == 0
    end
end

function SetTripletGrid()
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
    if not IsTripletGrid(grid_div) then
        if IsStraightGrid(grid_div) then
            grid_div = grid_div * (2 / 3)
        elseif IsQuintupletGrid(grid_div) then
            grid_div = grid_div * (5 / 4) * (2 / 3)
        elseif IsSeptupletGrid(grid_div) then
            grid_div = grid_div * (7 / 4) * (2 / 3)
        elseif IsDottedGrid(grid_div) then
            grid_div = grid_div * (2 / 3) ^ 2
        else
            grid_div = GetClosestStraightGrid(grid_div) * (2 / 3)
        end
        reaper.GetSetProjectGrid(0, 1, grid_div, 0, swing_amt)
        SaveProjectGrid(grid_div, 0, swing_amt)
    end
    return grid_div
end

function IsQuintupletGrid(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, 0))
    if grid_div > 1 then
        return 4 * grid_div % (4 / 5) == 0
    else
        return 4 / grid_div % 5 == 0
    end
end

function SetQuintupletGrid()
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
    if not IsQuintupletGrid(grid_div) then
        if IsStraightGrid(grid_div) then
            grid_div = grid_div * (4 / 5)
        elseif IsTripletGrid(grid_div) then
            grid_div = grid_div * (3 / 2) * (4 / 5)
        elseif IsSeptupletGrid(grid_div) then
            grid_div = grid_div * (7 / 4) * (4 / 5)
        elseif IsDottedGrid(grid_div) then
            grid_div = grid_div * (2 / 3) * (4 / 5)
        else
            grid_div = GetClosestStraightGrid(grid_div) * (4 / 5)
        end
        reaper.GetSetProjectGrid(0, 1, grid_div, 0, swing_amt)
        SaveProjectGrid(grid_div, 0, swing_amt)
    end
    return grid_div
end

function IsSeptupletGrid(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, 0))
    if grid_div > 1 then
        return 4 * grid_div % (4 / 7) == 0
    else
        return 4 / grid_div % 7 == 0
    end
end

function SetSeptupletGrid()
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
    if not IsSeptupletGrid(grid_div) then
        if IsStraightGrid(grid_div) then
            grid_div = grid_div * (4 / 7)
        elseif IsTripletGrid(grid_div) then
            grid_div = grid_div * (3 / 2) * (4 / 7)
        elseif IsQuintupletGrid(grid_div) then
            grid_div = grid_div * (5 / 4) * (4 / 7)
        elseif IsDottedGrid(grid_div) then
            grid_div = grid_div * (2 / 3) * (4 / 7)
        else
            grid_div = GetClosestStraightGrid(grid_div) * (4 / 7)
        end
        reaper.GetSetProjectGrid(0, 1, grid_div, 0, swing_amt)
        SaveProjectGrid(grid_div, 0, swing_amt)
    end
    return grid_div
end

function IsDottedGrid(grid_div)
    grid_div = grid_div or select(2, reaper.GetSetProjectGrid(0, 0))
    if grid_div > 1 then
        return 2 * grid_div % 3 == 0
    else
        return 2 / grid_div % (2 / 3) == 0
    end
end

function SetDottedGrid()
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
    if not IsDottedGrid(grid_div) then
        if IsStraightGrid(grid_div) then
            grid_div = grid_div * (3 / 2)
        elseif IsTripletGrid(grid_div) then
            grid_div = grid_div * (3 / 2) ^ 2
        elseif IsQuintupletGrid(grid_div) then
            grid_div = grid_div * (5 / 4) * (3 / 2)
        elseif IsSeptupletGrid(grid_div) then
            grid_div = grid_div * (7 / 4) * (3 / 2)
        else
            grid_div = GetClosestStraightGrid(grid_div) * (3 / 2)
        end
        reaper.GetSetProjectGrid(0, 1, grid_div, 0, swing_amt)
        SaveProjectGrid(grid_div, 0, swing_amt)
    end
    return grid_div
end

function IsSwingEnabled()
    local _, _, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
    return swing == 1 and swing_amt ~= 0
end

function SetSwingEnabled(is_enabled)
    local swing = is_enabled and 1 or 0
    local _, grid_div, _, swing_amt = reaper.GetSetProjectGrid(0, 0)
    reaper.GetSetProjectGrid(0, 1, grid_div, swing, swing_amt)
    SaveProjectGrid(grid_div, swing, swing_amt)
    return grid_div, swing, swing_amt
end

function HasUserGridDivisor(is_midi)
    local key = is_midi and 'midi_zoom_div' or 'zoom_div'
    return tonumber(reaper.GetExtState(extname, key)) ~= 2
end

function SetUserGridDivisor(is_midi)
    local key = is_midi and 'midi_zoom_div' or 'zoom_div'
    local val = tonumber(reaper.GetExtState(extname, key)) or 2
    local captions = 'Zooming divides grid by X (def: 2):'
    local title = is_midi and 'MIDI grid divisor' or 'Arrange grid divisor'
    local ret, divisor_str = reaper.GetUserInputs(title, 1, captions, val)
    if not ret then return end

    if divisor_str == '' then divisor_str = '2' end
    local divisor = tonumber(divisor_str)
    if not divisor or divisor <= 1 then
        local msg = 'Value \'%s\' not permitted!'
        reaper.MB(msg:format(divisor_str), 'Error', 0)
        return false
    end
    reaper.SetExtState(extname, key, ('%.32f'):format(divisor), true)
    return true
end

function HasUserGridLimits(is_midi)
    local min_key = is_midi and 'midi_min_limit' or 'min_limit'
    local max_key = is_midi and 'midi_max_limit' or 'max_limit'
    local min_val = reaper.GetExtState(extname, min_key .. '_str')
    local max_val = reaper.GetExtState(extname, max_key .. '_str')
    return min_val ~= '' or max_val ~= ''
end

function SetUserGridLimits(is_midi)
    local min_key = is_midi and 'midi_min_limit' or 'min_limit'
    local max_key = is_midi and 'midi_max_limit' or 'max_limit'
    local min_val = reaper.GetExtState(extname, min_key .. '_str')
    local max_val = reaper.GetExtState(extname, max_key .. '_str')
    local ret_vals = min_val .. ',' .. max_val
    local captions = 'Min grid size: (e.g. 1/128),Max grid size: (e.g. 1)'
    local title = is_midi and 'MIDI editor limits' or 'Arrange view limits'
    local ret, limits = reaper.GetUserInputs(title, 2, captions, ret_vals)
    if not ret then return end

    local str_vals = {}
    local vals = {}
    for limit in (limits .. ','):gmatch('(.-),') do
        local fraction
        local nom, denom, suffix = limit:match('(%d+)/(%d+)([TtDd]?)')
        if not nom then
            nom, suffix = limit:match('(%d+)([TtDd]?)')
            denom = 1
        end
        if nom then
            local factor = 1
            if suffix == 'T' or suffix == 't' then factor = 2 / 3 end
            if suffix == 'D' or suffix == 'd' then factor = 3 / 2 end
            fraction = nom / denom * factor
        else
            fraction = tonumber(limit) or 0
        end
        if (not fraction or fraction < 0) and limit ~= '' then
            local msg = 'Value \'%s\' not permitted!'
            reaper.MB(msg:format(limit), 'Error', 0)
            return false
        end
        str_vals[#str_vals + 1] = limit
        vals[#vals + 1] = fraction
    end

    if #vals ~= 2 then
        reaper.MB('Invalid input', 'Error', 0)
        return false
    end

    if vals[1] > vals[2] and vals[2] ~= 0 then
        reaper.MB('Max can\'t be smaller than min!', 'Error', 0)
        return false
    end

    reaper.SetExtState(extname, min_key .. '_str', str_vals[1], true)
    reaper.SetExtState(extname, max_key .. '_str', str_vals[2], true)
    reaper.SetExtState(extname, min_key, ('%.32f'):format(vals[1]), true)
    reaper.SetExtState(extname, max_key, ('%.32f'):format(vals[2]), true)

    return true
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
        if spacing < (is_midi and 15 or min_spacing) then
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

function CheckAdaptiveGrid(multiplier)
    if is_frame_grid or is_measure_grid then return false end
    return IsGridVisible() and GetGridMultiplier() == multiplier
end

function CheckMIDIAdaptiveGrid(multiplier)
    return GetMIDIGridMultiplier() == multiplier
end

function SetAdaptiveGrid(multiplier)
    if is_frame_grid then reaper.Main_OnCommand(41885, 0) end
    if is_measure_grid then reaper.Main_OnCommand(40725, 0) end
    -- Ask user for custom grid spacing if not available
    if multiplier == -1 and not CheckUserCustomGridSpacing(false) then return end
    -- Toggle adaptive mode when selecting an entry that's already active
    if CheckAdaptiveGrid(multiplier) then multiplier = 0 end

    ShowGrid(true)
    SetGridMultiplier(multiplier)

    if multiplier ~= 0 then
        RunAdaptScript(false)
        if not IsServiceRunning() then StartService() end
    end
end

function SetMIDIAdaptiveGrid(multiplier)
    -- Ask user for custom grid spacing if not available
    if multiplier == -1 and not CheckUserCustomGridSpacing(true) then return end
    -- Toggle adaptive mode when selecting an entry that's already active
    if CheckMIDIAdaptiveGrid(multiplier) then multiplier = 0 end

    ShowMIDIGrid(true)
    SetMIDIGridMultiplier(multiplier)

    if multiplier ~= 0 then
        RunAdaptScript(true)
        if not IsServiceRunning() then StartService() end
    end
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
    if is_frame_grid then reaper.Main_OnCommand(41885, 0) end
    if is_measure_grid then reaper.Main_OnCommand(40725, 0) end
    ShowGrid(true)
    SetGridMultiplier(0)
    if LoadProjectGrid(new_grid_div) then return end
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
    if IsTripletGrid(grid_div) then new_grid_div = new_grid_div * 2 / 3 end
    if IsQuintupletGrid(grid_div) then new_grid_div = new_grid_div * 4 / 5 end
    if IsSeptupletGrid(grid_div) then new_grid_div = new_grid_div * 4 / 7 end
    if IsDottedGrid(grid_div) then new_grid_div = new_grid_div * 3 / 2 end
    reaper.GetSetProjectGrid(0, 1, new_grid_div, swing, swing_amt)
end

function CheckFixedGrid(grid_div)
    if is_frame_grid or is_measure_grid then return false end
    if not IsGridVisible() or GetGridMultiplier() ~= 0 then return false end
    local _, curr_grid_div = reaper.GetSetProjectGrid(0, 0)
    if IsTripletGrid(curr_grid_div) then grid_div = grid_div * 2 / 3 end
    if IsQuintupletGrid(curr_grid_div) then grid_div = grid_div * 4 / 5 end
    if IsSeptupletGrid(curr_grid_div) then grid_div = grid_div * 4 / 7 end
    if IsDottedGrid(curr_grid_div) then grid_div = grid_div * 3 / 2 end
    return grid_div == curr_grid_div
end

function IsFrameVisibleInMenu()
    return reaper.GetExtState(extname, 'show_frame') == '1'
end

function SetFrameVisibleInMenu(is_show)
    reaper.SetExtState(extname, 'show_frame', is_show and 1 or 0, true)
end

function IsMeasureVisibleInMenu()
    return reaper.GetExtState(extname, 'show_measure') == '1'
end

function SetMeasureVisibleInMenu(is_show)
    reaper.SetExtState(extname, 'show_measure', is_show and 1 or 0, true)
end

local frame_entry = {}
local measure_entry = {}

local is_frame_option_visible = is_frame_grid or IsFrameVisibleInMenu()
local is_measure_option_visible = is_measure_grid or IsMeasureVisibleInMenu()

if is_frame_option_visible then
    frame_entry = {
        title = 'Frame',
        is_checked = is_frame_grid,
        OnReturn = function()
            SetGridMultiplier(0)
            reaper.Main_OnCommand(41885, 0)
        end,
    }
end

if is_measure_option_visible then
    measure_entry = {
        title = 'Measure',
        is_checked = is_measure_grid,
        OnReturn = function()
            SetGridMultiplier(0)
            reaper.Main_OnCommand(40725, 0)
        end,
    }
end

function IsQuintupletVisibleInMenu()
    return reaper.GetExtState(extname, 'show_quintuplets') == '1'
end

function SetQuintupletVisibleInMenu(is_show)
    reaper.SetExtState(extname, 'show_quintuplets', is_show and 1 or 0, true)
end

function IsSeptupletVisibleInMenu()
    return reaper.GetExtState(extname, 'show_septuplets') == '1'
end

function SetSeptupletVisibleInMenu(is_show)
    reaper.SetExtState(extname, 'show_septuplets', is_show and 1 or 0, true)
end

local is_quintuplet_option_visible = IsQuintupletVisibleInMenu()
local is_septuplet_option_visible = IsSeptupletVisibleInMenu()

local quintuplet_entry = {}
if is_quintuplet_option_visible then
    quintuplet_entry = {
        title = 'Quintuplet',
        IsChecked = IsQuintupletGrid,
        OnReturn = function()
            SetSwingEnabled(false)
            SetQuintupletGrid()
        end,
    }
end

local septuplet_entry = {}
if is_septuplet_option_visible then
    septuplet_entry = {
        title = 'Septuplet',
        IsChecked = IsSeptupletGrid,
        OnReturn = function()
            SetSwingEnabled(false)
            SetSeptupletGrid()
        end,
    }
end

local options_menu = {
    title = 'Options',
    {title = 'Arrange view', is_grayed = true},
    {separator = true},
    {title = 'Set custom size', OnReturn = SetUserCustomGridSpacing, arg = false},
    {
        title = 'Set grid divisor',
        IsChecked = HasUserGridDivisor,
        OnReturn = SetUserGridDivisor,
        arg = false,
    },
    {
        title = 'Set limits',
        IsChecked = HasUserGridLimits,
        OnReturn = SetUserGridLimits,
        arg = false,
    },
    {separator = true},
    {
        title = 'Show in menu',
        {
            title = 'Quintuplet',
            is_checked = is_quintuplet_option_visible,
            OnReturn = SetQuintupletVisibleInMenu,
            arg = not is_quintuplet_option_visible,
        },
        {
            title = 'Septuplet',
            is_checked = is_septuplet_option_visible,
            OnReturn = SetSeptupletVisibleInMenu,
            arg = not is_septuplet_option_visible,
        },
        {
            title = 'Frame',
            is_checked = is_frame_option_visible,
            OnReturn = SetFrameVisibleInMenu,
            arg = not is_frame_option_visible,
        },
        {
            title = 'Measure',
            is_checked = is_measure_option_visible,
            OnReturn = SetMeasureVisibleInMenu,
            arg = not is_measure_option_visible,
        },
    },
    {
        title = 'Preserve grid type per size',
        is_checked = reaper.GetExtState(extname, 'preserve_grid_type') == '1',
        OnReturn = function()
            local key = 'preserve_grid_type'
            local state = reaper.GetExtState(extname, key) == '1'
            local toggle_state = state and 0 or 1
            reaper.SetExtState(extname, key, toggle_state, 1)
        end,
    },
    {separator = true},
    {title = 'MIDI editor', is_grayed = true},
    {separator = true},
    {title = 'Set custom size', OnReturn = SetUserCustomGridSpacing, arg = true},
    {
        title = 'Set grid divisor',
        IsChecked = HasUserGridDivisor,
        OnReturn = SetUserGridDivisor,
        arg = true,
    },
    {
        title = 'Set limits',
        IsChecked = HasUserGridLimits,
        OnReturn = SetUserGridLimits,
        arg = true,
    },
    {separator = true},
    {
        title = 'Run service on startup',
        IsChecked = IsStartupHookEnabled,
        OnReturn = function()
            local is_enabled = not IsStartupHookEnabled()
            local comment = 'Start script: Adaptive grid (background process)'
            local var_name = 'adaptive_grid_cmd'
            SetStartupHookEnabled(is_enabled, comment, var_name)
        end,
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
            title = 'Set custom size',
            OnReturn = SetUserCustomGridSpacing,
            arg = true,
        },
        {
            title = 'Set grid divisor',
            IsChecked = HasUserGridDivisor,
            OnReturn = SetUserGridDivisor,
            arg = true,
        },
        {
            title = 'Set limits',
            IsChecked = HasUserGridLimits,
            OnReturn = SetUserGridLimits,
            arg = true,
        },
        {separator = true},
        {
            title = 'Run service on startup',
            IsChecked = IsStartupHookEnabled,
            OnReturn = function()
                local is_enabled = not IsStartupHookEnabled()
                local text = 'Start script: Adaptive grid (background process)'
                local var_name = 'adaptive_grid_cmd'
                SetStartupHookEnabled(is_enabled, text, var_name)
            end,
        },
    },
}

local _, _, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
swing_amt = math.floor(swing_amt * 100)

function SetSwingAmount(amount)
    local grid_div = SetStraightGrid()
    reaper.GetSetProjectGrid(0, 1, nil, 1, amount / 100)
    SaveProjectGrid(grid_div, 1, amount / 100)
end

function PromptSetSwingAmount()
    local title = 'Set swing'
    local caption = 'Amount: (-100% to 100%)'
    local input_text = ''

    local ret, user_text = reaper.GetUserInputs(title, 1, caption, input_text)
    if not ret or user_text == input_text then return end

    local amount = tonumber(user_text)
    if amount and amount >= -100 and amount <= 100 then
        SetSwingAmount(amount)
    else
        reaper.MB('Input must be a number between -100 and 100', 'Error', 0)
    end
end

function CheckSwingAmount(amount) return swing == 1 and swing_amt == amount end

local swing_menu = {
    {title = '53%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 53},
    {title = '55%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 55},
    {title = '57%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 57},
    {title = '59%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 59},
    {title = '61%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 61},
    {title = '64%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 64},
    {title = '67%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 67},
    {title = '70%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 70},
    {title = '73%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 73},
    {title = '75%', IsChecked = CheckSwingAmount, OnReturn = SetSwingAmount, arg = 75},
    {separator = true},
    {title = 'Other', OnReturn = PromptSetSwingAmount},
}

-- Check if there's an entry for the current swing amplitude
local has_swing_amt_entry = false
if swing_amt == 0 then
    has_swing_amt_entry = true
else
    for _, entry in ipairs(swing_menu) do
        if entry.arg == swing_amt then
            -- Mark entry with current swing amplitdue
            if swing ~= 1 then entry.title = entry.title .. '  •' end
            has_swing_amt_entry = true
            break
        end
    end
end

if not has_swing_amt_entry then
    -- Add entry with current swing ampitude
    local title = ('%s%%'):format(swing_amt)
    if swing ~= 1 then title = title .. '  •' end
    local new_entry =
    {
        title = title,
        IsChecked = CheckSwingAmount,
        OnReturn = SetSwingAmount,
        arg = swing_amt,
    }
    if swing_amt > 75 then
        table.insert(swing_menu, #swing_menu - 1, new_entry)
    else
        for e, entry in ipairs(swing_menu) do
            if entry.arg and entry.arg > swing_amt then
                table.insert(swing_menu, e, new_entry)
                break
            end
        end
    end
end

local main_menu = {
    {
        title = 'Straight',
        IsChecked = function()
            return not IsSwingEnabled() and IsStraightGrid()
        end,
        OnReturn = function()
            SetSwingEnabled(false)
            SetStraightGrid()
        end,
    },
    {
        title = 'Triplet',
        IsChecked = IsTripletGrid,
        OnReturn = function()
            SetSwingEnabled(false)
            SetTripletGrid()
        end,
    },
    quintuplet_entry,
    septuplet_entry,
    {
        title = 'Dotted',
        IsChecked = IsDottedGrid,
        OnReturn = function()
            SetSwingEnabled(false)
            SetDottedGrid()
        end,
    },
    {title = 'Swing', IsChecked = IsSwingEnabled, table.unpack(swing_menu)},
    {separator = true},
    {title = 'Fixed', is_grayed = true},
    {separator = true},
    frame_entry,
    measure_entry,
    {
        title = '1/128',
        IsChecked = CheckFixedGrid,
        OnReturn = SetFixedGrid,
        arg = 0.0078125,
    },
    {
        title = '1/64',
        IsChecked = CheckFixedGrid,
        OnReturn = SetFixedGrid,
        arg = 0.015625,
    },
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
    {separator = true},
    {title = 'Adaptive', is_grayed = true},
    {separator = true},
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

local has_config, projgridmin = reaper.get_config_var_string('projgridmin')
if has_config then
    min_spacing = tonumber(projgridmin) or 8
elseif reaper.SNM_GetIntConfigVar then
    min_spacing = reaper.SNM_GetIntConfigVar('projgridmin', 8)
else
    min_spacing = GetIniConfigValue('projgridmin', 8)
    reaper.SetExtState(extname, 'projgridmin', min_spacing, true)
end

-- Return menu to external scripts
if _G.menu then
    _G.menu = main_menu
    return
end

local is_hook_enabled = IsStartupHookEnabled()

local has_run = reaper.GetExtState(extname, 'has_run') == 'yes'
reaper.SetExtState(extname, 'has_run', 'yes', false)

RegisterToolbarToggleState(sec, cmd, 1000)

if not IsServiceRunning() then
    -- Exit immediately when running on startup but adaptive grid is deactivated
    if not has_run and is_hook_enabled then
        UpdateToolbarToggleStates(0, GetGridMultiplier())
        UpdateToolbarToggleStates(32060, GetMIDIGridMultiplier())
        reaper.defer(StartService)
        return
    else
        -- Deactivate adaptive grid
        SetGridMultiplier(0)
        SetMIDIGridMultiplier(0)
        UpdateToolbarToggleStates(0, 0)
        UpdateToolbarToggleStates(32060, 0)
    end
end

function StartDeferred()
    local menu = sec == 32060 and midi_menu or main_menu
    local menu_str = MenuCreateRecursive(menu)
    local ret = ShowMenu(menu_str)
    MenuReturnRecursive(menu, ret)
    UpdateToolbarToggleStates(0, GetGridMultiplier())
    UpdateToolbarToggleStates(32060, GetMIDIGridMultiplier())
end

reaper.defer(StartDeferred)
