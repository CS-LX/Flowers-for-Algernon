-- 玩法关卡目录。
-- 只描述游戏内已配置关卡：id、标题、资源路径。
-- 当前三关都是第一章：1-1 / 1-2 / 1-3。JSON 文件名仍是 chapter-1/2/3。
-- 章节进关只读 assets/Levels，不读用户关卡编辑器存档。

---@class LevelDefinition
---@field id string
---@field index number
---@field title string
---@field subtitle string
---@field sourcePath string

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

---@type LevelDefinition[]
LevelCatalog.LEVELS = {
    {
        id = "ch1_1",
        index = 1,
        title = "1-1 门",
        subtitle = "第一章 · 跑不过的迷宫",
        sourcePath = LevelCatalog.CHAPTER_1_PATH,
    },
    {
        id = "ch1_2",
        index = 2,
        title = "1-2 白鼠先行",
        subtitle = "第一章 · 跑不过的迷宫",
        sourcePath = LevelCatalog.CHAPTER_2_PATH,
    },
    {
        id = "ch1_3",
        index = 3,
        title = "1-3 另一种世界",
        subtitle = "第一章 · 跑不过的迷宫",
        sourcePath = LevelCatalog.CHAPTER_3_PATH,
    },
}

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

function LevelCatalog.GetNext(id)
    local current = LevelCatalog.GetById(id)
    if not current then
        return nil
    end
    for _, definition in ipairs(LevelCatalog.LEVELS) do
        if definition.index == current.index + 1 then
            return definition
        end
    end
    return nil
end

return LevelCatalog
