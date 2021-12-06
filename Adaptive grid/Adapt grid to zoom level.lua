--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @noindex
  @about Changes grid spacing to match current zoom level
]]

local extname = 'FTC.AdaptiveGrid'
local _, _, sec = reaper.get_action_context()
local is_midi = sec == 32060 or _G.mode == 2

function AdaptGrid(spacing)
    local zoom_lvl = reaper.GetHZoomLevel()

    local start_time, end_time = reaper.GetSet_ArrangeView2(0, false, 0, 0)
    local _, _, _, start_beat = reaper.TimeMap2_timeToBeats(0, start_time)
    local _, _, _, end_beat = reaper.TimeMap2_timeToBeats(0, end_time)

    -- Current view with in pixels
    local arrange_pixels = (end_time - start_time) * zoom_lvl
    -- Number of measures that fit into current view
    local arrange_measures = (end_beat - start_beat) / 4

    local measure_length_in_pixels = arrange_pixels / arrange_measures

    -- The maximum grid (divisions) that would be allowed with spacing
    local max_grid = measure_length_in_pixels / spacing

    -- Get current grid
    local _, grid_div, swing, swing_amt = reaper.GetSetProjectGrid(0, false)

    local grid = 1 / grid_div

    -- How often can current grid fit into max_grid?
    local exp = math.log(max_grid / grid, 2)
    grid = grid * 2 ^ math.floor(exp)

    reaper.GetSetProjectGrid(0, true, 1 / grid, swing, swing_amt)
end

function GetTakeChunk(take)
    local item = reaper.GetMediaItemTake_Item(take)
    local _, chunk = reaper.GetItemStateChunk(item, '', false)
    local tk = reaper.GetMediaItemTakeInfo_Value(take, 'IP_TAKENUMBER')

    local take_start_ptr = 0
    local take_end_ptr = 0

    for _ = 0, tk do
        take_start_ptr = take_end_ptr
        take_end_ptr = chunk:find('\nTAKE[%s\n]', take_start_ptr + 1)
    end
    return chunk:sub(take_start_ptr, take_end_ptr)
end

function GetTakeChunkHZoom(chunk)
    local pattern = 'CFGEDITVIEW (.-) (.-) '
    return chunk:match(pattern)
end

function GetTakeChunkTimeBase(chunk)
    local pattern = 'CFGEDIT ' .. ('.- '):rep(18) .. '(.-) '
    return tonumber(chunk:match(pattern))
end

function GetMIDIEditorView(hwnd)
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    local GetProjTimeFromPPQ = reaper.MIDI_GetProjTimeFromPPQPos

    local chunk = GetTakeChunk(take)
    local start_ppq, hzoom_lvl = GetTakeChunkHZoom(chunk)
    if not start_ppq then return end

    local timebase = GetTakeChunkTimeBase(chunk) or 0
    -- 0 = Beats (proj) 1 = Project synced 2 = Time (proj) 4 = Beats (source)

    local end_ppq
    local start_time, end_time

    if reaper.JS_Window_FindChildByID then
        local midiview = reaper.JS_Window_FindChildByID(hwnd, 0x3E9)
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
        if timebase == 1 then
            -- Timebase: Toggle sync to arrange view
            reaper.MIDIEditor_OnCommand(hwnd, 40640)
        end

        -- Cmd: Scroll view right
        reaper.MIDIEditor_OnCommand(hwnd, 40141)

        -- After scrolling right, the new start_ppq is our end_ppq
        chunk = GetTakeChunk(take)
        end_ppq = GetTakeChunkHZoom(chunk)

        -- Cmd: Scroll view left
        reaper.MIDIEditor_OnCommand(hwnd, 40140)

        if timebase == 1 then
            -- Timebase: Toggle sync to arrange view
            reaper.MIDIEditor_OnCommand(hwnd, 40640)
        end
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
    local grid_div, swing = reaper.MIDI_GetGrid(take)
    local grid = 1 / grid_div

    -- How often can current grid fit into max_grid?
    local exp = math.log(max_grid / grid, 2)
    grid = grid * 2 ^ math.floor(exp)

    reaper.SetMIDIEditorGrid(0, 1 / grid)
    if swing ~= 0 then
        -- Grid: Set grid type to swing
        reaper.MIDIEditor_OnCommand(hwnd, 41006)
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

-- Get adaptive mode multipliers
local main_mult = tonumber(reaper.GetExtState(extname, 'main_mult')) or 0
local midi_mult = tonumber(reaper.GetExtState(extname, 'midi_mult')) or 0
local mult = is_midi and midi_mult or main_mult

if not _G.mode then
    -- Create undo point when script is run by custom action
    if not _G.mode then reaper.Undo_OnStateChange('Adapt grid to zoom level') end

    -- Update toolbars when using first custom action after reaper restart
    local has_run = reaper.GetExtState(extname, 'has_run') == 'yes'
    if not has_run then
        reaper.SetExtState(extname, 'has_run', 'yes', false)
        UpdateToolbarToggleStates(0, main_mult)
        UpdateToolbarToggleStates(32060, midi_mult)
    end
end

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
    if reaper.SNM_GetIntConfigVar then
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
