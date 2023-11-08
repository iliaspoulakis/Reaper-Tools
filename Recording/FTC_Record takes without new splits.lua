--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.2.0
  @about Record takes without creating new splits. Recorded takes are split at existing item edges
  @changelog
    - Add v7 lane support
]]
-- User configuration

-- If set to true new take colors will be automatically colored, disregarding the reaper preference
local force_take_colors = false
-- If set to false, take colors will be used in the order below
local randomize_color_order = true

local colors = {
    '#8460a8',
    '#9a60a8',
    '#a8608a',
    '#a8606d',
    '#a86a60',
    '#a87c60',
    '#a89360',
    '#a2a860',
    '#87a860',
    '#71a860',
    '#60a874',
    '#60a897',
}

-------------------------------------------------------------------------------

local _, _, sec, cmd = reaper.get_action_context()
local tracks_state
local prev_play_state
local prev_undo_state
local rec_option_cmd

local color_idx = 1
local undo_idx

local extname = 'FTC.Record_without_splits'
local undo_name = 'Recorded media without splits'

local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(1) end

-- Get auto-coloring preference from ini file
local use_take_colors = false
local file = io.open(reaper.get_ini_file(), 'r')
if file then
    for line in file:lines() do
        local match = line:match('tinttcp=(.-)$')
        if match then
            use_take_colors = tonumber(match) & 512 == 512
            break
        end
    end
    file:close()
end
use_take_colors = use_take_colors or force_take_colors

function ShuffleColors()
    math.randomseed(reaper.time_precise())
    for i = #colors, 2, -1 do
        local j = math.random(i)
        colors[i], colors[j] = colors[j], colors[i]
    end
end

function Hex2Native(color)
    local r = tonumber(color:sub(2, 3), 16)
    local g = tonumber(color:sub(4, 5), 16)
    local b = tonumber(color:sub(6, 7), 16)
    return reaper.ColorToNative(r, g, b) | 0x1000000
end

