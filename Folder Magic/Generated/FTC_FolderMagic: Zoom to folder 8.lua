--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @noindex
  @about Zoom to folders or tracks based on name or number
]]
function hasVisibleItems(track, view_start_pos, view_end_pos)
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local item_end_pos = item_start_pos + item_length
        if item_end_pos > view_start_pos and item_start_pos < view_end_pos then
            return true
        end
        if item_start_pos > view_end_pos then
            break
        end
    end
    return false
end

function getFolderByNumber(tracks, number, min_depth, max_depth, use_min_folder)
    local folder_cnt = 0
    for _, track in ipairs(tracks) do
        local is_folder = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH') == 1
        local depth = reaper.GetTrackDepth(track)
        if is_folder or use_min_folder and depth == min_depth then
            if depth >= min_depth and depth <= max_depth then
                folder_cnt = folder_cnt + 1
                if folder_cnt == number then
                    return track
                end
            end
        end
    end
end

function getFolderByName(tracks, name, min_depth, max_depth)
    local name = name:lower()
    local backup
    local start_backup
    local no_depth_backup
    for _, track in ipairs(tracks) do
        local is_folder = reaper.GetMediaTrackInfo_Value(track, 'I_FOLDERDEPTH') == 1
        local depth = reaper.GetTrackDepth(track)
        if is_folder or use_min_folder and depth == min_depth then
            local ret, track_name = reaper.GetTrackName(track, '')
            if not track_name:match('^Track %d+$') then
                track_name = track_name:lower()
                -- Match start of string
                local start_match = track_name:match('^' .. name)
                if start_match then
                    if depth >= min_depth and depth <= max_depth then
                        return track
                    elseif not start_backup then
                        start_backup = track
                    end
                end
                -- Match string
                local match = track_name:match(name)
                if match then
                    if depth >= min_depth and depth <= max_depth then
                        if not start_backup then
                            backup = track
                        end
                    elseif not no_depth_backup then
                        no_depth_backup = track
                    end
                end
            end
        end
    end
    if backup then
        return backup
    end
    if start_backup then
        return start_backup
    end
    if no_depth_backup then
        return no_depth_backup
    end
end

function getTrackByName(tracks, name)
    local name = name:lower()
    local backup
    for _, track in ipairs(tracks) do
        local _, track_name = reaper.GetTrackName(track, '')
        if not track_name:match('^Track %d+$') then
            track_name = track_name:lower()
            -- Match start of string
            local start_match = track_name:match('^' .. name)
            if start_match then
                return track
            end
            -- Match string
            local match = track_name:match(name)
            if match then
                backup = track
            end
        end
    end
    return backup
end

