-- 玩法关卡目录。
-- 滚筒按 5 章 18 关排布 3-4-4-4-3。真正有 JSON 的只有 1-1/1-2/1-3，其余占位。

---@class LevelDefinition
---@field id string
---@field index number
---@field chapter number
---@field code string
---@field title string
---@field subtitle string
---@field sourcePath string
---@field placeholder boolean|nil

local LevelCatalog = {}

-- 玩法只读资源根下的关卡 JSON。docs/level.txt 是编辑器导出通道，不进 ResourceCache。
---@type string
LevelCatalog.WHITEBOX_PATH = "Levels/whitebox-level.json"
---@type string
LevelCatalog.CHAPTER_1_PATH = "Levels/chapter-1.json"
---@type string
LevelCatalog.CHAPTER_2_PATH = "Levels/chapter-2.json"
---@type string
LevelCatalog.CHAPTER_3_PATH = "Levels/chapter-3.json"

local CHAPTER_TITLES = {
    "跑不过的迷宫",
    "打开的世界",
    "高处没有朋友",
    "道路正在消失",
    "给阿尔吉侬的花",
}

local CHAPTER_LABELS = {
    "一",
    "二",
    "三",
    "四",
    "五",
}

local CHAPTER_STAGE_COUNTS = { 3, 4, 4, 4, 3 }

local CHAPTER_STAGE_NAMES = {
    { "门", "白鼠先行", "另一种世界" },
    { "研究室", "远处的房间", "两座塔之间", "高处的窗" },
    { "玻璃之间", "旁观席", "阿尔吉侬的记录", "最后的报告" },
    { "失效的迷宫", "反向的塔", "回到低处", "空房间" },
    { "真正的路", "花园", "余光" },
}

local PLAYABLE_PATHS = {
    ["1-1"] = LevelCatalog.CHAPTER_1_PATH,
    ["1-2"] = LevelCatalog.CHAPTER_2_PATH,
    ["1-3"] = LevelCatalog.CHAPTER_3_PATH,
}

---@type LevelDefinition[]
LevelCatalog.LEVELS = {}

local function BuildCatalog()
    local index = 1
    for chapter = 1, #CHAPTER_STAGE_COUNTS do
        local stageCount = CHAPTER_STAGE_COUNTS[chapter]
        local names = CHAPTER_STAGE_NAMES[chapter] or {}
        for stage = 1, stageCount do
            local code = string.format("%d-%d", chapter, stage)
            local path = PLAYABLE_PATHS[code]
            local stageName = names[stage] or "占位"
            LevelCatalog.LEVELS[index] = {
                id = string.format("ch%d_%d", chapter, stage),
                index = index,
                chapter = chapter,
                code = code,
                title = string.format("%s %s", code, stageName),
                subtitle = string.format("第%s章 · %s", CHAPTER_LABELS[chapter], CHAPTER_TITLES[chapter]),
                sourcePath = path or "",
                placeholder = path == nil,
            }
            index = index + 1
        end
    end
end

BuildCatalog()

local function Repeat(t, length)
    if length <= 0 then
        return 0
    end
    return ((t % length) + length) % length
end

function LevelCatalog.GetAll()
    return LevelCatalog.LEVELS
end

function LevelCatalog.GetById(id)
    for _, definition in ipairs(LevelCatalog.LEVELS) do
        if definition.id == id then
            return definition
        end
    end
    return nil
end

function LevelCatalog.GetByIndex(index)
    if type(index) ~= "number" then
        return nil
    end
    local count = #LevelCatalog.LEVELS
    if count <= 0 then
        return nil
    end
    return LevelCatalog.LEVELS[Repeat(index - 1, count) + 1]
end

function LevelCatalog.GetChapter(definition)
    if not definition then
        return 0
    end
    return math.max(1, math.floor((tonumber(definition.chapter) or 1) + 0.5))
end

-- 循环三格窗口。centerIndex 为 1-based 正面关卡号。
-- 初始 center=1 → [5-3][1-1][1-2]
function LevelCatalog.GetWindow(centerIndex)
    local left = LevelCatalog.GetByIndex(centerIndex - 1)
    local center = LevelCatalog.GetByIndex(centerIndex)
    local right = LevelCatalog.GetByIndex(centerIndex + 1)
    return { left, center, right }
end

function LevelCatalog.GetNext(id)
    local current = LevelCatalog.GetById(id)
    if not current then
        return nil
    end
    for _, definition in ipairs(LevelCatalog.LEVELS) do
        if definition.index > current.index and not definition.placeholder and definition.sourcePath ~= "" then
            return definition
        end
    end
    return nil
end

return LevelCatalog
