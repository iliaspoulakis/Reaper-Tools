--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Sets a razor edit to the region under the mouse
]]
local expand_beat_limit = 3
local shrink_beat_limit = 1

reaper.Undo_BeginBlock()

-- Get mouse cursor position
reaper.PreventUIRefresh(1)
local cursor_pos = reaper.GetCursorPosition()
-- View: Move edit cursor to mouse cursor (no snapping)
reaper.Main_OnCommand(40514, 0)
local mouse_pos = reaper.GetCursorPosition()
reaper.SetEditCurPos2(0, cursor_pos, false, false)
reaper.PreventUIRefresh(-1)

local _, reg_idx = reaper.GetLastMarkerAndCurRegion(0, mouse_pos)
if reg_idx == -1 then
    local proj_length = reaper.GetProjectLength(0)
    -- Set razor edit to space inbetween regions
    reg_start_pos = 0
    reg_end_pos = proj_length
    for i = 0, reaper.CountProjectMarkers(0) - 1 do
        local _, is_region, start_pos, end_pos = reaper.EnumProjectMarkers3(0, i)
        if is_region then
            if end_pos < mouse_pos then
                reg_start_pos = end_pos
            end
            if start_pos > mouse_pos then
                reg_end_pos = start_pos
                break
            end
        end
    end
    -- Set razor edit end to mouse pos if it exceeds project length
    if reg_start_pos == proj_length then
        reg_end_pos = mouse_pos
    end
else
    -- Get region bounds from region idx at mouse
    _, _, reg_start_pos, reg_end_pos = reaper.EnumProjectMarkers3(0, reg_idx)
end

-- Razor edit: Clear all areas
reaper.Main_OnCommand(42406, 0)

local _, _, _, reg_start_beat = reaper.TimeMap2_timeToBeats(0, reg_start_pos)
local _, _, _, reg_end_beat = reaper.TimeMap2_timeToBeats(0, reg_end_pos)

for t = 0, reaper.CountTracks(0) - 1 do
    local raz_start_pos = reg_start_pos
    local raz_end_pos = reg_end_pos
    local track = reaper.GetTrack(0, t)

    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local item_mid_pos = item_start_pos + item_length / 2
        local item_end_pos = item_start_pos + item_length

        -- Check if item crosses start of region
        if item_start_pos < reg_start_pos and item_end_pos > reg_start_pos then
            -- Check if the larger part of the item is inside the region
            if item_mid_pos >= reg_start_pos then
                -- Expand razor edit to item_start_pos if below limit
                local _, _, _, beat = reaper.TimeMap2_timeToBeats(0, item_start_pos)
                if reg_start_beat - beat < expand_beat_limit + 0.0001 then
                    raz_start_pos = item_start_pos
                end
            else
                -- Shrink razor edit to item_end_pos if below limit
                local _, _, _, beat = reaper.TimeMap2_timeToBeats(0, item_end_pos)
                if beat - reg_start_beat < shrink_beat_limit + 0.0001 then
                    raz_start_pos = item_end_pos
                end
            end
        end
        -- Check if item crosses end of region
        if item_start_pos < reg_end_pos and item_end_pos > reg_end_pos then
            if item_mid_pos <= reg_end_pos then
                -- Expand razor edit to item_end_pos if below limit
                local _, _, _, beat = reaper.TimeMap2_timeToBeats(0, item_end_pos)
                if beat - reg_end_beat < expand_beat_limit + 0.0001 then
                    raz_end_pos = item_end_pos
                end
            else
                -- Shrink razor edit to item_start_pos if below limit
                local _, _, _, beat = reaper.TimeMap2_timeToBeats(0, item_start_pos)
                if reg_end_beat - beat < shrink_beat_limit + 0.0001 then
                    raz_end_pos = item_start_pos
                end
            end
        end
        if item_start_pos > reg_end_pos then
            break
        end
    end
    local raz_edit = raz_start_pos .. ' ' .. raz_end_pos .. ' ""'
    reaper.GetSetMediaTrackInfo_String(track, 'P_RAZOREDITS', raz_edit, true)
end
reaper.Undo_EndBlock('Razor edit region under mouse', -1)
