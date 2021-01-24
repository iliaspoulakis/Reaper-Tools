--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about A set of scripts for quick razor editing using arrow keys
]]
reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

-- Extend razor edit to the right by one measure
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
            local end_pos = tonumber(edit:match(' .- '))
            local _, _, _, end_beat = reaper.TimeMap2_timeToBeats(0, end_pos)
            local end_num = reaper.TimeMap_GetTimeSigAtTime(0, end_pos + 0.0001)
            local new_end_beat = end_beat + end_num
            local new_end_pos = reaper.TimeMap2_beatsToTime(0, new_end_beat)
            local new_edit = edit:gsub(' .- ', ' ' .. new_end_pos .. ' ', 1)
            new_razor_edit = new_razor_edit .. new_edit .. ' '
        end
        GetSetTrackInfo(track, 'P_RAZOREDITS', new_razor_edit, true)
    end
end

-- Create razor edit of one measure to the right of edit cursor
if not has_razor_edit then
    local track = reaper.GetLastTouchedTrack()
    local start_pos = reaper.GetCursorPosition()
    local num = reaper.TimeMap_GetTimeSigAtTime(0, start_pos + 0.0001)
    local _, _, _, full_beats = reaper.TimeMap2_timeToBeats(0, start_pos)
    local end_beat = full_beats + num
    local end_pos = reaper.TimeMap2_beatsToTime(0, end_beat)
    local new_razor_edit = start_pos .. ' ' .. end_pos .. ' ""'
    GetSetTrackInfo(track, 'P_RAZOREDITS', new_razor_edit, true)
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock('Resize razor edit right by one measure', -1)
