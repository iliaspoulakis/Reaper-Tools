--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.4.0
  @provides [main=main,midi_editor] .
  @about Opens multiple items in the MIDI editor and scrolls to the center of their content
  @changelog
    - Avoid reopening editor when all selected items are already open and editable
    - Do not change user MIDI editor settings when opening single MIDI items
    - Add support for active MIDI item follows "Track" selection in arrange view
    - Change user MIDI editor settings in certain situations (show warning)
]]
------------------------------- GENERAL SETTINGS --------------------------------

-- When to zoom to items horizontally (inside MIDI editor)
-- 0: Never
-- 1: Always
-- 2: Only when multiple MIDI items are selected
_G.hzoom_mode = 1

-- Which note to scroll to when item/visible area contains no notes
_G.base_note = 60

---------------------------- MOUSE MODIFIER SETTINGS ----------------------------

-- Snap cursor to grid
_G.snap_edit_cursor = true

-- Keep all items selected after click (zoom will go to all items)
_G.keep_items_selected = true

-- Zoom to items instead of opening media item properties
_G.zoom_to_audio_items = false

--------------------------- KEYBOARD SHORTCUT SETTINGS -------------------------

-- Script closes MIDI editor when already open (toggle)
_G.toggle_editor = false

--------------------------------------------------------------------------------

local debug = false
local extname = 'FTC.MultiEditScroll'

if not reaper.SNM_GetIntConfigVar then
    reaper.MB('Please install SWS extension', 'Error', 0)
    return
end

local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(3) end

function print(msg)
    if debug then
        reaper.ShowConsoleMsg(tostring(msg) .. '\n')
    end
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

function GetConfigVZoom(cfg_edit_view)
    local pattern = 'CFGEDITVIEW .- .- (.-) (.-) '
    if cfg_edit_view then
        local offset, size = cfg_edit_view:match(pattern)
        return 127 - tonumber(offset), tonumber(size)
    end
    return -1, -1
end

function GetItemVZoom(item)
    local _, chunk = reaper.GetItemStateChunk(item, '', true)
    local cfg_edit_view = GetItemChunkConfig(item, chunk, 'CFGEDITVIEW')
    return GetConfigVZoom(cfg_edit_view)
end

function GetSourcePPQLength(take)
    local src = reaper.GetMediaItemTake_Source(take)
    local src_length = reaper.GetMediaSourceLength(src)
    local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
    return reaper.MIDI_GetPPQPosFromProjQN(take, start_qn + src_length)
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

function SaveItemSelection()
    local sel_state = ''
    for i = 0, reaper.CountSelectedMediaItems(0) - 1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        local track = reaper.GetMediaItem_Track(item)
        local item_num = reaper.GetMediaItemInfo_Value(item, 'IP_ITEMNUMBER')
        local track_num = reaper.GetMediaTrackInfo_Value(track, 'IP_TRACKNUMBER')
        item_num = math.floor(item_num)
        track_num = math.floor(track_num)
        sel_state = sel_state .. track_num .. '_' .. item_num .. ';'
    end
    reaper.SetExtState(extname, 'sel_state', sel_state, false)
end

function RestoreItemSelection()
    local sel_state = reaper.GetExtState(extname, 'sel_state')
    reaper.SetExtState(extname, 'sel_state', '', false)
    for s in sel_state:gmatch('(.-);') do
        local track_num = s:match('(%d+)_')
        local item_num = s:match('_(%d+)')
        local track = reaper.GetTrack(0, track_num - 1)
        local item = reaper.GetTrackMediaItem(track, item_num)
        if reaper.ValidatePtr(item, 'MediaItem*') then
            reaper.SetMediaItemSelected(item, true)
            reaper.UpdateItemInProject(item)
        end
    end
end

-- Avoid creating undo points
reaper.defer(function() end)

local time = reaper.time_precise()
local prev_time = tonumber(reaper.GetExtState(extname, 'timestamp')) or 0
reaper.SetExtState(extname, 'timestamp', time, false)

local mouse_item
local _, _, _, cmd, rel, res, val = reaper.get_action_context()

local x, y = reaper.GetMousePosition()
local _, mouse_context = reaper.GetThingFromPoint(x, y)

