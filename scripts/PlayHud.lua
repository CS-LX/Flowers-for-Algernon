-- 关卡内白膜 HUD。
-- 只显示当前章节和退出提示，不拦截 3D 点击。

local UI = require("urhox-libs/UI")

---@class PlayHud
---@field onExit fun()|nil
---@field root Widget|nil
local PlayHud = {}
PlayHud.__index = PlayHud

local PANEL = { 21, 27, 38, 220 }
local TEXT = { 231, 238, 248, 255 }
local MUTED = { 145, 160, 184, 255 }

function PlayHud.New(onExit)
    local self = setmetatable({}, PlayHud)
    self.onExit = onExit
    ---@type Widget|nil
    self.root = nil
    return self
end

function PlayHud:Show(definition)
    local onExit = self.onExit
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute",
                top = 12,
                left = 12,
                paddingHorizontal = 14,
                paddingVertical = 10,
                gap = 4,
                backgroundColor = PANEL,
                borderRadius = 8,
                children = {
                    UI.Label {
                        text = definition.title,
                        fontSize = 16,
                        fontWeight = "bold",
                        fontColor = TEXT,
                    },
                    UI.Label {
                        text = definition.subtitle,
                        fontSize = 12,
                        fontColor = MUTED,
                    },
                },
            },
            UI.Panel {
                position = "absolute",
                top = 12,
                right = 12,
                children = {
                    UI.Button {
                        text = "返回选关  Esc",
                        height = 34,
                        fontSize = 12,
                        variant = "secondary",
                        onClick = function()
                            if onExit then
                                onExit()
                            end
                        end,
                    },
                },
            },
        },
    }
    UI.SetRoot(self.root, true)
end

function PlayHud:Hide()
    if self.root then
        UI.SetRoot(nil, true)
        self.root = nil
    end
end

return PlayHud
