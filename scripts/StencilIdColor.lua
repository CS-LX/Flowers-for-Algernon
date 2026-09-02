-- 把整数 stencil id 编成可逆的 24 位 RGB。
-- 相邻 id 在颜色空间里拉开，避免滚筒邻面看起来像同一章。

local StencilIdColor = {}

-- 24 位奇数乘数，模 2^24 可逆。黄金比相关常数截断到 24 位。
local RGB_MASK = 0xFFFFFF
local MIX_MULT = 0x9E3779
local MIX_INV = 0xB382C9
local MIX_XOR = 0xA5A5A5

local function ToInt(value)
    return math.floor((tonumber(value) or 0) + 0.5)
end

local function Wrap24(value)
    local modulus = RGB_MASK + 1
    return ((ToInt(value) % modulus) + modulus) % modulus
end

local function Mul24(a, b)
    local aLow = a & 0xFFF
    local aHigh = a >> 12
    local bLow = b & 0xFFF
    local bHigh = b >> 12
    local mixed = (aLow * bLow) & RGB_MASK
    mixed = (mixed + ((aLow * bHigh + aHigh * bLow) << 12)) & RGB_MASK
    return mixed
end

local function Encode24(id)
    local packed = Wrap24(id)
    packed = Mul24(packed, MIX_MULT) ~ MIX_XOR
    return packed
end

local function Decode24(packed)
    packed = Wrap24(packed) ~ MIX_XOR
    return Mul24(packed, MIX_INV)
end

local function Byte(value)
    if value < 0 then
        value = 0
    elseif value > 255 then
        value = 255
    end
    return value
end

function StencilIdColor.ToPacked(id)
    return Encode24(id)
end

function StencilIdColor.FromPacked(packed)
    return Decode24(packed)
end

function StencilIdColor.ToColor(id)
    local packed = Encode24(id)
    local r = (packed >> 16) & 255
    local g = (packed >> 8) & 255
    local b = packed & 255
    return Color(r / 255.0, g / 255.0, b / 255.0, 1.0)
end

function StencilIdColor.FromColor(color)
    if not color then
        return 0
    end
    local r = Byte(math.floor((tonumber(color.r) or 0) * 255.0 + 0.5))
    local g = Byte(math.floor((tonumber(color.g) or 0) * 255.0 + 0.5))
    local b = Byte(math.floor((tonumber(color.b) or 0) * 255.0 + 0.5))
    local packed = (r << 16) | (g << 8) | b
    return Decode24(packed)
end

return StencilIdColor
