--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.8.4
  @provides [main=main,mediaexplorer] .
  @about Simple tuner utility for the reaper media explorer
  @changelog
    - Improve CPU usage
]]
-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_Find then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version < 6.52 then
    reaper.MB('Please install REAPER v6.52 or later', 'MX Tuner', 0)
    return
end

if version >= 7.03 then reaper.set_action_options(1) end

-- Open media explorer window
local mx_title = reaper.JS_Localize('Media Explorer', 'common')
local mx = reaper.OpenMediaExplorer('', false)

local _, _, sec, cmd = reaper.get_action_context()

local char_flags = version >= 7.08 and 65537 or 65536

local w_x, w_y, w_w, w_h

local prev_mouse_x, prev_mouse_y
local prev_mouse_cap
local prev_h, prev_w
local prev_dock

local prev_color_theme
local prev_mx_pitch
local prev_mx_rate
local prev_use_rate
local prev_file_pitch
local sel_note_name

local prev_item
local prev_item_idx
local curr_file

local locked_key
local hovered_key

local is_pressed = false
local is_window_hover = false

local rate_mode
local pitch_mode
local algo_mode
local algo_window
local parse_meta_mode
local parse_name_mode

local frameless_mode
local focus_mode
local ontop_mode

local curr_parsing_mode = 0
local is_parsing_bypassed = false

local is_option_bypassed = false
local trigger_pitch_rescan = false

local flat = {'C', 'D', 'E', 'F', 'G', 'A', 'B'}
local sharp = {'C#', 'D#', 'F#', 'G#', 'A#'}
local theme = {}
local theme_id

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function GetSemitonesToA(f) return 12 * math.log(f / 440) / math.log(2) % 12 end

function GetMinSemitonesTo(f1, f2, semitone_offs)
    local dist = GetSemitonesToA(f2) - GetSemitonesToA(f1) + semitone_offs
    dist = dist < 0 and dist % 12 - 12 or dist % 12
    if dist > 6 or dist > 2 and f1 > 4400 then dist = dist - 12 end
    if dist < -6 or dist < -2 and f1 < 60 then dist = dist + 12 end
    return dist
end

function FrequencyToName(f, semitone_offs)
    local n = {'A', 'A#', 'B', 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#'}
    local dist = GetSemitonesToA(f) + (semitone_offs or 0)
    local dist_rnd = math.floor(dist + 0.5) % 12
    return n[dist_rnd + 1]
end

function NameToFrequency(name)
    local n = {'A', 'A#', 'B', 'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#'}

    if name == 'Db' then name = 'C#' end
    if name == 'Eb' then name = 'D#' end
    if name == 'Gb' then name = 'F#' end
    if name == 'Ab' then name = 'G#' end
    if name == 'Bb' then name = 'A#' end

    for i = 1, #n do
        if name == n[i] then
            return 440 * math.exp((i - 1) * math.log(2) / 12)
        end
    end
end

function GetMIDIFileRootName(file)
    local has_added_track = false
    local track = reaper.GetTrack(0, 0)

    -- Add track if project has no tracks
    if not track then
        has_added_track = true
        reaper.InsertTrackAtIndex(0, false)
        track = reaper.GetTrack(0, 0)
    end

    -- Add MIDI source to new take
    local src = reaper.PCM_Source_CreateFromFileEx(file, true)
    local src_len = reaper.GetMediaSourceLength(src)
    local item = reaper.AddMediaItemToTrack(track)
    local take = reaper.AddTakeToMediaItem(item)
    reaper.SetMediaItemTake_Source(take, src)

    -- Get lowest pitch in MIDI file (root)
    local min_pitch = math.maxinteger
    local _, note_cnt = reaper.MIDI_CountEvts(take)
    for n = 0, note_cnt - 1 do
        local ret, _, _, _, _, _, pitch = reaper.MIDI_GetNote(take, n)
        min_pitch = pitch < min_pitch and pitch or min_pitch
    end

    -- Convert pitch to note name
    local n = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}
    local root_name = min_pitch ~= math.maxinteger and n[min_pitch % 12 + 1]

    -- Clean up
    reaper.DeleteTrackMediaItem(track, item)
    if has_added_track then reaper.DeleteTrack(track) end

    return root_name
end

function IsMediaFile(file)
    local ext = file:match('%.([^.]+)$')
    if ext and reaper.IsMediaExtension(ext, false) then
        ext = ext:lower()
        if ext ~= 'xml' and ext ~= 'rpp' then return true end
    end
end

function MediaExplorer_GetFirstSelectedItem()
    local mx_list_view = reaper.JS_Window_FindChildByID(mx, 1001)
    local _, sel_indexes = reaper.JS_ListView_ListAllSelItems(mx_list_view)

    local index = tonumber(sel_indexes:match('[^,]+'))
    if not index then return end

    local item_name = reaper.JS_ListView_GetItem(mx_list_view, index, 0)
    return item_name, index
end

function MediaExplorer_GetMediaFileFromItemIndex(index)
    local mx_list_view = reaper.JS_Window_FindChildByID(mx, 1001)

    local file_name = reaper.JS_ListView_GetItem(mx_list_view, index, 0)
    -- File name might not include extension, due to MX option
    local ext = reaper.JS_ListView_GetItem(mx_list_view, index, 3)
    if ext ~= '' and not file_name:match('%.' .. ext .. '$') then
        file_name = file_name .. '.' .. ext
    end
    if not IsMediaFile(file_name) then return end

    local file_path = file_name
    -- Check if file_name is valid path itself (for searches and DBs)
    if not reaper.file_exists(file_path) then
        local path_hwnd = reaper.JS_Window_FindChildByID(mx, 1002)
        local path = reaper.JS_Window_GetTitle(path_hwnd)
        local sep = package.config:sub(1, 1)
        file_path = path .. sep .. file_path
    end

    local show_full_path = reaper.GetToggleCommandStateEx(32063, 42026) == 1
    -- If file does not exist, try enabling option that shows full path
    if not show_full_path and not reaper.file_exists(file_path) then
        -- Browser: Show full path in databases and searches
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42026, 0, 0, 0)
        file_path = reaper.JS_ListView_GetItem(mx_list_view, index, 0)
        if ext ~= '' and not file_path:match('%.' .. ext .. '$') then
            file_path = file_path .. '.' .. ext
        end
        -- Browser: Show full path in databases and searches
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42026, 0, 0, 0)
    end
    return file_path
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
            local info = reaper.JS_ListView_GetItemText(mx_list_view, index, id)
            return info ~= '' and info
        end
    end
