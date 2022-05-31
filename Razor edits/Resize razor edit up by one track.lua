--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.1
  @about A set of scripts for quick razor editing using arrow keys
  @changelog
    - Fix script not working when there's a razor edit on last track
]]
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Set edit cursor to razor edit start pos
local has_razor_edit = false
local GetSetTrackInfo = reaper.GetSetMediaTrackInfo_String

local last_razor_edit
local track_cnt = reaper.CountTracks(0)
for i = track_cnt - 1, 0, -1 do
    local track = reaper.GetTrack(0, i)
    local _, razor_edit = GetSetTrackInfo(track, 'P_RAZOREDITS', '', false)
    if razor_edit ~= '' then
        has_razor_edit = true
        if last_razor_edit == '' or i == track_cnt - 1 then
            GetSetTrackInfo(track, 'P_RAZOREDITS', '', true)
        end
    end
    last_razor_edit = razor_edit
end

if not has_razor_edit then
    -- Track: Go to previous track
    reaper.Main_OnCommand(40286, 0)

    local cursor_pos = reaper.GetCursorPosition()
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
reaper.Undo_EndBlock('Resize razor edit up by one track', -1)
