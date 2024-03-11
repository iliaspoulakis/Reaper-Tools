--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about Multiply current grid by configured grid divisor
]]
local extname = 'FTC.AdaptiveGrid'
local _, _, sec = reaper.get_action_context()

-- Check REAPER version
local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(3) end

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

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

-- Change fixed grid size
if sec == 32060 then
    local hwnd = reaper.MIDIEditor_GetActive()
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if reaper.ValidatePtr(take, 'MediaItem_Take*') then
        -- Calculate new grid division
        local grid_div = reaper.MIDI_GetGrid(take) / 4
        local factor = reaper.GetExtState(extname, 'midi_zoom_div')
        factor = tonumber(factor) or 2
        grid_div = grid_div * factor
        -- Respect user limits
        local min_grid_div = reaper.GetExtState(extname, 'midi_min_limit')
        min_grid_div = tonumber(min_grid_div) or 0
        if min_grid_div == 0 then min_grid_div = 1 / 4096 * 2 / 3 end
        if grid_div < min_grid_div then return end
        local max_grid_div = reaper.GetExtState(extname, 'midi_max_limit')
        max_grid_div = tonumber(max_grid_div) or 0
        if max_grid_div == 0 then max_grid_div = 4096 * 3 / 2 end
        if grid_div > max_grid_div then return end
        reaper.SetMIDIEditorGrid(0, grid_div)
    end
else
    -- Calculate new grid division
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)
    local factor = reaper.GetExtState(extname, 'zoom_div')
    factor = tonumber(factor) or 2
    grid_div = grid_div * factor
    -- Respect user limits
    local min_grid_div = reaper.GetExtState(extname, 'min_limit')
    min_grid_div = tonumber(min_grid_div) or 0
    if min_grid_div == 0 then min_grid_div = 1 / 4096 * 2 / 3 end
    if grid_div < min_grid_div then return end
    local max_grid_div = reaper.GetExtState(extname, 'max_limit')
    max_grid_div = tonumber(max_grid_div) or 0
    if max_grid_div == 0 then max_grid_div = 4096 * 3 / 2 end
    if grid_div > max_grid_div then return end
    if not LoadProjectGrid(grid_div) then
        reaper.GetSetProjectGrid(0, 1, grid_div, swing, swing_amt)
    end
end
