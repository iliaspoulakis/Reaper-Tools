--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @provides [main=main,midi_editor,mediaexplorer] .
  @about Links the media explorer file selection, time selection, pitch and
    volume to the focused sample player. The link is automatically broken when
    closing either the FX window or the media explorer.
]]

-- Avoid creating undo points
reaper.defer(function() end)

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_Find then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

-- Check if media explorer is open
local mx_title = reaper.JS_Localize('Media Explorer', 'common')
local mx = reaper.JS_Window_Find(mx_title, true)
if not mx then return end

local _, _, sec, cmd = reaper.get_action_context()

local title = 'Add Sampler'

local jsfx_path
local record_track
local editor_track
local editor_send

local exit_cnt = 0
local min_exit_cnt = 0

local note_lo, note_hi

reaper.gmem_attach('ftc_midi_note_monitor')
-- Note on
reaper.gmem_write(0, -1)
-- Note off
reaper.gmem_write(1, -1)
-- Note on count
reaper.gmem_write(2, 0)
-- Note off count
reaper.gmem_write(3, 0)
-- Current MIDI bus
reaper.gmem_write(3, 0)

-- A simple JSFX that saves information about played MIDI notes in gmem
local jsfx = [[
desc:MIDI note monitor
options:gmem=ftc_midi_note_monitor

slider1:-1<-1,127,1>Note on
slider2:-1<-1,127,1>Note off

@init
ext_midi_bus = 1;

@block

while (midirecv(offset, msg1, msg2, msg3))
(
    mask = msg1 & 0xF0;
    is_note_on = mask == 0x90 && msg2;
    is_note_off = mask == 0x80 || (mask == 0x90 && !msg2);

    is_note_on  ? (gmem[0] = msg2; slider1 = msg2; gmem[2] = gmem[2] + 1);
    is_note_off ? (gmem[1] = msg2; slider2 = msg2; gmem[3] = gmem[3] + 1);
    midisend(offset, msg1, msg2, msg3);
    gmem[4] = midi_bus;
);
]]

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function ConcatPath(...)
    local sep = package.config:sub(1, 1)
    return table.concat({...}, sep)
end

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

