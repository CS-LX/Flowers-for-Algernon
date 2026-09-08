-- 查理：字号在正常值附近抖动，小概率轻微左右倾斜。
-- 错别字后续再接；这一版只做形态。

local Charlie = {}

local BASE_SIZE = 32
local COLOR = { 255, 255, 255, 255 }
local SHADOW = {
    offsetX = 0,
    offsetY = 1,
    blur = 10,
    color = { 18, 14, 10, 150 },
}
local ITALIC_CHANCE = 0.12
local ITALIC_ROTATE = 10

local function HashSeed(text, extra)
    local seed = 2166136261
    local source = tostring(text or "") .. "|" .. tostring(extra or "")
    for i = 1, #source do
        seed = (seed ~ string.byte(source, i)) * 16777619
        seed = seed % 2147483647
    end
    if seed <= 0 then
        seed = 1
    end
    return seed
end

local function EachChar(text, callback)
    if type(text) ~= "string" or text == "" then
        return
    end
    for _, code in utf8.codes(text) do
        callback(utf8.char(code))
    end
end

function Charlie.Layout(text, options)
    options = options or {}
    local seed = tonumber(options.seed) or HashSeed(text, options.id)
    math.randomseed(seed)
    local glyphs = {}
    EachChar(text, function(ch)
        local sizeJitter = math.random(-4, 4)
        local rotate = 0
        if math.random() < ITALIC_CHANCE then
            if math.random() < 0.5 then
                rotate = -ITALIC_ROTATE
            else
                rotate = ITALIC_ROTATE
            end
        end
        glyphs[#glyphs + 1] = {
            text = ch,
            fontSize = BASE_SIZE + sizeJitter,
            fontColor = COLOR,
            rotate = rotate,
            textShadow = SHADOW,
        }
    end)
    return {
        style = "charlie",
        align = "center",
        wrap = true,
        baseSize = BASE_SIZE,
        color = COLOR,
        textShadow = SHADOW,
        glyphs = glyphs,
        rawText = text,
        seed = seed,
    }
end

return Charlie