end

function MediaExplorer_SetMetaDataKey(key)
    if version < 6.79 then
        reaper.MB('This feature requires REAPER v6.79 and above.', 'Error', 0)
        return
    end
    -- Edit metadata tag: Key
    reaper.JS_Window_OnCommand(mx, 42064)

    function HandleDialog()
        local title = reaper.JS_Localize('Edit metadata tag', 'common')
        local dialog_hwnd = reaper.JS_Window_Find(title, true)
        local edit_hwnd = reaper.JS_Window_FindChildByID(dialog_hwnd, 1007)

        -- Insert key name into text field
        reaper.JS_Window_SetTitle(edit_hwnd, key)

        -- Click OK button
        -- Note: This only works on Windows
        local ok_button_hwnd = reaper.JS_Window_FindChildByID(dialog_hwnd, 1)
        reaper.JS_WindowMessage_Send(ok_button_hwnd, 'WM_LBUTTONDOWN', 0, 0, 0, 0)
        reaper.JS_WindowMessage_Send(ok_button_hwnd, 'WM_LBUTTONUP', 0, 0, 0, 0)

        -- Press key: Enter
        -- Note: This only works on Linux
        reaper.JS_WindowMessage_Send(edit_hwnd, 'WM_KEYDOWN', 0x0D, 0, 0, 0)
        reaper.JS_WindowMessage_Send(edit_hwnd, 'WM_KEYUP', 0x0D, 0, 0, 0)

        locked_key = nil
        if rate_mode == 1 then
            MediaExplorer_SetRate(1)
        else
            MediaExplorer_SetPitch(0)
        end

        local cnt = 0
        function DelayRescan()
            if cnt == 1 then
                trigger_pitch_rescan = true
                return
            end
            cnt = cnt + 1
            reaper.defer(DelayRescan)
        end
        reaper.defer(DelayRescan)
    end

    reaper.defer(HandleDialog)
end

function MediaExplorer_GetPitch()
    local pitch_hwnd = reaper.JS_Window_FindChildByID(mx, 1021)
    local pitch = reaper.JS_Window_GetTitle(pitch_hwnd)
    return tonumber(pitch)
end

function MediaExplorer_SetPitch(pitch)
    local curr_pitch = MediaExplorer_GetPitch()
    local diff = math.abs(pitch - curr_pitch)
    local is_upwards = pitch > curr_pitch

    local semitones = math.floor(diff)
    local cents = math.floor(diff % 1 * 100 + 0.5)

    if is_upwards then
        for i = 1, cents do
            -- Preview: adjust pitch by +1 cents
            reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 40074, 0, 0, 0)
        end
        for i = 1, semitones do
            -- Preview: adjust pitch by +1 semitones
            reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42163, 0, 0, 0)
        end
    else
        for i = 1, cents do
            -- Preview: adjust pitch by -1 cents
            reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 40075, 0, 0, 0)
        end
        for i = 1, semitones do
            -- Preview: adjust pitch by -1 semitones
            reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42162, 0, 0, 0)
        end
    end
end

function MediaExplorer_GetRate()
    local rate_hwnd = reaper.JS_Window_FindChildByID(mx, 1454)
    local rate = reaper.JS_Window_GetTitle(rate_hwnd)
    return tonumber(rate)
end

function MediaExplorer_SetRate(rate)
    -- Set precise rate to rate textfield
    local rate_hwnd = reaper.JS_Window_FindChildByID(mx, 1454)
    local pattern = rate == 1 and ('%.1f') or ('%.3f')
    reaper.JS_Window_SetTitle(rate_hwnd, pattern:format(rate))
end

function IsPitchPreservedWhenChangingRate()
    return reaper.GetToggleCommandStateEx(32063, 40068) == 1
end

function TurnOffPreservePitchOption()
    -- Turn off option to preserve pitch when changing rate
    if reaper.GetToggleCommandStateEx(32063, 40068) == 1 then
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 40068, 0, 0, 0)
    end
end

function GetApproximatePeakTime(src, src_len)
    local rate = 1000
    local spl_cnt = math.ceil(rate * src_len)
    local buf = reaper.new_array(spl_cnt * 2)

    local ret = reaper.PCM_Source_GetPeaks(src, rate, 0, 1, spl_cnt, 0, buf)

    if not ret then return 0 end
    spl_cnt = (ret & 0xfffff)
    if spl_cnt == 0 then return 0 end

    buf = buf.table()

    local max_i = 0
    local max_val = 0

    for i = 1, spl_cnt do
        local val = buf[i]
        local val_abs = val < 0 and -val or val
        if val_abs > max_val then
            max_i = i
            max_val = val_abs
        end
    end

    return max_i / spl_cnt * src_len
end

