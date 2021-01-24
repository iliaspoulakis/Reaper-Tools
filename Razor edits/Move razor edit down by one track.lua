--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about A set of scripts for quick razor editing using arrow keys
]]
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)
-- Razor edit: Move areas down without contents
reaper.Main_OnCommand(42403, 0)

-- Set edit cursor to razor edit start pos
local has_razor_edit = false
local first_razor_edit_track
local last_razor_edit_track
local GetSetTrackInfo = reaper.GetSetMediaTrackInfo_String
for i = reaper.CountTracks(0) - 1, 0, -1 do
    local track = reaper.GetTrack(0, i)
    local _, razor_edit = GetSetTrackInfo(track, 'P_RAZOREDITS', '', false)
    if razor_edit ~= '' then
        if not has_razor_edit then
            has_razor_edit = true
            reaper.SetOnlyTrackSelected(track)
            -- Track: Go to previous track
            reaper.Main_OnCommand(40286, 0)
            -- Track: Go to next track
            reaper.Main_OnCommand(40285, 0)
        end
        reaper.SetOnlyTrackSelected(track)
        local start_pos = tonumber(razor_edit:match('[^%s]+'))
        reaper.SetEditCurPos2(0, start_pos, false, false)
    end
end

if not has_razor_edit then
    -- Track: Go to next track
    reaper.Main_OnCommand(40285, 0)

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
reaper.Undo_EndBlock('Move razor edit down by one track', -1)