-- Check if action is executed through item context mouse modifier
if mouse_context == 'arrange' and rel == -1 and res == -1 and val == -1 then
    -- Get item under mouse
    mouse_item = reaper.GetItemFromPoint(x, y, true)
    if not reaper.ValidatePtr(mouse_item, 'MediaItem*') then
        return
    end

    local cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd)
    local is_double_click_mod = false
    local is_single_click_mod = false

    for i = 0, 15 do
        local dc_mod = reaper.GetMouseModifier('MM_CTX_ITEM_DBLCLK', i, '')
        local sc_mod = reaper.GetMouseModifier('MM_CTX_ITEM_CLK', i, '')
        if dc_mod == cmd_name then
            is_double_click_mod = true
            if sc_mod ~= cmd_name then
                local msg =
                'For the script to function as a double click modifier it also \z
                has to be set as a single click modifier for the same context.\z
                \n\nSet script as single click modifier?'
                local ret = reaper.MB(msg, 'FTC Multi edit', 1)
                if ret == 1 then
                    -- Set single click mouse modifier to script
                    reaper.SetMouseModifier('MM_CTX_ITEM_CLK', i, cmd)
                end
                return
            end
            break
        end
        if sc_mod == cmd_name then
            is_single_click_mod = true
            break
        end
    end

    local is_linux = reaper.GetOS():match('Other')

    -- Check if item changed (avoid wrong double clicks on different items)
    local GetSetItemInfo = reaper.GetSetMediaItemInfo_String
    local _, item_guid = GetSetItemInfo(mouse_item, 'GUID', '', false)
    local prev_item_guid = reaper.GetExtState(extname, 'item_guid')
    reaper.SetExtState(extname, 'item_guid', item_guid, false)

    local has_item_changed = item_guid ~= prev_item_guid

    -- Check if track changed
    local track = reaper.GetMediaItem_Track(mouse_item)
    local GetSetTrackInfo = reaper.GetSetMediaTrackInfo_String
    local _, track_guid = GetSetTrackInfo(track, 'GUID', '', false)
    local prev_track_guid = reaper.GetExtState(extname, 'track_guid')
    reaper.SetExtState(extname, 'track_guid', track_guid, false)

    local has_track_changed = track_guid ~= prev_track_guid

    local function CreateUserUndoPoints(sel_item_cnt)
        -- Create undo points according to user preferences
        local _, undo_mask = reaper.get_config_var_string('undomask')
        undo_mask = tonumber(undo_mask)

        -- Note: Linux creates it's own  undo points
        if undo_mask and not is_linux then
            if (sel_item_cnt > 1 or has_item_changed) and undo_mask & 1 == 1 then
                reaper.Undo_BeginBlock()
                reaper.Undo_EndBlock('Change media item selection', 4)
                return
            end
            if has_track_changed and undo_mask & 16 == 16 then
                reaper.Undo_BeginBlock()
                reaper.Undo_EndBlock('Change track selection', 1)
                return
            end
        end
    end

    if is_double_click_mod then
        -- Single click mode
        if has_item_changed or time - prev_time > 0.3 then
            reaper.SetExtState(extname, 'mode', 'sc', false)

            if not _G.snap_edit_cursor then
                -- View: Move edit cursor to mouse cursor (no snapping)
                reaper.Main_OnCommand(40514, 0)
            end
            SaveItemSelection()

            local defer_cnt = 0

            local function DelaySelectionChange()
                -- Delay selection change for a few defer cycles
                if defer_cnt < 2 then
                    defer_cnt = defer_cnt + 1
                    reaper.defer(DelaySelectionChange)
                    return
                end
                -- Do not change selection when double click detected
                local is_dc = reaper.GetExtState(extname, 'mode') == 'dc'
                if is_dc and _G.keep_items_selected then
                    has_item_changed = false
                    CreateUserUndoPoints(0)
                    return
                end

                -- Keep only mouse item selected
                local sel_item_cnt = reaper.CountSelectedMediaItems(0)
                for i = sel_item_cnt - 1, 0, -1 do
                    local item = reaper.GetSelectedMediaItem(0, i)
                    reaper.SetMediaItemSelected(item, item == mouse_item)
                end

                -- Options: Toggle item grouping and track media/razor edit grouping
                if reaper.GetToggleCommandState(1156) == 1 then
                    -- Options: Selecting one grouped item selects group
                    if reaper.GetToggleCommandState(41156) == 1 then
                        -- Item grouping: Select all items in groups
                        reaper.Main_OnCommand(40034, 0)
                    end
                end

                CreateUserUndoPoints(sel_item_cnt)
                reaper.defer(reaper.UpdateArrange)
            end

            if reaper.CountSelectedMediaItems(0) == 1 then
                CreateUserUndoPoints(0)
            else
                reaper.defer(DelaySelectionChange)
            end
            return
        end

        -- Exit mode (avoid double single click script runs)
        if reaper.GetExtState(extname, 'mode') == 'sc' then
            reaper.SetExtState(extname, 'mode', 'dc', false)
            if is_linux then return end
        end

        -- Double click mode
        local take = reaper.GetActiveTake(mouse_item)

        -- Handle empty takes
        if not reaper.ValidatePtr(take, 'MediaItem_Take*') then
            if reaper.GetMediaItemNumTakes(mouse_item) == 0 then
                -- Item: Show notes for items...
                reaper.Main_OnCommand(40850, 0)
            end
            return
        end

        local src = reaper.GetMediaItemTake_Source(take)
        local src_type = reaper.GetMediaSourceType(src, '')

        -- Open video window if not already open (else item properties)
        if src_type == 'VIDEO' and reaper.GetToggleCommandState(50125) == 0 then
            -- Video: Show/hide video window
            reaper.Main_OnCommand(50125, 0)
            return
        end

        if src_type == 'RPP_PROJECT' then
            -- Cmd: Open associated project in new tab
            reaper.Main_OnCommand(41816, 0)
            return
        end

        if not reaper.TakeIsMIDI(take) then
            if _G.zoom_to_audio_items then
                if _G.keep_items_selected then RestoreItemSelection() end
                reaper.Main_OnCommand(41622, 0)
            else
                -- Cmd: Show media item/take properties
                reaper.Main_OnCommand(40009, 0)
            end
            return
        end
    elseif is_single_click_mod then
        if not _G.snap_edit_cursor then
            -- View: Move edit cursor to mouse cursor (no snapping)
            reaper.Main_OnCommand(40514, 0)
        end
        local take = reaper.GetActiveTake(mouse_item)
        local is_valid = reaper.ValidatePtr(take, 'MediaItem_Take*')

        -- Options: Toggle item grouping and track media/razor edit grouping
        if reaper.GetToggleCommandState(1156) == 1 then
            -- Options: Selecting one grouped item selects group
            if reaper.GetToggleCommandState(41156) == 1 then
                -- Item grouping: Select all items in groups
                reaper.Main_OnCommand(40034, 0)
            end
        end

        if not is_valid or not reaper.TakeIsMIDI(take) then
            -- Keep only mouse item selected
            local sel_item_cnt = reaper.CountSelectedMediaItems(0)
            for i = sel_item_cnt - 1, 0, -1 do
                local item = reaper.GetSelectedMediaItem(0, i)
                reaper.SetMediaItemSelected(item, item == mouse_item)
                reaper.UpdateItemInProject(item)
            end

            -- Options: Selecting one grouped item selects group
            if reaper.GetToggleCommandState(41156) == 1 then
                -- Item grouping: Select all items in groups
                reaper.Main_OnCommand(40034, 0)
            end

            CreateUserUndoPoints(sel_item_cnt)
            return
        end
    end
