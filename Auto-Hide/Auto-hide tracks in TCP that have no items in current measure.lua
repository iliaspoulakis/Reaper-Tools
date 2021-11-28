--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Hides tracks in the TCP that have no items in the current measure
]]

local extname = 'FTC.AutoHideTCP'
local GetTrackInfoValue = reaper.GetMediaTrackInfo_Value
local SetTrackInfoValue = reaper.SetMediaTrackInfo_Value

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function SaveTracksVisibilityState()
    local states = {}
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local track_guid = reaper.GetTrackGUID(track)

        local visible = GetTrackInfoValue(track, 'B_SHOWINTCP')
        local compact = GetTrackInfoValue(track, 'I_FOLDERCOMPACT')

        local state = ('%s:%d:%d'):format(track_guid, visible, compact)
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
        local track_guid = reaper.GetTrackGUID(track)
        track_guid = track_guid:gsub('%-', '%%-')

        local visible, compact = states_str:match(track_guid .. ':(%d):(%d)')
        if visible then
            SetTrackInfoValue(track, 'B_SHOWINTCP', tonumber(visible))
            SetTrackInfoValue(track, 'I_FOLDERCOMPACT', tonumber(compact))
        end
    end
    reaper.SetProjExtState(0, extname, 'track_states', '')
end

function HasItemsInMeasure(track, measure)
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
        for t = 0, reaper.CountTracks(0) - 1 do
            local track = reaper.GetTrack(0, t)
            local visible = HasItemsInMeasure(track, cursor_measure) and 1 or 0
            SetTrackInfoValue(track, 'B_SHOWINTCP', visible)
        end
        reaper.TrackList_AdjustWindows(false)
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
    reaper.TrackList_AdjustWindows(false)
end

SaveTracksVisibilityState()

reaper.atexit(Exit)
reaper.defer(Main)
