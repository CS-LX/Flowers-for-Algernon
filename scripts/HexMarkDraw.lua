-- 关卡 HUD 六边形描边：对话 Mark 和退出按钮共用同一套路径/描边。
-- 尖端朝下，只负责 NanoVG 画环和水波，不处理点击或布局。

local HexMarkDraw = {}

HexMarkDraw.COLOR = { 255, 255, 255, 255 }
HexMarkDraw.RING_WIDTH = 3.2
HexMarkDraw.WAVE_DURATION = 0.45
HexMarkDraw.WAVE_SCALE = 1.7
HexMarkDraw.WAVE_WIDTH_START = 2.2

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

function HexMarkDraw.Clamp01(value)
    return Clamp01(value)
end

function HexMarkDraw.EaseOutExpo(t)
    t = Clamp01(t)
    if t >= 1.0 then
        return 1.0
    end
    if t <= 0.0 then
        return 0.0
    end
    return 1.0 - 2.0 ^ (-10.0 * t)
end

function HexMarkDraw.HexPoint(cx, cy, radius, index)
    -- 尖端朝下：从正下方起算，逆时针六顶点。
    local angle = math.pi * 0.5 + (index - 1) * math.pi / 3.0
    return cx + math.cos(angle) * radius, cy + math.sin(angle) * radius
end

function HexMarkDraw.FillHex(nvg, cx, cy, radius, color, alpha)
    if radius <= 0.05 then
        return
    end
    color = color or HexMarkDraw.COLOR
    local alpha255 = color[4]
    if alpha255 == nil then
        alpha255 = 255
    end
    nvgBeginPath(nvg)
    local x, y = HexMarkDraw.HexPoint(cx, cy, radius, 1)
    nvgMoveTo(nvg, x, y)
    for index = 2, 6 do
        x, y = HexMarkDraw.HexPoint(cx, cy, radius, index)
        nvgLineTo(nvg, x, y)
    end
    nvgClosePath(nvg)
    nvgFillColor(nvg, nvgRGBA(
        color[1],
        color[2],
        color[3],
        math.floor(alpha255 * Clamp01(alpha or 1.0) + 0.5)
    ))
    nvgFill(nvg)
end

function HexMarkDraw.StrokeHex(nvg, cx, cy, radius, width, alpha, color)
    if alpha <= 0.0 or width <= 0.05 or radius <= 0.05 then
        return
    end
    color = color or HexMarkDraw.COLOR
    nvgBeginPath(nvg)
    local x, y = HexMarkDraw.HexPoint(cx, cy, radius, 1)
    nvgMoveTo(nvg, x, y)
    for index = 2, 6 do
        x, y = HexMarkDraw.HexPoint(cx, cy, radius, index)
        nvgLineTo(nvg, x, y)
    end
    nvgClosePath(nvg)
    local alpha255 = color[4]
    if alpha255 == nil then
        alpha255 = 255
    end
    nvgStrokeColor(nvg, nvgRGBA(
        color[1],
        color[2],
        color[3],
        math.floor(alpha255 * Clamp01(alpha) + 0.5)
    ))
    nvgStrokeWidth(nvg, width)
    nvgLineJoin(nvg, NVG_MITER)
    nvgLineCap(nvg, NVG_BUTT)
    nvgStroke(nvg)
end

function HexMarkDraw.StrokeWave(nvg, cx, cy, radius, elapsed, color)
    if elapsed < 0.0 then
        return
    end
    local t = Clamp01(elapsed / HexMarkDraw.WAVE_DURATION)
    local scale = 1.0 + (HexMarkDraw.WAVE_SCALE - 1.0) * HexMarkDraw.EaseOutExpo(t)
    local width = HexMarkDraw.WAVE_WIDTH_START * (1.0 - t)
    HexMarkDraw.StrokeHex(nvg, cx, cy, radius * scale, width, 1.0 - t, color)
end

return HexMarkDraw