function SetItemTakeColors(item, default)
    for tk = 0, reaper.GetMediaItemNumTakes(item) - 1 do
        local take = reaper.GetMediaItemTake(item, tk)
        if reaper.ValidatePtr(take, 'MediaItem_Take*') then
            local color = default and 0 or Hex2Native(colors[color_idx])
            reaper.SetMediaItemTakeInfo_Value(take, 'I_CUSTOMCOLOR', color)
            color_idx = (color_idx % #colors) + 1
        end
    end
end

function GetArmedTracks()
    local tracks = {}
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        if reaper.GetMediaTrackInfo_Value(track, 'I_RECARM') == 1 then
            tracks[#tracks + 1] = track
        end
    end
    return tracks
end

function GetTrackItems(track)
    local items = {}
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        items[#items + 1] = reaper.GetTrackMediaItem(track, i)
    end
    return items
end

function GetNewItems(track_state)
    local items = {}
    local item_cnt = reaper.CountTrackMediaItems(track_state.track)
    if item_cnt ~= #track_state.items then
        local idx = 1
        for i = 0, item_cnt - 1 do
            local item = reaper.GetTrackMediaItem(track_state.track, i)
            if item ~= track_state.items[idx] then
                items[#items + 1] = item
            else
                idx = idx + 1
            end
        end
    end
    return items
end

function MergeTakes(main_item, item, item_soffs)
    local GetTakeInfo = reaper.GetMediaItemTakeInfo_Value
    local SetTakeInfo = reaper.SetMediaItemTakeInfo_Value
    local GetSetTakeInfo = reaper.GetSetMediaItemTakeInfo_String

    if reaper.ValidatePtr(item, 'MediaItem*') then
        -- Set sources of item to new takes on main item
        for tk = 0, reaper.GetMediaItemNumTakes(item) - 1 do
            local take = reaper.GetMediaItemTake(item, tk)
            if reaper.ValidatePtr(take, 'MediaItem_Take*') then
                -- Get take info
                local take_source = reaper.GetMediaItemTake_Source(take)
                local take_soffs = GetTakeInfo(take, 'D_STARTOFFS')
                local take_color = GetTakeInfo(take, 'I_CUSTOMCOLOR')
                local _, take_name = GetSetTakeInfo(take, 'P_NAME', '', false)

                -- Add take to main item
                local new_take = reaper.AddTakeToMediaItem(main_item)
                local new_take_source = reaper.GetMediaItemTake_Source(new_take)

                local soffs = take_soffs - item_soffs
                SetTakeInfo(new_take, 'D_STARTOFFS', soffs)
                SetTakeInfo(new_take, 'I_CUSTOMCOLOR', take_color)
                GetSetTakeInfo(new_take, 'P_NAME', take_name, true)

                reaper.SetMediaItemTake_Source(new_take, take_source)
                reaper.PCM_Source_Destroy(new_take_source)

                reaper.SetActiveTake(new_take)
            end
        end
        local track = reaper.GetMediaItem_Track(item)
        reaper.DeleteTrackMediaItem(track, item)
    end
end

function AddEmptyTakeLanes(main_item, num, is_add_at_start)
    reaper.PreventUIRefresh(1)
    local sel_items = {}
    -- Save current item selection
    for i = reaper.CountSelectedMediaItems() - 1, 0, -1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        sel_items[i + 1] = item
        reaper.SetMediaItemSelected(item, false)
    end
    -- Activate last take and use action that adds empty take lanes
    reaper.SetMediaItemSelected(main_item, true)
    local curr_tk = reaper.GetMediaItemInfo_Value(main_item, 'I_CURTAKE')
    local num_takes = reaper.GetMediaItemNumTakes(main_item)
    local target_tk = is_add_at_start and 0 or num_takes - 1
    reaper.SetMediaItemInfo_Value(main_item, 'I_CURTAKE', target_tk)
    for i = 1, num do
        -- Item: Add an empty take lane before/after the active take
        reaper.Main_OnCommand(is_add_at_start and 41351 or 41352, 0)
    end
    reaper.SetMediaItemInfo_Value(main_item, 'I_CURTAKE', curr_tk)
    reaper.SetMediaItemSelected(main_item, false)
    -- Restore item selection
    for _, item in ipairs(sel_items) do
        reaper.SetMediaItemSelected(item, true)
    end
    reaper.PreventUIRefresh(-1)
end

function MergeItems(track_state, new_item)
    local GetItemInfo = reaper.GetMediaItemInfo_Value
    local SetItemInfo = reaper.SetMediaItemInfo_Value
    local DeleteTrackItem = reaper.DeleteTrackMediaItem

    local overlap_cnt = 0
    local updated_items = {}

    local length = GetItemInfo(new_item, 'D_LENGTH')
    local start_pos = GetItemInfo(new_item, 'D_POSITION')
    local end_pos = start_pos + length

    local lane = GetItemInfo(new_item, 'I_FIXEDLANE') or 0

    local m = 0.0001

    -- When recording to layers new items do not end on full beat.
    -- There is a tiny offset of less than a millisecond. Is it a bug?
    local beats = reaper.TimeMap2_timeToBeats(0, end_pos)
    local beat_diff = beats - math.floor(beats + 0.5)
    if math.abs(beat_diff) < m then
        -- Snap item end to beat
        local diff_time = reaper.TimeMap2_beatsToTime(0, beat_diff)
        SetItemInfo(new_item, 'D_LENGTH', length - diff_time)
        end_pos = end_pos - diff_time
    end

    if use_take_colors then
        SetItemTakeColors(new_item)
    end

    local max_num_takes = 0
    for i = 1, #track_state.items do
        local item = track_state.items[i]
        local item_length = GetItemInfo(item, 'D_LENGTH')
        local item_start_pos = GetItemInfo(item, 'D_POSITION')
        local item_end_pos = item_start_pos + item_length
        local item_lane = GetItemInfo(item, 'I_FIXEDLANE') or 0
        -- Check if items overlap
        if item_start_pos < end_pos - m and item_end_pos > start_pos + m
            and item_lane == lane then
            local num_takes = reaper.GetMediaItemNumTakes(item)
            max_num_takes = math.max(max_num_takes, num_takes)
        end
        if item_start_pos > end_pos then
            break
        end
    end

    for _, item in ipairs(track_state.items) do
        if new_item then
            local item_length = GetItemInfo(item, 'D_LENGTH')
            local item_start_pos = GetItemInfo(item, 'D_POSITION')
            local item_end_pos = item_start_pos + item_length
            local item_lane = GetItemInfo(item, 'I_FIXEDLANE') or 0
            -- Check if items overlap
            if item_start_pos < end_pos - m and item_end_pos > start_pos + m
                and item_lane == lane then
                -- Add empty take lanes if necessary
                local num_takes = reaper.GetMediaItemNumTakes(item)
                local take_diff = max_num_takes - num_takes
                if take_diff > 0 then
                    AddEmptyTakeLanes(item, take_diff)
                end
                local overlapping_item = new_item
                -- Split starts (keep tail)
                if start_pos < item_start_pos then
                    local tail = reaper.SplitMediaItem(new_item, item_start_pos)
                    if tail then
                        if item_start_pos - start_pos < 0.005 then
                            -- Delete tiny leftover
                            DeleteTrackItem(track_state.track, new_item)
                        else
                            -- Update items for next iteration
                            updated_items[#updated_items + 1] = new_item
                            num_takes = reaper.GetMediaItemNumTakes(new_item)
                            take_diff = max_num_takes - num_takes + 1
                            if take_diff > 0 then
                                AddEmptyTakeLanes(new_item, take_diff, true)
                            end
                        end
                        new_item = tail
                        overlapping_item = tail
                    end
                    start_pos = item_start_pos
                end
                -- Split ends (cut off tail)
                if end_pos > item_end_pos then
                    new_item = reaper.SplitMediaItem(new_item, item_end_pos)
                    if new_item and end_pos - item_end_pos < 0.005 then
                        -- Delete tiny leftover
                        DeleteTrackItem(track_state.track, new_item)
                        new_item = nil
                    else
                        num_takes = reaper.GetMediaItemNumTakes(new_item)
                        take_diff = max_num_takes - num_takes + 1
                        if take_diff > 0 then
                            AddEmptyTakeLanes(new_item, take_diff, true)
                        end
                    end
                end
                -- Merge overlapping item
                local item_soffs = start_pos - item_start_pos
                MergeTakes(item, overlapping_item, item_soffs)
                SetItemInfo(item, 'B_LOOPSRC', 0)
                reaper.SetMediaItemSelected(item, true)

                overlap_cnt = overlap_cnt + 1
                start_pos = item_end_pos
            end
            -- Update items for next iteration (correct position)
            if overlap_cnt == 0 and item_start_pos > end_pos then
                updated_items[#updated_items + 1] = new_item
                SetItemTakeColors(new_item, true)
                overlap_cnt = overlap_cnt + 1
                new_item = nil
            end
        end
        updated_items[#updated_items + 1] = item
    end
    -- Update items for next iteration
    if overlap_cnt == 0 or #track_state.items == 0 then
        updated_items[#updated_items + 1] = new_item
        SetItemTakeColors(new_item, true)
    end
    track_state.items = updated_items
end

function Main()
    local play_state = reaper.GetPlayState()
    local undo_state = reaper.GetProjectStateChangeCount(0)

    if prev_play_state ~= play_state then
        if play_state == 5 then
            -- Save currently selected recording option
            local layer_rec_cmd = version >= 7.00 and 42677 or 41329
            local rec_option_cmds = {41330, 41186, layer_rec_cmd}
            for _, rec_cmd in ipairs(rec_option_cmds) do
                if reaper.GetToggleCommandState(rec_cmd) == 1 then
                    rec_option_cmd = rec_cmd
                end
            end
            -- Cmd: New recording creates new media items in separate lanes
            reaper.Main_OnCommand(layer_rec_cmd, 0)
            tracks_state = {}
            local tracks = GetArmedTracks()
            for i, track in ipairs(tracks) do
                tracks_state[i] = {track = track, items = GetTrackItems(track)}
            end
        end
        prev_play_state = play_state
    end

    if undo_state ~= prev_undo_state then
        if play_state == 5 then
            -- Handle editing and other changes during recording
            tracks_state = {}
            local tracks = GetArmedTracks()
            for _, track in ipairs(tracks) do
                local is_updated = false
                for i, state in ipairs(tracks_state) do
                    if state.track == track then
                        -- Update existing states
                        tracks_state[i] = {
                            track = track,
                            items = GetTrackItems(track),
                        }
                        is_updated = true
                        break
                    end
                end
                if not is_updated then
                    -- Add new state
                    local state = {track = track, items = GetTrackItems(track)}
                    tracks_state[#tracks_state + 1] = state
                end
            end
        end
        local redo = reaper.Undo_CanRedo2(0)
        if redo then
            local idx = tonumber(redo:match(undo_name .. ' %((%d+)'))
            if idx then
                if not undo_idx or idx < undo_idx then
                    undo_idx = idx
                end
                if idx == undo_idx then
                    reaper.Undo_DoUndo2(0)
                    undo_idx = undo_idx - 1
                elseif idx > undo_idx then
                    reaper.Undo_DoRedo2(0)
                    undo_idx = idx
                end
            end
        end
    end

    if tracks_state and play_state ~= 5 then
        -- Check undo state in case there is a record dialog
        if prev_undo_state ~= undo_state then
            if reaper.Undo_CanUndo2(0) == 'Recorded media' then
                -- Find new recorded items and merge them
                reaper.Undo_BeginBlock()
                for _, track_state in ipairs(tracks_state) do
                    local new_items = GetNewItems(track_state)
                    for _, item in ipairs(new_items) do
                        MergeItems(track_state, item)
                    end
                end
                reaper.UpdateArrange()
                local _, undo_cnt = reaper.GetProjExtState(0, extname, 'cnt')
                undo_cnt = tonumber(undo_cnt) or 0
                undo_cnt = undo_cnt + 1
                undo_idx = undo_cnt
                reaper.SetProjExtState(0, extname, 'cnt', undo_cnt)
                reaper.Undo_EndBlock(undo_name .. ' (' .. undo_idx .. ')', -1)
            end
            -- Restore previous recording option
            if rec_option_cmd then
                reaper.Main_OnCommand(rec_option_cmd, 0)
            end
            tracks_state = nil
            rec_option_cmd = nil
        end
    else
        prev_undo_state = undo_state
    end

    -- Keep polling until terminated by other script
    if reaper.GetExtState(extname, 'state_new_splits') == 'on' then
        reaper.defer(Main)
    end
end

reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

-- Terminate other running scripts
if reaper.GetExtState(extname, 'state_min_splits') == 'on' then
    reaper.SetExtState(extname, 'state_min_splits', 'off', false)
end

-- Signal that this script is running
reaper.SetExtState(extname, 'state_new_splits', 'on', false)

if randomize_color_order then
    ShuffleColors()
end

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    reaper.SetExtState(extname, 'state_new_splits', 'off', false)
end

reaper.atexit(Exit)
reaper.defer(Main)
