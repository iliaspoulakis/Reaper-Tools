--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @about Hides silent tracks from TCP during playback
]]
-- Volume threshold at which track is shown
_G.peak_threshold = 0.005
-- Release time in defer cycles (30 cycles is about 1 second)
_G.release_time = 65
------------------------------------------------------------------------

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

        local state = ('%s:%d'):format(track_guid, visible)
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

        local visible = states_str:match(track_guid .. ':(%d)')
        if visible then
            SetTrackInfoValue(track, 'B_SHOWINTCP', tonumber(visible))
        end
    end
    reaper.SetProjExtState(0, extname, 'track_states', '')
end

local prev_play_state
local timers = {}

function Main()
    local is_update = false
    local track_cnt = reaper.CountTracks(0)
    local play_state = reaper.GetPlayState()

    if play_state ~= prev_play_state then
        prev_play_state = play_state

        -- Reset timers
        timers = {}
        for t = 1, track_cnt do timers[t] = 0 end

        -- Save/Restore tracks visibility
        if play_state == 0 then
            RestoreTracksVisibilityState()
            reaper.TrackList_AdjustWindows(true)
            reaper.defer(Main)
            return
        else
            SaveTracksVisibilityState()
            is_update = true
        end
    end

    -- Count down timers
    for t = 1, track_cnt do
        if timers[t] > 0 then
            timers[t] = timers[t] - 1
            if timers[t] == 0 then is_update = true end
        end
    end

    if play_state == 0 then
        reaper.defer(Main)
        return
    end

    local x, y = reaper.GetMousePosition()
    local _, hover = reaper.GetThingFromPoint(x, y)
    if hover == 'tcp.volume' or hover == 'tcp.pan' then
        reaper.defer(Main)
        return
    end

    reaper.ClearConsole()
    for t = 1, track_cnt do
        local track = reaper.GetTrack(0, t - 1)
        local peak_l = reaper.Track_GetPeakInfo(track, 0)
        local peak_r = reaper.Track_GetPeakInfo(track, 1)
        local peak = math.max(peak_l, peak_r)

        if peak > peak_threshold then
            if timers[t] == 0 then is_update = true end
            timers[t] = release_time
        end

        local is_visible = timers[t] > 0
        SetTrackInfoValue(track, 'B_SHOWINTCP', is_visible and 1 or 0)
    end

    if is_update then
        reaper.TrackList_AdjustWindows(true)
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

reaper.atexit(Exit)
reaper.defer(Main)
