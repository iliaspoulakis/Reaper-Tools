--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Open multiple items in the MIDI editor and zoom to all of their content
]]
------------------------------ SETTINGS -----------------------------

-- The smallest number of vertical notes allowed (not exact)
local min_pitch_range = 6
-- Which pitch to zoom in on when the item is empty
local base_note = 60

-- Use the action as a toggle to open and close the editor. The MIDI editor settings
-- will be changed and optimized for multi-editing when the editor opens and changed
-- back to your previous configuration when it closes
-- Recommended: Set the scope of the action shortcut to global when using this
local toggle_editor_and_settings = false

local disable_vertical_zoom = false

---------------------------------------------------------------------

local debug = false
local undo_name = 'Multi edit zoom'
local extname = 'FTC.multi_edit_zoom'
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
    local sel_start_pos, sel_end_pos = getSetLoopTimeRange(false, false, 0, 0, false)
    local is_valid_sel = sel_end_pos > 0 and sel_start_pos ~= sel_end_pos
    if is_valid_sel then
        local sel = {}
        sel.start_pos = sel_start_pos
        sel.end_pos = sel_end_pos
        return sel
    end
end

function getItemVZoomOffset(item)
    local _, chunk = reaper.GetItemStateChunk(item, '', true)
    local cfg_edit_view = chunk:match('CFGEDITVIEW .-\n')
    local pattern = 'CFGEDITVIEW .- .- (.-) '
    if cfg_edit_view then
        local offset = cfg_edit_view:match(pattern)
        return tonumber(offset)
    end
    return -1
end

function zoomIn(hwnd, item, target_vzoom_offs)
    local prev_vzoom_offs
    local prev_vzoom_cnt = 0
    local i = 0
    repeat
        -- Cmd: Zoom in vertically
        reaper.MIDIEditor_OnCommand(hwnd, 40111)
        local vzoom_offs = getItemVZoomOffset(item)
        if prev_vzoom_offs == vzoom_offs then
            prev_vzoom_cnt = prev_vzoom_cnt + 1
        else
            prev_vzoom_cnt = 0
        end
        if prev_vzoom_cnt == 15 then
            break
        end
        prev_vzoom_offs = vzoom_offs
        i = i + 1
    until i == 125 or vzoom_offs >= target_vzoom_offs
    print('Zoom in count: ' .. i)
end

function zoomOut(hwnd, item, target_vzoom_offs)
    local i = 0
    repeat
        -- Cmd: Zoom out vertically
        reaper.MIDIEditor_OnCommand(hwnd, 40112)
        local vzoom_offs = getItemVZoomOffset(item)
        i = i + 1
    until i == 125 or vzoom_offs <= target_vzoom_offs
    print('Zoom out count: ' .. i)
end

function scrollDown(hwnd, item, target_vzoom_offs)
    local prev_vzoom_offs
    local i = 0
    repeat
        -- Cmd: Scroll view down
        reaper.MIDIEditor_OnCommand(hwnd, 40139)
        local vzoom_offs = getItemVZoomOffset(item)
        if prev_vzoom_offs == vzoom_offs then
            break
        end
        prev_vzoom_offs = vzoom_offs
        i = i + 1
    until i == 125 or vzoom_offs >= target_vzoom_offs
    print('Scroll down count: ' .. i)
end

function scrollUp(hwnd, item, target_vzoom_offs)
    local i = 0
    repeat
        -- Cmd: Scroll view up
        reaper.MIDIEditor_OnCommand(hwnd, 40138)
        local vzoom_offs = getItemVZoomOffset(item)
        i = i + 1
    until i == 125 or vzoom_offs <= target_vzoom_offs
    print('Scroll up count: ' .. i)
end

reaper.Undo_BeginBlock()

if toggle_editor_and_settings and not reaper.SNM_GetIntConfigVar then
    reaper.MB('Please install SWS extension', 'Error', 0)
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

local hwnd = reaper.MIDIEditor_GetActive()
local config = tonumber(reaper.GetExtState(extname, 'config'))
if config then
    -- Reset config to original state
    reaper.SNM_SetIntConfigVar('midieditor', config)
    reaper.SetExtState(extname, 'config', '', true)
end
if hwnd and config and toggle_editor_and_settings then
    -- Cmd: Toggle show MIDI editor windows
    reaper.MIDIEditor_OnCommand(hwnd, 40794)
    reaper.Undo_EndBlock(undo_name .. ' (hide editor)', -1)
    return
end

local item_cnt = reaper.CountSelectedMediaItems(0)
if item_cnt == 0 then
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

