--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.3.1
  @provides [main=main,mediaexplorer] .
  @about Inserts selected media explorer items into a new sample player on the
    next played note. Insertion target is either the selected track, or the track
    open in the MIDI editor (when clicking directly on the piano roll).
  @changelog
    - Break link when using undo
]]

-- Comment out the next line to avoid turning off autoplay temporarily
local toggle_autoplay = reaper.GetToggleCommandStateEx(32063, 1011) == 1

-- Avoid creating undo points
reaper.defer(function() end)

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_Find then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version >= 7.03 then reaper.set_action_options(1) end

local vol_hwnd_id = version < 6.65 and 1047 or 997

-- Get media explorer window
local mx_title = reaper.JS_Localize('Media Explorer', 'common')
local mx = reaper.OpenMediaExplorer('', false)

local _, _, sec, cmd = reaper.get_action_context()

local is_first_run = true
local prev_file
local container, container_idx

local GetNamedConfigParm
local GetFloatingWindow
local GetChainVisible
local GetParamName
local GetParamNormalized
local GetParam

local SetNamedConfigParm
local SetParamNormalized
local SetParam

local undo_time
local undo_delay
local prev_idx

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function DB2Slider(val)
    return math.exp(val * 0.11512925464970228420089957273422) / 2
end

function Slider2DB(val)
    return math.log(val * 2) * 8.6858896380650365530225783783321
end

function IsAudioFile(file)
    local ext = file:match('%.([^.]+)$')
    if ext and reaper.IsMediaExtension(ext, false) then
        ext = ext:lower()
        if ext ~= 'xml' and ext ~= 'mid' and ext ~= 'rpp' then
            return true
        end
    end
end

function GetAudioFileLength(file)
    local source = reaper.PCM_Source_CreateFromFile(file)
    local length = reaper.GetMediaSourceLength(source)
    reaper.PCM_Source_Destroy(source)
    return length
end

function GetHoveredWindowID()
    local x, y = reaper.GetMousePosition()
    local hwnd = reaper.JS_Window_FromPoint(x, y)
    return reaper.JS_Window_GetLong(hwnd, 'ID', 0)
end

function MediaExplorer_GetSelectedAudioFiles()
    local show_full_path = reaper.GetToggleCommandStateEx(32063, 42026) == 1
    local show_leading_path = reaper.GetToggleCommandStateEx(32063, 42134) == 1
    local forced_full_path = false

    local path_hwnd = reaper.JS_Window_FindChildByID(mx, 1002)
    local path = reaper.JS_Window_GetTitle(path_hwnd)

    local mx_list_view = reaper.JS_Window_FindChildByID(mx, 1001)
    local _, sel_indexes = reaper.JS_ListView_ListAllSelItems(mx_list_view)

    local sep = package.config:sub(1, 1)
    local sel_files = {}

    for sel_index in string.gmatch(sel_indexes, '[^,]+') do
        local index = tonumber(sel_index)
        local file_name = reaper.JS_ListView_GetItem(mx_list_view, index, 0)
        -- File name might not include extension, due to MX option
        local ext = reaper.JS_ListView_GetItem(mx_list_view, index, 3)
        if ext ~= '' and not file_name:match('%.' .. ext .. '$') then
            file_name = file_name .. '.' .. ext
        end
        if IsAudioFile(file_name) then
            -- Check if file_name is valid path itself (for searches and DBs)
            if not reaper.file_exists(file_name) then
                file_name = path .. sep .. file_name
            end

            -- If file does not exist, try enabling option that shows full path
            if not show_full_path and not reaper.file_exists(file_name) then
                show_full_path = true
                forced_full_path = true
                -- Browser: Show full path in databases and searches
                reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42026, 0, 0, 0)
                file_name = reaper.JS_ListView_GetItem(mx_list_view, index, 0)
                if ext ~= '' and not file_name:match('%.' .. ext .. '$') then
                    file_name = file_name .. '.' .. ext
                end
            end
            sel_files[#sel_files + 1] = file_name
        end
    end

    -- Restore previous settings
    if forced_full_path then
        -- Browser: Show full path in databases and searches
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42026, 0, 0, 0)

        if show_leading_path then
            -- Browser: Show leading path in databases and searches
            reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42134, 0, 0, 0)
        end
    end

    return sel_files
end

