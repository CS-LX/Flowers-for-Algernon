-- 剧情点击提示：尖端朝下的六边形环，文本打完后内下角再画一个跃动三角。
-- 环和水波走 HexMarkDraw，与关卡退出按钮同一套描边。

local Widget = require("urhox-libs/UI/Core/Widget")
local HexMarkDraw = require "HexMarkDraw"

---@class StoryHexPrompt : Widget
---@overload fun(props?: table): StoryHexPrompt
local StoryHexPrompt = Widget:Extend("StoryHexPrompt")

local RING_RADIUS = 18.0
local FADE_IN = 0.18
local FADE_OUT = 0.16
local TRIANGLE_FADE = 0.18
local BOUNCE_SPEED = 2.6
local BOUNCE_PIXELS = 3.5
local COLOR = { 236, 230, 218, 255 }

local function DrawTriangle(nvg, cx, cy, radius, alpha)
    if alpha <= 0.0 then
        return
    end
    local bottomX, bottomY = HexMarkDraw.HexPoint(cx, cy, radius, 1)
    local leftX, leftY = HexMarkDraw.HexPoint(cx, cy, radius, 6)
    local rightX, rightY = HexMarkDraw.HexPoint(cx, cy, radius, 2)
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
    nvgFillColor(nvg, nvgRGBA(COLOR[1], COLOR[2], COLOR[3], math.floor(255 * HexMarkDraw.Clamp01(alpha) + 0.5)))
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
        if self.waveElapsed >= HexMarkDraw.WAVE_DURATION then
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
        HexMarkDraw.StrokeHex(nvg, cx, cy, RING_RADIUS, HexMarkDraw.RING_WIDTH, self.ringAlpha, COLOR)
    end
    if self.triangleAlpha > 0.001 then
        local bounce = math.abs(math.sin(self.bounceTime * BOUNCE_SPEED)) * BOUNCE_PIXELS
        DrawTriangle(nvg, cx, cy + bounce, RING_RADIUS, self.triangleAlpha)
    end
    HexMarkDraw.StrokeWave(nvg, cx, cy, RING_RADIUS, self.waveElapsed, COLOR)
end

function StoryHexPrompt:IsStateful()
    return true
end

return StoryHexPrompt
