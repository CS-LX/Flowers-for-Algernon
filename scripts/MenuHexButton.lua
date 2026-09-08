-- 选关菜单六边形开关。
-- 关：环内两条横杠；开：环内两条短斜线。水波沿用 HexMarkDraw。

local Widget = require("urhox-libs/UI/Core/Widget")
local HexMarkDraw = require "HexMarkDraw"

---@class MenuHexButton : Widget
---@field iconAlpha number
---@field openAmount number
---@field openFrom number
---@field openTo number
---@field openElapsed number
---@field openDuration number
---@field waveElapsed number
---@field clickArmed boolean
---@field opened boolean
---@field fadeFrom number
---@field fadeTo number
---@field fadeElapsed number
---@field fadeDuration number
---@overload fun(props?: table): MenuHexButton
local MenuHexButton = Widget:Extend("MenuHexButton")

local RING_RADIUS = 18.0
local COLOR = HexMarkDraw.COLOR
local FADE_DURATION = 0.2

local function StrokeColor(alpha)
    return nvgRGBA(COLOR[1], COLOR[2], COLOR[3], math.floor(255 * HexMarkDraw.Clamp01(alpha) + 0.5))
end

local function DrawMenuBars(nvg, cx, cy, radius, alpha)
    if alpha <= 0.0 then
        return
    end
    local half = radius * 0.32
    local gap = radius * 0.16
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - half, cy - gap)
    nvgLineTo(nvg, cx + half, cy - gap)
    nvgMoveTo(nvg, cx - half, cy + gap)
    nvgLineTo(nvg, cx + half, cy + gap)
    nvgStrokeColor(nvg, StrokeColor(alpha))
    nvgStrokeWidth(nvg, 3.0)
    nvgLineCap(nvg, NVG_BUTT)
    nvgStroke(nvg)
end

local function DrawCloseMark(nvg, cx, cy, radius, alpha)
    if alpha <= 0.0 then
        return
    end
    local span = radius * 0.34
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, cx - span, cy - span)
    nvgLineTo(nvg, cx + span, cy + span)
    nvgMoveTo(nvg, cx + span, cy - span)
    nvgLineTo(nvg, cx - span, cy + span)
    nvgStrokeColor(nvg, StrokeColor(alpha))
    nvgStrokeWidth(nvg, 3.0)
    nvgLineCap(nvg, NVG_BUTT)
    nvgStroke(nvg)
end

function MenuHexButton:Init(props)
    props = props or {}
    props.width = props.width or 56
    props.height = props.height or 56
    props.pointerEvents = props.pointerEvents or "auto"
    rawset(self, "iconAlpha", 1.0)
    rawset(self, "openAmount", 0.0)
    rawset(self, "openFrom", 0.0)
    rawset(self, "openTo", 0.0)
    rawset(self, "openElapsed", 0.0)
    rawset(self, "openDuration", 0.0)
    rawset(self, "waveElapsed", -1.0)
    rawset(self, "clickArmed", true)
    rawset(self, "opened", false)
    rawset(self, "fadeFrom", 1.0)
    rawset(self, "fadeTo", 1.0)
    rawset(self, "fadeElapsed", 0.0)
    rawset(self, "fadeDuration", 0.0)
    props.onClick = function(button)
        button:HandleClick()
    end
    Widget.Init(self, props)
end

function MenuHexButton:SetIconAlpha(alpha)
    rawset(self, "iconAlpha", HexMarkDraw.Clamp01(alpha))
    rawset(self, "fadeDuration", 0.0)
end

function MenuHexButton:FadeTo(alpha, duration)
    local target = HexMarkDraw.Clamp01(alpha)
    local fadeDuration = tonumber(duration) or FADE_DURATION
    if fadeDuration < 0.0 then
        fadeDuration = 0.0
    end
    if fadeDuration <= 0.0 then
        rawset(self, "iconAlpha", target)
        rawset(self, "fadeDuration", 0.0)
        return
    end
    rawset(self, "fadeFrom", self.iconAlpha)
    rawset(self, "fadeTo", target)
    rawset(self, "fadeElapsed", 0.0)
    rawset(self, "fadeDuration", fadeDuration)
end

function MenuHexButton:SetOpened(opened, instant)
    local target = opened == true
    rawset(self, "opened", target)
    local to = target and 1.0 or 0.0
    if instant then
        rawset(self, "openAmount", to)
        rawset(self, "openDuration", 0.0)
        return
    end
    rawset(self, "openFrom", self.openAmount)
    rawset(self, "openTo", to)
    rawset(self, "openElapsed", 0.0)
    rawset(self, "openDuration", FADE_DURATION)
end

function MenuHexButton:SetClickArmed(armed)
    rawset(self, "clickArmed", armed == true)
    self:SetProp("pointerEvents", self.clickArmed and "auto" or "none")
end

function MenuHexButton:PlayWave()
    rawset(self, "waveElapsed", 0.0)
end

function MenuHexButton:HandleClick()
    if not self.clickArmed then
        return
    end
    if self.iconAlpha <= 0.05 then
        return
    end
    self:PlayWave()
    if self.props.onToggle then
        self.props.onToggle(self, not self.opened)
    end
end

function MenuHexButton:Update(dt)
    if self.fadeDuration > 0.0 then
        local elapsed = self.fadeElapsed + dt
        rawset(self, "fadeElapsed", elapsed)
        local t = HexMarkDraw.Clamp01(elapsed / self.fadeDuration)
        rawset(self, "iconAlpha", self.fadeFrom + (self.fadeTo - self.fadeFrom) * t)
        if t >= 1.0 then
            rawset(self, "iconAlpha", self.fadeTo)
            rawset(self, "fadeDuration", 0.0)
        end
    end
    if self.openDuration > 0.0 then
        local elapsed = self.openElapsed + dt
        rawset(self, "openElapsed", elapsed)
        local t = HexMarkDraw.Clamp01(elapsed / self.openDuration)
        rawset(self, "openAmount", self.openFrom + (self.openTo - self.openFrom) * t)
        if t >= 1.0 then
            rawset(self, "openAmount", self.openTo)
            rawset(self, "openDuration", 0.0)
        end
    end
    if self.waveElapsed >= 0.0 then
        local waveElapsed = self.waveElapsed + dt
        if waveElapsed >= HexMarkDraw.WAVE_DURATION then
            rawset(self, "waveElapsed", -1.0)
        else
            rawset(self, "waveElapsed", waveElapsed)
        end
    end
end

function MenuHexButton:Render(nvg)
    local layout = self:GetAbsoluteLayout()
    local cx = layout.x + layout.w * 0.5
    local cy = layout.y + layout.h * 0.5
    HexMarkDraw.StrokeHex(nvg, cx, cy, RING_RADIUS, HexMarkDraw.RING_WIDTH, self.iconAlpha, COLOR)
    DrawMenuBars(nvg, cx, cy, RING_RADIUS, self.iconAlpha * (1.0 - self.openAmount))
    DrawCloseMark(nvg, cx, cy, RING_RADIUS, self.iconAlpha * self.openAmount)
    HexMarkDraw.StrokeWave(nvg, cx, cy, RING_RADIUS, self.waveElapsed, COLOR)
end

function MenuHexButton:IsStateful()
    return true
end

return MenuHexButton
