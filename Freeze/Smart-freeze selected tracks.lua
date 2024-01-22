--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.1
  @noindex
  @about Configurable freeze action
]]
if not reaper.SNM_GetIntConfigVar then
    reaper.MB('Please install SWS extension', 'Error', 0)
    return
end

local extname = 'FTC.SmartFreeze'

-- Unlock items after freezing
local is_unlock = reaper.GetExtState(extname, 'is_unlock') ~= 'no'

-- Render tail length in ms
local render_tail = reaper.GetExtState(extname, 'render_tail')
render_tail = tonumber(render_tail) or 2000

-- Names of FX that need to be rendered in realtime
local realtime_fx = reaper.GetExtState(extname, 'realtime_fx')
local realtime_fx_names = {}
for fx in (realtime_fx .. ';'):gmatch('(.-);') do
    if fx ~= '' then realtime_fx_names[#realtime_fx_names + 1] = fx end
end

-- Freeze up to first instrument
local instr_freeze = reaper.GetExtState(extname, 'instr_freeze')
local user_wants_instr_freeze = instr_freeze ~= 'no'
if instr_freeze == '' or instr_freeze == 'ask' then
    user_wants_instr_freeze = nil
end

function IsItemMono(item)
    local take = reaper.GetActiveTake(item)
    local src = reaper.GetMediaItemTake_Source(take)
    local src_len = reaper.GetMediaSourceLength(src)

    local num_channels = reaper.GetMediaSourceNumChannels(src)
    if num_channels == 1 then return true end

    -- Note: Only a few samples should be necessary to determine difference
    local rate = 100
    local ch_spl_cnt = math.ceil(rate * src_len)
    ch_spl_cnt = math.min(ch_spl_cnt, 500)

    -- Make sure that enought peaks are built for comparison
    if reaper.PCM_Source_BuildPeaks(src, 0) ~= 0 then
        for _ = 1, 5 do
            reaper.PCM_Source_BuildPeaks(src, 1)
        end
    end

    local ch = 2
    local buf = reaper.new_array(ch_spl_cnt * ch * 2)
    local ret = reaper.PCM_Source_GetPeaks(src, rate, 0, ch, ch_spl_cnt, 0, buf)
    local spl_cnt = (ret & 0xfffff) * ch

    -- If all peaks are the same, file is mono
    local is_mono = spl_cnt > 0
    for i = 1, spl_cnt, 2 do
        if buf[i] ~= buf[i + 1] then
            is_mono = false
            break
        end
    end
    return is_mono
end

function GetLastInstrument(track)
    local instr_fx = reaper.TrackFX_GetInstrument(track)
    for fx = instr_fx + 1, reaper.TrackFX_GetCount(track) - 1 do
        local _, fx_type = reaper.TrackFX_GetNamedConfigParm(track, fx, 'fx_type')
        if fx_type:match('i$') then instr_fx = fx end
    end
    return instr_fx
end

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local GetItemInfo = reaper.GetMediaItemInfo_Value
local item_guids = {}
local item_bounds = {}
local is_realtime = false

local fx_backup_tracks

local sel_track_cnt = reaper.CountSelectedTracks(0)
for t = 0, sel_track_cnt - 1 do
    local track = reaper.GetSelectedTrack(0, t)

    local fx_cnt = reaper.TrackFX_GetCount(track)
    local instr_fx = GetLastInstrument(track)

    local freeze_up_to_fx
    if instr_fx >= 0 and instr_fx < fx_cnt - 1 then
        if user_wants_instr_freeze == nil then
            user_wants_instr_freeze = false
            local msg = 'Only freeze instruments?'
            local ret = reaper.MB(msg, 'Smart-Freeze', 3)
            if ret == 6 then
                freeze_up_to_fx = instr_fx
                user_wants_instr_freeze = true
            end
            if ret == 2 then
                reaper.Undo_EndBlock('Smart-freeze tracks (cancel)', -1)
                reaper.PreventUIRefresh(-1)
                return
            end
        end
        if user_wants_instr_freeze then
            freeze_up_to_fx = instr_fx
        end
    end

    if freeze_up_to_fx then
        -- Add track at end of track list
        local track_cnt = reaper.CountTracks()
        reaper.InsertTrackAtIndex(track_cnt, false)
        local fx_track = reaper.GetTrack(0, track_cnt)

        fx_backup_tracks = fx_backup_tracks or {}
        fx_backup_tracks[track] = fx_track

        -- Hide track in tcp and mixer
        reaper.SetMediaTrackInfo_Value(fx_track, 'B_SHOWINMIXER', 0)
        reaper.SetMediaTrackInfo_Value(fx_track, 'B_SHOWINTCP', 0)
        -- Move FX to hidden fx track
        for i = fx_cnt, freeze_up_to_fx + 1, -1 do
            reaper.TrackFX_CopyToTrack(track, i, fx_track, 0, true)
        end
    end

    item_bounds[track] = {}
    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local _, guid = reaper.GetSetMediaItemInfo_String(item, 'GUID', '', 0)
        item_guids[guid] = true

        local lane = GetItemInfo(item, 'I_FIXEDLANE') or 0
        local length = GetItemInfo(item, 'D_LENGTH')
        local start_pos = GetItemInfo(item, 'D_POSITION')
        local end_pos = start_pos + length
        local bounds = {lane = lane, start_pos = start_pos, end_pos = end_pos}
        table.insert(item_bounds[track], bounds)
    end

    -- Check track for realtime FX instances
    for fx = 0, reaper.TrackFX_GetCount(track) - 1 do
        if reaper.TrackFX_GetEnabled(track, fx) then
            local _, fx_name = reaper.TrackFX_GetFXName(track, fx, '')
            for _, name in ipairs(realtime_fx_names) do
                if fx_name:lower():match(name:lower()) then
                    is_realtime = true
                end
            end
        end
    end
end

local prev_render_tail = reaper.SNM_GetIntConfigVar('rendertail', 0)
local prev_work_render = reaper.SNM_GetIntConfigVar('workrender', 0)

-- Set render tail length to user value
reaper.SNM_SetIntConfigVar('rendertail', render_tail)

local work_render = prev_work_render
local is_include_tail = prev_work_render & 64 == 64
-- Uncheck option to "Include tail when freezing entire tracks"
if is_include_tail then work_render = work_render - 64 end
-- Limit render speed to realtime
if is_realtime then work_render = work_render | 8 end
reaper.SNM_SetIntConfigVar('workrender', work_render)

-- Track: Freeze to stereo (render pre-fader, save/remove items and online FX)
reaper.Main_OnCommand(41223, 0)

-- Restore settings
reaper.SNM_SetIntConfigVar('rendertail', prev_render_tail)
reaper.SNM_SetIntConfigVar('workrender', prev_work_render)

if fx_backup_tracks then
    for freeze_track, fx_track in pairs(fx_backup_tracks) do
        local fx_cnt = reaper.TrackFX_GetCount(fx_track)
        -- Move back FX from hidden fx track
        for i = 0, fx_cnt - 1 do
            reaper.TrackFX_CopyToTrack(fx_track, 0, freeze_track, fx_cnt + i, 1)
        end
        reaper.DeleteTrack(fx_track)
    end
end

for t = 0, reaper.CountSelectedTracks(0) - 1 do
    local track = reaper.GetSelectedTrack(0, t)

    for i = 0, reaper.CountTrackMediaItems(track) - 1 do
        local item = reaper.GetTrackMediaItem(track, i)
        local _, guid = reaper.GetSetMediaItemInfo_String(item, 'GUID', '', 0)

        -- Check item item existed before freeze (e.g. user cancelled process)
        if not item_guids[guid] then
            -- Unlock item after freezing
            if is_unlock then
                reaper.SetMediaItemInfo_Value(item, 'C_LOCK', 0)
            end

            local is_item_extended = true

            local lane = GetItemInfo(item, 'I_FIXEDLANE') or 0
            local length = GetItemInfo(item, 'D_LENGTH')
            local start_pos = GetItemInfo(item, 'D_POSITION')
            local end_pos = start_pos + length

            for _, bounds in ipairs(item_bounds[track]) do
                if bounds.start_pos == start_pos and bounds.end_pos == end_pos then
                    if bounds.lane == lane then
                        is_item_extended = false
                        break
                    end
                end
            end

            if is_item_extended then
                -- Restore pre-freeze item length (remove tail)
                local length_without_tail = length - render_tail / 1000
                reaper.SetMediaItemLength(item, length_without_tail, true)
            end

            if IsItemMono(item) then
                -- Show only left item channel
                local take = reaper.GetActiveTake(item)
                reaper.SetMediaItemTakeInfo_Value(take, 'I_CHANMODE', 3)
                reaper.UpdateItemInProject(item)
            end
        end
    end
end

reaper.PreventUIRefresh(-1)
reaper.Undo_EndBlock('Smart-freeze tracks', -1)
