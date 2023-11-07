--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.3.0
  @about Contextual zooming & scrolling for the MIDI editor in reaper
  @changelog
    - Support using selected notes for vertical zoom/scroll functions
]]
------------------------------ ZOOM MODES -----------------------------

-- HORIZONTAL MODES
-- 1: No change
-- 2: Zoom to item
-- 3: Zoom to number of measures at mouse or edit cursor
-- 4: Zoom to number of measures at mouse or edit cursor, restrict to item
-- 5: Smart zoom to number of notes at mouse or edit cursor
-- 6: Smart zoom to number of notes at mouse or edit cursor, restrict to item
-- 7: Smart zoom to measures at mouse or edit cursor
-- 8: Smart zoom to measures at mouse or edit cursor, restrict to item
-- 9: Scroll to mouse or edit cursor

-- VERTICAL MODES
-- 1: No change
-- 2: Zoom to notes in visible area
-- 3: Zoom to all notes in item
-- 4: Scroll note row under mouse cursor
-- 5: Scroll note row under mouse cursor, restrict to notes in visible area
-- 6: Scroll note row under mouse cursor, restrict to notes in item
-- 7: Scroll to center of notes in visible area
-- 8: Scroll to center of notes in item
-- 9: Scroll to lowest note in visible area
-- 10: Scroll to lowest note in item
-- 11: Scroll to highest note in visible area
-- 12: Scroll to highest note in item

-- Note: You can assign a different zoom mode to each MIDI editor timebase
-- by using an array with four elements, e.g {1, 2, 3, 1}
-- { Beats (project), Beats (source), Time (project), Sync to arrange }

-- Context: Toolbar button
local TBB_horizontal_zoom_mode = 1
local TBB_vertical_zoom_mode = 3

-- Context: MIDI editor note area
local MEN_horizontal_zoom_mode = {7, 1, 7, 7}
local MEN_vertical_zoom_mode = {6, 3, 3, 6}

-- Context: MIDI editor piano pane
local MEP_horizontal_zoom_mode = 2
local MEP_vertical_zoom_mode = 2

-- Context: MIDI editor ruler
local MER_horizontal_zoom_mode = {1, 1, 5, 1}
local MER_vertical_zoom_mode = {11, 11, 11, 11}

-- Context: MIDI editor CC lanes
local MEC_horizontal_zoom_mode = {1, 1, 5, 1}
local MEC_vertical_zoom_mode = {9, 9, 9, 9}

-- Context: Arrange view area
local AVA_horizontal_zoom_mode = 5
local AVA_vertical_zoom_mode = 3

-- Context: Arrange view item single click (mouse modifier)
local AIS_horizontal_zoom_mode = 5
local AIS_vertical_zoom_mode = 3

-- Context: Arrange view item double click (mouse modifier)
local AID_horizontal_zoom_mode = 2
local AID_vertical_zoom_mode = 2

------------------------------ GENERAL SETTINGS -----------------------------

-- Make this action non-contextual and always use modes from context: Toolbar button
local use_toolbar_context_only = false

-- Follow play cursor instead of edit cursor when playing
local use_play_cursor = true

-- Move edit cursor to mouse cursor
local set_edit_cursor = false

------------------------------ ZOOM SETTINGS -----------------------------

-- Number of measures to zoom to (for horizontal modes 3 and 4)
local number_of_measures = 4

-- Number of (approximate) notes to zoom to (for horizontal modes 5 and 6)
local number_of_notes = 20

-- Determines how influential the cursor position is on smart zoom levels
-- No influence: 0,  High influence: >1,  Default: 0.75
local smoothing = 0.75

-- Which note to zoom to when item/visible area contains no notes
local base_note = 60

-- Minimum number of vertical notes when zooming (not exact)
local min_vertical_notes = 8

-- Maximum vertical size for notes in pixels (smaller values increase performance)
local max_vertical_note_pixels = 32

-- Use selected notes only
local use_note_sel = false

------------------------------ FUNCTIONS ------------------------------------

local debug = false
local mb_title = 'MIDI Editor Magic'
local undo_name = 'Change media item selection (MeMagic)'
undo_name = use_toolbar_context_only and 'MeMagic zoom/scroll' or undo_name

function print(msg)
    if debug then
        reaper.ShowConsoleMsg(tostring(msg) .. '\n')
    end
end

function SetOnlyItemSelected(sel_item)
    for i = reaper.CountSelectedMediaItems(0) - 1, 0, -1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        if item then
            reaper.SetMediaItemSelected(item, false)
        end
    end
    reaper.SetMediaItemSelected(sel_item, true)
end

function GetSelection()
    local sel_start_pos, sel_end_pos = reaper.GetSet_LoopTimeRange(0, 1, 0, 0, 0)
    local is_valid_sel = sel_end_pos > 0 and sel_start_pos ~= sel_end_pos
    if is_valid_sel then
        local sel = {}
        sel.start_pos = sel_start_pos
        sel.end_pos = sel_end_pos
        return sel
    end
end

function SetSelection(sel_start_pos, sel_end_pos)
    reaper.GetSet_LoopTimeRange(1, 1, sel_start_pos, sel_end_pos, 0)
end

function GetClickMode(cmd)
    local mode = 0
    local modifiers = {
        'MM_CTX_ITEM_CLK',
        'MM_CTX_ITEM_DBLCLK',
        'MM_CTX_ITEMLOWER_CLK',
        'MM_CTX_ITEMLOWER_DBLCLK',
        'MM_CTX_AREASEL_CLK',
    }
    for _, modifier in ipairs(modifiers) do
        for i = 0, 15 do
            local action = reaper.GetMouseModifier(modifier, i, '')
            if not tonumber(action) then
                local modifier_cmd = reaper.NamedCommandLookup(action)
                if modifier_cmd == cmd then
                    local mode_id = modifier:match('DBLCLK') and 2 or 1
                    if modifier:match('MM_CTX_AREASEL_CLK') then mode_id = 2 end
                    mode = mode | mode_id
                    break
                end
            end
        end
    end
    return mode
end

function GetCursorPosition(play_state)
    local cursor_pos = reaper.BR_GetMouseCursorContext_Position()
    if not cursor_pos or cursor_pos < 0 or set_edit_cursor then
        cursor_pos = reaper.GetCursorPosition()
    end
    if play_state > 0 and use_play_cursor then
        cursor_pos = reaper.GetPlayPosition()
    end
    return cursor_pos
end