local note_lo = 128
local note_hi = -1
local zoom_start_pos = math.huge
local zoom_end_pos = 0

-- Analyze all selected items
for i = 0, item_cnt - 1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    local take = reaper.GetActiveTake(item)
    if reaper.ValidatePtr(take, 'MediaItem_Take*') and reaper.TakeIsMIDI(take) then
        -- Get mininum item start positiong and maximum item end position
        local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local item_end_pos = item_start_pos + item_length
        zoom_start_pos = math.min(zoom_start_pos, item_start_pos)
        zoom_end_pos = math.max(zoom_end_pos, item_end_pos)
        -- Get highest and lowest note in take
        local i = 0
        repeat
            local ret, _, _, _, _, _, pitch = reaper.MIDI_GetNote(take, i)
            if ret then
                note_lo = math.min(note_lo, pitch)
                note_hi = math.max(note_hi, pitch)
            end
            i = i + 1
        until not ret
    end
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
new_config = new_config - click_type + 16
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

if toggle_editor_and_settings then
    reaper.SetExtState(extname, 'config', config, true)
else
    -- Reset config to original state
    reaper.SNM_SetIntConfigVar('midieditor', config)
end

local hwnd = reaper.MIDIEditor_GetActive()
local take = reaper.MIDIEditor_GetTake(hwnd)
local is_valid = reaper.ValidatePtr(take, 'MediaItem_Take*')

if not is_valid then
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

local item = reaper.GetMediaItemTake_Item(take)

-- Get previous time selection
local sel = getSelection()
if zoom_start_pos ~= math.huge then
    setSelection(zoom_start_pos, zoom_end_pos)
end
-- Cmd: Zoom to project loop selection
reaper.MIDIEditor_OnCommand(hwnd, 40726)

-- Reset previous time selection
local sel_start_pos = sel and sel.start_pos or 0
local sel_end_pos = sel and sel.end_pos or 0
if not debug then
    setSelection(sel_start_pos, sel_end_pos)
end

local are_notes_hidden = reaper.GetToggleCommandStateEx(32060, 40452) ~= 1
if are_notes_hidden or disable_vertical_zoom then
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

if note_hi == -1 then
    note_lo, note_hi = base_note, base_note
end

local pitch_range = note_hi - note_lo
if pitch_range < min_pitch_range then
    print('Setting minimum pitch range: ' .. min_pitch_range)
    note_hi = math.ceil((note_lo + note_hi + min_pitch_range) / 2)
    note_lo = math.floor((note_lo + note_hi - min_pitch_range) / 2)
    pitch_range = min_pitch_range
end

local center_note = math.floor((note_lo + note_hi) / 2)
local margin = pitch_range > 35 and 2 or 1
local target_vzoom_offs = 127 - center_note - math.ceil(pitch_range / 2) - margin

-- Get previous active note row
local setting = 'active_note_row'
local active_row = reaper.MIDIEditor_GetSetting_int(hwnd, setting)

-- Set active note row to set center of vertical zoom
reaper.MIDIEditor_SetSetting_int(hwnd, setting, center_note)
print('Active note row set to: ' .. center_note)

-- Make sure the active note row is in sight
local vzoom_offs = getItemVZoomOffset(item)
if vzoom_offs < 127 - center_note then
    scrollDown(hwnd, item, 127 - center_note)
end
if vzoom_offs > 127 - center_note then
    scrollUp(hwnd, item, 127 - center_note)
end

-- Note: Zooming out once centers the note row
-- Cmd: Zoom out vertically
reaper.MIDIEditor_OnCommand(hwnd, 40112)

-- Zoom in or out until the target vzoom offset is reached
local vzoom_offs = getItemVZoomOffset(item)
if vzoom_offs > target_vzoom_offs then
    zoomOut(hwnd, item, target_vzoom_offs)
end
if vzoom_offs < target_vzoom_offs then
    zoomIn(hwnd, item, target_vzoom_offs)
end

-- Try zooming out once without changing the basenote (consistency)
-- Cmd: Zoom out vertically
reaper.MIDIEditor_OnCommand(hwnd, 40112)
local offs = getItemVZoomOffset(item)
if offs ~= target_vzoom_offs then
    -- Cmd: Zoom in vertically
    reaper.MIDIEditor_OnCommand(hwnd, 40111)
end

-- Reset previous active note row
if active_row and active_row ~= '' then
    reaper.MIDIEditor_SetSetting_int(hwnd, setting, active_row)
end

reaper.Undo_EndBlock(undo_name, -1)

local exec_time = math.floor((reaper.time_precise() - start_time) * 1000 + 0.5)
print('\nExecution time: ' .. exec_time .. ' ms')