function MediaExplorer_GetSelectedFileInfo(sel_file, id)
    if not sel_file or not id then return end
    local mx_list_view = reaper.JS_Window_FindChildByID(mx, 1001)
    local _, sel_indexes = reaper.JS_ListView_ListAllSelItems(mx_list_view)
    local sel_file_name = sel_file:match('([^\\/]+)$')
    for sel_index in string.gmatch(sel_indexes, '[^,]+') do
        local index = tonumber(sel_index)
        local file_name = reaper.JS_ListView_GetItem(mx_list_view, index, 0)
        -- File name might not include extension, due to MX option
        local ext = reaper.JS_ListView_GetItem(mx_list_view, index, 3)
        if not file_name:match('%.' .. ext .. '$') then
            file_name = file_name .. '.' .. ext
        end
        if file_name == sel_file_name then
            local info = reaper.JS_ListView_GetItem(mx_list_view, index, id)
            return info ~= '' and info
        end
    end
end

function MediaExplorer_GetVolume()
    local vol_hwnd = reaper.JS_Window_FindChildByID(mx, vol_hwnd_id)
    local vol = reaper.JS_Window_GetTitle(vol_hwnd)
    return tonumber(vol:match('[^%a]+'))
end

function MediaExplorer_GetPitch()
    local pitch_hwnd = reaper.JS_Window_FindChildByID(mx, 1021)
    local pitch = reaper.JS_Window_GetTitle(pitch_hwnd)
    return tonumber(pitch)
end

function MediaExplorer_GetTimeSelection(force_readout)
    if force_readout then
        -- Simulate mouse event on waveform to read out time selection
        local wave_hwnd = reaper.JS_Window_FindChildByID(mx, 1046)
        local x, y = reaper.GetMousePosition()
        local c_x, c_y = reaper.JS_Window_ScreenToClient(wave_hwnd, x, y)
        reaper.JS_WindowMessage_Send(wave_hwnd, 'WM_MOUSEFIRST', c_y, 0, c_x, 0)
    end

    -- If a time selection exists, it will be shown in the wave info window
    local wave_info_hwnd = reaper.JS_Window_FindChildByID(mx, 1014)
    local wave_info = reaper.JS_Window_GetTitle(wave_info_hwnd)
    local pattern = ': ([^%s]+) .-: ([^%s]+)'
    local start_timecode, end_timecode = wave_info:match(pattern)

    if not start_timecode then return false end

    -- Convert timecode to seconds
    local start_mins, start_secs = start_timecode:match('^(.-):(.-)$')
    start_secs = tonumber(start_secs) + tonumber(start_mins) * 60

    local end_mins, end_secs = end_timecode:match('^(.-):(.-)$')
    end_secs = tonumber(end_secs) + tonumber(end_mins) * 60

    -- Note: When no media file is loaded, start and end are both 0
    return start_secs ~= end_secs, start_secs, end_secs
end

function ScheduleUndoBlock(delay)
    undo_time = reaper.time_precise()
    undo_delay = math.min(undo_delay or math.maxinteger, delay)
end

function AddUndoBlock()
    if undo_time and reaper.time_precise() > undo_time + undo_delay then
        reaper.Undo_BeginBlock()
        reaper.Undo_EndBlock('Link sample player', -1)
        undo_time = nil
        undo_delay = nil
    end
end

function GetMIDIEvents()
    local idx, buf, ts, dev_id = reaper.MIDI_GetRecentInputEvent(0)
    prev_idx = prev_idx or 0
    if idx > prev_idx then
        local events = {}
        local new_idx = idx
        local i = 0
        repeat
            local msg = {}
            local len = #buf
            for n = 1, len do msg[n] = buf:byte(n) end
            events[i + 1] = {msg = msg, msg_len = len, ts = ts, dev_id = dev_id}
            i = i + 1
            idx, buf, _, dev_id = reaper.MIDI_GetRecentInputEvent(i)
        until idx == prev_idx
        prev_idx = new_idx
        return events
    end
end

function GetLastFocusedFXContainer()
    local ret, tnum, inum, fnum = reaper.GetFocusedFX2()

    local is_track_fx = ret & 1 == 1
    local is_item_fx = ret & 2 == 2

    if is_track_fx then
        local track
        if tnum == 0 then
            track = reaper.GetMasterTrack(0)
        else
            track = reaper.GetTrack(0, tnum - 1)
        end
        return track, fnum
    end

    if is_item_fx then
        local track = reaper.GetTrack(0, tnum - 1)
        local item = reaper.GetTrackMediaItem(track, inum)
        local tk = fnum >> 24
        local fx = fnum & 0xFFFFFF
        local take = reaper.GetMediaItemTake(item, tk)
        return take, fx
    end
end

