-- 选关滑动窗口 HUD。
-- 只显示棱柱当前三格：[左][正][右]。不进关，不挡拖转。

local UI = require("urhox-libs/UI")

---@class MenuWindowHud
---@field root Widget|nil
---@field leftLabel Label
---@field centerLabel Label
---@field rightLabel Label
local MenuWindowHud = {}
MenuWindowHud.__index = MenuWindowHud

local SLOT_W = 168
local SLOT_H = 72
local LEFT_BG = { 255, 255, 0, 36 }
local CENTER_BG = { 0, 255, 0, 48 }
local RIGHT_BG = { 0, 255, 255, 36 }
local TEXT = { 236, 242, 248, 255 }
local MUTED = { 168, 182, 198, 255 }

local function EnsureUI()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })
end

local function SlotLabel(id, fontSize, weight)
    return UI.Label {
        id = id,
        text = "",
        fontSize = fontSize,
        fontWeight = weight,
        fontColor = TEXT,
        textAlign = "center",
        width = "100%",
    }
end

local function SlotPanel(id, backgroundColor, children)
    return UI.Panel {
        width = SLOT_W,
        height = SLOT_H,
        padding = 10,
        gap = 4,
        backgroundColor = backgroundColor,
        borderRadius = 10,
        justifyContent = "center",
        alignItems = "center",
        children = children,
    }
end

local function TitleOf(definition)
    if not definition then
        return "--"
    end
    return definition.title
end

function MenuWindowHud.New()
    local self = setmetatable({}, MenuWindowHud)
    self:init()
    return self
end

function MenuWindowHud:init()
    EnsureUI()
    local leftLabel = SlotLabel("window-left", 16, "normal")
    local centerLabel = SlotLabel("window-center", 18, "bold")
    local rightLabel = SlotLabel("window-right", 16, "normal")
    self.leftLabel = leftLabel
    self.centerLabel = centerLabel
    self.rightLabel = rightLabel
    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "none",
        padding = 24,
        justifyContent = "flex-end",
        alignItems = "center",
        children = {
            UI.Panel {
                flexDirection = "row",
                gap = 12,
                alignItems = "center",
                children = {
                    SlotPanel("window-left-slot", LEFT_BG, {
                        UI.Label { text = "左", fontSize = 11, fontColor = MUTED, textAlign = "center", width = "100%" },
                        leftLabel,
                    }),
                    SlotPanel("window-center-slot", CENTER_BG, {
                        UI.Label { text = "正", fontSize = 11, fontColor = MUTED, textAlign = "center", width = "100%" },
                        centerLabel,
                    }),
                    SlotPanel("window-right-slot", RIGHT_BG, {
                        UI.Label { text = "右", fontSize = 11, fontColor = MUTED, textAlign = "center", width = "100%" },
                        rightLabel,
                    }),
                },
            },
        },
    }
    UI.SetRoot(self.root, true)
end

function MenuWindowHud:SetWindow(window)
    local left = window and window[1] or nil
    local center = window and window[2] or nil
    local right = window and window[3] or nil
    self.leftLabel:SetText(TitleOf(left))
    self.centerLabel:SetText(TitleOf(center))
    self.rightLabel:SetText(TitleOf(right))
end

function MenuWindowHud:Hide()
    if self.root then
        UI.SetRoot(nil, true)
        self.root = nil
    end
end

return MenuWindowHud
