--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.4
  @noindex
  @about Zoom to folders or tracks based on name or number
]]
local getTrackInfoValue = reaper.GetMediaTrackInfo_Value
local setTrackInfoValue = reaper.SetMediaTrackInfo_Value

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
        local is_folder = getTrackInfoValue(track, 'I_FOLDERDEPTH') == 1
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
        local is_folder = getTrackInfoValue(track, 'I_FOLDERDEPTH') == 1
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

function getCurrentFolderNum(tracks, min_depth, max_depth, use_min_folder)
    local folder_cnt = 0
    for _, track in ipairs(tracks) do
        local is_folder = getTrackInfoValue(track, 'I_FOLDERDEPTH') == 1
        local depth = reaper.GetTrackDepth(track)
        if is_folder or use_min_folder and depth == min_depth then
            if depth >= min_depth and depth <= max_depth then
                folder_cnt = folder_cnt + 1
                local tcp_y = getTrackInfoValue(track, 'I_TCPY')
                if tcp_y >= 0 then
                    return folder_cnt
                end
            end
        end
    end
end

function getFolderTracks(folder)
    local tracks = {folder}
    local track_num = getTrackInfoValue(folder, 'IP_TRACKNUMBER')
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
            setTrackInfoValue(folder, 'I_FOLDERCOMPACT', 0)
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

function getTrackHeights(track)
    -- Get track current state
    local is_selected = reaper.IsTrackSelected(track)
    local rec_arm = getTrackInfoValue(track, 'I_RECARM')
    local height_lock = getTrackInfoValue(track, 'B_HEIGHTLOCK')
    local height = getTrackInfoValue(track, 'I_HEIGHTOVERRIDE')

    -- Switch off track settings that get in the way
    reaper.SetTrackSelected(track, false)
    setTrackInfoValue(track, 'B_HEIGHTLOCK', 0)
    setTrackInfoValue(track, 'I_RECARM', 0)
    setTrackInfoValue(track, 'I_HEIGHTOVERRIDE', 1)

    -- Check min height for tracks
    reaper.TrackList_AdjustWindows(true)
    local track_min_height = getTrackInfoValue(track, 'I_TCPH')

    -- Check min height for record armed tracks
    setTrackInfoValue(track, 'I_RECARM', 1)
    reaper.TrackList_AdjustWindows(true)
    local armed_track_min_height = getTrackInfoValue(track, 'I_TCPH')

    -- Revert track to previous settings
    reaper.SetTrackSelected(track, is_selected)
    setTrackInfoValue(track, 'I_RECARM', rec_arm)
    setTrackInfoValue(track, 'B_HEIGHTLOCK', height_lock)
    setTrackInfoValue(track, 'I_HEIGHTOVERRIDE', height)
    return track_min_height, armed_track_min_height
end

-----------------------------------------------------------------------------

reaper.Undo_BeginBlock()

local extname = 'FTC.FolderMagic'
local mb_title = 'Folder Magic'

local emphasis_factor = tonumber(reaper.GetExtState(extname, 'emphasis_factor')) or 3.5
local min_depth = tonumber(reaper.GetExtState(extname, 'min_depth')) or 0
local max_depth = tonumber(reaper.GetExtState(extname, 'max_depth')) or 0
local use_tracks = reaper.GetExtState(extname, 'use_tracks') == 'yes' or false
local mode_sc = tonumber(reaper.GetExtState(extname, 'mode_sc')) or 3
local mode_dc = tonumber(reaper.GetExtState(extname, 'mode_dc')) or 4

local _, file_name = reaper.get_action_context()
local sep = reaper.GetOS():match('win') and '\\' or '/'
file_name = file_name:gsub('.+' .. sep, '')
local undo_name = 'FMagic: ' .. file_name:gsub('.+-%s', ''):gsub('%..+', '')
file_name = file_name:lower()

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
    folder_id = file_name:match(' folder (.-)%.')
    track_id = file_name:match(' track (.-)%.')
end
-- Get track or folder id from user dialog
local is_dialog = file_name:match('dialog') ~= nil
if is_dialog then
    local msg = 'Folder: (name or number),Track: (name or number)'
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

local is_next
local is_prev
if (not folder_id or folder_id == '') and (not track_id or track_id == '') then
    is_next = file_name:match('next') ~= nil
    is_prev = file_name:match('previous') ~= nil
    if not is_next and not is_prev then
        -- Zoom out all
        mode_sc = -1
        mode_dc = -2
    end
end

-- Check double click to determine mode
local mode = mode_sc

local prev_timestamp = tonumber(reaper.GetExtState(extname, 'timestamp'))
local prev_folder_id = reaper.GetExtState(extname, 'folder_id')
local prev_track_id = reaper.GetExtState(extname, 'track_id')

