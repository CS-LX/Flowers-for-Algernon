-- 叙事字幕样式入口。
-- 导演只传原始文字和样式名；这里产出带样式的 glyph，View 负责拼到字幕盒上。

local Normal = require "StoryTextStyles.Normal"
local Charlie = require "StoryTextStyles.Charlie"
local Researcher = require "StoryTextStyles.Researcher"

local StoryTextStyle = {}

StoryTextStyle.NORMAL = "normal"
StoryTextStyle.CHARLIE = "charlie"
StoryTextStyle.RESEARCHER = "researcher"

local STYLES = {
    [StoryTextStyle.NORMAL] = Normal,
    [StoryTextStyle.CHARLIE] = Charlie,
    [StoryTextStyle.RESEARCHER] = Researcher,
}

function StoryTextStyle.ResolveName(name)
    if name == StoryTextStyle.CHARLIE then
        return StoryTextStyle.CHARLIE
    end
    if name == StoryTextStyle.RESEARCHER then
        return StoryTextStyle.RESEARCHER
    end
    return StoryTextStyle.NORMAL
end

---@param text string
---@param styleName string|nil
---@param options table|nil
---@return table
function StoryTextStyle.Layout(text, styleName, options)
    local name = StoryTextStyle.ResolveName(styleName)
    local style = STYLES[name] or Normal
    return style.Layout(text or "", options)
end

return StoryTextStyle
