--[[
  @author Ilias-Timon Poulakis (FeedTheCat)
  @license MIT
  @version 1.5.0
  @provides [main=main] .
  @about Toggle show dockers attached to one side of the main window
  @changelog
    - Use different logic using native action to toggle dockers
]]
local _, file, sec, cmd = reaper.get_action_context()

-- Get docker position (left, right, etc.) from file name
local pos_str = file:match('show (.-) docker%.lua$')
local pos_ids = {bottom = 0, left = 1, top = 2, right = 3}
local pos = pos_ids[pos_str] or 0

reaper.Undo_OnStateChange(('Toggle show %s docker'):format(pos_str))

-- Check if js_ReaScriptAPI extension is installed
if not reaper.JS_Window_ListAllChild then
    reaper.MB('Please install js_ReaScriptAPI extension', 'Error', 0)
    return
end

function GetChildren(parent_hwnd, filter)
    local children = {}
    local ret, list = reaper.JS_Window_ListAllChild(parent_hwnd)
    if ret ~= 0 then
        for addr in (list .. ','):gmatch('(.-),') do
            local hwnd = reaper.JS_Window_HandleFromAddress(addr)
            local class = reaper.JS_Window_GetClassName(hwnd)
            if class ~= 'WDLTabCtrl' then
                if reaper.JS_Window_GetParent(hwnd) == parent_hwnd then
                    local GetTitle = reaper.JS_Window_GetTitle
                    if not filter or GetTitle(hwnd):match(filter) then
                        table.insert(children, hwnd)
                    end
                end
            end
        end
    end
    return children
end

function ShowDocker(docker)
    if docker.child_cnt == 1 then
        reaper.DockWindowActivate(docker.children[1])
    else
        -- Add a temporary window to force dock to show (will not change tab)
        local title = 'FTC_Docker'
        local tmp_hwnd = reaper.JS_Window_Create(title, '', 0, 0, 0, 0)
        reaper.Dock_UpdateDockID(title, docker.id)
        reaper.DockWindowAddEx(tmp_hwnd, title, title, true)
        reaper.DockWindowRemove(tmp_hwnd)
        reaper.JS_Window_Destroy(tmp_hwnd)
    end
end

local main_hwnd = reaper.GetMainHwnd()
local docker_hwnds = GetChildren(main_hwnd, 'REAPER_dock')

local dockers = {}
local is_visible = false
local child_cnt = 0

-- Get all dockers at position
for _, docker_hwnd in ipairs(docker_hwnds) do
    local docker = {}
    docker.id = reaper.DockIsChildOfDock(docker_hwnd)
    docker.pos = reaper.DockGetPosition(docker.id)
    docker.is_visible = reaper.JS_Window_IsVisible(docker_hwnd)
    docker.children = GetChildren(docker_hwnd, '.')
    docker.child_cnt = #docker.children
    table.insert(dockers, docker)

    if docker.pos == pos then
        -- Check if any docker at position is currently visible
        is_visible = is_visible or docker.is_visible
        child_cnt = child_cnt + docker.child_cnt
    end
end

if child_cnt == 0 then
    reaper.SetToggleCommandState(sec, cmd, 0)
    return
end

-- Set toolbar toggle state
reaper.SetToggleCommandState(sec, cmd, is_visible and 0 or 1)

-- Hide all dockers using native command
if reaper.GetToggleCommandState(40279) == 1 then
    -- View: Show docker
    reaper.Main_OnCommand(40279, 0)
end

for _, docker in ipairs(dockers) do
    if docker.pos == pos then
        if not is_visible and docker.child_cnt > 0 then
            ShowDocker(docker)
        end
    else
        if docker.is_visible and docker.child_cnt > 0 then
            ShowDocker(docker)
        end
    end
end
