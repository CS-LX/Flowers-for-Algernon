-- 六边形视觉闯关游戏入口。
-- 默认进入无 UI 选关场景；关卡容器负责 Init / Dispose。

local GameApp = require "GameApp"
local ScreenColorPicker = require "ScreenColorPicker"

---@type GameApp|nil
local app_ = nil

function Start()
    graphics.windowTitle = "Hexagon Visual Challenge"
    app_ = GameApp.New()
    app_:Start()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("EndRendering", "HandleEndRendering")
    print("Game entry: level select")
end

function Stop()
    if app_ then
        app_:Stop()
        app_ = nil
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if app_ then
        app_:Update(eventData["TimeStep"]:GetFloat())
    end
end

---@param eventType string
---@param eventData EndRenderingEventData
function HandleEndRendering(eventType, eventData)
    ScreenColorPicker.CaptureIfPending()
end