function GetZoomMode(context, timebase)
    local modes = {}

    modes[0] = {}
    modes[0].name = 'Toolbar button'
    modes[0].hzoom = TBB_horizontal_zoom_mode
    modes[0].vzoom = TBB_vertical_zoom_mode

    modes[10] = {}
    modes[10].name = 'Arrange view area'
    modes[10].hzoom = AVA_horizontal_zoom_mode
    modes[10].vzoom = AVA_vertical_zoom_mode

    modes[20] = {}
    modes[20].name = 'MIDI editor note area'
    modes[20].hzoom = MEN_horizontal_zoom_mode
    modes[20].vzoom = MEN_vertical_zoom_mode

    modes[21] = {}
    modes[21].name = 'MIDI editor piano pane'
    modes[21].hzoom = MEP_horizontal_zoom_mode
    modes[21].vzoom = MEP_vertical_zoom_mode

    modes[22] = {}
    modes[22].name = 'MIDI editor ruler'
    modes[22].hzoom = MER_horizontal_zoom_mode
    modes[22].vzoom = MER_vertical_zoom_mode

    modes[23] = {}
    modes[23].name = 'MIDI editor CC lanes'
    modes[23].hzoom = MEC_horizontal_zoom_mode
    modes[23].vzoom = MEC_vertical_zoom_mode

    modes[30] = {}
    modes[30].name = 'Arrange view item single click'
    modes[30].hzoom = AIS_horizontal_zoom_mode
    modes[30].vzoom = AIS_vertical_zoom_mode

    modes[31] = {}
    modes[31].name = 'Arrange view item double click'
    modes[31].hzoom = AID_horizontal_zoom_mode
    modes[31].vzoom = AID_vertical_zoom_mode

    local hzoom_mode, vzoom_mode
    local mode = modes[context]
    if not mode then
        print('Zoom mode of context not found')
    end

    local hzoom_min = 1
    local hzoom_max = 9

    local vzoom_min = 1
    local vzoom_max = 12

    local msg1 = 'Invalid %s zoom mode for context: %s\n'
    local msg2 = 'Mode has to be a number between %d and %d'
    local msg3 = 'Mode per timebase needs a table with 4 entries'

    if type(mode.hzoom) == 'number' then
        if mode.hzoom >= hzoom_min and mode.hzoom <= hzoom_max then
            hzoom_mode = mode.hzoom
        else
            local msg = msg1:format('horizontal', mode.name)
            msg = msg .. msg2:format(hzoom_min, hzoom_max)
            reaper.MB(msg, mb_title, 0)
        end
    end

    if type(mode.hzoom) == 'table' then
        if #mode.hzoom >= 4 then
            local timebase_hzoom = mode.hzoom[timebase]
            if timebase_hzoom >= hzoom_min and timebase_hzoom <= hzoom_max then
                hzoom_mode = timebase_hzoom
            else
                local msg = msg1:format('horizontal', mode.name)
                msg = msg .. msg2:format(hzoom_min, hzoom_max)
                reaper.MB(msg, mb_title, 0)
            end
        else
            local msg = msg1:format('horizontal', mode.name)
            reaper.MB(msg .. msg3, mb_title, 0)
        end
    end

    if type(mode.vzoom) == 'number' then
        if mode.vzoom >= vzoom_min and mode.vzoom <= vzoom_max then
            vzoom_mode = mode.vzoom
        else
            local msg = msg1:format('vertical', mode.name)
            msg = msg .. msg2:format(vzoom_min, vzoom_max)
            reaper.MB(msg, mb_title, 0)
        end
    end

    if type(mode.vzoom) == 'table' then
        if #mode.vzoom >= 4 then
            local timebase_vzoom = mode.vzoom[timebase]
            if timebase_vzoom >= vzoom_min and timebase_vzoom <= vzoom_max then
                vzoom_mode = timebase_vzoom
            else
                local msg = msg1:format('vertical', mode.name)
                msg = msg .. msg2:format(vzoom_min, vzoom_max)
                reaper.MB(msg, mb_title, 0)
            end
        else
            local msg = msg1:format('vertical', mode.name)
            reaper.MB(msg .. msg3, mb_title, 0)
        end
    end

    return hzoom_mode, vzoom_mode
end

function SetMode(hwnd, mode)
    if mode then
        local cmds = {40042, 40043, 40056, 40954}
        reaper.MIDIEditor_OnCommand(hwnd, cmds[mode])
    end
end

function SetHideUnused(hwnd, unused)
    if unused then
        local cmds = {40452, 40453, 40454}
        reaper.MIDIEditor_OnCommand(hwnd, cmds[unused])
    end
end

function SetTimebase(hwnd, timebase)
    if timebase then
        local cmds = {40459, 40470, 40460, 40461}
        reaper.MIDIEditor_OnCommand(hwnd, cmds[timebase])
    end
end

function GetEditorTimeBase()
    local tb = 0
    tb = reaper.GetToggleCommandStateEx(32060, 40459) == 1 and 1 or tb
    tb = reaper.GetToggleCommandStateEx(32060, 40470) == 1 and 2 or tb
    tb = reaper.GetToggleCommandStateEx(32060, 40460) == 1 and 3 or tb
    tb = reaper.GetToggleCommandStateEx(32060, 40461) == 1 and 4 or tb
    return tb
end

function GetItemChunkConfig(item, chunk, config)
    -- Parse the chunk to get the correct config for the active take
    local curr_tk = reaper.GetMediaItemInfo_Value(item, 'I_CURTAKE')
    local pattern = config .. ' .-\n'
    local s, e = chunk:find(pattern)
    local i = 0
    for _ = 0, curr_tk do
        s = i
        i = i + 1
        s, e = chunk:find(pattern, s)
        i = chunk:find('\nTAKE[%s\n]', i)
    end
    if s and i and s > i then
        s = nil
    end
    return s and chunk:sub(s, e)
end

function GetConfigMode(cfg_edit)
    local pattern = 'CFGEDIT .- .- .- .- .- (.-) '
    if cfg_edit then
        local mode = tonumber(cfg_edit:match(pattern))
        mode = mode & 37
        return mode == 32 and 4 or mode == 4 and 3 or mode == 1 and 2 or 1
    end
end

function GetConfigHideUnused(cfg_edit)
    local pattern = 'CFGEDIT ' .. ('.- '):rep(17) .. '(.-) '
    if cfg_edit then
        local unused = tonumber(cfg_edit:match(pattern))
        return unused + 1
    end
end