local timestamp = reaper.time_precise()

if tostring(folder_id) == prev_folder_id and tostring(track_id) == prev_track_id then
    if prev_timestamp and timestamp - prev_timestamp < 0.35 then
        if not is_next and not is_prev then
            -- Switch zoom mode
            mode = mode_dc
        end
    end
end
reaper.SetExtState(extname, 'timestamp', timestamp, false)
reaper.SetExtState(extname, 'folder_id', tostring(folder_id), false)
reaper.SetExtState(extname, 'track_id', tostring(track_id), false)

local all_tracks = {}
for i = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, i)
    if getTrackInfoValue(track, 'B_SHOWINTCP') == 1 then
        all_tracks[#all_tracks + 1] = track
    end
end

if #all_tracks == 0 then
    reaper.Undo_EndBlock(undo_name, -1)
    return
end

local main_track
local tracks = all_tracks

if is_next or is_prev then
    local curr_id = getCurrentFolderNum(tracks, min_depth, max_depth, use_tracks)
    folder_id = curr_id + (is_next and 1 or -1)
end

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

if not main_track then
    if mode > 0 then
        reaper.Undo_EndBlock(undo_name .. ' (not found)', -1)
        return
    end
    tracks = all_tracks
    main_track = all_tracks[1]
end

--------------------
local pinned_name = reaper.GetExtState(extname, 'pinned_name')
local pinned_track
local pinned_lock

-- Get pinned track
if pinned_name and pinned_name ~= '' then
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetTrackName(track, '')
        if track_name == pinned_name then
            pinned_track = track
        end
    end
end

if pinned_track then
    local track_num = getTrackInfoValue(tracks[1], 'IP_TRACKNUMBER')
    local pinned_num = getTrackInfoValue(pinned_track, 'IP_TRACKNUMBER')
    if pinned_num ~= track_num - 1 then
        reaper.PreventUIRefresh(1)
        -- Save current track selection
        local sel_tracks = {}
        for i = reaper.CountSelectedTracks(0) - 1, 0, -1 do
            local track = reaper.GetSelectedTrack(0, i)
            sel_tracks[#sel_tracks + 1] = track
            reaper.SetTrackSelected(track, false)
        end
        -- Reorder pinned track
        reaper.SetTrackSelected(pinned_track, true)
        reaper.ReorderSelectedTracks(track_num - 1, 0)
        reaper.SetTrackSelected(pinned_track, false)
        -- Restore track selection
        for _, track in ipairs(sel_tracks) do
            reaper.SetTrackSelected(track, true)
        end
        reaper.PreventUIRefresh(-1)
    end
    -- Lock pinned track
    pinned_lock = getTrackInfoValue(pinned_track, 'B_HEIGHTLOCK')
    setTrackInfoValue(pinned_track, 'B_HEIGHTLOCK', 1)
    -- Add pinned track to the beginning of track list
    local reorder_tracks = {pinned_track}
    for _, track in ipairs(tracks) do
        reorder_tracks[#reorder_tracks + 1] = track
    end
    tracks = reorder_tracks
end
----------------

-- Get main window properties
local main_hwnd = reaper.GetMainHwnd()
local main_id = reaper.JS_Window_FindChildByID(main_hwnd, 1000)
local _, page_pos, page_size = reaper.JS_Window_GetScrollInfo(main_id, 'v')
local view_start_pos, view_end_pos = reaper.GetSet_ArrangeView2(0, false, 0, 0)

if mode == -2 or mode == 2 or mode == 4 then
    -- Find index of last track that has visible items
    local last_vis_track_idx
    for i = #tracks, 1, -1 do
        local has_vis_items = hasVisibleItems(tracks[i], view_start_pos, view_end_pos)
        if not last_vis_track_idx and has_vis_items then
            last_vis_track_idx = i
        end
    end

    if last_vis_track_idx then
        local vis_tracks = {}
        -- Add all tracks after first visible track to list
        for i = 1, last_vis_track_idx do
            if #vis_tracks == 0 then
                local has_vis_items =
                    hasVisibleItems(tracks[i], view_start_pos, view_end_pos)
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
end

local diff = 0

if mode < 0 or mode == 3 or mode == 4 then
    local getEnvProps = reaper.BR_EnvGetProperties
    local setEnvProps = reaper.BR_EnvSetProperties

    local tracks_info = {}

    local track_min_height = tonumber(reaper.GetExtState(extname, 'min_height'))
    local armed_track_min_height = tonumber(reaper.GetExtState(extname, 'arm_min_height'))
    local theme = reaper.GetLastColorThemeFile()

    if not track_min_height or reaper.GetExtState(extname, 'theme') ~= theme then
        local last_vis_track = all_tracks[#all_tracks]
        track_min_height, armed_track_min_height = getTrackHeights(last_vis_track)
        reaper.SetExtState(extname, 'min_height', track_min_height, false)
        reaper.SetExtState(extname, 'arm_min_height', armed_track_min_height, false)
        reaper.SetExtState(extname, 'theme', theme, false)
    end

    local min_height_sum = 0
    local empty_lane_cnt = 0
    local full_lane_cnt = 0

    -- Gather information about tracks and envelopes
    for i, track in ipairs(tracks) do
        local info = {}
        info.height_lock = getTrackInfoValue(track, 'B_HEIGHTLOCK')
        -- Locked tracks are not touched
        if info.height_lock > 0 then
            local height = getTrackInfoValue(track, 'I_WNDH')
            min_height_sum = min_height_sum + height
        else
            -- Get minimum track height
            info.rec_arm = getTrackInfoValue(track, 'I_RECARM')
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
    diff = page_size - min_height_sum

    if diff > 0 then
        -- Calculate track height offsets that will be added to minimum height
        if mode == 4 and full_lane_cnt > 0 or emphasis_factor >= 10 then
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

    local avg_track_height = 0
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
            setTrackInfoValue(track, 'I_HEIGHTOVERRIDE', track_height)
            avg_track_height = avg_track_height + track_height
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

    avg_track_height = math.ceil(avg_track_height / #tracks)
    local first_track_num = getTrackInfoValue(tracks[1], 'IP_TRACKNUMBER')
    local last_track_num = getTrackInfoValue(tracks[#tracks], 'IP_TRACKNUMBER')

    -- Set rest of the tracks to an average height
    for i = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, i)
        local track_num = i + 1
        if track_num < first_track_num or track_num > last_track_num then
            local height_lock = getTrackInfoValue(track, 'B_HEIGHTLOCK')
            if height_lock == 0 then
                setTrackInfoValue(track, 'I_HEIGHTOVERRIDE', avg_track_height)
                local env_height = avg_track_height + 1
                for e = 0, reaper.CountTrackEnvelopes(track) - 1 do
                    local env = reaper.GetTrackEnvelope(track, e)
                    local br_env = reaper.BR_EnvAlloc(env, false)
                    local act, vis, arm, in_lane, _, ds, _, _, _, _, fs =
                        getEnvProps(br_env)
                    if vis then
                        setEnvProps(br_env, act, vis, arm, in_lane, env_height, ds, fs)
                    end
                    reaper.BR_EnvFree(br_env, true)
                end
            end
        end
    end
    reaper.TrackList_AdjustWindows(true)
end

if mode < 0 and diff <= 0 then
    -- Track: Vertical scroll selected tracks into view
    reaper.Main_OnCommand(40913, 0)
    reaper.TrackList_AdjustWindows(true)
    -- Make sure to not scroll past last track
    local last_track = tracks[#tracks]
    local tcp_y = getTrackInfoValue(last_track, 'I_TCPY')
    local wnd_h = getTrackInfoValue(last_track, 'I_WNDH')
    -- Scrolling is only necessary when the last track height is inside page_size
    if tcp_y + wnd_h < page_size then
        local diff = tcp_y + wnd_h - page_size
        reaper.JS_Window_SetScrollPos(main_id, 'v', page_pos + diff)
        reaper.TrackList_AdjustWindows(false)
        -- Note: Scrolling twice is necessary to ensure correct scroll
        local _, page_pos = reaper.JS_Window_GetScrollInfo(main_id, 'v')
        local tcp_y = getTrackInfoValue(last_track, 'I_TCPY')
        local diff = tcp_y + wnd_h - page_size
        reaper.JS_Window_SetScrollPos(main_id, 'v', page_pos + diff)
        reaper.TrackList_AdjustWindows(true)
    end
else
    -- Scroll to first track
    local tcp_y = getTrackInfoValue(tracks[1], 'I_TCPY')
    reaper.JS_Window_SetScrollPos(main_id, 'v', page_pos + tcp_y)
    reaper.TrackList_AdjustWindows(false)
    -- Note: Scrolling twice is necessary to ensure correct scroll
    local _, page_pos = reaper.JS_Window_GetScrollInfo(main_id, 'v')
    local tcp_y = getTrackInfoValue(tracks[1], 'I_TCPY')
    reaper.JS_Window_SetScrollPos(main_id, 'v', page_pos + tcp_y)
    reaper.TrackList_AdjustWindows(true)
end

if pinned_lock then
    setTrackInfoValue(pinned_track, 'B_HEIGHTLOCK', pinned_lock)
end

reaper.SetMixerScroll(main_track)
reaper.Undo_EndBlock(undo_name, -1)
