-- 选关雾色 → 菜单悬停色。
-- 拉饱和并抬亮度，保证压在深色遮罩上仍可读。
-- 纯黑雾（第五章）没有色相，退回暖沙色。

local MenuHoverTint = {}

local FALLBACK = { 214, 196, 168, 255 }
local WHITE = { 255, 255, 255, 255 }

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

local function Channel255(value)
    return math.floor(Clamp01(value) * 255.0 + 0.5)
end

local function HueToRgb(p, q, t)
    if t < 0.0 then
        t = t + 1.0
    end
    if t > 1.0 then
        t = t - 1.0
    end
    if t < 1.0 / 6.0 then
        return p + (q - p) * 6.0 * t
    end
    if t < 0.5 then
        return q
    end
    if t < 2.0 / 3.0 then
        return p + (q - p) * (2.0 / 3.0 - t) * 6.0
    end
    return p
end

function MenuHoverTint.White()
    return { WHITE[1], WHITE[2], WHITE[3], WHITE[4] }
end

---@param color Color|nil
---@return number[]
function MenuHoverTint.FromFog(color)
    if not color then
        return { FALLBACK[1], FALLBACK[2], FALLBACK[3], FALLBACK[4] }
    end
    local r = Clamp01(color.r)
    local g = Clamp01(color.g)
    local b = Clamp01(color.b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    if max <= 0.08 then
        return { FALLBACK[1], FALLBACK[2], FALLBACK[3], FALLBACK[4] }
    end
    local lightness = (max + min) * 0.5
    local delta = max - min
    local saturation = 0.0
    if delta > 0.0001 then
        saturation = delta / (1.0 - math.abs(2.0 * lightness - 1.0))
    end
    local hue = 0.0
    if delta > 0.0001 then
        if max == r then
            hue = ((g - b) / delta) % 6.0
        elseif max == g then
            hue = (b - r) / delta + 2.0
        else
            hue = (r - g) / delta + 4.0
        end
        hue = hue / 6.0
        if hue < 0.0 then
            hue = hue + 1.0
        end
    end
    saturation = Clamp01(saturation * 1.55 + 0.10)
    if lightness < 0.42 then
        lightness = 0.42 + lightness * 0.35
    elseif lightness > 0.78 then
        lightness = 0.78
    end
    local q
    if lightness < 0.5 then
        q = lightness * (1.0 + saturation)
    else
        q = lightness + saturation - lightness * saturation
    end
    local p = 2.0 * lightness - q
    return {
        Channel255(HueToRgb(p, q, hue + 1.0 / 3.0)),
        Channel255(HueToRgb(p, q, hue)),
        Channel255(HueToRgb(p, q, hue - 1.0 / 3.0)),
        255,
    }
end

return MenuHoverTint
