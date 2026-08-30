-- 关卡内白膜 HUD。
-- 显示当前章节、退出提示，以及过关结果。不拦截 3D 点击。

local UI = require("urhox-libs/UI")

---@class PlayHud
---@field onExit fun()|nil
---@field root Widget|nil
---@field statusLabel Label|nil
---@field finishPanel Widget|nil
local PlayHud = {}
PlayHud.__index = PlayHud

local PANEL = { 21, 27, 38, 220 }
local TEXT = { 231, 238, 248, 255 }
local MUTED = { 145, 160, 184, 255 }
local FINISH = { 80, 210, 160, 255 }

function PlayHud.New(onExit)
    local self = setmetatable({}, PlayHud)
    self.onExit = onExit
    ---@type Widget|nil
    self.root = nil
    ---@type Label|nil
    self.statusLabel = nil
    ---@type Widget|nil
    self.finishPanel = nil
    return self
end

function PlayHud:Show(definition)
    local onExit = self.onExit
    self.statusLabel = UI.Label {
        text = definition.subtitle .. "  ·  " .. definition.sourcePath,
        fontSize = 12,
        fontColor = MUTED,
        whiteSpace = "normal",
    }
    self.finishPanel = UI.Panel {
        position = "absolute",
        left = 0,
        right = 0,
        top = 0,
        bottom = 0,
        justifyContent = "center",
        alignItems = "center",
        pointerEvents = "box-none",
        visible = false,
        children = {
            UI.Panel {
                paddingHorizontal = 28,
                paddingVertical = 18,
                gap = 8,
                backgroundColor = PANEL,
                borderRadius = 12,
                alignItems = "center",
                children = {
                    UI.Label {
                        text = "过关",
                        fontSize = 28,
                        fontWeight = "bold",
                        fontColor = FINISH,
                    },
                    UI.Label {
                        text = "level.finish +1",
                        fontSize = 12,
                        fontColor = MUTED,
                    },
                },
            },
        },
    }
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
                    self.statusLabel,
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
            self.finishPanel,
        },
    }
    UI.SetRoot(self.root, true)
end

function PlayHud:SetStatus(text)
    if self.statusLabel then
        self.statusLabel:SetText(text)
    end
end

function PlayHud:ShowFinish()
    print("PlayHud: show finish")
    if self.finishPanel then
        self.finishPanel:SetVisible(true)
    end
    self:SetStatus("过关  ·  按 Esc 返回选关")
end

function PlayHud:Hide()
    if self.root then
        UI.SetRoot(nil, true)
        self.root = nil
    end
    self.statusLabel = nil
    self.finishPanel = nil
end

return PlayHud
