--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.1
  @about Hides silent tracks during playback
  @changelog
    - Improve behavior when adding new tracks while script is running
]]
-- Volume threshold at which track is shown
_G.peak_threshold = 0.005
-- Release time in defer cycles (30 cycles is about 1 second)
_G.release_time = 65
------------------------------------------------------------------------

local extname = 'FTC.AutoHideSilent'
local GetTrackInfo = reaper.GetMediaTrackInfo_Value
local SetTrackInfo = reaper.SetMediaTrackInfo_Value

local freeze_controls = {'volume', 'pan', 'mute', 'solo'}

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function SaveTracksVisibilityState()
    local states = {}
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local guid = reaper.GetTrackGUID(track)

        local show_tcp = GetTrackInfo(track, 'B_SHOWINTCP')
        local show_mcp = GetTrackInfo(track, 'B_SHOWINMIXER')

        local comp = 0
        local is_folder = GetTrackInfo(track, 'I_FOLDERDEPTH') == 1
        if is_folder then
            local _, chunk = reaper.GetTrackStateChunk(track, '')
            comp = chunk:match('\nBUSCOMP %d+ (%d+)')
            -- Expand folders in mixer
            if comp == '1' then
                chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 0', 1)
                reaper.SetTrackStateChunk(track, chunk)
            end
        end

        local state = ('%s:%d:%d:%d'):format(guid, show_tcp, show_mcp, comp)
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
        local pattern = guid:gsub('%-', '%%-') .. ':(%d):(%d):(%d)'

        local show_tcp, show_mcp, comp = states_str:match(pattern)
        show_tcp = tonumber(show_tcp) or 1
        show_mcp = tonumber(show_mcp) or 1
        SetTrackInfo(track, 'B_SHOWINTCP', show_tcp)
        SetTrackInfo(track, 'B_SHOWINMIXER', show_mcp)

        if comp == '1' then
            local _, chunk = reaper.GetTrackStateChunk(track, '')
            chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 1', 1)
            reaper.SetTrackStateChunk(track, chunk)
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
            reaper.TrackList_AdjustWindows(false)
            reaper.defer(Main)
            return
        else
            SaveTracksVisibilityState()
            is_update = true
        end
    end

    if play_state == 0 then
        reaper.defer(Main)
        return
    end

    -- Count down timers
    for t = 1, track_cnt do
        timers[t] = timers[t] or 0
        if timers[t] > 0 then
            timers[t] = timers[t] - 1
            if timers[t] == 0 then is_update = true end
        end
    end

    -- Freeze auto-hide when hovering over specific controls
    local x, y = reaper.GetMousePosition()
    local _, hovered_control = reaper.GetThingFromPoint(x, y)
    for _, control in ipairs(freeze_controls) do
        if hovered_control:match('^[mt]cp%.' .. control) then
            reaper.defer(Main)
            return
        end
    end

    for t = 1, track_cnt do
        local track = reaper.GetTrack(0, t - 1)
        local peak_l = reaper.Track_GetPeakInfo(track, 0)
        local peak_r = reaper.Track_GetPeakInfo(track, 1)
        local peak = math.max(peak_l, peak_r)

        if peak > peak_threshold then
            timers[t] = release_time
        end

        local is_visible = timers[t] > 0
        local vis_state = is_visible and 1 or 0

        if vis_state ~= GetTrackInfo(track, 'B_SHOWINTCP') then
            SetTrackInfo(track, 'B_SHOWINTCP', vis_state)
            is_update = true
        end
        if vis_state ~= GetTrackInfo(track, 'B_SHOWINMIXER') then
            SetTrackInfo(track, 'B_SHOWINMIXER', vis_state)
            is_update = true
        end
    end

    if is_update then
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

reaper.atexit(Exit)
reaper.defer(Main)
