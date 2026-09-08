-- 选关菜单滑条。
-- 两端白六边形，中间柄跟随章节雾色。不持有云读写。
-- 轨道加粗，柄用尖端朝下的填充六边形。

local Widget = require("urhox-libs/UI/Core/Widget")
local HexMarkDraw = require "HexMarkDraw"
local MenuHoverTint = require "MenuHoverTint"

---@class MenuDiamondSlider : Widget
---@field value number
---@field dragging boolean
---@field thumbColor number[]
---@overload fun(props?: table): MenuDiamondSlider
local MenuDiamondSlider = Widget:Extend("MenuDiamondSlider")

local TRACK_COLOR = { 255, 255, 255, 230 }
local END_COLOR = { 255, 255, 255, 255 }
local TRACK_WIDTH = 4.0
local END_HEX_RADIUS = 8.0
local THUMB_HEX_RADIUS = 11.0

local function Clamp01(value)
    local number = tonumber(value) or 0.0
    if number < 0.0 then
        return 0.0
    end
    if number > 1.0 then
        return 1.0
    end
    return number
end

function MenuDiamondSlider:Init(props)
    props = props or {}
    props.height = props.height or 44
    props.flexGrow = props.flexGrow or 1
    props.flexShrink = props.flexShrink or 1
    props.flexBasis = props.flexBasis or 0
    props.pointerEvents = props.pointerEvents or "auto"
    rawset(self, "value", Clamp01(props.value))
    rawset(self, "dragging", false)
    rawset(self, "thumbColor", props.thumbColor or MenuHoverTint.FromFog(nil))
    props.value = nil
    props.thumbColor = nil
    Widget.Init(self, props)
end

function MenuDiamondSlider:SetValue(value, notify)
    local nextValue = Clamp01(value)
    if math.abs(self.value - nextValue) < 0.0001 then
        return
    end
    rawset(self, "value", nextValue)
    if notify and self.props.onVolume then
        self.props.onVolume(nextValue, false)
    end
end

function MenuDiamondSlider:SetThumbColor(color)
    rawset(self, "thumbColor", color or MenuHoverTint.FromFog(nil))
end

function MenuDiamondSlider:TrackBounds()
    local layout = self:GetAbsoluteLayout()
    local pad = THUMB_HEX_RADIUS
    local left = layout.x + pad
    local right = layout.x + layout.w - pad
    if right < left then
        right = left
    end
    return left, right, layout.y + layout.h * 0.5
end

function MenuDiamondSlider:SetValueFromX(x, persist)
    local left, right = self:TrackBounds()
    local span = right - left
    local nextValue = 0.0
    if span > 0.0001 then
        nextValue = Clamp01((x - left) / span)
    end
    rawset(self, "value", nextValue)
    if self.props.onVolume then
        self.props.onVolume(nextValue, persist == true)
    end
end

function MenuDiamondSlider:OnPointerDown(event)
    Widget.OnPointerDown(self, event)
    if event:IsPrimaryAction() then
        rawset(self, "dragging", true)
        self:SetValueFromX(event.x, false)
    end
end

function MenuDiamondSlider:OnPointerMove(event)
    Widget.OnPointerMove(self, event)
    if self.dragging then
        self:SetValueFromX(event.x, false)
    end
end

function MenuDiamondSlider:OnPointerUp(event)
    Widget.OnPointerUp(self, event)
    if self.dragging then
        rawset(self, "dragging", false)
        self:SetValueFromX(event.x, true)
    end
end

function MenuDiamondSlider:OnPanStart(event)
    rawset(self, "dragging", true)
    self:SetValueFromX(event.x, false)
end

function MenuDiamondSlider:OnPanMove(event)
    if self.dragging then
        self:SetValueFromX(event.x, false)
    end
end

function MenuDiamondSlider:OnPanEnd(event)
    if self.dragging then
        rawset(self, "dragging", false)
        self:SetValueFromX(event.x, true)
    end
end

function MenuDiamondSlider:Render(nvg)
    local left, right, cy = self:TrackBounds()
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, left, cy)
    nvgLineTo(nvg, right, cy)
    nvgStrokeColor(nvg, nvgRGBA(TRACK_COLOR[1], TRACK_COLOR[2], TRACK_COLOR[3], TRACK_COLOR[4]))
    nvgStrokeWidth(nvg, TRACK_WIDTH)
    nvgLineCap(nvg, NVG_BUTT)
    nvgStroke(nvg)
    HexMarkDraw.FillHex(nvg, left, cy, END_HEX_RADIUS, END_COLOR, 1.0)
    HexMarkDraw.FillHex(nvg, right, cy, END_HEX_RADIUS, END_COLOR, 1.0)
    local thumbX = left + (right - left) * self.value
    HexMarkDraw.FillHex(nvg, thumbX, cy, THUMB_HEX_RADIUS, self.thumbColor, 1.0)
end

function MenuDiamondSlider:IsStateful()
    return true
end

return MenuDiamondSlider
