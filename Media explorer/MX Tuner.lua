--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @provides [main=main,mediaexplorer] .
  @about Simple tuner utility for the reaper media explorer
]]

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

local prev_mouse_x, prev_mouse_y
local prev_mouse_cap
local prev_h, prev_w
local prev_dock

local prev_mx_pitch
local prev_file_pitch
local highlighted_note_name
local prev_file

local locked_key
local hovered_key

local is_pressed = false
local is_window_hover = false

local pitch_mode
local algo_mode

local is_option_bypassed = false

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function GetSemitonesToA(f) return 12 * math.log(f / 440) / math.log(2) % 12 end

function GetSemitonesTo(f1, f2)
    local dist = GetSemitonesToA(f2) - GetSemitonesToA(f1)
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
    for i = 1, #n do
        if name == n[i] then
            return 440 * math.exp((i - 1) * math.log(2) / 12)
        end
    end
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
    local peaks = {}

    for index in string.gmatch(sel_indexes, '[^,]+') do
        index = tonumber(index)
        local file_name = reaper.JS_ListView_GetItem(mx_list_view, index, 0)
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
            local peak = reaper.JS_ListView_GetItem(mx_list_view, index, 21)
            peaks[#peaks + 1] = tonumber(peak)
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

    return sel_files, peaks
end

function MediaExplorer_GetPitch()
    local pitch_hwnd = reaper.JS_Window_FindChildByID(mx, 1021)
    local pitch = reaper.JS_Window_GetTitle(pitch_hwnd)
    return tonumber(pitch)
end

function MediaExplorer_SetPitch(pitch)
    local is_auto_play = reaper.GetToggleCommandStateEx(32063, 1011) == 1
    if is_auto_play then
        local pitch_rnd = math.floor(pitch + 0.5)
        local set_pitch_cmd = 42150 + pitch_rnd
        if pitch_rnd > 0 then set_pitch_cmd = set_pitch_cmd - 1 end
        -- Preview: set pitch to XX semitones
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', set_pitch_cmd, 0, 0, 0)

        -- Workaround for setting pitch to zero (action is missing)
        if pitch_rnd == 0 then
            -- Preview: adjust pitch by -01 semitones
            reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42162, 0, 0, 0)
        end

        -- Preview: Stop
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 1009, 0, 0, 0)
    end

    -- Set precise pitch to pitch textfield
    local pitch_hwnd = reaper.JS_Window_FindChildByID(mx, 1021)
    reaper.JS_Window_SetTitle(pitch_hwnd, ('%.2f'):format(pitch))
end

function GetPitchFTC(file)

    -- Get media source peaks
    local src = reaper.PCM_Source_CreateFromFileEx(file, true)
    if not src then return end

    local src_len = reaper.GetMediaSourceLength(src)
    if src_len == 0 then return end

    local rate = reaper.GetMediaSourceSampleRate(src)
    local spl_cnt = math.ceil(src_len * rate)
    local buf = reaper.new_array(spl_cnt * 2)
    buf.clear()

    local peaks = reaper.PCM_Source_GetPeaks(src, rate, 0, 1, spl_cnt, 0, buf)
    spl_cnt = peaks & 0xfffff
    if spl_cnt == 0 then return end

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
    if src_len == 0 then return end

    local rate = reaper.GetMediaSourceSampleRate(src)
    local spl_cnt = math.ceil(src_len * rate)

    -- FFT window size has to be a power of 2
    local window_size = 2 ^ 15
    local buf = reaper.new_array(math.max(window_size, spl_cnt) * 2)

    local peaks = reaper.PCM_Source_GetPeaks(src, rate, 0, 1, spl_cnt, 0, buf)
    spl_cnt = peaks & 0xfffff
    if spl_cnt == 0 then return end

    -- Zero padding
    buf.clear(0, spl_cnt - 1)
    buf.fft(window_size, true)

    local max_val = 0
    local max_i = 0
    for i = 1, window_size do
        local val = buf[i]
        local val_abs = val < 0 and -val or val
        if val_abs > max_val then
            max_i = i
            max_val = val_abs
        end
    end

    -- Use parabolic interpolation to improve precision
    local prev = buf[max_i - 1] or 0
    local next = buf[max_i + 1] or 0
    local diff = (next - prev) / (max_val + prev + next)
    max_i = max_i + diff

    return max_i * rate / window_size / 4
