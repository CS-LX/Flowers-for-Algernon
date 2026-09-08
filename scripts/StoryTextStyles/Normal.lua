-- 实验室/旁白：冷静白字，字号一致。

local Normal = {}

local BASE_SIZE = 32
local COLOR = { 255, 255, 255, 255 }
local SHADOW = {
    offsetX = 0,
    offsetY = 1,
    blur = 10,
    color = { 18, 14, 10, 150 },
}

local function EachChar(text, callback)
    if type(text) ~= "string" or text == "" then
        return
    end
    for _, code in utf8.codes(text) do
        callback(utf8.char(code))
    end
end

function Normal.Layout(text, options)
    options = options or {}
    local glyphs = {}
    EachChar(text, function(ch)
        glyphs[#glyphs + 1] = {
            text = ch,
            fontSize = BASE_SIZE,
            fontColor = COLOR,
            rotate = 0,
            textShadow = SHADOW,
        }
    end)
    return {
        style = "normal",
        align = "center",
        wrap = true,
        baseSize = BASE_SIZE,
        color = COLOR,
        textShadow = SHADOW,
        glyphs = glyphs,
        rawText = text,
        seed = options.seed,
    }
end

return Normal
