-- 选关菜单文字行。
-- 悬停：整体放大 + 颜色 tween 到当前选关雾色的拉饱和结果。

local Widget = require("urhox-libs/UI/Core/Widget")
local MenuHoverTint = require "MenuHoverTint"

---@class MenuTextItem : Widget
---@field hoverAmount number
---@field hoverFrom number
---@field hoverTo number
---@field hoverElapsed number
---@field hoverDuration number
---@field hovered boolean
---@field hoverColor number[]
---@field label Widget|nil
---@overload fun(props?: table): MenuTextItem
local MenuTextItem = Widget:Extend("MenuTextItem")

local REST_SIZE = 30
local HOVER_SCALE = 1.08
local TWEEN_SECONDS = 0.18
local REST_COLOR = MenuHoverTint.White()

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

local function EaseOutCubic(t)
    local inverse = 1.0 - Clamp01(t)
    return 1.0 - inverse * inverse * inverse
end

local function MixChannel(fromValue, toValue, t)
    return math.floor(fromValue + (toValue - fromValue) * t + 0.5)
end

local function MixRgba(fromColor, toColor, t)
    return {
        MixChannel(fromColor[1], toColor[1], t),
        MixChannel(fromColor[2], toColor[2], t),
        MixChannel(fromColor[3], toColor[3], t),
        MixChannel(fromColor[4] or 255, toColor[4] or 255, t),
    }
end

function MenuTextItem:Init(props)
    props = props or {}
    props.height = props.height or 84
    props.width = props.width or "100%"
    props.alignItems = props.alignItems or "center"
    props.justifyContent = props.justifyContent or "center"
    props.pointerEvents = props.pointerEvents or "auto"
    rawset(self, "hoverAmount", 0.0)
    rawset(self, "hoverFrom", 0.0)
    rawset(self, "hoverTo", 0.0)
    rawset(self, "hoverElapsed", 0.0)
    rawset(self, "hoverDuration", 0.0)
    rawset(self, "hovered", false)
    rawset(self, "hoverColor", MenuHoverTint.FromFog(nil))
    rawset(self, "label", nil)
    local text = props.text or ""
    props.text = nil
    props.onPointerEnter = function(_, item)
        item:SetHovered(true)
    end
    props.onPointerLeave = function(_, item)
        item:SetHovered(false)
    end
    props.onClick = function(item)
        if item.props.onSelect then
            item.props.onSelect(item)
        end
    end
    Widget.Init(self, props)
    local UI = require("urhox-libs/UI")
    local label = UI.Label {
        text = text,
        fontSize = REST_SIZE,
        fontColor = REST_COLOR,
        fontWeight = "bold",
        textAlign = "center",
        pointerEvents = "none",
    }
    self:AddChild(label)
    rawset(self, "label", label)
end

function MenuTextItem:SetHoverColor(color)
    rawset(self, "hoverColor", color or MenuHoverTint.FromFog(nil))
    self:ApplyHoverVisual()
end

function MenuTextItem:SetHovered(hovered)
    local target = hovered == true
    if self.hovered == target and self.hoverDuration <= 0.0 then
        return
    end
    rawset(self, "hovered", target)
    rawset(self, "hoverFrom", self.hoverAmount)
    rawset(self, "hoverTo", target and 1.0 or 0.0)
    rawset(self, "hoverElapsed", 0.0)
    rawset(self, "hoverDuration", TWEEN_SECONDS)
end

function MenuTextItem:ApplyHoverVisual()
    local label = self.label
    if not label then
        return
    end
    local t = EaseOutCubic(self.hoverAmount)
    label:SetFontColor(MixRgba(REST_COLOR, self.hoverColor, t))
    label:SetStyle({ scale = 1.0 + (HOVER_SCALE - 1.0) * t })
end

function MenuTextItem:Update(dt)
    if self.hoverDuration <= 0.0 then
        return
    end
    local elapsed = self.hoverElapsed + dt
    rawset(self, "hoverElapsed", elapsed)
    local t = Clamp01(elapsed / self.hoverDuration)
    rawset(self, "hoverAmount", self.hoverFrom + (self.hoverTo - self.hoverFrom) * t)
    self:ApplyHoverVisual()
    if t >= 1.0 then
        rawset(self, "hoverAmount", self.hoverTo)
        rawset(self, "hoverDuration", 0.0)
    end
end

function MenuTextItem:IsStateful()
    return true
end

return MenuTextItem
