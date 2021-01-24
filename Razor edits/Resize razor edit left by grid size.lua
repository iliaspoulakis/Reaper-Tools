--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about A set of scripts for quick razor editing using arrow keys
]]
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local _, grid_div = reaper.GetSetProjectGrid(0, false)
-- Shrink razor edit to the left by one grid unit
local has_razor_edit = false
local GetSetTrackInfo = reaper.GetSetMediaTrackInfo_String
for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    local _, razor_edit = GetSetTrackInfo(track, 'P_RAZOREDITS', '', false)
    if razor_edit ~= '' then
        if not has_razor_edit then
            has_razor_edit = true
            reaper.SetOnlyTrackSelected(track)
            local start_pos = tonumber(razor_edit:match('[^%s]+'))
            reaper.SetEditCurPos2(0, start_pos, true, false)
        end
        local new_razor_edit = ''
        for edit in razor_edit:gmatch('.- .- ".-"%s*') do
            local start_pos = tonumber(edit:match('.- '))
            local end_pos = tonumber(edit:match(' .- '))
            local _, _, _, end_beat = reaper.TimeMap2_timeToBeats(0, end_pos)
            local _, end_denom = reaper.TimeMap_GetTimeSigAtTime(0, end_pos - 0.0001)
            local new_end_beat = end_beat - end_denom * grid_div
            local new_end_pos = reaper.TimeMap2_beatsToTime(0, new_end_beat)
            local new_edit = edit:gsub(' .- ', ' ' .. new_end_pos .. ' ', 1)
            if new_end_pos > start_pos + 0.0001 then
                new_razor_edit = new_razor_edit .. new_edit .. ' '
            end
        end
        GetSetTrackInfo(track, 'P_RAZOREDITS', new_razor_edit, true)
    end
end

-- Move edit cursor one measure to the left
if not has_razor_edit then
    local track = reaper.GetLastTouchedTrack()
    local cursor_pos = reaper.GetCursorPosition()
    local _, _, _, full_beats = reaper.TimeMap2_timeToBeats(0, cursor_pos)
    local num = reaper.TimeMap_GetTimeSigAtTime(0, cursor_pos - 0.0001)
    local new_cursor_beat = full_beats - num
    local new_cursor_pos = reaper.TimeMap2_beatsToTime(0, new_cursor_beat)
    reaper.SetEditCurPos2(0, new_cursor_pos, true, false)

    cursor_pos = new_cursor_pos
    reaper.SelectAllMediaItems(0, false)
    -- Select all items on selected tracks that cross edit cursor
    for t = 0, reaper.CountSelectedTracks(0) - 1 do
        local track = reaper.GetSelectedTrack(0, t)
        for i = 0, reaper.CountTrackMediaItems(track) - 1 do
            local item = reaper.GetTrackMediaItem(track, i)
            local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
            local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
            local item_end_pos = item_start_pos + item_length

            -- Check if item crosses start of region
            if item_start_pos <= cursor_pos and item_end_pos - 0.0001 > cursor_pos then
                reaper.SetMediaItemSelected(item, true)
            end

            if item_start_pos > cursor_pos then
                break
            end
        end
    end
    reaper.UpdateArrange()
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock('Resize razor edit left by grid size', -1)