function GetConfigTimebase(cfg_edit)
    local pattern = 'CFGEDIT ' .. ('.- '):rep(18) .. '(.-) '
    if cfg_edit then
        local tb = tonumber(cfg_edit:match(pattern))
        return tb == 1 and 4 or tb == 2 and 3 or tb == 4 and 2 or 1
    end
end

function GetConfigHZoom(cfg_edit_view)
    local pattern = 'CFGEDITVIEW (.-) (.-) '
    if cfg_edit_view then
        local offset, level = cfg_edit_view:match(pattern)
        return tonumber(level), tonumber(offset)
    end
    return -1, -1
end

function GetConfigVZoom(cfg_edit_view)
    local pattern = 'CFGEDITVIEW .- .- (.-) (.-) '
    if cfg_edit_view then
        local offset, size = cfg_edit_view:match(pattern)
        return 127 - tonumber(offset), tonumber(size)
    end
    return -1, -1
end

function GetItemHZoom(item)
    local _, chunk = reaper.GetItemStateChunk(item, '', true)
    local cfg_edit_view = GetItemChunkConfig(item, chunk, 'CFGEDITVIEW')
    return GetConfigHZoom(cfg_edit_view)
end

function GetItemVZoom(item)
    local _, chunk = reaper.GetItemStateChunk(item, '', true)
    local cfg_edit_view = GetItemChunkConfig(item, chunk, 'CFGEDITVIEW')
    return GetConfigVZoom(cfg_edit_view)
end

function GetRelativeSourcePPQ(take, pos)
    local ppq_pos = reaper.MIDI_GetPPQPosFromProjTime(take, pos)
    local qn_pos = reaper.TimeMap2_timeToQN(0, pos)

    local src = reaper.GetMediaItemTake_Source(take)
    local src_length = reaper.GetMediaSourceLength(src)

    local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
    local src_qn_pos = start_qn + (qn_pos - start_qn) % src_length
    return reaper.MIDI_GetPPQPosFromProjQN(take, src_qn_pos)
end

function GetRelativeSourcePos(take, pos)
    local src_ppq_pos = GetRelativeSourcePPQ(take, pos)
    return reaper.MIDI_GetProjTimeFromPPQPos(take, src_ppq_pos)
end

function GetSourcePPQLength(take)
    local src = reaper.GetMediaItemTake_Source(take)
    local src_length = reaper.GetMediaSourceLength(src)
    local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
    return reaper.MIDI_GetPPQPosFromProjQN(take, start_qn + src_length)
end

function GetMIDIEditorView(hwnd, item, timebase)
    if timebase == 2 or timebase == 4 then
        SetTimebase(hwnd, 1)
    end

    local _, offset = GetItemHZoom(item)
    -- Cmd: Scroll view right
    reaper.MIDIEditor_OnCommand(hwnd, 40141)

    local _, scroll_offset = GetItemHZoom(item)
    -- Cmd: Scroll view left
    reaper.MIDIEditor_OnCommand(hwnd, 40140)

    if timebase == 2 or timebase == 4 then
        SetTimebase(hwnd, timebase)
    end

    local take = reaper.GetActiveTake(item)
    local start_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, offset)
    local end_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, scroll_offset)

    -- A factor is necessary to convert to the selection used for the action
    -- "Zoom to project loop selection" which is smaller than the actual visible area
    local factor = timebase == 2 and 0.97087377 or 0.943396226415
    local area = end_pos - start_pos
    local center = start_pos + area / 2
    return area * factor, center
end

function GetSmartZoomRange(take, pos, item_start_pos, item_end_pos)
    -- Algorithm is based on Shephard's method of inverse distance weighting
    -- https://en.wikipedia.org/wiki/Inverse_distance_weighting

    -- An average of all note lengths and gaps between notes is calculated. By using
    -- inverse distance weighting, notes/gaps closer to the given position have a
    -- stronger influence on the result

    -- The smoothing factor determines how much stronger this influence can be.
    -- A smoothing factor of 0, would make the distance to the given position irrelevant.

    local item = reaper.GetMediaItemTake_Item(take)
    local src_ppq_length = GetSourcePPQLength(take)

    local ppq_pos = reaper.MIDI_GetPPQPosFromProjTime(take, pos)
    local start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_start_pos)
    local end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_end_pos)

    local loop_start, loop_end = 0, 0
    if reaper.GetMediaItemInfo_Value(item, 'B_LOOPSRC') == 1 then
        local curr_iteration = math.floor(ppq_pos / src_ppq_length)
        -- For looped items
        if end_ppq - start_ppq > src_ppq_length then
            loop_start = math.max(0, curr_iteration - 1)
            loop_end = curr_iteration + 1
        end
    end

    local note_length_sum = 0
    local note_weight_sum = 0

    local prev_eppq = start_ppq
    local gap_length = 0
    local min_note_distance = math.huge

    local i = 0
    repeat
        local ret, _, _, sppq, eppq = reaper.MIDI_GetNote(take, i)
        if ret then
            local note_length = eppq - sppq
            -- Add gap between notes to note length
            if sppq >= prev_eppq then
                -- Limit gap length to something reasonable
                local min_gap_length = note_length * number_of_notes
                gap_length = math.min(min_gap_length, sppq - prev_eppq)
            end
            if eppq > prev_eppq then
                prev_eppq = eppq
            end
            for n = loop_start, loop_end do
                local sppq_o = sppq + n * src_ppq_length
                local eppq_o = eppq + n * src_ppq_length
                if eppq_o > start_ppq and sppq_o < end_ppq then
                    local note_center_ppq = sppq_o + note_length / 2
                    local note_distance = math.abs(note_center_ppq - ppq_pos)
                    -- Avoid dividing by zero (and attributing very high weights)
                    note_distance = math.max(note_distance, note_length)
                    min_note_distance = math.min(min_note_distance, note_distance)

                    local note_weight = 1 / note_distance ^ smoothing
                    local gap_note_length = note_length + gap_length
                    local weighted_gap_length = note_weight * gap_note_length
                    note_length_sum = note_length_sum + weighted_gap_length
                    note_weight_sum = note_weight_sum + note_weight
                end
            end
        end
        i = i + 1
    until not ret

    if note_weight_sum == 0 then
        return
    end

    local avg_note_length = note_length_sum / note_weight_sum
    print('Avg note length: ' .. math.floor(avg_note_length))
    local zoom_ppq_length = avg_note_length * number_of_notes

    -- If the area is empty, keep at least one note visible
    if min_note_distance ~= math.huge and zoom_ppq_length / 2.5 < min_note_distance then
        print('Using empty area hzoom level')
        zoom_ppq_length = min_note_distance * 2.5
    end

    return zoom_ppq_length
