--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about Changes grid spacing to match current zoom level
]]
local extname = 'FTC.AdaptiveGrid'
local _, _, sec = reaper.get_action_context()
local is_midi = sec == 32060 or _G.mode == 2

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

function AdaptGrid(spacing)
    local zoom_lvl = reaper.GetHZoomLevel()

    local start_time, end_time = reaper.GetSet_ArrangeView2(0, false, 0, 0)
    local _, _, _, start_beat = reaper.TimeMap2_timeToBeats(0, start_time)
    local _, _, _, end_beat = reaper.TimeMap2_timeToBeats(0, end_time)

    -- Current view width in pixels
    local arrange_pixels = (end_time - start_time) * zoom_lvl
    -- Number of measures that fit into current view
    local arrange_measures = (end_beat - start_beat) / 4

    local measure_length_in_pixels = arrange_pixels / arrange_measures

    -- The maximum grid (divisions) that would be allowed with spacing
    local max_grid = measure_length_in_pixels / spacing

    -- Get current grid
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, 0)

    local grid = 1 / grid_div

    local factor = reaper.GetExtState(extname, 'zoom_div')
    factor = tonumber(factor) or 2

    -- How often can current grid fit into max_grid?
    local exp = math.log(max_grid / grid, factor)
    local new_grid = grid * factor ^ math.floor(exp)

    local new_grid_div = 1 / new_grid

    -- Check if new grid division exceeds user limits
    local min_grid_div = reaper.GetExtState(extname, 'min_limit')
    min_grid_div = tonumber(min_grid_div) or 0
    if min_grid_div == 0 then min_grid_div = 1 / 4096 * 2 / 3 end
    if new_grid_div < min_grid_div then
        if new_grid_div < grid_div then return end
    end
    local max_grid_div = reaper.GetExtState(extname, 'max_limit')
    max_grid_div = tonumber(max_grid_div) or 0
    if max_grid_div == 0 then max_grid_div = 4096 * 3 / 2 end
    if new_grid_div > max_grid_div then
        if new_grid_div > grid_div then return end
    end

    if not LoadProjectGrid(new_grid_div) then
        reaper.GetSetProjectGrid(0, 1, new_grid_div, swing, swing_amt)
    end
end

function GetTakeChunk(take)
    local item = reaper.GetMediaItemTake_Item(take)
    local _, item_chunk = reaper.GetItemStateChunk(item, '', false)
    local tk = reaper.GetMediaItemTakeInfo_Value(take, 'IP_TAKENUMBER')

    local take_start_ptr = 0
    local take_end_ptr = 0

    for _ = 0, tk do
        take_start_ptr = take_end_ptr
        take_end_ptr = item_chunk:find('\nTAKE[%s\n]', take_start_ptr + 1)
    end
    return item_chunk:sub(take_start_ptr, take_end_ptr)
end

function GetTakeChunkHZoom(chunk)
    local pattern = 'CFGEDITVIEW (.-) (.-) '
    return chunk:match(pattern)
end

function GetTakeChunkTimeBase(take_chunk)
    local pattern = 'CFGEDIT ' .. ('.- '):rep(18) .. '(.-) '
    return tonumber(take_chunk:match(pattern))
end

