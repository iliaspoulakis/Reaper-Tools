--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 2.3.0
  @provides [main=main,midi_editor] .
  @about Adds a little box to the MIDI editor that displays chord information
  @changelog
    - Show selected chords only when notes overlap
    - Show inversions by default
    - Fix certain chords being incorrectly displayed as octaves
]]
local box_x_offs = 0
local box_y_offs = 0
local box_w_offs = 0
local box_h_offs = 0

local notes_view
local piano_pane
local key_snap_root_cbox

local curr_chords
local curr_sel_chord
local curr_scale_intervals
local curr_start_time
local curr_end_time

local input_timer
local input_note_map = {}
local input_note_cnt = 0

local prev_editor_hwnd
local prev_hash
local prev_take
local prev_mode
local prev_chunk_time
local prev_pane_time
local prev_editor_time
local prev_take_time
local prev_input_idx
local prev_piano_pane_w
local prev_cursor_pos
local prev_chord_name
local prev_color_theme
local prev_mouse_state
local prev_play_state
local prev_input_chord_name
local prev_is_key_snap
local prev_midi_scale_root
local prev_midi_scale
local prev_item_chunk
local prev_key_snap_root

local scale
local font_size
local bitmap
local lice_font

local bm_x, bm_y, bm_w, bm_h

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_SetPosition then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    if reaper.ReaPack_BrowsePackages then
        reaper.ReaPack_BrowsePackages('js_ReaScriptAPI')
    end
    return
end

-- Check REAPER version
local version = tonumber(reaper.GetAppVersion():match('[%d.]+'))
if version < 6.4 then
    reaper.MB('Please install REAPER v6.40 or later', 'Error', 0)
    return
end
if version >= 7.03 then reaper.set_action_options(1) end

local _, _, sec, cmd = reaper.get_action_context()

local extname = 'FTC.LilChordBox'

local user_bg_color = reaper.GetExtState(extname, 'bg_color')
local user_border_color = reaper.GetExtState(extname, 'border_color')
local user_text_color = reaper.GetExtState(extname, 'text_color')
local user_sel_color = reaper.GetExtState(extname, 'sel_color')
local user_play_color = reaper.GetExtState(extname, 'play_color')
local user_rec_color = reaper.GetExtState(extname, 'rec_color')

local os = reaper.GetOS()
local is_windows = os:match('Win')
local is_macos = os:match('OSX') or os:match('macOS')
local is_linux = os:match('Other')

local piano_pane_scale1_w = is_windows and 128 or is_macos and 145 or 161
local edit_box_scale1_w = is_windows and 52 or is_macos and 60 or 68

local box_m = 5
local box_p = 4
local box_x = 7
local box_y = 28
local box_h = 18

if version >= 7 then
    edit_box_scale1_w = is_windows and 46 or is_macos and 52 or 57
    box_m = is_windows and 11 or is_macos and 13 or 15
    box_p = 8
    box_x = is_windows and 12 or is_macos and 14 or 16
    box_y = 34
    box_h = 22
end

local tooltip_delay = 0.6

if is_windows then
    tooltip_delay = select(2, reaper.get_config_var_string('tooltipdelay'))
    tooltip_delay = 2 * (tonumber(tooltip_delay) or 200) / 1000
end

local chord_names = {}
-- Dyads
chord_names['1 2'] = ' minor 2nd'
chord_names['1 3'] = ' major 2nd'
chord_names['1 4'] = ' minor 3rd'
chord_names['1 5'] = ' major 3rd'
chord_names['1 6'] = ' perfect 4th'
chord_names['1 7'] = '5-'
chord_names['1 8'] = '5'
chord_names['1 9'] = ' minor 6th'
chord_names['1 10'] = ' major 6th'
chord_names['1 11'] = ' minor 7th'
chord_names['1 12'] = ' major 7th'
chord_names['1 13'] = ' octave'

-- Compound intervals
chord_names['1 14'] = ' minor 9th'
chord_names['1 15'] = ' major 9th'
chord_names['1 16'] = ' minor 10th'
chord_names['1 17'] = ' major 10th'
chord_names['1 18'] = ' perfect 11th'
chord_names['1 19'] = ' minor 12th'
chord_names['1 20'] = ' perfect 12th'
chord_names['1 21'] = ' minor 13th'
chord_names['1 22'] = ' major 13th'
chord_names['1 23'] = ' minor 14th'
chord_names['1 24'] = ' major 14th'

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
chord_names['1 4 8'] = 'm'
chord_names['1 4 11'] = 'm7 omit5'
chord_names['1 4 8 11'] = 'm7'
chord_names['1 4 12'] = 'm/maj7 omit5'
chord_names['1 4 8 12'] = 'm/maj7'
chord_names['1 3 4 12'] = 'm/maj9 omit5'
chord_names['1 3 4 8 12'] = 'm/maj9'
chord_names['1 3 4 11'] = 'm9 omit5'
chord_names['1 3 4 8 11'] = 'm9'
chord_names['1 3 4 6 11'] = 'm11 omit5'
chord_names['1 4 6 8 11'] = 'm11 omit9'
chord_names['1 3 4 6 8 11'] = 'm11'
chord_names['1 3 4 6 10 11'] = 'm13 omit5'
chord_names['1 4 6 8 10 11'] = 'm13 omit9'
chord_names['1 3 4 6 8 10 11'] = 'm13'
chord_names['1 4 8 10'] = 'm6'
chord_names['1 3 4 10'] = 'm6/9 omit5'
chord_names['1 3 4 8 10'] = 'm6/9'

-- Diminished
chord_names['1 4 7'] = 'dim'
chord_names['1 4 7 10'] = 'dim7'
chord_names['1 4 7 11'] = 'm7b5'
chord_names['1 2 4 8 11'] = 'm7b9'
chord_names['1 2 4 7 11'] = 'm7b5b9'
chord_names['1 2 4 11'] = 'm7b9 omit5'
chord_names['1 3 4 7 11'] = 'm9b5'
chord_names['1 3 4 6 7 11'] = 'm11b5'
chord_names['1 3 5 7 10 11'] = '13b5'

-- Augmented
chord_names['1 5 9'] = 'aug'
chord_names['1 5 9 11'] = 'aug7'
chord_names['1 5 9 12'] = 'aug/maj7'

-- Additions
chord_names['1 3 4'] = 'm add9 omit5'
chord_names['1 3 4 8'] = 'm add9'
chord_names['1 3 5'] = 'maj add9 omit5'
chord_names['1 3 5 8'] = 'maj add9'
chord_names['1 4 6 8'] = 'm add11'
chord_names['1 5 6 8'] = 'maj add11'
chord_names['1 5 10 11'] = '7 add13'

local degrees = {'I', 'II', 'II', 'III', 'III', 'IV', 'V', 'V', 'VI', 'VI',
    'VII', 'VII'}

local note_names_abc_sharp = {'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#',
    'A', 'A#', 'B'}

local note_names_solfege_sharp = {'Do ', 'Do# ', 'Re ', 'Re# ', 'Mi ', 'Fa ',
    'Fa# ', 'Sol ', 'Sol# ', 'La ', 'La# ', 'Si '}

local note_names_abc_flat = {'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab',
    'A', 'Bb', 'B'}

local note_names_solfege_flat = {'Do ', 'Reb ', 'Re ', 'Mib ', 'Mi ', 'Fa ',
    'Solb ', 'Sol ', 'Lab ', 'La ', 'Sib ', 'Si '}

local use_input = reaper.GetExtState(extname, 'input') ~= '0'
local degree_mode = tonumber(reaper.GetExtState(extname, 'degree_only')) or 3

local sel_mode = tonumber(reaper.GetExtState(extname, 'sel_mode')) or 2
local use_inversions = reaper.GetExtState(extname, 'inversions') ~= '0'
local use_solfege = reaper.GetExtState(extname, 'solfege') == '1'
local use_sharps = reaper.GetExtState(extname, 'sharps') == '1'
local use_sharps_autodetect = reaper.GetExtState(extname, 'sharps_auto') ~= '0'
local is_sharp_autodetect = false

local chord_track_name = reaper.GetExtState(extname, 'chord_track_name')
if chord_track_name == '' then chord_track_name = 'Chords' end
local reuse_chord_track = reaper.GetExtState(extname, 'reuse_chord_track') == '1'

function print(msg) reaper.ShowConsoleMsg(tostring(msg) .. '\n') end

function PitchToName(pitch)
    local note_names
    local is_sharp = use_sharps
    if prev_is_key_snap and use_sharps_autodetect then
        is_sharp = is_sharp_autodetect
    end
    if use_solfege then
        if is_sharp then
            note_names = note_names_solfege_sharp
        else
            note_names = note_names_solfege_flat
        end
    else
        if is_sharp then
            note_names = note_names_abc_sharp
        else
            note_names = note_names_abc_flat
        end
    end
    return note_names[pitch % 12 + 1]