end

function GetPitchRange(take, start_pos, end_pos, item_start_pos, item_end_pos)
    local item = reaper.GetMediaItemTake_Item(take)
    local item_start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_start_pos)
    local item_end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_end_pos)

    local start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, start_pos)
    local end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, end_pos)

    start_ppq = math.max(start_ppq, item_start_ppq)
    end_ppq = math.min(end_ppq, item_end_ppq)

    if reaper.GetMediaItemInfo_Value(item, 'B_LOOPSRC') == 1 then
        local src_ppq_length = GetSourcePPQLength(take)
        if end_ppq - start_ppq >= src_ppq_length then
            start_ppq = 0
            end_ppq = src_ppq_length
        else
            start_ppq = start_ppq % src_ppq_length
            end_ppq = end_ppq % src_ppq_length
        end
    end

    local function IsNoteVisible(sppq, eppq)
        if end_ppq < start_ppq then
            return eppq > start_ppq or sppq < end_ppq
        else
            return eppq > start_ppq and sppq < end_ppq
        end
    end

    local note_lo = 128
    local note_hi = -1

    local note_avg = 0
    local note_cnt = 0

    local sel_note_lo = 128
    local sel_note_hi = -1

    local sel_note_avg = 0
    local sel_note_cnt = 0

    local i = 0
    repeat
        local ret, sel, _, sppq, eppq, _, pitch = reaper.MIDI_GetNote(take, i)
        if ret and IsNoteVisible(sppq, eppq) then
            note_lo = math.min(note_lo, pitch)
            note_hi = math.max(note_hi, pitch)
            note_avg = note_avg + pitch
            note_cnt = note_cnt + 1
            if sel then
                sel_note_lo = math.min(sel_note_lo, pitch)
                sel_note_hi = math.max(sel_note_hi, pitch)
                sel_note_avg = sel_note_avg + pitch
                sel_note_cnt = sel_note_cnt + 1
            end
        end
        i = i + 1
    until not ret

    note_avg = note_cnt > 0 and note_avg / note_cnt
    sel_note_avg = sel_note_cnt > 0 and sel_note_avg / sel_note_cnt
    if sel_note_cnt == 0 then sel_note_lo, sel_note_hi = nil, nil end

    return note_lo, note_hi, note_avg, sel_note_lo, sel_note_hi, sel_note_avg
end

function ZoomToPitchRange(hwnd, item, note_lo, note_hi)
    -- Get previous active note row
    local setting = 'active_note_row'
    local active_row = reaper.MIDIEditor_GetSetting_int(hwnd, setting)

    note_lo = math.max(note_lo, 0)
    note_hi = math.min(note_hi, 127)
    local target_row = math.floor((note_lo + note_hi) / 2)
    local curr_row = GetItemVZoom(item)

    local target_range = math.ceil((note_hi - note_lo) / 2)

    -- Set active note row to set center of vertical zoom
    reaper.MIDIEditor_SetSetting_int(hwnd, setting, curr_row)

    -- Note: Zooming when row is visible centers the note row
    -- Cmd: Zoom out vertically
    reaper.MIDIEditor_OnCommand(hwnd, 40112)

    -- Debugging output
    local row_string = ' -> ' .. curr_row
    local zoom_string = ' -> out'

    local i = 0
    repeat
        local row, size = GetItemVZoom(item)
        local pitch_range = math.min(-2, curr_row - row + 1) * -1

        if curr_row > target_row then
            curr_row = math.max(target_row, curr_row - pitch_range)
        else
            curr_row = math.min(target_row, curr_row + pitch_range)
        end
        -- Set active note row to set center of vertical zoom
        reaper.MIDIEditor_SetSetting_int(hwnd, setting, curr_row)
        row_string = row_string .. ' -> ' .. curr_row

        if pitch_range > target_range and size < max_vertical_note_pixels then
            -- Cmd: Zoom in vertically
            reaper.MIDIEditor_OnCommand(hwnd, 40111)
            zoom_string = zoom_string .. ' -> in'
        else
            -- Cmd: Zoom out vertically
            reaper.MIDIEditor_OnCommand(hwnd, 40112)
            zoom_string = zoom_string .. ' -> out'
        end
        i = i + 1
    until i == 50 or curr_row == target_row

    zoom_string = zoom_string .. ' |'

    repeat
        local row, size = GetItemVZoom(item)
        local pitch_range = math.abs(curr_row - row)
        if size > max_vertical_note_pixels then
            print('Reached max zoom size!')
            break
        end
        -- Cmd: Zoom in vertically
        reaper.MIDIEditor_OnCommand(hwnd, 40111)
        zoom_string = zoom_string .. ' -> in'
        i = i + 1
    until i == 50 or pitch_range < target_range

    repeat
        local row, size = GetItemVZoom(item)
        local pitch_range = math.abs(curr_row - row)
        if size == 4 then
            print('Reached min zoom size!')
            break
        end
        -- Cmd: Zoom out vertically
        reaper.MIDIEditor_OnCommand(hwnd, 40112)
        zoom_string = zoom_string .. ' -> out'
        i = i + 1
    until i == 50 or pitch_range >= target_range and size <= max_vertical_note_pixels

    print('Target row:' .. target_row)
    print(row_string)
    print(zoom_string)
    local _, zoom_cnt = zoom_string:gsub(' %-', '')
    print('Vertically zooming ' .. zoom_cnt .. ' times')

    -- Reset previous active note row
    if active_row and active_row ~= '' then
        reaper.MIDIEditor_SetSetting_int(hwnd, setting, active_row)
    end
end