function GetMIDIEditorView(hwnd)
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    local GetProjTimeFromPPQ = reaper.MIDI_GetProjTimeFromPPQPos

    local take_chunk = GetTakeChunk(take)
    local start_ppq, hzoom_lvl = GetTakeChunkHZoom(take_chunk)
    start_ppq = tonumber(start_ppq)
    if not start_ppq then return end

    local timebase = GetTakeChunkTimeBase(take_chunk) or 0
    -- 0 = Beats (proj) 1 = Project synced 2 = Time (proj) 4 = Beats (source)

    local end_ppq
    local start_time, end_time

    if reaper.JS_Window_FindChildByID then
        local midiview = reaper.JS_Window_FindChildByID(hwnd, 1001)
        local _, width_in_pixels = reaper.JS_Window_GetClientSize(midiview)

        if timebase == 0 or timebase == 4 then
            -- For timebase 0 and 4, hzoom_lvl is in pixel/ppq
            end_ppq = start_ppq + width_in_pixels / hzoom_lvl
        else
            -- For timebase 1 and 2, hzoom_lvl is in pixel/time
            start_time = GetProjTimeFromPPQ(take, start_ppq)
            end_time = start_time + width_in_pixels / hzoom_lvl
        end
    else
        reaper.PreventUIRefresh(1)

        if timebase == 1 then
            -- Timebase: Toggle sync to arrange view
            reaper.MIDIEditor_OnCommand(hwnd, 40640)
        end

        -- Cmd: Scroll view right
        reaper.MIDIEditor_OnCommand(hwnd, 40141)

        -- After scrolling right, the new start_ppq is our end_ppq
        take_chunk = GetTakeChunk(take)
        end_ppq = GetTakeChunkHZoom(take_chunk)

        -- Note: Scrolling back to the left doesn't always work because
        -- it won't scroll back further than 0 ppq
        if start_ppq > 0 then
            -- Cmd: Scroll view left
            reaper.MIDIEditor_OnCommand(hwnd, 40140)
        else
            local editor_start_pos = GetProjTimeFromPPQ(take, start_ppq)
            local editor_end_pos = GetProjTimeFromPPQ(take, end_ppq)

            -- A factor is necessary to convert to the selection used for the
            -- action "Zoom to project loop selection" which is smaller than
            -- the actual visible area
            local factor = timebase == 2 and 0.97087377 or 0.943396226415
            local area = editor_end_pos - editor_start_pos
            local center = editor_start_pos + area / 2
            area = area * factor

            -- Save current time selection
            local GetSetTimeSel = reaper.GetSet_LoopTimeRange
            local sel_start_pos, sel_end_pos = GetSetTimeSel(0, 1, 0, 0, 0)

            -- Set selection to area for zoom
            GetSetTimeSel(1, 1, center - area / 2, center + area / 2, 0)

            -- View: Zoom to project loop selection
            reaper.MIDIEditor_OnCommand(hwnd, 40726)

            -- Restore initial time selection
            GetSetTimeSel(1, 1, sel_start_pos, sel_end_pos, 0)
        end

        if timebase == 1 then
            -- Timebase: Toggle sync to arrange view
            reaper.MIDIEditor_OnCommand(hwnd, 40640)
        end

        reaper.PreventUIRefresh(-1)
    end

    -- Convert ppq to time based units
    start_time = start_time or GetProjTimeFromPPQ(take, start_ppq)
    end_time = end_time or GetProjTimeFromPPQ(take, end_ppq)

    if timebase == 0 or timebase == 4 then
        -- Convert hzoom_lvl from pixel/ppq to pixel/time
        local width_in_pixels = (end_ppq - start_ppq) * hzoom_lvl
        hzoom_lvl = width_in_pixels / (end_time - start_time)
    end

    return start_time, end_time, hzoom_lvl
end

