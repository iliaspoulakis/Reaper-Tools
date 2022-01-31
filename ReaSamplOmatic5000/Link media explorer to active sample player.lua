--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.1.6
  @provides [main=main,mediaexplorer] .
  @about Inserts selected media explorer items into a new sample player on the
    next played note. Insertion target is either the selected track, or the track
    open in the MIDI editor (when clicking directly on the piano roll).
  @changelog
    - Fix issue with details/list view on Windows
]]

-- Avoid creating undo points
reaper.defer(function() end)

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_Find then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

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

local SetNamedConfigParm
local SetParamNormalized
local SetParam

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

    for index in string.gmatch(sel_indexes, '[^,]+') do
        index = tonumber(index)
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
            end

            -- Check if file_name is valid path itself (for searches and DBs)
            if not reaper.file_exists(file_name) then
                file_name = path .. sep .. file_name
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
    for index in string.gmatch(sel_indexes, '[^,]+') do
        index = tonumber(index)
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
    local vol_hwnd = reaper.JS_Window_FindChildByID(mx, 1047)
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
        SetParamNormalized(container, container_idx, 0, DB2Slider(vol))
    end

    -- Link pitch
    local pitch = MediaExplorer_GetPitch()
    if pitch then SetParam(container, container_idx, 15, (pitch + 80) / 160) end

    -- Link time selection
    local is_wave_preview_hovered = GetHoveredWindowID() == 1046
    local force_read = is_wave_preview_hovered or is_first_run
    local ret, start_pos, end_pos = MediaExplorer_GetTimeSelection(force_read)

    local is_init = not ret and is_first_run
    local has_file_changed = not is_first_run and prev_file ~= files[1]
    local user_removes_sel = not ret and is_wave_preview_hovered

    if not files[1] or is_init or has_file_changed or user_removes_sel then
        SetParam(container, container_idx, 13, 0)
        SetParam(container, container_idx, 14, 1)
    else
        if ret then
            local length = GetAudioFileLength(files[1])
            SetParam(container, container_idx, 13, start_pos / length)
            SetParam(container, container_idx, 14, end_pos / length)
        end
    end

    prev_file = files[1]
    is_first_run = false

    reaper.defer(Main)
end

function RefreshMXToolbar()
    -- Toggle any option to refresh MX toolbar
    reaper.JS_Window_OnCommand(mx, 42171)
    reaper.JS_Window_OnCommand(mx, 42171)
end

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    RefreshMXToolbar()
end

reaper.atexit(Exit)
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)
RefreshMXToolbar()

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
        SetParamNormalized = reaper.TakeFX_SetParamNormalized
        SetParam = reaper.TakeFX_SetParam
    else
        GetFloatingWindow = reaper.TrackFX_GetFloatingWindow
        GetChainVisible = reaper.TrackFX_GetChainVisible
        GetParamName = reaper.TrackFX_GetParamName
        GetNamedConfigParm = reaper.TrackFX_GetNamedConfigParm
        SetNamedConfigParm = reaper.TrackFX_SetNamedConfigParm
        SetParamNormalized = reaper.TrackFX_SetParamNormalized
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

