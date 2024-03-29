--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.2
  @about Hides tracks in the TCP that have no items in the current measure
  @changelog
    - Improve behavior when adding new tracks while script is running
]]
-- Exceptions: Track names separated by ; (e.g. "My track 1;My track 2")
_G.always_visible_tracks = ''
_G.always_hidden_tracks = ''
------------------------------------------------------------------------

local extname = 'FTC.AutoHideItemTCP'
local GetTrackInfo = reaper.GetMediaTrackInfo_Value
local SetTrackInfo = reaper.SetMediaTrackInfo_Value

-- Parse exceptions
local vis_track_names = {}
local hidden_track_names = {}

for track_name in (_G.always_visible_tracks .. ';'):gmatch('(.-);') do
    vis_track_names[#vis_track_names + 1] = track_name
end

for track_name in (_G.always_hidden_tracks .. ';'):gmatch('(.-);') do
    hidden_track_names[#hidden_track_names + 1] = track_name
end

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function SaveTracksVisibilityState()
    local states = {}
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local guid = reaper.GetTrackGUID(track)

        local show_tcp = GetTrackInfo(track, 'B_SHOWINTCP')

        local state = ('%s:%d'):format(guid, show_tcp)
        states[#states + 1] = state
    end
    local states_str = table.concat(states, ';')
    reaper.SetProjExtState(0, extname, 'track_states', states_str)
end

function RestoreTracksVisibilityState()
    -- Restore track states
    local _, states_str = reaper.GetProjExtState(0, extname, 'track_states')
    if states_str == '' then return end

    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local guid = reaper.GetTrackGUID(track)
        local pattern = guid:gsub('%-', '%%-') .. ':(%d)'

        local show_tcp = states_str:match(pattern)
        show_tcp = tonumber(show_tcp) or 1
        SetTrackInfo(track, 'B_SHOWINTCP', show_tcp)
    end
    reaper.SetProjExtState(0, extname, 'track_states', '')
end

function HasItemsInMeasure(track, measure)
    local ret, track_name = reaper.GetTrackName(track)
    if ret then
        -- Check track name for exceptions
        for _, name in ipairs(vis_track_names) do
            if name == track_name then return true end
        end
        for _, name in ipairs(hidden_track_names) do
            if name == track_name then return false end
        end
    end

    local measure_start_pos = reaper.TimeMap_GetMeasureInfo(0, measure)
    local measure_end_pos = reaper.TimeMap_GetMeasureInfo(0, measure + 1)

    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
        local start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
        local end_pos = start_pos + length

        if start_pos > measure_end_pos then break end
        if start_pos <= measure_end_pos and end_pos >= measure_start_pos then
            return true
        end
    end
end

local prev_measure

function Main()
    local cursor_pos = reaper.GetCursorPosition()
    if reaper.GetPlayState() > 0 then cursor_pos = reaper.GetPlayPosition() end
    local _, cursor_measure = reaper.TimeMap2_timeToBeats(0, cursor_pos)

    if cursor_measure ~= prev_measure then
        prev_measure = cursor_measure

        local is_update = false
        for t = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, t)
            local is_visible = HasItemsInMeasure(track, cursor_measure)
            local vis_state = is_visible and 1 or 0

            if vis_state ~= GetTrackInfo(track, 'B_SHOWINTCP') then
                SetTrackInfo(track, 'B_SHOWINTCP', vis_state)
                is_update = true
            end
        end

        if is_update then
            reaper.TrackList_AdjustWindows(true)
        end
    end

    reaper.defer(Main)
end

local _, _, sec, cmd = reaper.get_action_context()
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    RestoreTracksVisibilityState()
    reaper.TrackList_AdjustWindows(true)
end

SaveTracksVisibilityState()

reaper.atexit(Exit)
reaper.defer(Main)