end

function OpenWindow()
    -- Show script window in center of screen
    gfx.clear = reaper.ColorToNative(37, 37, 37)
    local w, h = 406, 138
    local x, y = reaper.GetMousePosition()
    local l, t, r, b = reaper.my_getViewport(0, 0, 0, 0, x, y, x, y, 1)
    gfx.init('MX Tuner', w, h, 0, (r + l - w) / 2, (b + t - h) / 2 - 24)
end

function DrawPiano()

    local keys = {}

    local flat = {'C', 'D', 'E', 'F', 'G', 'A', 'B'}
    local f_w = gfx.w // 7
    local f_h = gfx.h
    local m = 1

    for i = 1, 7 do
        keys[#keys + 1] = {
            title = flat[i],
            x = (i - 1) * f_w + m,
            y = m,
            w = f_w - 2 * m,
            h = f_h - 2 * m,
            bg_color = {0.79, 0.79, 0.79},
            text_color = {0.14, 0.14, 0.14},
        }
    end

    local sharp = {'C#', 'D#', 'F#', 'G#', 'A#'}
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
        keys[#keys + 1] = {
            title = sharp[i],
            x = s_x[i],
            y = m,
            w = s_w,
            h = s_h - 2 * m,
            bg_color = {0.14, 0.14, 0.14},
            text_color = {0.82, 0.82, 0.82},
        }
    end

    local m_x, m_y = gfx.mouse_x, gfx.mouse_y

    hovered_key = nil
    if gfx.mouse_cap & 1 == 0 then is_pressed = false end

    for i = #keys, 1, -1 do
        local key = keys[i]
        local x, y, w, h = key.x, key.y, key.w, key.h
        local is_hover = m_x >= x and m_x <= x + w and m_y >= y and m_y <= y + h

        if key.title == highlighted_note_name and not locked_key then
            key.bg_color = {0.61, 0.75, 0.38}
        end
        if key.title == locked_key then key.bg_color = {0.7, 0.43, 0.4} end

        if not hovered_key and is_hover then
            if gfx.mouse_cap & 1 == 1 then

                if not is_pressed then
                    locked_key = key.title ~= locked_key and key.title or nil
                    if not locked_key then
                        OnUnlock()
                    else
                        OnLock()
                    end
                    prev_file = nil
                    key.bg_color = {0.7, 0.43, 0.4}
                end
                is_pressed = true
            end

            hovered_key = key
            if key.title ~= locked_key and key.title ~= highlighted_note_name then
                key.bg_color = {0.74, 0.62, 0.44}
            end
        end
    end

    local margin_bot = math.min(8, gfx.h // 18)
    for _, key in ipairs(keys) do
        -- Draw background
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

    gfx.update()
end

function Main()

    local is_redraw = false

    -- Monitor media explorer pitch changes
    local mx_pitch = MediaExplorer_GetPitch()

    if mx_pitch ~= prev_mx_pitch then
        prev_mx_pitch = mx_pitch
        if prev_file_pitch then
            highlighted_note_name = FrequencyToName(prev_file_pitch, mx_pitch)
        end
        -- Redraw UI when pitch changes
        is_redraw = true
    end

    -- Monitor media explorer file selection
    local files = MediaExplorer_GetSelectedAudioFiles()

    if files[1] and prev_file ~= files[1] then

        local file_pitch

        if algo_mode == 1 then file_pitch = GetPitchFTC(files[1]) end
        if algo_mode == 2 then file_pitch = GetPitchFFT(files[1]) end

        prev_file_pitch = file_pitch

        if file_pitch then
            highlighted_note_name = FrequencyToName(file_pitch, mx_pitch)
        end

        if file_pitch and locked_key then
            local locked_freq = NameToFrequency(locked_key)
            if locked_freq then
                local dist = GetSemitonesTo(file_pitch, locked_freq)
                -- Round distance to semitones depending on pitch mode
                if pitch_mode == 2 then
                    dist = math.floor(2 * dist + 0.5) / 2
                end
                if pitch_mode == 3 then
                    dist = math.floor(dist + 0.5)
                end
                MediaExplorer_SetPitch(dist)
            end
        end
        -- Redraw UI when file changes
        is_redraw = true
    end

    if not files[1] then highlighted_note_name = nil end
    prev_file = files[1]

    -- Monitor changes to window dock state
    local dock = gfx.dock(-1)
    if prev_dock ~= dock then
        prev_dock = dock
        local is_docked = dock > 0 and 1 or 0
        reaper.SetExtState('FTC.MXTuner', 'is_docked', is_docked, true)
        if dock > 0 then
            reaper.SetExtState('FTC.MXTuner', 'dock', dock, true)
        end
    end

    -- Redraw UI when mouse_cap changes
    if prev_mouse_cap ~= gfx.mouse_cap then
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

    if is_redraw then DrawPiano() end

    -- Open settings menu on right click
    if gfx.mouse_cap & 2 == 2 then

        local menu = '%sDock window|>Pitch snap|%sContinuous|%sQuarter \z
            tones|<%sSemitones|>Algorithm|%sFTC|%sFFT'

        local is_docked = dock > 0
        local menu_dock_state = is_docked and '!' or ''
        local menu_pitch_continuous = pitch_mode == 1 and '!' or ''
        local menu_pitch_quarter = pitch_mode == 2 and '!' or ''
        local menu_pitch_semitones = pitch_mode == 3 and '!' or ''
        local menu_algo_ftc = algo_mode == 1 and '!' or ''
        local menu_algo_fft = algo_mode == 2 and '!' or ''

        menu = menu:format(menu_dock_state, menu_pitch_continuous,
                           menu_pitch_quarter, menu_pitch_semitones,
                           menu_algo_ftc, menu_algo_fft)

        gfx.x, gfx.y = m_x, m_y
        local ret = gfx.showmenu(menu)

        if ret == 1 then
            if is_docked then
                -- Undock window
                gfx.dock(0)
            else
                -- Dock window to last known position
                local last_dock = reaper.GetExtState('FTC.MXTuner', 'dock')
                last_dock = tonumber(last_dock) or 0x801
                gfx.dock(tonumber(last_dock))
            end
        end

        if ret == 2 then pitch_mode = 1 end
        if ret == 3 then pitch_mode = 2 end
        if ret == 4 then pitch_mode = 3 end
        if ret == 5 then algo_mode = 1 end
        if ret == 6 then algo_mode = 2 end

        -- Retrigger pitch detection when algorithm changes
        if ret >= 5 and ret <= 6 then prev_file = nil end

        reaper.SetExtState('FTC.MXTuner', 'pitch_mode', pitch_mode, true)
        reaper.SetExtState('FTC.MXTuner', 'algo_mode', algo_mode, true)
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
    MediaExplorer_SetPitch(0)
    -- Turn option back on to reset pitch when changing media
    if is_option_bypassed then
        -- Options: Reset pitch and rate when changing media
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42014, 0, 0, 0)
        is_option_bypassed = false
    end
end

function Exit()
    -- Turn toolbar icon off
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)

    -- Turn option back on to reset pitch when changing media
    if is_option_bypassed then
        -- Options: Reset pitch and rate when changing media
        reaper.JS_WindowMessage_Send(mx, 'WM_COMMAND', 42014, 0, 0, 0)
    end
end

OpenWindow()

local is_docked = reaper.GetExtState('FTC.MXTuner', 'is_docked') == '1'
if is_docked then
    prev_dock = tonumber(reaper.GetExtState('FTC.MXTuner', 'dock'))
    if prev_dock then gfx.dock(prev_dock) end
end

pitch_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'pitch_mode')) or 3
algo_mode = tonumber(reaper.GetExtState('FTC.MXTuner', 'algo_mode')) or 1

-- Turn toolbar icon on
reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

Main()
reaper.atexit(Exit)
