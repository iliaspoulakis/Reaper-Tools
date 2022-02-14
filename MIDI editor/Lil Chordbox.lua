--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.0.0
  @provides [main=main,midi_editor] .
  @about Adds a little box to the MIDI editor that displays chord information
]]

local piano_pane
local curr_chords
local curr_sel_chord
local input_timer

local input_note_map = {}
local input_note_cnt = 0

local prev_idx
local prev_hwnd
local prev_hash
local prev_row
local prev_mode
local prev_cursor_pos
local prev_chord_name
local prev_color_theme
local prev_mouse_state
local prev_play_state

local _, _, sec, cmd = reaper.get_action_context()

local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

local bm_w = is_windows and 109 or is_macos and 125 or is_linux and 141
local bm_h = 18
local bm_x = 7
local bm_y = 28

local bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)
local lice_font = reaper.JS_LICE_CreateFont()

local font_size = is_windows and 12 or 14
local gdi_font = reaper.JS_GDI_CreateFont(12, 0, 0, 0, 0, 0, '')
reaper.JS_LICE_SetFontFromGDI(lice_font, gdi_font, '')

-- Check if SWS extension is installed
if not reaper.BR_GetMouseCursorContext then
    reaper.MB('Please install SWS extension', 'Error', 0)
    return
end

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_SetPosition then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

local chord_names = {}
-- Major chords
chord_names['1 5 8'] = 'maj'
chord_names['1 8 12'] = 'maj7 omit3'
chord_names['1 5 12'] = 'maj7 omit5'
chord_names['1 5 8 12'] = 'maj7'
chord_names['1 3 5 12'] = 'maj9 omit5'
chord_names['1 3 5 8 12'] = 'maj9'
chord_names['1 3 5 6 12'] = 'maj11 omit5'
chord_names['1 5 6 8 12'] = 'maj11 omit9'
chord_names['1 3 5 6 8 12'] = 'maj11'
chord_names['1 3 5 6 10 12'] = 'maj13 omit5'
chord_names['1 5 6 8 10 12'] = 'maj13 omit9'
chord_names['1 3 5 6 8 10 12'] = 'maj13'
chord_names['1 8 10'] = '6 omit3'
chord_names['1 5 8 10'] = '6'
chord_names['1 3 5 10'] = '6/9 omit5'
chord_names['1 3 5 8 10'] = '6/9'

-- Dominant/Seventh
chord_names['1 8 11'] = '7 omit3'
chord_names['1 5 11'] = '7 omit5'
chord_names['1 5 8 11'] = '7'
chord_names['1 3 8 11'] = '9 omit3'
chord_names['1 3 5 11'] = '9 omit5'
chord_names['1 3 5 8 11'] = '9'
chord_names['1 3 5 10 11'] = '13 omit5'
chord_names['1 5 8 10 11'] = '13 omit9'
chord_names['1 3 5 8 10 11'] = '13'
chord_names['1 5 7 11'] = '7#11 omit5'
chord_names['1 5 7 8 11'] = '7#11'
chord_names['1 3 5 7 11'] = '9#11 omit5'
chord_names['1 3 5 7 8 11'] = '9#11'

-- Altered
chord_names['1 2 5 11'] = '7b9 omit5'
chord_names['1 2 5 8 11'] = '7b9'
chord_names['1 2 5 7 8 11'] = '7b9#11'
chord_names['1 4 5 11'] = '7#9 omit5'
chord_names['1 4 5 8 11'] = '7#9'
chord_names['1 4 5 9 11'] = '7#5#9'
chord_names['1 4 5 7 8 11'] = '7#9#11'
chord_names['1 2 5 8 10 11'] = '13b9'
chord_names['1 3 5 7 8 10 11'] = '13#11'
chord_names['1 5 7 12'] = 'maj7#11 omit5'
chord_names['1 5 7 8 12'] = 'maj7#11'
chord_names['1 3 5 7 12'] = 'maj9#11 omit5'
chord_names['1 3 5 7 8 12'] = 'maj9#11'
chord_names['1 3 5 7 10 12'] = 'maj13#11 omit5'
chord_names['1 5 7 8 10 12'] = 'maj13#11 omit9'
chord_names['1 3 5 7 8 10 12'] = 'maj13#11'

