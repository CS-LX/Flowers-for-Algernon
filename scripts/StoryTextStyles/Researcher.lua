-- 研究员：冷静白字，字号一致，加粗。

local Researcher = {}

local BASE_SIZE = 18
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

function Researcher.Layout(text, options)
    options = options or {}
    local glyphs = {}
    EachChar(text, function(ch)
        glyphs[#glyphs + 1] = {
            text = ch,
            fontSize = BASE_SIZE,
            fontColor = COLOR,
            rotate = 0,
            fontWeight = "bold",
            textShadow = SHADOW,
        }
    end)
    return {
        style = "researcher",
        align = "center",
        wrap = true,
        baseSize = BASE_SIZE,
        color = COLOR,
        fontWeight = "bold",
        textShadow = SHADOW,
        glyphs = glyphs,
        rawText = text,
        seed = options.seed,
    }
end

return Researcher
