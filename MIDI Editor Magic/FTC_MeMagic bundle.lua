--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.2.0
  @about Bundle with feasible configurations of MeMagic
  @metapackage
  @provides
    [main=main,midi_editor] Generated/FTC_MeMagic (1-2) Vertically zoom to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-3) Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-4) Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-5) Vertically scroll to pitch, restrict to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-6) Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-7) Vertically scroll to center of notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-8) Vertically scroll to center of notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-9) Vertically scroll to lowest note in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-10) Vertically scroll to lowest note in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-11) Vertically scroll to highest note in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (1-12) Vertically scroll to highest note in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (2-1) Horizontally zoom to item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (2-3) Horizontally zoom to item + Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (2-4) Horizontally zoom to item + Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (2-6) Horizontally zoom to item + Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (2-8) Horizontally zoom to item + Vertically scroll to center of notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (2-10) Horizontally zoom to item + Vertically scroll to lowest note in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (2-12) Horizontally zoom to item + Vertically scroll to highest note in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (3-1) Horizontally zoom to 4 measures at mouse or edit cursor.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (3-2) Horizontally zoom to 4 measures at mouse or edit cursor + Vertically zoom to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (3-3) Horizontally zoom to 4 measures at mouse or edit cursor + Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (3-4) Horizontally zoom to 4 measures at mouse or edit cursor + Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (3-5) Horizontally zoom to 4 measures at mouse or edit cursor + Vertically scroll to pitch, restrict to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (3-6) Horizontally zoom to 4 measures at mouse or edit cursor + Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (3-7) Horizontally zoom to 4 measures at mouse or edit cursor + Vertically scroll to center of notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (3-8) Horizontally zoom to 4 measures at mouse or edit cursor + Vertically scroll to center of notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (4-1) Horizontally zoom to 4 measures at mouse or edit cursor, restrict to item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (4-2) Horizontally zoom to 4 measures at mouse or edit cursor, restrict to item + Vertically zoom to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (4-3) Horizontally zoom to 4 measures at mouse or edit cursor, restrict to item + Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (4-4) Horizontally zoom to 4 measures at mouse or edit cursor, restrict to item + Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (4-5) Horizontally zoom to 4 measures at mouse or edit cursor, restrict to item + Vertically scroll to pitch, restrict to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (4-6) Horizontally zoom to 4 measures at mouse or edit cursor, restrict to item + Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (4-7) Horizontally zoom to 4 measures at mouse or edit cursor, restrict to item + Vertically scroll to center of notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (4-8) Horizontally zoom to 4 measures at mouse or edit cursor, restrict to item + Vertically scroll to center of notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (5-1) Horizontally smart zoom to 20 notes at mouse or edit cursor.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (5-2) Horizontally smart zoom to 20 notes at mouse or edit cursor + Vertically zoom to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (5-3) Horizontally smart zoom to 20 notes at mouse or edit cursor + Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (5-4) Horizontally smart zoom to 20 notes at mouse or edit cursor + Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (5-5) Horizontally smart zoom to 20 notes at mouse or edit cursor + Vertically scroll to pitch, restrict to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (5-6) Horizontally smart zoom to 20 notes at mouse or edit cursor + Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (5-7) Horizontally smart zoom to 20 notes at mouse or edit cursor + Vertically scroll to center of notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (5-8) Horizontally smart zoom to 20 notes at mouse or edit cursor + Vertically scroll to center of notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (6-1) Horizontally smart zoom to 20 notes at mouse or edit cursor, restrict to item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (6-2) Horizontally smart zoom to 20 notes at mouse or edit cursor, restrict to item + Vertically zoom to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (6-3) Horizontally smart zoom to 20 notes at mouse or edit cursor, restrict to item + Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (6-4) Horizontally smart zoom to 20 notes at mouse or edit cursor, restrict to item + Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (6-5) Horizontally smart zoom to 20 notes at mouse or edit cursor, restrict to item + Vertically scroll to pitch, restrict to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (6-6) Horizontally smart zoom to 20 notes at mouse or edit cursor, restrict to item + Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (6-7) Horizontally smart zoom to 20 notes at mouse or edit cursor, restrict to item + Vertically scroll to center of notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (6-8) Horizontally smart zoom to 20 notes at mouse or edit cursor, restrict to item + Vertically scroll to center of notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (7-1) Horizontally smart zoom to measures at mouse or edit cursor.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (7-2) Horizontally smart zoom to measures at mouse or edit cursor + Vertically zoom to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (7-3) Horizontally smart zoom to measures at mouse or edit cursor + Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (7-4) Horizontally smart zoom to measures at mouse or edit cursor + Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (7-5) Horizontally smart zoom to measures at mouse or edit cursor + Vertically scroll to pitch, restrict to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (7-6) Horizontally smart zoom to measures at mouse or edit cursor + Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (7-7) Horizontally smart zoom to measures at mouse or edit cursor + Vertically scroll to center of notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (7-8) Horizontally smart zoom to measures at mouse or edit cursor + Vertically scroll to center of notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (8-1) Horizontally smart zoom to measures at mouse or edit cursor, restrict to item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (8-2) Horizontally smart zoom to measures at mouse or edit cursor, restrict to item + Vertically zoom to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (8-3) Horizontally smart zoom to measures at mouse or edit cursor, restrict to item + Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (8-4) Horizontally smart zoom to measures at mouse or edit cursor, restrict to item + Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (8-5) Horizontally smart zoom to measures at mouse or edit cursor, restrict to item + Vertically scroll to pitch, restrict to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (8-6) Horizontally smart zoom to measures at mouse or edit cursor, restrict to item + Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (8-7) Horizontally smart zoom to measures at mouse or edit cursor, restrict to item + Vertically scroll to center of notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (8-8) Horizontally smart zoom to measures at mouse or edit cursor, restrict to item + Vertically scroll to center of notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (9-1) Horizontally scroll to mouse or edit cursor.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (9-2) Horizontally scroll to mouse or edit cursor + Vertically zoom to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (9-3) Horizontally scroll to mouse or edit cursor + Vertically zoom to all notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (9-4) Horizontally scroll to mouse or edit cursor + Vertically scroll to pitch.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (9-5) Horizontally scroll to mouse or edit cursor + Vertically scroll to pitch, restrict to notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (9-6) Horizontally scroll to mouse or edit cursor + Vertically scroll to pitch, restrict to notes in item.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (9-7) Horizontally scroll to mouse or edit cursor + Vertically scroll to center of notes in visible area.lua
    [main=main,midi_editor] Generated/FTC_MeMagic (9-8) Horizontally scroll to mouse or edit cursor + Vertically scroll to center of notes in item.lua
]]