function ScrollToNoteRow(hwnd, item, target_row, note_lo, note_hi)
    -- Get previous active note row
    local setting = 'active_note_row'
    local active_row = reaper.MIDIEditor_GetSetting_int(hwnd, setting)

    local curr_row = GetItemVZoom(item)
    -- Set active note row to set center of vertical zoom
    reaper.MIDIEditor_SetSetting_int(hwnd, setting, curr_row)

    if note_lo and note_hi then
        note_lo = math.max(note_lo, 0)
        note_hi = math.min(note_hi, 127)
        target_row = math.max(target_row, note_lo)
        target_row = math.min(target_row, note_hi)
    end

    -- Note: Zooming when row is visible centers the note row
    -- Cmd: Zoom in vertically
    reaper.MIDIEditor_OnCommand(hwnd, 40111)
    local zoom_in_cnt = 1
    local backup_target_row
    local target_range

    -- Debugging output
    local row_string = ' -> ' .. curr_row
    local zoom_string = ' -> in'

    local i = 0
    repeat
        local row, size = GetItemVZoom(item)
        local pitch_range = math.min(-2, curr_row - row + 1) * -1

        if row == 127 and i == 0 and not backup_target_row then
            -- When row 127 is visible it's not possible to get the target range.
            -- Scroll down until it isn't and keep target row as backup
            backup_target_row = target_row
            target_row = 0
        end

        if row < 127 and zoom_in_cnt == 0 and not target_range then
            target_range = pitch_range
            target_row = backup_target_row or target_row

            local note_range = math.ceil((note_hi - note_lo) / 2)
            if pitch_range > note_range then
                local diff = pitch_range - note_range
                note_hi = note_hi + diff * 2
                note_lo = note_lo - diff * 2
            end
            if target_row < note_lo + pitch_range then
                target_row = note_lo + pitch_range
            else
                if target_row > note_hi - pitch_range then
                    target_row = note_hi - pitch_range
                end
            end
            zoom_string = zoom_string .. ' -> R'
            row_string = row_string .. ' -> R'
        end

        if curr_row > target_row then
            curr_row = math.max(target_row, curr_row - pitch_range)
        else
            curr_row = math.min(target_row, curr_row + pitch_range)
        end

        if curr_row == target_row and not target_range and backup_target_row then
            target_row = pitch_range
        end

        -- Set active note row to set center of vertical zoom
        reaper.MIDIEditor_SetSetting_int(hwnd, setting, curr_row)
        row_string = row_string .. ' -> ' .. curr_row

        if zoom_in_cnt > 0 then
            -- Cmd: Zoom out vertically
            reaper.MIDIEditor_OnCommand(hwnd, 40112)
            zoom_string = zoom_string .. ' -> out'
            zoom_in_cnt = zoom_in_cnt - 1
        else
            -- Cmd: Zoom in vertically
            reaper.MIDIEditor_OnCommand(hwnd, 40111)
            zoom_string = zoom_string .. ' -> in'
            zoom_in_cnt = zoom_in_cnt + 1
        end
        i = i + 1
    until i == 50 or curr_row == target_row and zoom_in_cnt == 0 and i > 2

    print('Target row:' .. target_row)
    print('Target range:' .. tostring(target_range))
    print(row_string)
    print(zoom_string)
    local _, zoom_cnt = zoom_string:gsub(' %-', '')
    print('Vertically zooming ' .. zoom_cnt .. ' times')

    -- Reset previous active note row
    if active_row and active_row ~= '' then
        reaper.MIDIEditor_SetSetting_int(hwnd, setting, active_row)
    end
end

--------------------------------- CODE START -----------------------------------

local start_time = reaper.time_precise()
local _, _, _, cmd, rel, res, val = reaper.get_action_context()
local extname = 'FTC.MeMagic_' .. cmd

reaper.Undo_BeginBlock()

-- Check if SWS extension installed
if not reaper.SNM_GetIntConfigVar then
    reaper.MB('Please install SWS extension', mb_title, 0)
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

local config = reaper.SNM_GetIntConfigVar('midieditor', 0)
local editor_type = config % 4

local has_js_api = reaper.JS_MIDIEditor_ListAll ~= nil

-- Force setting: One MIDI editor per project
if not use_toolbar_context_only and editor_type ~= 1 and not has_js_api then
    local msg = 'This script requires the mode: One MIDI editor per project\z
        \n\n(You can also install JS_ReaScriptAPI to use it with other modes)\z
        \n\nChange mode now?'
    local ret = reaper.MB(msg, mb_title, 4)
    if ret == 6 then
        config = config - editor_type + 1
        reaper.SNM_SetIntConfigVar('midieditor', config)
    else
        reaper.Undo_EndBlock(undo_name, -1)
        return
    end
end

local play_state = reaper.GetPlayState()
local hwnd = reaper.MIDIEditor_GetActive()
local editor_take = reaper.MIDIEditor_GetTake(hwnd)
local is_valid_take = reaper.ValidatePtr(editor_take, 'MediaItem_Take*')
local editor_item = is_valid_take and reaper.GetMediaItemTake_Item(editor_take)
local window, segment, details = reaper.BR_GetMouseCursorContext()
local _, _, note_row = reaper.BR_GetMouseCursorContext_MIDI()
local is_hotkey = not (rel == -1 and res == -1 and val == -1)

local timestamp = tonumber(reaper.GetExtState(extname, 'timestamp'))
local exec_time = tonumber(reaper.GetExtState(extname, 'exec_time'))

local click_mode = 0
local context = -1

local sel_item
local cursor_pos

-- Handle mouse modifiers
if window == 'arrange' and not is_hotkey then
    click_mode = GetClickMode(cmd)
    if click_mode == 0 then
        -- This should only happen on item edges
        print('No mouse modifer found. Exiting')
        reaper.Undo_EndBlock(undo_name, -1)
        return
    end
    if click_mode == 3 then
        -- When script is used as both single and double click, use time interval
        -- to determine mode
        click_mode = timestamp and start_time - timestamp < 0.3 and 2 or 1
    end
end

if is_hotkey and timestamp then
    reaper.SetExtState(extname, 'timespan', start_time - timestamp, false)
    if exec_time then
        local min_time = timestamp + exec_time * 4
        if start_time < min_time and click_mode ~= 2 then
            print('Previous script still running. Exiting')
            reaper.Undo_EndBlock(undo_name, -1)
            return
        end
    end
end
reaper.SetExtState(extname, 'timestamp', start_time, false)

if debug then
    reaper.ClearConsole()
end

if not use_toolbar_context_only and window == 'midi_editor' then
    -- Context: MIDI editor note area
    if segment == 'notes' then
        context = 20
    end
    -- Context: MIDI editor piano pane
    if segment == 'piano' then
        context = 21
    end
    -- Context: MIDI editor ruler
    if segment == 'ruler' then
        context = 22
    end
    -- Context: MIDI editor CC lanes
    if segment == 'cc_lane' then
        context = 23
    end
end

-- Context: Arrange view area
if window == 'arrange' then
    context = 10
end

