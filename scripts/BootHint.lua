-- 进游戏黑屏提示。只负责文案淡入淡出，不读写存档。

local UI = require("urhox-libs/UI")

local BootHint = {}
BootHint.__index = BootHint

local FADE = 0.6
local HOLD = 2.2
local TEXT_COLOR = { 255, 255, 255, 255 }

local function EnsureUI()
    UI.Init({
        theme = "default-dark",
        fonts = {
            {
                family = "sans",
                weights = {
                    normal = "Fonts/MiSans-Regular.ttf",
                    bold = "Fonts/MiSans-Bold.ttf",
                },
            },
        },
        scale = UI.Scale.DESIGN_RESOLUTION(1920, 1080),
    })
    UI.SetScale(UI.Scale.DESIGN_RESOLUTION(1920, 1080))
end

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

function BootHint.New()
    local self = setmetatable({}, BootHint)
    ---@type Widget|nil
    self.root = nil
    ---@type Widget|nil
    self.panel = nil
    self.phase = "in"
    self.clock = 0.0
    self.opacity = 0.0
    ---@type fun()|nil
    self.onFinished = nil
    return self
end

function BootHint:ApplyOpacity()
    if self.panel then
        self.panel:SetStyle({ opacity = self.opacity })
    end
end

function BootHint:Show()
    EnsureUI()
    self.panel = UI.Panel {
        width = "100%",
        height = "100%",
        alignItems = "center",
        justifyContent = "center",
        backgroundColor = { 0, 0, 0, 255 },
        gap = 18,
        opacity = 0.0,
        onClick = function()
            self:Skip()
        end,
        children = {
            UI.Label {
                text = "佩戴耳机效果更好",
                fontSize = 36,
                fontColor = TEXT_COLOR,
                fontWeight = "bold",
                textAlign = "center",
                pointerEvents = "none",
            },
            UI.Label {
                text = "PC 端体验更佳",
                fontSize = 36,
                fontColor = TEXT_COLOR,
                fontWeight = "bold",
                textAlign = "center",
                pointerEvents = "none",
            },
        },
    }
    self.root = self.panel
    UI.SetRoot(self.root, true)
    self.phase = "in"
    self.clock = 0.0
    self.opacity = 0.0
    self:ApplyOpacity()
    print("BootHint: shown")
end

function BootHint:Skip()
    if self.phase == "done" then
        return
    end
    self:Finish()
end

function BootHint:Finish()
    if self.phase == "done" then
        return
    end
    self.phase = "done"
    print("BootHint: finished")
    local callback = self.onFinished
    self.onFinished = nil
    if callback then
        callback()
    end
end

function BootHint:ReleaseCover()
    local cover = self.panel
    if not cover then
        return nil, 1.0
    end
    local opacity = self.opacity
    cover.props.onClick = nil
    cover:SetProp("pointerEvents", "auto")
    self.panel = nil
    self.root = nil
    self.phase = "done"
    if UI.GetRoot() == cover then
        UI.SetRoot(nil, false)
    end
    print("BootHint: cover released")
    return cover, opacity
end

function BootHint:Update(timeStep)
    if self.phase == "done" then
        return
    end
    self.clock = self.clock + timeStep
    if self.phase == "in" then
        self.opacity = Clamp01(self.clock / FADE)
        self:ApplyOpacity()
        if self.clock >= FADE then
            self.phase = "hold"
            self.clock = 0.0
            self.opacity = 1.0
            self:ApplyOpacity()
        end
        return
    end
    if self.phase == "hold" then
        if self.clock >= HOLD then
            self:Finish()
        end
    end
end

function BootHint:Hide()
    if self.root then
        UI.SetRoot(nil, true)
    end
    self.root = nil
    self.panel = nil
end

return BootHint
