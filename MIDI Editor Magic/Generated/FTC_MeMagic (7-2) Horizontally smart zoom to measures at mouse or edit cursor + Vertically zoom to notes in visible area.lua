--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.3.3
  @noindex
  @about Automatically generated configuration of MeMagic
]]

------------------------------ GENERAL SETTINGS -----------------------------

-- Make this action non-contextual and always use modes from context: Toolbar button
_G.use_toolbar_context_only = true

-- Use mouse cursor instead of edit cursor when applicable
_G.use_mouse_cursor = true

-- Use play cursor instead of edit cursor during playback
_G.use_play_cursor = true

-- Move edit cursor to mouse cursor
_G.set_edit_cursor = false

------------------------------ ZOOM MODES -----------------------------

-- HORIZONTAL MODES
-- 1: No change
-- 2: Zoom to item
-- 3: Zoom to number of measures at mouse or edit cursor
-- 4: Zoom to number of measures at mouse or edit cursor, restrict to item
-- 5: Smart zoom to number of notes at mouse or edit cursor
-- 6: Smart zoom to number of notes at mouse or edit cursor, restrict to item
-- 7: Smart zoom to measures at mouse or edit cursor
-- 8: Smart zoom to measures at mouse or edit cursor, restrict to item
-- 9: Scroll to mouse or edit cursor

-- VERTICAL MODES
-- 1: No change
-- 2: Zoom to notes in visible area
-- 3: Zoom to all notes in item
-- 4: Scroll to note row at mouse or pitch cursor
-- 5: Scroll to note row at mouse or pitch cursor, restrict to notes in visible area
-- 6: Scroll to note row at mouse or pitch cursor, restrict to notes in item
-- 7: Scroll to center of notes in visible area
-- 8: Scroll to center of notes in item
-- 9: Scroll to lowest note in visible area
-- 10: Scroll to lowest note in item
-- 11: Scroll to highest note in visible area
-- 12: Scroll to highest note in item

-- Note: You can assign a different zoom mode to each MIDI editor timebase
-- by using an array with four elements, e.g {1, 2, 3, 1}
-- { Beats (project), Beats (source), Time (project), Sync to arrange }

-- Context: Toolbar button (default for non-contextual operation)
_G.TBB_horizontal_zoom_mode = 7
_G.TBB_vertical_zoom_mode = 2

-- Context: MIDI editor note area
_G.MEN_horizontal_zoom_mode = {6, 1, 6, 6}
_G.MEN_vertical_zoom_mode = {6, 3, 3, 6}

-- Context: MIDI editor piano pane
_G.MEP_horizontal_zoom_mode = 2
_G.MEP_vertical_zoom_mode = 2

-- Context: MIDI editor ruler
_G.MER_horizontal_zoom_mode = {1, 1, 5, 1}
_G.MER_vertical_zoom_mode = {11, 11, 11, 11}

-- Context: MIDI editor CC lanes
_G.MEC_horizontal_zoom_mode = {1, 1, 5, 1}
_G.MEC_vertical_zoom_mode = {9, 9, 9, 9}

-- Context: Arrange view area
_G.AVA_horizontal_zoom_mode = 5
_G.AVA_vertical_zoom_mode = 3

-- Context: Arrange view item single click (mouse modifier)
_G.AIS_horizontal_zoom_mode = 5
_G.AIS_vertical_zoom_mode = 3

-- Context: Arrange view item double click (mouse modifier)
_G.AID_horizontal_zoom_mode = 8
_G.AID_vertical_zoom_mode = 2

------------------------------ ZOOM SETTINGS -----------------------------

-- Number of measures to zoom to (for horizontal modes 3 and 4)
_G.number_of_measures = 4

-- Number of (approximate) notes to zoom to (for horizontal modes 5 and 6)
_G.number_of_notes = 20

-- Controls how the view is positioned relative to the cursor when zooming
-- 0: Cursor at left edge, 0.5: Centered, 1: Cursor at right edge
_G.cursor_alignment = 0.5

-- Determines how influential the cursor position is in smart zoom modes
-- No influence: 0,  High influence: >1,  Default: 0.75
_G.smoothing = 0.75

-- Which note to vertically zoom to when area contains no notes
_G.base_note = 60

-- Minimum number of vertical notes when zooming (not exact)
_G.min_vertical_notes = 8

-- Maximum vertical size for notes in pixels (smaller values increase performance)
_G.max_vertical_note_pixels = 32

-- Use selected notes only
_G.use_note_sel = false

----------------------------- DO MAGIC -----------------------------

local _, file = reaper.get_action_context()
local magic_dir = file:match('^(.+MIDI Editor Magic)[\\/]')

local path = {magic_dir}
if not magic_dir then
    path = {reaper.GetResourcePath(), 'Scripts', 'FTC Tools', 'MIDI Editor Magic'}
end
table.insert(path, 'FTC_MeMagic.lua')

local magic_file = table.concat(path, package.config:sub(1, 1))

if not reaper.file_exists(magic_file) then
    reaper.MB('Please install FTC_MeMagic', 'Error', 0)
    if reaper.ReaPack_BrowsePackages then
        reaper.ReaPack_BrowsePackages('FTC_MeMagic')
    end
    return
end

local function ForbidOverrides(_, k, v) if _G[k] == nil then _G[k] = v end end
local env = setmetatable({}, {__index = _G})
env._G = setmetatable({}, {__index = _G, __newindex = ForbidOverrides})

local chunk, err = loadfile(magic_file, 'bt', env)
if chunk then chunk() else reaper.ShowConsoleMsg(tostring(err)) end
