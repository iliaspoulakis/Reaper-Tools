--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.4
  @about Opens multiple items in the MIDI editor and scrolls to the center of their content
  @changelog
    - Use SWS zoom to selected items (to also show track envelopes)
]]
------------------------------ SETTINGS -----------------------------

-- Which note to scroll to when item/visible area contains no notes
local base_note = 60

-- When double clicking midi items, keep all items selected (Mouse modifier)
local keep_items_selected = true

-- Behavior when double-clicking on audio items
local zoom_to_audio_items = true

-- Make script close MIDI editor when already open (toggle)
local toggle_editor = false

---------------------------------------------------------------------

local debug = false
local undo_name = 'Multi edit scroll'
local start_time = reaper.time_precise()

if debug then
    reaper.ClearConsole()
end

function print(msg)
    if debug then
        reaper.ShowConsoleMsg(tostring(msg) .. '\n')
    end
end

function setSelection(sel_start_pos, sel_end_pos)
    reaper.GetSet_LoopTimeRange(true, true, sel_start_pos, sel_end_pos, false)
end

function getSelection()
    local getSetLoopTimeRange = reaper.GetSet_LoopTimeRange
    local sel_start_pos, sel_end_pos = getSetLoopTimeRange(false, true, 0, 0, false)
    local is_valid_sel = sel_end_pos > 0 and sel_start_pos ~= sel_end_pos
    if is_valid_sel then
        local sel = {}
        sel.start_pos = sel_start_pos
        sel.end_pos = sel_end_pos
        return sel
    end
end

function getItemChunkConfig(item, chunk, config)
    -- Parse the chunk to get the correct config for the active take
    local curr_tk = reaper.GetMediaItemInfo_Value(item, 'I_CURTAKE')
    local pattern = config .. ' .-\n'
    local s, e = chunk:find(pattern, s)
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

function getConfigVZoom(cfg_edit_view)
    local pattern = 'CFGEDITVIEW .- .- (.-) (.-) '
    if cfg_edit_view then
        local offset, size = cfg_edit_view:match(pattern)
        return 127 - tonumber(offset), tonumber(size)
    end
    return -1, -1
end

function getItemVZoom(item)
    local _, chunk = reaper.GetItemStateChunk(item, '', true)
    local cfg_edit_view = getItemChunkConfig(item, chunk, 'CFGEDITVIEW')
    return getConfigVZoom(cfg_edit_view)
end

function getSourcePPQLength(take)
    local source = reaper.GetMediaItemTake_Source(take)
    local source_length = reaper.GetMediaSourceLength(source)
    local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
    return reaper.MIDI_GetPPQPosFromProjQN(take, start_qn + source_length)
end

function scrollToNoteRow(hwnd, item, target_row, note_lo, note_hi)
    -- Get previous active note row
    local setting = 'active_note_row'
    local active_row = reaper.MIDIEditor_GetSetting_int(hwnd, setting)

    local curr_row = getItemVZoom(item)
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
        local row, size = getItemVZoom(item)
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

if not reaper.SNM_GetIntConfigVar then
    reaper.MB('Please install SWS extension', 'Error', 0)
    return
end

if toggle_editor then
    local hwnd = reaper.MIDIEditor_GetActive()
    if hwnd then
        -- View: Toggle show MIDI editor windows
        reaper.Main_OnCommand(40716, 0)
        reaper.Undo_OnStateChange(undo_name)
        return
    end
end

reaper.PreventUIRefresh(1)

local init_item
local window = reaper.BR_GetMouseCursorContext()
local _, _, _, _, rel, res, val = reaper.get_action_context()

-- Check if action is executed through item context mouse modifier
if window == 'arrange' and rel == -1 and res == -1 and val == -1 then
    -- Commit potential item selection change caused by left click
    reaper.Undo_BeginBlock()
    reaper.Undo_EndBlock('Uncommitted', -1)
    -- Check if there were uncommited changes and revert them
    if reaper.Undo_CanUndo2(0) == 'Uncommitted' then
        init_item = reaper.GetSelectedMediaItem(0, 0)
        local cursor_pos = reaper.GetCursorPosition()
        reaper.Undo_DoUndo2(0)
        reaper.SetEditCurPos(cursor_pos, false, false)
    end