function AdaptMIDIGrid(spacing)
    local hwnd = reaper.MIDIEditor_GetActive()

    local start_pos, end_pos, hzoom_lvl = GetMIDIEditorView(hwnd)
    if not start_pos then return end

    local _, _, _, start_beat = reaper.TimeMap2_timeToBeats(0, start_pos)
    local _, _, _, end_beat = reaper.TimeMap2_timeToBeats(0, end_pos)

    -- Current view with in pixels
    local editor_pixels = (end_pos - start_pos) * hzoom_lvl
    -- Number of measures that fit into current view
    local editor_measures = (end_beat - start_beat) / 4

    local measure_length_in_pixels = editor_pixels / editor_measures

    -- The maximum grid (divisions) that would be allowed with grid spacing
    local max_grid = measure_length_in_pixels / spacing

    -- Get current grid
    local take = reaper.MIDIEditor_GetTake(hwnd)
    local grid_div, swing, note_len = reaper.MIDI_GetGrid(take)
    local grid = 1 / grid_div

    local factor = reaper.GetExtState(extname, 'midi_zoom_div')
    factor = tonumber(factor) or 2

    -- How often can current grid fit into max_grid?
    local exp = math.log(max_grid / grid, factor)
    local new_grid = grid * factor ^ math.floor(exp)

    local new_grid_div = 1 / new_grid

    -- Check if new grid division exceeds user limits
    local min_grid_div = reaper.GetExtState(extname, 'midi_min_limit')
    min_grid_div = tonumber(min_grid_div) or 0
    if min_grid_div == 0 then min_grid_div = 1 / 4096 * 2 / 3 end
    if new_grid_div < min_grid_div then
        if new_grid_div < grid_div / 4 then return end
    end
    local max_grid_div = reaper.GetExtState(extname, 'midi_max_limit')
    max_grid_div = tonumber(max_grid_div) or 0
    if max_grid_div == 0 then max_grid_div = 4096 * 3 / 2 end
    if new_grid_div > max_grid_div then
        if new_grid_div > grid_div / 4 then return end
    end

    reaper.SetMIDIEditorGrid(0, new_grid_div)
    if swing ~= 0 then
        -- Grid: Set grid type to swing
        reaper.MIDIEditor_OnCommand(hwnd, 41006)
    end

    -- Check if new note length is set to grid and if grid changed
    if note_len == 0 and new_grid_div ~= grid_div / 4 then
        -- Options: Drawing or selecting a note sets the new note length
        local is_draw_length = reaper.GetToggleCommandStateEx(32060, 40479) == 1

        -- Try to keep length of next inserted note (if set to grid)
        if is_draw_length then
            -- These are the command ids to set next inserted note to a division
            local cmds = {
                {id = 41081, div = 1},
                {id = 41079, div = 1 / 2},
                {id = 41076, div = 1 / 4},
                {id = 41073, div = 1 / 8},
                {id = 41070, div = 1 / 16},
                {id = 41068, div = 1 / 32},
                {id = 41064, div = 1 / 64},
                {id = 41062, div = 1 / 128},
            }

            local set_note_length_cmd

            local straight_div = grid_div / 4
            local triplet_div = straight_div * 3 / 2
            local dotted_div = straight_div * 2 / 3

            -- Go through all divisions and check if they match previous grid
            for _, cmd in ipairs(cmds) do
                local is_straight = cmd.div == straight_div
                local is_triplet = cmd.div == triplet_div
                local is_dotted = cmd.div == dotted_div
                if is_straight or is_triplet or is_dotted then
                    set_note_length_cmd = cmd
                end
            end

            if not set_note_length_cmd then return end

            -- Set note length
            reaper.MIDIEditor_OnCommand(hwnd, set_note_length_cmd.id)

            -- Set type of next inserted note to current grid type
            if reaper.GetToggleCommandStateEx(32060, 41004) == 1 then
                -- Set length for next inserted note: triplet...
                reaper.MIDIEditor_OnCommand(hwnd, 41713)
            elseif reaper.GetToggleCommandStateEx(32060, 41005) == 1 then
                -- Set length for next inserted note: dotted...
                reaper.MIDIEditor_OnCommand(hwnd, 41712)
            else
                -- Set length for next inserted note: straight...
                reaper.MIDIEditor_OnCommand(hwnd, 41711)
            end
        end
    end
end

-- Get adaptive mode multipliers
local main_mult = tonumber(reaper.GetExtState(extname, 'main_mult')) or 0
local midi_mult = tonumber(reaper.GetExtState(extname, 'midi_mult')) or 0
local mult = is_midi and midi_mult or main_mult

-- Multiplier 0: Grid is fixed
if mult == 0 then return end

-- Skip arrangeview when using same grid division option
if main_mult > 0 and midi_mult > 0 and not is_midi then
    -- Grid: Use the same grid division in arrange view and MIDI editor
    local is_grid_synced = reaper.GetToggleCommandState(42010) == 1
    if is_grid_synced and reaper.MIDIEditor_GetActive() then return end
end

-- Return when grid is not visible
if is_midi then
    -- View: Toggle grid
    if reaper.GetToggleCommandStateEx(32060, 1017) == 0 then return end
else
    -- Options: Toggle grid lines
    if reaper.GetToggleCommandState(40145) == 0 then return end
end

-- Load minimum grid spacing
local spacing
if is_midi then
    -- Note: The minimum grid spacing for the MIDI editor is fixed
    spacing = 15
else
    local ret, projgridmin = reaper.get_config_var_string('projgridmin')
    if ret then
        spacing = tonumber(projgridmin) or 8
    elseif reaper.SNM_GetIntConfigVar then
        spacing = reaper.SNM_GetIntConfigVar('projgridmin', 8)
    else
        spacing = tonumber(reaper.GetExtState(extname, 'projgridmin')) or 8
    end
end

-- Multiplier -1: Custom grid spacing
if mult == -1 then
    local key = is_midi and 'midi_custom_spacing' or 'custom_spacing'
    spacing = tonumber(reaper.GetExtState(extname, key)) or spacing
    -- Account for grid line of 1 px
    spacing = spacing + 1
else
    -- Use multiple of minimum grid spacing
    spacing = spacing * mult
    -- Account for grid lines
    spacing = spacing + mult
end

if not is_midi then
    AdaptGrid(spacing)
else
    AdaptMIDIGrid(spacing)
end