end

function AutoDetectSharps(root, midi_scale)
    if root:match('b') then
        is_sharp_autodetect = false
        return
    end

    if root:match('#') then
        is_sharp_autodetect = true
        return
    end

    local is_minor = tonumber(midi_scale) & 8 == 8
    if is_minor then
        is_sharp_autodetect = root == 'E' or root == 'B'
    else
        is_sharp_autodetect = root ~= 'F'
    end
end

function ToggleInversionMode()
    use_inversions = not use_inversions
    reaper.SetExtState(extname, 'inversions', use_inversions and '1' or '0', 1)
end

function ToggleSolfegeMode()
    use_solfege = not use_solfege
    reaper.SetExtState(extname, 'solfege', use_solfege and '1' or '0', 1)
end

function SetSharpMode(is_sharp)
    use_sharps = is_sharp
    reaper.SetExtState(extname, 'sharps', use_sharps and '1' or '0', 1)

    if prev_is_key_snap and use_sharps_autodetect then
        local msg = 'This setting won\'t have any effect as \z
            long as auto-detection during key snap is enabled!'
        reaper.MB(msg, 'Warning', 0)
    end
end

function ToggleSelectionMode()
    sel_mode = sel_mode == 2 and 1 or 2
    reaper.SetExtState(extname, 'sel_mode', sel_mode, 1)
    prev_hash = nil
end

function ToggleSharpsAutoDetect()
    use_sharps_autodetect = not use_sharps_autodetect
    local state = use_sharps_autodetect and '1' or '0'
    reaper.SetExtState(extname, 'sharps_auto', state, 1)
end

function ToggleInputMode()
    use_input = not use_input
    input_note_map = {}
    prev_input_idx = reaper.MIDI_GetRecentInputEvent(0)
    reaper.SetExtState(extname, 'input', use_input and '1' or '0', true)
end

function SetDegreeMode(mode)
    degree_mode = mode
    reaper.SetExtState(extname, 'degree_mode', mode, true)
end