if not is_hotkey then
    -- Context: Toolbar button
    if window == 'unknown' or segment == 'unknown' then
        context = 0
    end
    if window == 'arrange' then
        -- Context: Arrange view item single click (mouse modifier)
        if click_mode == 1 then
            context = 30
        end
        -- Context: Arrange view item double click (mouse modifier)
        if click_mode == 2 then
            context = 31
        end
    end
end

-- Non-Contextual mode
if use_toolbar_context_only then
    context = 0
end

if context == -1 then
    print('Unkown context. Exiting.')
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

if window == 'arrange' and (context > 0 or click_mode > 0) then
    if set_edit_cursor and (play_state == 0 or not use_play_cursor) then
        -- Cmd: Move edit cursor to mouse cursor
        reaper.Main_OnCommand(40513, 0)
    end
    local sel_item_cnt = reaper.CountSelectedMediaItems(0)
    -- Cmd: Select item under mouse cursor (leaving other items selected)
    reaper.Main_OnCommand(40529, 0)

    if sel_item_cnt > 1 or sel_item_cnt ~= reaper.CountSelectedMediaItems(0) then
        -- Cmd: Select item under mouse cursor
        reaper.Main_OnCommand(40528, 0)
    end
    sel_item = reaper.GetSelectedMediaItem(0, 0)

    if sel_item then
        local take = reaper.GetActiveTake(sel_item)
        -- Handle empty take lanes
        if not reaper.ValidatePtr(take, 'MediaItem_Take*') then
            print('Take is an empty take lane')
            if reaper.GetMediaItemNumTakes(sel_item) == 0 then
                -- Item: Show notes for items...
                reaper.Main_OnCommand(40850, 0)
            end
            reaper.Undo_EndBlock(undo_name, -1)
            return
        end
        -- Handle non-MIDI takes
        if not reaper.TakeIsMIDI(take) then
            if click_mode == 2 then
                local src = reaper.GetMediaItemTake_Source(take)
                local src_type = reaper.GetMediaSourceType(src, '')
                -- Open video window if not already open (else item properties)
                if src_type == 'VIDEO' then
                    if reaper.GetToggleCommandState(50125) == 0 then
                        -- Video: Show/hide video window
                        reaper.Main_OnCommand(50125, 0)
                        undo_name = 'Show/hide video window'
                        reaper.Undo_EndBlock(undo_name, -1)
                        return
                    end
                end
                if src_type == 'RPP_PROJECT' then
                    -- Cmd: Open associated project in new tab
                    reaper.Main_OnCommand(41816, 0)
                    undo_name = 'Open associated project in new tab'
                else
                    -- Cmd: Show media item/take properties
                    reaper.Main_OnCommand(40009, 0)
                    undo_name = 'Show media item/take properties'
                end
            end
            reaper.Undo_EndBlock(undo_name, -1)
            return
        end
    end
end

-- Quit when single click mouse modifier and editor is closed
if context == 30 and not hwnd then
    print('No editor open. Exiting')
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

if context == 20 or context == 22 or context == 23 then
    if set_edit_cursor and (play_state == 0 or not use_play_cursor) then
        -- Cmd: Move edit cursor to mouse cursor
        reaper.MIDIEditor_OnCommand(hwnd, 40443)
    end
    -- Select closest item to cursor
    if editor_item then
        local GetItemInfoValue = reaper.GetMediaItemInfo_Value
        local item_length = GetItemInfoValue(editor_item, 'D_LENGTH')
        local item_start_pos = GetItemInfoValue(editor_item, 'D_POSITION')
        local item_end_pos = item_start_pos + item_length
        local editor_track = reaper.GetMediaItem_Track(editor_item)
        cursor_pos = GetCursorPosition(play_state)
        -- Check for other items on the same track
        if cursor_pos < item_start_pos then
            for i = 0, reaper.CountTrackMediaItems(editor_track) - 1 do
                local item = reaper.GetTrackMediaItem(editor_track, i)
                local length = GetItemInfoValue(item, 'D_LENGTH')
                local start_pos = GetItemInfoValue(item, 'D_POSITION')
                local end_pos = start_pos + length
                if cursor_pos < end_pos then
                    if item ~= editor_item then
                        sel_item = item
                        SetOnlyItemSelected(sel_item)
                    end
                    break
                end
            end
        end
        if cursor_pos > item_end_pos then
            for i = reaper.CountTrackMediaItems(editor_track) - 1, 0, -1 do
                local item = reaper.GetTrackMediaItem(editor_track, i)
                local start_pos = GetItemInfoValue(item, 'D_POSITION')
                if cursor_pos > start_pos then
                    if item ~= editor_item then
                        sel_item = item
                        SetOnlyItemSelected(sel_item)
                    end
                    break
                end
            end
        end
    end
end

if not is_valid_take and not sel_item then
    print('No editor item found. Exiting')
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

cursor_pos = cursor_pos or GetCursorPosition(play_state)

local hlength, hcenter
local prev_hzoom_lvl = tonumber(reaper.GetExtState(extname, 'hzoom_lvl'))

if sel_item and (editor_take ~= reaper.GetActiveTake(sel_item) or click_mode > 0) then
    print('Opening selected item in editor')
    local cfg_edit
    if is_valid_take then
        local chunk = select(2, reaper.GetItemStateChunk(editor_item, '', true))
        local cfg_edit_view = GetItemChunkConfig(editor_item, chunk,
            'CFGEDITVIEW')
        cfg_edit = GetItemChunkConfig(editor_item, chunk, 'CFGEDIT')
        -- Check editor length in case reaper will change zoom level
        local hzoom_lvl = GetConfigHZoom(cfg_edit_view)
        if hzoom_lvl ~= prev_hzoom_lvl then
            print('Getting horizontal editor length')
            local timebase = GetEditorTimeBase()
            prev_hzoom_lvl = hzoom_lvl
            hlength, hcenter = GetMIDIEditorView(hwnd, editor_item, timebase)
        end
    end

    -- Cmd: Open in built-in MIDI editor
    reaper.Main_OnCommand(40153, 0)

    if has_js_api then
        local _, list = reaper.JS_MIDIEditor_ListAll()
        local sel_take = reaper.GetActiveTake(sel_item)
        for addr in (list .. ','):gmatch('(.-),') do
            local editor_hwnd = reaper.JS_Window_HandleFromAddress(addr)
            if reaper.MIDIEditor_GetTake(editor_hwnd) == sel_take then
                hwnd = editor_hwnd
                break
            end
        end
    else
        hwnd = reaper.MIDIEditor_GetActive()
    end
    editor_take = reaper.GetActiveTake(sel_item)
    editor_item = sel_item

    if cfg_edit then
        -- Sometimes editor modes are not kept. This fixes this issue
        local item_mode = GetConfigMode(cfg_edit)
        SetMode(hwnd, item_mode)
    end