end

reaper.Undo_BeginBlock()

local sel_item_cnt = reaper.CountSelectedMediaItems(0)
if sel_item_cnt == 0 then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

if not init_item and sel_item_cnt == 1 then
    init_item = reaper.GetSelectedMediaItem(0, 0)
end

if init_item then
    local take = reaper.GetActiveTake(init_item)
    local is_valid = reaper.ValidatePtr(take, 'MediaItem_Take*')

    if not is_valid or not reaper.TakeIsMIDI(take) then
        if is_valid then
            local source = reaper.GetMediaItemTake_Source(take)
            local file_name = reaper.GetMediaSourceFileName(source, '')
            local video_extensions = {'mp4', 'gif'}
            for _, extension in ipairs(video_extensions) do
                if file_name:lower():match('[^.]+$') == extension then
                    local is_video_visible = reaper.GetToggleCommandState(50125) == 1
                    if not is_video_visible then
                        -- Video: Show/hide video window
                        reaper.Main_OnCommand(50125, 0)
                        reaper.PreventUIRefresh(-1)
                        reaper.Undo_EndBlock(undo_name, -1)
                        return
                    end
                end
            end
            local _, chunk = reaper.GetItemStateChunk(init_item, '', true)
            local is_subproject = chunk:match('SOURCE RPP_PROJECT')
            reaper.PreventUIRefresh(-1)
            if is_subproject then
                -- Cmd: Open associated project in new tab
                reaper.Main_OnCommand(41816, 0)
                undo_name = 'Item: Open associated project in new tab'
            else
                if zoom_to_audio_items then
                    -- SWS: Toggle zoom to selected items
                    local cmd = reaper.NamedCommandLookup('_SWS_TOGZOOMIONLY')
                    reaper.Main_OnCommand(cmd, 0)
                    undo_name = 'Toggle zoom to selected items'
                else
                    -- Cmd: Show media item/take properties
                    reaper.Main_OnCommand(40009, 0)
                    undo_name = 'Show media item/take properties'
                end
            end
        end
        reaper.Undo_EndBlock(undo_name, -1)
        return
    end
end

local sel_items = {}

-- Get selected items
for i = 0, sel_item_cnt - 1 do
    sel_items[#sel_items + 1] = reaper.GetSelectedMediaItem(0, i)
end

local zoom_start_pos = math.huge
local zoom_end_pos = 0

local note_lo = 128
local note_hi = -1

local density = 0
local density_cnt = 0

-- Analyze all selected items
for _, item in ipairs(sel_items) do
    local take = reaper.GetActiveTake(item)
    if reaper.ValidatePtr(take, 'MediaItem_Take*') and reaper.TakeIsMIDI(take) then
        -- Get mininum item start position and maximum item end position
        local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local item_end_pos = item_start_pos + item_length
        zoom_start_pos = math.min(zoom_start_pos, item_start_pos)
        zoom_end_pos = math.max(zoom_end_pos, item_end_pos)

        -- Get note center
        local start_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_start_pos)
        local end_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, item_end_pos)

        if reaper.GetMediaItemInfo_Value(item, 'B_LOOPSRC') == 1 then
            local source_ppq_length = getSourcePPQLength(take)
            if end_ppq - start_ppq >= source_ppq_length then
                start_ppq = 0
                end_ppq = source_ppq_length
            else
                start_ppq = start_ppq % source_ppq_length
                end_ppq = end_ppq % source_ppq_length
            end
        end

        local function isNoteVisible(sppq, eppq)
            if end_ppq < start_ppq then
                return eppq > start_ppq or sppq < end_ppq
            else
                return eppq > start_ppq and sppq < end_ppq
            end
        end
        local i = 0
        repeat
            local ret, _, _, sppq, eppq, _, pitch = reaper.MIDI_GetNote(take, i)
            if ret and isNoteVisible(sppq, eppq) then
                note_lo = math.min(note_lo, pitch)
                note_hi = math.max(note_hi, pitch)
                density = density + pitch
                density_cnt = density_cnt + 1
            end
            i = i + 1
        until not ret
    end
