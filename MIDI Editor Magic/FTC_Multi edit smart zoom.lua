--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.6.0
  @provides [main=main,midi_editor] .
  @about Opens multiple items in the MIDI editor and zooms depending on content
]]

------------------------------- GENERAL SETTINGS --------------------------------

-- Number of (approximate) notes to zoom to
_G.number_of_notes = 20

-- Determines how influential the cursor position is in smart zoom modes
-- No influence: 0,  High influence: >1,  Default: 0.75
_G.smoothing = 0.75

-- Restrict zoom to item bounds
_G.restrict_to_items = true

-- Minimum number of measures to zoom to (0 = disabled)
_G.min_number_of_measures = 0

-- Maximum number of measures to zoom to (0 = disabled)
_G.max_number_of_measures = 0

-- Minimum number of vertical notes when zooming (not exact)
_G.min_vertical_notes = 8

-- Maximum vertical size for notes in pixels (smaller values increase performance)
_G.max_vertical_note_pixels = 32

-- Which note to scroll to when item/visible area contains no notes
_G.base_note = 60

-- Switch note color to track when opening items from tracks with different colors
_G.smart_note_color = true

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

local is_debug = false
local extname = 'FTC.MultiEditSmartZoom'

if not reaper.SNM_GetIntConfigVar then
    reaper.MB('Please install SWS extension', 'Error', 0)
    return
end

local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(3) end

function print(msg)
    if is_debug then
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
    local _, chunk = reaper.GetItemStateChunk(item, '', false)
    local cfg_edit_view = GetItemChunkConfig(item, chunk, 'CFGEDITVIEW')
    return GetConfigVZoom(cfg_edit_view)
end

function GetSourcePPQLength(take)
    local src = reaper.GetMediaItemTake_Source(take)
    local src_length = reaper.GetMediaSourceLength(src)
    local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
    return reaper.MIDI_GetPPQPosFromProjQN(take, start_qn + src_length)
end

