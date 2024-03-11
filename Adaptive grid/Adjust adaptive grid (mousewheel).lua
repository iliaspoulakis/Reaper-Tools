--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about Use the mousewheel to go through adaptive grid sizes
]]
local extname = 'FTC.AdaptiveGrid'
local _, file, sec, _, _, _, val = reaper.get_action_context()
local path = file:match('^(.+)[\\/]')

-- Check REAPER version
local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(3) end

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

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

-- Avoid undo point
reaper.defer(function() end)

local GetMultiplier = GetGridMultiplier
local SetMultiplier = SetGridMultiplier

if sec == 32060 then
    GetMultiplier = GetMIDIGridMultiplier
    SetMultiplier = SetMIDIGridMultiplier
end

local mult = GetMultiplier()

-- Treat custom adaptive grid size like medium size
if mult == -1 then mult = 3 end

if mult > 0 then
    -- Change adaptive grid size
    if mult == 6 then mult = 5 end
    mult = mult + (val < 0 and 1 or -1)
    mult = math.min(5, math.max(1, mult))
    if mult == 5 then mult = 6 end
    SetMultiplier(mult)
    RunAdaptScript(sec == 32060)
    UpdateToolbarToggleStates(sec, mult)
else
    -- Change fixed grid size
    if sec == 32060 then
        local hwnd = reaper.MIDIEditor_GetActive()
        local take = reaper.MIDIEditor_GetTake(hwnd)
        if reaper.ValidatePtr(take, 'MediaItem_Take*') then
            -- Calculate new grid division
            local grid_div = reaper.MIDI_GetGrid(take) / 4
            local factor = reaper.GetExtState(extname, 'midi_zoom_div')
            factor = tonumber(factor) or 2
            grid_div = val < 0 and grid_div * factor or grid_div / factor
            -- Respect user limits
            local min_grid_div = reaper.GetExtState(extname, 'midi_min_limit')
            min_grid_div = tonumber(min_grid_div) or 0
            if min_grid_div == 0 then min_grid_div = 1 / 4096 * 2 / 3 end
            if grid_div < min_grid_div then
                if val > 0 then return end
            end
            local max_grid_div = reaper.GetExtState(extname, 'midi_max_limit')
            max_grid_div = tonumber(max_grid_div) or 0
            if max_grid_div == 0 then max_grid_div = 4096 * 3 / 2 end
            if grid_div > max_grid_div then
                if val < 0 then return end
            end
            reaper.SetMIDIEditorGrid(0, grid_div)
        end
    else
        -- Calculate new grid division
        local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
        local factor = reaper.GetExtState(extname, 'zoom_div')
        factor = tonumber(factor) or 2
        grid_div = val < 0 and grid_div * factor or grid_div / factor
        -- Respect user limits
        local min_grid_div = reaper.GetExtState(extname, 'min_limit')
        min_grid_div = tonumber(min_grid_div) or 0
        if min_grid_div == 0 then min_grid_div = 1 / 4096 * 2 / 3 end
        if grid_div < min_grid_div then
            if val > 0 then return end
        end
        local max_grid_div = reaper.GetExtState(extname, 'max_limit')
        max_grid_div = tonumber(max_grid_div) or 0
        if max_grid_div == 0 then max_grid_div = 4096 * 3 / 2 end
        if grid_div > max_grid_div then
            if val < 0 then return end
        end
        if not LoadProjectGrid(grid_div) then
            reaper.GetSetProjectGrid(0, 1, grid_div, swing, swing_amt)
        end
    end
end