-- Suspended
chord_names['1 6 8'] = 'sus4'
chord_names['1 3 8'] = 'sus2'
chord_names['1 6 11'] = '7sus4 omit5'
chord_names['1 6 8 11'] = '7sus4'
chord_names['1 3 6 11'] = '11 omit5'
chord_names['1 6 8 11'] = '11 omit9'
chord_names['1 3 6 8 11'] = '11'

-- Minor
chord_names['1 4 8'] = 'min'
chord_names['1 4 11'] = 'min7 omit5'
chord_names['1 4 8 11'] = 'min7'
chord_names['1 4 12'] = 'min/maj7 omit5'
chord_names['1 4 8 12'] = 'min/maj7'
chord_names['1 3 4 12'] = 'min/maj9 omit5'
chord_names['1 3 4 8 12'] = 'min/maj9'
chord_names['1 3 4 11'] = 'min9 omit5'
chord_names['1 3 4 8 11'] = 'min9'
chord_names['1 3 4 6 11'] = 'min11 omit5'
chord_names['1 4 6 8 11'] = 'min11 omit9'
chord_names['1 3 4 6 8 11'] = 'min11'
chord_names['1 3 4 6 10 11'] = 'min13 omit5'
chord_names['1 4 6 8 10 11'] = 'min13 omit9'
chord_names['1 3 4 6 8 10 11'] = 'min13'
chord_names['1 4 8 10'] = 'min6'
chord_names['1 3 4 10'] = 'min6/9 omit5'
chord_names['1 3 4 8 10'] = 'min6/9'

-- Diminished
chord_names['1 4 7'] = 'dim'
chord_names['1 4 7 10'] = 'dim7'
chord_names['1 2 4 7 11'] = 'min7b5'
chord_names['1 3 4 7 11'] = 'min9b5'
chord_names['1 3 4 6 7 11'] = 'min11b5'
chord_names['1 3 5 7 10 11'] = '13b5'

-- Augmented
chord_names['1 5 9'] = 'aug'
chord_names['1 5 9 11'] = 'aug7'
chord_names['1 5 9 12'] = 'aug/maj7'

-- Additions
chord_names['1 3 4 8'] = 'min add9'
chord_names['1 3 5 8'] = 'maj add9'
chord_names['1 5 10 11'] = '7 add13'

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function PitchToName(pitch)
    local n = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'}
    return n[pitch % 12 + 1]
end