function GetVisibleNoteRows(hwnd)
    local mode
    local visible_rows = {}

    if reaper.GetToggleCommandStateEx(32060, 40452) == 1 then
        mode = 'all'
        for n = 0, 127 do visible_rows[n + 1] = n end
    elseif reaper.GetToggleCommandStateEx(32060, 40143) == 1 then
        mode = 'custom'
        local take = reaper.MIDIEditor_GetTake(hwnd)
        local track = take and reaper.GetMediaItemTake_Track(take)

        local note_order
        if track then
            local _, chunk = reaper.GetTrackStateChunk(track, '', false)
            note_order = chunk:match('CUSTOM_NOTE_ORDER (.-)\n')
        end
        if note_order then
            for value in (note_order .. ' '):gmatch('(.-) ') do
                visible_rows[#visible_rows + 1] = tonumber(value)
            end
        else
            for n = 0, 127 do visible_rows[n + 1] = n end
        end
    else
        mode = 'unused'
        local GetSetting = reaper.MIDIEditor_GetSetting_int
        local SetSetting = reaper.MIDIEditor_SetSetting_int
        local setting = 'active_note_row'

        local prev_row = GetSetting(hwnd, setting)

        local highest_row = -1
        for i = 0, 127 do
            SetSetting(hwnd, setting, i)
            local row = GetSetting(hwnd, setting)
            if row > highest_row then
                highest_row = row
                visible_rows[#visible_rows + 1] = row
            end
        end

        SetSetting(hwnd, setting, prev_row)
    end
    return visible_rows, mode
end

function ZoomToPitchRange(hwnd, item, vis_rows, note_lo, note_hi)
    -- Get previous active note row
    local setting = 'active_note_row'
    local active_row = reaper.MIDIEditor_GetSetting_int(hwnd, setting)

    local vis_row_cnt = #vis_rows

    note_lo = math.max(note_lo, 1)
    note_hi = math.min(note_hi, vis_row_cnt)

    local target_row = math.floor((note_lo + note_hi) / 2)
    local curr_row = GetItemVZoom(item)
    if not curr_row or curr_row == 0 then return end
    curr_row = curr_row + vis_row_cnt - 127

    local target_range = math.ceil((note_hi - note_lo) / 2)

    -- Set active note row to set center of vertical zoom
    local pitch = vis_rows[curr_row]
    reaper.MIDIEditor_SetSetting_int(hwnd, setting, pitch)

    -- Note: Zooming when row is visible centers the note row
    -- Cmd: Zoom out vertically
    reaper.MIDIEditor_OnCommand(hwnd, 40112)

    -- Debugging output
    local row_string = ' -> ' .. curr_row .. ':' .. pitch
    local zoom_string = ' -> out'

    local i = 0
    repeat
        local row, size = GetItemVZoom(item)
        row = row + vis_row_cnt - 127
        local pitch_range = math.min(-2, curr_row - row + 1) * -1

        if curr_row > target_row then
            curr_row = math.max(target_row, curr_row - pitch_range)
        else
            curr_row = math.min(target_row, curr_row + pitch_range)
        end
        -- Set active note row to set center of vertical zoom
        pitch = vis_rows[curr_row]
        reaper.MIDIEditor_SetSetting_int(hwnd, setting, pitch)
        row_string = row_string .. ' -> ' .. row .. ':' .. pitch

        if pitch_range > target_range and size < _G.max_vertical_note_pixels then
            -- Cmd: Zoom in vertically
            reaper.MIDIEditor_OnCommand(hwnd, 40111)
            zoom_string = zoom_string .. ' -> in'
        else
            -- Cmd: Zoom out vertically
            reaper.MIDIEditor_OnCommand(hwnd, 40112)
            zoom_string = zoom_string .. ' -> out'
        end
        i = i + 1
    until i == 100 or curr_row == target_row

    zoom_string = zoom_string .. ' |'

    repeat
        local row, size = GetItemVZoom(item)
        row = row + vis_row_cnt - 127
        local pitch_range = math.abs(curr_row - row)
        if size > _G.max_vertical_note_pixels then
            print('Reached max zoom size!')
            break
        end
        -- Cmd: Zoom in vertically
        reaper.MIDIEditor_OnCommand(hwnd, 40111)
        zoom_string = zoom_string .. ' -> in'
        i = i + 1
    until i == 100 or pitch_range < target_range

    repeat
        local row, size = GetItemVZoom(item)
        row = row + vis_row_cnt - 127
        local pitch_range = math.abs(curr_row - row)
        if size == 4 then
            print('Reached min zoom size!')
            break
        end
        -- Cmd: Zoom out vertically
        reaper.MIDIEditor_OnCommand(hwnd, 40112)
        zoom_string = zoom_string .. ' -> out'
        i = i + 1
    until i == 100 or pitch_range >= target_range and size <= _G.max_vertical_note_pixels

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

function LoadCustomActions(script_cmd_name)
    local sep = package.config:sub(1, 1)
    local kb_ini_path = reaper.GetResourcePath() .. sep .. 'reaper-kb.ini'
    local kb_ini_file = io.open(kb_ini_path, 'r')

    local custom_actions = {}
    if kb_ini_file then
        for line in kb_ini_file:lines() do
            if line:match('^ACT') and line:match(script_cmd_name) then
                local custom_action_id = '_' .. line:match('"(.-)"')
                custom_actions[custom_action_id] = true
            end
        end
        kb_ini_file:close()
    end
    return custom_actions
end

local custom_actions
function IsScriptInCustomAction(action_cmd_name, script_cmd_name)
    local is_in_custom_action = false
    -- Check if modifier is set to a custom action
    if action_cmd_name:match('^_') and not action_cmd_name:match('^_RS') then
        -- Check if custom action includes this script
        -- Note: Avoid always loading custom actions (parse kb.ini) by caching
        local state = tonumber(reaper.GetExtState(extname, action_cmd_name))
        if state then
            is_in_custom_action = state == 1
        else
            custom_actions = custom_actions or LoadCustomActions(script_cmd_name)
            is_in_custom_action = custom_actions[action_cmd_name] or false
            state = is_in_custom_action and 1 or 0
            reaper.SetExtState(extname, action_cmd_name, state, 0)
        end
    end
    return is_in_custom_action
end

-- Avoid creating undo points
reaper.defer(function() end)

local time = reaper.time_precise()
local prev_time = tonumber(reaper.GetExtState(extname, 'timestamp')) or 0
reaper.SetExtState(extname, 'timestamp', time, false)

local mouse_item
local _, _, sec, cmd, rel, res, val, context_str = reaper.get_action_context()
if sec == 0 and context_str:match('custom') then rel, res, val = -1, -1, -1 end

local x, y = reaper.GetMousePosition()
local _, mouse_context = reaper.GetThingFromPoint(x, y)

-- Check if action is executed through item context mouse modifier
if sec == 0 and mouse_context == 'arrange' and rel + res + val == -3 then
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

        local is_in_custom_sc_action = IsScriptInCustomAction(sc_mod, cmd_name)
        local is_in_custom_dc_action = IsScriptInCustomAction(dc_mod, cmd_name)

        if dc_mod == cmd_name or is_in_custom_dc_action then
            is_double_click_mod = true
            if sc_mod ~= cmd_name and not is_in_custom_sc_action then
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
        if sc_mod == cmd_name or is_in_custom_sc_action then
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

        if src_type == 'CLICK' then
            -- Item properties: Show media item source properties
            reaper.Main_OnCommand(40011, 0)
            return
        end

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

local sel_items = {}

-- Get selected items
for i = 0, sel_item_cnt - 1 do
    sel_items[#sel_items + 1] = reaper.GetSelectedMediaItem(0, i)
end

local midi_takes = {}

-- Get selected MIDI takes
for i = 1, #sel_items do
    local item = sel_items[i]
    local take = reaper.GetActiveTake(item)
    if reaper.ValidatePtr(take, 'MediaItem_Take*') and reaper.TakeIsMIDI(take) then
        midi_takes[#midi_takes + 1] = take
    end
end

-- No MIDI items found
if #midi_takes == 0 then return end

reaper.PreventUIRefresh(1)

local config
local visibility

if #midi_takes > 1 then
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

    if editability == 0 and other_tracks_editable == 0 then
        -- Respect preference to avoid multi-track editing when editability is
        -- linked.
        new_config = new_config - 4096
    end
    reaper.SNM_SetIntConfigVar('midieditor', new_config)

    -- Select all tracks of items if editor follows track selection and selection
    -- is linked to editability
    local editor_follows_track_sel = config & 8192 == 8192
    if editor_follows_track_sel and editability == 0 then
        for _, take in ipairs(midi_takes) do
            local track = reaper.GetMediaItemTake_Track(take)
            reaper.SetMediaTrackInfo_Value(track, 'I_SELECTED', 1)
        end
    end
end

-- Note: Clearing editor is needed in edge case where track only has one midi item
local prev_hwnd = reaper.MIDIEditor_GetActive()
if prev_hwnd and #midi_takes == 1 then
    local prev_editor_take = reaper.MIDIEditor_GetTake(prev_hwnd)
    if prev_editor_take == midi_takes[1] then
        -- Contents: Activate next MIDI media item on this track, clearing the
        -- editor first
        reaper.MIDIEditor_OnCommand(prev_hwnd, 40798)
    end
end

-- Cmd: Open in built-in MIDI editor
reaper.Main_OnCommand(40153, 0)

local hwnd = reaper.MIDIEditor_GetActive()
local editor_take = reaper.MIDIEditor_GetTake(hwnd)

if not reaper.ValidatePtr(editor_take, 'MediaItem_Take*') then
    -- Reset config to original state
    if config then reaper.SNM_SetIntConfigVar('midieditor', config) end
    reaper.PreventUIRefresh(-1)
    return
end

if #midi_takes > 1 then
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

    if _G.smart_note_color then
        local has_multiple_track_colors = false
        local prev_color
        for _, take in ipairs(midi_takes) do
            local track = reaper.GetMediaItemTake_Track(take)
            local color = reaper.GetMediaTrackInfo_Value(track, 'I_CUSTOMCOLOR')
            if prev_color and color ~= prev_color then
                has_multiple_track_colors = true
                break
            end
            prev_color = color
        end

        if has_multiple_track_colors then
            -- Color notes/CC by track custom color
            reaper.MIDIEditor_OnCommand(hwnd, 40768)
        else
            -- If note color is set to track, switch to velocity
            if reaper.GetToggleCommandStateEx(32060, 40768) == 1 then
                -- Color notes by velocity
                reaper.MIDIEditor_OnCommand(hwnd, 40738)
            end
        end
    end
else
    if _G.smart_note_color then
        -- If note color is set to track, switch to velocity
        if reaper.GetToggleCommandStateEx(32060, 40768) == 1 then
            -- Color notes by velocity
            reaper.MIDIEditor_OnCommand(hwnd, 40738)
        end
    end
end

-- Restore previous item selection
local new_sel_item_cnt = reaper.CountSelectedMediaItems(0)
if new_sel_item_cnt ~= sel_item_cnt or mouse_item then
    for i = new_sel_item_cnt - 1, 0, -1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        reaper.SetMediaItemSelected(item, false)
    end
    for _, item in ipairs(sel_items) do
        reaper.SetMediaItemSelected(item, not mouse_item or item == mouse_item)
        reaper.UpdateItemInProject(item)
    end
end

local vis_rows = GetVisibleNoteRows(hwnd)
local vis_row_map = {}
for i = 1, #vis_rows do vis_row_map[vis_rows[i]] = i end

local item_zoom_start_pos = math.huge
local item_zoom_end_pos = 0

local note_lo = 128
local note_hi = -1

local note_length_sum = 0
local note_weight_sum = 0
local min_note_distance = math.huge

local num_notes = _G.number_of_notes
local smoothing = _G.smoothing

local cursor_pos = reaper.GetCursorPosition()
local analysis_start_time = reaper.time_precise()
local is_timebase_source = reaper.GetToggleCommandStateEx(32060, 40470) == 1

if is_timebase_source and #midi_takes > 0 then
    -- Switch timebase to "project" to allow multiple open items
    reaper.MIDIEditor_OnCommand(hwnd, 40459)
    is_timebase_source = false
end

local GetNote = reaper.MIDI_GetNote
local GetPPQFromTime = reaper.MIDI_GetPPQPosFromProjTime
local GetTimeFromPPQ = reaper.MIDI_GetProjTimeFromPPQPos
local GetItemInfo = reaper.GetMediaItemInfo_Value
local GetTrackMIDINoteRange = reaper.GetTrackMIDINoteRange

-- Analyze all midi takes
for i = 1, #midi_takes do
    local take = midi_takes[i]
    local item = reaper.GetMediaItemTake_Item(take)

    -- Get minimum item start position and maximum item end position
    local length = GetItemInfo(item, 'D_LENGTH')
    local start_pos = GetItemInfo(item, 'D_POSITION')
    local end_pos = start_pos + length
    if start_pos < item_zoom_start_pos then item_zoom_start_pos = start_pos end
    if end_pos > item_zoom_end_pos then item_zoom_end_pos = end_pos end

    if reaper.time_precise() - analysis_start_time > 0.15 then
        -- If analysis takes too long, start using track note range
        local track = reaper.GetMediaItem_Track(item)
        local range_note_lo, range_note_hi = GetTrackMIDINoteRange(0, track)
        if range_note_lo + range_note_hi > 0 then
            if range_note_lo < note_lo then note_lo = range_note_lo end
            if range_note_hi > note_hi then note_hi = range_note_hi end
        end
    else
        -- Get note center
        local start_ppq = GetPPQFromTime(take, start_pos)
        local end_ppq = GetPPQFromTime(take, end_pos)

        if not is_timebase_source and GetItemInfo(item, 'B_LOOPSRC') == 1 then
            local src_ppq_length = GetSourcePPQLength(take)
            if end_ppq - start_ppq >= src_ppq_length then
                start_ppq = 0
                end_ppq = src_ppq_length
            else
                start_ppq = start_ppq % src_ppq_length
                end_ppq = end_ppq % src_ppq_length
            end
        end

        local ppq_pos = GetPPQFromTime(take, cursor_pos)

        local prev_eppq
        local gap_length = 0

        local _, total_note_cnt = reaper.MIDI_CountEvts(take)
        for n = 0, total_note_cnt - 1 do
            local _, _, _, sppq, eppq, _, pitch = GetNote(take, n)
            -- Check if note is within bounds of the item
            local is_in_bounds = true
            if not is_timebase_source then
                if end_ppq < start_ppq then
                    is_in_bounds = eppq > start_ppq or sppq < end_ppq
                else
                    is_in_bounds = eppq > start_ppq and sppq < end_ppq
                end
            end
            if is_in_bounds then
                pitch = vis_row_map[pitch]
                if pitch then
                    if pitch < note_lo then note_lo = pitch end
                    if pitch > note_hi then note_hi = pitch end

                    local note_length = eppq - sppq
                    -- Add gap between notes to note length
                    if prev_eppq and sppq >= prev_eppq then
                        -- Limit gap length to something reasonable
                        local min_gap_length = note_length * num_notes
                        gap_length = sppq - prev_eppq
                        if gap_length > min_gap_length then
                            gap_length = min_gap_length
                        end
                    end
                    if not prev_eppq or eppq > prev_eppq then
                        prev_eppq = eppq
                    end
                    local note_center_ppq = sppq + note_length / 2
                    local note_distance = note_center_ppq - ppq_pos
                    if note_distance < 0 then note_distance = -note_distance end
                    -- Avoid dividing by zero (and attributing very high weights)
                    if note_length > note_distance then
                        note_distance = note_length
                    end
                    if note_distance < min_note_distance then
                        min_note_distance = note_distance
                    end
                    local note_weight = 1 / note_distance ^ smoothing
                    local gap_note_length = note_length + gap_length
                    local weighted_gap_length = note_weight * gap_note_length
                    note_length_sum = note_length_sum + weighted_gap_length
                    note_weight_sum = note_weight_sum + note_weight
                end
            end
        end
    end
end

if note_hi == -1 then
    print('No note in area/take: Setting base note')
    note_lo = _G.base_note
    note_hi = _G.base_note
end

if note_hi - note_lo < _G.min_vertical_notes then
    print('Using minimum pitch range')
    note_hi = math.ceil((note_lo + note_hi + _G.min_vertical_notes) / 2)
    note_lo = math.floor((note_lo + note_hi - _G.min_vertical_notes) / 2)
    note_lo = note_hi < 127 and note_lo or 127
    note_hi = note_hi < 127 and note_hi or 127 - _G.min_vertical_notes
end

print('Vertically zooming to notes ' .. note_lo .. ' - ' .. note_hi)

local editor_item = reaper.GetMediaItemTake_Item(editor_take)
ZoomToPitchRange(hwnd, editor_item, vis_rows,
    note_lo - 1, note_hi + 1)

local m = 0.001
local TimeToBeats = reaper.TimeMap2_timeToBeats
local BeatsToTime = reaper.TimeMap2_beatsToTime

local item_start_measure = select(2, TimeToBeats(0, item_zoom_start_pos + m))
local item_end_measure = select(2, TimeToBeats(0, item_zoom_end_pos - m)) + 1
local zoom_measures = item_end_measure - item_start_measure

if note_weight_sum > 0 then
    local avg_note_length = note_length_sum / note_weight_sum
    local zoom_ppq_length = avg_note_length * num_notes
    print('Avg note length: ' .. math.floor(avg_note_length))

    local cursor_ppq_pos = GetPPQFromTime(editor_take, cursor_pos)
    local offs = zoom_ppq_length / 2
    local start_pos = GetTimeFromPPQ(editor_take, cursor_ppq_pos - offs)
    local end_pos = GetTimeFromPPQ(editor_take, cursor_ppq_pos + offs)

    local start_beats, start_measures, start_cml = TimeToBeats(0, start_pos)
    local end_beats, end_measures, end_cml = TimeToBeats(0, end_pos)

    local start_measure = start_measures + start_beats / start_cml
    local end_measure = end_measures + end_beats / end_cml

    local measures = math.max(1, math.floor(end_measure - start_measure + 0.5))

    -- If item itelf is just a little bit larger, zoom to item
    if math.ceil(measures * 1.25) < zoom_measures or
        not _G.restrict_to_items and measures > zoom_measures then
        zoom_measures = measures
    end
end

if _G.min_number_of_measures > 0 and zoom_measures < _G.min_number_of_measures then
    zoom_measures = _G.min_number_of_measures
end

if _G.max_number_of_measures > 0 and zoom_measures > _G.max_number_of_measures then
    zoom_measures = _G.max_number_of_measures
end

local _, cursor_measure = TimeToBeats(0, cursor_pos)
local left_adjust = zoom_measures > 2 and 0.5 or 0
local start_offs = (zoom_measures - left_adjust) // 2

local start_measure = cursor_measure - start_offs
local end_measure = start_measure + zoom_measures

if _G.restrict_to_items and end_measure > item_end_measure then
    start_measure = item_end_measure - zoom_measures
    end_measure = item_end_measure
end

if _G.restrict_to_items and start_measure < item_start_measure then
    start_measure = item_start_measure
    end_measure = item_start_measure + zoom_measures
end

local zoom_start_pos = BeatsToTime(0, 0, start_measure)
local zoom_end_pos = BeatsToTime(0, 0, end_measure)

-- Get previous time selection
local sel = GetSelection()
SetSelection(zoom_start_pos, zoom_end_pos)

-- Cmd: Zoom to project loop selection
reaper.MIDIEditor_OnCommand(hwnd, 40726)

-- Reset previous time selection
local sel_start_pos = sel and sel.start_pos or 0
local sel_end_pos = sel and sel.end_pos or 0
if not is_debug then
    SetSelection(sel_start_pos, sel_end_pos)
end

reaper.PreventUIRefresh(-1)

local exec_time = math.floor((reaper.time_precise() - time) * 1000 + 0.5)
print('\nExecution time: ' .. exec_time .. ' ms')
