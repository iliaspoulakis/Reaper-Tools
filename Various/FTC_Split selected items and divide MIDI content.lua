--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.3
  @about Splits selected items and divides their MIDI content
]]
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
local cursor_pos = reaper.GetCursorPosition()
local sel_items = {}
-- Get and unselect all items
for i = reaper.CountSelectedMediaItems(0) - 1, 0, -1 do
    local item = reaper.GetSelectedMediaItem(0, i)
    reaper.SetMediaItemSelected(item, false)
    sel_items[#sel_items + 1] = item
end
for _, item in ipairs(sel_items) do
    local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local end_pos = start_pos + length
    -- Check if selected item is under cursor
    if cursor_pos >= start_pos and cursor_pos <= end_pos then
        -- Create an exact duplicate of item using state chunk
        local track = reaper.GetMediaItem_Track(item)
        local new_item = reaper.CreateNewMIDIItemInProj(track, 0, 1, 0)
        local _, chunk = reaper.GetItemStateChunk(item, '', true)
        reaper.SetItemStateChunk(new_item, chunk, true)

        -- Adjust duplicate position and offsets for split
        reaper.SetMediaItemInfo_Value(item, 'D_LENGTH', cursor_pos - start_pos)
        reaper.SetMediaItemInfo_Value(new_item, 'D_POSITION', cursor_pos)
        reaper.SetMediaItemInfo_Value(new_item, 'D_LENGTH', end_pos - cursor_pos)
        for tk = 0, reaper.GetMediaItemNumTakes(new_item) - 1 do
            local take = reaper.GetMediaItemTake(new_item, tk)
            local take_soffs = reaper.GetMediaItemTakeInfo_Value(take, 'D_STARTOFFS')
            local new_offs = take_soffs - (start_pos - cursor_pos)
            reaper.SetMediaItemTakeInfo_Value(take, 'D_STARTOFFS', new_offs)
        end

        reaper.SetMediaItemSelected(new_item, true)
        local active_take = reaper.GetActiveTake(new_item)
        -- Delete notes in both items, depending on cursor position
        for tk = 0, reaper.GetMediaItemNumTakes(new_item) - 1 do
            local take = reaper.GetMediaItemTake(item, tk)
            local new_take = reaper.GetMediaItemTake(new_item, tk)
            if reaper.TakeIsMIDI(take) then
                reaper.SetActiveTake(new_take)
                -- Item: Remove active take from MIDI source data pool
                reaper.Main_OnCommand(41613, 0)
                local cursor_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, cursor_pos)
                local i = 0
                repeat
                    local ret, _, _, sppq, eppq = reaper.MIDI_GetNote(take, i)
                    if ret then
                        if sppq < cursor_ppq then
                            reaper.MIDI_DeleteNote(new_take, 0)
                        else
                            reaper.MIDI_DeleteNote(take, i)
                            i = i - 1
                        end
                    end
                    i = i + 1
                until not ret
            end
        end
        reaper.SetActiveTake(active_take)
    end
end
-- Reselect all items
for _, item in ipairs(sel_items) do
    reaper.SetMediaItemSelected(item, true)
end
reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock('Split media item (MIDI divide)', -1)