end

local track = reaper.GetMediaItem_Track(editor_item)
local item_length = reaper.GetMediaItemInfo_Value(editor_item, 'D_LENGTH')
local item_start_pos = reaper.GetMediaItemInfo_Value(editor_item, 'D_POSITION')
local item_end_pos = item_start_pos + item_length

local timebase = GetEditorTimeBase()

if timebase == 2 then
    if window == 'arrange' then
        cursor_pos = GetRelativeSourcePos(editor_take, cursor_pos)
    end
    local src_ppq_length = GetSourcePPQLength(editor_take)
    item_start_pos = reaper.MIDI_GetProjTimeFromPPQPos(editor_take, 0)
    item_end_pos = reaper.MIDI_GetProjTimeFromPPQPos(editor_take, src_ppq_length)
    item_length = item_end_pos - item_start_pos
end
local is_cursor_inside_item = cursor_pos >= item_start_pos and
    cursor_pos <= item_end_pos

----------------------------------- ZOOM MODES ---------------------------------------

local hzoom_mode, vzoom_mode = GetZoomMode(context, timebase)

local prev_note_row, prev_note_lo, prev_note_hi
local timespan = tonumber(reaper.GetExtState(extname, 'timespan'))

if is_hotkey and timespan and timespan < 0.25 then
    print('Fast mode: Preloading settings')
    prev_note_row = tonumber(reaper.GetExtState(extname, 'note_row'))
    prev_note_lo = tonumber(reaper.GetExtState(extname, 'note_lo'))
    prev_note_hi = tonumber(reaper.GetExtState(extname, 'note_hi'))
    hlength = tonumber(reaper.GetExtState(extname, 'hlength'))
    hcenter = tonumber(reaper.GetExtState(extname, 'hcenter'))

    -- Make horizontal movements smoother
    if hcenter and cursor_pos >= 0 and context >= 20 and context < 30 then
        local cursor_diff = cursor_pos - hcenter
        local factor = math.abs(cursor_diff / hlength * 2)
        cursor_pos = hcenter + cursor_diff * factor
        if hzoom_mode ~= 1 then
            hcenter = cursor_pos
        end
    end

    -- Make vertical movements smoother
    if prev_note_row and prev_note_row >= 0 then
        local row_diff = note_row - prev_note_row
        local row_diff_abs = math.abs(row_diff)
        if row_diff_abs > 1 then
            local sign = row_diff / row_diff_abs
            note_row = prev_note_row + sign * math.floor(row_diff_abs ^ 0.5)
        end
    end
end

if not vzoom_mode or not hzoom_mode then
    print('Invalid mode. Exiting')
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

local is_smart_zoom_mode = hzoom_mode == 5 or hzoom_mode == 6
local hzoom_lvl = GetItemHZoom(editor_item)

if not hlength or not hcenter or prev_hzoom_lvl ~= hzoom_lvl and not is_smart_zoom_mode then
    print('Getting horizontal editor length')
    hlength, hcenter = GetMIDIEditorView(hwnd, editor_item, timebase)
end

if is_hotkey and is_smart_zoom_mode and not is_cursor_inside_item then
    -- TODO find a better solution
    vzoom_mode = 1
    hzoom_mode = 7
end

reaper.SetExtState(extname, 'hzoom_lvl', hzoom_lvl, false)
reaper.SetExtState(extname, 'hlength', hlength, false)
reaper.SetExtState(extname, 'hcenter', hcenter, false)

-------------------------------- HORIZONTAL ZOOM RANGE ----------------------------------

local zoom_start_pos, zoom_end_pos

if hzoom_mode == 1 then
    zoom_start_pos = hcenter - hlength / 2
    zoom_end_pos = hcenter + hlength / 2
end

if hzoom_mode == 2 then
    zoom_start_pos = item_start_pos
    zoom_end_pos = item_end_pos
end

-- Set zoom to number of measures
if hzoom_mode == 3 or hzoom_mode == 4 then
    local convQNToTime = reaper.TimeMap2_QNToTime
    local sig_num = reaper.TimeMap_GetTimeSigAtTime(0, cursor_pos)
    local cursor_qn = reaper.TimeMap2_timeToQN(0, cursor_pos)
    zoom_start_pos = convQNToTime(0, cursor_qn - sig_num * number_of_measures / 2)
    zoom_end_pos = convQNToTime(0, cursor_qn + sig_num * number_of_measures / 2)
end

-- Set zoom to number of notes
if hzoom_mode >= 5 and hzoom_mode <= 8 then
    local zoom_ppq_length =
        GetSmartZoomRange(editor_take, cursor_pos, item_start_pos, item_end_pos)
    if zoom_ppq_length then
        local GetTimeFromPPQ = reaper.MIDI_GetProjTimeFromPPQPos
        local GetPPQFromTime = reaper.MIDI_GetPPQPosFromProjTime
        local cursor_ppq_pos = GetPPQFromTime(editor_take, cursor_pos)
        zoom_start_pos = GetTimeFromPPQ(editor_take,
            cursor_ppq_pos - zoom_ppq_length / 2)
        zoom_end_pos = GetTimeFromPPQ(editor_take,
            cursor_ppq_pos + zoom_ppq_length / 2)
    else
        zoom_start_pos = item_start_pos
        zoom_end_pos = item_end_pos
    end

    if hzoom_mode >= 7 then
        local TimeToBeats = reaper.TimeMap2_timeToBeats
        local BeatsToTime = reaper.TimeMap2_beatsToTime
        local _, _, _, zoom_start_beats = TimeToBeats(0, zoom_start_pos)
        local _, _, _, zoom_end_beats = TimeToBeats(0, zoom_end_pos)
        local convQNToTime = reaper.TimeMap2_QNToTime
        local sig_num = reaper.TimeMap_GetTimeSigAtTime(0, cursor_pos)
        local cursor_qn = reaper.TimeMap2_timeToQN(0, cursor_pos)
        local measures = (zoom_end_beats - zoom_start_beats) / sig_num
        if measures < 10 then
            -- Find multiple of 2
            local exp = math.log(measures, 2)
            measures = 2 ^ math.floor(exp + 0.5)
        else
            measures = math.floor(measures + 0.5)
        end
        zoom_start_pos = convQNToTime(0, cursor_qn - sig_num * measures / 2)
        zoom_end_pos = convQNToTime(0, cursor_qn + sig_num * measures / 2)
    end