end

-- No MIDI items found
if zoom_start_pos == math.huge then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

-- Change MIDI editor settings for multi-edit
local config = reaper.SNM_GetIntConfigVar('midieditor', 0)

local click_type = config & 20
local other_tracks_editable = config & 256
local editability = config & 512
local visibility = config & 1024
local edit_secondary = config & 4096

local new_config = config
-- Set click type to 'Open all selected MIDI items'
new_config = new_config - click_type
-- Disable 'Avoid automatically setting items from other tracks editable'
new_config = new_config - other_tracks_editable + 256
-- Disable 'Selection is linked to editability'
new_config = new_config - editability + 512
-- Enable 'Selection is linked to visibility'
new_config = new_config - visibility
-- Enable 'Make secondary items editable by default'
new_config = new_config - edit_secondary + 4096
reaper.SNM_SetIntConfigVar('midieditor', new_config)

-- Cmd: Open in built-in MIDI editor
reaper.Main_OnCommand(40153, 0)

local hwnd = reaper.MIDIEditor_GetActive()
local editor_take = reaper.MIDIEditor_GetTake(hwnd)

if not reaper.ValidatePtr(editor_take, 'MediaItem_Take*') then
    reaper.PreventUIRefresh(-1)
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

-- Note: Setting 'Selection is linked to visibility' can change item selection to
-- all items that are open (visible) in editor
if reaper.CountSelectedMediaItems(0) ~= sel_item_cnt then
    -- Contents: Activate next MIDI media item on this track, clearing the editor first
    reaper.MIDIEditor_OnCommand(hwnd, 40798)
    -- We use this for clearing, if active item changes this needs to be reverted
    if reaper.MIDIEditor_GetTake(hwnd) ~= editor_take then
        -- Contents: Activate previous MIDI media item on this track, clearing the ...
        reaper.MIDIEditor_OnCommand(hwnd, 40797)
    end
end

-- Reset config to original state
reaper.SNM_SetIntConfigVar('midieditor', config)

if visibility == 0 or keep_items_selected then
    init_item = nil
end

-- Restore previous item selection
if reaper.CountSelectedMediaItems(0) ~= sel_item_cnt or init_item then
    reaper.SelectAllMediaItems(0, false)
    for _, item in ipairs(sel_items) do
        reaper.SetMediaItemSelected(item, not init_item or item == init_item)
    end
    reaper.UpdateArrange()
end

local are_notes_hidden = reaper.GetToggleCommandStateEx(32060, 40452) ~= 1
if are_notes_hidden then
    print('Notes are hidden. Zooming to content')
    -- Cmd: Zoom to content
    reaper.MIDIEditor_OnCommand(hwnd, 40466)
else
    if note_hi == -1 then
        print('No note in area/take: Scrolling to center')
        note_lo = 0
        note_hi = 127
    end

    local note_row = math.floor(density_cnt > 0 and density / density_cnt or base_note)
    print('Vertically scrolling to note ' .. note_row)
    print('Scroll lo/hi limit: ' .. note_lo .. '/' .. note_hi)
    local editor_item = reaper.GetMediaItemTake_Item(editor_take)
    scrollToNoteRow(hwnd, editor_item, note_row, note_lo - 1, note_hi + 1)
end

-- Get previous time selection
local sel = getSelection()
setSelection(zoom_start_pos, zoom_end_pos)

-- Cmd: Zoom to project loop selection
reaper.MIDIEditor_OnCommand(hwnd, 40726)

-- Reset previous time selection
local sel_start_pos = sel and sel.start_pos or 0
local sel_end_pos = sel and sel.end_pos or 0
if not debug then
    setSelection(sel_start_pos, sel_end_pos)
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock(undo_name, -1)

local exec_time = math.floor((reaper.time_precise() - start_time) * 1000 + 0.5)
print('\nExecution time: ' .. exec_time .. ' ms')