function GetPitchFTC(file)
    -- Get media source peaks
    local src = reaper.PCM_Source_CreateFromFileEx(file, true)
    if not src then return end

    local src_len = reaper.GetMediaSourceLength(src)
    if src_len == 0 then
        reaper.PCM_Source_Destroy(src)
        return
    end

    -- Avoid processing more that 100 seconds of audio
    src_len = math.min(src_len, 100)

    -- We find the highest peak and set our time window there
    local time_window = math.min(src_len, algo_window)
    local soffs = GetApproximatePeakTime(src, src_len)
    soffs = soffs - time_window / 5
    if soffs + time_window > src_len then
        soffs = src_len - soffs
    end
    soffs = math.max(soffs, 0)

    -- Limit length of analyzed sample
    src_len = math.min(src_len, time_window)

    local rate = reaper.GetMediaSourceSampleRate(src)
    local spl_cnt = math.ceil(src_len * rate)
    spl_cnt = math.min(spl_cnt, 2 ^ 19)

    local buf = reaper.new_array(spl_cnt * 2)

    local ret = reaper.PCM_Source_GetPeaks(src, rate, 0, 1, spl_cnt, 0, buf)
    reaper.PCM_Source_Destroy(src)

    if not ret then return end
    spl_cnt = ret & 0xfffff
    if spl_cnt == 0 then return end

    buf = buf.table()

    -- Note: window size of 1 * rate = 1 sec
    local window_size = rate
    -- A higher peak threshold is better for detecting lower notes, vice versa
    local peak_thres = 0.25 -- [0.1 - 0.5]

    -- Determine sample start and end position
    local epos = math.min(window_size, spl_cnt)
    local spos = math.max(epos - window_size, 1)

    local zcross = {}
    local peak = 0
    local peak_since_last_zcross = 0

    -- Get zero crossings between sample start and end position
    for i = spos, epos do
        local val = buf[i]
        local val_abs = val < 0 and -val or val
        -- Keep track of the highest peak we have encountered
        if val_abs > peak then peak = val_abs end
        -- Keep track of the highest peak we have encountered since last crossing
        if val_abs > peak_since_last_zcross then
            peak_since_last_zcross = val_abs
        end

        -- Check if samples cross the zero line
        local next_val = buf[i + 1]
        local is_lo = val < 0 and next_val >= 0
        local is_hi = val > 0 and next_val <= 0
        if is_lo or is_hi then
            -- Filter out weak crossings (compared to current max peak)
            if peak_since_last_zcross > peak * peak_thres then
                -- Optimization: Instead of using the sample index i, we approximate
                -- the exact crossing point (inter-sample) using linear interpolation.
                local x1, y1, x2, y2 = i, val, i + 1, next_val
                local pos = x1 + y2 * (x2 - x1) / (y2 - y1)
                zcross[#zcross + 1] = {
                    i = i,
                    pos = pos,
                    is_hi = is_hi,
                    peak = peak_since_last_zcross,
                }
            end
            peak_since_last_zcross = 0
        end
    end

    local candidates = {}
    local overlaps = math.min(#zcross // 2, 18)

    -- Count occurences of lengths (in samples) between zero crossings. Repeat this
    -- process for a set window of overlaps (length between zero crossing A and B,
    -- A and C, A and D, etc.)

    for m = overlaps - 2, 0, -2 do
        local bins = {}
        local max_len, max_weight = 0, 0

        for i = 1, #zcross - (m + 2) do
            for n = m + 1, m + 2 do
                if zcross[i].is_hi == zcross[i + n].is_hi then
                    local len = zcross[i + n].pos - zcross[i].pos
                    local len_rnd = math.floor(len + 0.5)

                    -- Optimization: Instead of a simple count (+1), we weight the
                    -- count of zero crossings by using their related peak volume.
                    local zcross_peak = zcross[i].peak + zcross[i + n].peak
                    local weight = (bins[len_rnd] or 0) + zcross_peak
                    bins[len_rnd] = weight

                    if weight > max_weight then
                        max_len = len_rnd
                        max_weight = weight
                    end
                end
            end
        end

        -- Save the best candidate (highest count/weight) for each overlap iteration
        if max_weight > 0 then
            -- Optimization: Use parabolic interpolation to improve length precision
            local prev = bins[max_len - 1] or 0
            local next = bins[max_len + 1] or 0
            local diff = (next - prev) / (max_weight + prev + next)
            candidates[#candidates + 1] = {
                len = max_len + diff,
                weight = max_weight,
            }
        end
    end

    local max_weight = 0
    local best_c

    -- Find the best candidate
    for c = 1, #candidates do
        local curr_c = candidates[c]

        for e = 1, c - 1 do
            local prev_c = candidates[e]

            local factor = prev_c.len / curr_c.len
            local factor_rnd = math.floor(factor + 0.5)
            local diff = math.abs(factor - factor_rnd)

            -- Check if this candidate is a multiple of previous candidates
            if factor > 0.5 and diff < 0.1 then
                -- Add a portion of previous weight to this candidate
                local prev_weight = prev_c.new_weight or prev_c.weight
                curr_c.new_weight = curr_c.new_weight or curr_c.weight
                curr_c.new_weight = curr_c.new_weight + prev_weight / factor_rnd

                -- Optimization: Improve length (and frequency) accuracy
                if not curr_c.diff or diff < curr_c.diff then
                    local prev_len = prev_c.new_len or prev_c.len
                    curr_c.new_len = prev_len / factor_rnd
                end
            end
        end

        -- The best candidate is the one with the highest (modified) count/weight
        local curr_weight = curr_c.new_weight or curr_c.weight
        if curr_weight > max_weight then
            max_weight = curr_weight
            best_c = curr_c
        end
    end

    return best_c and (rate / (best_c.new_len or best_c.len))
end


function GetPitchFFT(file)
    -- Get media source peaks
    local src = reaper.PCM_Source_CreateFromFileEx(file, true)
    if not src then return end

    local src_len = reaper.GetMediaSourceLength(src)
    if src_len == 0 then
        reaper.PCM_Source_Destroy(src)
        return
    end

    -- Avoid processing more that 100 seconds of audio
    src_len = math.min(src_len, 100)

    -- We find the highest peak and set our time window there
    local time_window = math.min(src_len, algo_window)
    local soffs = GetApproximatePeakTime(src, src_len)
    soffs = soffs - time_window / 5
    if soffs + time_window > src_len then
        soffs = src_len - soffs
    end
    soffs = math.max(soffs, 0)

    -- Limit length of analyzed sample
    src_len = math.min(src_len, time_window)

    local rate = reaper.GetMediaSourceSampleRate(src)
    local spl_cnt = math.ceil(src_len * rate)
    spl_cnt = math.min(spl_cnt, 2 ^ 19)

    -- FFT window size has to be a power of 2
    local window_size = 2 ^ 15
    local buf = reaper.new_array(math.max(window_size, spl_cnt) * 2)

    local ret = reaper.PCM_Source_GetPeaks(src, rate, soffs, 1, spl_cnt, 0, buf)
    reaper.PCM_Source_Destroy(src)

    if not ret then return end
    spl_cnt = ret & 0xfffff
    if spl_cnt == 0 then return end

    -- Zero padding
    buf.clear(0, spl_cnt - 1)

    buf.fft(window_size, true)
    buf = buf.table()

    for i = 1, window_size do
        local re = buf[i]
        local im = buf[window_size * 2 - i]
        buf[i] = re * re + im * im
    end

    local max_val = 0
    local max_i
    for i = 1, window_size do
        local val = buf[i]
        local val_abs = val < 0 and -val or val
        if val_abs > max_val then
            max_i = i
            max_val = val_abs
        end
    end

    if not max_i then return end

    -- Look for fundamental harmonics
    local limit = window_size // 500
    for h = 7, 2, -1 do
        local i = max_i // h
        if max_i - i > limit and buf[i] ^ 0.5 > max_val ^ 0.5 * (0.05 * h) then
            max_i = i
        end
    end

    -- Use parabolic interpolation to improve precision
    local prev = buf[max_i - 1]
    local next = buf[max_i + 1]
    if prev and next then
        local diff = (next - prev) / (2 * (2 * max_val - prev - next))
        max_i = max_i + diff
    end

    return max_i * rate / window_size / 4
end

function GetPitchFromFileName(file)
    -- Parse note name from file name
    local pattern_pre = '([%s_[(-.])'
    local pattern_note = '([CDEFGAB][#b]?)'
    local pattern_add = '(%d?m?[Mmdas]?[aiduM]?[jnmds]?o?r?%d*)'
    local pattern_post = '([%s_[(-.])'
    local pattern = pattern_pre .. pattern_note .. pattern_add .. pattern_post

    local file_name = file:match('([^\\/]+)$')
    local file_note

    for pre, note, add, post in file_name:gmatch(pattern) do
        -- Note: Avoid patterns like 'Color B 12'
        -- if pre == ' ' and post == ' ' and add == '' then note = nil end
        if not file_note then file_note = note end
        -- Keep matches later in the item name (or longer e.g. with #)
        if note and #note >= #file_note then file_note = note end
    end

    -- Check if note is at beginning of file
    if not file_note then
        pattern = '^' .. pattern_note .. pattern_add .. pattern_post
        file_note = file_name:match(pattern)
    end
    return NameToFrequency(file_note)
end

function GetPitchFromMetadata(file)
    local key = MediaExplorer_GetSelectedFileInfo(file, 12)
    if key then
        -- Remove any digits from key
        key = key:gsub('%d', '')
        return NameToFrequency(key)
    end
end

function OpenWindow(is_docked)
    local pos = reaper.GetExtState('FTC.MXTuner', 'pos')
    if pos == '' then
        -- Show script window in center of screen
        local w, h = 406, 138
        local x, y = reaper.GetMousePosition()
        local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, x, y, x, y, 1)
        gfx.init('MX Tuner', w, h, 0, (r + l - w) / 2, (b + t - h) / 2 - 24)
    else
        w_x, w_y, w_w, w_h = pos:match('(%-?%d+) (%-?%d+) (%-?%d+) (%-?%d+)')
        -- Note: Matched type is string because of matching '-' for negative values
        w_w, w_h = tonumber(w_w), tonumber(w_h)
        w_x, w_y = tonumber(w_x), tonumber(w_y)

        local dock = 0
        if is_docked then
            dock = tonumber(reaper.GetExtState('FTC.MXTuner', 'dock'))
        end
        gfx.init('MX Tuner', w_w, w_h, dock, w_x, w_y)
    end

    if focus_mode == 1 then
        local mx_list_view = reaper.JS_Window_FindChildByID(mx, 1001)
        reaper.JS_Window_SetFocus(mx_list_view)
    end
end

function SetWindowFrame(has_frame)
    local is_linux = reaper.GetOS():match('Other')
    local hwnd = reaper.JS_Window_Find('MX Tuner', true)

    if has_frame then
        if is_linux then
            local bar_h = reaper.GetExtState('FTC.MXTuner', 'bar_h')
            if tonumber(bar_h) then
                reaper.JS_Window_SetPosition(hwnd, w_x, w_y, w_w, w_h - bar_h)
            end
        end
        reaper.JS_Window_SetStyle(hwnd, 'CAPTION,SIZEBOX,SYSMENU')
    else
        if is_linux then
            -- Match behavior of other platforms (extend window to titlebar)
            local _, s_y = gfx.clienttoscreen(0, 0)
            local bar_h = s_y - w_y
            reaper.SetExtState('FTC.MXTuner', 'bar_h', bar_h, true)
            reaper.JS_Window_SetPosition(hwnd, w_x, w_y, w_w, w_h + bar_h)
        end
        reaper.JS_Window_SetStyle(hwnd, 'POPUP')
    end
end

function SetWindowOnTop(is_ontop)
    local hwnd = reaper.JS_Window_Find('MX Tuner', true)
    local zorder = is_ontop and 'TOPMOST' or 'NOTOPMOST'
    reaper.JS_Window_SetZOrder(hwnd, zorder)
end

function HexToNormRGB(color)
    local r, g, b = reaper.ColorFromNative(color)
    return {r / 255, g / 255, b / 255}
end

function OffsetColor(color, offs)
    return {color[1] + offs, color[2] + offs, color[2] + offs}
end

function IsLightColor(color) return (color[1] + color[2] + color[3]) / 3 > 0.5 end

function GetColorLuminance(color)
    local r, g, b = color[1], color[2], color[3]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
end

function MatchColorLuminance(color, target_color)
    local lum = GetColorLuminance(color)
    local target_lum = GetColorLuminance(target_color)
    -- Note: Only adjust the luminance by 1/3
    local diff = (target_lum - lum) / 3
    return {color[1] + diff, color[2] + diff, color[3] + diff}
end

function LoadTheme(id)
    local is_docked = reaper.GetExtState('FTC.MXTuner', 'is_docked') == '1'
    local toolbar_color = HexToNormRGB(reaper.GetThemeColor('col_main_bg2'))
    theme.div_color = {0.08, 0.08, 0.08}
    if is_docked and GetColorLuminance(toolbar_color) > 0.2 then
        theme.div_color = toolbar_color or {0.08, 0.08, 0.08}
    end

    theme.button_color = {0.38, 0.51, 0.76}
    theme.button_bypass_color = {0.5, 0.5, 0.5}
    theme.button_text_color = {0.8, 0.8, 0.8}

    if id == 1 then
        -- Light theme
        theme.nat_color = {0.82, 0.82, 0.82}
        theme.nat_text_color = {0.14, 0.14, 0.14}
        theme.nat_hover_color = {0.73, 0.73, 0.73}
        theme.nat_sel_color = {0.61, 0.75, 0.38}
        theme.nat_lock_color = {0.72, 0.44, 0.41}
        theme.flat_color = {0.14, 0.14, 0.14}
        theme.flat_text_color = {0.82, 0.82, 0.82}
        theme.flat_hover_color = {0.21, 0.21, 0.21}
        theme.flat_sel_color = {0.53, 0.67, 0.31}
        theme.flat_lock_color = {0.65, 0.4, 0.37}
        return
    end

    if id == 2 then
        -- Dark theme
        theme.nat_color = {0.14, 0.14, 0.14}
        theme.nat_text_color = {0.82, 0.82, 0.82}
        theme.nat_hover_color = {0.21, 0.21, 0.21}
        theme.nat_sel_color = {0.45, 0.59, 0.23}
        theme.nat_lock_color = {0.61, 0.36, 0.33}
        theme.flat_color = {0.72, 0.72, 0.72}
        theme.flat_text_color = {0.14, 0.14, 0.14}
        theme.flat_hover_color = {0.71, 0.71, 0.71}
        theme.flat_sel_color = {0.59, 0.73, 0.36}
        theme.flat_lock_color = {0.72, 0.44, 0.41}
        return
    end

    if id == 3 then
        -- Reaper theme 1 : Uses piano key colors
        local nat_color = HexToNormRGB(reaper.GetThemeColor('midi_pkey1'))
        local flat_color = HexToNormRGB(reaper.GetThemeColor('midi_pkey2'))

        local nat_hover_offs = IsLightColor(nat_color) and -0.1 or 0.1
        local nat_hover_color = OffsetColor(nat_color, nat_hover_offs)

        local flat_hover_offs = IsLightColor(flat_color) and -0.1 or 0.1
        local flat_hover_color = OffsetColor(flat_color, flat_hover_offs)

        local sel_color = {0.61, 0.75, 0.38}
        local lock_color = {0.72, 0.44, 0.41}

        theme.nat_color = nat_color
        theme.nat_text_color = flat_color
        theme.nat_hover_color = nat_hover_color
        theme.nat_sel_color = MatchColorLuminance(sel_color, nat_color)
        theme.nat_lock_color = MatchColorLuminance(lock_color, nat_color)
        theme.flat_color = flat_color
        theme.flat_text_color = nat_color
        theme.flat_hover_color = flat_hover_color
        theme.flat_sel_color = MatchColorLuminance(sel_color, flat_color)
        theme.flat_lock_color = MatchColorLuminance(lock_color, flat_color)
        return
    end

    if id == 4 then
        -- Reaper theme 2 : Uses list view colors
        local nat_color = HexToNormRGB(reaper.GetThemeColor('genlist_bg'))
        local flat_color = HexToNormRGB(reaper.GetThemeColor('genlist_fg'))

        local flat_hover_offs = IsLightColor(flat_color) and -0.1 or 0.1
        local flat_hover_color = OffsetColor(flat_color, flat_hover_offs)

        local nat_hover_offs = IsLightColor(nat_color) and -0.1 or 0.1
        local nat_hover_color = OffsetColor(nat_color, nat_hover_offs)

        local sel_color = {0.61, 0.75, 0.38}
        local lock_color = {0.72, 0.44, 0.41}

        theme.nat_color = nat_color
        theme.nat_text_color = flat_color
        theme.nat_hover_color = nat_hover_color
        theme.nat_sel_color = MatchColorLuminance(sel_color, nat_color)
        theme.nat_lock_color = MatchColorLuminance(lock_color, nat_color)
        theme.flat_color = flat_color
        theme.flat_text_color = nat_color
        theme.flat_hover_color = flat_hover_color
        theme.flat_sel_color = MatchColorLuminance(sel_color, flat_color)
        theme.flat_lock_color = MatchColorLuminance(lock_color, flat_color)
        return
    end
end

function DrawPiano()
    local keys = {}

    local f_w = gfx.w // 7
    local f_h = gfx.h
    local m = 1

    for i = 1, 7 do
        keys[i] = {
            title = flat[i],
            x = (i - 1) * f_w + m,
            y = m,
            w = f_w - 2 * m,
            h = f_h - 2 * m,
            bg_color = theme.nat_color,
            text_color = theme.nat_text_color,
            hover_color = theme.nat_hover_color,
            sel_color = theme.nat_sel_color,
            lock_color = theme.nat_lock_color,
        }
        if i == 7 then
            local rest = gfx.w - f_w * 7
            keys[7].w = keys[7].w + rest
        end
    end

    local s_w = math.floor(0.67 * f_w)
    local s_h = math.floor((gfx.h < 70 and 0.57 or 0.67) * f_h)
    local s_x = {
        math.floor(1 * f_w - 0.75 * s_w),
        math.floor(2 * f_w - 0.25 * s_w),
        math.floor(4 * f_w - 0.75 * s_w),
        math.floor(5 * f_w - 0.50 * s_w),
        math.floor(6 * f_w - 0.25 * s_w),
    }

    for i = 1, 5 do
        keys[7 + i] = {
            title = sharp[i],
            x = s_x[i],
            y = m,
            w = s_w,
            h = s_h - 2 * m,
            bg_color = theme.flat_color,
            text_color = theme.flat_text_color,
            hover_color = theme.flat_hover_color,
            sel_color = theme.flat_sel_color,
            lock_color = theme.flat_lock_color,
            is_flat = true,
        }
    end

    local m_x, m_y = gfx.mouse_x, gfx.mouse_y

    hovered_key = nil
    if gfx.mouse_cap & 1 == 0 then is_pressed = false end

    local button_w = math.max(18, math.min(f_w // 4, gfx.h // 4))
    if curr_parsing_mode > 0 and m_x <= button_w and m_y <= button_w then
        local x, y = gfx.clienttoscreen(button_w // 0.6, button_w // 8)
        local tooltip_fn = 'Pitch detected via file name'
        local tooltip_md = 'Pitch detected via metadata'
        local tooltip_algo = 'Pitch detected via algorithm'
        local tooltip = curr_parsing_mode == 1 and tooltip_fn or tooltip_md
        if is_parsing_bypassed then tooltip = tooltip_algo end
        reaper.TrackCtl_SetToolTip(tooltip, x, y, true)

        if not is_pressed then
            if gfx.mouse_cap & 17 == 17 then
                MediaExplorer_SetMetaDataKey('')
                is_pressed = true
            elseif gfx.mouse_cap & 1 == 1 then
                is_pressed = true
                is_parsing_bypassed = not is_parsing_bypassed
                trigger_pitch_rescan = true
            end
        end
    end

    for i = #keys, 1, -1 do
        local key = keys[i]
        local x, y, w, h = key.x, key.y, key.w, key.h
        local is_hover = m_x >= x and m_x <= x + w and m_y >= y and m_y <= y + h

        if key.title == sel_note_name and not locked_key then
            key.bg_color = key.sel_color
        end

        if key.title == locked_key then key.bg_color = key.lock_color end

        if not hovered_key and is_hover then
            if not is_pressed then
                if gfx.mouse_cap & 17 == 17 then
                    MediaExplorer_SetMetaDataKey(key.title)
                    is_pressed = true
                elseif gfx.mouse_cap & 1 == 1 then
                    locked_key = key.title ~= locked_key and key.title or nil
                    if not locked_key then
                        OnUnlock()
                    else
                        OnLock()
                    end
                    trigger_pitch_rescan = true
                    key.bg_color = key.lock_color
                    is_pressed = true
                end
            end

            hovered_key = key
            if key.title ~= locked_key and key.title ~= sel_note_name then
                key.bg_color = key.hover_color
            end
        end
    end

    -- Draw dividers for natural notes (window background)
    gfx.set(table.unpack(theme.div_color))
    gfx.rect(0, 0, gfx.w, gfx.h, 1)

    local margin_bot = math.min(8, gfx.h // 18)
    for _, key in ipairs(keys) do
        -- Draw dividers for flat notes
        if key.is_flat and theme.has_flat_divider then
            gfx.set(table.unpack(theme.div_color))
            gfx.rect(key.x - 1, key.y, key.w + 2, key.h + 1, 1)
        end
        -- Draw key background
        gfx.set(table.unpack(key.bg_color))
        gfx.rect(key.x, key.y, key.w, key.h, 1)
        gfx.set(table.unpack(key.text_color))
        if key.title == locked_key then
            -- Draw lock
            local size = 10
            local half_size = size // 2
            local x_center = key.x + (key.w + 1) // 2
            local y_center = key.h - size - margin_bot + 1
            gfx.rect(x_center - half_size, 3 + y_center - half_size, size,
                size - 2, 1)
            gfx.roundrect(x_center - half_size + 1, y_center - size + 3,
                size - 3, size, size // 3.5, 1)
        else
            -- Draw text
            gfx.setfont(1, '', 14, string.byte('b'))
            local text_w, text_h = gfx.measurestr(key.title)
            gfx.x = key.x + (key.w - text_w + 1) // 2
            gfx.y = key.h - text_h - margin_bot
            gfx.drawstr(key.title)
        end
    end

    if curr_parsing_mode == 0 then
        gfx.update()
        return
    end

    -- Draw parse button inner border
    gfx.set(table.unpack(theme.nat_color))
    gfx.rect(0, 0, button_w, button_w, 1)

    -- Draw parse button background
    local button_bg_color = theme.button_color
    if is_parsing_bypassed then button_bg_color = theme.button_bypass_color end
    gfx.set(table.unpack(button_bg_color))
    gfx.rect(2, 2, button_w - 4, button_w - 4, 1)

    -- Draw parse button border
    gfx.set(table.unpack(theme.flat_color))
    gfx.rect(0, 0, button_w, button_w, 0)

    -- Draw parse button text
    gfx.set(table.unpack(theme.button_text_color))

    local button_text = curr_parsing_mode == 1 and 'F' or 'M'
    local text_w, text_h = gfx.measurestr(button_text)
    gfx.x, gfx.y = (button_w - text_w) // 2, (button_w - text_h) // 2
    gfx.drawstr(button_text)

    gfx.update()
end

function Main()
    -- Ensure hwnd for MX is valid (changes when docked etc.)
    if not reaper.ValidatePtr(mx, 'HWND') then
        mx = reaper.JS_Window_FindTop(mx_title, true)
        -- Exit script when media explorer is closed
        if not mx then return end
    end

    -- Stop script when MX Tuner window is closed
    if gfx.getchar() == -1 then return end

    local is_redraw = false

    -- Monitor media explorer pitch and rate changes
    local mx_pitch = MediaExplorer_GetPitch()
    local mx_rate = MediaExplorer_GetRate()
    local use_rate = not IsPitchPreservedWhenChangingRate()

    local has_pitch_changed = mx_pitch ~= prev_mx_pitch
    local has_rate_changed = mx_rate ~= prev_mx_rate
    local has_rate_setting_changed = use_rate ~= prev_use_rate

    if has_pitch_changed or has_rate_changed or has_rate_setting_changed then
        prev_mx_pitch = mx_pitch
        prev_mx_rate = mx_rate
        prev_use_rate = use_rate
        if prev_file_pitch then
            -- Adjust displayed key when pitch has beend altered via knobs
            local pitch_offs = mx_pitch
            if use_rate then
                pitch_offs = pitch_offs + 12 * math.log(mx_rate, 2)
            end
            sel_note_name = FrequencyToName(prev_file_pitch, pitch_offs)
            if locked_key then locked_key = sel_note_name end
        end
        -- Redraw UI when pitch changes
        is_redraw = true
    end

    -- Monitor media explorer file selection
    local sel_item, sel_idx = MediaExplorer_GetFirstSelectedItem()
    local has_item_changed = sel_item ~= prev_item or sel_idx ~= prev_item_idx

    if has_item_changed then
        prev_item, prev_item_idx = sel_item, sel_idx
        curr_file = nil
        is_parsing_bypassed = false
        curr_file = sel_item and MediaExplorer_GetMediaFileFromItemIndex(sel_idx)
        if curr_file then
            trigger_pitch_rescan = true
        else
            curr_parsing_mode = 0
            sel_note_name = nil
            is_redraw = true
        end
    end

    if curr_file and trigger_pitch_rescan then
        local file_pitch
        -- Check metadata for pitch
        if parse_meta_mode == 1 then
            curr_parsing_mode = 2
            file_pitch = GetPitchFromMetadata(curr_file)
        end
        -- Check file name for pitch
        if not file_pitch and parse_name_mode == 1 then
            curr_parsing_mode = 1
            file_pitch = GetPitchFromFileName(curr_file)
        end
        -- Use chosen pitch detection algorithm to find pitch
        if not file_pitch or is_parsing_bypassed then
            if not is_parsing_bypassed then curr_parsing_mode = 0 end

            local ext = curr_file:match('%.([^.]+)$')
            if ext and ext:lower() == 'mid' then
                -- Get pitch from MIDI file
                local root_name = GetMIDIFileRootName(curr_file)
                file_pitch = NameToFrequency(root_name)
            else
                -- Get pitch from audio file
                if algo_mode == 1 then
                    file_pitch = GetPitchFTC(curr_file)
                end
                if algo_mode == 2 then
                    file_pitch = GetPitchFFT(curr_file)
                end
            end
        end
        prev_file_pitch = file_pitch

        if file_pitch then
            local pitch_offs = mx_pitch
            if use_rate then
                pitch_offs = pitch_offs + 12 * math.log(mx_rate, 2)
            end
            sel_note_name = FrequencyToName(file_pitch, pitch_offs)
        end

        if file_pitch and locked_key then
            local locked_freq = NameToFrequency(locked_key)
            if locked_freq then
                -- Account for offset in pitch that can be caused by rate knob
                local offs = 0
                if rate_mode == 1 then offs = -mx_pitch end
                if rate_mode == 0 and use_rate then
                    offs = -12 * math.log(mx_rate, 2)
                end
                local dist = GetMinSemitonesTo(file_pitch, locked_freq, offs)
                -- Round distance to semitones depending on pitch mode
                if pitch_mode == 2 then
                    dist = math.floor(2 * dist + 0.5) / 2
                end
                if pitch_mode == 3 then
                    dist = math.floor(dist + 0.5)
                end

                if rate_mode == 1 then
                    TurnOffPreservePitchOption()
                    MediaExplorer_SetRate(2 ^ (dist / 12))
                else
                    MediaExplorer_SetPitch(dist)
                end
            end
        end
        is_redraw = true
        trigger_pitch_rescan = false
    end

    -- Monitor changes to window dock state
    local dock, x, y, w, h = gfx.dock(-1, 0, 0, 0, 0)
    if prev_dock ~= dock then
        prev_dock = dock
        reaper.SetExtState('FTC.MXTuner', 'is_docked', dock & 1, true)
        if dock & 1 == 1 then
            reaper.SetExtState('FTC.MXTuner', 'dock', dock, true)
        else
            SetWindowFrame(frameless_mode == 0)
            SetWindowOnTop(ontop_mode == 1)
        end
        -- Note: Reload theme here to change divider color
        LoadTheme(theme_id)
    end

    -- Monitor changes to window position
    if not (x == w_x and y == w_y and w == w_w and h == w_h) then
        w_x, w_y, w_w, w_h = x, y, w, h
        local pos = ('%d %d %d %d'):format(x, y, w, h)
        reaper.SetExtState('FTC.MXTuner', 'pos', pos, true)
    end

    -- Redraw UI when mouse_cap changes
    if prev_mouse_cap ~= gfx.mouse_cap then
        if focus_mode == 1 and prev_mouse_cap and prev_mouse_cap > 0 then
            local mx_list_view = reaper.JS_Window_FindChildByID(mx, 1001)
            reaper.JS_Window_SetFocus(mx_list_view)
        end
        prev_mouse_cap = gfx.mouse_cap
        is_redraw = true
    end

    -- Redraw UI when window size changes
    if prev_w ~= gfx.w or prev_h ~= gfx.h then
        prev_w = gfx.w
        prev_h = gfx.h
        is_redraw = true
    end

    -- Redraw UI when mouse moves inside script window
    local m_x, m_y = gfx.mouse_x, gfx.mouse_y
    if m_x ~= prev_mouse_x or m_y ~= prev_mouse_y then
        prev_mouse_x = m_x
        prev_mouse_y = m_y
        if m_x >= 0 and m_x <= gfx.w and m_y >= 0 and m_y <= gfx.h then
            is_redraw = true
            is_window_hover = true
        elseif is_window_hover then
            is_redraw = true
            is_window_hover = false
        end
    end

    -- Redraw UI and reload theme when active theme changes
    local color_theme = reaper.GetLastColorThemeFile()
    if color_theme ~= prev_color_theme then
        prev_color_theme = color_theme
        LoadTheme(theme_id)
        is_redraw = true
    end

    if is_redraw then DrawPiano() end

    -- Open settings menu on right click
    if prev_mouse_cap & 2 == 2 then
        local menu =
        '>Window|%sDock window|%sHide frame|%sAlways on top|<%sAvoid focus\z
            |>Pitch snap|%sContinuous|%sQuarter tones|%sSemitones||<%sTune with \z
            rate|>Algorithm|%sFFT|%sFTC (deprecated)||<Set analysis time window|>Parsing|%sUse metadata tag \'key\'|\z
            <%sSearch filename for key|>Theme|%sLight|%sDark|%sReaper 1|<%sReaper 2'

        local is_docked = dock & 1 == 1
        local menu_dock_state = is_docked and '!' or ''
        local menu_frameless = frameless_mode == 1 and '!' or ''
        local menu_focus = focus_mode == 1 and '!' or ''
        local menu_ontop = ontop_mode == 1 and '!' or ''
        local menu_pitch_continuous = pitch_mode == 1 and '!' or ''
        local menu_pitch_quarter = pitch_mode == 2 and '!' or ''
        local menu_pitch_semitones = pitch_mode == 3 and '!' or ''
        local menu_rate = rate_mode == 1 and '!' or ''
        local menu_algo_fft = algo_mode == 2 and '!' or ''
        local menu_algo_ftc = algo_mode == 1 and '!' or ''
        local menu_parse_meta = parse_meta_mode == 1 and '!' or ''
        local menu_parse_name = parse_name_mode == 1 and '!' or ''
        local menu_theme1 = theme_id == 1 and '!' or ''
        local menu_theme2 = theme_id == 2 and '!' or ''
        local menu_theme3 = theme_id == 3 and '!' or ''
        local menu_theme4 = theme_id == 4 and '!' or ''

        menu = menu:format(menu_dock_state, menu_frameless, menu_ontop,
            menu_focus, menu_pitch_continuous,
            menu_pitch_quarter, menu_pitch_semitones, menu_rate,
            menu_algo_fft, menu_algo_ftc, menu_parse_meta,
            menu_parse_name, menu_theme1, menu_theme2,
            menu_theme3, menu_theme4)

        gfx.x, gfx.y = m_x, m_y
        local ret = gfx.showmenu(menu)

        if ret == 1 then
            if is_docked then
                -- Undock window
                gfx.dock(0)
            else
                -- Dock window to last known position
                local last_dock = reaper.GetExtState('FTC.MXTuner', 'dock')
                last_dock = tonumber(last_dock) or 256
                gfx.dock(last_dock | 1)
            end
        end

        if ret == 2 then
            frameless_mode = 1 - frameless_mode
            if not is_docked then SetWindowFrame(frameless_mode == 0) end
            reaper.SetExtState('FTC.MXTuner', 'has_frame', frameless_mode, true)
        end

        if ret == 3 then
            ontop_mode = 1 - ontop_mode
            if not is_docked then SetWindowOnTop(ontop_mode == 1) end
            reaper.SetExtState('FTC.MXTuner', 'is_ontop', ontop_mode, true)
        end

        if ret == 4 then
            focus_mode = 1 - focus_mode
            reaper.SetExtState('FTC.MXTuner', 'avoid_focus', focus_mode, true)
        end

        if ret == 5 then pitch_mode = 1 end
        if ret == 6 then pitch_mode = 2 end
        if ret == 7 then pitch_mode = 3 end

        if ret == 8 then
            rate_mode = 1 - rate_mode
            reaper.SetExtState('FTC.MXTuner', 'rate_mode', rate_mode, true)
        end

        if ret == 9 then algo_mode = 2 end
        if ret == 10 then algo_mode = 1 end

        if ret == 11 then
            local title = 'Analysis time window '
            local caption = 'Time window in seconds (def: 1)'
            local input = tostring(algo_window)

            local _, user_text = reaper.GetUserInputs(title, 1, caption, input)
            if tonumber(user_text) then
                algo_window = tonumber(user_text)
                reaper.SetExtState('FTC.MXTuner', 'algo_window', algo_window, 1)
            end
        end

        if ret == 12 then parse_meta_mode = 1 - parse_meta_mode end
        if ret == 13 then parse_name_mode = 1 - parse_name_mode end

        -- Retrigger pitch detection when detection type changes
        if ret >= 9 and ret <= 13 then trigger_pitch_rescan = true end

        if ret >= 14 and ret <= 18 then
            theme_id = ret - 13
            LoadTheme(theme_id)
            reaper.SetExtState('FTC.MXTuner', 'theme_id', theme_id, true)
        end

        reaper.SetExtState('FTC.MXTuner', 'pitch_mode', pitch_mode, true)
        reaper.SetExtState('FTC.MXTuner', 'algo_mode', algo_mode, true)
        reaper.SetExtState('FTC.MXTuner', 'meta_mode', parse_meta_mode, true)
        reaper.SetExtState('FTC.MXTuner', 'name_mode', parse_name_mode, true)
    end

    reaper.defer(Main)
end

function OnLock()
    -- Turn off option to reset pitch when changing media
    if reaper.GetToggleCommandStateEx(32063, 42014) == 1 then
        -- Options: Reset pitch and rate when changing media
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42014, 0, 0, 0)
        is_option_bypassed = true
    end
end

function OnUnlock()
    if rate_mode == 1 then
        MediaExplorer_SetRate(1)
    else
        MediaExplorer_SetPitch(0)
    end
    -- Turn option back on to reset pitch when changing media
    if is_option_bypassed then
        -- Options: Reset pitch and rate when changing media
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42014, 0, 0, 0)
        is_option_bypassed = false
    end
end

function RefreshMXToolbar()
    -- Toggle any option to refresh MX toolbar
    reaper.JS_Window_OnCommand(mx, 42171)
    reaper.JS_Window_OnCommand(mx, 42171)
end

function Exit()
    -- Turn toolbar icon off
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    RefreshMXToolbar()

    -- Turn option back on to reset pitch when changing media
    if is_option_bypassed then
        -- Options: Reset pitch and rate when changing media
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42014, 0, 0, 0)
    end
    gfx.quit()
end

theme_id = tonumber(reaper.GetExtState('FTC.MXTuner', 'theme_id')) or 1
LoadTheme(theme_id)

focus_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'avoid_focus')) or 1

local is_docked = reaper.GetExtState('FTC.MXTuner', 'is_docked') == '1'

OpenWindow(is_docked)

frameless_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'has_frame')) or 0
if not is_docked and frameless_mode == 1 then
    local hwnd = reaper.JS_Window_Find('MX Tuner', true)
    reaper.JS_Window_SetStyle(hwnd, 'POPUP')