function MediaExplorer_GetSelectedAudioFiles()
    local path_hwnd = reaper.JS_Window_FindChildByID(mx, 1002)
    local path = reaper.JS_Window_GetTitle(path_hwnd)

    local mx_list_view = reaper.JS_Window_FindChildByID(mx, 1001)
    local _, sel_indexes = reaper.JS_ListView_ListAllSelItems(mx_list_view)

    local sep = package.config:sub(1, 1)
    local sel_files = {}
    local peaks = {}

    for index in string.gmatch(sel_indexes, '[^,]+') do
        index = tonumber(index)
        local file_name = reaper.JS_ListView_GetItem(mx_list_view, index, 0)
        if IsAudioFile(file_name) then
            sel_files[#sel_files + 1] = path .. sep .. file_name
            local peak = reaper.JS_ListView_GetItem(mx_list_view, index, 21)
            peaks[#peaks + 1] = tonumber(peak)
        end
    end

    return sel_files, peaks
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

function CreateJSFX()
    -- Determine path to Effects folder
    local res_dir = reaper.GetResourcePath()
    local path = ConcatPath(res_dir, 'Effects', 'ftc_midi_note_monitor.jsfx')

    -- Create new file
    local file = io.open(path, 'w')
    file:write(jsfx)
    file:close()
    return path
end

function CreateHiddenRecordTrack()
    reaper.PreventUIRefresh(-1)
    -- Add track at end of track list (to not change visible track indexes)
    local track_cnt = reaper.CountTracks()
    reaper.InsertTrackAtIndex(track_cnt, false)
    local track = reaper.GetTrack(0, track_cnt)

    -- Hide track in tcp and mixer
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINMIXER', 0)
    reaper.SetMediaTrackInfo_Value(track, 'B_SHOWINTCP', 0)

    -- Make it capture MIDI
    reaper.SetMediaTrackInfo_Value(track, 'I_RECARM', 1)
    reaper.SetMediaTrackInfo_Value(track, 'I_RECMODE', 2)
    reaper.SetMediaTrackInfo_Value(track, 'I_RECINPUT', 6112)

    reaper.PreventUIRefresh(-1)
    return track
end

function AddTrackFX(track, fx_name, allow_show, pos, is_rec_fx)
    pos = pos or 0
    is_rec_fx = is_rec_fx or false

    -- FX: Auto-float new FX windows
    local is_auto_float = reaper.GetToggleCommandState(41078) == 1

    -- Follow preference if allow_show is enabled (else hide)
    if not allow_show and is_auto_float then reaper.Main_OnCommand(41078, 0) end
    local instantiate = -1000 - pos
    local fx = reaper.TrackFX_AddByName(track, fx_name, is_rec_fx, instantiate)
    if not allow_show and is_auto_float then reaper.Main_OnCommand(41078, 0) end
    return fx
end

function IsSampler(track, fx)
    local _, parm3_name = reaper.TrackFX_GetParamName(track, fx, 3, '')
    local _, parm4_name = reaper.TrackFX_GetParamName(track, fx, 4, '')
    return parm3_name == 'Note range start' and parm4_name == 'Note range end'
end

function GetSamplerNoteRange(track, fx)
    local start_note = reaper.TrackFX_GetParamNormalized(track, fx, 3)
    local end_note = reaper.TrackFX_GetParamNormalized(track, fx, 4)
    return math.floor(start_note * 127 + 0.5), math.floor(end_note * 127 + 0.5)
end

function SetSamplerNoteRange(track, fx, start_note, end_note)
    reaper.TrackFX_SetParamNormalized(track, fx, 3, start_note / 127)
    reaper.TrackFX_SetParamNormalized(track, fx, 4, end_note / 127)
end

function OpenWindow()
    -- Show script window in center of screen
    gfx.clear = reaper.ColorToNative(37, 37, 37)
    local w, h = 350, 188
    local x, y = reaper.GetMousePosition()
    local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, x, y, x, y, 1)
    gfx.init(title, w, h, 0, (r + l - w) / 2, (b + t - h) / 2 - 24)
end

function DrawGUI()
    -- Determine text
    local text
    if note_lo then
        gfx.setfont(1, '', 26, string.byte('b'))
        if note_lo == note_hi then
            text = ('%d - ?'):format(note_lo)
        else
            text = ('%d - %d'):format(note_lo, note_hi)
        end
    else
        gfx.setfont(1, '', 22, string.byte('b'))
        text = 'Play a note!'
    end

    -- Draw text
    gfx.set(0.7)
    local t_w, t_h = gfx.measurestr(text)
    gfx.x = math.floor(gfx.w / 2 - t_w / 2 + 4)
    gfx.y = math.floor(gfx.h / 2 - t_h / 2)
    gfx.drawstr(text, 1)

    -- Draw circle
    gfx.set(0.5, 0.4, 0.6)
    gfx.circle(gfx.x - t_w - 12, gfx.y + t_h // 2, 5, 1, 1)
end

function Main()
    local note_on = reaper.gmem_read(0)
    local note_off = reaper.gmem_read(1)

    -- Exit script when window closes or escape key is triggered
    local char = gfx.getchar()
    if char == -1 or char == 27 then return end

    -- Exit script when window loses focus
    local has_focus = gfx.getchar(65536) == 7
    if not has_focus and note_on < 0 then exit_cnt = exit_cnt + 1 end
    if exit_cnt > min_exit_cnt and note_on < 0 then return end

    -- Set played note range
    if note_on >= 0 then
        note_lo = math.min(note_lo or note_on, note_on)
        note_hi = math.max(note_hi or note_on, note_on)
    end

    -- Wait for note off, so that user can set a range
    if note_off >= 0 then
        local note_on_cnt = reaper.gmem_read(2)
        local note_off_cnt = reaper.gmem_read(3)

        -- If a note on was found for each note off, add sampler
        if note_on_cnt == note_off_cnt then

            local track = reaper.GetSelectedTrack(0, 0)

            -- When MIDI was received through bus use the MIDI editor track
            local is_midi_bus = reaper.gmem_read(4) == 1
            if is_midi_bus and editor_track then track = editor_track end

            if not track then return end

            local files, peaks = MediaExplorer_GetSelectedAudioFiles()
            if not files[1] then return end

            reaper.Undo_BeginBlock()
            reaper.ClearAllRecArmed()
            -- Make track record and monitor MIDI
            reaper.SetMediaTrackInfo_Value(track, 'I_RECARM', 1)

            local rec_in = reaper.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
            if rec_in < 6112 then
                reaper.SetMediaTrackInfo_Value(track, 'I_RECINPUT', 6112)
            end

            local rec_mon = reaper.GetMediaTrackInfo_Value(track, 'I_RECMON')
            if rec_mon == 0 then
                reaper.SetMediaTrackInfo_Value(track, 'I_RECMON', 1)
            end

            local chain_pos = 0
            for fx = reaper.TrackFX_GetCount(track) - 1, 0, -1 do
                if IsSampler(track, fx) then
                    local start_note, end_note = GetSamplerNoteRange(track, fx)
                    -- Set position where new sampler will be added in chain
                    if start_note <= note_lo then
                        chain_pos = fx
                    end
                    -- Remove existing Sampler instances that overlap in the note range
                    if start_note <= note_hi and end_note >= note_lo then
                        reaper.TrackFX_Delete(track, fx)
                    end
                end
            end

            -- Add sampler
            local fx = AddTrackFX(track, 'ReaSamplOmatic5000', true, chain_pos)

            -- Set note range
            SetSamplerNoteRange(track, fx, note_lo, note_hi)

            -- Set mode to "semi tone shifted" if user played a range of notes
            local mode = note_lo == note_hi and 1 or 2
            reaper.TrackFX_SetNamedConfigParm(track, fx, 'MODE', mode)
            if mode == 2 then
                -- Set start pitch to center of range (less sound degradation)
                local center = note_lo + (note_hi - note_lo) // 2
                reaper.TrackFX_SetParamNormalized(track, fx, 5, center / 127)
            end

            -- Set files
            for _, file in ipairs(files) do
                reaper.TrackFX_SetNamedConfigParm(track, fx, '+FILE0', file)
            end
            reaper.TrackFX_SetNamedConfigParm(track, fx, 'DONE', '')

            -- Set volume
            local vol = MediaExplorer_GetVolume()
            if vol then
                if peaks[1] then
                    -- Normalize preview volume if peak volume has been calculated
                    local normalize = reaper.GetToggleCommandStateEx(32063,
                                                                     42182) == 1
                    if normalize then vol = vol - peaks[1] end
                end
                reaper.TrackFX_SetParamNormalized(track, fx, 0, DB2Slider(vol))
            end

            -- Set pitch
            local pitch = MediaExplorer_GetPitch()
            if pitch then
                reaper.TrackFX_SetParam(track, fx, 15, (pitch + 80) / 160)
            end

            -- Set time selection
            local ret, start_pos, end_pos = MediaExplorer_GetTimeSelection(true)
            if ret then
                local length = GetAudioFileLength(files[1])
                reaper.TrackFX_SetParam(track, fx, 13, start_pos / length)
                reaper.TrackFX_SetParam(track, fx, 14, end_pos / length)
            end

            local range = ('note %d'):format(note_lo)
            if note_lo ~= note_hi then
                range = ('notes %d-%d'):format(note_lo, note_hi)
            end
            reaper.Undo_EndBlock('Add sample player to ' .. range, -1)
            return
        end
    end

    DrawGUI()
    gfx.update()
    reaper.defer(Main)
end

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    if reaper.ValidatePtr(editor_track, 'MediaTrack*') then
        reaper.RemoveTrackSend(editor_track, 0, editor_send)
    end
    if reaper.ValidatePtr(record_track, 'MediaTrack*') then
        reaper.DeleteTrack(record_track)
    end
    os.remove(jsfx_path)
end

local sel_files = MediaExplorer_GetSelectedAudioFiles()
if #sel_files == 0 then
    reaper.MB('Selected file is invalid!', 'Error', 0)
    return
end

reaper.atexit(Exit)
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

jsfx_path = CreateJSFX()
record_track = CreateHiddenRecordTrack()
AddTrackFX(record_track, 'ftc_midi_note_monitor.jsfx')

local hwnd = reaper.MIDIEditor_GetActive()
local take = reaper.MIDIEditor_GetTake(hwnd)

if reaper.ValidatePtr(take, 'MediaItem_Take*') then
    editor_track = reaper.GetMediaItemTake_Track(take)
    editor_send = reaper.CreateTrackSend(editor_track, record_track)
    local SetSendInfoValue = reaper.SetTrackSendInfo_Value
    SetSendInfoValue(editor_track, 0, editor_send, 'I_SENDMODE', 1)
    SetSendInfoValue(editor_track, 0, editor_send, 'I_SRCCHAN', -1)
    -- Set destination track to MIDI bus 2 (to distinguish source)
    SetSendInfoValue(editor_track, 0, editor_send, 'I_MIDIFLAGS', 2 << 22)

    -- When the editor track is not armed there seems to be a latency
    -- until the note on is received (introduced by buffering?)
    -- That's why we don't immediately exit the script on focus loss
    if reaper.GetMediaTrackInfo_Value(editor_track, 'I_RECARM', 1) == 0 then
        min_exit_cnt = 10
    end
end

OpenWindow()
Main()
reaper.atexit(Exit)
