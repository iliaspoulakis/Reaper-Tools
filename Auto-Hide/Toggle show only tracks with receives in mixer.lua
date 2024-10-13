--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.1
  @about Temporarily show only tracks with receives in mixer
  @changelog
    - Restore mixer scroll position
]]

local extname = 'FTC.ToggleShowOnlyReceiveTracksMCP'
local _, _, sec, cmd = reaper.get_action_context()

local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(3) end

local GetTrackInfo = reaper.GetMediaTrackInfo_Value
local SetTrackInfo = reaper.SetMediaTrackInfo_Value

local scroll_track

function SaveTracksVisibilityState()
    local states = {}
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local guid = reaper.GetTrackGUID(track)

        local show_mcp = GetTrackInfo(track, 'B_SHOWINMIXER')

        local comp = 0
        local is_folder = GetTrackInfo(track, 'I_FOLDERDEPTH') == 1
        if is_folder and GetTrackInfo(track, 'I_SELECTED') == 0 then
            local _, chunk = reaper.GetTrackStateChunk(track, '')
            comp = chunk:match('\nBUSCOMP %d+ (%d+)')
            -- Expand folders in mixer
            if comp == '1' then
                chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 0', 1)
                reaper.SetTrackStateChunk(track, chunk)
            end
        end

        local state = ('%s:%d:%d'):format(guid, show_mcp, comp)
        states[#states + 1] = state
    end
    local states_str = table.concat(states, ';')
    reaper.SetProjExtState(0, extname, 'track_states', states_str)

    local track = reaper.GetMixerScroll()
    local scroll_guid = track and reaper.GetTrackGUID(track) or ''
    reaper.SetProjExtState(0, extname, 'mixer_scroll_guid', scroll_guid)
end

function RestoreTracksVisibilityState(states_str)
    local _, scroll_guid = reaper.GetProjExtState(0, extname, 'mixer_scroll_guid')
    for t = 0, reaper.CountTracks(0) - 1 do
        local track = reaper.GetTrack(0, t)
        local guid = reaper.GetTrackGUID(track)
        local pattern = guid:gsub('%-', '%%-') .. ':(%d):(%d):(%d)'

        local show_mcp, comp = states_str:match(pattern)
        show_mcp = tonumber(show_mcp) or 1
        SetTrackInfo(track, 'B_SHOWINMIXER', show_mcp)

        if comp == '1' then
            local _, chunk = reaper.GetTrackStateChunk(track, '')
            chunk = chunk:gsub('(\nBUSCOMP %d) %d', '%1 1', 1)
            reaper.SetTrackStateChunk(track, chunk)
        end

        if guid == scroll_guid then scroll_track = track end
    end
end

-- Restore track states
local _, states_str = reaper.GetProjExtState(0, extname, 'track_states')
if states_str ~= '' then
    reaper.Undo_BeginBlock()
    RestoreTracksVisibilityState(states_str)
    reaper.SetProjExtState(0, extname, 'track_states', '')
    reaper.SetProjExtState(0, extname, 'mixer_scroll_guid', '')
    reaper.TrackList_AdjustWindows(false)

    if scroll_track then reaper.SetMixerScroll(scroll_track) end

    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.Undo_EndBlock('Toggle show only tracks with receives', -1)
    return
end

local GetSendInfo = reaper.GetTrackSendInfo_Value

local function IsValidReceive(track, recv_idx)
    -- Check if send is post-fx / post fader
    local send_mode = GetSendInfo(track, -1, recv_idx, 'I_SENDMODE')
    if not (send_mode == 0 or send_mode == 3) then return false end
    -- Check if audio is sent from channels 1-2
    local src_chan = GetSendInfo(track, -1, recv_idx, 'I_SRCCHAN')
    if src_chan < 0 or src_chan >= 2 then return false end
    -- Check if audio is sent to channels 1-2 (avoid sidechains)
    local dest_chan = GetSendInfo(track, -1, recv_idx, 'I_DSTCHAN') & 511
    if dest_chan < 0 or dest_chan >= 2 then return false end
    return true
end

local receive_tracks = {}
-- Show selected tracks (and child tracks)
for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    local num_receives = reaper.GetTrackNumSends(track, -1)
    for i = 0, num_receives - 1 do
        if IsValidReceive(track, 0) then
            receive_tracks[#receive_tracks + 1] = track
            break
        end
    end
end

if #receive_tracks == 0 then
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.defer(function() end)
    return
end

reaper.Undo_BeginBlock()
SaveTracksVisibilityState()
reaper.SetToggleCommandState(sec, cmd, 1)

-- Hide all tracks
for t = 0, reaper.CountTracks(0) - 1 do
    local track = reaper.GetTrack(0, t)
    SetTrackInfo(track, 'B_SHOWINMIXER', 0)
end

-- Show only receive tracks
for _, track in ipairs(receive_tracks) do
    SetTrackInfo(track, 'B_SHOWINMIXER', 1)
end

reaper.TrackList_AdjustWindows(false)
reaper.Undo_EndBlock('Toggle show only tracks with receives', -1)
