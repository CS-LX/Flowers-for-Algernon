-- 关卡内退出按钮：白色六边形框 + 左箭头。
-- 环和水波走 HexMarkDraw，与对话 Mark 同一套描边。点击走 Esc 语义。

local Widget = require("urhox-libs/UI/Core/Widget")
local HexMarkDraw = require "HexMarkDraw"
local Sfx = require "Sfx"

---@class LevelExitButton : Widget
---@overload fun(props?: table): LevelExitButton
local LevelExitButton = Widget:Extend("LevelExitButton")

local RING_RADIUS = 18.0
local COLOR = HexMarkDraw.COLOR
local FADE_DURATION = 1.0

local function DrawArrow(nvg, cx, cy, radius, alpha)
    if alpha <= 0.0 then
        return
    end
    local color = nvgRGBA(COLOR[1], COLOR[2], COLOR[3], math.floor(255 * HexMarkDraw.Clamp01(alpha) + 0.5))
    local shaftY = cy
    local headX = cx - radius * 0.42
    local tailX = cx + radius * 0.38
    local headSpan = radius * 0.28
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, tailX, shaftY)
    nvgLineTo(nvg, headX + radius * 0.08, shaftY)
    nvgStrokeColor(nvg, color)
    nvgStrokeWidth(nvg, 3.0)
    nvgLineCap(nvg, NVG_BUTT)
    nvgStroke(nvg)
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, headX + headSpan, shaftY - headSpan)
    nvgLineTo(nvg, headX, shaftY)
    nvgLineTo(nvg, headX + headSpan, shaftY + headSpan)
    nvgStrokeColor(nvg, color)
    nvgStrokeWidth(nvg, 3.0)
    nvgLineCap(nvg, NVG_BUTT)
    nvgLineJoin(nvg, NVG_MITER)
    nvgStroke(nvg)
end

function LevelExitButton:Init(props)
    props = props or {}
    props.width = props.width or 56
    props.height = props.height or 56
    props.pointerEvents = props.pointerEvents or "auto"
    -- Widget __newindex 会把 self.iconAlpha 路由到 SetIconAlpha，必须先 rawset。
    rawset(self, "iconAlpha", 0.0)
    rawset(self, "fadeFrom", 0.0)
    rawset(self, "fadeTo", 0.0)
    rawset(self, "fadeElapsed", 0.0)
    rawset(self, "fadeDuration", 0.0)
    rawset(self, "waveElapsed", -1.0)
    rawset(self, "clickArmed", true)
    props.onClick = function(button)
        button:HandleExitClick()
    end
    Widget.Init(self, props)
end

function LevelExitButton:SetIconAlpha(alpha)
    rawset(self, "iconAlpha", HexMarkDraw.Clamp01(alpha))
    rawset(self, "fadeDuration", 0.0)
end

function LevelExitButton:FadeTo(alpha, duration)
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

function LevelExitButton:PlayWave()
    rawset(self, "waveElapsed", 0.0)
end

function LevelExitButton:SetClickArmed(armed)
    rawset(self, "clickArmed", armed == true)
    self:SetProp("pointerEvents", self.clickArmed and "auto" or "none")
end

function LevelExitButton:HandleExitClick()
    if not self.clickArmed then
        return
    end
    if self.iconAlpha <= 0.05 then
        return
    end
    self:PlayWave()
    Sfx.PlayModalClick()
    if self.props.onExit then
        self.props.onExit(self)
    end
end

function LevelExitButton:Update(dt)
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
    if self.waveElapsed >= 0.0 then
        local waveElapsed = self.waveElapsed + dt
        if waveElapsed >= HexMarkDraw.WAVE_DURATION then
            rawset(self, "waveElapsed", -1.0)
        else
            rawset(self, "waveElapsed", waveElapsed)
        end
    end
end

function LevelExitButton:Render(nvg)
    if self.iconAlpha <= 0.001 and self.waveElapsed < 0.0 then
        return
    end
    local layout = self:GetAbsoluteLayout()
    local cx = layout.x + layout.w * 0.5
    local cy = layout.y + layout.h * 0.5
    if self.iconAlpha > 0.001 then
        HexMarkDraw.StrokeHex(nvg, cx, cy, RING_RADIUS, HexMarkDraw.RING_WIDTH, self.iconAlpha, COLOR)
        DrawArrow(nvg, cx, cy, RING_RADIUS, self.iconAlpha)
    end
    HexMarkDraw.StrokeWave(nvg, cx, cy, RING_RADIUS, self.waveElapsed, COLOR)
end

function LevelExitButton:IsStateful()
    return true
end

LevelExitButton.FADE_DURATION = FADE_DURATION

return LevelExitButton