end

ontop_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'is_ontop')) or 0
if not is_docked and ontop_mode == 1 then
    local hwnd = reaper.JS_Window_Find('MX Tuner', true)
    reaper.JS_Window_SetZOrder(hwnd, 'TOPMOST')
end

rate_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'rate_mode')) or 0
pitch_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'pitch_mode')) or 1
algo_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'algo_mode')) or 2
algo_window = tonumber(reaper.GetExtState('FTC.MXTuner', 'algo_window')) or 1
parse_meta_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'meta_mode')) or 1
parse_name_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'name_mode')) or 1

-- Turn toolbar icon on
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)
RefreshMXToolbar()

Main()
reaper.atexit(Exit)

-- Show a one time notice to users if they are using deprecated FTC algorithm
if reaper.GetExtState('FTC.MXTuner', 'show_deprecated') == '' then
    reaper.SetExtState('FTC.MXTuner', 'show_deprecated', '1', true)
    if algo_mode == 1 then
        local msg = 'You are using the FTC algorithm which is now \z
        deprecated.\n\nSwitch to the new and improved FFT algorithm?'
        local ret = reaper.MB(msg, 'Notice', 3)
        if ret == 6 then
            algo_mode = 2
            reaper.SetExtState('FTC.MXTuner', 'algo_mode', algo_mode, 1)
        end
    end
end