elseif _G.toggle_editor then
    local hwnd = reaper.MIDIEditor_GetActive()
    if hwnd then
        -- View: Toggle show MIDI editor windows
        reaper.Main_OnCommand(40716, 0)
        return
    end
end

RestoreItemSelection()

local sel_item_cnt = reaper.CountSelectedMediaItems(0)
if sel_item_cnt == 0 then
    return
end

reaper.PreventUIRefresh(1)

local sel_items = {}

-- Get selected items
for i = 0, sel_item_cnt - 1 do
    sel_items[#sel_items + 1] = reaper.GetSelectedMediaItem(0, i)
end

local midi_item_cnt = 0

local zoom_start_pos = math.huge
local zoom_end_pos = 0

local note_lo = 128
local note_hi = -1

local density = 0
local density_cnt = 0

local midi_takes = {}

-- Analyze all selected items
for _, item in ipairs(sel_items) do
    local take = reaper.GetActiveTake(item)
    if reaper.ValidatePtr(take, 'MediaItem_Take*') and reaper.TakeIsMIDI(take) then
        midi_item_cnt = midi_item_cnt + 1
        midi_takes[take] = true
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
        local i = 0
        repeat
            local ret, _, _, sppq, eppq, _, pitch = reaper.MIDI_GetNote(take, i)
            if ret and IsNoteVisible(sppq, eppq) then
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
if midi_item_cnt == 0 then
    reaper.PreventUIRefresh(-1)
    return
end

local prev_hwnd = reaper.MIDIEditor_GetActive()

local config
local visibility

if prev_hwnd or midi_item_cnt > 1 then
    -- Change MIDI editor settings for multi-edit
    config = reaper.SNM_GetIntConfigVar('midieditor', 0)

    local click_type = config & 20
    local other_tracks_editable = config & 256
    local editability = config & 512
    visibility = config & 1024
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

    if not prev_hwnd and editability == 0 and other_tracks_editable == 0 then
        local unique_track_cnt = 0
        local unique_tracks = {}
        for take in pairs(midi_takes) do
            local track = reaper.GetMediaItemTake_Track(take)
            if not unique_tracks[track] then
                unique_tracks[track] = true
                unique_track_cnt = unique_track_cnt + 1
                if unique_track_cnt > 1 then break end
            end
        end

        if unique_track_cnt > 1 then
            local msg = 'Your current MIDI editor settings configuration is \z
            incompatible with multi-track editing.\n\nThe following setting has \z
            been turned off:\n"Avoid automatically setting MIDI items from \z
            other tracks editable"'
            reaper.MB(msg, 'Warning', 0)
            config = config + 256
        end
    end

    -- Select all tracks of items if editor follows track selection and selection
    -- is linked to editability
    local editor_follows_track_sel = config & 8192 == 8192
    if editor_follows_track_sel and editability == 0 then
        for take in pairs(midi_takes) do
            local track = reaper.GetMediaItemTake_Track(take)
            reaper.SetMediaTrackInfo_Value(track, 'I_SELECTED', 1)
        end
    end
end

-- If all editable takes are already editable, avoid re-opening the editor
local requires_new_editor = true
if prev_hwnd then
    local i = 0
    repeat
        local take = reaper.MIDIEditor_EnumTakes(prev_hwnd, i, true)
        if take and not midi_takes[take] then break end
        i = i + 1
    until not take

    if midi_item_cnt == i - 1 then requires_new_editor = false end
end

if requires_new_editor then
    -- Cmd: Open in built-in MIDI editor
    reaper.Main_OnCommand(40153, 0)
end

local hwnd = reaper.MIDIEditor_GetActive()
local editor_take = reaper.MIDIEditor_GetTake(hwnd)

if not reaper.ValidatePtr(editor_take, 'MediaItem_Take*') then
    -- Reset config to original state
    reaper.SNM_SetIntConfigVar('midieditor', config)
    reaper.PreventUIRefresh(-1)
    return
end

if prev_hwnd or midi_item_cnt > 1 then
    -- Note: Setting 'Selection is linked to visibility' can change item
    -- selection to  all items that are open (visible) in editor
    if reaper.CountSelectedMediaItems(0) ~= sel_item_cnt then
        -- Contents: Activate next MIDI media item on this track, clearing the
        -- editor first
        reaper.MIDIEditor_OnCommand(hwnd, 40798)
        -- We use this for clearing, if active item changes this needs to be
        -- reverted
        if reaper.MIDIEditor_GetTake(hwnd) ~= editor_take then
            -- Contents: Activate previous MIDI media item on this track, clear...
            reaper.MIDIEditor_OnCommand(hwnd, 40797)
        end
    end

    -- Reset config to original state
    reaper.SNM_SetIntConfigVar('midieditor', config)

    if visibility == 0 or _G.keep_items_selected then
        mouse_item = nil
    end
end

-- Restore previous item selection
if reaper.CountSelectedMediaItems(0) ~= sel_item_cnt or mouse_item then
    reaper.SelectAllMediaItems(0, false)
    for _, item in ipairs(sel_items) do
        reaper.SetMediaItemSelected(item, not mouse_item or item == mouse_item)
        reaper.UpdateItemInProject(item)
    end
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
    local note_row = _G.base_note
    if density_cnt > 0 then
        note_row = density // density_cnt
    end
    print('Vertically scrolling to note ' .. note_row)
    print('Scroll lo/hi limit: ' .. note_lo .. '/' .. note_hi)
    local editor_item = reaper.GetMediaItemTake_Item(editor_take)
    ScrollToNoteRow(hwnd, editor_item, note_row, note_lo - 1, note_hi + 1)
end

if _G.hzoom_mode == 1 or _G.hzoom_mode == 2 and midi_item_cnt > 1 then
    -- Get previous time selection
    local sel = GetSelection()
    SetSelection(zoom_start_pos, zoom_end_pos)

    -- Cmd: Zoom to project loop selection
    reaper.MIDIEditor_OnCommand(hwnd, 40726)

    -- Reset previous time selection
    local sel_start_pos = sel and sel.start_pos or 0
    local sel_end_pos = sel and sel.end_pos or 0
    if not debug then
        SetSelection(sel_start_pos, sel_end_pos)
    end
else
    reaper.MIDIEditor_OnCommand(hwnd, 40151)
end

reaper.PreventUIRefresh(-1)

local exec_time = math.floor((reaper.time_precise() - time) * 1000 + 0.5)
print('\nExecution time: ' .. exec_time .. ' ms')