end

if hzoom_mode == 9 then
    zoom_start_pos = cursor_pos - hlength / 2
    zoom_end_pos = cursor_pos + hlength / 2
end

------------------------- HORIZONTAL ZOOM RANGE RESTRICTION ---------------------------

local zoom_length = zoom_end_pos - zoom_start_pos

-- Edge case: Zoom start is below zero
if zoom_start_pos < 0 then
    zoom_start_pos = 0
    zoom_end_pos = zoom_length
end

-- Edge case: Zoom start is below item start in timebase source beats
if timebase == 2 and zoom_start_pos < item_start_pos then
    zoom_start_pos = item_start_pos
    zoom_end_pos = zoom_start_pos + zoom_length
end

-- Restrict zoom to item edges based on mode
if hzoom_mode == 4 or hzoom_mode == 6 or hzoom_mode == 8 then
    if zoom_length < item_length then
        if zoom_start_pos < item_start_pos then
            zoom_start_pos = item_start_pos
            zoom_end_pos = zoom_start_pos + zoom_length
        end
        if zoom_end_pos > item_end_pos then
            zoom_start_pos = item_end_pos - zoom_length
            zoom_end_pos = item_end_pos
        end
    else
        zoom_start_pos = item_start_pos
        zoom_end_pos = item_end_pos
    end
end

----------------------------------- VERTICAL ZOOM -----------------------------------

local are_notes_hidden = reaper.GetToggleCommandStateEx(32060, 40452) ~= 1
local is_notation = reaper.GetToggleCommandStateEx(32060, 40954) == 1

-- Analyze take pitch in the given area. Find highest and lowest pitch
if vzoom_mode > 0 and not is_notation then
    -- Note: Visible zoom area is larger than project loop selection by a certain factor
    local factor = timebase == 2 and 0.015 or 0.03
    local start_pos = zoom_start_pos - zoom_length * factor
    local end_pos = zoom_end_pos + zoom_length * factor

    if vzoom_mode == 3 or vzoom_mode > 4 and vzoom_mode % 2 == 0 then
        start_pos = item_start_pos
        end_pos = item_end_pos
    end

    local note_lo, note_hi, note_avg, sel_note_lo, sel_note_hi, sel_note_avg =
        GetPitchRange(editor_take, start_pos, end_pos, item_start_pos,
            item_end_pos)

    if are_notes_hidden then
        print('Notes are hidden. Zooming to content')
        -- Cmd: Zoom to content
        reaper.MIDIEditor_OnCommand(hwnd, 40466)
    elseif not use_note_sel or sel_note_lo then
        if vzoom_mode >= 2 and vzoom_mode <= 3 then
            if use_note_sel then
                note_lo = sel_note_lo or note_lo
                note_hi = sel_note_hi or note_hi
                note_avg = sel_note_avg or note_avg
            end

            if note_hi == -1 then
                print('No note in area/take: Setting base note')
                note_lo, note_hi = base_note, base_note
            end

            if note_hi - note_lo < min_vertical_notes then
                print('Using minimum pitch range')
                note_hi = math.ceil((note_lo + note_hi + min_vertical_notes) / 2)
                note_lo = math.floor((note_lo + note_hi - min_vertical_notes) / 2)
                note_lo = note_hi < 127 and note_lo or 127
                note_hi = note_hi < 127 and note_hi or 127 - min_vertical_notes
            end

            if prev_note_lo ~= note_lo or prev_note_hi ~= note_hi then
                local msg = 'Vertically zooming to notes %s - %s'
                print(msg:format(note_lo, note_hi))
                if note_hi - note_lo < 28 then
                    ZoomToPitchRange(hwnd, editor_item, note_lo - 1, note_hi + 1)
                else
                    ZoomToPitchRange(hwnd, editor_item, note_lo, note_hi)
                end
            end
        end
        if vzoom_mode >= 4 and vzoom_mode <= 12 then
            if vzoom_mode == 4 or note_hi == -1 then
                note_lo, note_hi = 0, 127
            end

            if vzoom_mode >= 7 and vzoom_mode <= 8 then
                if use_note_sel then note_avg = sel_note_avg or note_avg end
                note_avg = note_avg or (note_lo + note_hi) / 2
                note_row = math.floor(note_avg)
            end

            if vzoom_mode >= 9 and vzoom_mode <= 10 then
                note_row = 0
                if use_note_sel then note_row = sel_note_lo or note_row end
            end

            if vzoom_mode >= 11 and vzoom_mode <= 12 then
                note_row = 127
                if use_note_sel then note_row = sel_note_hi or note_row end
            end

            if note_row and note_row >= 0 then
                local scroll_changed = prev_note_row ~= note_row
                scroll_changed = scroll_changed or prev_note_lo ~= note_lo
                scroll_changed = scroll_changed or prev_note_hi ~= note_hi
                if scroll_changed then
                    print('Vertically scrolling to note ' .. note_row)
                    print('Scroll lo/hi limit: ' .. note_lo .. '/' .. note_hi)
                    ScrollToNoteRow(hwnd, editor_item, note_row, note_lo - 1,
                        note_hi + 1)
                end
            end
        end
    end
    reaper.SetExtState(extname, 'note_row', note_row, false)
    reaper.SetExtState(extname, 'note_lo', note_lo, false)
    reaper.SetExtState(extname, 'note_hi', note_hi, false)
end

---------------------------------- HORIZONTAL ZOOM ----------------------------------

-- Get previous time selection
local sel = GetSelection()
reaper.PreventUIRefresh(1)

SetSelection(zoom_start_pos, zoom_end_pos)
-- Cmd: Zoom to project loop selection
reaper.MIDIEditor_OnCommand(hwnd, 40726)

-- Reset previous time selection
local sel_start_pos = sel and sel.start_pos or 0
local sel_end_pos = sel and sel.end_pos or 0
if not debug then
    SetSelection(sel_start_pos, sel_end_pos)
end

reaper.PreventUIRefresh(-1)

exec_time = reaper.time_precise() - start_time
print('\nExecution time: ' .. math.floor(exec_time * 1000 + 0.5) .. ' ms')
reaper.SetExtState(extname, 'exec_time', exec_time, false)

local is_docked = reaper.GetToggleCommandStateEx(32060, 40018) == 1
if is_docked and click_mode == 1 then reaper.SetCursorContext(1, 0) end
reaper.Undo_EndBlock(undo_name, -1)
