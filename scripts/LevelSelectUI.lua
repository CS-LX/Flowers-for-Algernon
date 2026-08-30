-- 白膜选关页。
-- 只负责关卡列表展示和点击回调，不持有 Scene 或关卡会话。

local UI = require("urhox-libs/UI")
local LevelCatalog = require "LevelCatalog"

---@class LevelSelectUI
---@field onSelect fun(definition: LevelDefinition)|nil
---@field root Widget|nil
---@field statusLabel Widget|nil
local LevelSelectUI = {}
LevelSelectUI.__index = LevelSelectUI

local PANEL = { 18, 24, 34, 255 }
local CARD = { 28, 36, 52, 255 }
local BORDER = { 92, 112, 140, 180 }
local TEXT = { 231, 238, 248, 255 }
local MUTED = { 145, 160, 184, 255 }
local ACCENT = { 78, 132, 194, 255 }

local function EnsureUI()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })
end

function LevelSelectUI.New(onSelect)
    local self = setmetatable({}, LevelSelectUI)
    self.onSelect = onSelect
    ---@type Widget|nil
    self.root = nil
    ---@type Widget|nil
    self.statusLabel = nil
    return self
end

function LevelSelectUI:BuildCard(definition)
    local onSelect = self.onSelect
    return UI.Panel {
        width = 240,
        height = 220,
        padding = 18,
        gap = 10,
        backgroundColor = CARD,
        borderColor = BORDER,
        borderWidth = 1,
        borderRadius = 10,
        justifyContent = "space-between",
        children = {
            UI.Panel {
                gap = 8,
                children = {
                    UI.Label {
                        text = string.format("%02d", definition.index),
                        fontSize = 12,
                        fontColor = ACCENT,
                    },
                    UI.Label {
                        text = definition.title,
                        fontSize = 22,
                        fontWeight = "bold",
                        fontColor = TEXT,
                    },
                    UI.Label {
                        text = definition.subtitle,
                        fontSize = 13,
                        fontColor = MUTED,
                    },
                    UI.Label {
                        text = "白膜关卡 · Levels/whitebox-level.json",
                        fontSize = 11,
                        fontColor = MUTED,
                    },
                },
            },
            UI.Button {
                text = "进入",
                height = 36,
                fontSize = 14,
                variant = "primary",
                onClick = function()
                    if onSelect then
                        onSelect(definition)
                    end
                end,
            },
        },
    }
end

function LevelSelectUI:Show()
    EnsureUI()
    local cards = {}
    for _, definition in ipairs(LevelCatalog.GetAll()) do
        cards[#cards + 1] = self:BuildCard(definition)
    end
    self.statusLabel = UI.Label {
        text = "Esc 退出关卡后回到这里",
        fontSize = 12,
        fontColor = MUTED,
    }
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        backgroundColor = PANEL,
        justifyContent = "center",
        alignItems = "center",
        gap = 28,
        children = {
            UI.Panel {
                alignItems = "center",
                gap = 8,
                children = {
                    UI.Label {
                        text = "Hexagon Visual Challenge",
                        fontSize = 28,
                        fontWeight = "bold",
                        fontColor = TEXT,
                    },
                    UI.Label {
                        text = "选择一章进入白膜关卡",
                        fontSize = 14,
                        fontColor = MUTED,
                    },
                },
            },
            UI.Panel {
                flexDirection = "row",
                gap = 18,
                children = cards,
            },
            self.statusLabel,
        },
    }
    UI.SetRoot(self.root, true)
    print("LevelSelectUI: shown with " .. tostring(#cards) .. " chapters")
end

function LevelSelectUI:SetStatus(text)
    if self.statusLabel then
        local label = self.statusLabel --[[@as Label]]
        label:SetText(text)
    end
end

function LevelSelectUI:Hide()
    if self.root then
        UI.SetRoot(nil, true)
        self.root = nil
        self.statusLabel = nil
        print("LevelSelectUI: hidden")
    end
end

function LevelSelectUI:Destroy()
    self:Hide()
end

return LevelSelectUI
