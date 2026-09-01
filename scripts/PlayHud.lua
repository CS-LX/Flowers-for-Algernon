-- 关卡内 HUD：只挂剧情层。
-- 调试信息、返回按钮、过关面板不进关卡画面；Esc 仍由 GameApp 处理。

local UI = require("urhox-libs/UI")
local StoryView = require "StoryView"

---@class PlayHud
---@field onExit fun()|nil
---@field root Widget|nil
local PlayHud = {}
PlayHud.__index = PlayHud

function PlayHud.New(onExit)
    local self = setmetatable({}, PlayHud)
    self.onExit = onExit
    ---@type Widget|nil
    self.root = nil
    ---@type table|nil
    self.storyView = nil
    ---@type Widget|nil
    self.storyHost = nil
    return self
end

function PlayHud:Show(definition)
    self.storyView = StoryView.New()
    self.storyHost = self.storyView:Build()
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            self.storyHost,
        },
    }
    UI.SetRoot(self.root, true)
    print("PlayHud: story-only hud for " .. tostring(definition and definition.id))
end

function PlayHud:SetStatus(text)
    -- 关内不再显示调试状态条。
end

function PlayHud:ShowFinish()
    print("PlayHud: finish acknowledged without overlay")
end

function PlayHud:Hide()
    if self.root then
        UI.SetRoot(nil, true)
        self.root = nil
    end
    if self.storyView then
        self.storyView:Destroy()
        self.storyView = nil
    end
    self.storyHost = nil
end

return PlayHud
