-- 关卡内剧情跳过：白色六边形框 + 尖角向右的三角。
-- 环半径、水波、淡入淡出对齐 LevelExitButton。

local Widget = require("urhox-libs/UI/Core/Widget")
local HexMarkDraw = require "HexMarkDraw"
local Sfx = require "Sfx"

---@class StorySkipButton : Widget
---@overload fun(props?: table): StorySkipButton
local StorySkipButton = Widget:Extend("StorySkipButton")

local DEFAULT_SIZE = 88.0
local RING_RATIO = 0.32
local COLOR = HexMarkDraw.COLOR
local FADE_DURATION = 0.2

local function RingRadius(layout)
    local size = math.min(layout.w, layout.h)
    return size * RING_RATIO
end

local function DrawSkipTriangle(nvg, cx, cy, radius, alpha)
    if alpha <= 0.0 then
        return
    end
    local color = nvgRGBA(COLOR[1], COLOR[2], COLOR[3], math.floor(255 * HexMarkDraw.Clamp01(alpha) + 0.5))
    local left = cx - radius * 0.20
    local right = cx + radius * 0.34
    local span = radius * 0.30
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, left, cy - span)
    nvgLineTo(nvg, right, cy)
    nvgLineTo(nvg, left, cy + span)
    nvgClosePath(nvg)
    nvgFillColor(nvg, color)
    nvgFill(nvg)
end

function StorySkipButton:Init(props)
    props = props or {}
    props.width = props.width or DEFAULT_SIZE
    props.height = props.height or DEFAULT_SIZE
    props.pointerEvents = props.pointerEvents or "auto"
    rawset(self, "iconAlpha", 0.0)
    rawset(self, "fadeFrom", 0.0)
    rawset(self, "fadeTo", 0.0)
    rawset(self, "fadeElapsed", 0.0)
    rawset(self, "fadeDuration", 0.0)
    rawset(self, "waveElapsed", -1.0)
    rawset(self, "clickArmed", false)
    props.onClick = function(button)
        button:HandleSkipClick()
    end
    Widget.Init(self, props)
    self:SetProp("pointerEvents", "none")
end

function StorySkipButton:SetIconAlpha(alpha)
    rawset(self, "iconAlpha", HexMarkDraw.Clamp01(alpha))
    rawset(self, "fadeDuration", 0.0)
end

function StorySkipButton:FadeTo(alpha, duration)
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

function StorySkipButton:PlayWave()
    rawset(self, "waveElapsed", 0.0)
end

function StorySkipButton:SetClickArmed(armed)
    rawset(self, "clickArmed", armed == true)
    self:SetProp("pointerEvents", self.clickArmed and "auto" or "none")
end

function StorySkipButton:HandleSkipClick()
    if not self.clickArmed then
        return
    end
    if self.iconAlpha <= 0.05 then
        return
    end
    self:PlayWave()
    Sfx.PlayModalClick()
    if self.props.onSkip then
        self.props.onSkip(self)
    end
end

function StorySkipButton:Update(dt)
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

function StorySkipButton:Render(nvg)
    if self.iconAlpha <= 0.001 and self.waveElapsed < 0.0 then
        return
    end

    local layout = self:GetAbsoluteLayout()
    local cx = layout.x + layout.w * 0.5
    local cy = layout.y + layout.h * 0.5
    local radius = RingRadius(layout)
    local ringWidth = math.max(HexMarkDraw.RING_WIDTH, radius * 0.12)
    if self.iconAlpha > 0.001 then
        HexMarkDraw.StrokeHex(nvg, cx, cy, radius, ringWidth, self.iconAlpha, COLOR)
        DrawSkipTriangle(nvg, cx, cy, radius, self.iconAlpha)
    end
    HexMarkDraw.StrokeWave(nvg, cx, cy, radius, self.waveElapsed, COLOR)
end

function StorySkipButton:IsStateful()
    return true
end

StorySkipButton.FADE_DURATION = FADE_DURATION

return StorySkipButton
