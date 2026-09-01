-- 临时入口：自研 stencil RT 实验。
-- 正式玩法入口仍在 Git 历史的 GameApp；本分支只跑实验室。

local StencilRtLab = require "StencilRtLab"

---@type StencilRtLab|nil
local lab_ = nil

function Start()
    lab_ = StencilRtLab.New()
    lab_:Start()
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("ScreenMode", "HandleScreenMode")
    print("Game entry: StencilRtLab")
end

function Stop()
    if lab_ then
        lab_:Stop()
        lab_ = nil
    end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if lab_ then
        lab_:Update(eventData["TimeStep"]:GetFloat())
    end
end

---@param eventType string
---@param eventData ScreenModeEventData
function HandleScreenMode(eventType, eventData)
    if lab_ then
        lab_:HandleScreenMode()
    end
end