function Main()
    --- Ensure hwnd for MX is valid (changes when docked etc.)
    if not reaper.ValidatePtr(mx, 'HWND') then
        mx = reaper.JS_Window_FindTop(mx_title, true)
        -- Exit script when media explorer is closed
        if not mx then return end
    end

    -- Stop link when container is invalid (project changes or delete)
    local is_container_take = reaper.ValidatePtr(container, 'MediaItem_Take*')
    local is_container_track = reaper.ValidatePtr(container, 'MediaTrack*')
    if not (is_container_take or is_container_track) then return end

    -- Stop link when floating/chain window closes (or chain selection changes)
    local floating_wnd = GetFloatingWindow(container, container_idx)
    local chain_idx = GetChainVisible(container)
    if not (floating_wnd or chain_idx == container_idx) then return end

    if not is_first_run and not undo_time then
        local redo = reaper.Undo_CanRedo2(0)
        if redo == 'Link sample player' then return end
    end

    -- Link files
    local files = MediaExplorer_GetSelectedAudioFiles()
    if #files > 0 then
        -- Check if files have changed (SetNamedConfigParm is CPU intensive)
        local file_cnt = math.min(64, #files)
        local have_files_changed = false

        local current_files = {}
        for f = file_cnt - 1, 0, -1 do
            local id = ('FILE%d'):format(f)
            local _, file = GetNamedConfigParm(container, container_idx, id)
            current_files[#current_files + 1] = file
        end

        for f = 1, file_cnt do
            if files[f] ~= current_files[f] then
                have_files_changed = true
                break
            end
        end

        -- Check if ReaSamplomatic contains more files
        local last_id = ('FILE%d'):format(file_cnt)
        local _, file = GetNamedConfigParm(container, container_idx, last_id)
        if file ~= '' then have_files_changed = true end

        -- Update files on change
        if have_files_changed then
            SetNamedConfigParm(container, container_idx, '-FILE*', '')
            for f = 1, file_cnt do
                SetNamedConfigParm(container, container_idx, '+FILE0', files[f])
            end
            SetNamedConfigParm(container, container_idx, 'DONE', '')
            ScheduleUndoBlock(1.2)
        end
    end

    -- Link volume
    local vol = MediaExplorer_GetVolume()
    if vol then
        -- Normalize preview volume if peak volume has been calculated
        local norm = reaper.GetToggleCommandStateEx(32063, 42182) == 1
        if norm then
            local peak = MediaExplorer_GetSelectedFileInfo(files[1], 21)
            if peak then vol = vol - peak end
        end
        local new_val = DB2Slider(vol)
        local curr_val = GetParamNormalized(container, container_idx, 0)

        if math.abs(curr_val - new_val) > 0.000001 then
            SetParamNormalized(container, container_idx, 0, new_val)
            ScheduleUndoBlock(0.6)
        end
    end

    -- Link pitch
    local pitch = MediaExplorer_GetPitch()
    if pitch then
        -- Note: When only using SetParam if value changed (checking with
        -- GetParam), the script creates undo points (why?)
        SetParam(container, container_idx, 15, (pitch + 80) / 160)
    end

    -- Link time selection
    local is_wave_preview_hovered = GetHoveredWindowID() == 1046
    local force_read = is_wave_preview_hovered or is_first_run
    local ret, start_pos, end_pos = MediaExplorer_GetTimeSelection(force_read)

    local is_init = not ret and is_first_run
    local has_file_changed = not is_first_run and prev_file ~= files[1]
    local user_removes_sel = not ret and is_wave_preview_hovered

    if not files[1] or is_init or has_file_changed or user_removes_sel then
        if GetParam(container, container_idx, 13) ~= 0 then
            SetParam(container, container_idx, 13, 0)
            ScheduleUndoBlock(0.6)
        end
        if GetParam(container, container_idx, 14) ~= 1 then
            SetParam(container, container_idx, 14, 1)
            ScheduleUndoBlock(0.6)
        end
    else
        if ret then
            local length = GetAudioFileLength(files[1])
            do
                local new_val = start_pos / length
                local curr_val = GetParam(container, container_idx, 13)

                if math.abs(curr_val - new_val) > 0.000001 then
                    SetParam(container, container_idx, 13, new_val)
                    ScheduleUndoBlock(0.6)
                end
            end
            do
                local new_val = end_pos / length
                local curr_val = GetParam(container, container_idx, 14)

                if math.abs(curr_val - new_val) > 0.000001 then
                    SetParam(container, container_idx, 14, new_val)
                    ScheduleUndoBlock(0.6)
                end
            end
        end
    end

    prev_file = files[1]
    is_first_run = false
    AddUndoBlock()

    reaper.defer(Main)

    -- Check if user played MIDI keyboard and mark file (when autoplay disabled)
    if not is_container_track then return end

    local is_autoplay = reaper.GetToggleCommandStateEx(32063, 1011) == 1
    if is_autoplay then return end

    local is_mark = reaper.GetToggleCommandStateEx(32063, 42167) == 1
    if not is_mark then return end

    local rec_in = reaper.GetMediaTrackInfo_Value(container, 'I_RECINPUT')
    local rec_arm = reaper.GetMediaTrackInfo_Value(container, 'I_RECARM')

    local is_recording_midi = rec_arm == 1 and rec_in & 4096 == 4096
    if not is_recording_midi then return end

    local events = GetMIDIEvents()
    if not events then return end

    -- Get file column entry with '+' mark
    if MediaExplorer_GetSelectedFileInfo(files[1], 15) then return end

    local dev_id = (rec_in >> 5) & 127
    local track_chan = rec_in & 31

    for _, event in ipairs(events) do
        if dev_id == 63 or dev_id == event.dev_id and event.msg_len == 3 then
            local msg1, msg2, msg3 = event.msg[1], event.msg[2], event.msg[3]
            -- Check if event is note on
            if msg1 & 0xF0 == 0x90 and msg3 > 0 then
                -- Check note channel
                local note_chan = (msg1 & 0x0F) + 1
                if track_chan == 0 or track_chan == note_chan then
                    -- Check sampler channel
                    local sampler_chan = GetParam(container, container_idx, 7)
                    sampler_chan = math.floor(sampler_chan * 16 + 0.5)
                    if sampler_chan == 0 or sampler_chan == note_chan then
                        -- Check sampler note range
                        local start_note = GetParam(container, container_idx, 3)
                        start_note = math.floor(start_note * 127 + 0.5)
                        local end_note = GetParam(container, container_idx, 4)
                        end_note = math.floor(end_note * 127 + 0.5)
                        if msg2 >= start_note and msg2 <= end_note then
                            reaper.JS_Window_OnCommand(mx, 42165)
                            return
                        end
                    end
                end
            end
        end
    end
end

function RefreshMXToolbar()
    -- Toggle any option to refresh MX toolbar
    reaper.JS_Window_OnCommand(mx, 42171)
    reaper.JS_Window_OnCommand(mx, 42171)
end

function Exit()
    if toggle_autoplay then reaper.JS_Window_OnCommand(mx, 40035) end
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    RefreshMXToolbar()
end

reaper.atexit(Exit)
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)
RefreshMXToolbar()

if toggle_autoplay then reaper.JS_Window_OnCommand(mx, 40036) end

--  Get the track ot take that "contains" the last touched fx
container, container_idx = GetLastFocusedFXContainer()

if container then
    -- Determine which functions will be used to get/set sampler values
    if reaper.ValidatePtr(container, 'MediaItem_Take*') then
        GetFloatingWindow = reaper.TakeFX_GetFloatingWindow
        GetChainVisible = reaper.TakeFX_GetChainVisible
        GetParamName = reaper.TakeFX_GetParamName
        GetNamedConfigParm = reaper.TakeFX_GetNamedConfigParm
        SetNamedConfigParm = reaper.TakeFX_SetNamedConfigParm
        GetParamNormalized = reaper.TakeFX_GetParamNormalized
        SetParamNormalized = reaper.TakeFX_SetParamNormalized
        GetParam = reaper.TakeFX_GetParam
        SetParam = reaper.TakeFX_SetParam
    else
        GetFloatingWindow = reaper.TrackFX_GetFloatingWindow
        GetChainVisible = reaper.TrackFX_GetChainVisible
        GetParamName = reaper.TrackFX_GetParamName
        GetNamedConfigParm = reaper.TrackFX_GetNamedConfigParm
        SetNamedConfigParm = reaper.TrackFX_SetNamedConfigParm
        GetParamNormalized = reaper.TrackFX_GetParamNormalized
        SetParamNormalized = reaper.TrackFX_SetParamNormalized
        GetParam = reaper.TrackFX_GetParam
        SetParam = reaper.TrackFX_SetParam
    end

    local _, parm3_name = GetParamName(container, container_idx, 3, '')
    local _, parm4_name = GetParamName(container, container_idx, 4, '')
    -- Check if focused fx window is instance of RS5K
    if parm3_name == 'Note range start' and parm4_name == 'Note range end' then
        Main()
        return
    end
end

reaper.MB('Please focus a sampler fx window', 'Error', 0)
