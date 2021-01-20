--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.1
  @about Create an approximate razor edit from time selection
]]
local expand_beat_limit = 3
local shrink_beat_limit = 1

reaper.Undo_BeginBlock()

local sel_start_pos, sel_end_pos = reaper.GetSet_LoopTimeRange(false, true, 0, 0, false)
local is_valid_sel = sel_end_pos > 0 and sel_start_pos ~= sel_end_pos

if not is_valid_sel then
    reaper.Undo_EndBlock('Create razor edit from time selection', -1)
    return
end

-- Razor edit: Clear all areas
reaper.Main_OnCommand(42406, 0)

local _, _, _, sel_start_beat = reaper.TimeMap2_timeToBeats(0, sel_start_pos)
local _, _, _, sel_end_beat = reaper.TimeMap2_timeToBeats(0, sel_end_pos)

for t = 0, reaper.CountTracks(0) - 1 do
    local raz_start_pos = sel_start_pos
    local raz_end_pos = sel_end_pos
    local track = reaper.GetTrack(0, t)

    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local item_mid_pos = item_start_pos + item_length / 2
        local item_end_pos = item_start_pos + item_length

        -- Check if item crosses start of region
        if item_start_pos < sel_start_pos and item_end_pos > sel_start_pos then
            -- Check if the larger part of the item is inside the region
            if item_mid_pos >= sel_start_pos then
                -- Expand razor edit to item_start_pos if below limit
                local _, _, _, beat = reaper.TimeMap2_timeToBeats(0, item_start_pos)
                if sel_start_beat - beat < expand_beat_limit + 0.0001 then
                    raz_start_pos = item_start_pos
                end
            else
                -- Shrink razor edit to item_end_pos if below limit
                local _, _, _, beat = reaper.TimeMap2_timeToBeats(0, item_end_pos)
                if beat - sel_start_beat < shrink_beat_limit + 0.0001 then
                    raz_start_pos = item_end_pos
                end
            end
        end
        -- Check if item crosses end of region
        if item_start_pos < sel_end_pos and item_end_pos > sel_end_pos then
            if item_mid_pos <= sel_end_pos then
                -- Expand razor edit to item_end_pos if below limit
                local _, _, _, beat = reaper.TimeMap2_timeToBeats(0, item_end_pos)
                if beat - sel_end_beat < expand_beat_limit + 0.0001 then
                    raz_end_pos = item_end_pos
                end
            else
                -- Shrink razor edit to item_start_pos if below limit
                local _, _, _, beat = reaper.TimeMap2_timeToBeats(0, item_start_pos)
                if sel_end_beat - beat < shrink_beat_limit + 0.0001 then
                    raz_end_pos = item_start_pos
                end
            end
        end
        if item_start_pos > sel_end_pos then
            break
        end
    end
    local raz_edit = raz_start_pos .. ' ' .. raz_end_pos .. ' ""'
    reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', raz_edit, true)
end
reaper.Undo_EndBlock('Create razor edit from time selection', -1)