function IdentifyChord(notes)
    -- Get chord root
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
    local interval_cnt = 0
    local key = '1'
    for i = 2, 12 do
        if intervals[i] then
            key = key .. ' ' .. i
            interval_cnt = interval_cnt + 1
        end
    end

    -- Check for compound chords / octaves
    if interval_cnt <= 1 then
        intervals = {}
        for _, note in ipairs(notes) do
            local diff = note.pitch - root
            if diff >= 12 then
                intervals[diff % 12 + 13] = 1
            elseif diff > 0 then
                intervals = {}
                break
            end
        end
        -- Create compound chord key string
        local comp_key = '1'
        for i = 12, 24 do
            if intervals[i] then comp_key = comp_key .. ' ' .. i end
        end

        -- Check if compound chord name exists for key
        if chord_names[comp_key] then return comp_key, root end
    end

    -- Check if chord name exists for key
    if chord_names[key] then return key, root end

    local key_nums = {}
    for key_num in key:gmatch('%d+') do key_nums[#key_nums + 1] = key_num end

    -- Create all possible inversions
    for n = 2, #key_nums do
        local diff = key_nums[n] - key_nums[1]
        intervals = {}
        for i = 1, #key_nums do
            intervals[(key_nums[i] - diff - 1) % 12 + 1] = 1
        end
        local inv_key = '1'
        for i = 2, 12 do
            if intervals[i] then inv_key = inv_key .. ' ' .. i end
        end
        -- Check if chord name exists for inversion key
        if chord_names[inv_key] then return inv_key, root + diff, root end
    end
end

function BuildChord(notes)
    local chord_key, chord_root, inversion_root = IdentifyChord(notes)
    if chord_key then
        local chord = {
            notes = notes,
            root = chord_root,
            key = chord_key,
            inversion_root = inversion_root,
        }
        if notes[1].sppq then
            -- Determine chord start and end ppq position
            local min_eppq = math.maxinteger
            local max_sppq = math.mininteger
            for _, note in ipairs(notes) do
                min_eppq = note.eppq < min_eppq and note.eppq or min_eppq
                max_sppq = note.sppq > max_sppq and note.sppq or max_sppq
            end
            chord.sppq = max_sppq
            chord.eppq = min_eppq
        end
        return chord
    end
end

function GetChordDegree(chord)
    local scale_root = prev_midi_scale_root
    -- Return without degree if a note of the chord is not included in scale
    for _, note in ipairs(chord.notes) do
        if not curr_scale_intervals[(note.pitch - scale_root) % 12 + 1] then
            return
        end
    end
    -- Check the third and and the fifth to get degree info (minor,augmented etc.)
    local scale_note_cnt = 0
    local third
    local fifth
    for i = 0, 8 do
        if curr_scale_intervals[(chord.root + i - scale_root) % 12 + 1] then
            scale_note_cnt = scale_note_cnt + 1
            if scale_note_cnt == 3 then third = i end
            if scale_note_cnt == 5 then fifth = i end
        end
    end
    -- Build degree string based on info
    local degree = degrees[(chord.root - scale_root) % 12 + 1]
    if third == 3 then degree = degree:lower() end
    if fifth == 6 then degree = degree .. 'o' end
    if fifth == 8 then degree = degree .. '+' end

    if use_inversions and chord.inversion_root then
        if (chord.root - chord.inversion_root) % 12 >= 8 then
            degree = degree .. '6'
        else
            degree = degree .. '64'
        end
    end
    return degree
end

function BuildChordName(chord)
    if not chord then return '' end
    if chord.name then return chord.name end
    local name = PitchToName(chord.root) .. chord_names[chord.key]
    if use_inversions and chord.inversion_root then
        name = name .. '/' .. PitchToName(chord.inversion_root)
    end
    if prev_is_key_snap and degree_mode > 1 then
        local degree = GetChordDegree(chord)
        if degree_mode == 2 then
            name = degree or ''
        elseif degree then
            name = name .. ' - ' .. degree
        end
    end
    return name
end

function GetChords(take)
    local _, note_cnt = reaper.MIDI_CountEvts(take)

    local chords = {}
    local notes = {}
    local sel_notes = {}

    local chord_min_eppq

    for i = 0, note_cnt - 1 do
        local _, sel, mute, sppq, eppq, _, pitch = reaper.MIDI_GetNote(take, i)
        if not mute then
            local note_info = {pitch = pitch, sel = sel, sppq = sppq, eppq = eppq}
            if sel then sel_notes[#sel_notes + 1] = note_info end

            chord_min_eppq = chord_min_eppq or eppq
            chord_min_eppq = eppq < chord_min_eppq and eppq or chord_min_eppq

            if sppq >= chord_min_eppq then
                local new_notes = {}
                if #notes >= 2 then
                    local chord = BuildChord(notes)
                    if chord then chords[#chords + 1] = chord end
                    for n = 3, #notes do
                        -- Remove notes that end prior to chord_min_eppq
                        for _, note in ipairs(notes) do
                            if note.eppq > chord_min_eppq then
                                new_notes[#new_notes + 1] = note
                            end
                        end
                        -- Try to build chords
                        chord = BuildChord(new_notes)
                        if chord then
                            chord.sppq = chord_min_eppq
                            chord.eppq = math.min(chord.eppq, sppq)
                            -- Ignore short chords
                            if chord.eppq - chord.sppq >= 240 then
                                chords[#chords + 1] = chord
                            end
                            chord_min_eppq = chord.eppq
                        end
                        new_notes = {}
                    end
                    -- Remove notes that end prior to the start of current note
                    chord_min_eppq = eppq
                    for _, note in ipairs(notes) do
                        if note.eppq > sppq then
                            new_notes[#new_notes + 1] = note
                            if note.eppq < chord_min_eppq then
                                chord_min_eppq = note.eppq
                            end
                        end
                    end
                else
                    chord_min_eppq = eppq
                end
                notes = new_notes
            else
                if #notes >= 2 then
                    local chord = BuildChord(notes)
                    if chord then
                        chord.eppq = math.min(chord.eppq, sppq)
                        -- Ignore very short arpeggiated chords
                        if chord.eppq - chord.sppq >= 180 then
                            chords[#chords + 1] = chord
                        end
                    end
                end
            end
            notes[#notes + 1] = note_info
        end
    end

    local sel_chord
    if #sel_notes >= 2 then
        if sel_mode == 1 then
            sel_chord = BuildChord(sel_notes) or {name = 'none'}
        end
        if sel_mode == 2 then
            -- Check for gaps in selected notes
            local has_gaps = false
            local max_eppq = sel_notes[1].eppq
            for i = 2, #sel_notes do
                local note = sel_notes[i]
                if note.sppq > max_eppq then
                    has_gaps = true
                    break
                end
                if note.eppq > max_eppq then max_eppq = note.eppq end
            end
            if not has_gaps then
                sel_chord = BuildChord(sel_notes) or {name = 'none'}
            end
        end
    end
    if #notes >= 2 then
        local chord = BuildChord(notes)
        if chord then chords[#chords + 1] = chord end
        for n = 3, #notes do
            local new_notes = {}
            -- Remove notes that end prior to chord_min_eppq
            for _, note in ipairs(notes) do
                if note.eppq > chord_min_eppq then
                    new_notes[#new_notes + 1] = note
                end
            end
            -- Try to build chords
            chord = BuildChord(new_notes)
            if chord then
                chord.sppq = chord_min_eppq
                -- Ignore short chords
                if chord.eppq - chord.sppq >= 240 then
                    chords[#chords + 1] = chord
                end
                chord_min_eppq = chord.eppq
            end
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

    prev_input_idx = prev_input_idx or 0

    local idx, buf, _, dev_id = reaper.MIDI_GetRecentInputEvent(0)
    if idx > prev_input_idx then
        local new_idx = idx
        local i = 0
        --TODO Reverse
        repeat
            if prev_input_idx ~= 0 and #buf == 3 then
                if filter_dev_id == 63 or filter_dev_id == dev_id then
                    local msg1 = buf:byte(1)
                    local channel = (msg1 & 0x0F) + 1
                    if filter_channel == 0 or filter_channel == channel then
                        local msg2 = buf:byte(2)
                        local msg3 = buf:byte(3)
                        local is_note_on = msg1 & 0xF0 == 0x90
                        local is_note_off = msg1 & 0xF0 == 0x80
                        -- Check for 0x90 note offs with 0 velocity
                        if is_note_on and msg3 == 0 then
                            is_note_on = false
                            is_note_off = true
                        end
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
        until idx == prev_input_idx

        prev_input_idx = new_idx
    end

    if input_note_cnt >= 2 then
        local notes = {}
        for n = 0, 127 do
            if input_note_map[n] == 1 then
                notes[#notes + 1] = {pitch = n}
            end
        end
        return BuildChord(notes)
    end
end

function IsBitmapHovered(x, y, hwnd)
    x, y = reaper.JS_Window_ScreenToClient(hwnd, x, y)
    return x >= bm_x and y > bm_y and x < bm_x + bm_w and y <= bm_y + bm_h
end

function ConcatPath(...) return table.concat({...}, package.config:sub(1, 1)) end

function GetStartupHookCommandID()
    -- Note: Startup hook commands have to be in the main section
    local _, script_file, section, cmd_id = reaper.get_action_context()
    if section == 0 then
        -- Save command name when main section script is run first
        local cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
        reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
    else
        -- Look for saved command name by main section script
        local cmd_name = reaper.GetExtState(extname, 'hook_cmd_name')
        cmd_id = reaper.NamedCommandLookup(cmd_name)
        if cmd_id == 0 then
            -- Add the script to main section (to get cmd id)
            cmd_id = reaper.AddRemoveReaScript(true, 0, script_file, true)
            if cmd_id ~= 0 then
                -- Save command name to avoid adding script on next run
                cmd_name = '_' .. reaper.ReverseNamedCommandLookup(cmd_id)
                reaper.SetExtState(extname, 'hook_cmd_name', cmd_name, true)
            end
        end
    end
    return cmd_id
end

function IsStartupHookEnabled()
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    if reaper.file_exists(startup_path) then
        -- Read content of __startup.lua
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return false end
        local content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        -- Check if line exists and whether it is commented out
        if s and e then
            local hook = content:sub(s, e)
            local comment = hook:match('[^\n]*%-%-[^\n]*reaper%.Main_OnCommand')
            if not comment then return true end
        end
    end
    return false
end

function SetStartupHookEnabled(is_enabled, comment, var_name)
    local res_path = reaper.GetResourcePath()
    local startup_path = ConcatPath(res_path, 'Scripts', '__startup.lua')
    local cmd_id = GetStartupHookCommandID()
    local cmd_name = reaper.ReverseNamedCommandLookup(cmd_id)

    local content = ''
    local hook_exists = false

    -- Check startup script for existing hook
    if reaper.file_exists(startup_path) then
        local startup_file = io.open(startup_path, 'r')
        if not startup_file then return end
        content = startup_file:read('*a')
        startup_file:close()

        -- Find line that contains command id (also next line if available)
        local pattern = '[^\n]+' .. cmd_name .. '\'?\n?[^\n]+'
        local s, e = content:find(pattern)

        if s and e then
            -- Add/remove comment from existing startup hook
            local hook = content:sub(s, e)
            local repl = (is_enabled and '' or '-- ') .. 'reaper.Main_OnCommand'
            hook = hook:gsub('[^\n]*reaper%.Main_OnCommand', repl, 1)
            content = content:sub(1, s - 1) .. hook .. content:sub(e + 1)

            -- Write changes to file
            local new_startup_file = io.open(startup_path, 'w')
            if not new_startup_file then return end
            new_startup_file:write(content)
            new_startup_file:close()

            hook_exists = true
        end
    end

    -- Create startup hook
    if is_enabled and not hook_exists then
        comment = comment and '-- ' .. comment .. '\n' or ''
        var_name = var_name or 'cmd_name'
        local hook = '%slocal %s = \'_%s\'\nreaper.\z
            Main_OnCommand(reaper.NamedCommandLookup(%s), 0)\n\n'
        hook = hook:format(comment, var_name, cmd_name, var_name)
        local startup_file = io.open(startup_path, 'w')
        if not startup_file then return end
        startup_file:write(hook .. content)
        startup_file:close()
    end
end

function SetCustomColors()
    local title = 'Custom Colors'
    local captions = 'Record icon: (e.g. #FF0000),Selection icon:,Play icon\z
        :,Background:,Border:,Text:'

    local curr_vals = {}
    local function AddCurrentValue(color)
        local hex_num = tonumber(color, 16)
        curr_vals[#curr_vals + 1] = hex_num and ('#%.6X'):format(hex_num) or ''
    end

    AddCurrentValue(user_rec_color)
    AddCurrentValue(user_sel_color)
    AddCurrentValue(user_play_color)
    AddCurrentValue(user_bg_color)
    AddCurrentValue(user_border_color)
    AddCurrentValue(user_text_color)

    local curr_vals_str = table.concat(curr_vals, ',')

    local ret, inputs = reaper.GetUserInputs(title, 6, captions, curr_vals_str)
    if not ret then return end

    local colors = {}
    for input in (inputs .. ','):gmatch('[^,]*') do
        colors[#colors + 1] = input:gsub('^#', '')
    end

    local invalid_flag = false
    local function ValidateColor(color)
        local is_valid = #color <= 6 and tonumber(color, 16)
        if not is_valid and color ~= '' then invalid_flag = true end
        return is_valid and color or ''
    end

    user_rec_color = ValidateColor(colors[1])
    user_sel_color = ValidateColor(colors[2])
    user_play_color = ValidateColor(colors[3])
    user_bg_color = ValidateColor(colors[4])
    user_border_color = ValidateColor(colors[5])
    user_text_color = ValidateColor(colors[6])

    reaper.SetExtState(extname, 'rec_color', user_rec_color, true)
    reaper.SetExtState(extname, 'sel_color', user_sel_color, true)
    reaper.SetExtState(extname, 'play_color', user_play_color, true)
    reaper.SetExtState(extname, 'bg_color', user_bg_color, true)
    reaper.SetExtState(extname, 'border_color', user_border_color, true)
    reaper.SetExtState(extname, 'text_color', user_text_color, true)

    if invalid_flag then
        local msg = 'Please specify colors in hexadecimal format! (#RRGGBB)'
        reaper.MB(msg, 'Invalid input', 0)
    end
end

function MenuCreateRecursive(menu)
    local str = ''
    if menu.title then str = str .. '>' .. menu.title .. '|' end

    for i, entry in ipairs(menu) do
        if #entry > 0 then
            str = str .. MenuCreateRecursive(entry) .. '|'
        else
            local arg = entry.arg

            if entry.IsGrayed and entry.IsGrayed(arg) or entry.is_grayed then
                str = str .. '#'
            end

            if entry.IsChecked and entry.IsChecked(arg) or entry.is_checked then
                str = str .. '!'
            end

            if menu.title and i == #menu then str = str .. '<' end

            if entry.title or entry.separator then
                str = str .. (entry.title or '') .. '|'
            end
        end
    end
    return str:sub(1, #str - 1)
end

function MenuReturnRecursive(menu, idx, i)
    i = i or 1
    for _, entry in ipairs(menu) do
        if #entry > 0 then
            i = MenuReturnRecursive(entry, idx, i)
            if i < 0 then return i end
        elseif entry.title then
            if i == math.floor(idx) then
                if entry.OnReturn then entry.OnReturn(entry.arg) end
                return -1
            end
            i = i + 1
        end
    end
    return i
end

function ShowMenu(menu_str)
    -- Toggle fullscreen
    local is_full_screen = reaper.GetToggleCommandState(40346) == 1

    -- On Windows and MacOS (fullscreen), a dummy window is required to show menu
    if is_windows or is_macos and is_full_screen then
        local offs = is_windows and {x = 10, y = 20} or {x = 0, y = 0}
        local x, y = reaper.GetMousePosition()
        gfx.init('LCB', 0, 0, 0, x + offs.x, y + offs.y)
        gfx.x, gfx.y = gfx.screentoclient(x + offs.x / 2, y + offs.y / 2)
        if reaper.JS_Window_Find then
            local hwnd = reaper.JS_Window_FindTop('LCB', true)
            reaper.JS_Window_Show(hwnd, 'HIDE')
        end
    end
    local ret = gfx.showmenu(menu_str)
    gfx.quit()
    return ret
end

function GetTakeChunk(take, item_chunk)
    if not item_chunk then
        local item = reaper.GetMediaItemTake_Item(take)
        item_chunk = select(2, reaper.GetItemStateChunk(item, '', false))
    end
    local tk = reaper.GetMediaItemTakeInfo_Value(take, 'IP_TAKENUMBER')

    local take_start_ptr = 0
    local take_end_ptr = 0

    for _ = 0, tk do
        take_start_ptr = take_end_ptr
        take_end_ptr = item_chunk:find('\nTAKE[%s\n]', take_start_ptr + 1)
    end
    return item_chunk:sub(take_start_ptr, take_end_ptr)
end

function GetTakeChunkHZoom(chunk)
    local pattern = 'CFGEDITVIEW (.-) (.-) '
    return chunk:match(pattern)
end

function GetTakeChunkTimeBase(chunk)
    local pattern = 'CFGEDIT ' .. ('.- '):rep(18) .. '(.-) '
    return tonumber(chunk:match(pattern))
end

function GetMIDIEditorView(hwnd, item_chunk)
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    local GetProjTimeFromPPQ = reaper.MIDI_GetProjTimeFromPPQPos

    local take_chunk = GetTakeChunk(take, item_chunk)
    local start_ppq, hzoom_lvl = GetTakeChunkHZoom(take_chunk)
    if not start_ppq then return end

    local timebase = GetTakeChunkTimeBase(take_chunk) or 0
    -- 0 = Beats (proj) 1 = Project synced 2 = Time (proj) 4 = Beats (source)

    local end_ppq
    local start_time, end_time

    local midi_view = reaper.JS_Window_FindChildByID(hwnd, 1001)
    local _, width_in_pixels = reaper.JS_Window_GetClientSize(midi_view)
    if timebase == 0 or timebase == 4 then
        -- For timebase 0 and 4, hzoom_lvl is in pixel/ppq
        end_ppq = start_ppq + width_in_pixels / hzoom_lvl
    else
        -- For timebase 1 and 2, hzoom_lvl is in pixel/time
        start_time = GetProjTimeFromPPQ(take, start_ppq)
        end_time = start_time + width_in_pixels / hzoom_lvl
    end

    -- Convert ppq to time based units
    start_time = start_time or GetProjTimeFromPPQ(take, start_ppq)
    end_time = end_time or GetProjTimeFromPPQ(take, end_ppq)

    return start_time, end_time
end

function SetChordTrackName()
    local title = 'Chord track'
    local caption = 'Track name:,extrawidth=100'
    local input_text = chord_track_name

    local ret, user_text = reaper.GetUserInputs(title, 1, caption, input_text)
    if not ret then return end

    chord_track_name = user_text == '' and 'Chords' or user_text
    reaper.SetExtState(extname, 'chord_track_name', chord_track_name, 1)
end

function ToggleReuseChordTrack()
    reuse_chord_track = not reuse_chord_track
    local state = reuse_chord_track and '1' or '0'
    reaper.SetExtState(extname, 'reuse_chord_track', state, 1)
end

function CreateChordTrack()
    local hwnd = reaper.MIDIEditor_GetActive()
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    reaper.SetExtState(extname, 'last_export', 'chord_track', 1)

    local item = reaper.GetMediaItemTake_Item(take)
    local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_pos = item_start_pos + item_length

    local AddItem = reaper.AddMediaItemToTrack
    local SetItemInfo = reaper.SetMediaItemInfo_Value
    local GetItemInfo = reaper.GetMediaItemInfo_Value
    local GetSetItemInfo = reaper.GetSetMediaItemInfo_String
    local GetTrackInfo = reaper.GetMediaTrackInfo_Value
    local GetSetTrackInfo = reaper.GetSetMediaTrackInfo_String

    local GetProjTimeFromPPQPos = reaper.MIDI_GetProjTimeFromPPQPos
    local GetPPQPosFromProjTime = reaper.MIDI_GetPPQPosFromProjTime

    reaper.Undo_BeginBlock()

    local midi_track = reaper.GetMediaItem_Track(item)
    local midi_track_num = GetTrackInfo(midi_track, 'IP_TRACKNUMBER')

    local chord_track

    -- Find existing chord track
    if reuse_chord_track then
        for i = midi_track_num - 2, 0, -1 do
            local track = reaper.GetTrack(0, i)
            local _, track_name = GetSetTrackInfo(track, 'P_NAME', '', 0)
            if track_name == chord_track_name then
                chord_track = track
                break
            end
        end
    end

    -- Delete/trim conflicting items on chord track
    if chord_track then
        for i = reaper.CountTrackMediaItems(chord_track) - 1, 0, -1 do
            local chord_item = reaper.GetTrackMediaItem(chord_track, i)
            local length = GetItemInfo(chord_item, 'D_LENGTH')
            local start_pos = GetItemInfo(chord_item, 'D_POSITION')
            local end_pos = start_pos + length
            if start_pos < item_end_pos and end_pos > item_start_pos then
                if start_pos < item_start_pos - 0.01 then
                    local diff = item_start_pos - start_pos
                    SetItemInfo(chord_item, 'D_LENGTH', length - diff)
                elseif end_pos > item_end_pos + 0.01 then
                    local diff = item_end_pos - start_pos
                    SetItemInfo(chord_item, 'D_LENGTH', length - diff)
                    SetItemInfo(chord_item, 'D_POSITION', start_pos + diff)
                else
                    reaper.DeleteTrackMediaItem(chord_track, chord_item)
                end
            end
        end
    end

    if not chord_track then
        -- Create chord track
        reaper.InsertTrackAtIndex(midi_track_num - 1, true)
        chord_track = reaper.GetTrack(0, midi_track_num - 1)
        GetSetTrackInfo(chord_track, 'P_NAME', chord_track_name, 1)
    end

    local loops = 1
    local source_ppq_length = 0
    -- Calculate how often item is looped (and loop length)
    if GetItemInfo(item, 'B_LOOPSRC') == 1 then
        local source = reaper.GetMediaItemTake_Source(take)
        local source_length = reaper.GetMediaSourceLength(source)
        local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
        local end_qn = start_qn + source_length
        source_ppq_length = reaper.MIDI_GetPPQPosFromProjQN(take, end_qn)

        local item_start_ppq = GetPPQPosFromProjTime(take, item_start_pos)
        local item_end_ppq = GetPPQPosFromProjTime(take, item_end_pos)
        local item_ppq_length = item_end_ppq - item_start_ppq
        -- Note: Looped items repeat after full ppq length
        loops = math.ceil(item_ppq_length / source_ppq_length)
    end

    local prev_name
    local prev_start_pos
    local prev_end_pos

    for loop = 1, loops do
        for _, chord in ipairs(curr_chords) do
            local loop_ppq = source_ppq_length * (loop - 1)
            local start_pos = GetProjTimeFromPPQPos(take, chord.sppq + loop_ppq)
            local end_pos = GetProjTimeFromPPQPos(take, chord.eppq + loop_ppq)

            if prev_start_pos then
                local reg_start_pos = prev_start_pos
                local reg_end_pos = start_pos
                if reg_start_pos < item_end_pos and reg_end_pos > item_start_pos then
                    reg_start_pos = math.max(reg_start_pos, item_start_pos)
                    if reg_end_pos > item_end_pos then
                        reg_end_pos = math.min(prev_end_pos, item_end_pos)
                    end
                    if prev_name ~= '' then
                        local chord_item = AddItem(chord_track)
                        local length = reg_end_pos - reg_start_pos
                        SetItemInfo(chord_item, 'D_POSITION', reg_start_pos)
                        SetItemInfo(chord_item, 'D_LENGTH', length)
                        GetSetItemInfo(chord_item, 'P_NOTES', prev_name, 1)
                    end
                end
            end

            prev_name = BuildChordName(chord)
            prev_start_pos = start_pos
            prev_end_pos = end_pos
        end
    end

    if prev_start_pos then
        local reg_start_pos = prev_start_pos
        local reg_end_pos = prev_end_pos
        if reg_start_pos < item_end_pos and reg_end_pos > item_start_pos then
            reg_start_pos = math.max(reg_start_pos, item_start_pos)
            reg_end_pos = math.min(reg_end_pos, item_end_pos)
            if prev_name ~= '' then
                local chord_item = AddItem(chord_track)
                local length = reg_end_pos - reg_start_pos
                SetItemInfo(chord_item, 'D_POSITION', reg_start_pos)
                SetItemInfo(chord_item, 'D_LENGTH', length)
                GetSetItemInfo(chord_item, 'P_NOTES', prev_name, 1)
            end
        end
    end

    -- Combine regions with same chord name
    local prev_name
    local prev_chord_item
    for i = reaper.CountTrackMediaItems(chord_track) - 1, 0, -1 do
        local chord_item = reaper.GetTrackMediaItem(chord_track, i)
        local start_pos = GetItemInfo(chord_item, 'D_POSITION')
        if start_pos >= item_start_pos and start_pos < item_end_pos then
            local _, name = GetSetItemInfo(chord_item, 'P_NOTES', '', 0)
            if name == prev_name then
                local prev_length = GetItemInfo(prev_chord_item, 'D_LENGTH')
                local prev_start_pos = GetItemInfo(prev_chord_item, 'D_POSITION')
                local prev_end_pos = prev_start_pos + prev_length

                reaper.DeleteTrackMediaItem(chord_track, prev_chord_item)

                local curr_start_pos = GetItemInfo(chord_item, 'D_POSITION')
                SetItemInfo(chord_item, 'D_LENGTH', prev_end_pos - curr_start_pos)
            end
            prev_name = name
            prev_chord_item = chord_item
        end
    end
    reaper.UpdateArrange()
    reaper.Undo_EndBlock('Create chord track', -1)
end

function CreateChordProjectRegions()
    local hwnd = reaper.MIDIEditor_GetActive()
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    reaper.SetExtState(extname, 'last_export', 'project_region', 1)

    local item = reaper.GetMediaItemTake_Item(take)
    local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_pos = item_start_pos + item_length

    local EnumMarkers = reaper.EnumProjectMarkers2
    local SetMarker = reaper.SetProjectMarker2
    local AddMarker = reaper.AddProjectMarker

    local GetProjTimeFromPPQPos = reaper.MIDI_GetProjTimeFromPPQPos
    local GetPPQPosFromProjTime = reaper.MIDI_GetPPQPosFromProjTime

    reaper.Undo_BeginBlock()

    -- Delete regions over item
    for i = reaper.CountProjectMarkers(0) - 1, 0, -1 do
        local _, is_reg, start_pos, end_pos, name, idx = EnumMarkers(0, i)
        if is_reg then
            -- Delete regions within item bounds
            if start_pos >= item_start_pos and end_pos <= item_end_pos then
                reaper.DeleteProjectMarker(0, idx, true)
            end
            -- Shorten regions that exceed item end
            if start_pos < item_end_pos and end_pos > item_end_pos then
                SetMarker(0, idx, true, item_end_pos, end_pos, name)
            end
            -- Shorten regions that proceed item start
            if start_pos < item_start_pos and end_pos > item_start_pos then
                SetMarker(0, idx, true, start_pos, item_start_pos, name)
            end
        end
    end

    -- Note: Keep this for debugging purposes
    --[[ for _, chord in ipairs(curr_chords) do
        local start_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, chord.sppq)
        local end_pos = reaper.MIDI_GetProjTimeFromPPQPos(take, chord.eppq)

        print(chord.sppq .. ' ' .. chord.eppq)
        local chord_name = BuildChordName(chord)
        reaper.AddProjectMarker(0, true, start_pos, end_pos, chord_name, -1)
    end
    reaper.Undo_EndBlock('Create chord regions', -1)
    if true then return end ]]
    local loops = 1
    local source_ppq_length = 0
    -- Calculate how often item is looped (and loop length)
    if reaper.GetMediaItemInfo_Value(item, 'B_LOOPSRC') == 1 then
        local source = reaper.GetMediaItemTake_Source(take)
        local source_length = reaper.GetMediaSourceLength(source)
        local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
        local end_qn = start_qn + source_length
        source_ppq_length = reaper.MIDI_GetPPQPosFromProjQN(take, end_qn)

        local item_start_ppq = GetPPQPosFromProjTime(take, item_start_pos)
        local item_end_ppq = GetPPQPosFromProjTime(take, item_end_pos)
        local item_ppq_length = item_end_ppq - item_start_ppq
        -- Note: Looped items repeat after full ppq length
        loops = math.ceil(item_ppq_length / source_ppq_length)
    end

    local prev_name
    local prev_start_pos
    local prev_end_pos

    for loop = 1, loops do
        for _, chord in ipairs(curr_chords) do
            local loop_ppq = source_ppq_length * (loop - 1)
            local start_pos = GetProjTimeFromPPQPos(take, chord.sppq + loop_ppq)
            local end_pos = GetProjTimeFromPPQPos(take, chord.eppq + loop_ppq)

            if prev_start_pos then
                local reg_start_pos = prev_start_pos
                local reg_end_pos = start_pos
                if reg_start_pos < item_end_pos and reg_end_pos > item_start_pos then
                    reg_start_pos = math.max(reg_start_pos, item_start_pos)
                    if reg_end_pos > item_end_pos then
                        reg_end_pos = math.min(prev_end_pos, item_end_pos)
                    end
                    if prev_name ~= '' then
                        AddMarker(0, 1, reg_start_pos, reg_end_pos, prev_name, -1)
                    end
                end
            end

            prev_name = BuildChordName(chord)
            prev_start_pos = start_pos
            prev_end_pos = end_pos
        end
    end

    if prev_start_pos then
        local reg_start_pos = prev_start_pos
        local reg_end_pos = prev_end_pos
        if reg_start_pos < item_end_pos and reg_end_pos > item_start_pos then
            reg_start_pos = math.max(reg_start_pos, item_start_pos)
            reg_end_pos = math.min(reg_end_pos, item_end_pos)
            if prev_name ~= '' then
                AddMarker(0, 1, reg_start_pos, reg_end_pos, prev_name, -1)
            end
        end
    end

    -- Combine regions with same chord name
    local prev_name
    local prev_idx
    local prev_end_pos
    for i = reaper.CountProjectMarkers(0) - 1, 0, -1 do
        local _, is_reg, start_pos, end_pos, name, idx = EnumMarkers(0, i)
        if is_reg then
            if start_pos >= item_start_pos and end_pos <= item_end_pos then
                if name == prev_name then
                    reaper.DeleteProjectMarker(0, prev_idx, true)
                    SetMarker(0, idx, true, start_pos, prev_end_pos, name)
                    end_pos = prev_end_pos
                end
                prev_name = name
                prev_idx = idx
                prev_end_pos = end_pos
            end
        end
    end
    reaper.Undo_EndBlock('Create chord project regions', -1)
end

function CreateChordProjectMarkers()
    local hwnd = reaper.MIDIEditor_GetActive()
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    reaper.SetExtState(extname, 'last_export', 'project_marker', 1)

    local item = reaper.GetMediaItemTake_Item(take)
    local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_pos = item_start_pos + item_length

    local EnumMarkers = reaper.EnumProjectMarkers2
    local AddMarker = reaper.AddProjectMarker

    local GetProjTimeFromPPQPos = reaper.MIDI_GetProjTimeFromPPQPos
    local GetPPQPosFromProjTime = reaper.MIDI_GetPPQPosFromProjTime

    reaper.Undo_BeginBlock()

    -- Delete markers over item
    for i = reaper.CountProjectMarkers(0) - 1, 0, -1 do
        local _, is_reg, start_pos, end_pos, name, idx = EnumMarkers(0, i)
        if not is_reg then
            if start_pos >= item_start_pos and end_pos < item_end_pos then
                reaper.DeleteProjectMarker(0, idx, false)
            end
        end
    end

    local loops = 1
    local source_ppq_length = 0
    -- Calculate how often item is looped (and loop length)
    if reaper.GetMediaItemInfo_Value(item, 'B_LOOPSRC') == 1 then
        local source = reaper.GetMediaItemTake_Source(take)
        local source_length = reaper.GetMediaSourceLength(source)
        local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
        local end_qn = start_qn + source_length
        source_ppq_length = reaper.MIDI_GetPPQPosFromProjQN(take, end_qn)

        local item_start_ppq = GetPPQPosFromProjTime(take, item_start_pos)
        local item_end_ppq = GetPPQPosFromProjTime(take, item_end_pos)
        local item_ppq_length = item_end_ppq - item_start_ppq
        -- Note: Looped items repeat after full ppq length
        loops = math.ceil(item_ppq_length / source_ppq_length)
    end

    for loop = 1, loops do
        local prev_name
        for _, chord in ipairs(curr_chords) do
            local loop_ppq = source_ppq_length * (loop - 1)
            local start_pos = GetProjTimeFromPPQPos(take, chord.sppq + loop_ppq)
            local name = BuildChordName(chord)
            if name ~= '' and name ~= prev_name then
                AddMarker(0, false, start_pos, 0, name, -1)
            end
            prev_name = name
        end
    end

    reaper.Undo_EndBlock('Create chord project markers', -1)
end

function CreateChordTakeMarkers()
    local hwnd = reaper.MIDIEditor_GetActive()
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    reaper.SetExtState(extname, 'last_export', 'take_marker', 1)

    local item = reaper.GetMediaItemTake_Item(take)
    local item_length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local item_start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local item_end_pos = item_start_pos + item_length

    local GetProjTimeFromPPQPos = reaper.MIDI_GetProjTimeFromPPQPos
    local GetPPQPosFromProjTime = reaper.MIDI_GetPPQPosFromProjTime

    reaper.Undo_BeginBlock()

    -- Delete take markers
    for i = reaper.GetNumTakeMarkers(take) - 1, 0, -1 do
        reaper.DeleteTakeMarker(take, i)
    end

    local loops = 1
    local source_ppq_length = 0
    -- Calculate how often item is looped (and loop length)
    if reaper.GetMediaItemInfo_Value(item, 'B_LOOPSRC') == 1 then
        local source = reaper.GetMediaItemTake_Source(take)
        local source_length = reaper.GetMediaSourceLength(source)
        local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
        local end_qn = start_qn + source_length
        source_ppq_length = reaper.MIDI_GetPPQPosFromProjQN(take, end_qn)

        local item_start_ppq = GetPPQPosFromProjTime(take, item_start_pos)
        local item_end_ppq = GetPPQPosFromProjTime(take, item_end_pos)
        local item_ppq_length = item_end_ppq - item_start_ppq
        -- Note: Looped items repeat after full ppq length
        loops = math.ceil(item_ppq_length / source_ppq_length)
    end

    for loop = 1, loops do
        local prev_name
        for _, chord in ipairs(curr_chords) do
            local loop_ppq = source_ppq_length * (loop - 1)
            local start_pos = GetProjTimeFromPPQPos(take, chord.sppq + loop_ppq)
            local name = BuildChordName(chord)
            if name ~= '' and name ~= prev_name then
                local marker_pos = start_pos - item_start_pos
                reaper.SetTakeMarker(take, -1, name, marker_pos)
            end
            prev_name = name
        end
    end
    reaper.Undo_EndBlock('Create chord take markers', -1)
end

function CreateChordTextEvents()
    local hwnd = reaper.MIDIEditor_GetActive()
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    reaper.SetExtState(extname, 'last_export', 'text_event', 1)

    reaper.Undo_BeginBlock()
    local _, _, _, evt_cnt = reaper.MIDI_CountEvts(take)

    -- Delete text event markers
    for i = evt_cnt - 1, 0, -1 do
        local ret, _, _, _, evt_type = reaper.MIDI_GetTextSysexEvt(take, i)
        if ret and evt_type == 6 then
            reaper.MIDI_DeleteTextSysexEvt(take, i)
        end
    end
    -- Add chord text event markers
    local prev_name
    for _, chord in ipairs(curr_chords) do
        local name = BuildChordName(chord)
        if name ~= '' and name ~= prev_name then
            reaper.MIDI_InsertTextSysexEvt(take, 0, 0, chord.sppq, 6, name)
        end
        prev_name = name
    end

    -- CC: Set CC lane to Text Events
    reaper.MIDIEditor_OnCommand(hwnd, 40370)

    reaper.Undo_EndBlock('Create chord text events', -1)
end

function CreateChordNotationEvents()
    local hwnd = reaper.MIDIEditor_GetActive()
    local take = reaper.MIDIEditor_GetTake(hwnd)
    if not reaper.ValidatePtr(take, 'MediaItem_Take*') then return end

    reaper.SetExtState(extname, 'last_export', 'notation_event', 1)

    reaper.Undo_BeginBlock()
    local _, _, _, evt_cnt = reaper.MIDI_CountEvts(take)

    -- Delete text event markers
    for i = evt_cnt - 1, 0, -1 do
        local ret, _, _, _, evt_type, msg = reaper.MIDI_GetTextSysexEvt(take, i)
        if ret and evt_type == 15 and msg:match('" chord$') then
            reaper.MIDI_DeleteTextSysexEvt(take, i)
        end
    end
    -- Add chord text event markers
    local prev_name
    for _, chord in ipairs(curr_chords) do
        local name = BuildChordName(chord)
        if name ~= '' and name ~= prev_name then
            local msg = 'TRAC custom "' .. name .. '" chord'
            reaper.MIDI_InsertTextSysexEvt(take, 0, 0, chord.sppq, 15, msg)
        end
        prev_name = name
    end

    -- CC: Set CC lane to Text Events
    reaper.MIDIEditor_OnCommand(hwnd, 40370)
    -- CC: Next CC lane
    reaper.MIDIEditor_OnCommand(hwnd, 40234)

    reaper.Undo_EndBlock('Create chord notation events', -1)
end

function GetCursorPPQPosition(take, cursor_pos)
    local cursor_ppq = reaper.MIDI_GetPPQPosFromProjTime(take, cursor_pos)

    -- In timebase source simply return cursor ppq position
    local is_timebase_source = reaper.GetToggleCommandStateEx(32060, 40470) == 1
    if is_timebase_source then return cursor_ppq end

    local item = reaper.GetMediaItemTake_Item(take)
    local length = reaper.GetMediaItemInfo_Value(item, 'D_LENGTH')
    local start_pos = reaper.GetMediaItemInfo_Value(item, 'D_POSITION')
    local end_pos = start_pos + length

    -- Check that cursor position is within arrange view item bounds
    if cursor_pos < start_pos or cursor_pos > end_pos then return end

    -- Adjust cursor ppq position for looped arrange view items
    if reaper.GetMediaItemInfo_Value(item, 'B_LOOPSRC') == 1 then
        local source = reaper.GetMediaItemTake_Source(take)
        local source_length = reaper.GetMediaSourceLength(source)
        local start_qn = reaper.MIDI_GetProjQNFromPPQPos(take, 0)
        local end_qn = start_qn + source_length
        local source_ppq_length = reaper.MIDI_GetPPQPosFromProjQN(take, end_qn)

        -- Note: Looped items repeat after full ppq length
        cursor_ppq = cursor_ppq % source_ppq_length
    end

    return cursor_ppq
end

function ShowChordBoxMenu()
    local menu = {
        {
            title = 'Export chords as',
            {
                title = 'Project regions',
                OnReturn = CreateChordProjectRegions,
            },
            {
                title = 'Project markers',
                OnReturn = CreateChordProjectMarkers,
            },
            {
                title = 'Take markers',
                OnReturn = CreateChordTakeMarkers,
            },
            {
                title = 'Text events',
                OnReturn = CreateChordTextEvents,
            },
            {
                title = 'Notation events',
                OnReturn = CreateChordNotationEvents,
            },
            {
                title = 'Chord track',
                OnReturn = CreateChordTrack,
            },
        },
        {
            title = 'Options',
            {
                title = 'Display chords as',
                {
                    title = 'Flat',
                    OnReturn = SetSharpMode,
                    is_checked = not use_sharps,
                    arg = false,
                },
                {
                    title = 'Sharp',
                    OnReturn = SetSharpMode,
                    is_checked = use_sharps,
                    arg = true,
                },
                {separator = true},
                {
                    title = 'Show inversions',
                    OnReturn = ToggleInversionMode,
                    is_checked = use_inversions,
                },
                {
                    title = 'Solfège (do, re, mi)',
                    OnReturn = ToggleSolfegeMode,
                    is_checked = use_solfege,
                },
            },
            {
                title = 'Key snap',
                {
                    title = 'Display chord and degree',
                    OnReturn = SetDegreeMode,
                    is_checked = degree_mode == 3,
                    arg = 3,
                },
                {
                    title = 'Display degree only',
                    OnReturn = SetDegreeMode,
                    is_checked = degree_mode == 2,
                    arg = 2,
                },
                {
                    title = 'Display chord only',
                    OnReturn = SetDegreeMode,
                    is_checked = degree_mode == 1,
                    arg = 1,
                },
                {separator = true},
                {
                    title = 'Auto-detect sharps/flats',
                    OnReturn = ToggleSharpsAutoDetect,
                    is_checked = use_sharps_autodetect,
                },
            },
            {
                title = 'Chord track',
                {
                    title = 'Set track name...',
                    OnReturn = SetChordTrackName,
                },
                {
                    title = 'Reuse existing chord track',
                    OnReturn = ToggleReuseChordTrack,
                    is_checked = reuse_chord_track,
                },
            },
            {
                title = 'Show selected chord only when notes overlap',
                OnReturn = ToggleSelectionMode,
                is_checked = sel_mode == 2,
            },
            {
                title = 'Analyze incoming MIDI (live input)',
                OnReturn = ToggleInputMode,
                is_checked = use_input,
            },
        },
        {title = 'Customize...', OnReturn = SetCustomColors},
        {
            title = 'Run script on startup',
            IsChecked = IsStartupHookEnabled,
            OnReturn = function()
                local is_enabled = IsStartupHookEnabled()
                local comment = 'Start script: Lil Chordbox'
                local var_name = 'chord_box_cmd_name'
                SetStartupHookEnabled(not is_enabled, comment, var_name)
            end,
        },
    }

    local menu_str = MenuCreateRecursive(menu)
    local ret = ShowMenu(menu_str)
    MenuReturnRecursive(menu, ret)
end

function DrawLICE(chord, mode)
    reaper.JS_LICE_Clear(bitmap, 0)

    local alpha = 0xFF000000
    local bg_color, hl_color, sh_color
    local play_color, sel_color, rec_color

    local text_color = reaper.GetThemeColor('col_main_text', 0) | alpha

    if user_bg_color ~= '' then
        bg_color = tonumber(user_bg_color, 16) | alpha
    else
        bg_color = reaper.GetThemeColor('col_main_editbk', 0) | alpha
    end
    if user_border_color ~= '' then
        hl_color = tonumber(user_border_color, 16) | alpha
        sh_color = hl_color
    else
        hl_color = reaper.GetThemeColor('col_main_3dhl', 0) | alpha
        sh_color = reaper.GetThemeColor('col_main_3dsh', 0) | alpha
    end
    if user_play_color ~= '' then
        play_color = tonumber(user_play_color, 16) | alpha
    else
        play_color = text_color
    end
    if user_sel_color ~= '' then
        sel_color = tonumber(user_sel_color, 16) | alpha
    else
        sel_color = text_color
    end
    if user_rec_color ~= '' then
        rec_color = tonumber(user_rec_color, 16) | alpha
    else
        rec_color = text_color
    end
    if user_text_color ~= '' then
        text_color = tonumber(user_text_color, 16) | alpha
    end

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
    local text_w, text_h = gfx.measurestr(chord)
    local text_x = (bm_w - text_w) // 2
    local text_y = (bm_h - text_h) // 2
    if is_macos then text_y = text_y + 1 end

    -- Position icon at start of text
    local icon_x = math.floor(text_x - 8 * scale)
    -- Move text slightly to the right when icon is drawn
    text_x = mode == 0 and text_x or math.floor(text_x + 5 * scale)

    if mode == 1 and chord ~= '' then
        local h = bm_h // 2 - 1
        -- Ensure triangle height is uneven
        if h % 2 ~= 1 then h = h - 1 end
        local x1, y1 = icon_x, (bm_h - h) // 2
        local x2, y2 = icon_x, y1 + h
        local x3, y3 = icon_x + h, y1 + h // 2

        reaper.JS_LICE_Line(bitmap, x1, y1, x3, y3, play_color, 1, 0, 1)
        reaper.JS_LICE_Line(bitmap, x2, y2, x3, y3 + 1, play_color, 1, 0, 1)
        reaper.JS_LICE_FillTriangle(bitmap, x1, y1, x2, y2, x3, y3, play_color,
            1, 0)
    end

    if mode == 2 then
        local h = bm_h // 2
        -- Ensure square height can be divided by 4
        local mod = h % 4
        if mod ~= 0 then h = h - mod end
        local x1, y1 = icon_x, (bm_h - h) // 2
        local x2, y2 = icon_x + h / 4, y1 + h / 4
        local w1, w2 = h, h / 2
        reaper.JS_LICE_FillRect(bitmap, x1, y1, w1, w1, sel_color, 1, 0)
        reaper.JS_LICE_FillRect(bitmap, x2, y2, w2, w2, bg_color, 1, 0)
    end

    if mode == 3 and chord ~= '' then
        local x, y = math.floor(icon_x + 5 * scale), bm_h // 2
        local r = math.floor(2.5 * scale * 10) / 10
        reaper.JS_LICE_FillCircle(bitmap, x, y, r, rec_color, 1, 1, true)
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
    local time = reaper.time_precise()
    local editor_hwnd = prev_editor_hwnd
    -- Find MIDI editor window
    if not prev_editor_time or time > prev_editor_time + 0.2 then
        prev_editor_time = time
        editor_hwnd = reaper.MIDIEditor_GetActive()
    elseif editor_hwnd and not reaper.ValidatePtr(editor_hwnd, 'HWND*') then
        editor_hwnd = reaper.MIDIEditor_GetActive()
    end

    -- Keep process idle when no MIDI editor is open
    if not editor_hwnd then
        reaper.defer(Main)
        prev_editor_hwnd = nil
        prev_take = nil
        return
    end

    local is_redraw = false
    local is_forced_redraw = false

    -- Monitor MIDI editor window handle changes
    if editor_hwnd ~= prev_editor_hwnd then
        prev_editor_hwnd = editor_hwnd
        notes_view = reaper.JS_Window_FindChildByID(editor_hwnd, 1001)
        piano_pane = reaper.JS_Window_FindChildByID(editor_hwnd, 1003)
        key_snap_root_cbox = reaper.JS_Window_FindChildByID(editor_hwnd, 1261)
        prev_piano_pane_w = nil
        prev_pane_time = nil
        prev_chunk_time = nil
        prev_take = nil
    end

    if not prev_pane_time or time > prev_pane_time + 0.5 then
        prev_pane_time = time
        -- Detect width changes (e.g. when editor moves from hdpi to non-hppi monitor)
        local _, piano_pane_w = reaper.JS_Window_GetClientSize(piano_pane)
        if piano_pane_w ~= prev_piano_pane_w then
            prev_piano_pane_w = piano_pane_w
            -- Calculate scale from piano pane width
            scale = piano_pane_w / piano_pane_scale1_w

            -- Use 2 times the size of the boxes above + inbetween margin
            bm_w = math.ceil(edit_box_scale1_w * scale) * 2
            bm_w = bm_w + math.floor(box_m * scale)
            bm_h = math.floor(box_h * scale)
            bm_x = math.floor(box_x * scale)
            bm_y = math.floor(box_y * scale)

            bm_x = bm_x + box_x_offs
            bm_y = bm_y + box_y_offs
            bm_w = bm_w + box_w_offs
            bm_h = bm_h + box_h_offs

            -- Find optimal font_size by incrementing until it doesn't fit box
            font_size = 1
            local font_max_height = bm_h - math.floor(box_p * scale)
            if is_macos then font_max_height = font_max_height + 2 end
            for i = 1, 100 do
                gfx.setfont(1, 'Arial', i)
                local _, h = gfx.measurestr('F')
                if h > font_max_height then break end
                font_size = i
            end
            gfx.setfont(1, 'Arial', font_size)

            -- Prepare LICE bitmap for drawing
            if bitmap then reaper.JS_LICE_DestroyBitmap(bitmap) end
            if lice_font then reaper.JS_LICE_DestroyFont(lice_font) end

            bitmap = reaper.JS_LICE_CreateBitmap(true, bm_w, bm_h)
            lice_font = reaper.JS_LICE_CreateFont()

            local gdi = reaper.JS_GDI_CreateFont(font_size, 0, 0, 0, 0, 0,
                'Arial')
            reaper.JS_LICE_SetFontFromGDI(lice_font, gdi, '')
            reaper.JS_GDI_DeleteObject(gdi)

            -- Draw LICE bitmap on piano pane
            reaper.JS_Composite(piano_pane, bm_x, bm_y, bm_w, bm_h, bitmap, 0, 0,
                bm_w, bm_h)
            reaper.JS_Composite_Delay(piano_pane, 0.03, 0.03, 2)
            is_forced_redraw = true
        end
    end

    -- Monitor color theme changes
    local color_theme = reaper.GetLastColorThemeFile()
    if color_theme ~= prev_color_theme then
        prev_color_theme = color_theme
        is_forced_redraw = true
    end

    local take = prev_take
    -- Find MIDI editor window
    if not prev_take_time or time > prev_take_time + 0.2 then
        prev_take_time = time
        take = reaper.MIDIEditor_GetTake(editor_hwnd)
    end

    if take and not reaper.ValidatePtr(take, 'MediaItem_Take*') then
        take = reaper.MIDIEditor_GetTake(editor_hwnd)
        if take and not reaper.ValidatePtr(take, 'MediaItem_Take*') then
            take = nil
        end
    end

    -- Keep process idle when no valid take is open
    if not take then
        reaper.defer(Main)
        prev_take = nil
        return
    end

    local item = reaper.GetMediaItemTake_Item(take)
    if not reaper.ValidatePtr(item, 'MediaItem*') then
        reaper.defer(Main)
        return
    end

    -- Flush input events when take changes
    if take ~= prev_take then
        prev_take = take
        prev_input_idx = reaper.MIDI_GetRecentInputEvent(0)
        input_note_map = {}
    end

    local x, y = reaper.GetMousePosition()
    local hover_hwnd = reaper.JS_Window_FromPoint(x, y)

    if hover_hwnd == piano_pane and IsBitmapHovered(x, y, piano_pane) then
        -- Open options menu when user clicks on the box
        local mouse_state = reaper.JS_Mouse_GetState(7)
        if prev_mouse_state and mouse_state ~= prev_mouse_state then
            prev_mouse_state = mouse_state
            local is_lclick = mouse_state & 1 == 1
            local is_rclick = mouse_state & 2 == 2
            if (is_lclick or is_rclick) and reaper.JS_Window_GetFocus() then
                -- Avoid mouse clicks when no REAPER window is focused
                local is_ctrl_pressed = mouse_state & 4 == 4
                if is_ctrl_pressed and is_lclick then
                    local last_export = reaper.GetExtState(extname, 'last_export')
                    local export_functions = {
                        chord_track = CreateChordTrack,
                        project_region = CreateChordProjectRegions,
                        project_marker = CreateChordProjectMarkers,
                        take_marker = CreateChordTakeMarkers,
                        text_event = CreateChordTextEvents,
                        notation_event = CreateChordNotationEvents,
                    }
                    if export_functions[last_export] then
                        export_functions[last_export]()
                    end
                else
                    ShowChordBoxMenu()
                end
                is_forced_redraw = true
                -- Flush input chords on click
                input_note_map = {}
            end
        end
        prev_mouse_state = mouse_state
    else
        prev_mouse_state = nil
    end

    -- Detect MIDI scale changes
    local is_key_snap, midi_scale_root, midi_scale = reaper.MIDI_GetScale(take)

    if is_key_snap ~= prev_is_key_snap then
        prev_is_key_snap = is_key_snap
        is_redraw = true
    end

    if is_key_snap then
        if midi_scale_root ~= prev_midi_scale_root then
            prev_midi_scale_root = midi_scale_root
            is_redraw = true
        end
        local has_scale_changed = false
        if midi_scale ~= prev_midi_scale then
            prev_midi_scale = midi_scale
            curr_scale_intervals = {}
            for i = 0, 11 do
                local mask = (1 << i)
                local has_note = midi_scale & mask == mask
                curr_scale_intervals[i + 1] = has_note and 1
            end
            is_redraw = true
            has_scale_changed = true
        end

        if use_sharps_autodetect then
            local key_snap_root = reaper.JS_Window_GetTitle(key_snap_root_cbox)
            if key_snap_root ~= prev_key_snap_root or has_scale_changed then
                prev_key_snap_root = key_snap_root
                AutoDetectSharps(key_snap_root, midi_scale)
            end
        end
    end

    -- Process input chords that user plays on MIDI keyboard
    local input_chord
    if use_input then
        local track = reaper.GetMediaItemTake_Track(take)
        input_chord = GetMIDIInputChord(track)
    end
    if input_chord then
        input_timer = time
        local input_chord_name = BuildChordName(input_chord)
        -- Only redraw LICE bitmap when chord name has changed
        if input_chord_name ~= prev_input_chord_name then
            prev_input_chord_name = input_chord_name
            DrawLICE(input_chord_name, 3)
        end
        reaper.defer(Main)
        return
    end

    -- Show input chords a bit longer than they are played (linger)
    if input_timer then
        local linger_duration = 0.6
        if time < input_timer + linger_duration then
            reaper.defer(Main)
            return
        else
            input_timer = nil
            prev_input_chord_name = nil
            is_forced_redraw = true
        end
    end

    -- Update take chord information when MIDI hash changes
    local _, hash = reaper.MIDI_GetHash(take, true)
    if hash ~= prev_hash then
        prev_hash = hash
        curr_chords, curr_sel_chord = GetChords(take)
        is_redraw = true
    end

    local play_state = reaper.GetPlayState()
    -- Note: Avoid using GetItemStateChunk every defer cycle so that tooltips
    -- show on Windows (and reduce overall CPU usage on other OSs)
    -- Avoid completely during playback as it isn't necessary and can cause
    -- play cursor stutter on Windows
    if play_state == 0 and (not prev_chunk_time or time > prev_chunk_time + tooltip_delay) then
        prev_chunk_time = time

        local is_channel_combobox_hovered = false
        -- Note: Avoid calling GetItemStateChunk when channel combobox is hovered
        if is_windows then
            local GetLong = reaper.JS_Window_GetLong
            local is_valid = reaper.ValidatePtr(hover_hwnd, 'HWND*')
            local hover_id = is_valid and GetLong(hover_hwnd, 'ID')

            -- Note: 1000 is the id of the combobox menu when opened
            if hover_id == 1000 then
                local focus_hwnd = reaper.JS_Window_GetFocus()
                is_valid = reaper.ValidatePtr(focus_hwnd, 'HWND*')

                local focus_id = is_valid and GetLong(focus_hwnd, 'ID')
                -- Check if the channel combobox (ID 1006) is focused
                if focus_id == 1006 then
                    if reaper.JS_Window_IsChild(editor_hwnd, focus_hwnd) then
                        is_channel_combobox_hovered = true
                    end
                end
            end
        end

        -- Avoid calling GetItemStateChunk as long as tooltip is shown
        local tooltip_hwnd = reaper.GetTooltipWindow()
        local has_tooltip = reaper.JS_Window_GetTitle(tooltip_hwnd) ~= ''

        -- Monitor item chunk (for getting time position at mouse)
        if not has_tooltip and not is_channel_combobox_hovered then
            local _, chunk = reaper.GetItemStateChunk(item, '', false)
            if chunk ~= prev_item_chunk then
                prev_item_chunk = chunk
                curr_start_time, curr_end_time = GetMIDIEditorView(editor_hwnd,
                    chunk)
            end
        end
    end

    local mode = -1
    local cursor_pos

    -- Calculate time position at mouse using start/end time of the MIDI editor
    if curr_start_time and hover_hwnd == notes_view then
        local diff = curr_end_time - curr_start_time
        local _, notes_view_width = reaper.JS_Window_GetClientSize(notes_view)
        x, y = reaper.JS_Window_ScreenToClient(notes_view, x, y)
        cursor_pos = curr_start_time + x / notes_view_width * diff
        mode = 0
    end

    -- Use play cursor position during playback/record
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

    if is_redraw or is_forced_redraw then
        local curr_chord
        -- Get chord name depending on mode
        if curr_sel_chord then
            curr_chord = curr_sel_chord
            mode = 2
        end

        if mode == 1 then
            local cursor_ppq = GetCursorPPQPosition(take, cursor_pos)
            if cursor_ppq then
                for _, chord in ipairs(curr_chords) do
                    if chord.sppq > cursor_ppq then break end
                    curr_chord = chord
                end
            end
        end

        if mode == 0 and cursor_pos then
            local cursor_ppq = GetCursorPPQPosition(take, cursor_pos)
            if cursor_ppq then
                for _, chord in ipairs(curr_chords) do
                    if chord.sppq > cursor_ppq then break end
                    if cursor_ppq >= chord.sppq and cursor_ppq <= chord.eppq then
                        curr_chord = chord
                        break
                    end
                end
            end
        end

        local curr_chord_name = BuildChordName(curr_chord)

        -- Check if redrawing LICE bitmap is necessary
        local has_chord_changed = curr_chord_name ~= prev_chord_name
        local has_mode_changed = mode ~= prev_mode
        if has_chord_changed or has_mode_changed or is_forced_redraw then
            prev_chord_name = curr_chord_name
            prev_mode = mode
            DrawLICE(curr_chord_name, mode)
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
    reaper.JS_Composite_Delay(piano_pane, 0, 0, 0)
end

reaper.atexit(Exit)
reaper.defer(Main)