function getFolderTracks(folder)
    local tracks = {folder}
    local track_num = reaper.GetMediaTrackInfo_Value(folder, 'IP_TRACKNUMBER')
    local folder_depth = reaper.GetTrackDepth(folder)
    for i = track_num, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local depth = reaper.GetTrackDepth(track)
        if depth <= folder_depth then
            break
        end
        tracks[#tracks + 1] = track
    end
    return tracks
end

function uncollapseFolders(tracks)
    reaper.PreventUIRefresh(1)
    local prev_depth = reaper.GetTrackDepth(tracks[1])
    local sel_items = {}
    for i = reaper.CountSelectedMediaItems(0) - 1, 0, -1 do
        local item = reaper.GetSelectedMediaItem(0, i)
        sel_items[#sel_items + 1] = item
        reaper.SetMediaItemSelected(item, false)
    end
    for i = 2, #tracks do
        local depth = reaper.GetTrackDepth(tracks[i])
        if depth > prev_depth then
            local folder = tracks[i - 1]
            -- Uncollapse folders in tcp
            reaper.SetMediaTrackInfo_Value(folder, 'I_FOLDERCOMPACT', 0)
            -- Uncollapse folders in mcp
            local _, chunk = reaper.GetTrackStateChunk(folder, '', true)
            local is_collapsed = tonumber(chunk:match('\nBUSCOMP %d (%d) %d'))
            if is_collapsed == 1 then
                reaper.SetTrackSelected(folder, true)
                -- Cmd: Show/hide children of selected tracks
                reaper.Main_OnCommand(41665, 0)
                reaper.SetTrackSelected(folder, false)
            end
        end
        prev_depth = depth
    end
    for _, item in ipairs(sel_items) do
        reaper.SetMediaItemSelected(item, true)
    end
    reaper.PreventUIRefresh(-1)
end

-----------------------------------------------------------------------------

reaper.Undo_BeginBlock()

local extname = 'FTC.FolderMagic'
local mb_title = 'Folder Magic'

local emphasis_factor = tonumber(reaper.GetExtState(extname, 'emphasis_factor')) or 3.5
local min_depth = tonumber(reaper.GetExtState(extname, 'min_depth')) or 0
local max_depth = tonumber(reaper.GetExtState(extname, 'max_depth')) or 0
local use_tracks = reaper.GetExtState(extname, 'use_tracks') == 'yes' or false
local zoom_mode = reaper.GetExtState(extname, 'reverse_zoom_mode') == 'yes' and 1 or 0

local _, file_name = reaper.get_action_context()
local sep = reaper.GetOS():match('win') and '\\' or '/'
file_name = file_name:gsub('.+' .. sep, '')
local undo_name = file_name:gsub('.+:%s', ''):gsub('%..+', '')

-- Check if SWS extension is installed
if not reaper.BR_EnvGetProperties then
    reaper.MB('Please install SWS extension', mb_title, 0)
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_GetScrollInfo then
    reaper.MB('Please install js_ReaScriptAPI extension', mb_title, 0)
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

-- Get track or folder id from filename
local folder_id, track_id = file_name:match('folder (.-) track (.-)%.')
if not folder_id and not track_id then
    folder_id = file_name:match('folder (.-)%.')
    track_id = file_name:match('track (.-)%.')
end
-- Get track or folder id from user dialog
if file_name:match('dialog') then
    local msg = 'Folder (name or number),Track (name or number)'
    local ret, user_input = reaper.GetUserInputs(mb_title, 2, msg, '')
    if not ret then
        reaper.Undo_EndBlock(undo_name, -1)
        return
    end

    folder_id = user_input:gsub(',.*', '')
    track_id = user_input:gsub('.*,', '')
end

-- Remove trailing and leading whitespaces
if folder_id then
    folder_id = folder_id:gsub('^%s*(.-)%s*$', '%1')
end
if track_id then
    track_id = track_id:gsub('^%s*(.-)%s*$', '%1')
end

-- Get main window properties
local main_hwnd = reaper.GetMainHwnd()
local main_id = reaper.JS_Window_FindChildByID(main_hwnd, 1000)
local _, page_pos, page_size = reaper.JS_Window_GetScrollInfo(main_id, 'v')
local view_start_pos, view_end_pos = reaper.GetSet_ArrangeView2(0, false, 0, 0)

-- Check double click to determine zoom mode
local prev_timestamp = tonumber(reaper.GetExtState(extname, 'timestamp'))
local prev_folder_id = reaper.GetExtState(extname, 'folder_id')
local prev_track_id = reaper.GetExtState(extname, 'track_id')

local timestamp = reaper.time_precise()

if tostring(folder_id) == prev_folder_id and tostring(track_id) == prev_track_id then
    if prev_timestamp and timestamp - prev_timestamp < 0.35 then
        -- Switch zoom mode
        zoom_mode = 1 - zoom_mode
    end
end
reaper.SetExtState(extname, 'timestamp', timestamp, false)
reaper.SetExtState(extname, 'folder_id', tostring(folder_id), false)
reaper.SetExtState(extname, 'track_id', tostring(track_id), false)

local all_tracks = {}
for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if reaper.GetMediaTrackInfo_Value(track, 'B_SHOWINTCP') == 1 then
        all_tracks[#all_tracks + 1] = track
    end
end

if #all_tracks == 0 then
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

local main_track
local tracks = all_tracks

if folder_id and folder_id ~= '' then
    if tonumber(folder_id) then
        local number = tonumber(folder_id)
        main_track = getFolderByNumber(tracks, number, min_depth, max_depth, use_tracks)
    else
        main_track = getFolderByName(tracks, folder_id, min_depth, max_depth, use_tracks)
    end
    if main_track then
        tracks = getFolderTracks(main_track)
        uncollapseFolders(tracks)
    else
        track_id = nil
    end
end

if track_id and track_id ~= '' then
    if tonumber(track_id) then
        main_track = tracks[tonumber(track_id)]
    else
        main_track = getTrackByName(tracks, track_id)
    end
    if main_track then
        tracks = {main_track}
    end
end

local is_zoom_out = false
if not main_track then
    tracks = all_tracks
    main_track = all_tracks[1]
    is_zoom_out = true
end

-- Find index of last track that has visible items
local last_vis_track_idx
for i = #tracks, 1, -1 do
    local has_vis_items = hasVisibleItems(tracks[i], view_start_pos, view_end_pos)
    if not last_vis_track_idx and has_vis_items then
        last_vis_track_idx = i
    end
end

if zoom_mode == 1 and last_vis_track_idx then
    local vis_tracks = {}
    -- Add all tracks after first visible track to list
    for i = 1, last_vis_track_idx do
        if #vis_tracks == 0 then
            local has_vis_items = hasVisibleItems(tracks[i], view_start_pos, view_end_pos)
            if has_vis_items then
                vis_tracks[#vis_tracks + 1] = tracks[i]
            end
        else
            vis_tracks[#vis_tracks + 1] = tracks[i]
        end
    end
    -- Swap lists
    tracks = vis_tracks
end

-- Get track current state
local is_selected = reaper.IsTrackSelected(main_track)
local rec_arm = reaper.GetMediaTrackInfo_Value(main_track, 'I_RECARM')
local height_lock = reaper.GetMediaTrackInfo_Value(main_track, 'B_HEIGHTLOCK')
local height = reaper.GetMediaTrackInfo_Value(main_track, 'I_HEIGHTOVERRIDE')

-- Switch off track settings that get in the way
reaper.SetTrackSelected(main_track, false)
reaper.SetMediaTrackInfo_Value(main_track, 'B_HEIGHTLOCK', 0)
reaper.SetMediaTrackInfo_Value(main_track, 'I_RECARM', 0)
reaper.SetMediaTrackInfo_Value(main_track, 'I_HEIGHTOVERRIDE', 1)

-- Check min height for tracks
reaper.TrackList_AdjustWindows(true)
local track_min_height = reaper.GetMediaTrackInfo_Value(main_track, 'I_TCPH')

-- Check min height for record armed tracks
reaper.SetMediaTrackInfo_Value(main_track, 'I_RECARM', 1)
reaper.TrackList_AdjustWindows(true)
local armed_track_min_height = reaper.GetMediaTrackInfo_Value(main_track, 'I_TCPH')

-- Revert track to previous settings
reaper.SetTrackSelected(main_track, is_selected)
reaper.SetMediaTrackInfo_Value(main_track, 'I_RECARM', rec_arm)
reaper.SetMediaTrackInfo_Value(main_track, 'B_HEIGHTLOCK', height_lock)
reaper.SetMediaTrackInfo_Value(main_track, 'I_HEIGHTOVERRIDE', height)

local tracks_info = {}

local min_height_sum = 0
local empty_lane_cnt = 0
local full_lane_cnt = 0

local getEnvProps = reaper.BR_EnvGetProperties
local setEnvProps = reaper.BR_EnvSetProperties

-- Gather information about tracks and envelopes
for i, track in ipairs(tracks) do
    local info = {}
    info.height_lock = reaper.GetMediaTrackInfo_Value(track, 'B_HEIGHTLOCK')
    -- Locked tracks are not touched
    if info.height_lock > 0 then
        local height = reaper.GetMediaTrackInfo_Value(track, 'I_WNDH')
        min_height_sum = min_height_sum + height
    else
        -- Get minimum track height
        info.rec_arm = reaper.GetMediaTrackInfo_Value(track, 'I_RECARM')
        if info.rec_arm == 0 then
            info.min_height = track_min_height
        else
            info.min_height = armed_track_min_height
        end
        min_height_sum = min_height_sum + info.min_height
        -- Count lanes with and without visible items
        info.has_vis_items = hasVisibleItems(track, view_start_pos, view_end_pos)
        if info.has_vis_items then
            full_lane_cnt = full_lane_cnt + 1
        else
            empty_lane_cnt = empty_lane_cnt + 1
        end
        -- Count visible envelopes
        for e = 0, reaper.CountTrackEnvelopes(track) - 1 do
            local env = reaper.GetTrackEnvelope(track, e)
            local br_env = reaper.BR_EnvAlloc(env, false)
            local _, vis, _, in_lane = getEnvProps(br_env)
            if vis and in_lane then
                min_height_sum = min_height_sum + track_min_height + 1
                if info.has_vis_items then
                    full_lane_cnt = full_lane_cnt + 1
                else
                    empty_lane_cnt = empty_lane_cnt + 1
                end
            end
            reaper.BR_EnvFree(br_env, false)
        end
    end
    tracks_info[#tracks_info + 1] = info
end

local empty_offset, full_offset, rest_offset, rest = 0, 0, 0, 0
local diff = page_size - min_height_sum

if diff > 0 then
    -- Calculate track height offsets that will be added to minimum height
    if zoom_mode == 1 and full_lane_cnt > 0 or emphasis_factor >= 10 then
        empty_offset = 0
        full_offset = diff // full_lane_cnt
    else
        empty_offset = diff // (full_lane_cnt * emphasis_factor + empty_lane_cnt)
        full_offset = math.floor(emphasis_factor * empty_offset)
    end
    -- Rest pixels are spread amongst tracks (not envelopes)
    rest = diff - full_offset * full_lane_cnt - empty_offset * empty_lane_cnt
    rest_offset = math.ceil(rest / #tracks)
end

-- Set track heights
for i, track in ipairs(tracks) do
    local info = tracks_info[i]
    if info.height_lock == 0 then
        local offset = info.has_vis_items and full_offset or empty_offset
        -- Set track height
        local track_height = info.min_height + offset
        if rest > 0 then
            track_height = track_height + rest_offset
            rest = rest - rest_offset
        end
        reaper.SetMediaTrackInfo_Value(track, 'I_HEIGHTOVERRIDE', track_height)
        -- Set visible envelope heights
        local env_height = track_min_height + offset + 1
        for e = 0, reaper.CountTrackEnvelopes(track) - 1 do
            local env = reaper.GetTrackEnvelope(track, e)
            local br_env = reaper.BR_EnvAlloc(env, false)
            local act, vis, arm, in_lane, _, ds, _, _, _, _, fs = getEnvProps(br_env)
            if vis then
                setEnvProps(br_env, act, vis, arm, in_lane, env_height, ds, fs)
            end
            reaper.BR_EnvFree(br_env, true)
        end
    end
end

if is_zoom_out and diff < 0 then
    -- Track: Vertical scroll selected tracks into view
    reaper.Main_OnCommand(40913, 0)
    reaper.TrackList_AdjustWindows(true)
    -- Make sure to not scroll past last track
    local last_track = tracks[#tracks]
    local tcp_y = reaper.GetMediaTrackInfo_Value(last_track, 'I_TCPY')
    local wnd_h = reaper.GetMediaTrackInfo_Value(last_track, 'I_WNDH')
    -- Scrolling is only necessary when the last track height is inside page_size
    if tcp_y + wnd_h < page_size then
        local diff = tcp_y + wnd_h - page_size
        reaper.JS_Window_SetScrollPos(main_id, 'v', page_pos + diff)
        reaper.TrackList_AdjustWindows(false)
        -- Note: Scrolling twice is necessary to ensure correct scroll
        local _, page_pos = reaper.JS_Window_GetScrollInfo(main_id, 'v')
        local tcp_y = reaper.GetMediaTrackInfo_Value(last_track, 'I_TCPY')
        local diff = tcp_y + wnd_h - page_size
        reaper.JS_Window_SetScrollPos(main_id, 'v', page_pos + diff)
        reaper.TrackList_AdjustWindows(true)
    end
else
    -- Scroll to first visible track
    local tcp_y = reaper.GetMediaTrackInfo_Value(tracks[1], 'I_TCPY')
    reaper.JS_Window_SetScrollPos(main_id, 'v', page_pos + tcp_y)
    reaper.TrackList_AdjustWindows(false)
    -- Note: Scrolling twice is necessary to ensure correct scroll
    local _, page_pos = reaper.JS_Window_GetScrollInfo(main_id, 'v')
    local tcp_y = reaper.GetMediaTrackInfo_Value(tracks[1], 'I_TCPY')
    reaper.JS_Window_SetScrollPos(main_id, 'v', page_pos + tcp_y)
    reaper.TrackList_AdjustWindows(true)
end

reaper.SetMixerScroll(main_track)
reaper.Undo_EndBlock(undo_name, -1)