function GetChordName(notes)
    -- Get root note
    local root = math.maxinteger
    for _, note in ipairs(notes) do
        root = note.pitch < root and note.pitch or root
    end
    -- Remove duplicates and move notes closer
    local intervals = {}
    for _, note in ipairs(notes) do
        intervals[(note.pitch - root) % 12 + 1] = 1
    end
    -- Create chord key string
    local key = '1'
    for i = 2, 12 do if intervals[i] then key = key .. ' ' .. i end end

    -- Check if chord name exists for key
    if chord_names[key] then return PitchToName(root) .. chord_names[key] end

    local key_nums = {}
    for key_num in key:gmatch('%d+') do key_nums[#key_nums + 1] = key_num end

    -- Create all possible inversions
    for n = 2, #key_nums do
        local diff = key_nums[n] - key_nums[1]
        intervals = {}
        for i = 1, #key_nums do intervals[(key_nums[i] - diff) % 12] = 1 end
        local inv_key = '1'
        for i = 2, 12 do
            if intervals[i] then inv_key = inv_key .. ' ' .. i end
        end
        -- Check if chord name exists for inversion key
        if chord_names[inv_key] then
            return PitchToName(root + diff) .. chord_names[inv_key]
        end
    end
end

function BuildChord(notes)
    -- Get chord start and end position
    local min_eppq = math.maxinteger
    local max_sppq = math.mininteger
    for _, note in ipairs(notes) do
        min_eppq = note.eppq < min_eppq and note.eppq or min_eppq
        max_sppq = note.sppq > max_sppq and note.sppq or max_sppq
    end

    local chord_name = GetChordName(notes)
    if chord_name then
        return {name = chord_name, sppq = max_sppq, eppq = min_eppq}
    end
end

function BuildChordFromSelectedNotes(notes)
    local sel_notes = {}
    for _, note in ipairs(notes) do
        if note.sel then sel_notes[#sel_notes + 1] = note end
    end
    return BuildChord(sel_notes)
end

function GetChords(take)
    local _, note_cnt = reaper.MIDI_CountEvts(take)

    local chords = {}
    local notes = {}

    local chord_min_eppq
    local chord_sel_cnt = 0
    local total_sel_cnt = 0

    local sel_chord

    for i = 0, note_cnt - 1 do
        local _, sel, _, sppq, eppq, _, pitch = reaper.MIDI_GetNote(take, i)

        chord_min_eppq = chord_min_eppq or eppq
        chord_min_eppq = eppq < chord_min_eppq and eppq or chord_min_eppq

        if sppq >= chord_min_eppq then
            local new_notes = {}
            local new_chord_sel_cnt = 0
            if #notes >= 3 then
                local chord = BuildChord(notes)
                if chord then chords[#chords + 1] = chord end
                if chord_sel_cnt >= 3 and chord_sel_cnt == total_sel_cnt then
                    sel_chord = BuildChordFromSelectedNotes(notes)
                end
                -- Remove notes that end prior to the start of current note
                for _, note in ipairs(notes) do
                    if note.eppq > sppq then
                        new_notes[#new_notes + 1] = note
                        if note.sel then
                            new_chord_sel_cnt = new_chord_sel_cnt + 1
                        end
                    end
                end
            end
            notes = new_notes
            chord_sel_cnt = new_chord_sel_cnt
            chord_min_eppq = nil
        end

        notes[#notes + 1] = {pitch = pitch, sel = sel, sppq = sppq, eppq = eppq}

        -- Count selected notes
        if sel then
            total_sel_cnt = total_sel_cnt + 1
            chord_sel_cnt = chord_sel_cnt + 1
            -- Remove selected chord if another selected note is found
            if sel_chord then sel_chord = nil end
        end
    end

    if #notes >= 3 then
        local chord = BuildChord(notes)
        if chord then chords[#chords + 1] = chord end
        if chord_sel_cnt >= 3 and chord_sel_cnt == total_sel_cnt then
            sel_chord = BuildChordFromSelectedNotes(notes)
        end
    end

    return chords, sel_chord
end

function GetMIDIInputChord(track)
    local rec_in = reaper.GetMediaTrackInfo_Value(track, 'I_RECINPUT')
    local rec_arm = reaper.GetMediaTrackInfo_Value(track, 'I_RECARM')
    local is_recording_midi = rec_arm == 1 and rec_in & 4096 == 4096
    if not is_recording_midi then return end

    local filter_channel = rec_in & 31
    local filter_dev_id = (rec_in >> 5) & 127

    prev_idx = prev_idx or 0

    local idx, buf, _, dev_id = reaper.MIDI_GetRecentInputEvent(0)
    if idx > prev_idx then
        local new_idx = idx
        local i = 0
        repeat
            if prev_idx ~= 0 then
                local is_vkb_dev = dev_id == 62
                local is_all_dev = filter_dev_id == 63
                if not is_vkb_dev and (is_all_dev or dev_id == filter_dev_id) then

                    local msg1 = buf:byte(1)
                    local msg2 = buf:byte(2)
                    local msg3 = buf:byte(3)

                    local channel = msg1 & 0x0F
                    if filter_channel == 0 or filter_channel == channel then
                        local is_note_on = msg1 & 0xF0 == 0x90
                        local is_note_off = msg1 & 0xF0 == 0x80
                        if is_note_on and not input_note_map[msg2] then
                            input_note_map[msg2] = 1
                            input_note_cnt = input_note_cnt + 1
                        end
                        if is_note_off and input_note_map[msg2] == 1 then
                            input_note_map[msg2] = nil
                            input_note_cnt = input_note_cnt - 1
                        end

                    end
                end
            end
            i = i + 1
            idx, buf, _, dev_id = reaper.MIDI_GetRecentInputEvent(i)
        until idx == prev_idx

        prev_idx = new_idx
    end

    if input_note_cnt >= 3 then
        local notes = {}
        for n = 0, 127 do
            if input_note_map[n] == 1 then
                notes[#notes + 1] = {pitch = n}
            end
        end
        local chord_name = GetChordName(notes)
        if chord_name then return chord_name end
    end
end

function DrawLICE(chord, mode)
    reaper.JS_LICE_Clear(bitmap, 0)

    local aa = 0xFF000000
    local bg_color = reaper.GetThemeColor('col_main_editbk', 0) | aa
    local hl_color = reaper.GetThemeColor('col_main_3dhl', 0) | aa
    local sh_color = reaper.GetThemeColor('col_main_3dsh', 0) | aa
    local text_color = reaper.GetThemeColor('col_main_text', 0) | aa

    -- Draw box background
    reaper.JS_LICE_FillRect(bitmap, 0, 0, bm_w, bm_h, bg_color, 1, 0)

    -- Draw box 3D shadow
    reaper.JS_LICE_Line(bitmap, 0, 0, bm_w, 0, sh_color, 1, 0, 0)
    reaper.JS_LICE_Line(bitmap, 0, 0, 0, bm_h, sh_color, 1, 0, 0)

    -- Draw box 3D highlight
    reaper.JS_LICE_Line(bitmap, 0, bm_h - 1, bm_w, bm_h - 1, hl_color, 1, 0, 0)
    reaper.JS_LICE_Line(bitmap, bm_w - 1, 0, bm_w - 1, bm_h, hl_color, 1, 0, 0)

    -- Draw Text
    reaper.JS_LICE_SetFontColor(lice_font, text_color)
    local _, text_h = reaper.JS_LICE_MeasureText(chord)
    -- Note: Width reported by JS_LICE_MeasureText seems to be incorrect
    gfx.setfont(1, is_windows and 'Georgia' or 'Calibri', 12)
    local text_w = gfx.measurestr(chord)
    local text_x = (bm_w - text_w) // 2
    local text_y = bm_h // 2 - text_h
    if is_windows or is_macos then text_y = text_y + 2 end

    -- Move x axis slightly if icon for mode will is drawn
    local x = text_x - 8
    text_x = mode == 0 and text_x or text_x + 5

    if mode == 1 and chord ~= '' then
        reaper.JS_LICE_Line(bitmap, x, 5, x + 7, 8, text_color, 1, 0, 1)
        reaper.JS_LICE_Line(bitmap, x, 12, x + 7, 9, text_color, 1, 0, 1)
        reaper.JS_LICE_FillTriangle(bitmap, x, 5, x, 12, x + 7, 8, text_color,
                                    1, 0)
    end

    if mode == 2 then
        reaper.JS_LICE_FillRect(bitmap, x, 5, 8, 8, text_color, 1, 0)
        reaper.JS_LICE_FillRect(bitmap, x + 2, 7, 4, 4, bg_color, 1, 0)
    end

    if mode == 3 then
        reaper.JS_LICE_FillCircle(bitmap, x + 5, 9, 2.5, text_color, 1, 1, true)
    end

    -- Note: Green box to help measure text
    --[[ reaper.JS_LICE_FillRect(bitmap, text_x, text_y, text_w, text_h, 0xFF00FF00,
                            1, 0) ]]

    local len = chord:len()
    reaper.JS_LICE_DrawText(bitmap, lice_font, chord, len, text_x, text_y, bm_w,
                            bm_h)

    -- Refresh window
    reaper.JS_Window_InvalidateRect(piano_pane, bm_x, bm_y, bm_x + bm_w,
                                    bm_y + bm_h, false)
end

function Main()
    local hwnd = reaper.MIDIEditor_GetActive()

    -- Keep process idle when no MIDI editor is open
    if not reaper.ValidatePtr(hwnd, 'HWND*') then
        reaper.defer(Main)
        return
    end

    local is_redraw = false

    -- Monitor color theme changes
    local color_theme = reaper.GetLastColorThemeFile()
    if color_theme ~= prev_color_theme then
        prev_color_theme = color_theme
        is_redraw = true
        prev_chord_name = nil
    end

    -- Monitor MIDI editor window changes
    if hwnd ~= prev_hwnd then
        prev_hwnd = hwnd
        piano_pane = reaper.JS_Window_FindChildByID(hwnd, 1003)
        -- Draw LICE bitmap on piano pane
        reaper.JS_Composite(piano_pane, bm_x, bm_y, bm_w, bm_h, bitmap, 0, 0,
                            bm_w, bm_h, false)
        reaper.JS_Composite_Delay(piano_pane, 0.022, 0.022, 2)
        is_redraw = true
        prev_chord_name = nil
    end

    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then
        reaper.defer(Main)
        return
    end

    -- Note: Keep this code for future left/right click options

    --[[ local mouse_state = reaper.JS_Mouse_GetState(3)
    if mouse_state ~= prev_mouse_state then
        prev_mouse_state = mouse_state
        local is_right_click = mouse_state == 2
        local x, y = reaper.GetMousePosition()
        -- Open scale finder on left click
        local is_left_click = mouse_state == 1
        if is_right_click then
            local w_x, w_y = reaper.JS_Window_ScreenToClient(piano_pane, x, y)
            if w_x >= bm_x and w_y > bm_y and w_x < bm_x + bm_w and w_y <= bm_y +
                bm_h then reaper.Main_OnCommand(40301, 0) end
        end
    end ]]

    local track = reaper.GetMediaItemTake_Track(take)
    local input_chord = GetMIDIInputChord(track)

    if input_chord then
        input_timer = reaper.time_precise()
        DrawLICE(input_chord, 3)
        reaper.defer(Main)
        return
    end

    -- Show input chords a bit longer than they are played (linger)
    if input_timer then
        local linger_duration = 0.6
        if reaper.time_precise() < input_timer + linger_duration then
            reaper.defer(Main)
            return
        else
            input_timer = nil
            prev_cursor_pos = nil
            prev_chord_name = nil
            is_redraw = true
        end
    end

    -- Get new chords when take MIDI information changes
    local ret, hash = reaper.MIDI_GetHash(take, true)
    if hash ~= prev_hash then
        prev_hash = hash
        curr_chords, curr_sel_chord = GetChords(take)
        is_redraw = true
    end

    local mode = -1
    local cursor_pos

    -- Get position at mouse cursor
    local _, segment = reaper.BR_GetMouseCursorContext()
    if segment == 'notes' then
        cursor_pos = reaper.BR_GetMouseCursorContext_Position()
        mode = 0
    end

    -- Use play cursor position during playback/record
    local play_state = reaper.GetPlayState()
    if play_state > 0 then
        cursor_pos = reaper.GetPlayPosition()
        mode = 1
    end

    -- Redraw when transport status changes
    if play_state ~= prev_play_state then
        prev_play_state = play_state
        is_redraw = true
    end

    -- Redraw when cursor changes
    if cursor_pos ~= prev_cursor_pos then
        prev_cursor_pos = cursor_pos
        is_redraw = true
    end

    if is_redraw then
        local chord_name = ''
        -- Get chord name depending on mode
        if curr_sel_chord then
            chord_name = curr_sel_chord.name
            mode = 2
        end

        if mode == 1 then
            local GetPPQFromTime = reaper.MIDI_GetPPQPosFromProjTime
            local cursor_ppq = GetPPQFromTime(take, cursor_pos)
            for _, chord in ipairs(curr_chords) do
                if chord.sppq > cursor_ppq then break end
                chord_name = chord.name
            end
        end

        if mode == 0 and cursor_pos then
            local GetPPQFromTime = reaper.MIDI_GetPPQPosFromProjTime
            local cursor_ppq = GetPPQFromTime(take, cursor_pos)
            for _, chord in ipairs(curr_chords) do
                if chord.sppq > cursor_ppq then break end
                if cursor_ppq >= chord.sppq and cursor_ppq <= chord.eppq then
                    chord_name = chord.name
                    break
                end
            end
        end

        if chord_name ~= prev_chord_name or mode ~= prev_mode then
            prev_chord_name = chord_name
            prev_mode = mode
            DrawLICE(chord_name, mode)
        end
    end

    reaper.defer(Main)
end

reaper.SetToggleCommandState(sec, cmd, 1)
reaper.RefreshToolbar2(sec, cmd)

function Exit()
    reaper.SetToggleCommandState(sec, cmd, 0)
    reaper.RefreshToolbar2(sec, cmd)
    reaper.JS_LICE_DestroyBitmap(bitmap)
    reaper.JS_LICE_DestroyFont(lice_font)
    reaper.JS_GDI_DeleteObject(gdi_font)
    reaper.JS_Composite_Delay(piano_pane, 0, 0, 0)
end

reaper.atexit(Exit)
reaper.defer(Main)

