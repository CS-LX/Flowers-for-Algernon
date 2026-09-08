-- 选关菜单音量行。固定标签宽，滑条右对齐。不持有云读写。

local Widget = require("urhox-libs/UI/Core/Widget")
local MenuDiamondSlider = require "MenuDiamondSlider"
local MenuHoverTint = require "MenuHoverTint"

---@class MenuVolumeRow : Widget
---@field slider MenuDiamondSlider|nil
---@overload fun(props?: table): MenuVolumeRow
local MenuVolumeRow = Widget:Extend("MenuVolumeRow")

local LABEL_COLOR = { 255, 255, 255, 255 }
local LABEL_WIDTH = 168
local LABEL_SIZE = 28

function MenuVolumeRow:Init(props)
    props = props or {}
    props.width = props.width or "100%"
    props.height = props.height or 64
    props.flexDirection = "row"
    props.alignItems = "center"
    props.justifyContent = "flexStart"
    props.gap = 36
    rawset(self, "slider", nil)
    local title = props.title or ""
    local value = tonumber(props.value) or 1.0
    local thumbColor = props.thumbColor or MenuHoverTint.FromFog(nil)
    props.title = nil
    props.value = nil
    props.thumbColor = nil
    Widget.Init(self, props)
    local UI = require("urhox-libs/UI")
    self:AddChild(UI.Label {
        text = title,
        width = LABEL_WIDTH,
        fontSize = LABEL_SIZE,
        fontColor = LABEL_COLOR,
        fontWeight = "bold",
        pointerEvents = "none",
        flexShrink = 0,
    })
    local slider = MenuDiamondSlider {
        value = value,
        thumbColor = thumbColor,
        onVolume = function(nextValue, persist)
            if self.props.onVolume then
                self.props.onVolume(nextValue, persist)
            end
        end,
    }
    self:AddChild(slider)
    rawset(self, "slider", slider)
end

function MenuVolumeRow:SetVolume(value)
    if self.slider then
        self.slider:SetValue(value, false)
    end
end

function MenuVolumeRow:SetThumbColor(color)
    if self.slider then
        self.slider:SetThumbColor(color)
    end
end

function MenuVolumeRow:IsStateful()
    return true
end

return MenuVolumeRow
