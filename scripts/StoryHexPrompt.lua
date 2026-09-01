-- 剧情点击提示：尖端朝下的六边形环，文本打完后内下角再画一个跃动三角。
-- 只负责 NanoVG 绘制和点击水波，不排队台词。

local Widget = require("urhox-libs/UI/Core/Widget")

---@class StoryHexPrompt : Widget
local StoryHexPrompt = Widget:Extend("StoryHexPrompt")

local RING_RADIUS = 18.0
local RING_WIDTH = 3.2
local WAVE_DURATION = 0.45
local WAVE_SCALE = 1.7
local WAVE_WIDTH_START = 2.2
local FADE_IN = 0.18
local FADE_OUT = 0.16
local TRIANGLE_FADE = 0.18
local BOUNCE_SPEED = 2.6
local BOUNCE_PIXELS = 3.5
local COLOR = { 236, 230, 218, 255 }

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

local function EaseOutExpo(t)
    t = Clamp01(t)
    if t >= 1.0 then
        return 1.0
    end
    if t <= 0.0 then
        return 0.0
    end
    return 1.0 - 2.0 ^ (-10.0 * t)
end

local function HexPoint(cx, cy, radius, index)
    -- 尖端朝下：从正下方起算，逆时针六顶点。
    local angle = math.pi * 0.5 + (index - 1) * math.pi / 3.0
    return cx + math.cos(angle) * radius, cy + math.sin(angle) * radius
end

local function DrawHexRing(nvg, cx, cy, radius, width, alpha)
    if alpha <= 0.0 or width <= 0.05 or radius <= 0.05 then
        return
    end
    nvgBeginPath(nvg)
    local x, y = HexPoint(cx, cy, radius, 1)
    nvgMoveTo(nvg, x, y)
    for index = 2, 6 do
        x, y = HexPoint(cx, cy, radius, index)
        nvgLineTo(nvg, x, y)
    end
    nvgClosePath(nvg)
    nvgStrokeColor(nvg, nvgRGBA(COLOR[1], COLOR[2], COLOR[3], math.floor(255 * Clamp01(alpha) + 0.5)))
    nvgStrokeWidth(nvg, width)
    nvgLineJoin(nvg, NVG_MITER)
    nvgLineCap(nvg, NVG_BUTT)
    nvgStroke(nvg)
end

local function DrawTriangle(nvg, cx, cy, radius, alpha)
    if alpha <= 0.0 then
        return
    end
    local bottomX, bottomY = HexPoint(cx, cy, radius, 1)
    local leftX, leftY = HexPoint(cx, cy, radius, 6)
    local rightX, rightY = HexPoint(cx, cy, radius, 2)
    local inset = 0.58
    local topY = cy + radius * 0.08
    local p1x = cx + (bottomX - cx) * inset
    local p1y = cy + (bottomY - cy) * inset
    local p2x = cx + (leftX - cx) * (inset * 0.72)
    local p2y = topY + (leftY - cy) * 0.12
    local p3x = cx + (rightX - cx) * (inset * 0.72)
    local p3y = topY + (rightY - cy) * 0.12
    nvgBeginPath(nvg)
    nvgMoveTo(nvg, p1x, p1y)
    nvgLineTo(nvg, p2x, p2y)
    nvgLineTo(nvg, p3x, p3y)
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(COLOR[1], COLOR[2], COLOR[3], math.floor(255 * Clamp01(alpha) + 0.5)))
    nvgFill(nvg)
end

function StoryHexPrompt:Init(props)
    props = props or {}
    props.width = props.width or 56
    props.height = props.height or 56
    props.pointerEvents = props.pointerEvents or "none"
    self.ringVisible = false
    self.triangleVisible = false
    self.ringAlpha = 0.0
    self.triangleAlpha = 0.0
    self.bounceTime = 0.0
    self.waveElapsed = -1.0
    self.waveKind = nil
    Widget.Init(self, props)
end

function StoryHexPrompt:SetPrompt(ringVisible, triangleVisible)
    self.ringVisible = ringVisible == true
    self.triangleVisible = triangleVisible == true
    if not self.ringVisible then
        self.triangleVisible = false
    end
end

function StoryHexPrompt:PlayWave(kind)
    self.waveKind = kind or "reveal"
    self.waveElapsed = 0.0
    if self.waveKind == "advance" then
        self.ringVisible = false
        self.triangleVisible = false
    end
end

function StoryHexPrompt:HideImmediate()
    self.ringVisible = false
    self.triangleVisible = false
    self.ringAlpha = 0.0
    self.triangleAlpha = 0.0
    self.waveElapsed = -1.0
    self.waveKind = nil
end

function StoryHexPrompt:Update(dt)
    if self.ringVisible then
        self.ringAlpha = math.min(1.0, self.ringAlpha + dt / FADE_IN)
    else
        self.ringAlpha = math.max(0.0, self.ringAlpha - dt / FADE_OUT)
    end
    if self.triangleVisible then
        self.triangleAlpha = math.min(1.0, self.triangleAlpha + dt / TRIANGLE_FADE)
        self.bounceTime = self.bounceTime + dt
    else
        self.triangleAlpha = math.max(0.0, self.triangleAlpha - dt / TRIANGLE_FADE)
        if self.triangleAlpha <= 0.0 then
            self.bounceTime = 0.0
        end
    end
    if self.waveElapsed >= 0.0 then
        self.waveElapsed = self.waveElapsed + dt
        if self.waveElapsed >= WAVE_DURATION then
            self.waveElapsed = -1.0
            self.waveKind = nil
        end
    end
end

function StoryHexPrompt:Render(nvg)
    local layout = self:GetAbsoluteLayout()
    local cx = layout.x + layout.w * 0.5
    local cy = layout.y + layout.h * 0.5
    if self.ringAlpha > 0.001 then
        DrawHexRing(nvg, cx, cy, RING_RADIUS, RING_WIDTH, self.ringAlpha)
    end
    if self.triangleAlpha > 0.001 then
        local bounce = math.abs(math.sin(self.bounceTime * BOUNCE_SPEED)) * BOUNCE_PIXELS
        DrawTriangle(nvg, cx, cy + bounce, RING_RADIUS, self.triangleAlpha)
    end
    if self.waveElapsed >= 0.0 then
        local t = Clamp01(self.waveElapsed / WAVE_DURATION)
        local scale = 1.0 + (WAVE_SCALE - 1.0) * EaseOutExpo(t)
        local width = WAVE_WIDTH_START * (1.0 - t)
        local alpha = 1.0 - t
        DrawHexRing(nvg, cx, cy, RING_RADIUS * scale, width, alpha)
    end
end

function StoryHexPrompt:IsStateful()
    return true
end

return StoryHexPrompt
